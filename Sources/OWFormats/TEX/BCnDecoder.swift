import Foundation

/// CPU decoder for BC1/BC2/BC3 (DXT1/3/5) blocks into RGBA8.
///
/// The GPU path uploads BCn directly; this exists for PNG export, thumbnails and tests.
public enum BCnDecoder {
    public static func decode(_ data: Data, format: TEXFormat, width: Int, height: Int) throws(TEXError) -> Data {
        guard format.isBlockCompressed else { throw .unsupportedFormat(format.rawValue) }
        let needed = format.byteCount(width: width, height: height)
        guard data.count >= needed else { throw .payloadTooSmall(expected: needed, actual: data.count) }
        let bytes = [UInt8](data.prefix(needed))
        var output = [UInt8](repeating: 0, count: width * height * 4)
        let blockSize = format == .dxt1 ? 8 : 16
        let blocksWide = (width + 3) / 4
        for blockIndex in 0 ..< needed / blockSize {
            let base = blockIndex * blockSize
            let pixels = decodeBlock(bytes, at: base, format: format)
            write(pixels, to: &output, blockX: blockIndex % blocksWide, blockY: blockIndex / blocksWide,
                  width: width, height: height)
        }
        return Data(output)
    }

    /// Decodes one block into 16 RGBA pixels.
    static func decodeBlock(_ bytes: [UInt8], at base: Int, format: TEXFormat) -> [[UInt8]] {
        switch format {
        case .dxt1:
            return colorBlock(bytes, at: base, allowTransparent: true)
        case .dxt3:
            let colors = colorBlock(bytes, at: base + 8, allowTransparent: false)
            return (0 ..< 16).map { i in
                let nibble = (bytes[base + i / 2] >> (4 * UInt8(i % 2))) & 0x0F
                return [colors[i][0], colors[i][1], colors[i][2], nibble * 17]
            }
        default:
            let colors = colorBlock(bytes, at: base + 8, allowTransparent: false)
            let alphas = alphaBlock(bytes, at: base)
            return (0 ..< 16).map { [colors[$0][0], colors[$0][1], colors[$0][2], alphas[$0]] }
        }
    }

    private static func colorBlock(_ b: [UInt8], at base: Int, allowTransparent: Bool) -> [[UInt8]] {
        let c0 = UInt16(b[base]) | UInt16(b[base + 1]) << 8
        let c1 = UInt16(b[base + 2]) | UInt16(b[base + 3]) << 8
        let p0 = rgb565(c0)
        let p1 = rgb565(c1)
        let palette: [[Int]]
        if c0 > c1 || !allowTransparent {
            palette = [p0 + [255], p1 + [255], mix(p0, p1, 2, 1) + [255], mix(p0, p1, 1, 2) + [255]]
        } else {
            palette = [p0 + [255], p1 + [255], mix(p0, p1, 1, 1) + [255], [0, 0, 0, 0]]
        }
        let indices = UInt32(b[base + 4]) | UInt32(b[base + 5]) << 8
            | UInt32(b[base + 6]) << 16 | UInt32(b[base + 7]) << 24
        return (0 ..< 16).map { i in palette[Int((indices >> (2 * UInt32(i))) & 0x3)].map { UInt8($0) } }
    }

    private static func alphaBlock(_ b: [UInt8], at base: Int) -> [UInt8] {
        let a0 = Int(b[base])
        let a1 = Int(b[base + 1])
        var table = [a0, a1]
        if a0 > a1 {
            table += (1 ... 6).map { ((7 - $0) * a0 + $0 * a1) / 7 }
        } else {
            table += (1 ... 4).map { ((5 - $0) * a0 + $0 * a1) / 5 } + [0, 255]
        }
        let bits = (0 ..< 6).reduce(UInt64(0)) { $0 | UInt64(b[base + 2 + $1]) << (8 * UInt64($1)) }
        return (0 ..< 16).map { UInt8(table[Int((bits >> (3 * UInt64($0))) & 0x7)]) }
    }

    private static func rgb565(_ value: UInt16) -> [Int] {
        let r = Int((value >> 11) & 0x1F)
        let g = Int((value >> 5) & 0x3F)
        let b = Int(value & 0x1F)
        return [(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)]
    }

    private static func mix(_ a: [Int], _ b: [Int], _ wa: Int, _ wb: Int) -> [Int] {
        zip(a, b).map { ($0 * wa + $1 * wb) / (wa + wb) }
    }

    private static func write(
        _ pixels: [[UInt8]], to output: inout [UInt8], blockX: Int, blockY: Int, width: Int, height: Int
    ) {
        for i in 0 ..< 16 {
            let x = blockX * 4 + i % 4
            let y = blockY * 4 + i / 4
            guard x < width, y < height else { continue }
            let target = (y * width + x) * 4
            output.replaceSubrange(target ..< target + 4, with: pixels[i])
        }
    }
}
