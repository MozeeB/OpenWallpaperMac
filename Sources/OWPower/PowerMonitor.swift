import AppKit
import CoreGraphics
import Foundation
import IOKit.ps
import OWCore

/// Merges every power-related signal into one `PowerSnapshot` and reports changes.
///
/// Signals: screen sleep/wake, lock/unlock, fast user switching, Space/app changes,
/// battery (IOKit run-loop source), Low Power Mode, thermal state, per-window occlusion
/// (pushed in by the desktop layer) and a coalesced fullscreen poll, because borderless
/// fullscreen apps trigger no activation or Space notification.
@MainActor
public final class PowerMonitor {
    public private(set) var snapshot: PowerSnapshot = .idle
    public var onChange: ((PowerSnapshot) -> Void)?

    private let windows: any WindowListProviding
    private let power: any PowerSourceProviding
    private let analyzer: FullscreenAnalyzer
    private let pollInterval: TimeInterval
    private var displayBounds: [DisplayKey: CGRect] = [:]
    private var occluded: Set<DisplayKey> = []
    private var fullscreen: Set<DisplayKey> = []
    private var locked = false
    private var asleep = false
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    private var timer: Timer?
    private var batterySource: CFRunLoopSource?

    public init(
        windows: any WindowListProviding = CGWindowListProvider(),
        power: any PowerSourceProviding = SystemPowerSource(),
        analyzer: FullscreenAnalyzer = FullscreenAnalyzer(ownPID: ProcessInfo.processInfo.processIdentifier),
        pollInterval: TimeInterval = 2
    ) {
        self.windows = windows
        self.power = power
        self.analyzer = analyzer
        self.pollInterval = pollInterval
    }

    public func start() {
        guard observers.isEmpty else { return }
        observeWorkspace()
        observeSystem()
        startBatteryNotifications()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFullscreen() }
        }
        timer.tolerance = pollInterval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshAll()
    }

    public func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers = []
        timer?.invalidate()
        timer = nil
        if let batterySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .defaultMode) }
        batterySource = nil
    }

    /// Display bounds in global CoreGraphics coordinates (top-left origin), from the desktop layer.
    public func updateDisplays(_ bounds: [DisplayKey: CGRect]) {
        displayBounds = bounds
        occluded = occluded.filter { bounds[$0] != nil }
        refreshFullscreen()
    }

    public func setOccluded(_ display: DisplayKey, _ isOccluded: Bool) {
        let updated = isOccluded ? occluded.union([display]) : occluded.subtracting([display])
        guard updated != occluded else { return }
        occluded = updated
        publish()
    }

    /// Re-reads every pollable signal. Exposed for tests and wake handling.
    public func refreshAll() {
        refreshFullscreen(publishing: false)
        publish()
    }

    func refreshFullscreen(publishing: Bool = true) {
        // Skip the window-list query while nothing can be visible anyway.
        if !(locked || asleep) {
            fullscreen = analyzer.coveredDisplays(windows: windows.onScreenWindows(), displays: displayBounds)
        }
        if publishing { publish() }
    }

    func setLocked(_ value: Bool) {
        locked = value
        refreshAll()
    }

    func setAsleep(_ value: Bool) {
        asleep = value
        refreshAll()
    }

    private func publish() {
        let perDisplay = Dictionary(uniqueKeysWithValues: displayBounds.keys.map { key in
            (key, DisplayPowerState(occluded: occluded.contains(key), fullscreenApp: fullscreen.contains(key)))
        })
        let next = PowerSnapshot(
            perDisplay: perDisplay, onBattery: power.isOnBattery, lowPowerMode: power.isLowPowerMode,
            thermal: power.thermal, screenLocked: locked, screensAsleep: asleep
        )
        guard next != snapshot else { return }
        snapshot = next
        onChange?(next)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        observers.append((center, token))
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.setAsleep(true) }
        observe(center, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.setAsleep(false) }
        observe(center, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.setLocked(true) }
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.setLocked(false) }
        observe(center, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.refreshFullscreen() }
        observe(center, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.refreshFullscreen() }
    }

    private func observeSystem() {
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.setLocked(true) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.setLocked(false) }
        let local = NotificationCenter.default
        observe(local, Notification.Name.NSProcessInfoPowerStateDidChange) { [weak self] in self?.refreshAll() }
        observe(local, ProcessInfo.thermalStateDidChangeNotification) { [weak self] in self?.refreshAll() }
    }

    private func startBatteryNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refreshAll() }
        }, context)?.takeRetainedValue()
        guard let source else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        batterySource = source
    }
}
