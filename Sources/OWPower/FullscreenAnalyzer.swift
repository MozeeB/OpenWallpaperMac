import CoreGraphics
import Foundation
import OWCore

/// A normal on-screen window, as reported by `CGWindowListCopyWindowInfo`.
public struct WindowInfo: Equatable, Sendable {
    public let ownerPID: Int32
    public let layer: Int
    public let bounds: CGRect
    public let alpha: Double

    public init(ownerPID: Int32, layer: Int, bounds: CGRect, alpha: Double = 1) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
        self.alpha = alpha
    }

    /// Parses one dictionary from `CGWindowListCopyWindowInfo`.
    public init?(dictionary: [String: Any]) {
        guard
            let pid = dictionary[kCGWindowOwnerPID as String] as? Int32,
            let layer = dictionary[kCGWindowLayer as String] as? Int,
            let boundsDict = dictionary[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict)
        else { return nil }
        let alpha = dictionary[kCGWindowAlpha as String] as? Double ?? 1
        self.init(ownerPID: pid, layer: layer, bounds: bounds, alpha: alpha)
    }
}

/// Decides which displays are covered by another app's window (fullscreen or maximised).
///
/// A display counts as covered when a single opaque, normal-layer window from another process
/// covers at least `coverageThreshold` of its area. The threshold tolerates the menu bar and the
/// notch, which a pure size comparison does not.
public struct FullscreenAnalyzer: Sendable {
    public let ownPID: Int32
    public let coverageThreshold: Double

    public init(ownPID: Int32, coverageThreshold: Double = 0.95) {
        self.ownPID = ownPID
        self.coverageThreshold = min(max(coverageThreshold, 0.5), 1)
    }

    public func coveredDisplays(windows: [WindowInfo], displays: [DisplayKey: CGRect]) -> Set<DisplayKey> {
        let candidates = windows.filter { $0.layer == 0 && $0.ownerPID != ownPID && $0.alpha > 0.5 }
        return Set(displays.compactMap { key, bounds in
            candidates.contains { coverage(of: bounds, by: $0.bounds) >= coverageThreshold } ? key : nil
        })
    }

    func coverage(of display: CGRect, by window: CGRect) -> Double {
        let area = display.width * display.height
        guard area > 0 else { return 0 }
        let overlap = display.intersection(window)
        guard !overlap.isNull else { return 0 }
        return (overlap.width * overlap.height) / area
    }
}
