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

    /// Assignments that still point at existing wallpapers; rotations drop removed items and fall back
    /// to a single wallpaper when only one remains.
    public static func pruning(_ assignments: [DisplayAssignment], library: [Wallpaper]) -> [DisplayAssignment] {
        let ids = Set(library.map(\.id))
        return assignments.compactMap { assignment in
            let kept = assignment.wallpapers.filter(ids.contains)
            guard let first = kept.first else { return nil }
            let rotation = assignment.rotation?.pruned(keeping: ids)
            return DisplayAssignment(
                display: assignment.display, wallpaper: first, overrides: assignment.overrides,
                fill: assignment.fill, rotation: rotation, space: assignment.space
            )
        }
    }

    /// Sets (or replaces) a rotation for a display, or for one of its Spaces. One item becomes a plain
    /// assignment.
    public static func rotating(
        _ wallpapers: [WallpaperID], interval: TimeInterval, shuffle: Bool, on display: DisplayKey,
        space: SpaceKey? = nil, in assignments: [DisplayAssignment]
    ) -> [DisplayAssignment] {
        let slot = AssignmentSlot(display: display, space: space)
        guard let first = wallpapers.first else { return clearing(slot, in: assignments) }
        let rotation = Rotation(items: wallpapers, interval: interval, shuffle: shuffle)
        let existing = assignments.assignment(in: slot)
        let assignment = DisplayAssignment(
            display: display, wallpaper: first, overrides: existing?.overrides ?? [:],
            fill: existing?.fill ?? .fill, rotation: rotation, space: space
        )
        return clearing(slot, in: assignments) + [assignment]
    }

    /// Sets (or replaces) the assignment for a display, or for one of its Spaces.
    public static func assigning(
        _ wallpaper: WallpaperID, to display: DisplayKey, space: SpaceKey? = nil, in assignments: [DisplayAssignment]
    ) -> [DisplayAssignment] {
        let slot = AssignmentSlot(display: display, space: space)
        return clearing(slot, in: assignments) + [DisplayAssignment(display: display, wallpaper: wallpaper, space: space)]
    }

    /// Edits the rotation of one slot. Fewer than two remaining items become a single wallpaper;
    /// no items removes the assignment.
    public static func updatingRotation(
        in slot: AssignmentSlot, _ transform: (Rotation) -> Rotation, assignments: [DisplayAssignment]
    ) -> [DisplayAssignment] {
        guard let current = assignments.assignment(in: slot), let rotation = current.rotation else { return assignments }
        let edited = transform(rotation)
        guard let first = edited.items.first else { return clearing(slot, in: assignments) }
        let updated = DisplayAssignment(
            display: current.display, wallpaper: first, overrides: current.overrides, fill: current.fill,
            rotation: edited, space: current.space
        )
        return assignments.map { $0.slot == slot ? updated : $0 }
    }

    /// Removes the assignment of one slot (a Space-specific one, or the display default).
    public static func clearing(_ slot: AssignmentSlot, in assignments: [DisplayAssignment]) -> [DisplayAssignment] {
        assignments.filter { $0.slot != slot }
    }
}
