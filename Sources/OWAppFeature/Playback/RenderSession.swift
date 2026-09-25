import OWCore
import OWRendering

/// One wallpaper running on one display.
@MainActor
final class RenderSession {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(RenderError)
    }

    let display: DisplayKey
    let wallpaper: Wallpaper
    let renderer: any WallpaperRenderer
    /// True when this session shows the preview image because the real wallpaper failed.
    let isFallback: Bool
    var phase: Phase = .loading
    var values: PropertyValues
    var playback: PlaybackState = .paused
    var loadTask: Task<Void, Never>?

    init(display: DisplayKey, wallpaper: Wallpaper, renderer: any WallpaperRenderer, values: PropertyValues, isFallback: Bool) {
        self.display = display
        self.wallpaper = wallpaper
        self.renderer = renderer
        self.values = values
        self.isFallback = isFallback
    }

    var wantsAudio: Bool { wallpaper.usesAudio && phase == .ready && playback.isPlaying }

    /// Records the desired state; only calls the renderer when it is loaded and the state changed.
    func apply(playback state: PlaybackState) {
        let changed = state != playback
        playback = state
        guard phase == .ready, changed else { return }
        renderer.setPlayback(state)
    }

    func teardown() {
        loadTask?.cancel()
        renderer.teardown()
    }
}

/// Things the coordinator reports to the UI layer.
public enum CoordinatorEvent: Equatable, Sendable {
    case loaded(DisplayKey, WallpaperID)
    case failed(DisplayKey, WallpaperID, RenderError)
    case fellBackToPreview(DisplayKey, WallpaperID)
    case audioSilent
    case audioUnavailable(String)
    case spacesChanged
}
