import Foundation
import OWCore
import OWFormats

/// Parameters of every natively re-implemented effect, combined into one shader pass.
public struct EffectParameters: Equatable, Sendable {
    public var scroll = SIMD2<Float>(0, 0)
    public var shakeSpeed: Float = 0
    public var shakeStrength: Float = 0
    public var rippleSpeed: Float = 0
    public var rippleScale: Float = 0
    public var rippleStrength: Float = 0
    public var waveSpeed: Float = 0
    public var waveScale: Float = 0
    public var waveStrength: Float = 0
    public var tint = SIMD3<Float>(1, 1, 1)
    public var tintAmount: Float = 0
    public var opacity: Float = 1
    public var pulseSpeed: Float = 0
    public var pulseAmount: Float = 0
    public var blurRadius: Float = 0

    public init() {}

    /// True when any parameter changes over time (needs a running frame loop).
    public var isAnimated: Bool {
        scroll != .zero || shakeStrength != 0 || rippleStrength != 0 || waveStrength != 0 || pulseAmount != 0
    }
}

/// Maps Wallpaper Engine effect folder names to native implementations.
///
/// Effects are reimplemented from their observable behaviour; none of the original shader code
/// is used. Unknown effects are reported by `SceneSupportAnalyzer` and skipped.
public enum EffectRegistry {
    public static let known: Set<String> = [
        "scroll", "shake", "waterripple", "waterwaves", "foliagesway", "pulse", "tint", "opacity", "blur",
    ]

    public static func parameters(for effects: [SceneEffect], values: PropertyValues) -> EffectParameters {
        effects.reduce(into: EffectParameters()) { params, effect in
            guard effect.visible.bool(values), known.contains(effect.name) else { return }
            apply(effect, values: values, to: &params)
        }
    }

    static func constant(_ effect: SceneEffect, _ names: [String], _ values: PropertyValues, default fallback: Float) -> Float {
        for name in names { if let value = effect.constants[name] { return value.scalar(values, default: fallback) } }
        return fallback
    }

    static func vector(_ effect: SceneEffect, _ names: [String], _ values: PropertyValues, default fallback: [Float]) -> [Float] {
        for name in names { if let value = effect.constants[name] { return value.resolve(values) } }
        return fallback
    }

    static func apply(_ effect: SceneEffect, values: PropertyValues, to p: inout EffectParameters) {
        let c = { (names: [String], fallback: Float) in constant(effect, names, values, default: fallback) }
        switch effect.name {
        case "scroll":
            let speed = vector(effect, ["speed", "scrollspeed"], values, default: [0.1, 0])
            p.scroll += SIMD2(speed.first ?? 0, speed.count > 1 ? speed[1] : 0)
        case "shake", "foliagesway":
            p.shakeSpeed = c(["speed"], 1)
            p.shakeStrength += c(["strength", "amount"], 0.1)
        case "waterripple":
            p.rippleSpeed = c(["speed", "ripplespeed"], 1)
            p.rippleScale = c(["scale", "ripplescale"], 1)
            p.rippleStrength += c(["strength", "ripplestrength"], 0.1)
        case "waterwaves":
            p.waveSpeed = c(["speed"], 1)
            p.waveScale = c(["scale"], 1)
            p.waveStrength += c(["strength"], 0.1)
        case "pulse":
            p.pulseSpeed = c(["speed"], 1)
            p.pulseAmount += c(["amount", "strength"], 0.5)
        case "tint":
            let color = vector(effect, ["color", "tint"], values, default: [1, 1, 1])
            p.tint = SIMD3(color.first ?? 1, color.count > 1 ? color[1] : 1, color.count > 2 ? color[2] : 1)
            p.tintAmount = c(["alpha", "amount", "strength"], 1)
        case "opacity":
            p.opacity *= c(["alpha", "opacity"], 1)
        case "blur":
            p.blurRadius = max(p.blurRadius, c(["scale", "radius", "amount"], 1))
        default:
            break
        }
    }
}
