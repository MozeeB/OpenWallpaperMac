import AVFoundation
import Foundation

/// A video prepared for wallpaper playback: audio stripped, frame-rate cap ready to apply.
public struct PreparedVideo: @unchecked Sendable {
    /// Video-only composition of the source file (audio is never decoded).
    public let asset: AVAsset
    public let sourceFPS: Float
    /// Base video composition used to cap the output frame rate; nil if unavailable.
    public let baseComposition: AVVideoComposition?

    /// Output frame rate for a cap: the source rate when it is already at or below the cap.
    public func effectiveFPS(cap: Int) -> Int {
        let source = sourceFPS > 0 ? Int(sourceFPS.rounded()) : cap
        return max(1, min(source, cap))
    }

    /// Composition that makes the player emit `fps` frames per second, or nil when no cap is needed.
    public func composition(cap: Int) -> AVVideoComposition? {
        guard let base = baseComposition, effectiveFPS(cap: cap) < Int(sourceFPS.rounded()),
              let mutable = base.mutableCopy() as? AVMutableVideoComposition
        else { return nil }
        mutable.frameDuration = CMTime(value: 1, timescale: CMTimeScale(effectiveFPS(cap: cap)))
        return mutable
    }

    /// Loads tracks off the main thread and builds the video-only asset.
    public static func prepare(url: URL) async throws -> PreparedVideo {
        let source = AVURLAsset(url: url)
        guard let track = try await source.loadTracks(withMediaType: .video).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let (duration, fps, transform) = try await (source.load(.duration), track.load(.nominalFrameRate),
                                                    track.load(.preferredTransform))
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        videoTrack.preferredTransform = transform
        let base = try? await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        return PreparedVideo(asset: composition, sourceFPS: fps, baseComposition: base)
    }
}

/// Shares one decoder (`AVQueuePlayer` + `AVPlayerLooper`) per video file across displays.
///
/// Each display gets its own `AVPlayerLayer`, but the file is decoded once. The player runs while
/// at least one owner wants playback and is released when the last owner leaves.
@MainActor
public final class VideoPlayerPool {
    final class Entry {
        let player: AVQueuePlayer
        let prepared: PreparedVideo
        private(set) var looper: AVPlayerLooper
        private(set) var outputFPS: Int
        var owners: [ObjectIdentifier: Bool] = [:]

        init(prepared: PreparedVideo, cap: Int) {
            self.prepared = prepared
            player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.allowsExternalPlayback = false
            player.automaticallyWaitsToMinimizeStalling = false
            player.actionAtItemEnd = .advance
            outputFPS = prepared.effectiveFPS(cap: cap)
            looper = AVPlayerLooper(player: player, templateItem: Entry.item(prepared, cap: cap))
        }

        static func item(_ prepared: PreparedVideo, cap: Int) -> AVPlayerItem {
            let item = AVPlayerItem(asset: prepared.asset)
            item.preferredForwardBufferDuration = 2
            item.videoComposition = prepared.composition(cap: cap)
            return item
        }

        /// Rebuilds the loop when the effective output rate changes (e.g. switching to battery).
        func apply(cap: Int) {
            let fps = prepared.effectiveFPS(cap: cap)
            guard fps != outputFPS else { return }
            outputFPS = fps
            let time = player.currentTime()
            let wasPlaying = player.rate != 0
            looper.disableLooping()
            player.removeAllItems()
            looper = AVPlayerLooper(player: player, templateItem: Entry.item(prepared, cap: cap))
            player.seek(to: time, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
            if wasPlaying { player.play() }
        }
    }

    public static let shared = VideoPlayerPool()

    private var entries: [URL: Entry] = [:]

    public init() {}

    public func acquire(_ url: URL, prepared: PreparedVideo, cap: Int = 30, owner: AnyObject) -> AVQueuePlayer {
        let key = url.standardizedFileURL
        let entry = entries[key] ?? Entry(prepared: prepared, cap: cap)
        entries[key] = entry
        if entry.owners[ObjectIdentifier(owner)] == nil { entry.owners[ObjectIdentifier(owner)] = false }
        return entry.player
    }

    public func setPlaying(_ playing: Bool, fps: Int? = nil, url: URL, owner: AnyObject) {
        guard let entry = entries[url.standardizedFileURL] else { return }
        entry.owners[ObjectIdentifier(owner)] = playing
        if let fps { entry.apply(cap: fps) }
        updateRate(entry)
    }

    private func updateRate(_ entry: Entry) {
        let shouldPlay = entry.owners.values.contains(true)
        if shouldPlay, entry.player.rate == 0 { entry.player.play() }
        if !shouldPlay, entry.player.rate != 0 { entry.player.pause() }
    }

    public func release(_ url: URL, owner: AnyObject) {
        let key = url.standardizedFileURL
        guard let entry = entries[key] else { return }
        entry.owners.removeValue(forKey: ObjectIdentifier(owner))
        if entry.owners.isEmpty {
            entry.player.pause()
            entry.looper.disableLooping()
            entry.player.removeAllItems()
            entries.removeValue(forKey: key)
        } else {
            updateRate(entry)
        }
    }

    public var activeDecoders: Int { entries.count }

    public func ownerCount(for url: URL) -> Int {
        entries[url.standardizedFileURL]?.owners.count ?? 0
    }

    public func isPlaying(_ url: URL) -> Bool {
        (entries[url.standardizedFileURL]?.player.rate ?? 0) != 0
    }

    /// Frame rate the shared player currently emits for `url`.
    public func outputFPS(for url: URL) -> Int? {
        entries[url.standardizedFileURL]?.outputFPS
    }
}
