import Foundation

public enum BinaryReaderError: Error, Equatable, Sendable {
    case outOfBounds(offset: Int, needed: Int, available: Int)
    case negativeLength(Int32)
    case lengthExceedsLimit(length: Int, limit: Int)
    case invalidString(offset: Int)
    case unterminatedString(offset: Int)
}

/// A bounds-checked little-endian cursor over untrusted bytes.
///
/// Every read validates the remaining length first, so truncated or hostile input
/// produces a typed error instead of a crash.
public struct BinaryReader: Sendable {
    public let data: Data
    public private(set) var offset: Int

    public init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    public var remaining: Int { data.count - offset }
    public var isAtEnd: Bool { remaining <= 0 }

    public mutating func seek(to newOffset: Int) throws(BinaryReaderError) {
        guard newOffset >= 0, newOffset <= data.count else {
            throw .outOfBounds(offset: newOffset, needed: 0, available: data.count)
        }
        offset = newOffset
    }

    public mutating func bytes(_ count: Int) throws(BinaryReaderError) -> Data {
        guard count >= 0, count <= remaining else {
            throw .outOfBounds(offset: offset, needed: count, available: max(remaining, 0))
        }
        let start = data.startIndex + offset
        let slice = data[start ..< start + count]
        offset += count
        return Data(slice)
    }

    public mutating func uint8() throws(BinaryReaderError) -> UInt8 {
        try bytes(1).first ?? 0
    }

    public mutating func uint32() throws(BinaryReaderError) -> UInt32 {
        let raw = try bytes(4)
        return raw.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }

    public mutating func int32() throws(BinaryReaderError) -> Int32 {
        Int32(bitPattern: try uint32())
    }

    public mutating func float32() throws(BinaryReaderError) -> Float {
        Float(bitPattern: try uint32())
    }

    /// Reads a non-negative Int32 length and checks it against `limit`.
    public mutating func length(limit: Int) throws(BinaryReaderError) -> Int {
        let raw = try int32()
        guard raw >= 0 else { throw .negativeLength(raw) }
        let value = Int(raw)
        guard value <= limit else { throw .lengthExceedsLimit(length: value, limit: limit) }
        return value
    }

    /// Reads an Int32 byte count followed by that many UTF-8 bytes.
    public mutating func lengthPrefixedString(limit: Int) throws(BinaryReaderError) -> String {
        let start = offset
        let count = try length(limit: limit)
        let raw = try bytes(count)
        guard let text = String(data: raw, encoding: .utf8) else { throw .invalidString(offset: start) }
        return text
    }

    /// Reads bytes up to a NUL terminator (consumed), at most `limit` bytes before it.
    public mutating func nullTerminatedString(limit: Int) throws(BinaryReaderError) -> String {
        let start = offset
        let window = min(limit + 1, remaining)
        let base = data.startIndex + offset
        guard let terminator = data[base ..< base + max(window, 0)].firstIndex(of: 0) else {
            throw .unterminatedString(offset: start)
        }
        let raw = data[base ..< terminator]
        offset += raw.count + 1
        guard let text = String(data: Data(raw), encoding: .utf8) else { throw .invalidString(offset: start) }
        return text
    }
}

/// Little-endian writer used by tests and the CLI to build fixtures.
public struct BinaryWriter: Sendable {
    public private(set) var data = Data()

    public init() {}

    public mutating func append(_ bytes: Data) { data.append(bytes) }

    public mutating func uint32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    public mutating func int32(_ value: Int32) { uint32(UInt32(bitPattern: value)) }

    public mutating func float32(_ value: Float) { uint32(value.bitPattern) }

    public mutating func lengthPrefixedString(_ text: String) {
        let raw = Data(text.utf8)
        int32(Int32(raw.count))
        data.append(raw)
    }

    public mutating func nullTerminatedString(_ text: String) {
        data.append(Data(text.utf8))
        data.append(0)
    }
}
