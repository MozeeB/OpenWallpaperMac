import Foundation

/// A playlist of wallpapers shown one after another on a display.
public struct Rotation: Codable, Sendable, Equatable {
    public static let intervalRange: ClosedRange<TimeInterval> = 5 ... 86_400
    /// Choices offered in the UI (seconds).
    public static let presetIntervals: [TimeInterval] = [5, 10, 30, 60, 300, 900, 1800, 3600]

    public let items: [WallpaperID]
    public let interval: TimeInterval
    public let shuffle: Bool

    /// Duplicates are removed (keeping order) and the interval is clamped to `intervalRange`.
    public init(items: [WallpaperID], interval: TimeInterval = 5, shuffle: Bool = false) {
        var seen = Set<WallpaperID>()
        self.items = items.filter { seen.insert($0).inserted }
        let range = Rotation.intervalRange
        self.interval = interval.isFinite ? min(max(interval, range.lowerBound), range.upperBound) : range.lowerBound
        self.shuffle = shuffle
    }

    /// Keeps only wallpapers that still exist; nil when fewer than two remain.
    public func pruned(keeping ids: Set<WallpaperID>) -> Rotation? {
        let kept = items.filter(ids.contains)
        return kept.count > 1 ? Rotation(items: kept, interval: interval, shuffle: shuffle) : nil
    }

    /// Index of the item to show after `current`. Shuffle never repeats the current item.
    public func nextIndex<G: RandomNumberGenerator>(after current: Int, using generator: inout G) -> Int {
        guard items.count > 1 else { return 0 }
        guard shuffle else { return (current + 1) % items.count }
        let offset = Int.random(in: 1 ..< items.count, using: &generator)
        return (current + offset) % items.count
    }

    /// Units for a custom interval.
    public enum Unit: String, CaseIterable, Sendable {
        case seconds, minutes, hours

        public var seconds: TimeInterval {
            switch self {
            case .seconds: return 1
            case .minutes: return 60
            case .hours: return 3600
            }
        }
    }

    /// Converts a custom value to seconds, or nil when outside `intervalRange` or not a number.
    public static func customInterval(_ value: Double, unit: Unit) -> TimeInterval? {
        let seconds = value * unit.seconds
        guard seconds.isFinite, intervalRange.contains(seconds) else { return nil }
        return seconds
    }

    /// Human-readable interval, e.g. "5 s", "1 min", "1 h" (and "90 s", "1.5 h" for custom values).
    public static func label(for interval: TimeInterval) -> String {
        func trimmed(_ value: Double) -> String {
            value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        }
        if interval < 60 || interval.truncatingRemainder(dividingBy: 60) != 0 { return "\(trimmed(interval)) s" }
        if interval < 3600 || interval.truncatingRemainder(dividingBy: 1800) != 0 { return "\(trimmed(interval / 60)) min" }
        return "\(trimmed(interval / 3600)) h"
    }
}
