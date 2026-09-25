import Compression
import Foundation
import OWCore

/// Raw LZ4 block coding via Apple's Compression framework (no third-party code).
public enum LZ4Block {
    public static func decompress(_ input: Data, expectedSize: Int) throws(TEXError) -> Data {
        guard expectedSize >= 0, expectedSize <= Limits.maxDecompressedBytes else {
            throw .decompressionFailed(expected: expectedSize, actual: 0)
        }
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { outBuffer in
            input.withUnsafeBytes { inBuffer in
                guard
                    let dst = outBuffer.bindMemory(to: UInt8.self).baseAddress,
                    let src = inBuffer.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(dst, expectedSize, src, input.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        guard written == expectedSize else {
            throw .decompressionFailed(expected: expectedSize, actual: written)
        }
        return output
    }

    /// Compresses for fixtures. Returns `nil` if the framework fails.
    public static func compress(_ input: Data) -> Data? {
        guard !input.isEmpty else { return Data() }
        let capacity = input.count + input.count / 255 + 64
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { outBuffer in
            input.withUnsafeBytes { inBuffer in
                guard
                    let dst = outBuffer.bindMemory(to: UInt8.self).baseAddress,
                    let src = inBuffer.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_encode_buffer(dst, capacity, src, input.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        return written > 0 ? output.prefix(written) : nil
    }
}
