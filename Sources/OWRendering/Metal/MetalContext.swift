import Metal
import OWFormats

/// One device and command queue shared by every GPU renderer in the process.
public final class MetalContext: @unchecked Sendable {
    public static let pixelFormat = MTLPixelFormat.bgra8Unorm

    public let device: any MTLDevice
    public let queue: any MTLCommandQueue

    public init?(device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        queue.label = "OpenWallpaperMac"
    }

    public static let shared: MetalContext? = MetalContext()

    /// Compiles MSL source off the main thread.
    public func makeLibrary(source: String) async throws(RenderError) -> any MTLLibrary {
        let options = MTLCompileOptions()
        options.mathMode = .fast
        do {
            return try await device.makeLibrary(source: source, options: options)
        } catch {
            throw ShaderSourceBuilder.parseCompileError(String(describing: error))
        }
    }

    public func makePipeline(
        library: any MTLLibrary, vertex: String, fragment: String, blending: Bool = false, additive: Bool = false
    ) throws(RenderError) -> any MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: vertex),
              let fragmentFunction = library.makeFunction(name: fragment)
        else { throw .compile(line: nil, message: "missing \(vertex) or \(fragment)") }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        guard let attachment = descriptor.colorAttachments[0] else { throw .metalUnavailable }
        attachment.pixelFormat = MetalContext.pixelFormat
        if blending {
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw .compile(line: nil, message: error.localizedDescription)
        }
    }

    /// Reads a BGRA texture back into an RGBA bitmap (Apple-silicon shared storage).
    public func readBack(_ texture: any MTLTexture) -> RGBABitmap {
        let width = texture.width
        let height = texture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        for index in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(index, index + 2) }
        return RGBABitmap(width: width, height: height, pixels: Data(bytes))
    }

    /// A render target texture readable from the CPU.
    public func makeOffscreenTexture(width: Int, height: Int) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalContext.pixelFormat, width: max(width, 1), height: max(height, 1), mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }
}

/// Anything that can encode one frame into a render pass (shaders, scenes).
@MainActor
public protocol FrameDrawing: AnyObject {
    /// Advances simulation/time by `delta` seconds and encodes a frame of the given pixel size.
    func encodeFrame(into encoder: any MTLRenderCommandEncoder, size: CGSize, delta: Float)
    var clearColor: MTLClearColor { get }
}

/// Renders frames off-screen; used for snapshots, `owctl render` and golden-image tests.
@MainActor
public enum OffscreenRenderer {
    public static func render(
        _ drawer: any FrameDrawing, context: MetalContext, width: Int, height: Int, frames: Int = 1, delta: Float = 1 / 30
    ) throws(RenderError) -> RGBABitmap {
        guard let texture = context.makeOffscreenTexture(width: width, height: height) else { throw .snapshotFailed }
        for _ in 0 ..< max(frames, 1) {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = drawer.clearColor
            guard let buffer = context.queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
            else { throw .snapshotFailed }
            drawer.encodeFrame(into: encoder, size: CGSize(width: width, height: height), delta: delta)
            encoder.endEncoding()
            buffer.commit()
            buffer.waitUntilCompleted()
            if buffer.status == .error { throw .gpuHang }
        }
        return context.readBack(texture)
    }
}
