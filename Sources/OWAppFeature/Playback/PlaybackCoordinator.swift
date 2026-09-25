import AppKit
import OWAudioCapture
import OWCore
import OWDesktop
import OWFormats
import OWLibrary
import OWPower
import OWRendering

/// Reconciles library + assignments + settings + power state into running renderers.
///
/// Owns one `RenderSession` per display. Every input change funnels through `reconcile()`, which
/// is idempotent: it tears down sessions whose wallpaper changed, starts missing ones, pushes
/// property changes, and applies the power policy's playback decision to each session.
@MainActor
public final class PlaybackCoordinator {
    public var onEvent: ((CoordinatorEvent) -> Void)?
    public private(set) var settings: AppSettings = .default
    public private(set) var userPaused = false

    let displays: DisplayManager
    let power: PowerMonitor
    private let factory: any RendererMaking
    private let posters: PosterSync?
    private let audio: (any AudioSpectrumSource)?
    private var library: [WallpaperID: Wallpaper] = [:]
    private var assignments: [DisplayKey: DisplayAssignment] = [:]
    private(set) var sessions: [DisplayKey: RenderSession] = [:]
    private var started = false

    public init(
        displays: DisplayManager, power: PowerMonitor, factory: any RendererMaking,
        posters: PosterSync?, audio: (any AudioSpectrumSource)?
    ) {
        self.displays = displays
        self.power = power
        self.factory = factory
        self.posters = posters
        self.audio = audio
    }

    public func start() {
        guard !started else { return }
        started = true
        displays.onLayoutChange = { [weak self] _ in self?.layoutChanged() }
        displays.onOcclusionChange = { [weak self] key, occluded in self?.power.setOccluded(key, occluded) }
        power.onChange = { [weak self] _ in self?.applyPlayback() }
        audio?.onSpectrum = { [weak self] spectrum in self?.broadcast(spectrum) }
        audio?.onSilence = { [weak self] in self?.onEvent?(.audioSilent) }
        displays.start()
        power.start()
        layoutChanged()
    }

    public func stop(restoreOriginalWallpaper: Bool) {
        sessions.values.forEach { $0.teardown() }
        sessions = [:]
        audio?.stop()
        power.stop()
        displays.stop()
        if restoreOriginalWallpaper { posters?.restoreOriginals() }
        started = false
    }

    public func update(library items: [Wallpaper], assignments list: [DisplayAssignment], settings newSettings: AppSettings) {
        library = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        assignments = Dictionary(list.map { ($0.display, $0) }, uniquingKeysWith: { _, last in last })
        let levelChanged = newSettings.windowLevelOffset != settings.windowLevelOffset
        settings = newSettings
        if levelChanged { displays.update(config: DesktopWindowConfig(levelOffset: newSettings.windowLevelOffset)) }
        reconcile()
    }

    public func setUserPaused(_ paused: Bool) {
        userPaused = paused
        applyPlayback()
    }

    public var connectedDisplays: [ScreenDescriptor] { displays.screens }

    public func playbackState(for display: DisplayKey) -> PlaybackState? { sessions[display]?.playback }

    public func activeWallpaper(for display: DisplayKey) -> WallpaperID? { sessions[display]?.wallpaper.id }

    private func layoutChanged() {
        power.updateDisplays(Dictionary(uniqueKeysWithValues: displays.screens.map { ($0.key, $0.cgBounds) }))
        reconcile()
    }

    func reconcile() {
        let connected = Set(displays.screens.map(\.key))
        for (key, session) in sessions where !connected.contains(key) || !isCurrent(session) {
            session.teardown()
            sessions.removeValue(forKey: key)
        }
        for screen in displays.screens {
            guard let assignment = assignments[screen.key], let wallpaper = library[assignment.wallpaper] else {
                displays.windows[screen.key]?.host(nil)
                continue
            }
            let values = wallpaper.properties.resolve(assignment.overrides)
            if let session = sessions[screen.key] {
                if session.values != values, !session.isFallback {
                    session.values = values
                    session.renderer.apply(values)
                }
            } else {
                startSession(on: screen, wallpaper: wallpaper, values: values, fill: assignment.fill)
            }
        }
        applyPlayback()
    }

    private func isCurrent(_ session: RenderSession) -> Bool {
        guard let assignment = assignments[session.display], let wallpaper = library[assignment.wallpaper] else { return false }
        if session.isFallback { return session.wallpaper.id == wallpaper.id && session.wallpaper.root == wallpaper.root }
        return session.wallpaper == wallpaper
    }

    private func startSession(on screen: ScreenDescriptor, wallpaper: Wallpaper, values: PropertyValues, fill: FillMode) {
        guard wallpaper.support != .previewOnly else {
            startFallback(on: screen, for: wallpaper, reason: .unsupported(wallpaper.type), fill: fill)
            return
        }
        switch factory.makeRenderer(for: wallpaper.type) {
        case .success(let renderer):
            let session = RenderSession(display: screen.key, wallpaper: wallpaper, renderer: renderer, values: values, isFallback: false)
            launch(session, on: screen, fill: fill)
        case .failure(let error):
            startFallback(on: screen, for: wallpaper, reason: error, fill: fill)
        }
    }

    private func launch(_ session: RenderSession, on screen: ScreenDescriptor, fill: FillMode) {
        sessions[screen.key] = session
        displays.windows[screen.key]?.host(session.renderer.hostView)
        session.renderer.onFailure = { [weak self, weak session] error in
            guard let self, let session else { return }
            self.handleFailure(session, error: error, fill: fill)
        }
        let context = RenderContext(
            pixelSize: screen.pixelSize, scale: screen.scale, fill: fill, renderScale: CGFloat(settings.renderScale)
        )
        let resolved = resolve(session)
        session.loadTask = Task { [weak self, weak session] in
            guard let session else { return }
            do throws(RenderError) {
                guard let resolved else { throw RenderError.assetMissing(session.wallpaper.root.path) }
                try await session.renderer.load(resolved, context: context)
                guard !Task.isCancelled else { return }
                self?.didLoad(session)
            } catch {
                guard !Task.isCancelled else { return }
                self?.handleFailure(session, error: error, fill: fill)
            }
        }
    }

    private func resolve(_ session: RenderSession) -> ResolvedWallpaper? {
        guard let assets = try? WallpaperResolver.assets(for: session.wallpaper) else { return nil }
        return ResolvedWallpaper(wallpaper: session.wallpaper, assets: assets, values: session.values)
    }

    private func didLoad(_ session: RenderSession) {
        guard sessions[session.display] === session else { return }
        session.phase = .ready
        session.renderer.setPlayback(session.playback)
        let id = session.wallpaper.id
        onEvent?(session.isFallback ? .fellBackToPreview(session.display, id) : .loaded(session.display, id))
        updateAudio()
        syncPoster(session)
    }

    private func handleFailure(_ session: RenderSession, error: RenderError, fill: FillMode) {
        guard sessions[session.display] === session else { return }
        session.phase = .failed(error)
        onEvent?(.failed(session.display, session.wallpaper.id, error))
        session.teardown()
        sessions.removeValue(forKey: session.display)
        guard !session.isFallback, let screen = displays.screens.first(where: { $0.key == session.display }) else { return }
        startFallback(on: screen, for: session.wallpaper, reason: error, fill: fill)
        applyPlayback()
    }

    /// Shows the wallpaper's preview image (e.g. `preview.gif`/`preview.jpg`) instead.
    private func startFallback(on screen: ScreenDescriptor, for wallpaper: Wallpaper, reason: RenderError, fill: FillMode) {
        guard let preview = wallpaper.preview else {
            displays.windows[screen.key]?.host(nil)
            return
        }
        let still = Wallpaper(id: wallpaper.id, title: wallpaper.title, type: .image, origin: wallpaper.origin,
                              root: wallpaper.root, entry: preview, preview: preview)
        guard case .success(let renderer) = factory.makeRenderer(for: .image) else { return }
        let session = RenderSession(display: screen.key, wallpaper: still, renderer: renderer, values: [:], isFallback: true)
        launch(session, on: screen, fill: fill)
    }

    func applyPlayback() {
        let keys = Array(sessions.keys)
        let decisions = PowerPolicy.decide(power.snapshot, settings: settings, displays: keys)
        for (key, session) in sessions {
            session.apply(playback: userPaused ? .paused : (decisions[key] ?? .paused))
        }
        updateAudio()
    }

    private func updateAudio() {
        guard let audio else { return }
        let wanted = settings.audioEnabled && sessions.values.contains(where: \.wantsAudio)
        if wanted, !audio.isRunning {
            do {
                try audio.start()
            } catch {
                onEvent?(.audioUnavailable(String(describing: error)))
            }
        } else if !wanted, audio.isRunning {
            audio.stop()
        }
    }

    private func broadcast(_ spectrum: AudioSpectrum) {
        for session in sessions.values where session.wantsAudio {
            session.renderer.receive(spectrum)
        }
    }

    private func syncPoster(_ session: RenderSession) {
        guard settings.posterSync, let posters else { return }
        Task { [weak session] in
            guard let session, let image = try? await session.renderer.snapshot() else { return }
            _ = try? posters.apply(image, for: session.display)
        }
    }
}
