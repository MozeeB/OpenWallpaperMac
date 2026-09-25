import Foundation

/// An RGB colour with components in 0...1.
public struct RGBColor: Codable, Sendable, Equatable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = RGBColor.clamp(red)
        self.green = RGBColor.clamp(green)
        self.blue = RGBColor.clamp(blue)
    }

    public static let white = RGBColor(red: 1, green: 1, blue: 1)
    public static let black = RGBColor(red: 0, green: 0, blue: 0)

    /// Parses Wallpaper Engine style `"r g b"` strings. Values above 1 are treated as 0...255.
    public init?(weString: String) {
        let parts = weString.split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
        guard parts.count >= 3 else { return nil }
        let scale = parts.prefix(3).contains { $0 > 1 } ? 255.0 : 1.0
        self.init(red: parts[0] / scale, green: parts[1] / scale, blue: parts[2] / scale)
    }

    /// `"r g b"` with components in 0...1, as Wallpaper Engine web wallpapers expect.
    public var weString: String {
        [red, green, blue].map { String(format: "%.4g", $0) }.joined(separator: " ")
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// A user-adjustable property value.
public enum PropertyValue: Codable, Sendable, Equatable, Hashable {
    case bool(Bool)
    case number(Double)
    case color(RGBColor)
    case string(String)

    public var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .bool(let value): return value ? 1 : 0
        case .string(let value): return Double(value)
        case .color: return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value): return ["true", "1"].contains(value.lowercased())
        case .color: return nil
        }
    }
}

public typealias PropertyValues = [String: PropertyValue]

public struct ComboOption: Codable, Sendable, Equatable, Hashable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public enum PropertyKind: Codable, Sendable, Equatable {
    case bool
    case slider(min: Double, max: Double, step: Double)
    case color
    case combo([ComboOption])
    case text
}

/// Definition of a user property exposed by a wallpaper.
public struct PropertyDefinition: Codable, Sendable, Equatable, Identifiable {
    public let key: String
    public let label: String
    public let order: Int
    public let kind: PropertyKind
    public let defaultValue: PropertyValue

    public var id: String { key }

    public init(key: String, label: String, order: Int, kind: PropertyKind, defaultValue: PropertyValue) {
        self.key = key
        self.label = label
        self.order = order
        self.kind = kind
        self.defaultValue = defaultValue
    }

    /// Returns `value` coerced to what this definition accepts, or `nil` if incompatible.
    public func validated(_ value: PropertyValue) -> PropertyValue? {
        switch (kind, value) {
        case (.bool, _):
            return value.boolValue.map(PropertyValue.bool)
        case let (.slider(lower, upper, _), _):
            guard let number = value.doubleValue, number.isFinite else { return nil }
            return .number(min(max(number, lower), upper))
        case (.color, .color):
            return value
        case (.color, .string(let text)):
            return RGBColor(weString: text).map(PropertyValue.color)
        case (.combo(let options), _):
            let text = PropertyDefinition.comboText(value)
            return options.contains { $0.value == text } ? .string(text) : nil
        case (.text, .string):
            return value
        default:
            return nil
        }
    }

    private static func comboText(_ value: PropertyValue) -> String {
        switch value {
        case .string(let text): return text
        case .number(let number):
            return number.rounded() == number ? String(Int(number)) : String(number)
        case .bool(let flag): return flag ? "true" : "false"
        case .color(let color): return color.weString
        }
    }
}

public extension Array where Element == PropertyDefinition {
    /// Merges `overrides` over defaults, dropping unknown keys and invalid values.
    func resolve(_ overrides: PropertyValues) -> PropertyValues {
        var result: PropertyValues = [:]
        for definition in self {
            let candidate = overrides[definition.key].flatMap(definition.validated)
            result[definition.key] = candidate ?? definition.defaultValue
        }
        return result
    }
}
