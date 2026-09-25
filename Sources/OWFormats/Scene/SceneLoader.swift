import Foundation
import OWCore

public struct LoadedImageLayer: Equatable, Sendable {
    public let layer: SceneImageLayer
    public let model: ModelDocument
    public let material: MaterialDocument?
    public let texture: SanitizedPath?
}

public struct LoadedParticleLayer: Equatable, Sendable {
    public let layer: SceneParticleLayer
    public let system: ParticleSystemDocument
    public let material: MaterialDocument?
    public let texture: SanitizedPath?
}

public enum LoadedLayer: Equatable, Sendable {
    case image(LoadedImageLayer)
    case particle(LoadedParticleLayer)
}

/// A scene with every referenced model/material/particle document resolved, in draw order.
public struct LoadedScene: Equatable, Sendable {
    public let general: SceneGeneral
    public let layers: [LoadedLayer]
    /// Human-readable notes about objects or references that could not be loaded.
    public let skipped: [String]
}

/// Resolves a scene's documents from an `AssetSource` (package and/or folder).
public enum SceneLoader {
    public static func load(entry: SanitizedPath, from assets: any AssetSource) throws(SceneError) -> LoadedScene {
        let json: [String: Any]
        do {
            json = try assets.json(at: entry)
        } catch {
            throw .asset(error)
        }
        let document = try SceneParser.parseScene(json)
        var skipped: [String] = []
        var layers: [LoadedLayer] = []
        for object in document.objects {
            switch object {
            case .image(let layer):
                switch loadImage(layer, assets: assets) {
                case .success(let loaded): layers.append(.image(loaded))
                case .failure(let note): skipped.append(note.message)
                }
            case .particle(let layer):
                switch loadParticle(layer, assets: assets) {
                case .success(let loaded): layers.append(.particle(loaded))
                case .failure(let note): skipped.append(note.message)
                }
            case let .unsupported(name, kind):
                skipped.append("\(kind) object '\(name)'")
            }
        }
        return LoadedScene(general: document.general, layers: layers, skipped: skipped)
    }

    struct Note: Error {
        let message: String
    }

    static func loadImage(_ layer: SceneImageLayer, assets: any AssetSource) -> Result<LoadedImageLayer, Note> {
        guard let modelJSON = try? assets.json(at: layer.model) else {
            return .failure(Note(message: "image '\(layer.name)': missing model \(layer.model)"))
        }
        let model = SceneParser.parseModel(modelJSON)
        let material = model.material.flatMap { try? assets.json(at: $0) }.map(SceneParser.parseMaterial)
        let texture = material?.primaryTexturePath.flatMap { assets.exists($0) ? $0 : nil }
        return .success(LoadedImageLayer(layer: layer, model: model, material: material, texture: texture))
    }

    static func loadParticle(_ layer: SceneParticleLayer, assets: any AssetSource) -> Result<LoadedParticleLayer, Note> {
        guard let json = try? assets.json(at: layer.particle) else {
            return .failure(Note(message: "particle '\(layer.name)': missing \(layer.particle)"))
        }
        let system = ParticleParser.parse(json)
        let material = system.material.flatMap { try? assets.json(at: $0) }.map(SceneParser.parseMaterial)
        let texture = material?.primaryTexturePath.flatMap { assets.exists($0) ? $0 : nil }
        return .success(LoadedParticleLayer(layer: layer, system: system, material: material, texture: texture))
    }
}
