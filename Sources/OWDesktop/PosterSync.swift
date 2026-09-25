import AppKit
import ImageIO
import OWCore
import UniformTypeIdentifiers

public enum DesktopError: Error, Equatable, Sendable {
    case screenNotFound(DisplayKey)
    case writeFailed(String)
    case setFailed(String)
}

/// Sets the *system* desktop picture (what Mission Control, Space swipes, the menu bar tint
/// and the lock screen show). Injectable for tests.
@MainActor
public protocol DesktopImageSetting {
    func currentImage(for display: DisplayKey) -> URL?
    func setImage(_ url: URL, for display: DisplayKey) throws(DesktopError)
}

@MainActor
public struct WorkspaceDesktopImageSetter: DesktopImageSetting {
    private let screens: any ScreenProviding

    public init(screens: any ScreenProviding = SystemScreenProvider()) {
        self.screens = screens
    }

    public func currentImage(for display: DisplayKey) -> URL? {
        screens.nsScreen(for: display).flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }

    public func setImage(_ url: URL, for display: DisplayKey) throws(DesktopError) {
        guard let screen = screens.nsScreen(for: display) else { throw .screenNotFound(display) }
        do {
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        } catch {
            throw .setFailed(error.localizedDescription)
        }
    }
}

/// Writes poster frames and keeps the system wallpaper in sync; restores the original on quit.
@MainActor
public final class PosterSync {
    private let setter: any DesktopImageSetting
    private let directory: URL
    private let backupURL: URL
    private var originals: [DisplayKey: URL]
    private var sequence = 0

    public init(setter: any DesktopImageSetting, directory: URL) {
        self.setter = setter
        self.directory = directory
        backupURL = directory.appendingPathComponent("originals.json")
        originals = PosterSync.loadBackup(backupURL)
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenWallpaperMac/Posters")
    }

    /// Writes `image` under a unique name (macOS caches desktop pictures by URL) and applies it.
    @discardableResult
    public func apply(_ image: CGImage, for display: DisplayKey) throws(DesktopError) -> URL {
        rememberOriginal(for: display)
        sequence += 1
        let prefix = PosterSync.filePrefix(display)
        let url = directory.appendingPathComponent("\(prefix)\(Int(Date().timeIntervalSince1970))-\(sequence).png")
        try write(image, to: url)
        try setter.setImage(url, for: display)
        removeStalePosters(prefix: prefix, keeping: url)
        return url
    }

    /// Puts back whatever wallpaper each display had before we touched it.
    public func restoreOriginals() {
        for (display, url) in originals where FileManager.default.fileExists(atPath: url.path) {
            try? setter.setImage(url, for: display)
        }
        originals = [:]
        try? FileManager.default.removeItem(at: backupURL)
    }

    public var rememberedOriginals: [DisplayKey: URL] { originals }

    private func rememberOriginal(for display: DisplayKey) {
        guard originals[display] == nil, let current = setter.currentImage(for: display),
              !current.path.hasPrefix(directory.path)
        else { return }
        originals[display] = current
        saveBackup()
    }

    private func write(_ image: CGImage, to url: URL) throws(DesktopError) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw .writeFailed(url.path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw .writeFailed(url.path) }
    }

    private func removeStalePosters(prefix: String, keeping url: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.lastPathComponent != url.lastPathComponent {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func filePrefix(_ display: DisplayKey) -> String {
        "poster-" + display.rawValue.filter { $0.isLetter || $0.isNumber || $0 == "-" } + "-"
    }

    private func saveBackup() {
        let encoded = originals.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.path }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: backupURL, options: .atomic)
    }

    private static func loadBackup(_ url: URL) -> [DisplayKey: URL] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded.reduce(into: [:]) { $0[DisplayKey($1.key)] = URL(fileURLWithPath: $1.value) }
    }
}
