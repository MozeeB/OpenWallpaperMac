import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import OWCore
@testable import OWFormats

@Suite("TEX")
struct TEXTests {
    static let pixels2x2 = Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 128])

    @Test("parses RGBA across container versions", arguments: [1, 2, 3, 4])
    func rgba(version: Int) throws {
        var options = TEXWriter.Options()
        options.containerVersion = version
        let data = TEXWriter.build(format: .rgba8888, width: 2, height: 2, pixels: Self.pixels2x2, options: options)
        let texture = try TEXParser.parse(data)
        #expect(texture.containerVersion == version)
        #expect(texture.payload == .raw(.rgba8888))
        let bitmap = try TEXImageConverter.bitmap(from: texture)
        #expect(bitmap.pixel(x: 1, y: 0) == [0, 255, 0, 255])
        #expect(bitmap.pixel(x: 1, y: 1) == [255, 255, 255, 128])
    }

    @Test("LZ4-compressed payloads decompress")
    func lz4() throws {
        var options = TEXWriter.Options()
        options.compress = true
        let pixels = Data((0 ..< 64 * 64).flatMap { _ in [UInt8(10), 20, 30, 255] })
        let texture = try TEXParser.parse(TEXWriter.build(format: .rgba8888, width: 64, height: 64, pixels: pixels, options: options))
        #expect(texture.primaryMipmap?.data == pixels)
        #expect(throws: TEXError.decompressionFailed(expected: 10, actual: 0)) {
            try LZ4Block.decompress(Data([0xFF, 0xFF]), expectedSize: 10)
        }
        #expect(try LZ4Block.decompress(Data(), expectedSize: 0).isEmpty)
        #expect(throws: TEXError.self) { try LZ4Block.decompress(Data(), expectedSize: -1) }
        #expect(LZ4Block.compress(Data())?.isEmpty == true)
    }

    @Test("R8 and RG88 expand to RGBA")
    func grayscale() throws {
        let r8 = try TEXParser.parse(TEXWriter.build(format: .r8, width: 2, height: 1, pixels: Data([10, 200])))
        #expect(try TEXImageConverter.bitmap(from: r8).pixel(x: 1, y: 0) == [200, 200, 200, 255])
        let rg = try TEXParser.parse(TEXWriter.build(format: .rg88, width: 1, height: 1, pixels: Data([50, 60])))
        #expect(try TEXImageConverter.bitmap(from: rg).pixel(x: 0, y: 0) == [50, 50, 50, 60])
    }

    @Test("BC1 decodes opaque and transparent modes")
    func bc1() throws {
        let red: [UInt8] = [0x00, 0xF8, 0x1F, 0x00]
        let allIndex0 = Data(red + [0, 0, 0, 0])
        #expect(try BCnDecoder.decode(allIndex0, format: .dxt1, width: 4, height: 4).prefix(4) == Data([255, 0, 0, 255]))
        let allIndex2 = Data(red + [0xAA, 0xAA, 0xAA, 0xAA])
        #expect(try BCnDecoder.decode(allIndex2, format: .dxt1, width: 4, height: 4).prefix(4) == Data([170, 0, 85, 255]))
        let transparent = Data([0x1F, 0x00, 0x00, 0xF8, 0xFF, 0xFF, 0xFF, 0xFF])
        #expect(try BCnDecoder.decode(transparent, format: .dxt1, width: 4, height: 4).prefix(4) == Data([0, 0, 0, 0]))
        let texture = try TEXParser.parse(TEXWriter.build(format: .dxt1, width: 4, height: 4, pixels: allIndex0))
        #expect(try TEXImageConverter.bitmap(from: texture).pixel(x: 3, y: 3) == [255, 0, 0, 255])
    }

    @Test("BC2 and BC3 decode alpha")
    func bc23() throws {
        let color: [UInt8] = [0xFF, 0xFF, 0x00, 0x00, 0, 0, 0, 0]
        let bc3 = Data([255, 0, 0b0000_1001, 0, 0, 0, 0, 0] + color)
        let decoded3 = try BCnDecoder.decode(bc3, format: .dxt5, width: 4, height: 4)
        #expect(Array(decoded3.prefix(8)) == [255, 255, 255, 0, 255, 255, 255, 0])
        let smallAlpha = Data([0, 255, 0b0011_1111, 0, 0, 0, 0, 0] + color)
        #expect(try BCnDecoder.decode(smallAlpha, format: .dxt5, width: 4, height: 4)[3] == 255)
        let bc2 = Data([0xF0, 0, 0, 0, 0, 0, 0, 0] + color)
        let decoded2 = try BCnDecoder.decode(bc2, format: .dxt3, width: 4, height: 4)
        #expect(decoded2[3] == 0)
        #expect(decoded2[7] == 255)
        #expect(throws: TEXError.unsupportedFormat(0)) { try BCnDecoder.decode(Data(), format: .rgba8888, width: 4, height: 4) }
        #expect(throws: TEXError.payloadTooSmall(expected: 16, actual: 2)) { try BCnDecoder.decode(Data([1, 2]), format: .dxt5, width: 3, height: 3) }
    }

    @Test("embedded PNG payload decodes via ImageIO")
    func encodedImage() throws {
        let bitmap = RGBABitmap(width: 2, height: 2, pixels: Self.pixels2x2)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("owtex-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try TEXImageConverter.writePNG(bitmap, to: url)
        let texture = try TEXParser.parse(TEXWriter.buildEncoded(imageData: try Data(contentsOf: url), width: 2, height: 2))
        #expect(texture.payload == .encodedImage(13))
        let decoded = try TEXImageConverter.bitmap(from: texture)
        #expect(decoded.pixel(x: 0, y: 0) == [255, 0, 0, 255])
        #expect(throws: TEXError.imageDecodeFailed) { try TEXImageConverter.decodeEncoded(Data([1, 2, 3])) }
    }

    @Test("animated textures read frame tables")
    func frames() throws {
        var options = TEXWriter.Options()
        options.flags = .isGif
        var data = TEXWriter.build(format: .rgba8888, width: 2, height: 2, pixels: Self.pixels2x2, options: options)
        var writer = BinaryWriter()
        writer.nullTerminatedString("TEXS0003")
        writer.int32(1)
        writer.int32(2)
        writer.int32(2)
        writer.int32(0)
        [0.1, 0, 0, 2, 0, 0, 2].forEach { writer.float32(Float($0)) }
        data.append(writer.data)
        let texture = try TEXParser.parse(data)
        #expect(texture.isAnimated)
        #expect(texture.frames.first?.frameTime == Float(0.1))
        #expect(texture.frames.first?.height == 2)
    }

    @Test("rejects malformed textures")
    func rejects() throws {
        #expect(throws: TEXError.invalidMagic(expected: "TEXV", found: "NOPE0000")) {
            var writer = BinaryWriter()
            writer.nullTerminatedString("NOPE0000")
            return try TEXParser.parse(writer.data)
        }
        let good = TEXWriter.build(format: .rgba8888, width: 2, height: 2, pixels: Self.pixels2x2)
        for length in stride(from: 0, to: good.count - 1, by: 3) {
            #expect(throws: TEXError.self) { try TEXParser.parse(good.prefix(length)) }
        }
        #expect(throws: TEXError.payloadTooSmall(expected: 16, actual: 4)) {
            try TEXParser.parse(TEXWriter.build(format: .rgba8888, width: 2, height: 2, pixels: Data(count: 4)))
        }
        #expect(throws: TEXError.unsupportedContainer("TEXB0009")) { try TEXParser.containerVersion("TEXB0009") }
        var unknownFormat = [UInt8](good)
        unknownFormat[18] = 3
        #expect(throws: TEXError.unsupportedFormat(3)) { try TEXParser.parse(Data(unknownFormat)) }
        var huge = [UInt8](good)
        huge[26] = 0xFF
        huge[27] = 0xFF
        #expect(throws: TEXError.self) { try TEXParser.parse(Data(huge)) }
    }

    @Test("per-texture byte budget stops many-mipmap decompression bombs")
    func budget() throws {
        var options = TEXWriter.Options()
        options.compress = true
        let pixels = Data(count: 64 * 64 * 4)
        let data = TEXWriter.build(format: .rgba8888, width: 64, height: 64, pixels: pixels, options: options)
        #expect(throws: TEXError.textureTooLarge(limit: 1000)) { try TEXParser.parse(data, byteBudget: 1000) }
        #expect(try TEXParser.parse(data, byteBudget: pixels.count).primaryMipmap?.data.count == pixels.count)
    }

    @Test("embedded images larger than the texture limit are rejected before decoding")
    func imageBomb() throws {
        let wide = RGBABitmap(width: Limits.maxTextureDimension + 1, height: 1,
                              pixels: Data(count: (Limits.maxTextureDimension + 1) * 4))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("owbomb-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try TEXImageConverter.writePNG(wide, to: url)
        let texture = try TEXParser.parse(TEXWriter.buildEncoded(imageData: try Data(contentsOf: url), width: 1, height: 1))
        #expect(throws: TEXError.invalidDimensions(width: Limits.maxTextureDimension + 1, height: 1)) {
            try TEXImageConverter.bitmap(from: texture)
        }
    }

    @Test("bitmap helpers crop and round-trip CGImage")
    func bitmapHelpers() throws {
        let bitmap = RGBABitmap(width: 2, height: 2, pixels: Self.pixels2x2)
        let cropped = bitmap.cropped(width: 1, height: 1)
        #expect(cropped.width == 1 && cropped.pixels == Data([255, 0, 0, 255]))
        #expect(bitmap.cropped(width: 5, height: 5) == bitmap)
        let image = try #require(bitmap.makeCGImage())
        #expect(RGBABitmap.from(cgImage: image)?.pixel(x: 0, y: 1) == [0, 0, 255, 255])
        #expect(RGBABitmap(width: 0, height: 0, pixels: Data()).makeCGImage() == nil)
        #expect(TEXFormat.dxt1.byteCount(width: 5, height: 5) == 32)
    }
}
