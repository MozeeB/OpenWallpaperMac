import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import OWCore
import OWFormats
import UniformTypeIdentifiers

/// Produces small, disk-cached thumbnails for the library grid (off the main thread).
public actor ThumbnailService {
    public let cacheDirectory: URL
    public let maxPixelSize: Int

    public init(cacheDirectory: URL, maxPixelSize: Int = 480) {
        self.cacheDirectory = cacheDirectory
        self.maxPixelSize = maxPixelSize
    }

    public static func defaultCacheDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenWallpaperMac/Thumbnails")
    }

    /// Cached PNG URL for a wallpaper, generating it if needed. `nil` when no source image exists.
    public func thumbnail(for wallpaper: Wallpaper) async -> URL? {
        let cached = cacheDirectory.appendingPathComponent("\(wallpaper.id.rawValue).png")
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        guard let image = await makeImage(for: wallpaper) else { return nil }
        return write(image, to: cached) ? cached : nil
    }

    public func invalidate(_ id: WallpaperID) {
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("\(id.rawValue).png"))
    }

    func makeImage(for wallpaper: Wallpaper) async -> CGImage? {
        if let preview = wallpaper.preview, let url = try? preview.resolve(in: wallpaper.root),
           let image = downsample(url) {
            return image
        }
        guard let entry = try? wallpaper.entry.resolve(in: wallpaper.root) else { return nil }
        switch wallpaper.type {
        case .image: return downsample(entry)
        case .video: return await videoFrame(entry)
        case .web, .shader, .scene: return nil
        }
    }

    func downsample(_ url: URL) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func videoFrame(_ url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        return try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
    }

    private func write(_ image: CGImage, to url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}

/// Builds render-ready wallpapers (asset source over folder + optional `scene.pkg`).
public enum WallpaperResolver {
    public static func assets(for wallpaper: Wallpaper) throws(PKGError) -> any AssetSource {
        try LayeredAssetSource.forWallpaperFolder(wallpaper.root)
    }
}
