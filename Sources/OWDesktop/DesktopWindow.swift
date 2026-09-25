import AppKit
import OWCore

/// Window placement parameters (configurable because macOS updates have moved the icon level before).
public struct DesktopWindowConfig: Equatable, Sendable {
    /// Offset from the desktop-icon window level; `-1` sits just below Finder's icons.
    public let levelOffset: Int

    public init(levelOffset: Int = -1) {
        let range = AppSettings.windowLevelOffsetRange
        self.levelOffset = min(max(levelOffset, range.lowerBound), range.upperBound)
    }

    public var level: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + levelOffset)
    }

    public static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone,
    ]
}

/// A borderless, click-through window pinned to the desktop layer of one display.
///
/// Opaque with no shadow so WindowServer can composite it cheaply.
public final class DesktopWindow: NSWindow {
    public let displayKey: DisplayKey

    public init(screen: ScreenDescriptor, config: DesktopWindowConfig) {
        displayKey = screen.key
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        apply(config)
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        let host = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        host.autoresizingMask = [.width, .height]
        contentView = host
        setFrame(screen.frame, display: false)
    }

    public func apply(_ config: DesktopWindowConfig) {
        level = config.level
        collectionBehavior = DesktopWindowConfig.collectionBehavior
    }

    public func reframe(to screen: ScreenDescriptor) {
        setFrame(screen.frame, display: true)
    }

    /// Replaces the hosted renderer view.
    public func host(_ view: NSView?) {
        guard let container = contentView else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        guard let view else { return }
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    /// Fades `view` in over the current content, then removes the old content and calls `completion`.
    /// Used when a rotation switches wallpapers so there is never a black frame.
    public func crossfade(to view: NSView, duration: TimeInterval = 0.6, completion: @escaping @MainActor () -> Void) {
        guard let container = contentView else {
            completion()
            return
        }
        let previous = container.subviews
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        view.alphaValue = 0
        container.addSubview(view)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            view.animator().alphaValue = 1
        }, completionHandler: {
            MainActor.assumeIsolated {
                previous.filter { $0 !== view }.forEach { $0.removeFromSuperview() }
                completion()
            }
        })
    }

    public var isVisibleOnScreen: Bool { occlusionState.contains(.visible) }

    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }
}
