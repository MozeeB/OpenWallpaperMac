import Foundation
import OWCore

/// Tracks where each display is in its rotation and decides when to switch. Pure: time and
/// randomness are passed in, so it is fully unit-testable.
struct RotationTracker {
    struct Entry: Equatable {
        let rotation: Rotation
        var index: Int
        var lastSwitch: Date
    }

    private(set) var entries: [DisplayKey: Entry] = [:]

    var isActive: Bool { !entries.isEmpty }

    /// Adopts new assignments. Unchanged rotations keep their position; a new item list restarts.
    mutating func sync(_ assignments: [DisplayKey: DisplayAssignment], now: Date) {
        var next: [DisplayKey: Entry] = [:]
        for (key, assignment) in assignments {
            guard let rotation = assignment.rotation else { continue }
            if let existing = entries[key], existing.rotation.items == rotation.items {
                next[key] = Entry(rotation: rotation, index: existing.index, lastSwitch: existing.lastSwitch)
            } else {
                next[key] = Entry(rotation: rotation, index: 0, lastSwitch: now)
            }
        }
        entries = next
    }

    /// The wallpaper a display should show right now.
    func wallpaper(for assignment: DisplayAssignment) -> WallpaperID {
        guard let entry = entries[assignment.display], entry.rotation.items.indices.contains(entry.index) else {
            return assignment.wallpaper
        }
        return entry.rotation.items[entry.index]
    }

    /// 1-based position and item count, for display in the UI.
    func position(for display: DisplayKey) -> (current: Int, count: Int)? {
        entries[display].map { ($0.index + 1, $0.rotation.items.count) }
    }

    /// Advances every rotation whose interval has elapsed. A display that is not playing holds its
    /// timer, so a paused or covered wallpaper does not skip ahead. Returns the displays that switched.
    mutating func advance<G: RandomNumberGenerator>(
        now: Date, isPlaying: (DisplayKey) -> Bool, using generator: inout G
    ) -> [DisplayKey] {
        var switched: [DisplayKey] = []
        for key in entries.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard var entry = entries[key] else { continue }
            if !isPlaying(key) {
                entry.lastSwitch = now
            } else if now.timeIntervalSince(entry.lastSwitch) >= entry.rotation.interval {
                entry.index = entry.rotation.nextIndex(after: entry.index, using: &generator)
                entry.lastSwitch = now
                switched.append(key)
            }
            entries[key] = entry
        }
        return switched
    }

    /// Jumps to the next item immediately (menu "Next Wallpaper"). Returns false without a rotation.
    mutating func skip<G: RandomNumberGenerator>(_ display: DisplayKey, now: Date, using generator: inout G) -> Bool {
        guard var entry = entries[display] else { return false }
        entry.index = entry.rotation.nextIndex(after: entry.index, using: &generator)
        entry.lastSwitch = now
        entries[display] = entry
        return true
    }
}
