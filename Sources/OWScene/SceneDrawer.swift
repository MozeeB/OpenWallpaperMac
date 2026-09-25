import Metal
import OWCore
import OWFormats
import OWRendering
import simd

/// Encodes a `SceneGraph` each frame: image layers with native effects, then particles, in scene order.
@MainActor
public final class SceneDrawer: FrameDrawing {
    public let graph: SceneGraph
    public private(set) var time: Float = 0
    public private(set) var camera: SceneCamera
    public var cursorProvider: (() -> SIMD2<Float>?)?

    private let pipelines: ScenePipelines
    private let device: any MTLDevice
    private var values: PropertyValues = [:]
    private var effects: [Int: EffectParameters] = [:]
    private var simulators: [Int: ParticleSimulator] = [:]
    private var particleBuffers: [Int: ParticleBufferRing] = [:]
    private var scratch: [Float] = []

    public var clearColor: MTLClearColor {
        let color = graph.general.clearColor
        return MTLClearColor(red: Double(color.x), green: Double(color.y), blue: Double(color.z), alpha: 1)
    }

    public init(graph: SceneGraph, pipelines: ScenePipelines, device: any MTLDevice, fill: FillMode, seed: UInt64 = 1) {
        self.graph = graph
        self.pipelines = pipelines
        self.device = device
        camera = SceneCamera(general: graph.general, fill: fill)
        for (index, node) in graph.nodes.enumerated() {
            guard case .particle(let particle) = node else { continue }
            let origin = particle.layer.transform.origin
            simulators[index] = ParticleSimulator(system: particle.system, origin: SIMD2(origin.x, origin.y), seed: seed &+ UInt64(index))
            particleBuffers[index] = ParticleBufferRing(device: device, maxParticles: particle.system.maxCount)
        }
        apply([:])
    }

    /// Whether frames change over time. Static scenes render once and stop the frame loop.
    public var isAnimated: Bool {
        if camera.parallaxEnabled || !simulators.isEmpty { return true }
        return graph.nodes.contains { node in
            guard case .image(let image) = node else { return false }
            return image.texture.isAnimated
        } || effects.values.contains(where: \.isAnimated)
    }

    public func apply(_ newValues: PropertyValues) {
        values = newValues
        effects = [:]
        for (index, node) in graph.nodes.enumerated() {
            guard case .image(let image) = node else { continue }
            effects[index] = EffectRegistry.parameters(for: image.layer.effects, values: values)
        }
    }

    public func encodeFrame(into encoder: any MTLRenderCommandEncoder, size: CGSize, delta: Float) {
        let dt = min(max(delta, 0), 0.25)
        time += dt
        if let cursor = cursorProvider?() { camera.updateCursor(target: cursor, delta: dt) }
        let projection = camera.projection(viewport: size)
        encoder.setFragmentSamplerState(pipelines.sampler, index: 0)
        for (index, node) in graph.nodes.enumerated() {
            switch node {
            case .image(let image):
                drawImage(image, index: index, projection: projection, encoder: encoder)
            case .particle(let particle):
                drawParticles(particle, index: index, delta: dt, projection: projection, encoder: encoder)
            }
        }
    }

    private func drawImage(_ node: ImageNode, index: Int, projection: simd_float4x4, encoder: any MTLRenderCommandEncoder) {
        let layer = node.layer
        guard layer.visible.bool(values) else { return }
        let effect = effects[index] ?? EffectParameters()
        let transform = layer.transform
        let offset = camera.parallaxOffset(depth: transform.parallaxDepth)
        let model = SceneMath.model(
            origin: SIMD2(transform.origin.x, transform.origin.y) + offset, size: node.size,
            scale: SIMD2(transform.scale.x, transform.scale.y), angle: transform.angles.z
        )
        let color = layer.color.vec3(values, default: .one)
        let alpha = layer.alpha.scalar(values, default: 1) * effect.opacity
        let uniforms = LayerUniformPacker.pack(
            mvp: projection * model, color: SIMD4(color.x, color.y, color.z, alpha),
            uvRect: node.texture.uvRect(at: time), effect: effect, time: time
        )
        encoder.setRenderPipelineState(pipelines.layerPipeline(node.blending))
        uniforms.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 0) }
        uniforms.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.setFragmentTexture(node.texture.texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func drawParticles(
        _ node: ParticleNode, index: Int, delta: Float, projection: simd_float4x4, encoder: any MTLRenderCommandEncoder
    ) {
        guard var simulator = simulators[index], let ring = particleBuffers[index] else { return }
        simulator.update(delta: delta)
        simulators[index] = simulator
        guard node.layer.visible.bool(values), !simulator.particles.isEmpty else { return }
        simulator.writeInstanceData(into: &scratch)
        guard let buffer = ring.next(copying: scratch) else { return }
        var matrix = projection * SceneMath.translation(
            camera.parallaxOffset(depth: node.layer.transform.parallaxDepth).x,
            camera.parallaxOffset(depth: node.layer.transform.parallaxDepth).y
        )
        encoder.setRenderPipelineState(pipelines.particlePipeline(node.blending))
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&matrix, length: MemoryLayout<simd_float4x4>.stride, index: 1)
        encoder.setFragmentTexture(node.texture.texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: simulator.particles.count)
    }

    public func particleCount(at index: Int) -> Int {
        simulators[index]?.particles.count ?? 0
    }
}

/// Packs `LayerUniforms` (see `SceneShaderSource`) as 44 floats.
enum LayerUniformPacker {
    static let floatCount = 44

    static func pack(mvp: simd_float4x4, color: SIMD4<Float>, uvRect: SIMD4<Float>, effect: EffectParameters, time: Float) -> [Float] {
        var output: [Float] = []
        output.reserveCapacity(floatCount)
        for column in [mvp.columns.0, mvp.columns.1, mvp.columns.2, mvp.columns.3] {
            output += [column.x, column.y, column.z, column.w]
        }
        output += [color.x, color.y, color.z, color.w, uvRect.x, uvRect.y, uvRect.z, uvRect.w]
        output += [effect.scroll.x, effect.scroll.y, effect.shakeSpeed, effect.shakeStrength]
        output += [effect.rippleSpeed, effect.rippleScale, effect.rippleStrength, 0]
        output += [effect.waveSpeed, effect.waveScale, effect.waveStrength, 0]
        output += [effect.tint.x, effect.tint.y, effect.tint.z, effect.tintAmount]
        output += [time, effect.pulseSpeed, effect.pulseAmount, effect.blurRadius]
        return output
    }
}

/// Three rotating instance buffers so the CPU never writes a buffer the GPU is still reading.
final class ParticleBufferRing {
    private let buffers: [any MTLBuffer]
    private var index = 0

    init?(device: any MTLDevice, maxParticles: Int) {
        let length = max(maxParticles, 1) * 8 * MemoryLayout<Float>.stride
        let made = (0 ..< 3).compactMap { _ in device.makeBuffer(length: length, options: .storageModeShared) }
        guard made.count == 3 else { return nil }
        buffers = made
    }

    func next(copying values: [Float]) -> (any MTLBuffer)? {
        index = (index + 1) % buffers.count
        let buffer = buffers[index]
        let bytes = values.count * MemoryLayout<Float>.stride
        guard bytes <= buffer.length else { return nil }
        values.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: bytes) }
        return buffer
    }
}
