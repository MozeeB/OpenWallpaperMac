import OWCore
import OWRendering
import OWScene

/// Creates the right renderer for each wallpaper family.
@MainActor
public struct DefaultRendererFactory: RendererMaking {
    public init() {}

    public func makeRenderer(for type: WallpaperType) -> Result<any WallpaperRenderer, RenderError> {
        switch type {
        case .image:
            return .success(ImageRenderer())
        case .video:
            return .success(VideoRenderer())
        case .web:
            return .success(WebRenderer())
        case .shader:
            return ShaderRenderer().map { .success($0) } ?? .failure(.metalUnavailable)
        case .scene:
            return SceneRenderer().map { .success($0) } ?? .failure(.metalUnavailable)
        }
    }
}
