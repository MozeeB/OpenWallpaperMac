import Foundation
import OWCore

public enum PKGError: Error, Equatable, Sendable {
    case invalidMagic(String)
    case tooManyEntries(Int)
    case entryOutOfBounds(name: String)
    case invalidEntryName(String)
    case duplicateEntry(String)
    case truncated(BinaryReaderError)
    case missingEntry(String)
    case unreadable(String)
}

/// One file inside a package.
public struct PKGEntry: Equatable, Sendable {
    public let path: SanitizedPath
    /// Absolute offset of the entry's bytes within the package data.
    public let offset: Int
    public let length: Int
}

/// An immutable, parsed Wallpaper Engine-style package (`scene.pkg`).
///
/// Layout (little-endian): Int32-prefixed magic `PKGV####`, Int32 entry count, then per entry
/// an Int32-prefixed name, Int32 offset and Int32 length. Offsets are relative to the end of
/// the header. See `docs/formats/pkg.md`.
public struct PKGArchive: Sendable {
    public let version: String
    public let entries: [PKGEntry]
    private let data: Data
    private let index: [String: Int]

    init(version: String, entries: [PKGEntry], data: Data) {
        self.version = version
        self.entries = entries
        self.data = data
        self.index = Dictionary(
            entries.enumerated().map { ($1.path.lookupKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public var paths: [SanitizedPath] { entries.map(\.path) }

    public func entry(for path: SanitizedPath) -> PKGEntry? {
        index[path.lookupKey].map { entries[$0] }
    }

    public func contains(_ path: SanitizedPath) -> Bool {
        entry(for: path) != nil
    }

    public func data(for path: SanitizedPath) throws(PKGError) -> Data {
        guard let entry = entry(for: path) else { throw .missingEntry(path.string) }
        let start = data.startIndex + entry.offset
        return Data(data[start ..< start + entry.length])
    }
}

public enum PKGParser {
    public static func parse(contentsOf url: URL) throws(PKGError) -> PKGArchive {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        return try parse(data)
    }

    public static func parse(_ data: Data) throws(PKGError) -> PKGArchive {
        var reader = BinaryReader(data)
        do {
            let magic = try reader.lengthPrefixedString(limit: Limits.maxPackageMagicBytes)
            guard isValidMagic(magic) else { throw PKGError.invalidMagic(magic) }
            let rawCount = try reader.int32()
            guard rawCount >= 0, Int(rawCount) <= Limits.maxPackageEntries else {
                throw PKGError.tooManyEntries(Int(rawCount))
            }
            let rawEntries = try readEntries(&reader, count: Int(rawCount))
            let entries = try validate(rawEntries, headerSize: reader.offset, total: data.count)
            return PKGArchive(version: magic, entries: entries, data: data)
        } catch let error as PKGError {
            throw error
        } catch let error as BinaryReaderError {
            throw .truncated(error)
        } catch {
            throw .unreadable(String(describing: error))
        }
    }

    static func isValidMagic(_ magic: String) -> Bool {
        guard magic.count == 8, magic.hasPrefix("PKGV") else { return false }
        return magic.dropFirst(4).allSatisfy(\.isNumber)
    }

    private struct RawEntry {
        let name: String
        let offset: Int32
        let length: Int32
    }

    private static func readEntries(_ reader: inout BinaryReader, count: Int) throws -> [RawEntry] {
        var result: [RawEntry] = []
        result.reserveCapacity(min(count, 4096))
        for _ in 0 ..< count {
            let name = try reader.lengthPrefixedString(limit: Limits.maxPackageNameBytes)
            let offset = try reader.int32()
            let length = try reader.int32()
            result.append(RawEntry(name: name, offset: offset, length: length))
        }
        return result
    }

    private static func validate(_ raw: [RawEntry], headerSize: Int, total: Int) throws(PKGError) -> [PKGEntry] {
        var seen = Set<String>()
        var entries: [PKGEntry] = []
        for item in raw {
            let path: SanitizedPath
            do {
                path = try SanitizedPath(item.name)
            } catch {
                throw .invalidEntryName(item.name)
            }
            guard seen.insert(path.lookupKey).inserted else { throw .duplicateEntry(path.string) }
            let start = headerSize + Int(item.offset)
            let (end, overflow) = start.addingReportingOverflow(Int(item.length))
            guard item.offset >= 0, item.length >= 0, !overflow, end <= total else {
                throw .entryOutOfBounds(name: item.name)
            }
            entries.append(PKGEntry(path: path, offset: start, length: Int(item.length)))
        }
        return entries
    }
}

/// Builds packages; used by tests, fixtures and `owctl`.
public enum PKGWriter {
    public static func build(version: String = "PKGV0019", files: [(String, Data)]) -> Data {
        var header = BinaryWriter()
        header.lengthPrefixedString(version)
        header.int32(Int32(files.count))
        var offset: Int32 = 0
        for (name, contents) in files {
            header.lengthPrefixedString(name)
            header.int32(offset)
            header.int32(Int32(contents.count))
            offset += Int32(contents.count)
        }
        var output = header.data
        files.forEach { output.append($0.1) }
        return output
    }
}
