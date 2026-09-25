import AppKit
import OWCore

/// Source of per-display Space information (injectable for tests).
@MainActor
public protocol SpaceProviding: AnyObject {
    var isAvailable: Bool { get }
    /// Spaces per display. Empty when the information is unavailable.
    func snapshot(displays: [DisplayKey]) -> [DisplayKey: DisplaySpaces]
}

/// Reads Spaces through the window server's `CopyManagedDisplaySpaces` call.
///
/// This is a private, read-only API (see docs/adr/0004-per-space-wallpapers.md). It is resolved at
/// runtime with `dlsym`, so if a future macOS removes it, per-Space features simply turn off.
@MainActor
public final class WindowServerSpaceProvider: SpaceProviding {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private let mainConnection: MainConnection?
    private let copySpaces: CopySpaces?

    public init() {
        let candidates: [(String, String, String)] = [
            ("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", "SLSMainConnectionID", "SLSCopyManagedDisplaySpaces"),
            ("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGSMainConnectionID", "CGSCopyManagedDisplaySpaces"),
        ]
        for (path, connection, copy) in candidates {
            guard let handle = dlopen(path, RTLD_LAZY),
                  let connectionSymbol = dlsym(handle, connection),
                  let copySymbol = dlsym(handle, copy)
            else { continue }
            mainConnection = unsafeBitCast(connectionSymbol, to: MainConnection.self)
            copySpaces = unsafeBitCast(copySymbol, to: CopySpaces.self)
            return
        }
        mainConnection = nil
        copySpaces = nil
    }

    public var isAvailable: Bool { copySpaces != nil }

    public func snapshot(displays: [DisplayKey]) -> [DisplayKey: DisplaySpaces] {
        guard let mainConnection, let copySpaces,
              let raw = copySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]]
        else { return [:] }
        return SpaceParser.parse(raw, displays: displays)
    }
}

/// Converts the window server's dictionaries into `DisplaySpaces`.
public enum SpaceParser {
    /// "Displays have separate Spaces" off: one shared list reported under this identifier.
    static let sharedIdentifier = "Main"

    public static func parse(_ raw: [[String: Any]], displays: [DisplayKey]) -> [DisplayKey: DisplaySpaces] {
        var result: [DisplayKey: DisplaySpaces] = [:]
        for entry in raw {
            guard let identifier = entry["Display Identifier"] as? String else { continue }
            let spaces = parseSpaces(entry["Spaces"] as? [[String: Any]] ?? [])
            let current = (entry["Current Space"] as? [String: Any]).flatMap(key(for:))
            let value = DisplaySpaces(spaces: spaces, current: current)
            if identifier == sharedIdentifier {
                displays.forEach { result[$0] = value }
            } else {
                result[DisplayKey(identifier)] = value
            }
        }
        return result
    }

    static func parseSpaces(_ raw: [[String: Any]]) -> [SpaceInfo] {
        var desktopNumber = 0
        return raw.compactMap { space in
            guard let key = key(for: space) else { return nil }
            // type 0 = regular desktop; others (4 = fullscreen app) are not numbered.
            let isFullscreen = (space["type"] as? Int ?? 0) != 0
            if !isFullscreen { desktopNumber += 1 }
            return SpaceInfo(key: key, number: isFullscreen ? 0 : desktopNumber, isFullscreen: isFullscreen)
        }
    }

    /// The persistent `uuid`; the original first desktop has an empty one, so fall back to its id.
    static func key(for space: [String: Any]) -> SpaceKey? {
        if let uuid = space["uuid"] as? String, !uuid.isEmpty { return SpaceKey(uuid) }
        guard let id = space["ManagedSpaceID"] as? Int ?? (space["id64"] as? Int) else { return nil }
        return SpaceKey("managed-\(id)")
    }
}

/// Publishes the active Space of every display and notifies on Space switches.
@MainActor
public final class SpaceMonitor {
    public var onChange: (() -> Void)?
    public private(set) var spaces: [DisplayKey: DisplaySpaces] = [:]

    private let provider: any SpaceProviding
    private var observer: (any NSObjectProtocol)?
    private var displays: [DisplayKey] = []

    public init(provider: any SpaceProviding = WindowServerSpaceProvider()) {
        self.provider = provider
    }

    public var isAvailable: Bool { provider.isAvailable }

    public func start() {
        guard observer == nil, provider.isAvailable else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    public func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    public func updateDisplays(_ keys: [DisplayKey]) {
        displays = keys
        refresh()
    }

    public func currentSpace(on display: DisplayKey) -> SpaceKey? {
        spaces[display]?.current
    }

    /// Re-reads Spaces; calls `onChange` only when something changed.
    public func refresh() {
        guard provider.isAvailable else { return }
        let next = provider.snapshot(displays: displays)
        guard next != spaces else { return }
        spaces = next
        onChange?()
    }
}
