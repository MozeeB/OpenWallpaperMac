import Foundation
import OWCore

/// CPU mirror of `OWUniforms` in `ShaderSourceBuilder.prelude`, packed as 144 floats (576 bytes).
///
/// Layout: iResolution(3) iTime(1) iTimeDelta(1) iFrame(1, Int32 bits) pad(2) iMouse(4) iDate(4)
/// iAudio(64) props(64).
public struct ShaderUniforms: Equatable, Sendable {
    public static let floatCount = 144
    public static let byteCount = floatCount * MemoryLayout<Float>.stride

    public var resolution: SIMD3<Float> = .zero
    public var time: Float = 0
    public var timeDelta: Float = 0
    public var frame: Int32 = 0
    public var mouse: SIMD4<Float> = .zero
    public var date: SIMD4<Float> = .zero
    public var audio: [Float] = []
    public var properties: [SIMD4<Float>] = []

    public init() {}

    public func packed() -> [Float] {
        var output: [Float] = [resolution.x, resolution.y, resolution.z, time, timeDelta,
                               Float(bitPattern: UInt32(bitPattern: frame)), 0, 0]
        output += [mouse.x, mouse.y, mouse.z, mouse.w, date.x, date.y, date.z, date.w]
        output += ShaderUniforms.fixed(audio, count: 64)
        let props = properties.prefix(16).flatMap { [$0.x, $0.y, $0.z, $0.w] }
        output += ShaderUniforms.fixed(props, count: 64)
        return output
    }

    static func fixed(_ values: [Float], count: Int) -> [Float] {
        Array(values.prefix(count)) + Array(repeating: 0, count: max(count - values.count, 0))
    }

    /// Converts property values to `float4` slots matching `ShaderSourceBuilder.propertySlots`.
    public static func propertyVectors(_ definitions: [PropertyDefinition], values: PropertyValues) -> [SIMD4<Float>] {
        ShaderSourceBuilder.propertySlots(definitions).map { entry in
            vector(values[entry.key])
        }
    }

    static func vector(_ value: PropertyValue?) -> SIMD4<Float> {
        switch value {
        case .color(let color): return SIMD4(Float(color.red), Float(color.green), Float(color.blue), 1)
        case .number(let number): return SIMD4(Float(number), 0, 0, 0)
        case .bool(let flag): return SIMD4(flag ? 1 : 0, 0, 0, 0)
        case .string(let text): return SIMD4(Float(text) ?? 0, 0, 0, 0)
        case nil: return .zero
        }
    }

    /// `iDate`: year, month, day, seconds since midnight (Shadertoy convention).
    public static func dateVector(_ date: Date, calendar: Calendar = .current) -> SIMD4<Float> {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        let seconds = Float((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0))
            + Float(parts.nanosecond ?? 0) / 1e9
        return SIMD4(Float(parts.year ?? 0), Float(parts.month ?? 1) - 1, Float(parts.day ?? 1), seconds)
    }
}
