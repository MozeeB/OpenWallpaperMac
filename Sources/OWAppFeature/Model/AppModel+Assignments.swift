import Foundation
import OWCore
import OWLibrary

/// Assigning wallpapers and rotations to displays, optionally to a single Space.
///
/// A `space` of nil targets the display default, which shows on every Space without its own
/// assignment. Edits made from the inspector apply to whatever is showing right now (the
/// "effective" assignment).
extension AppModel {
    // MARK: Spaces

    public var supportsSpaces: Bool { coordinator.supportsSpaces }

    public func spaces(on display: DisplayKey) -> DisplaySpaces? {
        _ = spacesRevision
        return coordinator.spaces(on: display)
    }

    /// Space-specific assignments of a display, in desktop order.
    public func spaceAssignments(on display: DisplayKey) -> [(space: SpaceInfo, assignment: DisplayAssignment)] {
        let known = spaces(on: display)?.spaces ?? []
        return known.compactMap { info in
            state.assignments.assignment(in: AssignmentSlot(display: display, space: info.key)).map { (info, $0) }
        }
    }

    // MARK: Lookup

    /// The assignment of one slot: the display default when `space` is nil.
    public func assignment(for display: DisplayKey, space: SpaceKey? = nil) -> DisplayAssignment? {
        state.assignments.assignment(in: AssignmentSlot(display: display, space: space))
    }

    /// What applies on the display right now (the active Space's own assignment, else the default).
    ///
    /// Computed from `state` (observable) so views refresh on every change; only the active Space
    /// comes from the coordinator, and `spacesRevision` makes Space switches observable too.
    public func effectiveAssignment(for display: DisplayKey) -> DisplayAssignment? {
        _ = spacesRevision
        let space = coordinator.spaces(on: display)?.current
        return state.assignments.effective(for: display, space: space)
    }

    public func activeWallpaper(for display: DisplayKey) -> Wallpaper? {
        effectiveAssignment(for: display).flatMap { assignment in
            let id = coordinator.activeWallpaper(for: display) ?? assignment.wallpaper
            return state.library.first { $0.id == id }
        }
    }

    /// 1-based position within the rotation showing on a display, if it has one.
    public func rotationPosition(for display: DisplayKey) -> (current: Int, count: Int)? {
        guard effectiveAssignment(for: display)?.rotation != nil else { return nil }
        return coordinator.rotationPosition(for: display)
    }

    // MARK: Assign

    /// Assigns to one display (or one of its Spaces), or to every connected display when `display` is nil.
    public func assign(_ id: WallpaperID, to display: DisplayKey?, space: SpaceKey? = nil) {
        let targets = display.map { [$0] } ?? displays.map(\.key)
        let assignments = targets.reduce(state.assignments) { LibraryIndex.assigning(id, to: $1, space: space, in: $0) }
        commit(state.with(assignments: assignments))
    }

    /// Rotates `wallpapers` on one display (or one of its Spaces), or on every display when `display` is nil.
    public func setRotation(
        _ wallpapers: [WallpaperID], interval: TimeInterval, shuffle: Bool, display: DisplayKey?, space: SpaceKey? = nil
    ) {
        let targets = display.map { [$0] } ?? displays.map(\.key)
        let assignments = targets.reduce(state.assignments) { result, key in
            LibraryIndex.rotating(wallpapers, interval: interval, shuffle: shuffle, on: key, space: space, in: result)
        }
        commit(state.with(assignments: assignments))
    }

    /// Appends a wallpaper to a slot's rotation, starting one from its current wallpaper if needed.
    public func addToRotation(_ id: WallpaperID, display: DisplayKey, space: SpaceKey? = nil) {
        guard let current = assignment(for: display, space: space) else {
            assign(id, to: display, space: space)
            return
        }
        let items = current.wallpapers.contains(id) ? current.wallpapers : current.wallpapers + [id]
        setRotation(items, interval: current.rotation?.interval ?? Rotation.presetIntervals[0],
                    shuffle: current.rotation?.shuffle ?? false, display: display, space: space)
    }

    /// Stops the rotation showing on a display (or the given slot) and keeps the wallpaper on screen.
    public func stopRotation(on display: DisplayKey, space: SpaceKey? = nil) {
        let target = space.flatMap { assignment(for: display, space: $0) } ?? effectiveAssignment(for: display)
        guard let assignment = target, assignment.rotation != nil else { return }
        let showing = coordinator.activeWallpaper(for: display).flatMap { id in
            assignment.wallpapers.contains(id) ? id : nil
        } ?? assignment.wallpaper
        let single = DisplayAssignment(
            display: display, wallpaper: showing, overrides: assignment.overrides, fill: assignment.fill,
            space: assignment.space
        )
        commit(state.with(assignments: state.assignments.map { $0.slot == assignment.slot ? single : $0 }))
    }

    /// Jumps to the next wallpaper of the rotation showing on a display.
    public func nextWallpaper(on display: DisplayKey) {
        coordinator.skipToNext(on: display)
        refreshDisplays()
    }

    /// Removes one slot's assignment (the display default when `space` is nil).
    public func clearAssignment(for display: DisplayKey, space: SpaceKey? = nil) {
        let slot = AssignmentSlot(display: display, space: space)
        commit(state.with(assignments: LibraryIndex.clearing(slot, in: state.assignments)))
    }

    // MARK: Properties (apply to what is showing)

    public func setOverride(_ value: PropertyValue, key: String, display: DisplayKey) {
        updateEffectiveAssignment(display) { $0.with(overrides: $0.overrides.merging([key: value]) { _, new in new }) }
    }

    public func resetOverrides(display: DisplayKey) {
        updateEffectiveAssignment(display) { $0.with(overrides: [:]) }
    }

    public func setFill(_ fill: FillMode, display: DisplayKey) {
        updateEffectiveAssignment(display) { $0.with(fill: fill) }
    }

    private func updateEffectiveAssignment(_ display: DisplayKey, _ transform: (DisplayAssignment) -> DisplayAssignment) {
        guard let slot = effectiveAssignment(for: display)?.slot else { return }
        let assignments = state.assignments.map { $0.slot == slot ? transform($0) : $0 }
        commit(state.with(assignments: assignments))
    }
}
