import AppKit
import Foundation
import Testing
@testable import OWAppFeature
@testable import OWCore
@testable import OWFormats
@testable import OWLibrary
@testable import OWRendering

@MainActor
private func makeModel(_ h: CoordinatorHarness, base: URL, loginItem: any LoginItemControlling = InMemoryLoginItem()) -> AppModel {
    AppModel(
        store: StateStore(fileURL: base.appendingPathComponent("state.json")),
        importer: ImportService(libraryRoot: base.appendingPathComponent("Library"), knownEffects: ["shake"]),
        thumbnails: ThumbnailService(cacheDirectory: base.appendingPathComponent("Thumbs")),
        coordinator: h.coordinator, steam: SteamLibraryLocator(steamRoot: base.appendingPathComponent("Steam")),
        loginItem: loginItem
    )
}

@MainActor
private final class FailingLoginItem: LoginItemControlling {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws { throw NSError(domain: "test", code: 1) }
}

@Suite("AppModel")
@MainActor
struct AppModelTests {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("owmodel-\(UUID())")

    @Test("imports, assigns, edits properties, persists and removes")
    func workflow() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let h = CoordinatorHarness(displays: ["A", "B"])
        let model = makeModel(h, base: base)
        await model.bootstrap()
        #expect(model.displays.count == 2)

        let source = base.appendingPathComponent("src")
        try SyntheticScene.write(SampleContent.plasmaShaderFiles(), to: source.appendingPathComponent("Plasma"))
        try SyntheticScene.write([("clip.mp4", Data("x".utf8)), ("bad.exe", Data())], to: source)
        await model.importItems([source.appendingPathComponent("Plasma"), source.appendingPathComponent("clip.mp4"), source.appendingPathComponent("bad.exe")])
        #expect(model.library.count == 2)
        #expect(model.messages.contains { $0.level == .error && $0.text.contains("bad.exe") })
        #expect(model.messages.contains { $0.text == "Imported 2 wallpapers." })
        let plasma = try #require(model.library.first { $0.title == "Plasma" })
        #expect(plasma.usesAudio)

        model.assign(plasma.id, to: nil)
        #expect(model.state.assignments.count == 2)
        #expect(model.activeWallpaper(for: DisplayKey("A"))?.id == plasma.id)
        model.setOverride(.number(2), key: "speed", display: DisplayKey("A"))
        #expect(model.assignment(for: DisplayKey("A"))?.overrides["speed"] == .number(2))
        model.setFill(.fit, display: DisplayKey("A"))
        #expect(model.assignment(for: DisplayKey("A"))?.fill == .fit)
        model.resetOverrides(display: DisplayKey("A"))
        #expect(model.assignment(for: DisplayKey("A"))?.overrides.isEmpty == true)
        model.clearAssignment(for: DisplayKey("B"))
        #expect(model.assignment(for: DisplayKey("B")) == nil)

        // Rapid commits must land on disk in order: the last override wins after flush.
        for value in 1 ... 20 { model.setOverride(.number(Double(value)), key: "speed", display: DisplayKey("A")) }
        await model.flush()
        let reloaded = try await StateStore(fileURL: base.appendingPathComponent("state.json")).load()
        #expect(reloaded.library.count == 2)
        #expect(reloaded.assignments.first { $0.display == DisplayKey("A") }?.overrides["speed"] == .number(20))
        model.resetOverrides(display: DisplayKey("A"))

        model.remove(plasma.id)
        #expect(model.library.count == 1)
        #expect(model.state.assignments.isEmpty)
        model.remove(WallpaperID("missing"))
        model.shutdown()
    }

    @Test("settings, pause toggle, login item errors and messages")
    func settings() async {
        defer { try? FileManager.default.removeItem(at: base) }
        let h = CoordinatorHarness()
        let model = makeModel(h, base: base, loginItem: FailingLoginItem())
        await model.bootstrap()
        model.updateSettings(model.settings.with(frameRateCap: .fps60))
        #expect(model.settings.frameRateCap == .fps60)
        model.updateSettings(model.settings.with(launchAtLogin: true))
        #expect(!model.settings.launchAtLogin)
        #expect(model.messages.last?.text.contains("launch at login") == true)

        model.togglePause()
        #expect(model.isPaused && h.coordinator.userPaused)
        model.togglePause()
        #expect(!model.isPaused)

        for index in 0 ..< 8 { model.post(.info, "m\(index)") }
        #expect(model.messages.count == 5)
        model.dismiss(model.messages[0])
        #expect(model.messages.count == 4)

        await model.scanSteamLibrary()
        #expect(model.messages.last?.text.contains("No Wallpaper Engine projects") == true)
        model.shutdown()
    }

    @Test("corrupt state starts fresh with an error message")
    func corruptState() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: base.appendingPathComponent("state.json"))
        let model = makeModel(CoordinatorHarness(), base: base)
        await model.bootstrap()
        #expect(model.library.isEmpty)
        #expect(model.messages.first?.level == .error)
        model.shutdown()
    }

    @Test("environment helpers")
    func environment() throws {
        #expect(AppEnvironment.mode(from: ["app", "-UITestMode"]) == .uiTest)
        #expect(AppEnvironment.mode(from: ["app"]) == .live)
        #expect(AppEnvironment.baseDirectory(mode: .live).lastPathComponent == "OpenWallpaperMac")
        let store = StateStore(fileURL: base.appendingPathComponent("state.json"))
        let importer = ImportService(libraryRoot: base.appendingPathComponent("Library"), knownEffects: ["shake"])
        AppEnvironment.seedSamples(store: store, importer: importer, base: base)
        let data = try Data(contentsOf: store.fileURL)
        let state = try JSONDecoder().decode(PersistedState.self, from: data)
        #expect(state.library.map(\.title).sorted() == ["Plasma", "Synthetic Scene"])
        #expect(!state.settings.posterSync)
        try? FileManager.default.removeItem(at: base)
    }

    @Test("error text is user friendly")
    func errorText() {
        #expect(ImportErrorText.describe(.project(.missingField("type"))) == "the manifest is missing \"type\"")
        #expect(ImportErrorText.describe(.unsupportedFile("a.exe")).contains("not a supported"))
        for error in [ImportError.notFound("x"), .tooLarge("x"), .copyFailed("x"), .package(.invalidMagic("x"))] {
            #expect(!ImportErrorText.describe(error).isEmpty)
        }
        for error in [ProjectError.noManifest, .unreadable("x"), .invalidJSON(.notAnObject), .unsupportedType("x"), .invalidPath("x"), .entryNotFound("x")] {
            #expect(!ImportErrorText.describe(.project(error)).isEmpty)
        }
        #expect(RenderErrorText.describe(.compile(line: 3, message: "bad")) == "shader error on line 3: bad")
        let renderErrors: [RenderError] = [
            .unsupported(.scene), .assetMissing("x"), .invalidAsset("x"), .metalUnavailable,
            .gpuHang, .snapshotFailed, .notLoaded, .web("x"),
        ]
        for error in renderErrors {
            #expect(!RenderErrorText.describe(error).isEmpty)
        }
    }

    @Test("default factory builds every renderer family")
    func factory() {
        let factory = DefaultRendererFactory()
        for type in WallpaperType.allCases {
            guard case .success(let renderer) = factory.makeRenderer(for: type) else {
                Issue.record("no renderer for \(type)")
                continue
            }
            renderer.teardown()
        }
    }
}

@Suite("Smoke-test seeding")
@MainActor
struct SeedAssignTests {
    @Test("assigns the named sample to connected displays")
    func assign() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("owseed-\(UUID())")
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(AppEnvironment.argument(after: "-x", in: ["a", "-x", "Plasma"]) == "Plasma")
        #expect(AppEnvironment.argument(after: "-x", in: ["a", "-x"]) == nil)
        let store = StateStore(fileURL: base.appendingPathComponent("state.json"))
        AppEnvironment.seedSamples(store: store, importer: ImportService(libraryRoot: base.appendingPathComponent("L"), knownEffects: []),
                                   base: base, assign: "Plasma")
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: store.fileURL))
        let plasma = try #require(state.library.first { $0.title == "Plasma" })
        #expect(state.assignments.allSatisfy { $0.wallpaper == plasma.id })
        #expect(state.assignments.count == NSScreen.screens.count)
    }
}
