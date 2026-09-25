import Foundation
import Metal
import OWCore

/// A compiled user shader plus its time/uniform state. Encodes a full-screen triangle per frame.
@MainActor
public final class ShaderProgram: FrameDrawing {
    public let pipeline: any MTLRenderPipelineState
    public let definitions: [PropertyDefinition]
    public private(set) var uniforms = ShaderUniforms()
    public var clearColor: MTLClearColor { MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1) }
    private let dateProvider: () -> Date

    init(pipeline: any MTLRenderPipelineState, definitions: [PropertyDefinition], dateProvider: @escaping () -> Date) {
        self.pipeline = pipeline
        self.definitions = definitions
        self.dateProvider = dateProvider
    }

    /// Compiles `source` (user MSL) into a program.
    public static func compile(
        source: String, definitions: [PropertyDefinition], context: MetalContext,
        dateProvider: @escaping () -> Date = Date.init
    ) async throws(RenderError) -> ShaderProgram {
        let full = ShaderSourceBuilder.build(userSource: source, properties: definitions)
        let library = try await context.makeLibrary(source: full)
        let pipeline = try context.makePipeline(
            library: library, vertex: ShaderSourceBuilder.vertexFunction, fragment: ShaderSourceBuilder.fragmentFunction
        )
        return ShaderProgram(pipeline: pipeline, definitions: definitions, dateProvider: dateProvider)
    }

    public func apply(_ values: PropertyValues) {
        uniforms.properties = ShaderUniforms.propertyVectors(definitions, values: definitions.resolve(values))
    }

    public func receive(_ spectrum: AudioSpectrum) {
        uniforms.audio = spectrum.average
    }

    public var elapsed: Float { uniforms.time }

    public func encodeFrame(into encoder: any MTLRenderCommandEncoder, size: CGSize, delta: Float) {
        let clamped = min(max(delta, 0), 0.25)
        uniforms.time += clamped
        uniforms.timeDelta = clamped
        uniforms.frame &+= 1
        uniforms.resolution = SIMD3(Float(size.width), Float(size.height), 1)
        uniforms.date = ShaderUniforms.dateVector(dateProvider())
        let packed = uniforms.packed()
        encoder.setRenderPipelineState(pipeline)
        packed.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            encoder.setFragmentBytes(base, length: raw.count, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
