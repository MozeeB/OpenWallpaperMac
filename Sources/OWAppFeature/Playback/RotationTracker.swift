import Foundation
import OWCore

/// Tracks where each assignment slot (display, or display + Space) is in its rotation and decides
/// when to switch. Pure: time and randomness are passed in, so it is fully unit-testable.
struct RotationTracker {
    struct Entry: Equatable {
        let rotation: Rotation
        var index: Int
        var lastSwitch: Date
    }

    private(set) var entries: [AssignmentSlot: Entry] = [:]

    var isActive: Bool { !entries.isEmpty }

    /// Adopts new assignments. Edits (interval, shuffle, reorder, add/remove) keep the wallpaper that is
    /// showing when it is still in the list; otherwise the rotation starts from its first item.
    mutating func sync(_ assignments: [DisplayAssignment], now: Date) {
        var next: [AssignmentSlot: Entry] = [:]
        for assignment in assignments {
            let key = assignment.slot
            guard let rotation = assignment.rotation else { continue }
            if let existing = entries[key], existing.rotation.items.indices.contains(existing.index),
               let index = rotation.items.firstIndex(of: existing.rotation.items[existing.index]) {
                next[key] = Entry(rotation: rotation, index: index, lastSwitch: existing.lastSwitch)
            } else {
                next[key] = Entry(rotation: rotation, index: 0, lastSwitch: now)
            }
        }
        entries = next
    }

    /// The wallpaper a display should show right now.
    func wallpaper(for assignment: DisplayAssignment) -> WallpaperID {
        guard let entry = entries[assignment.slot], entry.rotation.items.indices.contains(entry.index) else {
            return assignment.wallpaper
        }
        return entry.rotation.items[entry.index]
    }

    /// 1-based position and item count, for display in the UI.
    func position(for slot: AssignmentSlot) -> (current: Int, count: Int)? {
        entries[slot].map { ($0.index + 1, $0.rotation.items.count) }
    }

    /// Advances every rotation whose interval has elapsed. A slot that is not playing (paused, covered,
    /// or on a Space that is not active) holds its timer. Returns the slots that switched.
    mutating func advance<G: RandomNumberGenerator>(
        now: Date, isPlaying: (AssignmentSlot) -> Bool, using generator: inout G
    ) -> [AssignmentSlot] {
        var switched: [AssignmentSlot] = []
        for key in entries.keys.sorted(by: RotationTracker.order) {
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

    private static func order(_ lhs: AssignmentSlot, _ rhs: AssignmentSlot) -> Bool {
        (lhs.display.rawValue, lhs.space?.rawValue ?? "") < (rhs.display.rawValue, rhs.space?.rawValue ?? "")
    }

    /// Jumps to the next item immediately (menu "Next Wallpaper"). Returns false without a rotation.
    mutating func skip<G: RandomNumberGenerator>(_ slot: AssignmentSlot, now: Date, using generator: inout G) -> Bool {
        guard var entry = entries[slot] else { return false }
        entry.index = entry.rotation.nextIndex(after: entry.index, using: &generator)
        entry.lastSwitch = now
        entries[slot] = entry
        return true
    }
}
