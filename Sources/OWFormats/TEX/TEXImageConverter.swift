import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Tightly packed 8-bit RGBA pixels.
public struct RGBABitmap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: Data

    public init(width: Int, height: Int, pixels: Data) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public func pixel(x: Int, y: Int) -> [UInt8] {
        let start = pixels.startIndex + (y * width + x) * 4
        return Array(pixels[start ..< start + 4])
    }

    /// Crops to the visible image area (textures are stored padded to powers of two).
    public func cropped(width newWidth: Int, height newHeight: Int) -> RGBABitmap {
        let w = min(newWidth, width)
        let h = min(newHeight, height)
        guard w != width || h != height else { return self }
        var output = Data(capacity: w * h * 4)
        for row in 0 ..< h {
            let start = pixels.startIndex + row * width * 4
            output.append(pixels[start ..< start + w * 4])
        }
        return RGBABitmap(width: w, height: h, pixels: output)
    }

    public func makeCGImage() -> CGImage? {
        guard width > 0, height > 0, let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    public static func from(cgImage: CGImage) -> RGBABitmap? {
        let width = cgImage.width
        let height = cgImage.height
        var buffer = Data(count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? RGBABitmap(width: width, height: height, pixels: buffer) : nil
    }
}

public enum TEXImageConverter {
    /// Converts the primary mipmap to RGBA8, cropped to the visible image size.
    public static func bitmap(from texture: TEXTexture) throws(TEXError) -> RGBABitmap {
        guard let mip = texture.primaryMipmap else { throw .noImages }
        switch texture.payload {
        case .raw(let format):
            let full = RGBABitmap(width: mip.width, height: mip.height, pixels: try rgba(mip, format: format))
            let header = texture.header
            guard header.imageWidth > 0, header.imageHeight > 0 else { return full }
            return full.cropped(width: header.imageWidth, height: header.imageHeight)
        case .encodedImage:
            return try decodeEncoded(mip.data)
        case .mp4:
            throw .unsupportedFormat(-1)
        }
    }

    static func rgba(_ mip: TEXMipmap, format: TEXFormat) throws(TEXError) -> Data {
        let count = mip.width * mip.height
        switch format {
        case .rgba8888:
            return mip.data.prefix(count * 4)
        case .rg88:
            return expand(mip.data, pixels: count, stride: 2) { [$0[0], $0[0], $0[0], $0[1]] }
        case .r8:
            return expand(mip.data, pixels: count, stride: 1) { [$0[0], $0[0], $0[0], 255] }
        case .dxt1, .dxt3, .dxt5:
            return try BCnDecoder.decode(mip.data, format: format, width: mip.width, height: mip.height)
        }
    }

    private static func expand(_ data: Data, pixels: Int, stride: Int, _ map: ([UInt8]) -> [UInt8]) -> Data {
        let bytes = [UInt8](data.prefix(pixels * stride))
        var output = [UInt8]()
        output.reserveCapacity(pixels * 4)
        for index in 0 ..< pixels {
            output.append(contentsOf: map(Array(bytes[index * stride ..< index * stride + stride])))
        }
        return Data(output)
    }

    static func decodeEncoded(_ data: Data) throws(TEXError) -> RGBABitmap {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let bitmap = RGBABitmap.from(cgImage: image)
        else { throw .imageDecodeFailed }
        return bitmap
    }

    /// Writes a PNG file.
    public static func writePNG(_ bitmap: RGBABitmap, to url: URL) throws(TEXError) {
        guard
            let image = bitmap.makeCGImage(),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw .imageDecodeFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw .imageDecodeFailed }
    }
}
