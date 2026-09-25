import AppKit
import Foundation
@testable import OWAppFeature
@testable import OWAudioCapture
@testable import OWCore
@testable import OWDesktop
@testable import OWPower
@testable import OWRendering

@MainActor
final class FakeScreens: ScreenProviding {
    var screens: [ScreenDescriptor] = []
    func currentScreens() -> [ScreenDescriptor] { screens }
    func nsScreen(for key: DisplayKey) -> NSScreen? { nil }

    static func screen(_ key: String, x: CGFloat = 0) -> ScreenDescriptor {
        ScreenDescriptor(key: DisplayKey(key), displayID: 1, name: "Display \(key)",
                         frame: CGRect(x: x, y: 0, width: 320, height: 200),
                         cgBounds: CGRect(x: x, y: 0, width: 320, height: 200), scale: 2)
    }
}

final class FakeWindows: WindowListProviding, @unchecked Sendable {
    var windows: [WindowInfo] = []
    func onScreenWindows() -> [WindowInfo] { windows }
}

final class FakePower: PowerSourceProviding, @unchecked Sendable {
    var isOnBattery = false
    var isLowPowerMode = false
    var thermal = ThermalLevel.nominal
}

@MainActor
final class FakeRenderer: WallpaperRenderer {
    var onFailure: ((RenderError) -> Void)?
    let hostView = NSView()
    let type: WallpaperType
    var loadError: RenderError?
    private(set) var loaded: ResolvedWallpaper?
    private(set) var playback: [PlaybackState] = []
    private(set) var applied: [PropertyValues] = []
    private(set) var spectra = 0
    private(set) var tornDown = false

    init(type: WallpaperType) {
        self.type = type
    }

    func load(_ wallpaper: ResolvedWallpaper, context: RenderContext) async throws(RenderError) {
        if let loadError { throw loadError }
        loaded = wallpaper
    }

    func setPlayback(_ state: PlaybackState) { playback.append(state) }
    func apply(_ values: PropertyValues) { applied.append(values) }
    func receive(_ spectrum: AudioSpectrum) { spectra += 1 }

    func snapshot() async throws(RenderError) -> CGImage {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    func teardown() { tornDown = true }
}

@MainActor
final class FakeFactory: RendererMaking {
    var created: [FakeRenderer] = []
    var failNextLoad: RenderError?
    var unavailable: Set<WallpaperType> = []

    func makeRenderer(for type: WallpaperType) -> Result<any WallpaperRenderer, RenderError> {
        if unavailable.contains(type) { return .failure(.metalUnavailable) }
        let renderer = FakeRenderer(type: type)
        renderer.loadError = failNextLoad
        failNextLoad = nil
        created.append(renderer)
        return .success(renderer)
    }
}

@MainActor
final class FakeAudio: AudioSpectrumSource {
    var onSpectrum: ((AudioSpectrum) -> Void)?
    var onSilence: (() -> Void)?
    private(set) var isRunning = false
    var failStart = false

    func start() throws(AudioCaptureError) {
        if failStart { throw .unsupportedOS }
        isRunning = true
    }

    func stop() { isRunning = false }
}

@MainActor
final class FakeSetter: DesktopImageSetting {
    var applied: [(URL, DisplayKey)] = []
    var current: [DisplayKey: URL] = [:]
    func currentImage(for display: DisplayKey) -> URL? { current[display] }
    func setImage(_ url: URL, for display: DisplayKey) throws(DesktopError) { applied.append((url, display)) }
}

@MainActor
func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

extension SanitizedPath {
    /// Test-only: literal paths known to be valid.
    static func fixture(_ raw: String) -> SanitizedPath {
        guard let path = try? SanitizedPath(raw) else { fatalError("invalid fixture path \(raw)") }
        return path
    }
}
