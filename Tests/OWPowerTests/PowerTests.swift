import CoreGraphics
import Foundation
import Testing
@testable import OWCore
@testable import OWPower

private let main = DisplayKey("main")
private let side = DisplayKey("side")

@Suite("PowerPolicy")
struct PowerPolicyTests {
    let settings = AppSettings.default

    @Test("idle machine plays at the user cap")
    func idle() {
        let result = PowerPolicy.decide(.idle, settings: settings, displays: [main, side])
        #expect(result == [main: .playing(fps: 30), side: .playing(fps: 30)])
    }

    @Test("global conditions map through rules", arguments: [
        (PowerSnapshot(onBattery: true), PlaybackState.playing(fps: 15)),
        (PowerSnapshot(lowPowerMode: true), .paused),
        (PowerSnapshot(thermal: .fair), .playing(fps: 30)),
        (PowerSnapshot(thermal: .serious), .paused),
        (PowerSnapshot(thermal: .critical), .suspended),
        (PowerSnapshot(screenLocked: true), .paused),
        (PowerSnapshot(screensAsleep: true), .suspended),
        (PowerSnapshot(lowPowerMode: true, screensAsleep: true), .suspended),
    ])
    func global(snapshot: PowerSnapshot, expected: PlaybackState) {
        #expect(PowerPolicy.decide(snapshot, settings: settings, displays: [main])[main] == expected)
    }

    @Test("per-display conditions only affect their display")
    func perDisplay() {
        let snapshot = PowerSnapshot(perDisplay: [main: DisplayPowerState(fullscreenApp: true), side: DisplayPowerState()])
        let result = PowerPolicy.decide(snapshot, settings: settings, displays: [main, side])
        #expect(result[main] == .paused)
        #expect(result[side] == .playing(fps: 30))
        let occluded = PowerSnapshot(perDisplay: [side: DisplayPowerState(occluded: true)])
        #expect(PowerPolicy.decide(occluded, settings: settings, displays: [side])[side] == .paused)
    }

    @Test("custom rules and frame caps")
    func custom() {
        let rules = PauseRules(fullscreenApp: .suspend, onBattery: .pause, thermalSerious: .ignore)
        let custom = settings.with(pauseRules: rules, frameRateCap: .fps60, batteryFrameRateCap: .fps30)
        #expect(PowerPolicy.decide(.idle, settings: custom, displays: [main])[main] == .playing(fps: 60))
        #expect(PowerPolicy.decide(PowerSnapshot(onBattery: true), settings: custom, displays: [main])[main] == .paused)
        #expect(PowerPolicy.decide(PowerSnapshot(thermal: .serious), settings: custom, displays: [main])[main] == .playing(fps: 15))
        let fullscreen = PowerSnapshot(perDisplay: [main: DisplayPowerState(fullscreenApp: true)])
        #expect(PowerPolicy.decide(fullscreen, settings: custom, displays: [main])[main] == .suspended)
        let ignoreAll = PauseRules(fullscreenApp: .ignore, lowPowerMode: .ignore, occluded: .ignore, screenLocked: .ignore, screensAsleep: .ignore)
        let busy = PowerSnapshot(
            perDisplay: [main: DisplayPowerState(occluded: true, fullscreenApp: true)],
            lowPowerMode: true, screenLocked: true, screensAsleep: true
        )
        #expect(PowerPolicy.decide(busy, settings: settings.with(pauseRules: ignoreAll), displays: [main])[main] == .playing(fps: 30))
    }

    @Test("snapshot copy helper and thermal mapping")
    func helpers() {
        let base = PowerSnapshot.idle
        #expect(base.with(onBattery: true).onBattery)
        #expect(base.with(thermal: .fair).thermal == .fair)
        #expect(base.with(screenLocked: true, screensAsleep: true).screensAsleep)
        #expect(base.with(perDisplay: [main: DisplayPowerState()], lowPowerMode: true).lowPowerMode)
        #expect(ThermalLevel(.nominal) == .nominal)
        #expect(ThermalLevel(.fair) == .fair)
        #expect(ThermalLevel(.serious) == .serious)
        #expect(ThermalLevel(.critical) == .critical)
    }
}

@Suite("FullscreenAnalyzer")
struct FullscreenAnalyzerTests {
    let analyzer = FullscreenAnalyzer(ownPID: 1)
    let displays: [DisplayKey: CGRect] = [
        main: CGRect(x: 0, y: 0, width: 1512, height: 982),
        side: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
    ]

    @Test("detects covering windows per display, tolerating menu bar/notch")
    func covering() {
        let notched = WindowInfo(ownerPID: 2, layer: 0, bounds: CGRect(x: 0, y: 37, width: 1512, height: 945))
        #expect(analyzer.coveredDisplays(windows: [notched], displays: displays) == [main])
        let full = WindowInfo(ownerPID: 3, layer: 0, bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        #expect(analyzer.coveredDisplays(windows: [notched, full], displays: displays) == [main, side])
    }

    @Test("ignores own, partial, overlay and transparent windows")
    func ignores() {
        let windows = [
            WindowInfo(ownerPID: 1, layer: 0, bounds: displays[main]!),
            WindowInfo(ownerPID: 2, layer: 0, bounds: CGRect(x: 0, y: 0, width: 800, height: 600)),
            WindowInfo(ownerPID: 2, layer: 25, bounds: displays[main]!),
            WindowInfo(ownerPID: 2, layer: 0, bounds: displays[side]!, alpha: 0),
            WindowInfo(ownerPID: 2, layer: 0, bounds: CGRect(x: 5000, y: 0, width: 10, height: 10)),
        ]
        #expect(analyzer.coveredDisplays(windows: windows, displays: displays).isEmpty)
        #expect(analyzer.coverage(of: .zero, by: displays[main]!) == 0)
        #expect(FullscreenAnalyzer(ownPID: 0, coverageThreshold: 5).coverageThreshold == 1)
    }

    @Test("parses CGWindowList dictionaries")
    func parse() {
        let bounds = CGRect(x: 1, y: 2, width: 3, height: 4).dictionaryRepresentation
        let info = WindowInfo(dictionary: [
            kCGWindowOwnerPID as String: Int32(9), kCGWindowLayer as String: 0,
            kCGWindowBounds as String: bounds, kCGWindowAlpha as String: 0.5,
        ])
        #expect(info == WindowInfo(ownerPID: 9, layer: 0, bounds: CGRect(x: 1, y: 2, width: 3, height: 4), alpha: 0.5))
        #expect(WindowInfo(dictionary: [:]) == nil)
    }
}

private final class FakeWindows: WindowListProviding, @unchecked Sendable {
    var windows: [WindowInfo] = []
    func onScreenWindows() -> [WindowInfo] { windows }
}

private final class FakePower: PowerSourceProviding, @unchecked Sendable {
    var isOnBattery = false
    var isLowPowerMode = false
    var thermal = ThermalLevel.nominal
}

@Suite("PowerMonitor")
@MainActor
struct PowerMonitorTests {
    @Test("publishes changes from pushed and polled signals")
    func publishes() {
        let windows = FakeWindows()
        let power = FakePower()
        let monitor = PowerMonitor(windows: windows, power: power, analyzer: FullscreenAnalyzer(ownPID: 1))
        var received: [PowerSnapshot] = []
        monitor.onChange = { received.append($0) }
        monitor.updateDisplays([main: CGRect(x: 0, y: 0, width: 100, height: 100)])
        #expect(received.last?.perDisplay[main] == DisplayPowerState())

        monitor.setOccluded(main, true)
        #expect(received.last?.perDisplay[main]?.occluded == true)
        let count = received.count
        monitor.setOccluded(main, true)
        #expect(received.count == count)

        windows.windows = [WindowInfo(ownerPID: 2, layer: 0, bounds: CGRect(x: 0, y: 0, width: 100, height: 100))]
        monitor.refreshFullscreen()
        #expect(monitor.snapshot.perDisplay[main]?.fullscreenApp == true)

        power.isOnBattery = true
        power.thermal = .serious
        monitor.refreshAll()
        #expect(monitor.snapshot.onBattery && monitor.snapshot.thermal == .serious)

        monitor.setLocked(true)
        #expect(monitor.snapshot.screenLocked)
        windows.windows = []
        monitor.refreshFullscreen()
        #expect(monitor.snapshot.perDisplay[main]?.fullscreenApp == true, "window list is not polled while locked")
        monitor.setLocked(false)
        #expect(monitor.snapshot.perDisplay[main]?.fullscreenApp == false)
        monitor.setAsleep(true)
        #expect(monitor.snapshot.screensAsleep)
    }

    @Test("start and stop register and remove observers")
    func lifecycle() {
        let monitor = PowerMonitor(windows: FakeWindows(), power: FakePower())
        monitor.start()
        monitor.start()
        monitor.stop()
        monitor.updateDisplays([:])
        #expect(monitor.snapshot.perDisplay.isEmpty)
    }

    @Test("system providers return sane values")
    func providers() {
        _ = CGWindowListProvider().onScreenWindows()
        let power = SystemPowerSource()
        _ = power.isOnBattery
        _ = power.isLowPowerMode
        #expect(power.thermal <= .critical)
    }
}
