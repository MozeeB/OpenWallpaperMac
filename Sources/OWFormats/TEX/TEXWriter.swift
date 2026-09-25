import Foundation

/// Builds `.tex` files for fixtures, samples and `owctl`.
public enum TEXWriter {
    public struct Options: Sendable {
        public var containerVersion: Int = 3
        public var compress = false
        public var flags: TEXFlags = []
        public var imageFormat: Int32 = -1

        public init() {}
    }

    /// Single-image, single-mipmap texture.
    public static func build(
        format: TEXFormat, width: Int, height: Int, pixels: Data, options: Options = Options()
    ) -> Data {
        var writer = BinaryWriter()
        writeHeader(&writer, format: format.rawValue, width: width, height: height, flags: options.flags)
        writer.nullTerminatedString("TEXB000\(options.containerVersion)")
        writer.int32(1)
        if options.containerVersion >= 3 { writer.int32(options.imageFormat) }
        if options.containerVersion == 4 { writer.int32(0) }
        writer.int32(1)
        writeMipmap(&writer, width: width, height: height, pixels: pixels, options: options)
        return writer.data
    }

    /// Texture whose payload is an encoded image file (PNG/JPEG).
    public static func buildEncoded(imageData: Data, width: Int, height: Int, freeImageFormat: Int32 = 13) -> Data {
        var options = Options()
        options.imageFormat = freeImageFormat
        return build(format: .rgba8888, width: width, height: height, pixels: imageData, options: options)
    }

    static func writeHeader(_ writer: inout BinaryWriter, format: Int32, width: Int, height: Int, flags: TEXFlags) {
        writer.nullTerminatedString("TEXV0005")
        writer.nullTerminatedString("TEXI0001")
        writer.int32(format)
        writer.int32(flags.rawValue)
        [width, height, width, height].forEach { writer.int32(Int32($0)) }
        writer.uint32(0)
    }

    static func writeMipmap(_ writer: inout BinaryWriter, width: Int, height: Int, pixels: Data, options: Options) {
        if options.containerVersion == 4 {
            writer.int32(1)
            writer.int32(2)
            writer.nullTerminatedString("")
            writer.int32(1)
        }
        writer.int32(Int32(width))
        writer.int32(Int32(height))
        let compressed = options.compress ? LZ4Block.compress(pixels) : nil
        if options.containerVersion >= 2 {
            writer.int32(compressed == nil ? 0 : 1)
            writer.int32(Int32(pixels.count))
        }
        let payload = compressed ?? pixels
        writer.int32(Int32(payload.count))
        writer.append(payload)
    }
}
