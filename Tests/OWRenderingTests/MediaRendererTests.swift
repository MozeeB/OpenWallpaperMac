import AppKit
import AVFoundation
import Foundation
import Testing
@testable import OWCore
@testable import OWFormats
@testable import OWRendering
import OWTestSupport

private func wallpaper(_ type: WallpaperType, folder: URL, entry: String) throws -> ResolvedWallpaper {
    let item = Wallpaper(id: .random(), title: "T", type: type, origin: .native, root: folder, entry: try SanitizedPath(entry))
    return ResolvedWallpaper(wallpaper: item, assets: FolderAssetSource(root: folder), values: [:])
}

private let context = RenderContext(pixelSize: CGSize(width: 64, height: 64), scale: 1)

@Suite("Image & video renderers")
@MainActor
struct MediaRendererTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("owmedia-\(UUID())")

    @Test("image renderer decodes and suspends")
    func image() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let bitmap = RGBABitmap(width: 2, height: 2, pixels: Data(repeating: 200, count: 16))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try TEXImageConverter.writePNG(bitmap, to: folder.appendingPathComponent("a.png"))
        try Data("nope".utf8).write(to: folder.appendingPathComponent("bad.png"))
        let renderer = ImageRenderer()
        try await renderer.load(try wallpaper(.image, folder: folder, entry: "a.png"), context: context)
        #expect(try await renderer.snapshot().width == 2)
        renderer.setPlayback(.suspended)
        #expect(renderer.hostView.layer?.contents == nil)
        renderer.setPlayback(.playing(fps: 30))
        #expect(renderer.hostView.layer?.contents != nil)
        renderer.apply([:])
        renderer.receive(.silent)
        renderer.teardown()
        await #expect(throws: RenderError.notLoaded) { _ = try await renderer.snapshot() }
        await #expect(throws: RenderError.invalidAsset("unreadable image")) {
            try await renderer.load(try wallpaper(.image, folder: folder, entry: "bad.png"), context: context)
        }
        await #expect(throws: RenderError.assetMissing("none.png")) {
            try await renderer.load(try wallpaper(.image, folder: folder, entry: "none.png"), context: context)
        }
        #expect(FillMode.fit.layerGravity == .resizeAspect)
        #expect(FillMode.stretch.layerGravity == .resize)
    }

    @Test("video renderers share one decoder and release it")
    func video() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let clip = folder.appendingPathComponent("clip.mp4")
        try await ClipFactory.makeClip(at: clip)
        let pool = VideoPlayerPool()
        let first = VideoRenderer(pool: pool)
        let second = VideoRenderer(pool: pool)
        let resolved = try wallpaper(.video, folder: folder, entry: "clip.mp4")
        try await first.load(resolved, context: context)
        try await second.load(resolved, context: RenderContext(pixelSize: .zero, scale: 1, fill: .fit))
        #expect(pool.activeDecoders == 1)
        #expect(pool.ownerCount(for: clip) == 2)

        first.setPlayback(.playing(fps: 30))
        #expect(pool.isPlaying(clip))
        #expect(pool.outputFPS(for: clip) == 30, "30 fps source stays at its native rate")
        first.setPlayback(.playing(fps: 15))
        #expect(pool.outputFPS(for: clip) == 15, "battery cap lowers the output rate")
        #expect(pool.isPlaying(clip))
        first.setPlayback(.playing(fps: 30))
        second.setPlayback(.paused)
        #expect(pool.isPlaying(clip), "one owner still wants playback")
        first.setPlayback(.paused)
        #expect(!pool.isPlaying(clip))

        first.setPlayback(.suspended)
        #expect(!first.isAttached)
        #expect(pool.ownerCount(for: clip) == 1)
        let frame = try await second.snapshot()
        #expect(frame.width == 64)
        second.teardown()
        first.teardown()
        #expect(pool.activeDecoders == 0)
        #expect(VideoRenderer.gravity(.stretch) == .resize)
    }

    @Test("prepared videos drop audio and cap the frame rate")
    func prepared() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let clip = folder.appendingPathComponent("clip.mp4")
        try await ClipFactory.makeClip(at: clip)
        let prepared = try await PreparedVideo.prepare(url: clip)
        #expect(try await prepared.asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(abs(prepared.sourceFPS - 30) < 0.01, "encoders may write 29.99…")
        #expect(prepared.effectiveFPS(cap: 60) == 30)
        #expect(prepared.effectiveFPS(cap: 15) == 15)
        #expect(prepared.composition(cap: 60) == nil, "no composition overhead when under the cap")
        #expect(prepared.composition(cap: 15)?.frameDuration == CMTime(value: 1, timescale: 15))
        await #expect(throws: (any Error).self) {
            _ = try await PreparedVideo.prepare(url: folder.appendingPathComponent("missing.mp4"))
        }
    }

    @Test("60 fps sources play at native 60 fps when the cap is 60")
    func sixtyFPS() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let clip = folder.appendingPathComponent("clip60.mp4")
        try await ClipFactory.makeClip(at: clip, frames: 60, fps: 60)
        let prepared = try await PreparedVideo.prepare(url: clip)
        #expect(abs(prepared.sourceFPS - 60) < 0.01, "encoders may write 59.99…")
        #expect(prepared.effectiveFPS(cap: 60) == 60)
        #expect(prepared.composition(cap: 60) == nil, "native 60 fps: no capping composition")
        #expect(prepared.composition(cap: 30)?.frameDuration == CMTime(value: 1, timescale: 30))

        let pool = VideoPlayerPool()
        let renderer = VideoRenderer(pool: pool)
        try await renderer.load(try wallpaper(.video, folder: folder, entry: "clip60.mp4"), context: context)
        renderer.setPlayback(.playing(fps: 60))
        #expect(pool.outputFPS(for: clip) == 60)
        renderer.setPlayback(.playing(fps: 30))
        #expect(pool.outputFPS(for: clip) == 30)
        renderer.setPlayback(.playing(fps: 60))
        #expect(pool.outputFPS(for: clip) == 60)
        #expect(pool.isPlaying(clip))
        renderer.teardown()
    }

    @Test("video renderer rejects missing and invalid files")
    func invalidVideo() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a video".utf8).write(to: folder.appendingPathComponent("fake.mp4"))
        let renderer = VideoRenderer(pool: VideoPlayerPool())
        await #expect(throws: RenderError.assetMissing("gone.mp4")) {
            try await renderer.load(try wallpaper(.video, folder: folder, entry: "gone.mp4"), context: context)
        }
        await #expect(throws: RenderError.invalidAsset("not a playable video: fake.mp4")) {
            try await renderer.load(try wallpaper(.video, folder: folder, entry: "fake.mp4"), context: context)
        }
        await #expect(throws: RenderError.notLoaded) { _ = try await renderer.snapshot() }
        renderer.setPlayback(.playing(fps: 30))
        await #expect(throws: RenderError.snapshotFailed) {
            _ = try await VideoRenderer.frame(of: folder.appendingPathComponent("fake.mp4"))
        }
    }
}
