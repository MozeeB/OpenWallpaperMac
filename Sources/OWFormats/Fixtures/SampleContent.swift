import Foundation

/// Original, MIT-licensed sample content bundled with the app.
public enum SampleContent {
    public static let plasmaShader = """
    // Plasma — sample OpenWallpaperMac shader (MIT). Reacts to audio when enabled.
    float4 mainImage(float2 fragCoord, constant OWUniforms& u) {
        float2 uv = fragCoord / u.iResolution.xy;
        float t = u.iTime * prop_speed.x;
        float bass = owAudio(u, 2);
        float v = sin(uv.x * 10.0 + t) + sin(uv.y * 10.0 + t * 1.3) + sin((uv.x + uv.y) * 8.0 + t * 0.7);
        float3 color = 0.5 + 0.5 * cos(v + float3(0.0, 2.0, 4.0) + bass * 3.0);
        return float4(mix(color, prop_tint.rgb, 0.25), 1.0);
    }
    """

    public static func plasmaShaderFiles() -> [(String, Data)] {
        let manifest = """
        {
          "title": "Plasma",
          "type": "shader",
          "entry": "plasma.metal",
          "usesAudio": true,
          "properties": {
            "speed": { "type": "slider", "text": "Speed", "value": 0.6, "min": 0, "max": 3, "step": 0.1, "order": 0 },
            "tint": { "type": "color", "text": "Tint", "value": "0.2 0.4 1", "order": 1 }
          }
        }
        """
        return [("wallpaper.json", Data(manifest.utf8)), ("plasma.metal", Data(plasmaShader.utf8))]
    }
}
