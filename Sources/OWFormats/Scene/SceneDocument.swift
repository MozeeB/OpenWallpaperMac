import Foundation
import OWCore

public enum SceneError: Error, Equatable, Sendable {
    case asset(AssetError)
    case missingField(String)
    case tooManyObjects(Int)
    case noRenderableLayers
}

public enum Blending: String, Equatable, Sendable {
    case normal
    case translucent
    case additive
    case disabled

    public init(weName: String?) {
        self = Blending(rawValue: weName?.lowercased() ?? "") ?? .translucent
    }
}

/// Scene-wide settings (`general` block).
public struct SceneGeneral: Equatable, Sendable {
    public let clearColor: Vec3
    public let width: Float
    public let height: Float
    public let cameraParallax: Bool
    public let parallaxAmount: Float
    public let parallaxDelay: Float
    public let parallaxMouseInfluence: Float

    public init(
        clearColor: Vec3 = Vec3(0, 0, 0), width: Float = 1920, height: Float = 1080,
        cameraParallax: Bool = false, parallaxAmount: Float = 0.5, parallaxDelay: Float = 0.1,
        parallaxMouseInfluence: Float = 0.5
    ) {
        self.clearColor = clearColor
        self.width = width
        self.height = height
        self.cameraParallax = cameraParallax
        self.parallaxAmount = parallaxAmount
        self.parallaxDelay = parallaxDelay
        self.parallaxMouseInfluence = parallaxMouseInfluence
    }
}

/// An effect attached to a layer, identified by its folder name (`effects/<name>/effect.json`).
public struct SceneEffect: Equatable, Sendable {
    public let name: String
    public let file: String
    public let visible: SceneValue
    public let constants: [String: SceneValue]

    public init(name: String, file: String, visible: SceneValue = SceneValue([1]), constants: [String: SceneValue] = [:]) {
        self.name = name
        self.file = file
        self.visible = visible
        self.constants = constants
    }
}

/// Transform and visibility shared by every layer type.
public struct LayerTransform: Equatable, Sendable {
    public let origin: Vec3
    public let scale: Vec3
    public let angles: Vec3
    public let parallaxDepth: Vec2

    public init(origin: Vec3 = .zero, scale: Vec3 = .one, angles: Vec3 = .zero, parallaxDepth: Vec2 = .zero) {
        self.origin = origin
        self.scale = scale
        self.angles = angles
        self.parallaxDepth = parallaxDepth
    }
}

public struct SceneImageLayer: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let model: SanitizedPath
    public let transform: LayerTransform
    public let size: Vec2?
    public let visible: SceneValue
    public let alpha: SceneValue
    public let color: SceneValue
    public let effects: [SceneEffect]
}

public struct SceneParticleLayer: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let particle: SanitizedPath
    public let transform: LayerTransform
    public let visible: SceneValue
}

public enum SceneObject: Equatable, Sendable {
    case image(SceneImageLayer)
    case particle(SceneParticleLayer)
    /// Objects this app does not render (sounds, lights, text, 3D models...).
    case unsupported(name: String, kind: String)
}

public struct SceneDocument: Equatable, Sendable {
    public let general: SceneGeneral
    public let objects: [SceneObject]
}

/// `models/*.json`
public struct ModelDocument: Equatable, Sendable {
    public let material: SanitizedPath?
    public let width: Float?
    public let height: Float?
    public let fullscreen: Bool
    public let usesPuppet: Bool
}

/// First pass of `materials/*.json`.
public struct MaterialDocument: Equatable, Sendable {
    public let shader: String
    public let blending: Blending
    /// Texture names as written (`"bg"`, `"_rt_..."`, or empty for unused slots).
    public let textures: [String]

    /// The colour texture path, if it is a real file (`materials/<name>.tex`).
    public var primaryTexturePath: SanitizedPath? {
        guard let name = textures.first, !name.isEmpty, !isRenderTarget(name) else { return nil }
        let withExtension = name.lowercased().hasSuffix(".tex") ? name : name + ".tex"
        let full = withExtension.lowercased().hasPrefix("materials/") ? withExtension : "materials/" + withExtension
        return try? SanitizedPath(full)
    }

    public var usesRenderTarget: Bool { textures.contains(where: isRenderTarget) }

    private func isRenderTarget(_ name: String) -> Bool { name.hasPrefix("_rt_") }
}
