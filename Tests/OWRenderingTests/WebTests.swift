import AppKit
import Foundation
import Testing
import WebKit
@testable import OWCore
@testable import OWFormats
@testable import OWRendering

@Suite("Web policy & bridge")
struct WebPolicyTests {
    let root = URL(fileURLWithPath: "/tmp/ow-web-root")

    @Test("allows only in-root files and safe schemes", arguments: [
        ("file:///tmp/ow-web-root/index.html", false, true),
        ("file:///tmp/ow-web-root", false, true),
        ("file:///tmp/ow-web-root-evil/x.html", false, false),
        ("file:///tmp/ow-web-root/../secret", false, false),
        ("about:blank", false, true),
        ("about:config", false, false),
        ("data:text/plain,hi", false, true),
        ("https://example.com", false, false),
        ("https://example.com", true, true),
        ("javascript:alert(1)", true, false),
    ])
    func policy(url: String, network: Bool, expected: Bool) {
        #expect(WebSecurityPolicy.allows(URL(string: url)!, root: root, networkAllowed: network) == expected)
    }

    @Test("validates page messages")
    func messages() {
        #expect(WebMessage.parse(["type": "ready"]) == .ready)
        #expect(WebMessage.parse(["type": "audioListener"]) == .audioListenerRegistered)
        #expect(WebMessage.parse(["type": "log", "message": String(repeating: "x", count: 900)]) == .log(String(repeating: "x", count: 500)))
        #expect(WebMessage.parse(["type": "log"]) == nil)
        #expect(WebMessage.parse(["type": "exec"]) == nil)
        #expect(WebMessage.parse("ready") == nil)
        #expect(WebMessage.parse(["type": "ready", "a": 1, "b": 2, "c": 3, "d": 4]) == nil)
    }

    @Test("builds Wallpaper Engine–shaped property payloads")
    func payloads() {
        let json = WebBridgeScript.propertiesJSON([
            "tint": .color(RGBColor(red: 1, green: 0.5, blue: 0)), "on": .bool(true),
            "speed": .number(2), "mode": .string("a"), "bad": .number(.nan),
        ])
        #expect(json == #"{"bad":{"value":0},"mode":{"value":"a"},"on":{"value":true},"speed":{"value":2},"tint":{"value":"1 0.5 0"}}"#)
        #expect(WebBridgeScript.pausedCall(true).contains("setPaused(true)"))
        let audio = WebBridgeScript.audioCall(AudioSpectrum(left: [1], right: []))
        #expect(audio.hasPrefix("window.__ow && window.__ow.audio([1.000,0.000"))
        #expect(audio.components(separatedBy: ",").count == 128)
    }
}

@Suite("Web renderer (WebKit)")
@MainActor
struct WebRendererTests {
    @Test("loads a local page, delivers properties and audio registration")
    func roundTrip() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("owweb-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let html = """
        <html><body><script>
        window.wallpaperPropertyListener = { applyUserProperties: function (p) {
          if (p.speed) { document.title = 'speed=' + p.speed.value; }
        } };
        wallpaperRegisterAudioListener(function (a) { document.body.dataset.bands = a.length; });
        </script></body></html>
        """
        try SyntheticScene.write([("index.html", Data(html.utf8))], to: folder)
        let definition = PropertyDefinition(key: "speed", label: "Speed", order: 0, kind: .slider(min: 0, max: 10, step: 1), defaultValue: .number(3))
        let wallpaper = Wallpaper(
            id: .random(), title: "W", type: .web, origin: .wallpaperEngine, root: folder,
            entry: try SanitizedPath("index.html"), properties: [definition]
        )
        let renderer = WebRenderer()
        try await renderer.load(
            ResolvedWallpaper(wallpaper: wallpaper, assets: FolderAssetSource(root: folder), values: [:]),
            context: RenderContext(pixelSize: CGSize(width: 320, height: 200), scale: 1)
        )
        let webView = try #require(renderer.webView)
        #expect(try await poll { (try? await webView.evaluateJavaScript("document.title") as? String) == "speed=3" })
        renderer.apply(["speed": .number(7)])
        #expect(try await poll { (try? await webView.evaluateJavaScript("document.title") as? String) == "speed=7" })
        #expect(try await poll { renderer.receivedMessages.contains(.audioListenerRegistered) })
        renderer.setPlayback(.playing(fps: 30))
        renderer.receive(AudioSpectrum(left: [0.5], right: [0.5]))
        #expect(try await poll { (try? await webView.evaluateJavaScript("document.body.dataset.bands") as? String) == "128" })
        renderer.setPlayback(.paused)
        #expect(webView.isHidden)
        renderer.setPlayback(.suspended)
        #expect(renderer.webView == nil)
        renderer.teardown()
    }

    @Test("rejects missing entry and snapshot before load")
    func errors() async throws {
        let renderer = WebRenderer()
        let wallpaper = Wallpaper(
            id: .random(), title: "W", type: .web, origin: .native, root: URL(fileURLWithPath: "/tmp/none-\(UUID())"),
            entry: try SanitizedPath("index.html")
        )
        await #expect(throws: RenderError.assetMissing("index.html")) {
            try await renderer.load(
                ResolvedWallpaper(wallpaper: wallpaper, assets: FolderAssetSource(root: wallpaper.root), values: [:]),
                context: RenderContext(pixelSize: .zero, scale: 1)
            )
        }
        await #expect(throws: RenderError.notLoaded) { _ = try await renderer.snapshot() }
    }

    private func poll(timeout: Duration = .seconds(10), _ condition: @MainActor () async -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}
