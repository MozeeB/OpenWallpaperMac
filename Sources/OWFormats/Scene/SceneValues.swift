import Foundation
import OWCore

public struct Vec2: Equatable, Sendable {
    public var x: Float
    public var y: Float

    public init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)
    public static let one = Vec2(1, 1)
}

public struct Vec3: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)
    public static let one = Vec3(1, 1, 1)
}

/// A scene value that is either a literal or bound to a user property (`{"user": key, "value": ...}`).
public struct SceneValue: Equatable, Sendable {
    public let fallback: [Float]
    public let userKey: String?

    public init(_ fallback: [Float], userKey: String? = nil) {
        self.fallback = fallback
        self.userKey = userKey
    }

    /// Current components, taking the bound user property into account.
    public func resolve(_ values: PropertyValues) -> [Float] {
        guard let key = userKey, let value = values[key] else { return fallback }
        switch value {
        case .number(let number): return [Float(number)]
        case .bool(let flag): return [flag ? 1 : 0]
        case .color(let color): return [Float(color.red), Float(color.green), Float(color.blue)]
        case .string(let text): return SceneValues.floats(text).nonEmpty ?? fallback
        }
    }

    public func scalar(_ values: PropertyValues, default defaultValue: Float = 0) -> Float {
        resolve(values).first ?? defaultValue
    }

    public func vec3(_ values: PropertyValues, default defaultValue: Vec3) -> Vec3 {
        SceneValues.vec3(resolve(values)) ?? defaultValue
    }

    public func bool(_ values: PropertyValues, default defaultValue: Bool = true) -> Bool {
        resolve(values).first.map { $0 != 0 } ?? defaultValue
    }
}

/// Parsing helpers for the loosely typed values found in scene JSON.
public enum SceneValues {
    /// Accepts numbers, booleans, `"1 2 3"` strings and `{"user":..., "value":...}` bindings.
    public static func value(_ raw: Any?) -> SceneValue? {
        switch raw {
        case let number as NSNumber:
            return SceneValue([number.floatValue])
        case let text as String:
            return floats(text).nonEmpty.map { SceneValue($0) }
        case let dict as [String: Any]:
            let fallback = value(dict["value"])?.fallback ?? []
            return SceneValue(fallback, userKey: userKey(dict["user"]))
        default:
            return nil
        }
    }

    private static func userKey(_ raw: Any?) -> String? {
        if let key = raw as? String { return key }
        if let dict = raw as? [String: Any] { return dict["name"] as? String }
        return nil
    }

    public static func floats(_ text: String) -> [Float] {
        text.split(whereSeparator: { $0 == " " || $0 == "," })
            .prefix(16)
            .compactMap { Float($0) }
            .filter(\.isFinite)
    }

    public static func vec3(_ values: [Float]) -> Vec3? {
        switch values.count {
        case 0: return nil
        case 1: return Vec3(values[0], values[0], values[0])
        case 2: return Vec3(values[0], values[1], 0)
        default: return Vec3(values[0], values[1], values[2])
        }
    }

    public static func vec2(_ values: [Float]) -> Vec2? {
        switch values.count {
        case 0: return nil
        case 1: return Vec2(values[0], values[0])
        default: return Vec2(values[0], values[1])
        }
    }

    public static func vec3(_ raw: Any?, default defaultValue: Vec3) -> Vec3 {
        value(raw).flatMap { vec3($0.fallback) } ?? defaultValue
    }

    public static func vec2(_ raw: Any?, default defaultValue: Vec2) -> Vec2 {
        value(raw).flatMap { vec2($0.fallback) } ?? defaultValue
    }

    public static func float(_ raw: Any?, default defaultValue: Float) -> Float {
        value(raw)?.fallback.first ?? defaultValue
    }

    public static func bool(_ raw: Any?, default defaultValue: Bool) -> Bool {
        if let number = raw as? NSNumber { return number.boolValue }
        return value(raw)?.fallback.first.map { $0 != 0 } ?? defaultValue
    }

    public static func path(_ raw: Any?) -> SanitizedPath? {
        (raw as? String).flatMap { try? SanitizedPath($0) }
    }
}

extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}
