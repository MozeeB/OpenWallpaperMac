import Foundation
import Testing
@testable import OWCore

@Suite("SanitizedPath")
struct SanitizedPathTests {
    @Test("normalises separators and dot components")
    func normalises() throws {
        let path = try SanitizedPath("materials\\bg.tex")
        #expect(path.string == "materials/bg.tex")
        #expect(try SanitizedPath("./a//b/./c").string == "a/b/c")
        #expect(path.pathExtension == "tex")
        #expect(path.lastComponent == "bg.tex")
        #expect(path.parent?.string == "materials")
        #expect(try SanitizedPath("top").parent == nil)
    }

    @Test("rejects dangerous input", arguments: [
        ("", PathError.empty),
        ("/etc/passwd", .absolute("/etc/passwd")),
        ("C:/Windows", .absolute("C:/Windows")),
        ("../secret", .traversal("../secret")),
        ("a/../../b", .traversal("a/../../b")),
        ("a\0b", .invalidCharacter("a\0b")),
        ("./.", .empty),
    ])
    func rejects(raw: String, expected: PathError) {
        #expect(throws: expected) { try SanitizedPath(raw) }
    }

    @Test("rejects over-long paths")
    func rejectsLong() {
        let raw = String(repeating: "a", count: SanitizedPath.maxLength + 1)
        #expect(throws: PathError.tooLong(raw.count)) { try SanitizedPath(raw) }
    }

    @Test("resolves inside root and blocks symlink escape")
    func resolve() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("owtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inside = try SanitizedPath("sub/file.txt").resolve(in: root)
        #expect(inside.path.hasSuffix("sub/file.txt"))

        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/tmp"))
        #expect(throws: PathError.escapesRoot("escape/x")) {
            try SanitizedPath("escape/x").resolve(in: root)
        }
    }

    @Test("codable round-trip and invalid decode")
    func codable() throws {
        let path = try SanitizedPath("a/b.json")
        let data = try JSONEncoder().encode([path])
        #expect(try JSONDecoder().decode([SanitizedPath].self, from: data) == [path])
        let bad = Data(#"["../x"]"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([SanitizedPath].self, from: bad) }
    }

    @Test("appending validates")
    func appending() throws {
        let base = try SanitizedPath("materials")
        #expect(try base.appending("x.tex").string == "materials/x.tex")
        #expect(throws: PathError.self) { try base.appending("../../x") }
        #expect(try SanitizedPath("A/B.TEX").lookupKey == "a/b.tex")
    }
}
