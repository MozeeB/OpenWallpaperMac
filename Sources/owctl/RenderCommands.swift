import ArgumentParser
import AVFoundation
import Darwin
import Foundation
import OWCore
import OWFormats
import OWLibrary
import OWRendering
import OWScene

/// Loads a shader or scene folder into an offscreen-drawable program.
@MainActor
enum DrawerLoader {
    static func load(folder: URL, context: MetalContext) async throws -> (any FrameDrawing, Wallpaper) {
        let wallpaper = try ImportService(libraryRoot: folder, knownEffects: EffectRegistry.known).importFolder(folder)
        let assets = try LayeredAssetSource.forWallpaperFolder(folder)
        switch wallpaper.type {
        case .shader:
            guard let source = String(data: try assets.data(at: wallpaper.entry), encoding: .utf8) else {
                throw CLIError("shader is not UTF-8")
            }
            let program = try await ShaderProgram.compile(source: source, definitions: wallpaper.properties, context: context)
            program.apply(wallpaper.defaultValues)
            return (program, wallpaper)
        case .scene:
            let pipelines = try await ScenePipelines.shared(context: context)
            let graph = try SceneGraphBuilder.build(entry: wallpaper.entry, assets: assets, device: context.device, pipelines: pipelines)
            let drawer = SceneDrawer(graph: graph, pipelines: pipelines, device: context.device, fill: .fill)
            drawer.apply(wallpaper.defaultValues)
            return (drawer, wallpaper)
        default:
            throw CLIError("render/bench support shader and scene wallpapers (use bench on a video file for decode cost)")
        }
    }
}

struct RenderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "render", abstract: "Render a shader/scene offscreen to PNG.")

    @Argument var folder: String
    @Option(help: "Output PNG path.") var out = "render.png"
    @Option(help: "Width in pixels.") var width = 1280
    @Option(help: "Height in pixels.") var height = 720
    @Option(help: "Frames to simulate before capturing.") var frames = 30

    @MainActor
    func run() async throws {
        guard let context = MetalContext.shared else { throw CLIError("Metal unavailable") }
        let (drawer, _) = try await DrawerLoader.load(folder: URL(fileURLWithPath: folder), context: context)
        let bitmap = try OffscreenRenderer.render(drawer, context: context, width: width, height: height, frames: frames)
        try TEXImageConverter.writePNG(bitmap, to: URL(fileURLWithPath: out))
        print("Wrote \(width)x\(height) after \(frames) frames to \(out)")
    }
}

/// Process-level resource usage for benchmarks.
enum ResourceUsage {
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return user + system
    }

    static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }
}

struct BenchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bench",
        abstract: "Measure per-frame cost; prints JSON with estimated CPU % at the target frame rate."
    )

    @Argument(help: "Shader/scene folder, or a video file (measures hardware decode cost).")
    var path: String
    @Option var width = 3840
    @Option var height = 2160
    @Option var frames = 300
    @Option(help: "Frame rate used to project CPU %.") var fps = 30

    @MainActor
    func run() async throws {
        let url = URL(fileURLWithPath: path)
        let result = VideoRenderer.supportedExtensions.contains(url.pathExtension.lowercased())
            ? try await benchVideo(url)
            : try await benchDrawer(url)
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(bytes: data, encoding: .utf8) ?? "{}")
    }

    @MainActor
    private func benchDrawer(_ folder: URL) async throws -> [String: Any] {
        guard let context = MetalContext.shared else { throw CLIError("Metal unavailable") }
        let (drawer, wallpaper) = try await DrawerLoader.load(folder: folder, context: context)
        _ = try OffscreenRenderer.render(drawer, context: context, width: width, height: height, frames: 5)
        let cpuStart = ResourceUsage.cpuSeconds()
        let wallStart = Date()
        _ = try OffscreenRenderer.render(drawer, context: context, width: width, height: height, frames: frames)
        return summary(kind: wallpaper.type.rawValue, cpu: ResourceUsage.cpuSeconds() - cpuStart,
                       wall: Date().timeIntervalSince(wallStart), note: "offscreen, includes GPU wait + readback")
    }

    private func benchVideo(_ url: URL) async throws -> [String: Any] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CLIError("no video track") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        reader.add(output)
        reader.startReading()
        let cpuStart = ResourceUsage.cpuSeconds()
        let wallStart = Date()
        var decoded = 0
        while decoded < frames, output.copyNextSampleBuffer() != nil { decoded += 1 }
        reader.cancelReading()
        let size = try await track.load(.naturalSize)
        var result = summary(kind: "video", cpu: ResourceUsage.cpuSeconds() - cpuStart, wall: Date().timeIntervalSince(wallStart),
                             note: "hardware decode only; compositing happens in WindowServer", count: decoded)
        result["videoSize"] = "\(Int(size.width))x\(Int(size.height))"
        return result
    }

    private func summary(kind: String, cpu: Double, wall: Double, note: String, count: Int? = nil) -> [String: Any] {
        let rendered = Double(count ?? frames)
        let cpuPerFrameMs = cpu / max(rendered, 1) * 1000
        return [
            "kind": kind, "frames": Int(rendered), "size": "\(width)x\(height)",
            "cpuMsPerFrame": (cpuPerFrameMs * 100).rounded() / 100,
            "wallMsPerFrame": ((wall / max(rendered, 1) * 1000) * 100).rounded() / 100,
            "estimatedCPUPercentAtTargetFPS": ((cpuPerFrameMs * Double(fps) / 10) * 100).rounded() / 100,
            "targetFPS": fps, "residentMB": ResourceUsage.residentMB().rounded(), "note": note,
        ]
    }
}
