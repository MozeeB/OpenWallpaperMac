import AppKit
import OWCore
import OWFormats

public enum RenderError: Error, Equatable, Sendable {
    case unsupported(WallpaperType)
    case assetMissing(String)
    case invalidAsset(String)
    case metalUnavailable
    case compile(line: Int?, message: String)
    case gpuHang
    case snapshotFailed
    case notLoaded
    case web(String)
}

/// A wallpaper with everything needed to render it.
public struct ResolvedWallpaper: Sendable {
    public let wallpaper: Wallpaper
    public let assets: any AssetSource
    public let values: PropertyValues

    public init(wallpaper: Wallpaper, assets: any AssetSource, values: PropertyValues) {
        self.wallpaper = wallpaper
        self.assets = assets
        self.values = values
    }

    /// File URL of the entry when it exists on disk (video/web/image need real files).
    public var entryFileURL: URL? {
        guard let url = try? wallpaper.entry.resolve(in: wallpaper.root),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }
}

/// Per-display rendering parameters.
public struct RenderContext: Sendable {
    public let pixelSize: CGSize
    public let scale: CGFloat
    public let fill: FillMode
    /// Fraction of native resolution for GPU renderers (shaders/scenes), 0.25...1.
    public let renderScale: CGFloat

    public init(pixelSize: CGSize, scale: CGFloat, fill: FillMode = .fill, renderScale: CGFloat = 1) {
        self.pixelSize = pixelSize
        self.scale = max(scale, 1)
        self.fill = fill
        self.renderScale = min(max(renderScale, 0.25), 1)
    }
}

/// Common interface of every renderer family.
@MainActor
public protocol WallpaperRenderer: AnyObject {
    var hostView: NSView { get }
    /// Called when the renderer disables itself (e.g. GPU hang) so the host can fall back.
    var onFailure: ((RenderError) -> Void)? { get set }
    func load(_ wallpaper: ResolvedWallpaper, context: RenderContext) async throws(RenderError)
    func setPlayback(_ state: PlaybackState)
    func apply(_ values: PropertyValues)
    func receive(_ spectrum: AudioSpectrum)
    func snapshot() async throws(RenderError) -> CGImage
    func teardown()
}

/// Builds renderers; implemented by the app layer, which knows every family (including scenes).
@MainActor
public protocol RendererMaking {
    func makeRenderer(for type: WallpaperType) -> Result<any WallpaperRenderer, RenderError>
}

public extension FillMode {
    var layerGravity: CALayerContentsGravity {
        switch self {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        }
    }
}
