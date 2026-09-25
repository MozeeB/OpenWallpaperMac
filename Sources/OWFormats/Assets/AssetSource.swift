import Foundation
import OWCore

public enum AssetError: Error, Equatable, Sendable {
    case notFound(String)
    case unreadable(String)
    case invalidPath(String)
}

/// Read-only access to a wallpaper's files, independent of where they are stored.
public protocol AssetSource: Sendable {
    func data(at path: SanitizedPath) throws(AssetError) -> Data
    func exists(_ path: SanitizedPath) -> Bool
}

public extension AssetSource {
    func data(at raw: String) throws(AssetError) -> Data {
        let path: SanitizedPath
        do {
            path = try SanitizedPath(raw)
        } catch {
            throw .invalidPath(raw)
        }
        return try data(at: path)
    }

    func json(at path: SanitizedPath) throws(AssetError) -> [String: Any] {
        let bytes = try data(at: path)
        do {
            return try JSONGuard.object(from: bytes)
        } catch {
            throw .unreadable("\(path): \(error)")
        }
    }
}

/// Files inside a folder; every path is resolved and checked against the root.
public struct FolderAssetSource: AssetSource {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func data(at path: SanitizedPath) throws(AssetError) -> Data {
        let url: URL
        do {
            url = try path.resolve(in: root)
        } catch {
            throw .invalidPath(path.string)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { throw .notFound(path.string) }
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
    }

    public func exists(_ path: SanitizedPath) -> Bool {
        guard let url = try? path.resolve(in: root) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

/// Files inside a parsed package.
public struct PKGAssetSource: AssetSource {
    public let archive: PKGArchive

    public init(archive: PKGArchive) {
        self.archive = archive
    }

    public func data(at path: SanitizedPath) throws(AssetError) -> Data {
        do {
            return try archive.data(for: path)
        } catch {
            throw .notFound(path.string)
        }
    }

    public func exists(_ path: SanitizedPath) -> Bool {
        archive.contains(path)
    }
}

/// Tries each source in order (e.g. `scene.pkg` first, then loose files in the folder).
public struct LayeredAssetSource: AssetSource {
    public let sources: [any AssetSource]

    public init(_ sources: [any AssetSource]) {
        self.sources = sources
    }

    public func data(at path: SanitizedPath) throws(AssetError) -> Data {
        for source in sources where source.exists(path) {
            return try source.data(at: path)
        }
        throw .notFound(path.string)
    }

    public func exists(_ path: SanitizedPath) -> Bool {
        sources.contains { $0.exists(path) }
    }

    /// Assets for a wallpaper folder: its `scene.pkg` (if any) layered over the folder itself.
    public static func forWallpaperFolder(_ folder: URL) throws(PKGError) -> LayeredAssetSource {
        let folderSource = FolderAssetSource(root: folder)
        let packageURL = folder.appendingPathComponent(ProjectLoader.packageName)
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            return LayeredAssetSource([folderSource])
        }
        let archive = try PKGParser.parse(contentsOf: packageURL)
        return LayeredAssetSource([PKGAssetSource(archive: archive), folderSource])
    }
}
