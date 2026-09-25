import AppKit
import OWCore
import OWFormats
import OWRendering

/// Renders Wallpaper Engine-style scenes natively in Metal.
@MainActor
public final class SceneRenderer: WallpaperRenderer {
    public var onFailure: ((RenderError) -> Void)? {
        didSet { host.onFailure = onFailure }
    }

    public var hostView: NSView { host.view }
    public private(set) var drawer: SceneDrawer?
    public private(set) var report: SupportReport?
    private let host: MetalFrameHost
    private let context: MetalContext
    private var requested: PlaybackState = .paused
    /// Parallax follows the global cursor when the scene enables camera parallax.
    public var parallaxFollowsCursor = true

    public init?(context: MetalContext? = .shared) {
        guard let context else { return nil }
        self.context = context
        host = MetalFrameHost(context: context)
    }

    public func load(_ wallpaper: ResolvedWallpaper, context renderContext: RenderContext) async throws(RenderError) {
        let pipelines = try await ScenePipelines.shared(context: context)
        let graph = try SceneGraphBuilder.build(
            entry: wallpaper.wallpaper.entry, assets: wallpaper.assets, device: context.device, pipelines: pipelines
        )
        let drawer = SceneDrawer(graph: graph, pipelines: pipelines, device: context.device, fill: renderContext.fill)
        drawer.apply(wallpaper.wallpaper.properties.resolve(wallpaper.values))
        if parallaxFollowsCursor {
            drawer.cursorProvider = { [weak self] in self?.cursorPosition() }
        }
        self.drawer = drawer
        report = graph.report
        host.drawer = drawer
        host.configure(renderScale: renderContext.renderScale)
    }

    /// Cursor position relative to this window, normalised to 0...1 with y up.
    func cursorPosition() -> SIMD2<Float>? {
        guard let frame = hostView.window?.frame, frame.width > 0, frame.height > 0 else { return nil }
        let location = NSEvent.mouseLocation
        return SIMD2(Float((location.x - frame.minX) / frame.width), Float((location.y - frame.minY) / frame.height))
    }

    public func setPlayback(_ state: PlaybackState) {
        requested = state
        guard let drawer else { return }
        if case .playing = state, !drawer.isAnimated {
            // Static scene: draw once, keep the display link stopped.
            host.setPlayback(.paused)
            host.redraw()
        } else {
            host.setPlayback(state)
        }
    }

    public func apply(_ values: PropertyValues) {
        guard let drawer else { return }
        drawer.apply(values)
        setPlayback(requested)
        host.redraw()
    }

    public func receive(_ spectrum: AudioSpectrum) {}

    public func snapshot() async throws(RenderError) -> CGImage {
        try host.snapshot()
    }

    public func teardown() {
        host.teardown()
        drawer = nil
    }
}
