import AppKit
import Foundation
import Testing
@testable import OWAppFeature
@testable import OWCore
@testable import OWLibrary

private struct FixedGenerator: RandomNumberGenerator {
    var value: UInt64
    mutating func next() -> UInt64 { value }
}

private let a = DisplayKey("A")
private let b = DisplayKey("B")
private let ids = (0 ..< 4).map { WallpaperID("w\($0)") }

@Suite("Rotation model")
struct RotationModelTests {
    @Test("dedupes items, clamps interval, labels presets")
    func model() {
        let rotation = Rotation(items: [ids[0], ids[1], ids[0]], interval: 1)
        #expect(rotation.items == [ids[0], ids[1]])
        #expect(rotation.interval == 5)
        #expect(Rotation(items: ids, interval: 1_000_000).interval == 86_400)
        #expect(Rotation(items: ids, interval: .nan).interval == 5)
        #expect(Rotation.presetIntervals.map(Rotation.label) == ["5 s", "10 s", "30 s", "1 min", "5 min", "15 min", "30 min", "1 h"])
    }

    @Test("sequential and shuffled order never repeat the current item")
    func order() {
        var generator = FixedGenerator(value: 0)
        let sequential = Rotation(items: ids)
        #expect(sequential.nextIndex(after: 0, using: &generator) == 1)
        #expect(sequential.nextIndex(after: 3, using: &generator) == 0)
        var system = SystemRandomNumberGenerator()
        let shuffled = Rotation(items: ids, shuffle: true)
        for current in 0 ..< ids.count {
            for _ in 0 ..< 50 { #expect(shuffled.nextIndex(after: current, using: &system) != current) }
        }
        #expect(Rotation(items: [ids[0]]).nextIndex(after: 0, using: &system) == 0)
    }

    @Test("assignments keep rotations of two or more items only")
    func assignment() {
        let single = DisplayAssignment(display: a, wallpaper: ids[0], rotation: Rotation(items: [ids[0]]))
        #expect(single.rotation == nil)
        let rotating = DisplayAssignment(display: a, wallpaper: ids[0]).with(rotation: Rotation(items: [ids[2], ids[3]]))
        #expect(rotating.wallpaper == ids[2])
        #expect(rotating.wallpapers == [ids[2], ids[3]])
        #expect(rotating.with(fill: .fit).rotation == rotating.rotation)
        #expect(rotating.with(overrides: ["x": .bool(true)]).rotation == rotating.rotation)
    }

    @Test("persists and decodes older assignments without a rotation")
    func codable() throws {
        let old = Data(#"{"display":"A","wallpaper":"w0","overrides":{},"fill":"fill"}"#.utf8)
        #expect(try JSONDecoder().decode(DisplayAssignment.self, from: old).rotation == nil)
        let rotating = DisplayAssignment(display: a, wallpaper: ids[0], rotation: Rotation(items: ids, interval: 30, shuffle: true))
        #expect(try JSONDecoder().decode(DisplayAssignment.self, from: JSONEncoder().encode(rotating)) == rotating)
    }
}

@Suite("Library rotation helpers")
struct LibraryRotationTests {
    private func wallpaper(_ id: WallpaperID) throws -> Wallpaper {
        Wallpaper(id: id, title: id.rawValue, type: .image, origin: .native, root: URL(fileURLWithPath: "/tmp/\(id)"), entry: try SanitizedPath("a.png"))
    }

    @Test("rotating replaces a display's assignment and keeps its settings")
    func rotating() {
        let existing = [DisplayAssignment(display: a, wallpaper: ids[0], overrides: ["k": .bool(true)], fill: .fit)]
        let result = LibraryIndex.rotating([ids[1], ids[2]], interval: 10, shuffle: true, on: a, in: existing)
        #expect(result.count == 1)
        #expect(result[0].rotation == Rotation(items: [ids[1], ids[2]], interval: 10, shuffle: true))
        #expect(result[0].fill == .fit && result[0].overrides["k"] == .bool(true))
        #expect(LibraryIndex.rotating([], interval: 5, shuffle: false, on: a, in: existing).isEmpty)
        #expect(LibraryIndex.rotating([ids[3]], interval: 5, shuffle: false, on: a, in: existing)[0].rotation == nil)
    }

    @Test("pruning drops removed items and collapses short rotations")
    func pruning() throws {
        let assignments = [
            DisplayAssignment(display: a, wallpaper: ids[0], rotation: Rotation(items: [ids[0], ids[1], ids[2]])),
            DisplayAssignment(display: b, wallpaper: ids[3], rotation: Rotation(items: [ids[3], ids[1]])),
        ]
        let library = try [ids[1], ids[2], ids[3]].map(wallpaper)
        let pruned = LibraryIndex.pruning(assignments, library: library)
        #expect(pruned[0].rotation?.items == [ids[1], ids[2]])
        #expect(pruned[0].wallpaper == ids[1])
        #expect(pruned[1].rotation?.items == [ids[3], ids[1]])
        let tiny = LibraryIndex.pruning(assignments, library: try [ids[1]].map(wallpaper))
        #expect(tiny.map(\.rotation) == [nil, nil])
        #expect(tiny.map(\.wallpaper) == [ids[1], ids[1]])
    }
}

@Suite("RotationTracker")
struct RotationTrackerTests {
    let start = Date(timeIntervalSince1970: 1000)
    let slotA = AssignmentSlot(display: a)
    let spaceTwo = AssignmentSlot(display: a, space: SpaceKey("desktop-2"))

    private func tracker(interval: TimeInterval = 5) -> RotationTracker {
        var tracker = RotationTracker()
        tracker.sync([DisplayAssignment(display: a, wallpaper: ids[0], rotation: Rotation(items: ids, interval: interval))], now: start)
        return tracker
    }

    @Test("switches exactly when the interval elapses")
    func timing() {
        var tracker = tracker()
        var generator = FixedGenerator(value: 0)
        let assignment = DisplayAssignment(display: a, wallpaper: ids[0], rotation: Rotation(items: ids))
        #expect(tracker.advance(now: start.addingTimeInterval(4.9), isPlaying: { _ in true }, using: &generator).isEmpty)
        #expect(tracker.advance(now: start.addingTimeInterval(5), isPlaying: { _ in true }, using: &generator) == [slotA])
        #expect(tracker.wallpaper(for: assignment) == ids[1])
        #expect(tracker.position(for: slotA)! == (2, 4))
        #expect(tracker.advance(now: start.addingTimeInterval(9), isPlaying: { _ in true }, using: &generator).isEmpty)
        #expect(tracker.advance(now: start.addingTimeInterval(10), isPlaying: { _ in true }, using: &generator) == [slotA])
    }

    @Test("paused slots hold their timer")
    func pausedHolds() {
        var tracker = tracker()
        var generator = FixedGenerator(value: 0)
        #expect(tracker.advance(now: start.addingTimeInterval(60), isPlaying: { _ in false }, using: &generator).isEmpty)
        #expect(tracker.advance(now: start.addingTimeInterval(64), isPlaying: { _ in true }, using: &generator).isEmpty,
                "a full interval must pass after resuming")
        #expect(tracker.advance(now: start.addingTimeInterval(65), isPlaying: { _ in true }, using: &generator) == [slotA])
    }

    @Test("display default and a Space rotation advance independently")
    func perSpace() {
        var tracker = RotationTracker()
        var generator = FixedGenerator(value: 0)
        let spaceAssignment = DisplayAssignment(
            display: a, wallpaper: ids[2], rotation: Rotation(items: [ids[2], ids[3]]), space: spaceTwo.space
        )
        tracker.sync([
            DisplayAssignment(display: a, wallpaper: ids[0], rotation: Rotation(items: [ids[0], ids[1]])), spaceAssignment,
        ], now: start)
        // Only the Space rotation is on screen.
        let switched = tracker.advance(now: start.addingTimeInterval(5), isPlaying: { $0 == spaceTwo }, using: &generator)
        #expect(switched == [spaceTwo])
        #expect(tracker.wallpaper(for: spaceAssignment) == ids[3])
        #expect(tracker.position(for: slotA)! == (1, 2), "hidden default rotation did not move")
    }

    @Test("sync keeps position when only settings change, restarts on new items, removes old")
    func sync() {
        var tracker = tracker()
        var generator = FixedGenerator(value: 0)
        _ = tracker.skip(slotA, now: start, using: &generator)
        tracker.sync([DisplayAssignment(display: a, wallpaper: ids[0], rotation: Rotation(items: ids, interval: 60))], now: start)
        #expect(tracker.entries[slotA]?.index == 1)
        #expect(tracker.entries[slotA]?.rotation.interval == 60)
        tracker.sync([DisplayAssignment(display: a, wallpaper: ids[0], rotation: Rotation(items: [ids[2], ids[3]]))], now: start)
        #expect(tracker.entries[slotA]?.index == 0)
        tracker.sync([DisplayAssignment(display: a, wallpaper: ids[0])], now: start)
        #expect(!tracker.isActive)
        #expect(tracker.wallpaper(for: DisplayAssignment(display: a, wallpaper: ids[3])) == ids[3])
        #expect(!tracker.skip(slotA, now: start, using: &generator))
        #expect(tracker.position(for: slotA) == nil)
    }
}

@Suite("Coordinator rotation")
@MainActor
struct CoordinatorRotationTests {
    @Test("rotates through wallpapers with cross-fades, holds while paused, supports skip")
    func rotates() async {
        let h = CoordinatorHarness()
        h.coordinator.start()
        let items = [CoordinatorHarness.wallpaper(.image), CoordinatorHarness.wallpaper(.video), CoordinatorHarness.wallpaper(.shader)]
        let rotation = Rotation(items: items.map(\.id), interval: 5)
        h.coordinator.update(library: items, assignments: [DisplayAssignment(display: a, wallpaper: items[0].id, rotation: rotation)], settings: .default)
        #expect(h.coordinator.isRotationTimerRunning)
        #expect(await eventually { h.coordinator.sessions[a]?.phase == .ready })
        #expect(h.coordinator.activeWallpaper(for: a) == items[0].id)
        #expect(h.coordinator.rotationPosition(for: a)! == (1, 3))

        h.coordinator.advanceRotations(now: Date().addingTimeInterval(6))
        #expect(h.coordinator.pending[a] != nil, "next wallpaper loads in the background")
        #expect(await eventually { h.coordinator.activeWallpaper(for: a) == items[1].id })
        #expect(await eventually { h.factory.created[0].tornDown }, "previous wallpaper retired after the fade")

        h.coordinator.setUserPaused(true)
        h.coordinator.advanceRotations(now: Date().addingTimeInterval(60))
        #expect(h.coordinator.activeWallpaper(for: a) == items[1].id, "no switching while paused")
        h.coordinator.setUserPaused(false)

        h.coordinator.skipToNext(on: a)
        #expect(await eventually { h.coordinator.activeWallpaper(for: a) == items[2].id })
        #expect(h.coordinator.rotationPosition(for: a)! == (3, 3))

        h.coordinator.update(library: items, assignments: [DisplayAssignment(display: a, wallpaper: items[0].id)], settings: .default)
        #expect(!h.coordinator.isRotationTimerRunning, "timer stops when no rotation is active")
        h.coordinator.stop(restoreOriginalWallpaper: false)
    }

    @Test("a failing rotation item keeps the current wallpaper and falls back to its preview")
    func failingItem() async {
        let h = CoordinatorHarness()
        var events: [CoordinatorEvent] = []
        h.coordinator.onEvent = { events.append($0) }
        h.coordinator.start()
        let good = CoordinatorHarness.wallpaper(.image)
        let broken = CoordinatorHarness.wallpaper(.web)
        h.coordinator.update(library: [good, broken], assignments: [
            DisplayAssignment(display: a, wallpaper: good.id, rotation: Rotation(items: [good.id, broken.id], interval: 5)),
        ], settings: .default)
        #expect(await eventually { h.coordinator.sessions[a]?.phase == .ready })
        h.factory.failNextLoad = .web("boom")
        h.coordinator.advanceRotations(now: Date().addingTimeInterval(6))
        #expect(await eventually { events.contains(.failed(a, broken.id, .web("boom"))) })
        #expect(await eventually { events.contains(.fellBackToPreview(a, broken.id)) })
        #expect(await eventually { h.coordinator.activeWallpaper(for: a) == broken.id }, "preview of the broken item is shown")
        #expect(await eventually { h.factory.created[0].tornDown }, "good wallpaper stayed until the preview was ready")
        h.coordinator.stop(restoreOriginalWallpaper: false)
    }
}

@Suite("AppModel rotation")
@MainActor
struct AppModelRotationTests {
    @Test("sets, reads and stops rotations per display")
    func model() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("owrot-\(UUID())")
        defer { try? FileManager.default.removeItem(at: base) }
        let h = CoordinatorHarness(displays: ["A", "B"])
        let model = AppModel(
            store: StateStore(fileURL: base.appendingPathComponent("state.json")),
            importer: ImportService(libraryRoot: base.appendingPathComponent("L"), knownEffects: []),
            thumbnails: ThumbnailService(cacheDirectory: base.appendingPathComponent("T")),
            coordinator: h.coordinator, steam: SteamLibraryLocator(steamRoot: base), loginItem: InMemoryLoginItem()
        )
        await model.bootstrap()
        let items = [CoordinatorHarness.wallpaper(.image), CoordinatorHarness.wallpaper(.image)]
        model.commit(model.state.with(library: items))

        model.setRotation(items.map(\.id), interval: 10, shuffle: true, display: DisplayKey("A"))
        #expect(model.assignment(for: DisplayKey("A"))?.rotation == Rotation(items: items.map(\.id), interval: 10, shuffle: true))
        #expect(model.assignment(for: DisplayKey("B")) == nil)
        model.setRotation(items.map(\.id), interval: 5, shuffle: false, display: nil)
        #expect(model.state.assignments.allSatisfy { $0.rotation?.interval == 5 })
        #expect(model.rotationPosition(for: DisplayKey("A")) != nil)
        model.nextWallpaper(on: DisplayKey("A"))

        model.stopRotation(on: DisplayKey("A"))
        #expect(model.assignment(for: DisplayKey("A"))?.rotation == nil)
        #expect(items.map(\.id).contains(model.assignment(for: DisplayKey("A"))?.wallpaper ?? WallpaperID("none")),
                "stopping keeps the wallpaper that is showing")
        model.remove(items[1].id)
        #expect(model.assignment(for: DisplayKey("B"))?.rotation == nil, "rotation collapses when an item is removed")
        model.shutdown()
    }
}
