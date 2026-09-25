import ArgumentParser
import Foundation
import OWCore
import OWFormats
import OWLibrary
import OWScene

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "inspect", abstract: "Describe a .pkg, .tex or wallpaper folder.")

    @Argument(help: "Path to a scene.pkg, .tex file or wallpaper folder.")
    var path: String

    func run() throws {
        let url = URL(fileURLWithPath: path)
        switch url.pathExtension.lowercased() {
        case "pkg":
            let archive = try PKGParser.parse(contentsOf: url)
            print("\(archive.version): \(archive.entries.count) entries")
            archive.entries.forEach { print(String(format: "%10d  %@", $0.length, $0.path.string)) }
        case "tex":
            let texture = try TEXParser.parse(try Data(contentsOf: url))
            let header = texture.header
            print("TEXB v\(texture.containerVersion) payload=\(texture.payload) image=\(header.imageWidth)x\(header.imageHeight)",
                  "storage=\(header.textureWidth)x\(header.textureHeight) images=\(texture.images.count) frames=\(texture.frames.count)")
        default:
            try inspectFolder(url)
        }
    }

    private func inspectFolder(_ url: URL) throws {
        let wallpaper = try ImportService(libraryRoot: url, knownEffects: EffectRegistry.known).importFolder(url)
        print("\(wallpaper.title) — \(wallpaper.type.rawValue) (\(wallpaper.origin.rawValue)), support: \(wallpaper.support.rawValue)")
        print("entry: \(wallpaper.entry)  audio: \(wallpaper.usesAudio)")
        wallpaper.properties.forEach { print("  property \($0.key): \($0.kind) = \($0.defaultValue)") }
        guard wallpaper.type == .scene else { return }
        let scene = try SceneLoader.load(entry: wallpaper.entry, from: try LayeredAssetSource.forWallpaperFolder(url))
        let report = SceneSupportAnalyzer.analyze(scene, knownEffects: EffectRegistry.known)
        print("layers: \(scene.layers.count) renderable: \(report.renderableLayers)")
        report.unsupported.forEach { print("  unsupported: \($0)") }
    }
}

struct ExtractCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "extract", abstract: "Extract a scene.pkg into a folder.")

    @Argument var package: String
    @Argument var output: String

    func run() throws {
        let archive = try PKGParser.parse(contentsOf: URL(fileURLWithPath: package))
        let root = URL(fileURLWithPath: output)
        for entry in archive.entries {
            // Paths are sanitized by the parser; resolve() re-checks containment.
            let target = try entry.path.resolve(in: root)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try archive.data(for: entry.path).write(to: target)
        }
        print("Extracted \(archive.entries.count) files to \(root.path)")
    }
}

struct TexToPNGCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tex2png", abstract: "Convert a .tex texture to PNG.")

    @Argument var input: String
    @Argument var output: String

    func run() throws {
        let texture = try TEXParser.parse(try Data(contentsOf: URL(fileURLWithPath: input)))
        let bitmap = try TEXImageConverter.bitmap(from: texture)
        try TEXImageConverter.writePNG(bitmap, to: URL(fileURLWithPath: output))
        print("Wrote \(bitmap.width)x\(bitmap.height) PNG to \(output)")
    }
}

struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate", abstract: "Validate wallpaper folders; exits non-zero on failure."
    )

    @Argument(help: "One or more wallpaper folders.")
    var folders: [String]

    func run() throws {
        var failures = 0
        for folder in folders {
            let url = URL(fileURLWithPath: folder)
            do {
                let wallpaper = try ImportService(libraryRoot: url, knownEffects: EffectRegistry.known).importFolder(url)
                print("ok    \(folder)  [\(wallpaper.type.rawValue), \(wallpaper.support.rawValue)]")
            } catch {
                failures += 1
                print("FAIL  \(folder)  \(error)")
            }
        }
        if failures > 0 { throw ExitCode(1) }
    }
}

struct MakeSampleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "make-sample", abstract: "Write original sample wallpapers (scene + shader)."
    )

    @Argument var output: String

    func run() throws {
        let root = URL(fileURLWithPath: output)
        try SyntheticScene.write(SyntheticScene.projectFiles(), to: root.appendingPathComponent("Synthetic Scene"))
        try SyntheticScene.write(SampleContent.plasmaShaderFiles(), to: root.appendingPathComponent("Plasma"))
        print("Wrote samples to \(root.path)")
    }
}
