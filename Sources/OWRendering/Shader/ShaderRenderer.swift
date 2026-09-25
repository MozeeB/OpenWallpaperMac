import AppKit
import OWCore
import OWFormats

/// Renders a user Metal shader wallpaper.
@MainActor
public final class ShaderRenderer: WallpaperRenderer {
    public var onFailure: ((RenderError) -> Void)? {
        didSet { host.onFailure = onFailure }
    }

    public var hostView: NSView { host.view }
    public private(set) var program: ShaderProgram?
    private let host: MetalFrameHost
    private let context: MetalContext

    public init?(context: MetalContext? = .shared) {
        guard let context else { return nil }
        self.context = context
        host = MetalFrameHost(context: context)
    }

    public func load(_ wallpaper: ResolvedWallpaper, context renderContext: RenderContext) async throws(RenderError) {
        let data: Data
        do {
            data = try wallpaper.assets.data(at: wallpaper.wallpaper.entry)
        } catch {
            throw .assetMissing(wallpaper.wallpaper.entry.string)
        }
        guard data.count <= 512 * 1024, let source = String(data: data, encoding: .utf8) else {
            throw .invalidAsset("shader source must be UTF-8 and under 512 KB")
        }
        let program = try await ShaderProgram.compile(
            source: source, definitions: wallpaper.wallpaper.properties, context: context
        )
        program.apply(wallpaper.values)
        self.program = program
        host.drawer = program
        host.configure(renderScale: renderContext.renderScale)
    }

    public func setPlayback(_ state: PlaybackState) {
        host.setPlayback(state)
    }

    public func apply(_ values: PropertyValues) {
        program?.apply(values)
        host.redraw()
    }

    public func receive(_ spectrum: AudioSpectrum) {
        program?.receive(spectrum)
    }

    public func snapshot() async throws(RenderError) -> CGImage {
        try host.snapshot()
    }

    public func teardown() {
        host.teardown()
        program = nil
    }
}
