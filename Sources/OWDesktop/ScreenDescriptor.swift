import AppKit
import CoreGraphics
import OWCore

/// Immutable description of one connected display.
public struct ScreenDescriptor: Equatable, Sendable {
    public let key: DisplayKey
    public let displayID: CGDirectDisplayID
    public let name: String
    /// AppKit frame (bottom-left origin), used to place windows.
    public let frame: CGRect
    /// CoreGraphics bounds (top-left origin), used to compare against the window list.
    public let cgBounds: CGRect
    public let scale: CGFloat

    public init(key: DisplayKey, displayID: CGDirectDisplayID, name: String, frame: CGRect, cgBounds: CGRect, scale: CGFloat) {
        self.key = key
        self.displayID = displayID
        self.name = name
        self.frame = frame
        self.cgBounds = cgBounds
        self.scale = scale
    }

    public var pixelSize: CGSize {
        CGSize(width: frame.width * scale, height: frame.height * scale)
    }
}

/// Source of connected screens (injectable for tests).
@MainActor
public protocol ScreenProviding {
    func currentScreens() -> [ScreenDescriptor]
    func nsScreen(for key: DisplayKey) -> NSScreen?
}

@MainActor
public struct SystemScreenProvider: ScreenProviding {
    public init() {}

    public func currentScreens() -> [ScreenDescriptor] {
        NSScreen.screens.compactMap(SystemScreenProvider.descriptor)
    }

    public func nsScreen(for key: DisplayKey) -> NSScreen? {
        NSScreen.screens.first { SystemScreenProvider.descriptor($0)?.key == key }
    }

    static func descriptor(_ screen: NSScreen) -> ScreenDescriptor? {
        let numberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[numberKey] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        return ScreenDescriptor(
            key: displayKey(for: displayID), displayID: displayID, name: screen.localizedName,
            frame: screen.frame, cgBounds: CGDisplayBounds(displayID), scale: screen.backingScaleFactor
        )
    }

    /// Stable across reboots and reconnects, unlike `CGDirectDisplayID`.
    public static func displayKey(for displayID: CGDirectDisplayID) -> DisplayKey {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) as String?
        else { return DisplayKey("display-\(displayID)") }
        return DisplayKey(text)
    }
}

/// What changed between two screen layouts.
public struct LayoutDiff: Equatable, Sendable {
    public let added: [ScreenDescriptor]
    public let removed: [DisplayKey]
    public let changed: [ScreenDescriptor]

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }

    /// `didChangeScreenParameters` fires often with nothing changed; diffing keeps rebuilds rare.
    public static func between(_ old: [ScreenDescriptor], _ new: [ScreenDescriptor]) -> LayoutDiff {
        let oldByKey = Dictionary(old.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let newKeys = Set(new.map(\.key))
        return LayoutDiff(
            added: new.filter { oldByKey[$0.key] == nil },
            removed: old.map(\.key).filter { !newKeys.contains($0) },
            changed: new.filter { screen in oldByKey[screen.key].map { $0 != screen } ?? false }
        )
    }
}
