import Metal
import OWCore
import OWFormats
import OWRendering

/// A renderable image layer with its GPU texture.
public struct ImageNode: @unchecked Sendable {
    public let layer: SceneImageLayer
    public let texture: SceneTexture
    public let blending: Blending
    public let size: SIMD2<Float>
}

/// A particle system layer.
public struct ParticleNode: @unchecked Sendable {
    public let layer: SceneParticleLayer
    public let system: ParticleSystemDocument
    public let texture: SceneTexture
    public let blending: Blending
}

public enum SceneNode: @unchecked Sendable {
    case image(ImageNode)
    case particle(ParticleNode)
}

/// Resolved, GPU-ready scene.
public struct SceneGraph: @unchecked Sendable {
    public let general: SceneGeneral
    public let nodes: [SceneNode]
    public let report: SupportReport
}

/// Loads textures and resolves layer sizes. Missing textures skip the layer (already reported).
public enum SceneGraphBuilder {
    public static func build(
        entry: SanitizedPath, assets: any AssetSource, device: any MTLDevice, pipelines: ScenePipelines
    ) throws(RenderError) -> SceneGraph {
        let loaded: LoadedScene
        do {
            loaded = try SceneLoader.load(entry: entry, from: assets)
        } catch {
            throw .invalidAsset("scene: \(error)")
        }
        let report = SceneSupportAnalyzer.analyze(loaded, knownEffects: EffectRegistry.known)
        guard report.level != .previewOnly else { throw .unsupported(.scene) }
        var cache: [String: SceneTexture] = [:]
        let nodes = loaded.layers.compactMap { layer -> SceneNode? in
            switch layer {
            case .image(let image):
                return imageNode(image, general: loaded.general, assets: assets, device: device, pipelines: pipelines, cache: &cache)
                    .map(SceneNode.image)
            case .particle(let particle):
                let sprite = particle.texture.flatMap {
                    SceneGraphBuilder.texture(at: $0, assets: assets, device: device, cache: &cache)
                } ?? pipelines.dot
                return .particle(ParticleNode(
                    layer: particle.layer, system: particle.system, texture: sprite,
                    blending: particle.material?.blending ?? .additive
                ))
            }
        }
        return SceneGraph(general: loaded.general, nodes: nodes, report: report)
    }

    static func imageNode(
        _ image: LoadedImageLayer, general: SceneGeneral, assets: any AssetSource, device: any MTLDevice,
        pipelines: ScenePipelines, cache: inout [String: SceneTexture]
    ) -> ImageNode? {
        let texture: SceneTexture
        if let path = image.texture, let loaded = self.texture(at: path, assets: assets, device: device, cache: &cache) {
            texture = loaded
        } else if image.model.fullscreen {
            texture = pipelines.white
        } else {
            return nil
        }
        return ImageNode(
            layer: image.layer, texture: texture, blending: image.material?.blending ?? .translucent,
            size: size(for: image, texture: texture, general: general)
        )
    }

    /// Layer size: explicit `size`, else model dimensions, else the texture's image size.
    static func size(for image: LoadedImageLayer, texture: SceneTexture, general: SceneGeneral) -> SIMD2<Float> {
        if image.model.fullscreen { return SIMD2(general.width, general.height) }
        if let size = image.layer.size, size.x > 0, size.y > 0 { return SIMD2(size.x, size.y) }
        if let width = image.model.width, let height = image.model.height, width > 0, height > 0 {
            return SIMD2(width, height)
        }
        return texture.imageSize
    }

    static func texture(
        at path: SanitizedPath, assets: any AssetSource, device: any MTLDevice, cache: inout [String: SceneTexture]
    ) -> SceneTexture? {
        if let cached = cache[path.lookupKey] { return cached }
        guard let data = try? assets.data(at: path),
              let parsed = try? TEXParser.parse(data),
              let uploaded = try? TextureUploader.upload(parsed, device: device)
        else { return nil }
        cache[path.lookupKey] = uploaded
        return uploaded
    }
}
