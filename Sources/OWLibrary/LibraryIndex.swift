import Foundation
import OWCore

/// Pure, immutable operations on the library list.
public enum LibraryIndex {
    /// Adds `wallpaper`, replacing an existing entry with the same root folder (re-import).
    public static func adding(_ wallpaper: Wallpaper, to library: [Wallpaper]) -> [Wallpaper] {
        let root = wallpaper.root.standardizedFileURL.path
        guard let index = library.firstIndex(where: { $0.root.standardizedFileURL.path == root }) else {
            return library + [wallpaper]
        }
        var copy = library
        copy[index] = Wallpaper(
            id: library[index].id, title: wallpaper.title, type: wallpaper.type, origin: wallpaper.origin,
            root: wallpaper.root, entry: wallpaper.entry, preview: wallpaper.preview,
            properties: wallpaper.properties, support: wallpaper.support, usesAudio: wallpaper.usesAudio
        )
        return copy
    }

    public static func removing(_ id: WallpaperID, from library: [Wallpaper]) -> [Wallpaper] {
        library.filter { $0.id != id }
    }

    public static func replacing(_ wallpaper: Wallpaper, in library: [Wallpaper]) -> [Wallpaper] {
        library.map { $0.id == wallpaper.id ? wallpaper : $0 }
    }

    public static func filtered(_ library: [Wallpaper], query: String, types: Set<WallpaperType>) -> [Wallpaper] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return library.filter { item in
            (types.isEmpty || types.contains(item.type)) && (needle.isEmpty || item.title.lowercased().contains(needle))
        }
    }

    /// Assignments that still point at existing wallpapers.
    public static func pruning(_ assignments: [DisplayAssignment], library: [Wallpaper]) -> [DisplayAssignment] {
        let ids = Set(library.map(\.id))
        return assignments.filter { ids.contains($0.wallpaper) }
    }

    /// Sets (or replaces) the assignment for a display.
    public static func assigning(
        _ wallpaper: WallpaperID, to display: DisplayKey, in assignments: [DisplayAssignment]
    ) -> [DisplayAssignment] {
        assignments.filter { $0.display != display } + [DisplayAssignment(display: display, wallpaper: wallpaper)]
    }
}
