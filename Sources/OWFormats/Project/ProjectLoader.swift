import Foundation
import OWCore

public enum ProjectError: Error, Equatable, Sendable {
    case noManifest
    case unreadable(String)
    case invalidJSON(JSONGuardError)
    case missingField(String)
    case unsupportedType(String)
    case invalidPath(String)
    case entryNotFound(String)
}

/// Reads a wallpaper folder: native `wallpaper.json` first, else Wallpaper Engine `project.json`.
public enum ProjectLoader {
    public static let nativeManifest = "wallpaper.json"
    public static let weManifest = "project.json"
    public static let packageName = "scene.pkg"

    public static func load(folder: URL, id: WallpaperID = .random()) throws(ProjectError) -> Wallpaper {
        let fileManager = FileManager.default
        let native = folder.appendingPathComponent(nativeManifest)
        let we = folder.appendingPathComponent(weManifest)
        if fileManager.fileExists(atPath: native.path) {
            return try parse(manifest: try readJSON(native), folder: folder, origin: .native, id: id)
        }
        if fileManager.fileExists(atPath: we.path) {
            return try parse(manifest: try readJSON(we), folder: folder, origin: .wallpaperEngine, id: id)
        }
        throw .noManifest
    }

    static func readJSON(_ url: URL) throws(ProjectError) -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        do {
            return try JSONGuard.object(from: data)
        } catch {
            throw .invalidJSON(error)
        }
    }

    public static func parse(
        manifest: [String: Any], folder: URL, origin: WallpaperOrigin, id: WallpaperID
    ) throws(ProjectError) -> Wallpaper {
        guard let typeName = manifest["type"] as? String else { throw .missingField("type") }
        guard let type = wallpaperType(typeName) else { throw .unsupportedType(typeName) }
        let entryKey = origin == .native ? "entry" : "file"
        guard let entryRaw = manifest[entryKey] as? String else { throw .missingField(entryKey) }
        let entry = try path(entryRaw)
        try verifyEntry(entry, type: type, folder: folder)
        let preview = (manifest["preview"] as? String).flatMap { try? SanitizedPath($0) }
        let general = manifest["general"] as? [String: Any]
        let rawProperties = (manifest["properties"] ?? general?["properties"]) as? [String: Any] ?? [:]
        let title = PropertyParser.cleanLabel(manifest["title"] as? String) ?? folder.lastPathComponent
        let usesAudio = PropertyParser.boolValue(manifest["usesAudio"] ?? general?["supportsaudioprocessing"])
        return Wallpaper(
            id: id, title: title, type: type, origin: origin, root: folder, entry: entry,
            preview: preview, properties: PropertyParser.parse(rawProperties), support: .full,
            usesAudio: usesAudio
        )
    }

    static func wallpaperType(_ raw: String) -> WallpaperType? {
        WallpaperType(rawValue: raw.lowercased())
    }

    private static func path(_ raw: String) throws(ProjectError) -> SanitizedPath {
        do {
            return try SanitizedPath(raw)
        } catch {
            throw .invalidPath(raw)
        }
    }

    /// Scenes may live inside `scene.pkg`; everything else must exist on disk inside the folder.
    private static func verifyEntry(_ entry: SanitizedPath, type: WallpaperType, folder: URL) throws(ProjectError) {
        let url: URL
        do {
            url = try entry.resolve(in: folder)
        } catch {
            throw .invalidPath(entry.string)
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) { return }
        if type == .scene, fileManager.fileExists(atPath: folder.appendingPathComponent(packageName).path) { return }
        throw .entryNotFound(entry.string)
    }
}
