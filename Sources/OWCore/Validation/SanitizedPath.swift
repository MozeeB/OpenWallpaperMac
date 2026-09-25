import Foundation

public enum PathError: Error, Equatable, Sendable {
    case empty
    case tooLong(Int)
    case absolute(String)
    case traversal(String)
    case invalidCharacter(String)
    case escapesRoot(String)
}

/// A relative path that has been validated to stay inside its root.
///
/// Rejects absolute paths, `..` components, NUL bytes and over-long input.
/// Backslashes (Windows-style paths found in Wallpaper Engine packages) are normalised to `/`.
public struct SanitizedPath: Hashable, Codable, Sendable, CustomStringConvertible {
    public static let maxLength = 1024

    public let components: [String]

    public init(_ raw: String) throws(PathError) {
        guard !raw.isEmpty else { throw .empty }
        guard raw.utf8.count <= SanitizedPath.maxLength else { throw .tooLong(raw.utf8.count) }
        guard !raw.contains("\0") else { throw .invalidCharacter(raw) }
        let normalized = raw.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/"), !SanitizedPath.hasDrivePrefix(normalized) else {
            throw .absolute(raw)
        }
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." }
        guard !parts.contains("..") else { throw .traversal(raw) }
        guard !parts.isEmpty else { throw .empty }
        components = parts
    }

    public var string: String { components.joined(separator: "/") }
    public var description: String { string }
    public var lastComponent: String { components.last ?? "" }

    public var pathExtension: String {
        (lastComponent as NSString).pathExtension.lowercased()
    }

    /// Lower-cased form used for case-insensitive lookups inside packages.
    public var lookupKey: String { string.lowercased() }

    /// The directory portion, or `nil` at the top level.
    public var parent: SanitizedPath? {
        guard components.count > 1 else { return nil }
        return try? SanitizedPath(components.dropLast().joined(separator: "/"))
    }

    public func appending(_ other: String) throws(PathError) -> SanitizedPath {
        try SanitizedPath(string + "/" + other)
    }

    /// Resolves inside `root`, following symlinks, and verifies the result stays inside it.
    public func resolve(in root: URL) throws(PathError) -> URL {
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        var candidate = base
        for component in components {
            // Resolve each existing prefix so a symlinked directory cannot escape the root.
            candidate = SanitizedPath.resolveExisting(candidate.appendingPathComponent(component))
            guard candidate.path.hasPrefix(basePath) else { throw .escapesRoot(string) }
        }
        return candidate
    }

    private static func resolveExisting(_ url: URL) -> URL {
        let path = url.path
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
            return url
        }
        let target = destination.hasPrefix("/")
            ? URL(fileURLWithPath: destination)
            : url.deletingLastPathComponent().appendingPathComponent(destination)
        return target.standardizedFileURL.resolvingSymlinksInPath()
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        do {
            try self.init(raw)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid path \(raw): \(error)")
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }

    private static func hasDrivePrefix(_ path: String) -> Bool {
        let chars = Array(path.prefix(2))
        return chars.count == 2 && chars[1] == ":" && chars[0].isLetter
    }
}
