import AppKit
import Foundation
import Testing
@testable import OWCore
@testable import OWDesktop

private func screen(_ key: String, x: CGFloat = 0, width: CGFloat = 800, scale: CGFloat = 2) -> ScreenDescriptor {
    ScreenDescriptor(
        key: DisplayKey(key), displayID: 1, name: key,
        frame: CGRect(x: x, y: 0, width: width, height: 600),
        cgBounds: CGRect(x: x, y: 0, width: width, height: 600), scale: scale
    )
}

@MainActor
private final class FakeScreens: ScreenProviding {
    var screens: [ScreenDescriptor] = []
    func currentScreens() -> [ScreenDescriptor] { screens }
    func nsScreen(for key: DisplayKey) -> NSScreen? { nil }
}

@MainActor
private final class FakeSetter: DesktopImageSetting {
    var current: [DisplayKey: URL] = [:]
    var applied: [(URL, DisplayKey)] = []
    var failing = false

    func currentImage(for display: DisplayKey) -> URL? { current[display] }

    func setImage(_ url: URL, for display: DisplayKey) throws(DesktopError) {
        if failing { throw .setFailed("nope") }
        applied.append((url, display))
    }
}

@Suite("LayoutDiff")
struct LayoutDiffTests {
    @Test("detects added, removed and changed screens")
    func diff() {
        let before = [screen("a"), screen("b")]
        let after = [screen("a", scale: 1), screen("c", x: 800)]
        let diff = LayoutDiff.between(before, after)
        #expect(diff.added.map(\.key) == [DisplayKey("c")])
        #expect(diff.removed == [DisplayKey("b")])
        #expect(diff.changed.map(\.key) == [DisplayKey("a")])
        #expect(LayoutDiff.between(after, after).isEmpty)
        #expect(screen("a").pixelSize == CGSize(width: 1600, height: 1200))
    }
}

@Suite("Desktop windows")
@MainActor
struct DesktopWindowTests {
    init() {
        _ = NSApplication.shared
    }

    @Test("window sits below desktop icons, on all spaces, click-through")
    func configuration() {
        let window = DesktopWindow(screen: screen("a"), config: DesktopWindowConfig(levelOffset: -1))
        #expect(window.level.rawValue == Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.stationary))
        #expect(window.collectionBehavior.contains(.ignoresCycle))
        #expect(window.collectionBehavior.contains(.fullScreenNone))
        #expect(window.ignoresMouseEvents)
        #expect(window.isOpaque)
        #expect(!window.hasShadow)
        #expect(!window.canBecomeKey && !window.canBecomeMain)
        let view = NSView()
        window.host(view)
        #expect(window.contentView?.subviews == [view])
        window.host(nil)
        #expect(window.contentView?.subviews.isEmpty == true)
        window.reframe(to: screen("a", width: 400))
        #expect(window.frame.width == 400)
        #expect(DesktopWindowConfig(levelOffset: -9).levelOffset == -3)
        window.close()
    }

    @Test("display manager keeps one window per screen")
    func manager() {
        let provider = FakeScreens()
        provider.screens = [screen("a"), screen("b", x: 800)]
        let manager = DisplayManager(provider: provider)
        var diffs: [LayoutDiff] = []
        manager.onLayoutChange = { diffs.append($0) }
        manager.start()
        #expect(Set(manager.windows.keys) == [DisplayKey("a"), DisplayKey("b")])
        #expect(manager.sync().isEmpty)

        provider.screens = [screen("a", width: 1000)]
        let diff = manager.sync()
        #expect(diff.removed == [DisplayKey("b")])
        #expect(manager.windows[DisplayKey("a")]?.frame.width == 1000)
        #expect(diffs.count == 2)

        manager.update(config: DesktopWindowConfig(levelOffset: -2))
        #expect(manager.windows[DisplayKey("a")]?.level.rawValue == Int(CGWindowLevelForKey(.desktopIconWindow)) - 2)
        #expect(manager.nsScreen(for: DisplayKey("a")) == nil)
        manager.stop()
        #expect(manager.windows.isEmpty)
    }

    @Test("debounced sync coalesces notifications")
    func debounce() async throws {
        let provider = FakeScreens()
        let manager = DisplayManager(provider: provider, debounce: .milliseconds(20))
        manager.start()
        provider.screens = [screen("x")]
        manager.scheduleSync()
        manager.scheduleSync()
        let deadline = ContinuousClock.now + .seconds(3)
        while !manager.windows.keys.contains(DisplayKey("x")), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(manager.windows.keys.contains(DisplayKey("x")))
        manager.stop()
    }

    @Test("system screen provider describes real screens")
    func systemProvider() {
        let provider = SystemScreenProvider()
        let screens = provider.currentScreens()
        #expect(screens.allSatisfy { $0.scale >= 1 })
        if let first = screens.first {
            #expect(provider.nsScreen(for: first.key) != nil)
            #expect(SystemScreenProvider.displayKey(for: first.displayID) == first.key)
        }
        #expect(SystemScreenProvider.displayKey(for: 999_999).rawValue.hasPrefix("display-"))
    }
}

@Suite("PosterSync")
@MainActor
struct PosterSyncTests {
    private func image() -> CGImage {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context.makeImage()!
    }

    @Test("writes unique posters, remembers and restores originals")
    func sync() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("owposter-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("../original-\(UUID()).png").standardizedFileURL
        try Data([1]).write(to: original)
        defer { try? FileManager.default.removeItem(at: original) }
        let setter = FakeSetter()
        let display = DisplayKey("37D8832A-2D66-02CA-B9F7-8F30A301B230")
        setter.current[display] = original

        let sync = PosterSync(setter: setter, directory: directory)
        let first = try sync.apply(image(), for: display)
        let second = try sync.apply(image(), for: display)
        #expect(first != second)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(sync.rememberedOriginals[display] == original)

        let reloaded = PosterSync(setter: setter, directory: directory)
        #expect(reloaded.rememberedOriginals[display] == original)
        reloaded.restoreOriginals()
        #expect(setter.applied.last?.0 == original)
        #expect(reloaded.rememberedOriginals.isEmpty)
    }

    @Test("propagates setter failures")
    func failure() {
        let setter = FakeSetter()
        setter.failing = true
        let sync = PosterSync(setter: setter, directory: FileManager.default.temporaryDirectory.appendingPathComponent("owp-\(UUID())"))
        #expect(throws: DesktopError.setFailed("nope")) { try sync.apply(image(), for: DisplayKey("d")) }
        #expect(PosterSync.filePrefix(DisplayKey("a/b:c")) == "poster-abc-")
        #expect(PosterSync.defaultDirectory().path.hasSuffix("OpenWallpaperMac/Posters"))
    }

    @Test("workspace setter reports unknown screens")
    func workspace() {
        let setter = WorkspaceDesktopImageSetter(screens: FakeScreens())
        #expect(setter.currentImage(for: DisplayKey("zz")) == nil)
        #expect(throws: DesktopError.screenNotFound(DisplayKey("zz"))) {
            try setter.setImage(URL(fileURLWithPath: "/tmp/x.png"), for: DisplayKey("zz"))
        }
    }
}
