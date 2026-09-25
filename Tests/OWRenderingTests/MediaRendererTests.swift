import AppKit
import AVFoundation
import Foundation
import Testing
@testable import OWCore
@testable import OWFormats
@testable import OWRendering

/// Writes a tiny H.264 clip so video tests never depend on bundled media.
enum ClipFactory {
    static func makeClip(at url: URL, frames: Int = 15, size: Int = 64) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for index in 0 ..< frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(index * 10), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }
}

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
