import AppKit
import Foundation
import Testing
@testable import OWAppFeature
@testable import OWCore
@testable import OWLibrary

private let a = DisplayKey("A")
private let ids = (0 ..< 4).map { WallpaperID("e\($0)") }

@Suite("Rotation editing model")
struct RotationEditingModelTests {
    @Test("edit helpers reorder, add, remove and change settings")
    func helpers() {
        let rotation = Rotation(items: [ids[0], ids[1], ids[2]], interval: 5)
        #expect(rotation.moving(at: 0, by: 1).items == [ids[1], ids[0], ids[2]])
        #expect(rotation.moving(at: 2, by: -1).items == [ids[0], ids[2], ids[1]])
        #expect(rotation.moving(at: 0, by: -5).items == rotation.items)
        #expect(rotation.moving(at: 9, by: 1) == rotation)
        #expect(rotation.removing(ids[1]).items == [ids[0], ids[2]])
        #expect(rotation.adding([ids[3], ids[0]]).items == [ids[0], ids[1], ids[2], ids[3]])
        #expect(rotation.with(interval: 120, shuffle: true).interval == 120)
        #expect(rotation.with(shuffle: true).shuffle)
    }

    @Test("split picks the largest whole unit")
    func split() {
        #expect(Rotation.split(90) == (90, .seconds))
        #expect(Rotation.split(120) == (2, .minutes))
        #expect(Rotation.split(5400) == (1.5, .hours))
        #expect(Rotation.split(7200) == (2, .hours))
        #expect(Rotation.split(3660) == (61, .minutes))
    }

    @Test("updating a slot's rotation collapses or clears when items run out")
    func updating() {
        let slot = AssignmentSlot(display: a)
        let start = [DisplayAssignment(display: a, wallpaper: ids[0], fill: .fit, rotation: Rotation(items: [ids[0], ids[1]]))]
        let slower = LibraryIndex.updatingRotation(in: slot, { $0.with(interval: 60) }, assignments: start)
        #expect(slower[0].rotation?.interval == 60)
        #expect(slower[0].fill == .fit)
        let single = LibraryIndex.updatingRotation(in: slot, { $0.removing(ids[0]) }, assignments: start)
        #expect(single[0].rotation == nil)
        #expect(single[0].wallpaper == ids[1])
        let empty = LibraryIndex.updatingRotation(in: slot, { $0.with(items: []) }, assignments: start)
        #expect(empty.isEmpty)
        let untouched = [DisplayAssignment(display: a, wallpaper: ids[0])]
        #expect(LibraryIndex.updatingRotation(in: slot, { $0.with(interval: 60) }, assignments: untouched) == untouched)
    }

    @Test("tracker keeps showing the same wallpaper through edits")
    func trackerKeepsCurrent() {
        var tracker = RotationTracker()
        var generator = SystemRandomNumberGenerator()
        let slot = AssignmentSlot(display: a)
        let now = Date()
        tracker.sync([DisplayAssignment(display: a, wallpaper: ids[0], rotation: Rotation(items: [ids[0], ids[1], ids[2]]))], now: now)
        _ = tracker.skip(slot, now: now, using: &generator)
        let showing = [ids[0], ids[1], ids[2]][tracker.entries[slot]!.index]
        let reordered = Rotation(items: [ids[2], ids[1], ids[0]], interval: 60)
        tracker.sync([DisplayAssignment(display: a, wallpaper: ids[2], rotation: reordered)], now: now)
        #expect(reordered.items[tracker.entries[slot]!.index] == showing)
        let withoutShowing = Rotation(items: [ids[3]] + reordered.items.filter { $0 != showing })
        tracker.sync([DisplayAssignment(display: a, wallpaper: ids[3], rotation: withoutShowing)], now: now)
        #expect(tracker.entries[slot]?.index == 0, "restarts when the showing item was removed")
    }
}

@Suite("AppModel rotation editing & active lists")
@MainActor
struct AppModelRotationEditingTests {
    @Test("edit a running rotation, make one from a single wallpaper, list active wallpapers")
    func editing() async {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("owedit-\(UUID())")
        defer { try? FileManager.default.removeItem(at: base) }
        let h = CoordinatorHarness(displays: ["A", "B"])
        let model = AppModel(
            store: StateStore(fileURL: base.appendingPathComponent("state.json")),
            importer: ImportService(libraryRoot: base.appendingPathComponent("L"), knownEffects: []),
            thumbnails: ThumbnailService(cacheDirectory: base.appendingPathComponent("T")),
            coordinator: h.coordinator, steam: SteamLibraryLocator(steamRoot: base), loginItem: InMemoryLoginItem()
        )
        await model.bootstrap()
        let items = (0 ..< 3).map { _ in CoordinatorHarness.wallpaper(.image) }
        model.commit(model.state.with(library: items))
        let slotA = AssignmentSlot(display: DisplayKey("A"))

        model.setRotation([items[0].id, items[1].id], interval: 5, shuffle: false, display: DisplayKey("A"))
        model.assign(items[2].id, to: DisplayKey("B"))
        #expect(model.activeWallpaperIDs == Set(items.map(\.id)))
        #expect(model.activeLocations(for: items[2].id) == ["On Display B"])
        #expect(model.activeLocations(for: items[1].id).first?.hasSuffix("on Display A") == true)
        #expect(model.slots(on: DisplayKey("A")).map(\.title) == ["This display"])

        model.updateRotation(in: slotA) { $0.with(interval: 90, shuffle: true) }
        #expect(model.assignment(for: DisplayKey("A"))?.rotation?.interval == 90)
        #expect(model.assignment(for: DisplayKey("A"))?.rotation?.shuffle == true)
        model.updateRotation(in: slotA) { $0.adding([items[2].id]).moving(at: 2, by: -2) }
        #expect(model.assignment(for: DisplayKey("A"))?.rotation?.items == [items[2].id, items[0].id, items[1].id])

        let slotB = AssignmentSlot(display: DisplayKey("B"))
        model.makeRotation(in: slotB, adding: [items[0].id])
        #expect(model.assignment(for: DisplayKey("B"))?.rotation?.items == [items[2].id, items[0].id])
        model.makeRotation(in: AssignmentSlot(display: DisplayKey("none")), adding: [items[0].id])
        #expect(model.state.assignments.count == 2)

        model.clearAssignment(for: DisplayKey("B"))
        #expect(model.activeLocations(for: items[2].id).allSatisfy { $0.hasSuffix("Display A") })
        model.shutdown()
    }
}
