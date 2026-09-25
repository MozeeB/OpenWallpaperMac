import Metal
import OWFormats
import OWRendering

/// A GPU texture plus the metadata needed to sample the visible image inside it.
public struct SceneTexture: @unchecked Sendable {
    public let texture: any MTLTexture
    /// Visible image size in pixels.
    public let imageSize: SIMD2<Float>
    /// Fraction of the (power-of-two) storage covered by the image.
    public let uvScale: SIMD2<Float>
    /// Sprite-sheet frames for animated textures (all within image 0).
    public let frames: [TEXFrame]
    public let storageSize: SIMD2<Float>

    public var isAnimated: Bool { frames.count > 1 }

    /// UV rect (offset.xy, scale.zw) for the frame showing at `time`.
    public func uvRect(at time: Float) -> SIMD4<Float> {
        guard isAnimated else { return SIMD4(0, 0, uvScale.x, uvScale.y) }
        let total = frames.reduce(Float(0)) { $0 + max($1.frameTime, 0.001) }
        var remaining = time.truncatingRemainder(dividingBy: max(total, 0.001))
        let frame = frames.first { frame in
            remaining -= max(frame.frameTime, 0.001)
            return remaining < 0
        } ?? frames[0]
        return SIMD4(frame.x / storageSize.x, frame.y / storageSize.y, frame.width / storageSize.x, frame.height / storageSize.y)
    }
}

/// Uploads parsed `.tex` textures. BCn data is uploaded still compressed (no CPU decode).
public enum TextureUploader {
    public static func upload(_ tex: TEXTexture, device: any MTLDevice) throws(RenderError) -> SceneTexture {
        switch tex.payload {
        case .raw(let format):
            return try uploadRaw(tex, format: format, device: device)
        case .encodedImage:
            let bitmap: RGBABitmap
            do {
                bitmap = try TEXImageConverter.bitmap(from: tex)
            } catch {
                throw .invalidAsset("texture image: \(error)")
            }
            return try upload(bitmap, device: device)
        case .mp4:
            throw .invalidAsset("video textures are not supported")
        }
    }

    public static func upload(_ bitmap: RGBABitmap, device: any MTLDevice) throws(RenderError) -> SceneTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: max(bitmap.width, 1), height: max(bitmap.height, 1), mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw .metalUnavailable }
        bitmap.pixels.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count >= bitmap.width * bitmap.height * 4 else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height), mipmapLevel: 0,
                            withBytes: base, bytesPerRow: bitmap.width * 4)
        }
        let size = SIMD2(Float(bitmap.width), Float(bitmap.height))
        return SceneTexture(texture: texture, imageSize: size, uvScale: SIMD2(1, 1), frames: [], storageSize: size)
    }

    static func pixelFormat(_ format: TEXFormat) -> MTLPixelFormat {
        switch format {
        case .rgba8888: return .rgba8Unorm
        case .dxt1: return .bc1_rgba
        case .dxt3: return .bc2_rgba
        case .dxt5: return .bc3_rgba
        case .rg88: return .rg8Unorm
        case .r8: return .r8Unorm
        }
    }

    static func bytesPerRow(_ format: TEXFormat, width: Int) -> Int {
        switch format {
        case .rgba8888: return width * 4
        case .rg88: return width * 2
        case .r8: return width
        case .dxt1: return ((width + 3) / 4) * 8
        case .dxt3, .dxt5: return ((width + 3) / 4) * 16
        }
    }

    private static func uploadRaw(_ tex: TEXTexture, format: TEXFormat, device: any MTLDevice) throws(RenderError) -> SceneTexture {
        guard let mipmaps = tex.images.first?.mipmaps, let base = mipmaps.first, base.width > 0, base.height > 0 else {
            throw .invalidAsset("texture has no image data")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat(format), width: base.width, height: base.height, mipmapped: false
        )
        descriptor.mipmapLevelCount = mipmaps.count
        descriptor.usage = .shaderRead
        switch format {
        case .r8: descriptor.swizzle = MTLTextureSwizzleChannels(red: .red, green: .red, blue: .red, alpha: .one)
        case .rg88: descriptor.swizzle = MTLTextureSwizzleChannels(red: .red, green: .red, blue: .red, alpha: .green)
        default: break
        }
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw .metalUnavailable }
        for (level, mip) in mipmaps.enumerated() where mip.width > 0 && mip.height > 0 {
            mip.data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                texture.replace(region: MTLRegionMake2D(0, 0, mip.width, mip.height), mipmapLevel: level,
                                withBytes: base, bytesPerRow: bytesPerRow(format, width: mip.width))
            }
        }
        let header = tex.header
        let imageWidth = Float(header.imageWidth > 0 ? header.imageWidth : base.width)
        let imageHeight = Float(header.imageHeight > 0 ? header.imageHeight : base.height)
        let storage = SIMD2(Float(base.width), Float(base.height))
        return SceneTexture(
            texture: texture, imageSize: SIMD2(imageWidth, imageHeight),
            uvScale: SIMD2(min(imageWidth / storage.x, 1), min(imageHeight / storage.y, 1)),
            frames: tex.frames.filter { $0.imageIndex == 0 }, storageSize: storage
        )
    }

    /// Soft round sprite used when a particle system has no texture.
    public static func softDot(device: any MTLDevice, size: Int = 32) throws(RenderError) -> SceneTexture {
        var pixels = Data(capacity: size * size * 4)
        let center = Float(size - 1) / 2
        for y in 0 ..< size {
            for x in 0 ..< size {
                let distance = hypot(Float(x) - center, Float(y) - center) / center
                let alpha = UInt8(max(0, min(1, 1 - distance)) * 255)
                pixels.append(contentsOf: [255, 255, 255, alpha])
            }
        }
        return try upload(RGBABitmap(width: size, height: size, pixels: pixels), device: device)
    }

    public static func white(device: any MTLDevice) throws(RenderError) -> SceneTexture {
        try upload(RGBABitmap(width: 1, height: 1, pixels: Data([255, 255, 255, 255])), device: device)
    }
}
