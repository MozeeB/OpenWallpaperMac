import Foundation

/// Persistent identifier of a macOS Space (desktop).
public struct SpaceKey: Hashable, Codable, Sendable, CustomStringConvertible {
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

/// One Space on a display, as shown to the user ("Desktop 2").
public struct SpaceInfo: Equatable, Sendable, Identifiable {
    public let key: SpaceKey
    /// 1-based desktop number among the display's regular (non-fullscreen) Spaces.
    public let number: Int
    public let isFullscreen: Bool

    public init(key: SpaceKey, number: Int, isFullscreen: Bool = false) {
        self.key = key
        self.number = number
        self.isFullscreen = isFullscreen
    }

    public var id: SpaceKey { key }
    public var name: String { isFullscreen ? "Fullscreen app" : "Desktop \(number)" }
}

/// The Spaces of one display and which one is active.
public struct DisplaySpaces: Equatable, Sendable {
    public let spaces: [SpaceInfo]
    public let current: SpaceKey?

    public init(spaces: [SpaceInfo], current: SpaceKey?) {
        self.spaces = spaces
        self.current = current
    }

    public var currentSpace: SpaceInfo? { spaces.first { $0.key == current } }
}

/// Where an assignment applies: a display, optionally narrowed to one of its Spaces.
public struct AssignmentSlot: Hashable, Sendable {
    public let display: DisplayKey
    /// nil means "every Space on this display that has no assignment of its own".
    public let space: SpaceKey?

    public init(display: DisplayKey, space: SpaceKey? = nil) {
        self.display = display
        self.space = space
    }
}

public extension Array where Element == DisplayAssignment {
    /// The assignment that applies on `display` while `space` is active: a Space-specific one wins,
    /// otherwise the display's default.
    func effective(for display: DisplayKey, space: SpaceKey?) -> DisplayAssignment? {
        if let space, let specific = first(where: { $0.display == display && $0.space == space }) { return specific }
        return first { $0.display == display && $0.space == nil }
    }

    func assignment(in slot: AssignmentSlot) -> DisplayAssignment? {
        first { $0.slot == slot }
    }
}
