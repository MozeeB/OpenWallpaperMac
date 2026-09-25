import Foundation

/// Finds Wallpaper Engine Workshop folders the user already has on disk.
///
/// Wallpaper Engine itself is Windows-only, so on a Mac these usually come from a Steam library
/// synced or copied from a PC. Results are suggestions only; nothing is imported automatically.
public struct SteamLibraryLocator: Sendable {
    public static let wallpaperEngineAppID = "431960"
    public let steamRoot: URL

    public init(steamRoot: URL = SteamLibraryLocator.defaultSteamRoot()) {
        self.steamRoot = steamRoot
    }

    public static func defaultSteamRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Steam")
    }

    /// Steam library roots: the main one plus any listed in `libraryfolders.vdf`.
    public func libraryRoots() -> [URL] {
        let vdf = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        let extra = (try? String(contentsOf: vdf, encoding: .utf8)).map(SteamLibraryLocator.parseLibraryPaths) ?? []
        let all = [steamRoot] + extra.map { URL(fileURLWithPath: $0) }
        var seen = Set<String>()
        return all.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// Existing `steamapps/workshop/content/431960` folders.
    public func workshopFolders() -> [URL] {
        libraryRoots()
            .map { $0.appendingPathComponent("steamapps/workshop/content/\(SteamLibraryLocator.wallpaperEngineAppID)") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Project folders (containing `project.json`) directly inside the given folders.
    public func projectFolders(in folders: [URL]? = nil, limit: Int = 5000) -> [URL] {
        let parents = folders ?? workshopFolders()
        let found = parents.flatMap { parent -> [URL] in
            let children = (try? FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )) ?? []
            return children.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("project.json").path) }
        }
        return Array(found.sorted { $0.path < $1.path }.prefix(limit))
    }

    /// Extracts `"path"  "..."` values from Valve's KeyValues format (inline or multi-line).
    static func parseLibraryPaths(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #""path"\s+"((?:[^"\\]|\\.)*)""#, options: .caseInsensitive) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]).replacingOccurrences(of: "\\\\", with: "\\") }
        }
    }
}
