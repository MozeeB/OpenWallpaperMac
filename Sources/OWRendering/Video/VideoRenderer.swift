import AppKit
import AVFoundation
import OWCore
import OWFormats

/// Looping, muted, hardware-decoded video wallpaper.
@MainActor
public final class VideoRenderer: WallpaperRenderer {
    public var onFailure: ((RenderError) -> Void)?
    public let hostView: NSView
    public private(set) var url: URL?
    private var prepared: PreparedVideo?
    private var fpsCap = 30
    private let pool: VideoPlayerPool
    private let playerLayer = AVPlayerLayer()
    private var attached = false

    public static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v", "webm"]

    public init(pool: VideoPlayerPool = .shared) {
        self.pool = pool
        hostView = NSView()
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        hostView.layer?.addSublayer(playerLayer)
    }

    public func load(_ wallpaper: ResolvedWallpaper, context: RenderContext) async throws(RenderError) {
        guard let url = wallpaper.entryFileURL else { throw .assetMissing(wallpaper.wallpaper.entry.string) }
        let asset = AVURLAsset(url: url)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        guard playable, let prepared = try? await PreparedVideo.prepare(url: url) else {
            throw .invalidAsset("not a playable video: \(url.lastPathComponent)")
        }
        self.prepared = prepared
        self.url = url
        playerLayer.videoGravity = VideoRenderer.gravity(context.fill)
        playerLayer.frame = hostView.bounds
        attach()
    }

    static func gravity(_ fill: FillMode) -> AVLayerVideoGravity {
        switch fill {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        }
    }

    private func attach() {
        guard let url, let prepared, !attached else { return }
        playerLayer.player = pool.acquire(url, prepared: prepared, cap: fpsCap, owner: self)
        attached = true
    }

    private func detach() {
        guard let url, attached else { return }
        playerLayer.player = nil
        pool.release(url, owner: self)
        attached = false
    }

    public func setPlayback(_ state: PlaybackState) {
        guard let url else { return }
        switch state {
        case .playing(let fps):
            fpsCap = fps
            attach()
            playerLayer.frame = hostView.bounds
            pool.setPlaying(true, fps: fps, url: url, owner: self)
        case .paused:
            pool.setPlaying(false, url: url, owner: self)
        case .suspended:
            detach()
        }
    }

    public var isAttached: Bool { attached }

    public func apply(_ values: PropertyValues) {}
    public func receive(_ spectrum: AudioSpectrum) {}

    public func snapshot() async throws(RenderError) -> CGImage {
        guard let url else { throw .notLoaded }
        let time = playerLayer.player?.currentTime() ?? .zero
        return try await VideoRenderer.frame(of: url, at: time)
    }

    /// Extracts a still frame; used for poster sync and thumbnails.
    public nonisolated static func frame(of url: URL, at time: CMTime = .zero) async throws(RenderError) -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        generator.maximumSize = CGSize(width: 3840, height: 3840)
        do {
            return try await generator.image(at: time).image
        } catch {
            throw .snapshotFailed
        }
    }

    public func teardown() {
        detach()
        playerLayer.removeFromSuperlayer()
        url = nil
        prepared = nil
    }
}
