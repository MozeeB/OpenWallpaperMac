import Foundation
import Testing
import OWTestSupport
@testable import OWCore
@testable import OWFormats
@testable import OWLibrary

private func tempDir(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID())")
}

private func item(_ title: String, type: WallpaperType = .video, root: String = "/tmp/a") throws -> Wallpaper {
    Wallpaper(id: .random(), title: title, type: type, origin: .native, root: URL(fileURLWithPath: root), entry: try SanitizedPath("x"))
}

@Suite("LibraryIndex")
struct LibraryIndexTests {
    @Test("adds, re-imports in place, removes, filters and prunes")
    func operations() throws {
        let first = try item("Ocean", root: "/tmp/one")
        let second = try item("Forest", type: .scene, root: "/tmp/two")
        var library = LibraryIndex.adding(first, to: [])
        library = LibraryIndex.adding(second, to: library)
        let reimport = try item("Ocean v2", root: "/tmp/one/")
        library = LibraryIndex.adding(reimport, to: library)
        #expect(library.count == 2)
        #expect(library[0].id == first.id && library[0].title == "Ocean v2")
        #expect(LibraryIndex.filtered(library, query: "for", types: []).map(\.id) == [second.id])
        #expect(LibraryIndex.filtered(library, query: "", types: [.video]).map(\.id) == [first.id])
        #expect(LibraryIndex.replacing(first.with(title: "Z"), in: library)[0].title == "Z")

        let display = DisplayKey("d")
        var assignments = LibraryIndex.assigning(first.id, to: display, in: [])
        assignments = LibraryIndex.assigning(second.id, to: display, in: assignments)
        #expect(assignments.count == 1 && assignments[0].wallpaper == second.id)
        library = LibraryIndex.removing(second.id, from: library)
        #expect(LibraryIndex.pruning(assignments, library: library).isEmpty)
    }
}

@Suite("ImportService")
struct ImportServiceTests {
    let library = tempDir("owlib")

    private var service: ImportService { ImportService(libraryRoot: library, knownEffects: ["shake"]) }

    @Test("imports Wallpaper Engine scene folders in place with support level")
    func sceneFolder() throws {
        let folder = tempDir("owwe")
        defer { try? FileManager.default.removeItem(at: folder) }
        var options = SyntheticScene.Options()
        options.effects = ["shake", "godrays"]
        try SyntheticScene.write(SyntheticScene.projectFiles(options: options), to: folder)
        let wallpaper = try service.importItem(at: folder)
        #expect(wallpaper.type == .scene)
        #expect(wallpaper.origin == .wallpaperEngine)
        #expect(wallpaper.support == .partial)
        #expect(wallpaper.root == folder)
        #expect(!service.owns(wallpaper))
        service.removeOwnedFiles(of: wallpaper)
        #expect(FileManager.default.fileExists(atPath: folder.path), "never deletes user folders")
    }

    @Test("copies single files with a generated manifest", arguments: [
        ("clip.mp4", WallpaperType.video), ("art.png", .image), ("fx.metal", .shader), ("page.html", .web),
    ])
    func singleFile(name: String, type: WallpaperType) throws {
        let source = tempDir("owsrc")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: library)
        }
        try SyntheticScene.write([(name, Data("content".utf8))], to: source)
        let wallpaper = try service.importItem(at: source.appendingPathComponent(name))
        #expect(wallpaper.type == type)
        #expect(wallpaper.origin == .native)
        #expect(service.owns(wallpaper))
        #expect(wallpaper.title == (name as NSString).deletingPathExtension)
        service.removeOwnedFiles(of: wallpaper)
        #expect(!FileManager.default.fileExists(atPath: wallpaper.root.path))
    }

    @Test("imports a bare scene.pkg")
    func barePackage() throws {
        let source = tempDir("owpkgsrc")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: library)
        }
        try SyntheticScene.write([("my.pkg", PKGWriter.build(files: SyntheticScene.sceneContents()))], to: source)
        let wallpaper = try service.importItem(at: source.appendingPathComponent("my.pkg"))
        #expect(wallpaper.type == .scene)
        #expect(wallpaper.support == .full)
    }

    @Test("rejects missing, unsupported and invalid input")
    func rejects() throws {
        let source = tempDir("owbad")
        defer { try? FileManager.default.removeItem(at: source) }
        try SyntheticScene.write([("a.exe", Data()), ("broken.pkg", Data("x".utf8)), ("empty/.keep", Data())], to: source)
        #expect(throws: ImportError.notFound("/nope")) { try service.importItem(at: URL(fileURLWithPath: "/nope")) }
        #expect(throws: ImportError.unsupportedFile("a.exe")) { try service.importItem(at: source.appendingPathComponent("a.exe")) }
        #expect(throws: ImportError.project(.noManifest)) { try service.importItem(at: source.appendingPathComponent("empty")) }
        let broken = try service.importItem(at: source.appendingPathComponent("broken.pkg"))
        #expect(broken.support == .previewOnly)
        #expect(ImportService.defaultLibraryRoot().path.hasSuffix("OpenWallpaperMac/Library"))
    }
}

@Suite("Steam discovery")
struct SteamLocatorTests {
    @Test("parses libraryfolders.vdf and lists project folders")
    func discovery() throws {
        let steam = tempDir("owsteam")
        let extra = tempDir("owsteamextra")
        defer {
            try? FileManager.default.removeItem(at: steam)
            try? FileManager.default.removeItem(at: extra)
        }
        let vdf = """
        "libraryfolders"
        {
            "0" { "path"		"\(steam.path)" }
            "1" { "path"		"\(extra.path)" "label" "" }
        }
        """
        let content = "steamapps/workshop/content/431960"
        try SyntheticScene.write([
            ("steamapps/libraryfolders.vdf", Data(vdf.utf8)),
            ("\(content)/111/project.json", Data("{}".utf8)),
            ("\(content)/222/readme.txt", Data()),
        ], to: steam)
        try SyntheticScene.write([("\(content)/333/project.json", Data("{}".utf8))], to: extra)
        let locator = SteamLibraryLocator(steamRoot: steam)
        #expect(locator.libraryRoots().count == 2)
        #expect(locator.workshopFolders().count == 2)
        #expect(locator.projectFolders().map(\.lastPathComponent).sorted() == ["111", "333"])
        #expect(SteamLibraryLocator.parseLibraryPaths(#""path" "D:\\Games\\Steam""#) == [#"D:\Games\Steam"#])
        #expect(SteamLibraryLocator(steamRoot: tempDir("none")).workshopFolders().isEmpty)
        #expect(SteamLibraryLocator.defaultSteamRoot().lastPathComponent == "Steam")
    }
}

@Suite("Thumbnails")
struct ThumbnailTests {
    @Test("uses preview images and video frames, caches to disk")
    func thumbnails() async throws {
        let folder = tempDir("owthumb")
        let cache = tempDir("owthumbcache")
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: cache)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bitmap = RGBABitmap(width: 800, height: 400, pixels: Data(repeating: 255, count: 800 * 400 * 4))
        try TEXImageConverter.writePNG(bitmap, to: folder.appendingPathComponent("preview.png"))
        try await ClipFactory.makeClip(at: folder.appendingPathComponent("clip.mp4"), frames: 30)
        let service = ThumbnailService(cacheDirectory: cache, maxPixelSize: 100)

        let withPreview = Wallpaper(
            id: .random(), title: "P", type: .scene, origin: .native, root: folder,
            entry: try SanitizedPath("scene.json"), preview: try SanitizedPath("preview.png")
        )
        let url = try #require(await service.thumbnail(for: withPreview))
        let image = try #require(await service.downsample(url))
        #expect(max(image.width, image.height) == 100)
        #expect(await service.thumbnail(for: withPreview) == url)
        await service.invalidate(withPreview.id)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let video = Wallpaper(id: .random(), title: "V", type: .video, origin: .native, root: folder, entry: try SanitizedPath("clip.mp4"))
        #expect(await service.thumbnail(for: video) != nil)
        let image2 = Wallpaper(id: .random(), title: "I", type: .image, origin: .native, root: folder, entry: try SanitizedPath("preview.png"))
        #expect(await service.thumbnail(for: image2) != nil)
        let shader = Wallpaper(id: .random(), title: "S", type: .shader, origin: .native, root: folder, entry: try SanitizedPath("x.metal"))
        #expect(await service.thumbnail(for: shader) == nil)
        #expect(ThumbnailService.defaultCacheDirectory().path.contains("OpenWallpaperMac"))
        #expect(throws: Never.self) { _ = try WallpaperResolver.assets(for: shader) }
    }
}
