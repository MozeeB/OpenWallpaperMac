import Foundation
import Testing
@testable import OWCore
@testable import OWFormats

@Suite("BinaryReader")
struct BinaryReaderTests {
    @Test("reads little-endian values and strings")
    func reads() throws {
        var writer = BinaryWriter()
        writer.uint32(0x0403_0201)
        writer.int32(-2)
        writer.float32(1.5)
        writer.lengthPrefixedString("héllo")
        writer.nullTerminatedString("TEXV0005")
        var reader = BinaryReader(writer.data)
        #expect(try reader.uint32() == 0x0403_0201)
        #expect(try reader.int32() == -2)
        #expect(try reader.float32() == 1.5)
        #expect(try reader.lengthPrefixedString(limit: 32) == "héllo")
        #expect(try reader.nullTerminatedString(limit: 16) == "TEXV0005")
        #expect(reader.isAtEnd)
    }

    @Test("fails safely on bad input")
    func failures() throws {
        var reader = BinaryReader(Data([1, 2]))
        #expect(throws: BinaryReaderError.outOfBounds(offset: 0, needed: 4, available: 2)) { try reader.uint32() }
        var negative = BinaryReader({ var w = BinaryWriter(); w.int32(-5); return w.data }())
        #expect(throws: BinaryReaderError.negativeLength(-5)) { try negative.length(limit: 10) }
        var big = BinaryReader({ var w = BinaryWriter(); w.int32(50); return w.data }())
        #expect(throws: BinaryReaderError.lengthExceedsLimit(length: 50, limit: 10)) { try big.length(limit: 10) }
        var unterminated = BinaryReader(Data("abcdef".utf8))
        #expect(throws: BinaryReaderError.unterminatedString(offset: 0)) { try unterminated.nullTerminatedString(limit: 3) }
        var invalid = BinaryReader(Data([0xFF, 0xFE, 0]))
        #expect(throws: BinaryReaderError.invalidString(offset: 0)) { try invalid.nullTerminatedString(limit: 8) }
        var seekable = BinaryReader(Data(count: 4))
        #expect(throws: BinaryReaderError.self) { try seekable.seek(to: 9) }
        try seekable.seek(to: 4)
        #expect(seekable.remaining == 0)
        #expect(throws: BinaryReaderError.self) { try seekable.bytes(-1) }
    }
}

@Suite("PKG")
struct PKGTests {
    let files: [(String, Data)] = [("scene.json", Data("{}".utf8)), ("materials/A.tex", Data([1, 2, 3]))]

    @Test("round-trips entries with case-insensitive lookup")
    func roundTrip() throws {
        let archive = try PKGParser.parse(PKGWriter.build(files: files))
        #expect(archive.version == "PKGV0019")
        #expect(archive.paths.map(\.string) == ["scene.json", "materials/A.tex"])
        #expect(try archive.data(for: SanitizedPath("materials/a.tex")) == Data([1, 2, 3]))
        #expect(throws: PKGError.missingEntry("nope")) { try archive.data(for: SanitizedPath("nope")) }
        let source = PKGAssetSource(archive: archive)
        #expect(source.exists(try SanitizedPath("scene.json")))
        #expect(try source.data(at: "scene.json") == Data("{}".utf8))
        #expect(throws: AssetError.self) { try source.data(at: "../x") }
    }

    @Test("rejects bad magic, traversal, duplicates and overflow")
    func rejects() {
        #expect(throws: PKGError.invalidMagic("PKGVXXXX")) { try PKGParser.parse(PKGWriter.build(version: "PKGVXXXX", files: files)) }
        #expect(throws: PKGError.invalidEntryName("../evil")) {
            try PKGParser.parse(PKGWriter.build(files: [("../evil", Data())]))
        }
        #expect(throws: PKGError.duplicateEntry("A")) {
            try PKGParser.parse(PKGWriter.build(files: [("a", Data()), ("A", Data())]))
        }
        var writer = BinaryWriter()
        writer.lengthPrefixedString("PKGV0001")
        writer.int32(1)
        writer.lengthPrefixedString("big")
        writer.int32(Int32.max)
        writer.int32(Int32.max)
        #expect(throws: PKGError.entryOutOfBounds(name: "big")) { try PKGParser.parse(writer.data) }
        var many = BinaryWriter()
        many.lengthPrefixedString("PKGV0001")
        many.int32(Int32.max)
        #expect(throws: PKGError.tooManyEntries(Int(Int32.max))) { try PKGParser.parse(many.data) }
    }

    @Test("every truncation throws instead of crashing")
    func truncation() {
        let data = PKGWriter.build(files: files)
        for length in 0 ..< data.count - 3 {
            #expect(throws: PKGError.self) { try PKGParser.parse(data.prefix(length)) }
        }
    }

    @Test("seeded bit-flip mutation never crashes")
    func mutation() {
        let data = PKGWriter.build(files: files)
        var rng = SeededGenerator(seed: 42)
        for _ in 0 ..< 3000 {
            var mutated = [UInt8](data)
            for _ in 0 ..< 3 {
                let index = Int.random(in: 0 ..< mutated.count, using: &rng)
                mutated[index] ^= UInt8.random(in: 1 ... 255, using: &rng)
            }
            _ = try? PKGParser.parse(Data(mutated))
        }
    }

    @Test("reads packages from disk and layered sources")
    func disk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("owpkg-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try SyntheticScene.write(
            [("scene.pkg", PKGWriter.build(files: files)), ("loose.txt", Data("x".utf8))], to: folder
        )
        let layered = try LayeredAssetSource.forWallpaperFolder(folder)
        #expect(try layered.data(at: "scene.json") == Data("{}".utf8))
        #expect(try layered.data(at: "loose.txt") == Data("x".utf8))
        #expect(throws: AssetError.notFound("missing")) { try layered.data(at: "missing") }
        #expect(throws: PKGError.self) { try PKGParser.parse(contentsOf: folder.appendingPathComponent("none.pkg")) }
        let plain = try LayeredAssetSource.forWallpaperFolder(folder.appendingPathComponent("nothing"))
        #expect(plain.sources.count == 1)
    }
}

/// Deterministic RNG for fuzz-style tests (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
