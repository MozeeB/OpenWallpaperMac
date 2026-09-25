import AVFoundation
import Foundation

/// Shares one decoder (`AVQueuePlayer` + `AVPlayerLooper`) per video file across displays.
///
/// Each display gets its own `AVPlayerLayer`, but the file is decoded once. The player runs while
/// at least one owner wants playback and is released when the last owner leaves.
@MainActor
public final class VideoPlayerPool {
    final class Entry {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        var owners: [ObjectIdentifier: Bool] = [:]

        init(url: URL) {
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 2
            player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.allowsExternalPlayback = false
            player.automaticallyWaitsToMinimizeStalling = false
            player.actionAtItemEnd = .advance
            looper = AVPlayerLooper(player: player, templateItem: item)
        }
    }

    public static let shared = VideoPlayerPool()

    private var entries: [URL: Entry] = [:]

    public init() {}

    public func acquire(_ url: URL, owner: AnyObject) -> AVQueuePlayer {
        let key = url.standardizedFileURL
        let entry = entries[key] ?? Entry(url: key)
        entries[key] = entry
        if entry.owners[ObjectIdentifier(owner)] == nil { entry.owners[ObjectIdentifier(owner)] = false }
        return entry.player
    }

    public func setPlaying(_ playing: Bool, url: URL, owner: AnyObject) {
        guard let entry = entries[url.standardizedFileURL] else { return }
        entry.owners[ObjectIdentifier(owner)] = playing
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
}
