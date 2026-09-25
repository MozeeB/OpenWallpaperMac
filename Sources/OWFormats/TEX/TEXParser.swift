import Foundation
import OWCore

/// Parses `.tex` textures. Layout documented in `docs/formats/tex.md`:
///
/// `TEXV####\0` `TEXI####\0` header(7×Int32) → `TEXB####\0` image container → optional
/// `TEXS####\0` frame container for animated textures.
public enum TEXParser {
    static let magicLimit = 16

    /// - Parameter byteBudget: maximum total decoded bytes across all images and mipmaps.
    public static func parse(_ data: Data, byteBudget: Int = Limits.maxBytesPerTexture) throws(TEXError) -> TEXTexture {
        var reader = BinaryReader(data)
        do {
            try expectMagic(&reader, prefix: "TEXV")
            try expectMagic(&reader, prefix: "TEXI")
            let header = try readHeader(&reader)
            let version = try containerVersion(try reader.nullTerminatedString(limit: magicLimit))
            let container = try readContainerHeader(&reader, version: version, format: header.format)
            var budget = byteBudget
            let images = try readImages(&reader, version: version, container: container, budget: &budget)
            let frames = header.flags.contains(.isGif) ? try readFrames(&reader) : []
            return TEXTexture(
                header: header, containerVersion: version, payload: container.payload,
                images: images, frames: frames
            )
        } catch let error as TEXError {
            throw error
        } catch let error as BinaryReaderError {
            throw .truncated(error)
        } catch {
            throw .imageDecodeFailed
        }
    }

    private static func expectMagic(_ reader: inout BinaryReader, prefix: String) throws {
        let magic = try reader.nullTerminatedString(limit: magicLimit)
        guard magic.count == 8, magic.hasPrefix(prefix), magic.dropFirst(4).allSatisfy(\.isNumber) else {
            throw TEXError.invalidMagic(expected: prefix, found: magic)
        }
    }

    private static func readHeader(_ reader: inout BinaryReader) throws -> TEXHeader {
        let format = try reader.int32()
        let flags = TEXFlags(rawValue: try reader.int32())
        let dims = try (0 ..< 4).map { _ in Int(try reader.int32()) }
        _ = try reader.uint32()
        for value in dims where value < 0 || value > Limits.maxTextureDimension {
            throw TEXError.invalidDimensions(width: dims[0], height: dims[1])
        }
        return TEXHeader(
            format: format, flags: flags,
            textureWidth: dims[0], textureHeight: dims[1], imageWidth: dims[2], imageHeight: dims[3]
        )
    }

    static func containerVersion(_ magic: String) throws(TEXError) -> Int {
        guard magic.count == 8, magic.hasPrefix("TEXB"), let version = Int(magic.dropFirst(4)),
              (1 ... 4).contains(version)
        else { throw .unsupportedContainer(magic) }
        return version
    }

    private struct ContainerHeader {
        let imageCount: Int
        let payload: TEXPayload
    }

    private static func readContainerHeader(
        _ reader: inout BinaryReader, version: Int, format: Int32
    ) throws -> ContainerHeader {
        let imageCount = Int(try reader.int32())
        guard imageCount > 0 else { throw TEXError.noImages }
        guard imageCount <= Limits.maxTextureImages else { throw TEXError.tooManyImages(imageCount) }
        let imageFormat: Int32 = version >= 3 ? try reader.int32() : -1
        let isMP4 = version == 4 ? try reader.int32() == 1 : false
        if isMP4 && imageFormat == -1 { return ContainerHeader(imageCount: imageCount, payload: .mp4) }
        if imageFormat != -1 { return ContainerHeader(imageCount: imageCount, payload: .encodedImage(imageFormat)) }
        guard let raw = TEXFormat(rawValue: format) else { throw TEXError.unsupportedFormat(format) }
        return ContainerHeader(imageCount: imageCount, payload: .raw(raw))
    }

    private static func readImages(
        _ reader: inout BinaryReader, version: Int, container: ContainerHeader, budget: inout Int
    ) throws -> [TEXImage] {
        try (0 ..< container.imageCount).map { _ in
            let mipCount = Int(try reader.int32())
            guard mipCount >= 0, mipCount <= Limits.maxTextureMipmaps else {
                throw TEXError.tooManyMipmaps(mipCount)
            }
            let mipmaps = try (0 ..< mipCount).map { _ in
                try readMipmap(&reader, version: version, payload: container.payload, budget: &budget)
            }
            return TEXImage(mipmaps: mipmaps)
        }
    }

    private static func readMipmap(
        _ reader: inout BinaryReader, version: Int, payload: TEXPayload, budget: inout Int
    ) throws -> TEXMipmap {
        if version == 4 {
            // Version 4 prefixes each mipmap with two markers, a condition string and a third marker.
            _ = try reader.int32()
            _ = try reader.int32()
            _ = try reader.nullTerminatedString(limit: 4096)
            _ = try reader.int32()
        }
        let width = Int(try reader.int32())
        let height = Int(try reader.int32())
        guard (0 ... Limits.maxTextureDimension).contains(width), (0 ... Limits.maxTextureDimension).contains(height) else {
            throw TEXError.invalidDimensions(width: width, height: height)
        }
        var compressed = false
        var decompressedSize = 0
        if version >= 2 {
            compressed = try reader.int32() == 1
            decompressedSize = try reader.length(limit: Limits.maxDecompressedBytes)
        }
        let byteCount = try reader.length(limit: Limits.maxDecompressedBytes)
        // Charge the output size against the per-texture budget *before* allocating it.
        let outputSize = compressed ? decompressedSize : byteCount
        guard outputSize <= budget else { throw TEXError.textureTooLarge(limit: budget) }
        budget -= outputSize
        let raw = try reader.bytes(byteCount)
        let bytes = compressed ? try LZ4Block.decompress(raw, expectedSize: decompressedSize) : raw
        if case .raw(let format) = payload {
            let expected = format.byteCount(width: width, height: height)
            guard bytes.count >= expected else { throw TEXError.payloadTooSmall(expected: expected, actual: bytes.count) }
        }
        return TEXMipmap(width: width, height: height, data: bytes)
    }

    private static func readFrames(_ reader: inout BinaryReader) throws -> [TEXFrame] {
        let magic = try reader.nullTerminatedString(limit: magicLimit)
        guard magic.hasPrefix("TEXS"), let version = Int(magic.dropFirst(4)), (1 ... 3).contains(version) else {
            throw TEXError.unsupportedContainer(magic)
        }
        let count = Int(try reader.int32())
        guard count >= 0, count <= Limits.maxTextureImages else { throw TEXError.tooManyImages(count) }
        if version == 3 {
            _ = try reader.int32()
            _ = try reader.int32()
        }
        return try (0 ..< count).map { _ in try readFrame(&reader, version: version) }
    }

    private static func readFrame(_ reader: inout BinaryReader, version: Int) throws -> TEXFrame {
        let imageIndex = Int(try reader.int32())
        let frameTime = try reader.float32()
        func value() throws -> Float { version == 1 ? Float(try reader.int32()) : try reader.float32() }
        let x = try value()
        let y = try value()
        let width = try value()
        _ = try value()
        _ = try value()
        let height = try value()
        return TEXFrame(imageIndex: imageIndex, frameTime: frameTime, x: x, y: y, width: width, height: height)
    }
}
