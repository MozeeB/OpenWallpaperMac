import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import OWAppFeature
@testable import OWCore
@testable import OWDesktop
@testable import OWPower
@testable import OWRendering

@MainActor
struct CoordinatorHarness {
    let screens = FakeScreens()
    let windows = FakeWindows()
    let power = FakePower()
    let factory = FakeFactory()
    let audio = FakeAudio()
    let setter = FakeSetter()
    let coordinator: PlaybackCoordinator
    let posterDir = FileManager.default.temporaryDirectory.appendingPathComponent("owcoord-\(UUID())")

    init(displays: [String] = ["A"]) {
        _ = NSApplication.shared
        screens.screens = displays.enumerated().map { FakeScreens.screen($1, x: CGFloat($0) * 320) }
        let monitor = PowerMonitor(windows: windows, power: power, analyzer: FullscreenAnalyzer(ownPID: 1), pollInterval: 60)
        coordinator = PlaybackCoordinator(
            displays: DisplayManager(provider: screens, debounce: .milliseconds(1)), power: monitor, factory: factory,
            posters: PosterSync(setter: setter, directory: posterDir), audio: audio
        )
    }

    static func wallpaper(_ type: WallpaperType = .video, audio: Bool = false, support: SupportLevel = .full, preview: String? = "preview.png") -> Wallpaper {
        Wallpaper(
            id: .random(), title: "W", type: type, origin: .native, root: FileManager.default.temporaryDirectory,
            entry: try! SanitizedPath("entry"), preview: preview.map { try! SanitizedPath($0) },
            properties: [PropertyDefinition(key: "speed", label: "Speed", order: 0, kind: .slider(min: 0, max: 10, step: 1), defaultValue: .number(1))],
            support: support, usesAudio: audio
        )
    }
}

@Suite("PlaybackCoordinator")
@MainActor
struct PlaybackCoordinatorTests {
    let a = DisplayKey("A")
    let b = DisplayKey("B")

    @Test("assigning starts, hosts, loads and plays a renderer")
    func startsSession() async {
        let h = CoordinatorHarness()
        h.coordinator.start()
        let wallpaper = CoordinatorHarness.wallpaper()
        h.coordinator.update(library: [wallpaper], assignments: [DisplayAssignment(display: a, wallpaper: wallpaper.id)], settings: .default)
        let renderer = h.factory.created.first
        #expect(renderer?.type == .video)
        #expect(await eventually { renderer?.loaded != nil })
        #expect(await eventually { renderer?.playback.last == .playing(fps: 30) })
        #expect(h.coordinator.displays.windows[a]?.contentView?.subviews.first === renderer?.hostView)
        #expect(h.coordinator.activeWallpaper(for: a) == wallpaper.id)
        #expect(await eventually { h.setter.applied.count == 1 }, "poster synced after load")
        h.coordinator.stop(restoreOriginalWallpaper: true)
        #expect(renderer?.tornDown == true)
    }

    @Test("power policy, user pause and fullscreen apps gate playback")
    func gating() async {
        let h = CoordinatorHarness()
        h.coordinator.start()
        let wallpaper = CoordinatorHarness.wallpaper()
        h.coordinator.update(library: [wallpaper], assignments: [DisplayAssignment(display: a, wallpaper: wallpaper.id)], settings: .default)
        let renderer = h.factory.created[0]
        #expect(await eventually { renderer.loaded != nil })

        h.coordinator.setUserPaused(true)
        #expect(renderer.playback.last == .paused)
        h.coordinator.setUserPaused(false)
        #expect(renderer.playback.last == .playing(fps: 30))

        h.windows.windows = [WindowInfo(ownerPID: 99, layer: 0, bounds: CGRect(x: 0, y: 0, width: 320, height: 200))]
        h.coordinator.power.refreshFullscreen()
        #expect(renderer.playback.last == .paused)
        #expect(h.coordinator.playbackState(for: a) == .paused)

        h.windows.windows = []
        h.power.isOnBattery = true
        h.coordinator.power.refreshAll()
        #expect(renderer.playback.last == .playing(fps: 15))
        h.coordinator.stop(restoreOriginalWallpaper: false)
    }

    @Test("property changes are pushed; wallpaper changes replace the renderer")
    func updates() async {
        let h = CoordinatorHarness()
        h.coordinator.start()
        let first = CoordinatorHarness.wallpaper()
        let second = CoordinatorHarness.wallpaper(.shader)
        let assignment = DisplayAssignment(display: a, wallpaper: first.id)
        h.coordinator.update(library: [first, second], assignments: [assignment], settings: .default)
        let renderer = h.factory.created[0]
        #expect(await eventually { renderer.loaded != nil })
        #expect(renderer.loaded?.values == ["speed": .number(1)])

        h.coordinator.update(library: [first, second], assignments: [assignment.with(overrides: ["speed": .number(99)])], settings: .default)
        #expect(renderer.applied.last == ["speed": .number(10)], "validated and clamped")

        h.coordinator.update(library: [first, second], assignments: [DisplayAssignment(display: a, wallpaper: second.id)], settings: .default)
        #expect(renderer.tornDown)
        #expect(h.factory.created.last?.type == .shader)

        h.coordinator.update(library: [first, second], assignments: [], settings: .default.with(windowLevelOffset: -2))
        #expect(h.factory.created.last?.tornDown == true)
        #expect(h.coordinator.displays.config.levelOffset == -2)
        h.coordinator.stop(restoreOriginalWallpaper: false)
    }

    @Test("load failures and unsupported scenes fall back to the preview image")
    func fallback() async {
        let h = CoordinatorHarness()
        var events: [CoordinatorEvent] = []
        h.coordinator.onEvent = { events.append($0) }
        h.coordinator.start()
        let broken = CoordinatorHarness.wallpaper(.web)
        h.factory.failNextLoad = .web("boom")
        h.coordinator.update(library: [broken], assignments: [DisplayAssignment(display: a, wallpaper: broken.id)], settings: .default)
        #expect(await eventually { h.factory.created.count == 2 })
        #expect(h.factory.created[1].type == .image)
        #expect(await eventually { h.factory.created[1].loaded?.wallpaper.entry.string == "preview.png" })
        #expect(events.contains(.failed(a, broken.id, .web("boom"))))
        #expect(await eventually { events.contains(.fellBackToPreview(a, broken.id)) })

        // Runtime failure (e.g. GPU hang) of the fallback does not loop.
        h.factory.created[1].onFailure?(.gpuHang)
        #expect(h.factory.created.count == 2)

        let scene = CoordinatorHarness.wallpaper(.scene, support: .previewOnly)
        h.coordinator.update(library: [scene], assignments: [DisplayAssignment(display: a, wallpaper: scene.id)], settings: .default)
        #expect(h.factory.created.last?.type == .image)

        let noPreview = CoordinatorHarness.wallpaper(.shader, preview: nil)
        h.factory.unavailable = [.shader]
        h.coordinator.update(library: [noPreview], assignments: [DisplayAssignment(display: a, wallpaper: noPreview.id)], settings: .default)
        #expect(h.coordinator.activeWallpaper(for: a) == nil)
        h.coordinator.stop(restoreOriginalWallpaper: false)
    }

    @Test("sessions follow connected displays")
    func displays() async {
        let h = CoordinatorHarness(displays: ["A", "B"])
        h.coordinator.start()
        let wallpaper = CoordinatorHarness.wallpaper()
        h.coordinator.update(library: [wallpaper], assignments: [
            DisplayAssignment(display: a, wallpaper: wallpaper.id), DisplayAssignment(display: b, wallpaper: wallpaper.id),
        ], settings: .default)
        #expect(h.factory.created.count == 2)
        #expect(h.coordinator.connectedDisplays.count == 2)
        h.screens.screens = [FakeScreens.screen("A")]
        h.coordinator.displays.sync()
        #expect(h.factory.created.filter(\.tornDown).count == 1)
        #expect(h.coordinator.activeWallpaper(for: b) == nil)
        h.coordinator.displays.onOcclusionChange?(a, true)
        #expect(h.coordinator.power.snapshot.perDisplay[a]?.occluded == true)
        h.coordinator.stop(restoreOriginalWallpaper: false)
    }

    @Test("audio capture runs only for playing audio-reactive wallpapers")
    func audio() async {
        let h = CoordinatorHarness()
        var events: [CoordinatorEvent] = []
        h.coordinator.onEvent = { events.append($0) }
        h.coordinator.start()
        let reactive = CoordinatorHarness.wallpaper(.shader, audio: true)
        let assignment = [DisplayAssignment(display: a, wallpaper: reactive.id)]
        h.coordinator.update(library: [reactive], assignments: assignment, settings: .default.with(audioEnabled: true))
        #expect(await eventually { h.audio.isRunning })
        h.audio.onSpectrum?(AudioSpectrum(left: [1], right: [1]))
        #expect(h.factory.created[0].spectra == 1)
        h.audio.onSilence?()
        #expect(events.contains(.audioSilent))

        h.coordinator.setUserPaused(true)
        #expect(!h.audio.isRunning)
        h.coordinator.setUserPaused(false)
        #expect(h.audio.isRunning)
        h.coordinator.update(library: [reactive], assignments: assignment, settings: .default.with(audioEnabled: false))
        #expect(!h.audio.isRunning)

        h.audio.failStart = true
        h.coordinator.update(library: [reactive], assignments: assignment, settings: .default.with(audioEnabled: true))
        #expect(events.contains { if case .audioUnavailable = $0 { return true } else { return false } })
        h.coordinator.stop(restoreOriginalWallpaper: false)
    }
}
