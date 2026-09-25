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
/// Owns one visible `RenderSession` per display, plus an optional `pending` session that loads the
/// next wallpaper of a rotation in the background and cross-fades in once ready. Every input change
/// funnels through `reconcile()`, which is idempotent. Session start/load/fallback lives in
/// `PlaybackCoordinator+Sessions.swift`.
@MainActor
public final class PlaybackCoordinator {
    public var onEvent: ((CoordinatorEvent) -> Void)?
    public private(set) var settings: AppSettings = .default
    public private(set) var userPaused = false

    let displays: DisplayManager
    let power: PowerMonitor
    let factory: any RendererMaking
    let posters: PosterSync?
    private let audio: (any AudioSpectrumSource)?
    /// Active Space per display; nil when per-Space support is unavailable.
    let spaces: SpaceMonitor?
    private var library: [WallpaperID: Wallpaper] = [:]
    private var assignments: [DisplayAssignment] = []
    var sessions: [DisplayKey: RenderSession] = [:]
    /// Next wallpaper of a rotation, loading off screen.
    var pending: [DisplayKey: RenderSession] = [:]
    private var rotations = RotationTracker()
    private var rotationTimer: Timer?
    private var random = SystemRandomNumberGenerator()
    private var started = false

    public init(
        displays: DisplayManager, power: PowerMonitor, factory: any RendererMaking,
        posters: PosterSync?, audio: (any AudioSpectrumSource)?, spaces: SpaceMonitor? = nil
    ) {
        self.displays = displays
        self.power = power
        self.factory = factory
        self.posters = posters
        self.audio = audio
        self.spaces = spaces
    }

    public func start() {
        guard !started else { return }
        started = true
        displays.onLayoutChange = { [weak self] _ in self?.layoutChanged() }
        displays.onOcclusionChange = { [weak self] key, occluded in self?.power.setOccluded(key, occluded) }
        power.onChange = { [weak self] _ in self?.applyPlayback() }
        audio?.onSpectrum = { [weak self] spectrum in self?.broadcast(spectrum) }
        audio?.onSilence = { [weak self] in self?.onEvent?(.audioSilent) }
        spaces?.onChange = { [weak self] in
            self?.reconcile()
            self?.onEvent?(.spacesChanged)
        }
        displays.start()
        power.start()
        spaces?.start()
        layoutChanged()
    }

    public func stop(restoreOriginalWallpaper: Bool) {
        rotationTimer?.invalidate()
        rotationTimer = nil
        (Array(sessions.values) + Array(pending.values)).forEach { $0.teardown() }
        sessions = [:]
        pending = [:]
        audio?.stop()
        spaces?.stop()
        power.stop()
        displays.stop()
        if restoreOriginalWallpaper { posters?.restoreOriginals() }
        started = false
    }

    public func update(library items: [Wallpaper], assignments list: [DisplayAssignment], settings newSettings: AppSettings) {
        library = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // One assignment per slot (display, or display + Space); the last one wins.
        assignments = Array(Dictionary(list.map { ($0.slot, $0) }, uniquingKeysWith: { _, last in last }).values)
        rotations.sync(assignments, now: Date())
        updateRotationTimer()
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

    /// 1-based position within the rotation showing on the display, if it has one.
    public func rotationPosition(for display: DisplayKey) -> (current: Int, count: Int)? {
        effectiveAssignment(for: display).flatMap { rotations.position(for: $0.slot) }
    }

    /// Shows the next wallpaper of the rotation showing on the display now.
    public func skipToNext(on display: DisplayKey) {
        guard let slot = effectiveAssignment(for: display)?.slot,
              rotations.skip(slot, now: Date(), using: &random)
        else { return }
        reconcile()
    }

    /// Whether Spaces can be told apart on this Mac.
    public var supportsSpaces: Bool { spaces?.isAvailable ?? false }

    /// The Spaces of a display and which one is active.
    public func spaces(on display: DisplayKey) -> DisplaySpaces? {
        spaces?.spaces[display]
    }

    private func layoutChanged() {
        power.updateDisplays(Dictionary(uniqueKeysWithValues: displays.screens.map { ($0.key, $0.cgBounds) }))
        spaces?.updateDisplays(displays.screens.map(\.key))
        reconcile()
    }

    /// The assignment that applies on a display right now: the active Space's own, else the default.
    public func effectiveAssignment(for display: DisplayKey) -> DisplayAssignment? {
        assignments.effective(for: display, space: spaces?.currentSpace(on: display))
    }

    /// The wallpaper a display should show now (its rotation's current item, or its single wallpaper).
    func desiredWallpaper(for display: DisplayKey) -> Wallpaper? {
        guard let assignment = effectiveAssignment(for: display) else { return nil }
        return library[rotations.wallpaper(for: assignment)]
    }

    func reconcile() {
        let connected = Set(displays.screens.map(\.key))
        for key in Set(sessions.keys).union(pending.keys)
        where !connected.contains(key) || desiredWallpaper(for: key) == nil {
            clearDisplay(key)
        }
        for screen in displays.screens {
            guard let assignment = effectiveAssignment(for: screen.key), let wallpaper = desiredWallpaper(for: screen.key) else {
                displays.windows[screen.key]?.host(nil)
                continue
            }
            show(wallpaper, on: screen, assignment: assignment)
        }
        applyPlayback()
    }

    private func clearDisplay(_ key: DisplayKey) {
        sessions.removeValue(forKey: key)?.teardown()
        pending.removeValue(forKey: key)?.teardown()
    }

    /// Keeps, updates or replaces the session on one display so it shows `wallpaper`.
    private func show(_ wallpaper: Wallpaper, on screen: ScreenDescriptor, assignment: DisplayAssignment) {
        let key = screen.key
        let values = wallpaper.properties.resolve(assignment.overrides)
        if let current = sessions[key], current.shows(wallpaper) {
            pending.removeValue(forKey: key)?.teardown()
            if current.values != values, !current.isFallback {
                current.values = values
                current.renderer.apply(values)
            }
            return
        }
        if let loading = pending[key], loading.shows(wallpaper) { return }
        pending.removeValue(forKey: key)?.teardown()
        // Cross-fade from a ready wallpaper; otherwise replace directly.
        let replaceInBackground = sessions[key]?.phase == .ready
        if !replaceInBackground { sessions.removeValue(forKey: key)?.teardown() }
        startSession(on: screen, wallpaper: wallpaper, values: values, fill: assignment.fill, inBackground: replaceInBackground)
    }

    func applyPlayback() {
        let keys = Array(sessions.keys)
        let decisions = PowerPolicy.decide(power.snapshot, settings: settings, displays: keys)
        for (key, session) in sessions {
            session.apply(playback: userPaused ? .paused : (decisions[key] ?? .paused))
        }
        updateAudio()
    }

    // MARK: Rotation timer

    private func updateRotationTimer() {
        if rotations.isActive, rotationTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advanceRotations(now: Date()) }
            }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            rotationTimer = timer
        } else if !rotations.isActive {
            rotationTimer?.invalidate()
            rotationTimer = nil
        }
    }

    /// Switches every on-screen rotation whose interval elapsed while it was playing. Rotations of
    /// Spaces that are not active hold their position.
    func advanceRotations(now: Date) {
        let paused = userPaused
        let visible = sessions
        let onScreen = Set(displays.screens.compactMap { effectiveAssignment(for: $0.key)?.slot })
        let switched = rotations.advance(now: now, isPlaying: { slot in
            guard onScreen.contains(slot) else { return false }
            // No visible session (e.g. a broken item without preview) must not stall the rotation.
            return visible[slot.display].map(\.playback.isPlaying) ?? !paused
        }, using: &random)
        if !switched.isEmpty { reconcile() }
    }

    var isRotationTimerRunning: Bool { rotationTimer != nil }

    // MARK: Audio & posters

    func updateAudio() {
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

    func syncPoster(_ session: RenderSession) {
        guard settings.posterSync, let posters else { return }
        Task { [weak session] in
            guard let session, let image = try? await session.renderer.snapshot() else { return }
            _ = try? posters.apply(image, for: session.display)
        }
    }
}
