import Foundation
import OWCore

public struct FloatRange: Equatable, Sendable {
    public let lower: Float
    public let upper: Float

    public init(_ lower: Float, _ upper: Float) {
        self.lower = min(lower, upper)
        self.upper = max(lower, upper)
    }
}

public enum EmitterShape: String, Equatable, Sendable {
    case box
    case sphere
}

public struct ParticleEmitterSpec: Equatable, Sendable {
    public let shape: EmitterShape
    /// Particles per second.
    public let rate: Float
    public let origin: Vec3
    public let distanceMin: Vec3
    public let distanceMax: Vec3
    public let directions: Vec3
    public let speed: FloatRange
}

public struct ParticleInitializerSpec: Equatable, Sendable {
    public var lifetime = FloatRange(1, 1)
    public var size = FloatRange(20, 20)
    public var velocityMin = Vec3.zero
    public var velocityMax = Vec3.zero
    /// 0...1 components.
    public var colorMin = Vec3.one
    public var colorMax = Vec3.one
    public var alpha = FloatRange(1, 1)
    public var rotation = FloatRange(0, 0)
    public var angularVelocity = FloatRange(0, 0)

    public init() {}
}

public struct ParticleOperatorSpec: Equatable, Sendable {
    public var gravity = Vec3.zero
    public var drag: Float = 0
    /// Fractions of lifetime (0...1).
    public var fadeInTime: Float = 0
    public var fadeOutTime: Float = 0
    public var sizeStart: Float = 1
    public var sizeEnd: Float = 1

    public init() {}
}

public struct ParticleSystemDocument: Equatable, Sendable {
    public let emitters: [ParticleEmitterSpec]
    public let initializer: ParticleInitializerSpec
    public let operators: ParticleOperatorSpec
    public let material: SanitizedPath?
    public let maxCount: Int
    public let startTime: Float
    /// Component names that were present but are not simulated.
    public let unsupported: [String]
}

/// Parses `particles/*.json`.
public enum ParticleParser {
    public static func parse(_ json: [String: Any]) -> ParticleSystemDocument {
        var unsupported: [String] = []
        let emitters = (json["emitter"] as? [[String: Any]] ?? []).compactMap { raw -> ParticleEmitterSpec? in
            let spec = emitter(raw)
            if spec == nil { unsupported.append("emitter:\(raw["name"] as? String ?? "?")") }
            return spec
        }
        var initializer = ParticleInitializerSpec()
        for raw in json["initializer"] as? [[String: Any]] ?? [] where !apply(initializer: raw, to: &initializer) {
            unsupported.append("initializer:\(raw["name"] as? String ?? "?")")
        }
        var operators = ParticleOperatorSpec()
        for raw in json["operator"] as? [[String: Any]] ?? [] where !apply(operator: raw, to: &operators) {
            unsupported.append("operator:\(raw["name"] as? String ?? "?")")
        }
        let maxCount = (json["maxcount"] as? NSNumber)?.intValue ?? 100
        return ParticleSystemDocument(
            emitters: emitters, initializer: initializer, operators: operators,
            material: SceneValues.path(json["material"]),
            maxCount: min(max(maxCount, 0), Limits.maxParticles),
            startTime: SceneValues.float(json["starttime"], default: 0),
            unsupported: unsupported
        )
    }

    static func emitter(_ raw: [String: Any]) -> ParticleEmitterSpec? {
        let name = (raw["name"] as? String ?? "").lowercased()
        let shape: EmitterShape
        switch name {
        case "boxrandom": shape = .box
        case "sphererandom": shape = .sphere
        default: return nil
        }
        return ParticleEmitterSpec(
            shape: shape,
            rate: max(SceneValues.float(raw["rate"], default: 5), 0),
            origin: SceneValues.vec3(raw["origin"], default: .zero),
            distanceMin: SceneValues.vec3(raw["distancemin"], default: .zero),
            distanceMax: SceneValues.vec3(raw["distancemax"], default: Vec3(256, 256, 0)),
            directions: SceneValues.vec3(raw["directions"], default: Vec3(1, 1, 0)),
            speed: FloatRange(
                SceneValues.float(raw["speedmin"], default: 0), SceneValues.float(raw["speedmax"], default: 0)
            )
        )
    }

    static func range(_ raw: [String: Any], _ defaultMin: Float, _ defaultMax: Float) -> FloatRange {
        FloatRange(SceneValues.float(raw["min"], default: defaultMin), SceneValues.float(raw["max"], default: defaultMax))
    }

    static func apply(initializer raw: [String: Any], to spec: inout ParticleInitializerSpec) -> Bool {
        switch (raw["name"] as? String ?? "").lowercased() {
        case "lifetimerandom": spec.lifetime = range(raw, 1, 1)
        case "sizerandom": spec.size = range(raw, 20, 20)
        case "alpharandom": spec.alpha = range(raw, 1, 1)
        case "rotationrandom": spec.rotation = range(raw, 0, 0)
        case "angularvelocityrandom": spec.angularVelocity = range(raw, 0, 0)
        case "velocityrandom":
            spec.velocityMin = SceneValues.vec3(raw["min"], default: Vec3(-32, -32, 0))
            spec.velocityMax = SceneValues.vec3(raw["max"], default: Vec3(32, 32, 0))
        case "colorrandom":
            spec.colorMin = normalizedColor(raw["min"], default: .one)
            spec.colorMax = normalizedColor(raw["max"], default: .one)
        default: return false
        }
        return true
    }

    static func apply(operator raw: [String: Any], to spec: inout ParticleOperatorSpec) -> Bool {
        switch (raw["name"] as? String ?? "").lowercased() {
        case "movement":
            spec.gravity = SceneValues.vec3(raw["gravity"], default: .zero)
            spec.drag = SceneValues.float(raw["drag"], default: 0)
        case "alphafade":
            spec.fadeInTime = SceneValues.float(raw["fadeintime"], default: 0.1)
            spec.fadeOutTime = SceneValues.float(raw["fadeouttime"], default: 0.5)
        case "sizechange":
            spec.sizeStart = SceneValues.float(raw["startvalue"], default: 1)
            spec.sizeEnd = SceneValues.float(raw["endvalue"], default: 0)
        default: return false
        }
        return true
    }

    /// Colours may be written as 0...255; normalise to 0...1.
    static func normalizedColor(_ raw: Any?, default defaultValue: Vec3) -> Vec3 {
        let color = SceneValues.vec3(raw, default: defaultValue)
        let scale: Float = [color.x, color.y, color.z].contains { $0 > 1 } ? 255 : 1
        return Vec3(color.x / scale, color.y / scale, color.z / scale)
    }
}
