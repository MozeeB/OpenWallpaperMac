import Foundation

/// Persistent identifier of a display (CoreGraphics display UUID string).
public struct DisplayKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// How a wallpaper is scaled into the display.
public enum FillMode: String, Codable, Sendable, CaseIterable {
    case fill
    case fit
    case stretch
}

/// Which wallpaper runs on which display.
public struct DisplayAssignment: Codable, Sendable, Equatable {
    public let display: DisplayKey
    public let wallpaper: WallpaperID
    public let overrides: PropertyValues
    public let fill: FillMode

    public init(display: DisplayKey, wallpaper: WallpaperID, overrides: PropertyValues = [:], fill: FillMode = .fill) {
        self.display = display
        self.wallpaper = wallpaper
        self.overrides = overrides
        self.fill = fill
    }

    public func with(overrides: PropertyValues) -> DisplayAssignment {
        DisplayAssignment(display: display, wallpaper: wallpaper, overrides: overrides, fill: fill)
    }

    public func with(fill: FillMode) -> DisplayAssignment {
        DisplayAssignment(display: display, wallpaper: wallpaper, overrides: overrides, fill: fill)
    }
}

/// The playback decision for one renderer.
public enum PlaybackState: Equatable, Sendable {
    case playing(fps: Int)
    case paused
    case suspended

    public var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
}

/// One frame of audio spectrum data, Wallpaper Engine compatible (64 bands per channel, 0...1).
public struct AudioSpectrum: Equatable, Sendable {
    public static let bandCount = 64

    public let left: [Float]
    public let right: [Float]

    public init(left: [Float], right: [Float]) {
        self.left = AudioSpectrum.normalize(left)
        self.right = AudioSpectrum.normalize(right)
    }

    public static let silent = AudioSpectrum(left: [], right: [])

    /// Per-band mean of both channels.
    public var average: [Float] {
        zip(left, right).map { ($0 + $1) * 0.5 }
    }

    /// Flat 128-value array: 64 left bands followed by 64 right bands.
    public var weArray: [Float] { left + right }

    private static func normalize(_ values: [Float]) -> [Float] {
        let clamped = values.prefix(bandCount).map { $0.isFinite ? min(max($0, 0), 1) : 0 }
        return clamped + Array(repeating: 0, count: bandCount - clamped.count)
    }
}
