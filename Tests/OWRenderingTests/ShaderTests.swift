import Foundation
import Metal
import Testing
@testable import OWCore
@testable import OWFormats
@testable import OWRendering

private func slider(_ key: String, value: Double = 0.5) -> PropertyDefinition {
    PropertyDefinition(key: key, label: key, order: 0, kind: .slider(min: 0, max: 1, step: 0.1), defaultValue: .number(value))
}

@Suite("Shader source & uniforms")
struct ShaderSourceTests {
    @Test("wraps user code with prelude, macros and #line")
    func build() {
        let source = ShaderSourceBuilder.build(
            userSource: "float4 mainImage(float2 c, constant OWUniforms& u) { return prop_speed; }",
            properties: [slider("speed"), slider("bad-key"), slider("2d")]
        )
        #expect(source.contains("#define prop_speed (u.props[0])"))
        #expect(!source.contains("bad-key"))
        #expect(!source.contains("prop_2d"))
        #expect(source.contains("#line 1 \"wallpaper.metal\""))
        #expect(source.contains("fragment float4 ow_fragment"))
        #expect(ShaderSourceBuilder.propertySlots((0 ..< 20).map { slider("k\($0)") }).count == 16)
    }

    @Test("parses compiler errors with user line numbers")
    func errors() {
        let message = "program_source:40:1: warning: x\nwallpaper.metal:3:12: error: use of undeclared identifier 'foo'\n"
        #expect(ShaderSourceBuilder.parseCompileError(message) == .compile(line: 3, message: "use of undeclared identifier 'foo'"))
        #expect(ShaderSourceBuilder.parseCompileError("boom") == .compile(line: nil, message: "boom"))
    }

    @Test("packs uniforms into the Metal layout")
    func packing() {
        var uniforms = ShaderUniforms()
        uniforms.resolution = SIMD3(100, 50, 1)
        uniforms.time = 2
        uniforms.frame = 7
        uniforms.audio = [0.5]
        uniforms.properties = [SIMD4(1, 2, 3, 4)]
        let packed = uniforms.packed()
        #expect(packed.count == ShaderUniforms.floatCount)
        #expect(Array(packed[0 ..< 4]) == [100, 50, 1, 2])
        #expect(packed[5].bitPattern == 7)
        #expect(packed[16] == 0.5)
        #expect(Array(packed[80 ..< 84]) == [1, 2, 3, 4])
        #expect(ShaderUniforms.byteCount == 576)
    }

    @Test("property vectors and date")
    func vectors() {
        let definitions = [
            slider("a"),
            PropertyDefinition(key: "c", label: "c", order: 1, kind: .color, defaultValue: .color(.white)),
            PropertyDefinition(key: "b", label: "b", order: 2, kind: .bool, defaultValue: .bool(true)),
        ]
        let vectors = ShaderUniforms.propertyVectors(definitions, values: definitions.resolve(["a": .number(0.25)]))
        #expect(vectors == [SIMD4(0.25, 0, 0, 0), SIMD4(1, 1, 1, 1), SIMD4(1, 0, 0, 0)])
        #expect(ShaderUniforms.vector(.string("3")) == SIMD4(3, 0, 0, 0))
        #expect(ShaderUniforms.vector(nil) == .zero)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = ShaderUniforms.dateVector(Date(timeIntervalSince1970: 3661), calendar: calendar)
        #expect(date == SIMD4(1970, 0, 1, 3661))
    }

    @Test("watchdog trips on errors or repeated slow frames")
    func watchdog() {
        var dog = GPUWatchdog(frameBudget: 0.1, strikesAllowed: 2)
        let results = [(0.2, false), (0.01, false), (0.2, false), (0.2, false)].map {
            dog.record(gpuTime: $0.0, failed: $0.1)
        }
        #expect(results == [false, false, false, true])
        var fresh = GPUWatchdog()
        let tripped = fresh.record(gpuTime: 0, failed: true)
        #expect(tripped)
    }
}

@Suite("Shader rendering (Metal)")
@MainActor
struct ShaderRenderingTests {
    let context = MetalContext.shared!

    @Test("renders a property-driven colour offscreen")
    func offscreen() async throws {
        let source = """
        float4 mainImage(float2 fragCoord, constant OWUniforms& u) {
            float2 uv = fragCoord / u.iResolution.xy;
            return float4(uv.x < 0.5 ? prop_level.x : 0.0, owAudio(u, 0), 0.0, 1.0);
        }
        """
        let definitions = [slider("level", value: 1)]
        let program = try await ShaderProgram.compile(source: source, definitions: definitions, context: context)
        program.apply([:])
        program.receive(AudioSpectrum(left: [1], right: [1]))
        let bitmap = try OffscreenRenderer.render(program, context: context, width: 8, height: 4, frames: 2)
        #expect(bitmap.pixel(x: 1, y: 1) == [255, 255, 0, 255])
        #expect(bitmap.pixel(x: 6, y: 1) == [0, 255, 0, 255])
        #expect(program.uniforms.frame == 2)
        #expect(abs(program.elapsed - 2.0 / 30) < 0.001)
    }

    @Test("reports compile errors with line numbers")
    func compileError() async {
        let source = "float4 mainImage(float2 c, constant OWUniforms& u) {\n  return undefinedThing;\n}"
        await #expect(throws: RenderError.compile(line: 2, message: "use of undeclared identifier 'undefinedThing'")) {
            _ = try await ShaderProgram.compile(source: source, definitions: [], context: context)
        }
    }

    @Test("shader renderer loads from assets, plays, pauses and snapshots")
    func renderer() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("owshader-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try SyntheticScene.write([("a.metal", Data("float4 mainImage(float2 c, constant OWUniforms& u) { return float4(1,0,0,1); }".utf8))], to: folder)
        let wallpaper = Wallpaper(id: .random(), title: "S", type: .shader, origin: .native, root: folder, entry: try SanitizedPath("a.metal"))
        let renderer = try #require(ShaderRenderer(context: context))
        try await renderer.load(
            ResolvedWallpaper(wallpaper: wallpaper, assets: FolderAssetSource(root: folder), values: [:]),
            context: RenderContext(pixelSize: CGSize(width: 64, height: 64), scale: 2, renderScale: 0.5)
        )
        renderer.setPlayback(.playing(fps: 30))
        renderer.setPlayback(.paused)
        renderer.apply([:])
        renderer.receive(.silent)
        let image = try await renderer.snapshot()
        #expect(image.width > 0)
        renderer.teardown()
        await #expect(throws: RenderError.notLoaded) { _ = try await renderer.snapshot() }
    }

    @Test("rejects missing and oversized shader sources")
    func invalidSources() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("owshader-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try SyntheticScene.write([("big.metal", Data(count: 600 * 1024))], to: folder)
        let renderer = try #require(ShaderRenderer(context: context))
        let context = RenderContext(pixelSize: .zero, scale: 1)
        for (name, expected) in [("missing.metal", RenderError.assetMissing("missing.metal")),
                                 ("big.metal", .invalidAsset("shader source must be UTF-8 and under 512 KB"))] {
            let wallpaper = Wallpaper(id: .random(), title: "S", type: .shader, origin: .native, root: folder, entry: try SanitizedPath(name))
            await #expect(throws: expected) {
                try await renderer.load(ResolvedWallpaper(wallpaper: wallpaper, assets: FolderAssetSource(root: folder), values: [:]), context: context)
            }
        }
    }

    @Test("frame host records GPU failures once")
    func hostFailure() {
        let host = MetalFrameHost(context: context)
        var failures: [RenderError] = []
        host.onFailure = { failures.append($0) }
        host.recordCompletion(gpuTime: 0, failed: true)
        host.recordCompletion(gpuTime: 0, failed: true)
        #expect(failures == [.gpuHang])
        host.setPlayback(.playing(fps: 30))
        #expect(!host.isRunning)
        #expect(throws: RenderError.notLoaded) { try host.snapshot() }
    }
}
