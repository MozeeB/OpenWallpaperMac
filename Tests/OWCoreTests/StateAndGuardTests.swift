import Foundation
import Testing
@testable import OWCore

@Suite("JSONGuard")
struct JSONGuardTests {
    @Test("measures depth ignoring strings")
    func depth() {
        #expect(JSONGuard.maximumDepth(of: Data(#"{"a":[1,{"b":"[[[["}]}"#.utf8)) == 3)
        #expect(JSONGuard.maximumDepth(of: Data(#"{"a":"\"{"}"#.utf8)) == 1)
    }

    @Test("rejects deep, large, malformed and non-object input")
    func rejects() {
        let deep = Data((String(repeating: "[", count: 70) + String(repeating: "]", count: 70)).utf8)
        #expect(throws: JSONGuardError.tooDeep(70)) { try JSONGuard.check(deep) }
        #expect(throws: JSONGuardError.tooLarge(10)) { try JSONGuard.check(Data(count: 10), maxBytes: 5) }
        #expect(throws: JSONGuardError.notAnObject) { try JSONGuard.object(from: Data("[1]".utf8)) }
        #expect(throws: JSONGuardError.self) { try JSONGuard.object(from: Data("{nope".utf8)) }
    }

    @Test("parses objects")
    func parses() throws {
        let object = try JSONGuard.object(from: Data(#"{"x":1}"#.utf8))
        #expect(object["x"] as? Int == 1)
    }
}

@Suite("Settings & state")
struct StateTests {
    @Test("settings clamp level offset and copy immutably")
    func settings() {
        #expect(AppSettings(windowLevelOffset: -10).windowLevelOffset == -3)
        #expect(AppSettings(windowLevelOffset: 4).windowLevelOffset == 0)
        let base = AppSettings.default
        let changed = base.with(frameRateCap: .fps30, audioEnabled: true)
        #expect(base.frameRateCap == .fps60, "60 fps is the default")
        #expect(changed.frameRateCap == .fps30)
        #expect(changed.audioEnabled)
        #expect(changed.pauseRules == base.pauseRules)
        #expect(PauseAction.suspend > PauseAction.pause)
        #expect(PauseAction.ignore < PauseAction.pause)
    }

    @Test("state store round-trips and handles missing file")
    func roundTrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("owstate-\(UUID().uuidString)/state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = StateStore(fileURL: url)
        #expect(try await store.load() == .empty)

        let wallpaper = Wallpaper(
            id: WallpaperID("w1"), title: "Test", type: .video, origin: .native,
            root: URL(fileURLWithPath: "/tmp/w1"), entry: try SanitizedPath("clip.mp4"),
            properties: [
                PropertyDefinition(key: "k", label: "K", order: 0, kind: .color, defaultValue: .color(.white)),
            ]
        )
        let state = PersistedState.empty.with(
            settings: .default.with(posterSync: false),
            assignments: [DisplayAssignment(display: DisplayKey("d1"), wallpaper: wallpaper.id)],
            library: [wallpaper]
        )
        try await store.save(state)
        #expect(try await store.load() == state)
    }

    @Test("state store rejects future schema and corrupt data")
    func rejects() {
        #expect(throws: StateStoreError.unsupportedSchema(99)) {
            try StateStore.decode(Data(#"{"schemaVersion":99}"#.utf8))
        }
        #expect(throws: StateStoreError.self) { try StateStore.decode(Data("garbage".utf8)) }
        #expect(throws: StateStoreError.self) { try StateStore.decode(Data(#"{"schemaVersion":1}"#.utf8)) }
    }

    @Test("model copy helpers")
    func copies() throws {
        let wallpaper = Wallpaper(
            id: .random(), title: "A", type: .image, origin: .native,
            root: URL(fileURLWithPath: "/tmp"), entry: try SanitizedPath("a.png"),
            properties: [PropertyDefinition(key: "x", label: "X", order: 0, kind: .bool, defaultValue: .bool(true))]
        )
        #expect(wallpaper.with(title: "B").title == "B")
        #expect(wallpaper.with(support: .partial).support == .partial)
        #expect(wallpaper.defaultValues == ["x": .bool(true)])
        let assignment = DisplayAssignment(display: DisplayKey("d"), wallpaper: wallpaper.id)
        #expect(assignment.with(fill: .fit).fill == .fit)
        #expect(assignment.with(overrides: ["x": .bool(false)]).overrides["x"] == .bool(false))
        #expect(PlaybackState.playing(fps: 30).isPlaying)
        #expect(!PlaybackState.paused.isPlaying)
        #expect(WallpaperID("a").description == "a")
        #expect(DisplayKey("d").description == "d")
    }
}

@Suite("Settings migration")
struct SettingsMigrationTests {
    @Test("older state files with missing keys decode with defaults")
    func tolerant() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"audioEnabled":true,"pauseRules":{"onBattery":"suspend"}}"#.utf8))
        #expect(settings.audioEnabled)
        #expect(settings.frameRateCap == .fps60)
        #expect(settings.renderScale == 1)
        #expect(settings.pauseRules.onBattery == .suspend)
        #expect(settings.pauseRules.fullscreenApp == .pause)
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings.with(renderScale: 0.1)))
        #expect(round.renderScale == 0.25)
        #expect(AppSettings(renderScale: .nan).renderScale == 1)
    }

    @Test("pause rule copy helper")
    func ruleCopy() {
        let rules = PauseRules.default.with(\.onBattery, .suspend)
        #expect(rules.onBattery == .suspend)
        #expect(PauseRules.default.onBattery == .ignore)
        #expect(rules.fullscreenApp == PauseRules.default.fullscreenApp)
    }
}
