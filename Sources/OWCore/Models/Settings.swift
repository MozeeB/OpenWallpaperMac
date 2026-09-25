import Foundation

/// What to do with a wallpaper when a condition is active.
public enum PauseAction: String, Codable, Sendable, CaseIterable, Comparable {
    case ignore
    /// Stop the frame loop, keep resources.
    case pause
    /// Tear the renderer down and free memory.
    case suspend

    private var rank: Int {
        switch self {
        case .ignore: return 0
        case .pause: return 1
        case .suspend: return 2
        }
    }

    public static func < (lhs: PauseAction, rhs: PauseAction) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// User-configurable rules that gate playback.
public struct PauseRules: Codable, Sendable, Equatable {
    public let fullscreenApp: PauseAction
    public let onBattery: PauseAction
    public let lowPowerMode: PauseAction
    public let thermalSerious: PauseAction
    public let occluded: PauseAction
    public let screenLocked: PauseAction
    public let screensAsleep: PauseAction

    public init(
        fullscreenApp: PauseAction = .pause,
        onBattery: PauseAction = .ignore,
        lowPowerMode: PauseAction = .pause,
        thermalSerious: PauseAction = .pause,
        occluded: PauseAction = .pause,
        screenLocked: PauseAction = .pause,
        screensAsleep: PauseAction = .suspend
    ) {
        self.fullscreenApp = fullscreenApp
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        self.thermalSerious = thermalSerious
        self.occluded = occluded
        self.screenLocked = screenLocked
        self.screensAsleep = screensAsleep
    }

    public static let `default` = PauseRules()
}

/// Frame-rate cap choices.
public enum FrameRateCap: Int, Codable, Sendable, CaseIterable {
    case fps15 = 15
    case fps30 = 30
    case fps60 = 60
}

/// App-wide settings. Immutable; use `with…` helpers to derive new values.
public struct AppSettings: Codable, Sendable, Equatable {
    public static let windowLevelOffsetRange = -3...0

    public let pauseRules: PauseRules
    public let frameRateCap: FrameRateCap
    public let batteryFrameRateCap: FrameRateCap
    public let windowLevelOffset: Int
    public let audioEnabled: Bool
    public let posterSync: Bool
    public let launchAtLogin: Bool

    public init(
        pauseRules: PauseRules = .default,
        frameRateCap: FrameRateCap = .fps30,
        batteryFrameRateCap: FrameRateCap = .fps15,
        windowLevelOffset: Int = -1,
        audioEnabled: Bool = false,
        posterSync: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.pauseRules = pauseRules
        self.frameRateCap = frameRateCap
        self.batteryFrameRateCap = batteryFrameRateCap
        let range = AppSettings.windowLevelOffsetRange
        self.windowLevelOffset = min(max(windowLevelOffset, range.lowerBound), range.upperBound)
        self.audioEnabled = audioEnabled
        self.posterSync = posterSync
        self.launchAtLogin = launchAtLogin
    }

    public static let `default` = AppSettings()

    public func with(
        pauseRules: PauseRules? = nil,
        frameRateCap: FrameRateCap? = nil,
        batteryFrameRateCap: FrameRateCap? = nil,
        windowLevelOffset: Int? = nil,
        audioEnabled: Bool? = nil,
        posterSync: Bool? = nil,
        launchAtLogin: Bool? = nil
    ) -> AppSettings {
        AppSettings(
            pauseRules: pauseRules ?? self.pauseRules,
            frameRateCap: frameRateCap ?? self.frameRateCap,
            batteryFrameRateCap: batteryFrameRateCap ?? self.batteryFrameRateCap,
            windowLevelOffset: windowLevelOffset ?? self.windowLevelOffset,
            audioEnabled: audioEnabled ?? self.audioEnabled,
            posterSync: posterSync ?? self.posterSync,
            launchAtLogin: launchAtLogin ?? self.launchAtLogin
        )
    }
}
