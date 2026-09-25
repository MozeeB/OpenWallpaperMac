import Foundation
import OWCore

public enum ThermalLevel: Int, Comparable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Conditions that apply to a single display.
public struct DisplayPowerState: Equatable, Sendable {
    public let occluded: Bool
    public let fullscreenApp: Bool

    public init(occluded: Bool = false, fullscreenApp: Bool = false) {
        self.occluded = occluded
        self.fullscreenApp = fullscreenApp
    }
}

/// Everything the policy needs to know about the machine right now.
public struct PowerSnapshot: Equatable, Sendable {
    public let perDisplay: [DisplayKey: DisplayPowerState]
    public let onBattery: Bool
    public let lowPowerMode: Bool
    public let thermal: ThermalLevel
    public let screenLocked: Bool
    public let screensAsleep: Bool

    public init(
        perDisplay: [DisplayKey: DisplayPowerState] = [:], onBattery: Bool = false, lowPowerMode: Bool = false,
        thermal: ThermalLevel = .nominal, screenLocked: Bool = false, screensAsleep: Bool = false
    ) {
        self.perDisplay = perDisplay
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        self.thermal = thermal
        self.screenLocked = screenLocked
        self.screensAsleep = screensAsleep
    }

    public static let idle = PowerSnapshot()

    public func with(
        perDisplay: [DisplayKey: DisplayPowerState]? = nil, onBattery: Bool? = nil, lowPowerMode: Bool? = nil,
        thermal: ThermalLevel? = nil, screenLocked: Bool? = nil, screensAsleep: Bool? = nil
    ) -> PowerSnapshot {
        PowerSnapshot(
            perDisplay: perDisplay ?? self.perDisplay,
            onBattery: onBattery ?? self.onBattery,
            lowPowerMode: lowPowerMode ?? self.lowPowerMode,
            thermal: thermal ?? self.thermal,
            screenLocked: screenLocked ?? self.screenLocked,
            screensAsleep: screensAsleep ?? self.screensAsleep
        )
    }
}

/// Pure decision function: snapshot + settings -> playback state per display.
///
/// Precedence: the strictest action from every active rule wins (`suspend` > `pause` > `ignore`);
/// critical thermal pressure always suspends. When playing, the frame rate is the lowest of the
/// user cap, the battery cap (on battery) and a thermal cap.
public enum PowerPolicy {
    public static func decide(
        _ snapshot: PowerSnapshot, settings: AppSettings, displays: [DisplayKey]
    ) -> [DisplayKey: PlaybackState] {
        let global = globalAction(snapshot, rules: settings.pauseRules)
        let fps = frameRate(snapshot, settings: settings)
        return Dictionary(uniqueKeysWithValues: displays.map { display in
            let local = displayAction(snapshot.perDisplay[display] ?? DisplayPowerState(), rules: settings.pauseRules)
            return (display, state(for: max(global, local), fps: fps))
        })
    }

    static func globalAction(_ snapshot: PowerSnapshot, rules: PauseRules) -> PauseAction {
        if snapshot.thermal == .critical { return .suspend }
        let active: [(Bool, PauseAction)] = [
            (snapshot.onBattery, rules.onBattery),
            (snapshot.lowPowerMode, rules.lowPowerMode),
            (snapshot.thermal >= .serious, rules.thermalSerious),
            (snapshot.screenLocked, rules.screenLocked),
            (snapshot.screensAsleep, rules.screensAsleep),
        ]
        return active.filter(\.0).map(\.1).max() ?? .ignore
    }

    static func displayAction(_ state: DisplayPowerState, rules: PauseRules) -> PauseAction {
        let active: [(Bool, PauseAction)] = [
            (state.fullscreenApp, rules.fullscreenApp),
            (state.occluded, rules.occluded),
        ]
        return active.filter(\.0).map(\.1).max() ?? .ignore
    }

    static func frameRate(_ snapshot: PowerSnapshot, settings: AppSettings) -> Int {
        var fps = settings.frameRateCap.rawValue
        if snapshot.onBattery { fps = min(fps, settings.batteryFrameRateCap.rawValue) }
        switch snapshot.thermal {
        case .fair: fps = min(fps, 30)
        case .serious, .critical: fps = min(fps, 15)
        case .nominal: break
        }
        return fps
    }

    static func state(for action: PauseAction, fps: Int) -> PlaybackState {
        switch action {
        case .ignore: return .playing(fps: fps)
        case .pause: return .paused
        case .suspend: return .suspended
        }
    }
}
