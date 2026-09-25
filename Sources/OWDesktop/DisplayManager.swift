import AppKit
import OWCore

/// Keeps exactly one `DesktopWindow` per connected display and reports changes.
@MainActor
public final class DisplayManager {
    public var onLayoutChange: ((LayoutDiff) -> Void)?
    public var onOcclusionChange: ((DisplayKey, Bool) -> Void)?

    public private(set) var screens: [ScreenDescriptor] = []
    public private(set) var windows: [DisplayKey: DesktopWindow] = [:]
    public private(set) var config: DesktopWindowConfig

    private let provider: any ScreenProviding
    private let debounce: Duration
    private var screenObserver: (any NSObjectProtocol)?
    private var occlusionObservers: [DisplayKey: any NSObjectProtocol] = [:]
    private var pendingSync: Task<Void, Never>?

    public init(provider: any ScreenProviding = SystemScreenProvider(), config: DesktopWindowConfig = .init(),
                debounce: Duration = .milliseconds(250)) {
        self.provider = provider
        self.config = config
        self.debounce = debounce
    }

    public func start() {
        sync()
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        }
    }

    public func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        pendingSync?.cancel()
        Array(windows.keys).forEach(removeWindow)
        screens = []
    }

    public func update(config newConfig: DesktopWindowConfig) {
        guard newConfig != config else { return }
        config = newConfig
        windows.values.forEach { $0.apply(newConfig) }
    }

    public func nsScreen(for key: DisplayKey) -> NSScreen? {
        provider.nsScreen(for: key)
    }

    /// Coalesces bursts of screen-parameter notifications.
    func scheduleSync() {
        pendingSync?.cancel()
        let delay = debounce
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.sync()
        }
    }

    /// Applies the current layout. Returns the diff (empty when nothing changed).
    @discardableResult
    public func sync() -> LayoutDiff {
        let current = provider.currentScreens()
        let diff = LayoutDiff.between(screens, current)
        screens = current
        guard !diff.isEmpty else { return diff }
        diff.removed.forEach(removeWindow)
        diff.added.forEach(addWindow)
        diff.changed.forEach { windows[$0.key]?.reframe(to: $0) }
        onLayoutChange?(diff)
        return diff
    }

    private func addWindow(_ screen: ScreenDescriptor) {
        let window = DesktopWindow(screen: screen, config: config)
        window.orderBack(nil)
        windows[screen.key] = window
        let key = screen.key
        occlusionObservers[key] = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let window else { return }
                self?.onOcclusionChange?(key, !window.isVisibleOnScreen)
            }
        }
    }

    private func removeWindow(_ key: DisplayKey) {
        if let observer = occlusionObservers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(observer)
        }
        windows.removeValue(forKey: key)?.close()
    }
}
