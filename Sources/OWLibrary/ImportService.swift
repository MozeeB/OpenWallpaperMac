import Foundation
import OWCore
import OWFormats

public enum ImportError: Error, Equatable, Sendable {
    case notFound(String)
    case unsupportedFile(String)
    case tooLarge(String)
    case project(ProjectError)
    case copyFailed(String)
    case package(PKGError)
}

/// Turns user-chosen files and folders into library entries. Never executes imported content.
///
/// Folders (Wallpaper Engine projects or native `wallpaper.json` folders) are referenced in place;
/// single files are copied into the library directory with a generated manifest.
public struct ImportService: Sendable {
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]
    public static let maxVideoBytes: Int64 = 8 * 1024 * 1024 * 1024
    public static let maxOtherBytes: Int64 = 512 * 1024 * 1024

    public let libraryRoot: URL
    public let knownEffects: Set<String>

    public init(libraryRoot: URL, knownEffects: Set<String>) {
        self.libraryRoot = libraryRoot
        self.knownEffects = knownEffects
    }

    public static func defaultLibraryRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenWallpaperMac/Library")
    }

    public func importItem(at url: URL) throws(ImportError) -> Wallpaper {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw .notFound(url.path)
        }
        return isDirectory.boolValue ? try importFolder(url) : try importFile(url)
    }

    public func importFolder(_ folder: URL) throws(ImportError) -> Wallpaper {
        let wallpaper: Wallpaper
        do {
            wallpaper = try ProjectLoader.load(folder: folder)
        } catch {
            throw .project(error)
        }
        return wallpaper.type == .scene ? wallpaper.with(support: sceneSupport(wallpaper)) : wallpaper
    }

    /// Support level of a scene, computed once at import so the library can badge it.
    public func sceneSupport(_ wallpaper: Wallpaper) -> SupportLevel {
        guard let assets = try? LayeredAssetSource.forWallpaperFolder(wallpaper.root),
              let scene = try? SceneLoader.load(entry: wallpaper.entry, from: assets)
        else { return .previewOnly }
        return SceneSupportAnalyzer.analyze(scene, knownEffects: knownEffects).level
    }

    public func importFile(_ file: URL) throws(ImportError) -> Wallpaper {
        let ext = file.pathExtension.lowercased()
        guard let type = ImportService.type(forExtension: ext) else { throw .unsupportedFile(file.lastPathComponent) }
        try checkSize(file, video: type == .video)
        let id = WallpaperID.random()
        let folder = libraryRoot.appendingPathComponent(id.rawValue)
        let entryName = type == .scene ? ProjectLoader.packageName : "wallpaper.\(ext)"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(entryName))
            try writeManifest(title: file.deletingPathExtension().lastPathComponent, type: type,
                              entry: type == .scene ? "scene.json" : entryName, to: folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw .copyFailed(error.localizedDescription)
        }
        do {
            let wallpaper = try ProjectLoader.load(folder: folder, id: id)
            return type == .scene ? wallpaper.with(support: sceneSupport(wallpaper)) : wallpaper
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw .project(error)
        }
    }

    static func type(forExtension ext: String) -> WallpaperType? {
        if videoExtensions.contains(ext) { return .video }
        if imageExtensions.contains(ext) { return .image }
        switch ext {
        case "metal": return .shader
        case "html", "htm": return .web
        case "pkg": return .scene
        default: return nil
        }
    }

    private func checkSize(_ file: URL, video: Bool) throws(ImportError) {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        guard size <= (video ? ImportService.maxVideoBytes : ImportService.maxOtherBytes) else {
            throw .tooLarge(file.lastPathComponent)
        }
    }

    private func writeManifest(title: String, type: WallpaperType, entry: String, to folder: URL) throws {
        let manifest: [String: Any] = ["title": title, "type": type.rawValue, "entry": entry, "properties": [String: Any]()]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent(ProjectLoader.nativeManifest))
    }

    /// Deletes files we own (copied imports). Folders imported in place are never touched.
    public func removeOwnedFiles(of wallpaper: Wallpaper) {
        let root = libraryRoot.standardizedFileURL.path + "/"
        guard wallpaper.root.standardizedFileURL.path.hasPrefix(root) else { return }
        try? FileManager.default.removeItem(at: wallpaper.root)
    }

    public func owns(_ wallpaper: Wallpaper) -> Bool {
        wallpaper.root.standardizedFileURL.path.hasPrefix(libraryRoot.standardizedFileURL.path + "/")
    }
}
