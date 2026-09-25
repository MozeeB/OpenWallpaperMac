import Foundation
import Observation
import OWCore
import OWDesktop
import OWLibrary

public struct AppMessage: Identifiable, Equatable, Sendable {
    public enum Level: Sendable { case info, warning, error }

    public let id = UUID()
    public let level: Level
    public let text: String

    public init(level: Level, text: String) {
        self.level = level
        self.text = text
    }
}

/// UI-facing state and commands. All mutations produce a new `PersistedState` via `commit`.
@Observable
@MainActor
public final class AppModel {
    public private(set) var state: PersistedState = .empty
    public private(set) var thumbnails: [WallpaperID: URL] = [:]
    public private(set) var messages: [AppMessage] = []
    public private(set) var isPaused = false
    public private(set) var isImporting = false
    public private(set) var displays: [ScreenDescriptor] = []

    @ObservationIgnored let store: StateStore
    @ObservationIgnored let importer: ImportService
    @ObservationIgnored let thumbnailService: ThumbnailService
    @ObservationIgnored let coordinator: PlaybackCoordinator
    @ObservationIgnored let steam: SteamLibraryLocator
    @ObservationIgnored let loginItem: any LoginItemControlling
    /// Tail of the save chain: each save awaits the previous one, so disk order matches commit order.
    @ObservationIgnored private var lastSave: Task<Void, Never>?

    public init(
        store: StateStore, importer: ImportService, thumbnails: ThumbnailService, coordinator: PlaybackCoordinator,
        steam: SteamLibraryLocator, loginItem: any LoginItemControlling
    ) {
        self.store = store
        self.importer = importer
        thumbnailService = thumbnails
        self.coordinator = coordinator
        self.steam = steam
        self.loginItem = loginItem
    }

    public var library: [Wallpaper] { state.library }
    public var settings: AppSettings { state.settings }

    public func bootstrap() async {
        do {
            state = try await store.load()
        } catch {
            post(.error, "Could not read saved state (\(error)). Starting fresh.")
        }
        coordinator.onEvent = { [weak self] event in self?.handle(event) }
        coordinator.start()
        refreshDisplays()
        coordinator.update(library: state.library, assignments: state.assignments, settings: state.settings)
        await loadThumbnails(for: state.library)
    }

    public func shutdown() {
        coordinator.stop(restoreOriginalWallpaper: true)
    }

    public func refreshDisplays() {
        displays = coordinator.connectedDisplays
    }

    // MARK: Library

    public func importItems(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        var library = state.library
        var imported: [Wallpaper] = []
        for url in urls {
            do {
                let wallpaper = try importer.importItem(at: url)
                library = LibraryIndex.adding(wallpaper, to: library)
                imported.append(wallpaper)
            } catch {
                post(.error, "Could not import \(url.lastPathComponent): \(ImportErrorText.describe(error))")
            }
        }
        commit(state.with(library: library))
        if !imported.isEmpty { post(.info, "Imported \(imported.count) wallpaper\(imported.count == 1 ? "" : "s").") }
        await loadThumbnails(for: imported)
    }

    /// Imports every Wallpaper Engine project found in local Steam libraries.
    public func scanSteamLibrary() async {
        let folders = steam.projectFolders()
        guard !folders.isEmpty else {
            post(.warning, "No Wallpaper Engine projects found in your Steam libraries.")
            return
        }
        await importItems(folders)
    }

    public func remove(_ id: WallpaperID) {
        guard let wallpaper = state.library.first(where: { $0.id == id }) else { return }
        let library = LibraryIndex.removing(id, from: state.library)
        importer.removeOwnedFiles(of: wallpaper)
        Task { await thumbnailService.invalidate(id) }
        thumbnails.removeValue(forKey: id)
        commit(state.with(assignments: LibraryIndex.pruning(state.assignments, library: library), library: library))
    }

    // MARK: Assignment & properties

    /// Assigns to one display, or to every connected display when `display` is nil.
    public func assign(_ id: WallpaperID, to display: DisplayKey?) {
        let targets = display.map { [$0] } ?? displays.map(\.key)
        let assignments = targets.reduce(state.assignments) { LibraryIndex.assigning(id, to: $1, in: $0) }
        commit(state.with(assignments: assignments))
    }

    /// Rotates `wallpapers` on one display, or on every connected display when `display` is nil.
    public func setRotation(_ wallpapers: [WallpaperID], interval: TimeInterval, shuffle: Bool, display: DisplayKey?) {
        let targets = display.map { [$0] } ?? displays.map(\.key)
        let assignments = targets.reduce(state.assignments) { result, key in
            LibraryIndex.rotating(wallpapers, interval: interval, shuffle: shuffle, on: key, in: result)
        }
        commit(state.with(assignments: assignments))
    }

    /// Appends a wallpaper to a display's rotation, starting one from its current wallpaper if needed.
    public func addToRotation(_ id: WallpaperID, display: DisplayKey) {
        guard let current = assignment(for: display) else {
            assign(id, to: display)
            return
        }
        let items = current.wallpapers.contains(id) ? current.wallpapers : current.wallpapers + [id]
        setRotation(items, interval: current.rotation?.interval ?? Rotation.presetIntervals[0],
                    shuffle: current.rotation?.shuffle ?? false, display: display)
    }

    /// Stops rotating on a display and keeps the wallpaper that is currently showing.
    public func stopRotation(on display: DisplayKey) {
        guard let assignment = assignment(for: display), assignment.rotation != nil else { return }
        let showing = coordinator.activeWallpaper(for: display).flatMap { id in
            assignment.wallpapers.contains(id) ? id : nil
        } ?? assignment.wallpaper
        let single = DisplayAssignment(
            display: display, wallpaper: showing, overrides: assignment.overrides, fill: assignment.fill
        )
        commit(state.with(assignments: state.assignments.map { $0.display == display ? single : $0 }))
    }

    /// Jumps to the next wallpaper of a display's rotation.
    public func nextWallpaper(on display: DisplayKey) {
        coordinator.skipToNext(on: display)
        refreshDisplays()
    }

    /// 1-based position within a display's rotation, if it has one.
    public func rotationPosition(for display: DisplayKey) -> (current: Int, count: Int)? {
        coordinator.rotationPosition(for: display)
    }

    public func clearAssignment(for display: DisplayKey) {
        commit(state.with(assignments: state.assignments.filter { $0.display != display }))
    }

    public func assignment(for display: DisplayKey) -> DisplayAssignment? {
        state.assignments.first { $0.display == display }
    }

    public func setOverride(_ value: PropertyValue, key: String, display: DisplayKey) {
        updateAssignment(display) { $0.with(overrides: $0.overrides.merging([key: value]) { _, new in new }) }
    }

    public func resetOverrides(display: DisplayKey) {
        updateAssignment(display) { $0.with(overrides: [:]) }
    }

    public func setFill(_ fill: FillMode, display: DisplayKey) {
        updateAssignment(display) { $0.with(fill: fill) }
    }

    private func updateAssignment(_ display: DisplayKey, _ transform: (DisplayAssignment) -> DisplayAssignment) {
        let assignments = state.assignments.map { $0.display == display ? transform($0) : $0 }
        commit(state.with(assignments: assignments))
    }

    // MARK: Settings & playback

    public func updateSettings(_ settings: AppSettings) {
        if settings.launchAtLogin != state.settings.launchAtLogin {
            do {
                try loginItem.setEnabled(settings.launchAtLogin)
            } catch {
                post(.error, "Could not change launch at login: \(error.localizedDescription)")
                commit(state.with(settings: settings.with(launchAtLogin: loginItem.isEnabled)))
                return
            }
        }
        commit(state.with(settings: settings))
    }

    public func togglePause() {
        isPaused.toggle()
        coordinator.setUserPaused(isPaused)
    }

    public func dismiss(_ message: AppMessage) {
        messages.removeAll { $0.id == message.id }
    }

    public func activeWallpaper(for display: DisplayKey) -> Wallpaper? {
        assignment(for: display).flatMap { assignment in state.library.first { $0.id == assignment.wallpaper } }
    }

    // MARK: Internals

    func commit(_ newState: PersistedState) {
        guard newState != state else { return }
        state = newState
        coordinator.update(library: newState.library, assignments: newState.assignments, settings: newState.settings)
        let store = self.store
        let previous = lastSave
        lastSave = Task { [weak self] in
            await previous?.value
            do {
                try await store.save(newState)
            } catch {
                self?.post(.error, "Could not save settings: \(error)")
            }
        }
    }

    /// Waits for every pending save (call before quitting).
    public func flush() async {
        await lastSave?.value
    }

    func post(_ level: AppMessage.Level, _ text: String) {
        messages = Array((messages + [AppMessage(level: level, text: text)]).suffix(5))
    }

    private func handle(_ event: CoordinatorEvent) {
        switch event {
        case let .failed(_, id, error):
            let title = state.library.first { $0.id == id }?.title ?? "Wallpaper"
            post(.warning, "\(title) could not be rendered (\(RenderErrorText.describe(error))). Showing its preview if available.")
        case .audioSilent:
            post(.warning, """
            No system audio detected. If visuals should react to sound, allow OpenWallpaperMac under \
            System Settings > Privacy & Security > Screen & System Audio Recording.
            """)
        case .audioUnavailable(let reason):
            post(.warning, "Audio capture unavailable: \(reason)")
        case .loaded, .fellBackToPreview:
            refreshDisplays()
        }
    }

    private func loadThumbnails(for wallpapers: [Wallpaper]) async {
        for wallpaper in wallpapers {
            if let url = await thumbnailService.thumbnail(for: wallpaper) { thumbnails[wallpaper.id] = url }
        }
    }
}
