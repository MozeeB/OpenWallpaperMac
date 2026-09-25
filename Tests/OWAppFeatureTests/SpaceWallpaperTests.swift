import AppKit
import Foundation
import Testing
@testable import OWAppFeature
@testable import OWCore
@testable import OWDesktop
@testable import OWLibrary

private let a = DisplayKey("A")
private let one = SpaceInfo(key: SpaceKey("space-1"), number: 1)
private let two = SpaceInfo(key: SpaceKey("space-2"), number: 2)

@MainActor
final class FakeSpaces: SpaceProviding {
    var isAvailable = true
    var current: SpaceKey? = one.key
    func snapshot(displays: [DisplayKey]) -> [DisplayKey: DisplaySpaces] {
        Dictionary(uniqueKeysWithValues: displays.map { ($0, DisplaySpaces(spaces: [one, two], current: current)) })
    }
}

@Suite("Per-Space assignments")
struct SpaceAssignmentModelTests {
    let w = (0 ..< 3).map { WallpaperID("w\($0)") }

    @Test("a Space's own assignment wins over the display default")
    func effective() {
        let list = [
            DisplayAssignment(display: a, wallpaper: w[0]),
            DisplayAssignment(display: a, wallpaper: w[1], space: two.key),
        ]
        #expect(list.effective(for: a, space: one.key)?.wallpaper == w[0])
        #expect(list.effective(for: a, space: two.key)?.wallpaper == w[1])
        #expect(list.effective(for: a, space: nil)?.wallpaper == w[0])
        #expect([DisplayAssignment(display: a, wallpaper: w[1], space: two.key)].effective(for: a, space: one.key) == nil)
    }

    @Test("library helpers replace only the targeted slot")
    func slots() {
        var list = LibraryIndex.assigning(w[0], to: a, in: [])
        list = LibraryIndex.assigning(w[1], to: a, space: two.key, in: list)
        #expect(list.count == 2)
        list = LibraryIndex.assigning(w[2], to: a, space: two.key, in: list)
        #expect(list.count == 2)
        #expect(list.assignment(in: AssignmentSlot(display: a, space: two.key))?.wallpaper == w[2])
        list = LibraryIndex.rotating([w[0], w[1]], interval: 90, shuffle: false, on: a, space: one.key, in: list)
        #expect(list.count == 3)
        list = LibraryIndex.clearing(AssignmentSlot(display: a, space: two.key), in: list)
        #expect(list.map(\.space) .contains(two.key) == false)
        #expect(list.assignment(in: AssignmentSlot(display: a))?.wallpaper == w[0], "default untouched")
        let decoded = try? JSONDecoder().decode(DisplayAssignment.self, from: JSONEncoder().encode(list[1]))
        #expect(decoded == list[1], "Space survives persistence")
    }

    @Test("custom intervals convert, validate and label")
    func customInterval() {
        #expect(Rotation.customInterval(90, unit: .seconds) == 90)
        #expect(Rotation.customInterval(2, unit: .minutes) == 120)
        #expect(Rotation.customInterval(1.5, unit: .hours) == 5400)
        #expect(Rotation.customInterval(4, unit: .seconds) == nil)
        #expect(Rotation.customInterval(25, unit: .hours) == nil)
        #expect(Rotation.customInterval(.nan, unit: .minutes) == nil)
        #expect(Rotation.label(for: 90) == "90 s")
        #expect(Rotation.label(for: 120) == "2 min")
        #expect(Rotation.label(for: 2700) == "45 min")
        #expect(Rotation.label(for: 5400) == "1.5 h")
        #expect(Rotation.label(for: 7200) == "2 h")
        #expect(Rotation.Unit.hours.seconds == 3600)
    }
}

@Suite("Coordinator per-Space")
@MainActor
struct CoordinatorSpaceTests {
    private func harness(_ spaces: FakeSpaces) -> CoordinatorHarness {
        CoordinatorHarness(spaces: SpaceMonitor(provider: spaces))
    }

    @Test("switching Spaces cross-fades to that Space's wallpaper")
    func switching() async {
        let spaces = FakeSpaces()
        let h = harness(spaces)
        var events: [CoordinatorEvent] = []
        h.coordinator.onEvent = { events.append($0) }
        h.coordinator.start()
        let desk = CoordinatorHarness.wallpaper(.image)
        let focus = CoordinatorHarness.wallpaper(.video)
        h.coordinator.update(library: [desk, focus], assignments: [
            DisplayAssignment(display: a, wallpaper: desk.id),
            DisplayAssignment(display: a, wallpaper: focus.id, space: two.key),
        ], settings: .default)
        #expect(h.coordinator.supportsSpaces)
        #expect(await eventually { h.coordinator.sessions[a]?.phase == .ready })
        #expect(h.coordinator.activeWallpaper(for: a) == desk.id)

        spaces.current = two.key
        h.coordinator.spaces?.refresh()
        #expect(events.contains(.spacesChanged))
        #expect(h.coordinator.effectiveAssignment(for: a)?.space == two.key)
        #expect(await eventually { h.coordinator.activeWallpaper(for: a) == focus.id })

        spaces.current = one.key
        h.coordinator.spaces?.refresh()
        #expect(await eventually { h.coordinator.activeWallpaper(for: a) == desk.id })
        #expect(h.coordinator.spaces(on: a)?.spaces.count == 2)
        h.coordinator.stop(restoreOriginalWallpaper: false)
    }

    @Test("rotations on hidden Spaces hold; the visible one advances")
    func rotationsPerSpace() async {
        let spaces = FakeSpaces()
        let h = harness(spaces)
        h.coordinator.start()
        let items = (0 ..< 4).map { _ in CoordinatorHarness.wallpaper(.image) }
        h.coordinator.update(library: items, assignments: [
            DisplayAssignment(display: a, wallpaper: items[0].id, rotation: Rotation(items: [items[0].id, items[1].id])),
            DisplayAssignment(display: a, wallpaper: items[2].id, rotation: Rotation(items: [items[2].id, items[3].id]), space: two.key),
        ], settings: .default)
        #expect(await eventually { h.coordinator.sessions[a]?.phase == .ready })
        h.coordinator.advanceRotations(now: Date().addingTimeInterval(6))
        #expect(await eventually { h.coordinator.activeWallpaper(for: a) == items[1].id })

        spaces.current = two.key
        h.coordinator.spaces?.refresh()
        #expect(await eventually { h.coordinator.activeWallpaper(for: a) == items[2].id }, "Space rotation starts at its first item")
        #expect(h.coordinator.rotationPosition(for: a)! == (1, 2))
        h.coordinator.skipToNext(on: a)
        #expect(await eventually { h.coordinator.activeWallpaper(for: a) == items[3].id })
        h.coordinator.stop(restoreOriginalWallpaper: false)
    }
}

@Suite("AppModel per-Space")
@MainActor
struct AppModelSpaceTests {
    @Test("assign, list and clear Space wallpapers; edits apply to what is showing")
    func model() async {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("owspace-\(UUID())")
        defer { try? FileManager.default.removeItem(at: base) }
        let spaces = FakeSpaces()
        let h = CoordinatorHarness(spaces: SpaceMonitor(provider: spaces))
        let model = AppModel(
            store: StateStore(fileURL: base.appendingPathComponent("state.json")),
            importer: ImportService(libraryRoot: base.appendingPathComponent("L"), knownEffects: []),
            thumbnails: ThumbnailService(cacheDirectory: base.appendingPathComponent("T")),
            coordinator: h.coordinator, steam: SteamLibraryLocator(steamRoot: base), loginItem: InMemoryLoginItem()
        )
        await model.bootstrap()
        let items = [CoordinatorHarness.wallpaper(.image), CoordinatorHarness.wallpaper(.image)]
        model.commit(model.state.with(library: items))
        #expect(model.supportsSpaces)
        #expect(model.spaces(on: a)?.spaces.count == 2)

        model.assign(items[0].id, to: a)
        model.assign(items[1].id, to: a, space: two.key)
        #expect(model.spaceAssignments(on: a).map(\.space.key) == [two.key])
        #expect(model.effectiveAssignment(for: a)?.wallpaper == items[0].id)

        spaces.current = two.key
        h.coordinator.spaces?.refresh()
        #expect(model.spacesRevision > 0)
        #expect(model.effectiveAssignment(for: a)?.space == two.key)
        model.setFill(.fit, display: a)
        #expect(model.assignment(for: a, space: two.key)?.fill == .fit, "edits target the Space being shown")
        #expect(model.assignment(for: a)?.fill == .fill)

        model.setRotation(items.map(\.id), interval: 90, shuffle: false, display: a, space: two.key)
        #expect(model.assignment(for: a, space: two.key)?.rotation?.interval == 90)
        model.stopRotation(on: a)
        #expect(model.assignment(for: a, space: two.key)?.rotation == nil)
        let kept = model.assignment(for: a, space: two.key)?.wallpaper
        model.addToRotation((kept == items[0].id ? items[1] : items[0]).id, display: a, space: two.key)
        #expect(model.assignment(for: a, space: two.key)?.rotation != nil)
        model.clearAssignment(for: a, space: two.key)
        #expect(model.spaceAssignments(on: a).isEmpty)
        #expect(model.activeWallpaper(for: a)?.id == items[0].id)
        model.shutdown()
    }
}
