import Foundation

/// Stable identifier of a library item.
public struct WallpaperID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func random() -> WallpaperID {
        WallpaperID(UUID().uuidString.lowercased())
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The renderer family a wallpaper needs.
public enum WallpaperType: String, Codable, Sendable, CaseIterable {
    case image
    case video
    case web
    case shader
    case scene
}

/// Where a wallpaper definition came from.
public enum WallpaperOrigin: String, Codable, Sendable {
    /// OpenWallpaperMac `wallpaper.json` manifest (or a single imported file).
    case native
    /// A Wallpaper Engine project folder (`project.json`).
    case wallpaperEngine
}

/// How completely a wallpaper can be rendered by this app.
public enum SupportLevel: String, Codable, Sendable {
    case full
    /// Renders, but some features (effects, particles…) are skipped.
    case partial
    /// Cannot be rendered; the preview image is shown instead.
    case previewOnly
}

/// An immutable library entry.
public struct Wallpaper: Codable, Sendable, Equatable, Identifiable {
    public let id: WallpaperID
    public let title: String
    public let type: WallpaperType
    public let origin: WallpaperOrigin
    /// Folder that holds all of the wallpaper's files.
    public let root: URL
    /// Entry file relative to `root` (video file, html page, shader, scene.json…).
    public let entry: SanitizedPath
    public let preview: SanitizedPath?
    public let properties: [PropertyDefinition]
    public let support: SupportLevel
    public let usesAudio: Bool

    public init(
        id: WallpaperID,
        title: String,
        type: WallpaperType,
        origin: WallpaperOrigin,
        root: URL,
        entry: SanitizedPath,
        preview: SanitizedPath? = nil,
        properties: [PropertyDefinition] = [],
        support: SupportLevel = .full,
        usesAudio: Bool = false
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.origin = origin
        self.root = root
        self.entry = entry
        self.preview = preview
        self.properties = properties
        self.support = support
        self.usesAudio = usesAudio
    }

    /// Default values of all user properties.
    public var defaultValues: PropertyValues {
        Dictionary(uniqueKeysWithValues: properties.map { ($0.key, $0.defaultValue) })
    }

    public func with(support: SupportLevel) -> Wallpaper {
        Wallpaper(
            id: id, title: title, type: type, origin: origin, root: root, entry: entry,
            preview: preview, properties: properties, support: support, usesAudio: usesAudio
        )
    }

    public func with(title: String) -> Wallpaper {
        Wallpaper(
            id: id, title: title, type: type, origin: origin, root: root, entry: entry,
            preview: preview, properties: properties, support: support, usesAudio: usesAudio
        )
    }
}
