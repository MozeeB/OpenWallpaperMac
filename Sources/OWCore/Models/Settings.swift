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

    private enum CodingKeys: String, CodingKey {
        case fullscreenApp, onBattery, lowPowerMode, thermalSerious, occluded, screenLocked, screensAsleep
    }

    /// Missing keys fall back to defaults so older state files keep loading.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PauseRules.default
        self.init(
            fullscreenApp: try c.decodeIfPresent(PauseAction.self, forKey: .fullscreenApp) ?? d.fullscreenApp,
            onBattery: try c.decodeIfPresent(PauseAction.self, forKey: .onBattery) ?? d.onBattery,
            lowPowerMode: try c.decodeIfPresent(PauseAction.self, forKey: .lowPowerMode) ?? d.lowPowerMode,
            thermalSerious: try c.decodeIfPresent(PauseAction.self, forKey: .thermalSerious) ?? d.thermalSerious,
            occluded: try c.decodeIfPresent(PauseAction.self, forKey: .occluded) ?? d.occluded,
            screenLocked: try c.decodeIfPresent(PauseAction.self, forKey: .screenLocked) ?? d.screenLocked,
            screensAsleep: try c.decodeIfPresent(PauseAction.self, forKey: .screensAsleep) ?? d.screensAsleep
        )
    }

    public var mutableCopy: Mutable { Mutable(self) }

    public func with(_ keyPath: WritableKeyPath<PauseRules.Mutable, PauseAction>, _ action: PauseAction) -> PauseRules {
        var mutable = Mutable(self)
        mutable[keyPath: keyPath] = action
        return mutable.frozen
    }

    /// Scratch copy used only to build a new immutable value.
    public struct Mutable {
        public var fullscreenApp, onBattery, lowPowerMode, thermalSerious, occluded, screenLocked, screensAsleep: PauseAction

        init(_ rules: PauseRules) {
            fullscreenApp = rules.fullscreenApp
            onBattery = rules.onBattery
            lowPowerMode = rules.lowPowerMode
            thermalSerious = rules.thermalSerious
            occluded = rules.occluded
            screenLocked = rules.screenLocked
            screensAsleep = rules.screensAsleep
        }

        var frozen: PauseRules {
            PauseRules(
                fullscreenApp: fullscreenApp, onBattery: onBattery, lowPowerMode: lowPowerMode,
                thermalSerious: thermalSerious, occluded: occluded, screenLocked: screenLocked, screensAsleep: screensAsleep
            )
        }
    }
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
    /// Fraction of native resolution for shader/scene rendering (0.25...1).
    public let renderScale: Double

    public init(
        pauseRules: PauseRules = .default,
        frameRateCap: FrameRateCap = .fps60,
        batteryFrameRateCap: FrameRateCap = .fps15,
        windowLevelOffset: Int = -1,
        audioEnabled: Bool = false,
        posterSync: Bool = true,
        launchAtLogin: Bool = false,
        renderScale: Double = 1
    ) {
        self.pauseRules = pauseRules
        self.frameRateCap = frameRateCap
        self.batteryFrameRateCap = batteryFrameRateCap
        let range = AppSettings.windowLevelOffsetRange
        self.windowLevelOffset = min(max(windowLevelOffset, range.lowerBound), range.upperBound)
        self.audioEnabled = audioEnabled
        self.posterSync = posterSync
        self.launchAtLogin = launchAtLogin
        self.renderScale = renderScale.isFinite ? min(max(renderScale, 0.25), 1) : 1
    }

    public static let `default` = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case pauseRules, frameRateCap, batteryFrameRateCap, windowLevelOffset, audioEnabled, posterSync
        case launchAtLogin, renderScale
    }

    /// Missing keys fall back to defaults so older state files keep loading.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        self.init(
            pauseRules: try c.decodeIfPresent(PauseRules.self, forKey: .pauseRules) ?? d.pauseRules,
            frameRateCap: try c.decodeIfPresent(FrameRateCap.self, forKey: .frameRateCap) ?? d.frameRateCap,
            batteryFrameRateCap: try c.decodeIfPresent(FrameRateCap.self, forKey: .batteryFrameRateCap) ?? d.batteryFrameRateCap,
            windowLevelOffset: try c.decodeIfPresent(Int.self, forKey: .windowLevelOffset) ?? d.windowLevelOffset,
            audioEnabled: try c.decodeIfPresent(Bool.self, forKey: .audioEnabled) ?? d.audioEnabled,
            posterSync: try c.decodeIfPresent(Bool.self, forKey: .posterSync) ?? d.posterSync,
            launchAtLogin: try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin,
            renderScale: try c.decodeIfPresent(Double.self, forKey: .renderScale) ?? d.renderScale
        )
    }

    public func with(
        pauseRules: PauseRules? = nil,
        frameRateCap: FrameRateCap? = nil,
        batteryFrameRateCap: FrameRateCap? = nil,
        windowLevelOffset: Int? = nil,
        audioEnabled: Bool? = nil,
        posterSync: Bool? = nil,
        launchAtLogin: Bool? = nil,
        renderScale: Double? = nil
    ) -> AppSettings {
        AppSettings(
            pauseRules: pauseRules ?? self.pauseRules,
            frameRateCap: frameRateCap ?? self.frameRateCap,
            batteryFrameRateCap: batteryFrameRateCap ?? self.batteryFrameRateCap,
            windowLevelOffset: windowLevelOffset ?? self.windowLevelOffset,
            audioEnabled: audioEnabled ?? self.audioEnabled,
            posterSync: posterSync ?? self.posterSync,
            launchAtLogin: launchAtLogin ?? self.launchAtLogin,
            renderScale: renderScale ?? self.renderScale
        )
    }
}
