import Foundation
import OWCore

/// Wraps a user's Shadertoy-style MSL function into a complete Metal library source.
///
/// User contract (documented in `docs/shaders.md`):
/// ```metal
/// float4 mainImage(float2 fragCoord, constant OWUniforms& u) { ... }
/// ```
/// Available: `u.iResolution`, `u.iTime`, `u.iTimeDelta`, `u.iFrame`, `u.iMouse`, `u.iDate`,
/// `owAudio(u, band)` (0...63) and one `prop_<key>` macro (a `float4`) per user property.
public enum ShaderSourceBuilder {
    public static let maxProperties = 16
    public static let fileName = "wallpaper.metal"
    public static let vertexFunction = "ow_vertex"
    public static let fragmentFunction = "ow_fragment"

    public static let prelude = """
    #include <metal_stdlib>
    using namespace metal;

    struct OWUniforms {
        packed_float3 iResolution;
        float iTime;
        float iTimeDelta;
        int iFrame;
        float2 _owPad;
        float4 iMouse;
        float4 iDate;
        float4 iAudio[16];
        float4 props[16];
    };

    static inline float owAudio(constant OWUniforms& u, int band) {
        band = clamp(band, 0, 63);
        return u.iAudio[band / 4][band % 4];
    }

    """

    public static let epilogue = """

    struct OWVertexOut { float4 position [[position]]; };

    vertex OWVertexOut ow_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        OWVertexOut out;
        out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    fragment float4 ow_fragment(OWVertexOut in [[stage_in]], constant OWUniforms& u [[buffer(0)]]) {
        float2 fragCoord = float2(in.position.x, u.iResolution.y - in.position.y);
        return mainImage(fragCoord, u);
    }
    """

    public static func build(userSource: String, properties: [PropertyDefinition]) -> String {
        prelude + propertyMacros(properties) + "#line 1 \"\(fileName)\"\n" + userSource + "\n" + epilogue
    }

    /// Property slots in definition order; keys that are not valid identifiers are skipped.
    public static func propertySlots(_ properties: [PropertyDefinition]) -> [(key: String, slot: Int)] {
        properties.map(\.key).filter(isIdentifier).prefix(maxProperties).enumerated().map { ($1, $0) }
    }

    static func propertyMacros(_ properties: [PropertyDefinition]) -> String {
        propertySlots(properties).map { "#define prop_\($0.key) (u.props[\($0.slot)])\n" }.joined()
    }

    static func isIdentifier(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, key.count <= 64 else { return false }
        let letters = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))
        let body = letters.union(.decimalDigits)
        return key.unicodeScalars.allSatisfy { $0.isASCII && body.contains($0) } && letters.contains(first)
    }

    /// Extracts the first error's user line number from Metal compiler output.
    public static func parseCompileError(_ message: String) -> RenderError {
        let lines = message.split(separator: "\n").map(String.init)
        let errorLine = lines.first { $0.contains("error:") } ?? lines.first ?? message
        let pattern = "\(fileName):([0-9]+):"
        var lineNumber: Int?
        if let range = errorLine.range(of: pattern, options: .regularExpression) {
            let match = errorLine[range].dropFirst(fileName.count + 1).dropLast()
            lineNumber = Int(match)
        }
        let text = errorLine.components(separatedBy: "error:").last?.trimmingCharacters(in: .whitespaces) ?? errorLine
        return .compile(line: lineNumber, message: text)
    }
}
