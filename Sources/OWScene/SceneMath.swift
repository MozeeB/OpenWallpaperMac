import CoreGraphics
import Foundation
import OWCore
import OWFormats
import simd

public enum SceneMath {
    /// Orthographic projection mapping x∈[left,right], y∈[bottom,top] to clip space.
    public static func ortho(left: Float, right: Float, bottom: Float, top: Float) -> simd_float4x4 {
        let width = right - left
        let height = top - bottom
        return simd_float4x4(columns: (
            SIMD4(2 / width, 0, 0, 0),
            SIMD4(0, 2 / height, 0, 0),
            SIMD4(0, 0, -1, 0),
            SIMD4(-(right + left) / width, -(top + bottom) / height, 0, 1)
        ))
    }

    public static func translation(_ x: Float, _ y: Float) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(x, y, 0, 1)
        return matrix
    }

    public static func scale(_ x: Float, _ y: Float) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(x, y, 1, 1))
    }

    /// Rotation around Z; Wallpaper Engine angles are radians.
    public static func rotationZ(_ radians: Float) -> simd_float4x4 {
        let c = cos(radians)
        let s = sin(radians)
        return simd_float4x4(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
    }

    public static func model(origin: SIMD2<Float>, size: SIMD2<Float>, scale s: SIMD2<Float>, angle: Float) -> simd_float4x4 {
        translation(origin.x, origin.y) * rotationZ(angle) * scale(size.x * s.x, size.y * s.y)
    }
}

/// Maps scene space (origin bottom-left, y up, `width`×`height` units) onto a viewport.
///
/// `fill` crops to cover the viewport, `fit` letterboxes, `stretch` distorts. Parallax shifts each
/// layer by `(cursor - 0.5) × amount × depth × sceneSize`, eased with the scene's delay.
public struct SceneCamera: Equatable, Sendable {
    public let sceneSize: SIMD2<Float>
    public let fill: FillMode
    public let parallaxEnabled: Bool
    public let parallaxAmount: Float
    public let parallaxDelay: Float
    public private(set) var cursor = SIMD2<Float>(0.5, 0.5)

    public init(general: SceneGeneral, fill: FillMode) {
        sceneSize = SIMD2(general.width, general.height)
        self.fill = fill
        parallaxEnabled = general.cameraParallax
        parallaxAmount = general.parallaxAmount * general.parallaxMouseInfluence * 2
        parallaxDelay = max(general.parallaxDelay, 0)
    }

    /// Visible scene rectangle (min, max) for a viewport aspect ratio.
    public func visibleRect(viewport: CGSize) -> (SIMD2<Float>, SIMD2<Float>) {
        guard viewport.width > 0, viewport.height > 0, fill != .stretch else { return (.zero, sceneSize) }
        let viewAspect = Float(viewport.width / viewport.height)
        let sceneAspect = sceneSize.x / sceneSize.y
        let coverWidth = (fill == .fill) == (viewAspect > sceneAspect)
        var extent = sceneSize
        if coverWidth {
            extent.y = sceneSize.x / viewAspect
        } else {
            extent.x = sceneSize.y * viewAspect
        }
        let center = sceneSize / 2
        return (center - extent / 2, center + extent / 2)
    }

    public func projection(viewport: CGSize) -> simd_float4x4 {
        let (low, high) = visibleRect(viewport: viewport)
        return SceneMath.ortho(left: low.x, right: high.x, bottom: low.y, top: high.y)
    }

    /// Eases the cursor (0…1, y up) toward `target`.
    public mutating func updateCursor(target: SIMD2<Float>, delta: Float) {
        guard parallaxEnabled else { return }
        let clamped = simd_clamp(target, SIMD2(0, 0), SIMD2(1, 1))
        let factor: Float = parallaxDelay <= 0 ? 1 : 1 - exp(-max(delta, 0) / parallaxDelay)
        cursor += (clamped - cursor) * factor
    }

    public func parallaxOffset(depth: Vec2) -> SIMD2<Float> {
        guard parallaxEnabled else { return .zero }
        let centered = cursor - SIMD2(0.5, 0.5)
        return centered * parallaxAmount * SIMD2(depth.x, depth.y) * sceneSize * 0.05
    }
}
