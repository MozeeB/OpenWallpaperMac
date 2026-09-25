import AppKit
import ImageIO
import OWCore
import OWFormats

/// Static image wallpaper: a single CALayer, zero per-frame cost.
@MainActor
public final class ImageRenderer: WallpaperRenderer {
    public var onFailure: ((RenderError) -> Void)?
    public let hostView: NSView
    public private(set) var image: CGImage?
    public nonisolated static let maxBytes = 200 * 1024 * 1024

    public init() {
        hostView = NSView()
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.black.cgColor
    }

    public func load(_ wallpaper: ResolvedWallpaper, context: RenderContext) async throws(RenderError) {
        let data: Data
        do {
            data = try wallpaper.assets.data(at: wallpaper.wallpaper.entry)
        } catch {
            throw .assetMissing(wallpaper.wallpaper.entry.string)
        }
        let result = await Task.detached(priority: .utility) {
            Result { () throws(RenderError) -> CGImage in try ImageRenderer.decode(data) }
        }.value
        let image = try result.get()
        self.image = image
        hostView.layer?.contents = image
        hostView.layer?.contentsGravity = context.fill.layerGravity
    }

    nonisolated static func decode(_ data: Data) throws(RenderError) -> CGImage {
        guard data.count <= maxBytes else { throw .invalidAsset("image larger than 200 MB") }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options)
        else { throw .invalidAsset("unreadable image") }
        return image
    }

    public func setPlayback(_ state: PlaybackState) {
        if state == .suspended { hostView.layer?.contents = nil } else if hostView.layer?.contents == nil {
            hostView.layer?.contents = image
        }
    }

    public func apply(_ values: PropertyValues) {}
    public func receive(_ spectrum: AudioSpectrum) {}

    public func snapshot() async throws(RenderError) -> CGImage {
        guard let image else { throw .notLoaded }
        return image
    }

    public func teardown() {
        hostView.layer?.contents = nil
        image = nil
    }
}
