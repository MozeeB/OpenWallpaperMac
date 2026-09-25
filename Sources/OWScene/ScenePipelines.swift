import Metal
import OWFormats
import OWRendering

/// Compiled pipelines for scene layers and particles (compiled once per process).
public final class ScenePipelines: @unchecked Sendable {
    public let layerTranslucent: any MTLRenderPipelineState
    public let layerAdditive: any MTLRenderPipelineState
    public let layerOpaque: any MTLRenderPipelineState
    public let particleTranslucent: any MTLRenderPipelineState
    public let particleAdditive: any MTLRenderPipelineState
    public let sampler: any MTLSamplerState
    public let white: SceneTexture
    public let dot: SceneTexture

    init(context: MetalContext, library: any MTLLibrary) throws(RenderError) {
        let make = { (vertex: String, fragment: String, blend: Bool, additive: Bool) throws(RenderError) in
            try context.makePipeline(library: library, vertex: vertex, fragment: fragment, blending: blend, additive: additive)
        }
        layerTranslucent = try make("layer_vertex", "layer_fragment", true, false)
        layerAdditive = try make("layer_vertex", "layer_fragment", true, true)
        layerOpaque = try make("layer_vertex", "layer_fragment", false, false)
        particleTranslucent = try make("particle_vertex", "particle_fragment", true, false)
        particleAdditive = try make("particle_vertex", "particle_fragment", true, true)
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        guard let sampler = context.device.makeSamplerState(descriptor: descriptor) else { throw .metalUnavailable }
        self.sampler = sampler
        white = try TextureUploader.white(device: context.device)
        dot = try TextureUploader.softDot(device: context.device)
    }

    @MainActor private static var cache: ScenePipelines?

    @MainActor
    public static func shared(context: MetalContext) async throws(RenderError) -> ScenePipelines {
        if let cache { return cache }
        let library = try await context.makeLibrary(source: SceneShaderSource.source)
        let pipelines = try ScenePipelines(context: context, library: library)
        cache = pipelines
        return pipelines
    }

    public func layerPipeline(_ blending: Blending) -> any MTLRenderPipelineState {
        switch blending {
        case .additive: return layerAdditive
        case .disabled: return layerOpaque
        case .normal, .translucent: return layerTranslucent
        }
    }

    public func particlePipeline(_ blending: Blending) -> any MTLRenderPipelineState {
        blending == .additive ? particleAdditive : particleTranslucent
    }
}

/// Our own MSL for scene layers (one pass, all native effects) and instanced particles.
enum SceneShaderSource {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct LayerUniforms {
        float4x4 mvp;
        float4 color;        // rgb multiplier, alpha
        float4 uvRect;       // offset.xy, scale.zw
        float4 scrollShake;  // scroll.xy, shake speed, shake strength
        float4 ripple;       // speed, scale, strength, -
        float4 waves;        // speed, scale, strength, -
        float4 tint;         // rgb, amount
        float4 misc;         // time, pulse speed, pulse amount, blur radius
    };

    struct LayerOut { float4 position [[position]]; float2 uv; };

    vertex LayerOut layer_vertex(uint vid [[vertex_id]], constant LayerUniforms& u [[buffer(0)]]) {
        float2 corner = float2(vid & 1, (vid >> 1) & 1);
        LayerOut out;
        out.position = u.mvp * float4(corner - 0.5, 0.0, 1.0);
        out.uv = float2(corner.x, 1.0 - corner.y);
        return out;
    }

    static float2 distort(float2 uv, constant LayerUniforms& u) {
        float t = u.misc.x;
        uv += u.scrollShake.xy * t;
        if (u.scrollShake.w != 0.0) {
            uv += float2(sin(t * u.scrollShake.z * 3.1), cos(t * u.scrollShake.z * 2.3)) * u.scrollShake.w * 0.02;
        }
        if (u.ripple.z != 0.0) {
            float2 d = uv - 0.5;
            float r = length(d);
            float2 dir = r > 0.0001 ? d / r : float2(0.0);
            uv += dir * sin(r * u.ripple.y * 60.0 - t * u.ripple.x * 4.0) * u.ripple.z * 0.01;
        }
        if (u.waves.z != 0.0) {
            uv.x += sin(uv.y * u.waves.y * 20.0 + t * u.waves.x * 2.0) * u.waves.z * 0.01;
        }
        return uv;
    }

    static float4 sampleLayer(texture2d<float> tex, sampler s, float2 uv, constant LayerUniforms& u) {
        bool scrolling = u.scrollShake.x != 0.0 || u.scrollShake.y != 0.0;
        float2 wrapped = scrolling ? fract(uv) : clamp(uv, 0.0, 1.0);
        float2 texUV = u.uvRect.xy + wrapped * u.uvRect.zw;
        float radius = u.misc.w;
        if (radius <= 0.0) { return tex.sample(s, texUV); }
        float2 stepUV = radius * 0.002 * u.uvRect.zw;
        float4 acc = float4(0.0);
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) { acc += tex.sample(s, texUV + float2(x, y) * stepUV); }
        }
        return acc / 9.0;
    }

    fragment float4 layer_fragment(LayerOut in [[stage_in]], constant LayerUniforms& u [[buffer(0)]],
                                   texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]]) {
        float4 c = sampleLayer(tex, s, distort(in.uv, u), u);
        c.rgb = mix(c.rgb, c.rgb * u.tint.rgb, u.tint.a);
        c.rgb *= u.color.rgb;
        float pulse = 1.0 - u.misc.z * (0.5 + 0.5 * sin(u.misc.x * u.misc.y * 3.0));
        c.a *= u.color.a * clamp(pulse, 0.0, 1.0);
        return c;
    }

    struct ParticleInstance { float2 position; float size; float rotation; float4 color; };
    struct ParticleOut { float4 position [[position]]; float2 uv; float4 color; };

    vertex ParticleOut particle_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                       const device ParticleInstance* instances [[buffer(0)]],
                                       constant float4x4& projection [[buffer(1)]]) {
        ParticleInstance p = instances[iid];
        float2 corner = float2(vid & 1, (vid >> 1) & 1) - 0.5;
        float c = cos(p.rotation);
        float s = sin(p.rotation);
        float2 local = float2(corner.x * c - corner.y * s, corner.x * s + corner.y * c) * p.size;
        ParticleOut out;
        out.position = projection * float4(p.position + local, 0.0, 1.0);
        out.uv = corner + 0.5;
        out.color = p.color;
        return out;
    }

    fragment float4 particle_fragment(ParticleOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                      sampler s [[sampler(0)]]) {
        return tex.sample(s, in.uv) * in.color;
    }
    """
}
