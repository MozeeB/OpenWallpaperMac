import Foundation
import Metal
import Testing
@testable import OWCore
@testable import OWFormats
@testable import OWRendering
@testable import OWScene

@Suite("Scene rendering (Metal)")
@MainActor
struct SceneRenderTests {
    let context = MetalContext.shared!

    private func assets(_ options: SyntheticScene.Options) throws -> PKGAssetSource {
        PKGAssetSource(archive: try PKGParser.parse(PKGWriter.build(files: SyntheticScene.sceneContents(options: options))))
    }

    private func graph(_ options: SyntheticScene.Options) async throws -> (SceneGraph, ScenePipelines) {
        let pipelines = try await ScenePipelines.shared(context: context)
        let graph = try SceneGraphBuilder.build(
            entry: try SanitizedPath("scene.json"), assets: try assets(options), device: context.device, pipelines: pipelines
        )
        return (graph, pipelines)
    }

    @Test("static image layer renders the texture pixel-exactly")
    func staticLayer() async throws {
        var options = SyntheticScene.Options()
        options.effects = []
        options.includeParticles = false
        let (graph, pipelines) = try await graph(options)
        let drawer = SceneDrawer(graph: graph, pipelines: pipelines, device: context.device, fill: .fill)
        #expect(drawer.isAnimated, "synthetic scene enables camera parallax")
        let bitmap = try OffscreenRenderer.render(drawer, context: context, width: 64, height: 36)
        for (x, y) in [(0, 0), (63, 0), (32, 18), (10, 30)] {
            let expected = [UInt8(x * 255 / 63), UInt8(y * 255 / 35), 128, 255]
            let actual = bitmap.pixel(x: x, y: y)
            #expect(zip(actual, expected).allSatisfy { abs(Int($0) - Int($1)) <= 2 }, "pixel \(x),\(y): \(actual) vs \(expected)")
        }
    }

    @Test("user property binding hides layer alpha")
    func alphaBinding() async throws {
        var options = SyntheticScene.Options()
        options.effects = []
        options.includeParticles = false
        let (graph, pipelines) = try await graph(options)
        let drawer = SceneDrawer(graph: graph, pipelines: pipelines, device: context.device, fill: .fill)
        drawer.apply(["bgalpha": .number(0)])
        let bitmap = try OffscreenRenderer.render(drawer, context: context, width: 64, height: 36)
        // Only the clear colour (0.1, 0.1, 0.15) remains.
        let pixel = bitmap.pixel(x: 32, y: 18)
        #expect(zip(pixel, [26, 26, 38, 255] as [UInt8]).allSatisfy { abs(Int($0) - Int($1)) <= 1 }, "\(pixel)")
    }

    @Test("effects and particles animate without errors")
    func animated() async throws {
        let (graph, pipelines) = try await graph(SyntheticScene.Options())
        #expect(graph.nodes.count == 2)
        #expect(graph.report.level == .full)
        let drawer = SceneDrawer(graph: graph, pipelines: pipelines, device: context.device, fill: .fit)
        drawer.cursorProvider = { SIMD2(1, 1) }
        _ = try OffscreenRenderer.render(drawer, context: context, width: 128, height: 72, frames: 30)
        #expect(drawer.particleCount(at: 1) > 0)
        #expect(drawer.time > 0.9)
        #expect(drawer.camera.cursor.x > 0.5)
        drawer.apply(["showdots": .bool(false)])
        _ = try OffscreenRenderer.render(drawer, context: context, width: 32, height: 18)
    }

    @Test("scene renderer lifecycle and preview-only rejection")
    func renderer() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("owscene-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        var options = SyntheticScene.Options()
        options.effects = []
        options.includeParticles = false
        try SyntheticScene.write(SyntheticScene.projectFiles(options: options), to: folder)
        let wallpaper = try ProjectLoader.load(folder: folder)
        let assets = try LayeredAssetSource.forWallpaperFolder(folder)
        let renderer = try #require(SceneRenderer(context: context))
        renderer.parallaxFollowsCursor = false
        try await renderer.load(
            ResolvedWallpaper(wallpaper: wallpaper, assets: assets, values: [:]),
            context: RenderContext(pixelSize: CGSize(width: 64, height: 36), scale: 1)
        )
        #expect(renderer.report?.level == .full)
        renderer.setPlayback(.playing(fps: 30))
        renderer.apply(["bgalpha": .number(0.5)])
        renderer.receive(.silent)
        #expect(try await renderer.snapshot().width > 0)
        #expect(renderer.cursorPosition() == nil)
        renderer.teardown()

        let empty = PKGAssetSource(archive: try PKGParser.parse(PKGWriter.build(files: [("scene.json", Data(#"{"objects":[]}"#.utf8))])))
        let emptyWallpaper = wallpaper.with(title: "empty")
        await #expect(throws: RenderError.unsupported(.scene)) {
            try await SceneRenderer(context: context)!.load(
                ResolvedWallpaper(wallpaper: emptyWallpaper, assets: empty, values: [:]),
                context: RenderContext(pixelSize: .zero, scale: 1)
            )
        }
    }
}

@Suite("Texture upload")
@MainActor
struct TextureUploadTests {
    let device = MetalContext.shared!.device

    @Test("uploads raw, block-compressed and swizzled formats")
    func formats() throws {
        let rgba = try TEXParser.parse(SyntheticScene.gradientTexture(width: 8, height: 4))
        let uploaded = try TextureUploader.upload(rgba, device: device)
        #expect(uploaded.texture.pixelFormat == .rgba8Unorm)
        #expect(uploaded.imageSize == SIMD2(8, 4))
        #expect(uploaded.uvRect(at: 0) == SIMD4(0, 0, 1, 1))

        let bc1 = try TEXParser.parse(TEXWriter.build(format: .dxt1, width: 4, height: 4, pixels: Data(count: 8)))
        #expect(try TextureUploader.upload(bc1, device: device).texture.pixelFormat == .bc1_rgba)
        let r8 = try TEXParser.parse(TEXWriter.build(format: .r8, width: 2, height: 2, pixels: Data(count: 4)))
        let gray = try TextureUploader.upload(r8, device: device)
        #expect(gray.texture.swizzle.green == .red)
        #expect(TextureUploader.pixelFormat(.dxt5) == .bc3_rgba)
        #expect(TextureUploader.pixelFormat(.dxt3) == .bc2_rgba)
        #expect(TextureUploader.pixelFormat(.rg88) == .rg8Unorm)
        #expect(TextureUploader.bytesPerRow(.dxt5, width: 8) == 32)
    }

    @Test("animated sprite sheets cycle frames")
    func animatedFrames() throws {
        let frames = [
            TEXFrame(imageIndex: 0, frameTime: 0.5, x: 0, y: 0, width: 2, height: 2),
            TEXFrame(imageIndex: 0, frameTime: 0.5, x: 2, y: 0, width: 2, height: 2),
        ]
        let base = try TextureUploader.white(device: device)
        let sheet = SceneTexture(texture: base.texture, imageSize: SIMD2(4, 2), uvScale: SIMD2(1, 1), frames: frames, storageSize: SIMD2(4, 2))
        #expect(sheet.isAnimated)
        #expect(sheet.uvRect(at: 0.1) == SIMD4(0, 0, 0.5, 1))
        #expect(sheet.uvRect(at: 0.7) == SIMD4(0.5, 0, 0.5, 1))
        #expect(sheet.uvRect(at: 1.2) == SIMD4(0, 0, 0.5, 1))
    }

    @Test("rejects video payloads and empty textures")
    func rejects() throws {
        var options = TEXWriter.Options()
        options.containerVersion = 4
        var bytes = [UInt8](TEXWriter.build(format: .rgba8888, width: 1, height: 1, pixels: Data(count: 4), options: options))
        // Flip the container's isMP4 flag (after imageCount and imageFormat=-1).
        let headerEnd = 9 + 9 + 28 + 9
        bytes[headerEnd + 8] = 1
        let mp4 = try TEXParser.parse(Data(bytes))
        #expect(mp4.payload == .mp4)
        #expect(throws: RenderError.invalidAsset("video textures are not supported")) {
            try TextureUploader.upload(mp4, device: device)
        }
        #expect(try TextureUploader.softDot(device: device).imageSize == SIMD2(32, 32))
    }
}
