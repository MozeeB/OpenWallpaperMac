import Foundation
import OWCore

/// What a scene needs that this app cannot (yet) render.
public struct SupportReport: Equatable, Sendable {
    public let level: SupportLevel
    public let unsupported: [String]
    public let renderableLayers: Int

    public init(level: SupportLevel, unsupported: [String], renderableLayers: Int) {
        self.level = level
        self.unsupported = unsupported
        self.renderableLayers = renderableLayers
    }
}

public enum SceneSupportAnalyzer {
    /// Object kinds that are ignored without reducing visual fidelity.
    static let silentKinds = ["sound object", "camera object"]

    public static func analyze(_ scene: LoadedScene, knownEffects: Set<String>) -> SupportReport {
        var notes = scene.skipped.filter { note in !silentKinds.contains { note.hasPrefix($0) } }
        var renderable = 0
        for layer in scene.layers {
            switch layer {
            case .image(let image):
                notes += imageNotes(image, knownEffects: knownEffects)
                if image.texture != nil || image.model.fullscreen { renderable += 1 }
            case .particle(let particle):
                notes += particle.system.unsupported.map { "particle '\(particle.layer.name)': \($0)" }
                if particle.system.emitters.isEmpty {
                    notes.append("particle '\(particle.layer.name)': no supported emitter")
                } else {
                    renderable += 1
                }
            }
        }
        let level: SupportLevel = renderable == 0 ? .previewOnly : (notes.isEmpty ? .full : .partial)
        return SupportReport(level: level, unsupported: notes, renderableLayers: renderable)
    }

    static func imageNotes(_ image: LoadedImageLayer, knownEffects: Set<String>) -> [String] {
        let name = image.layer.name
        var notes: [String] = []
        if image.model.usesPuppet { notes.append("image '\(name)': puppet warp animation") }
        if image.material?.usesRenderTarget == true { notes.append("image '\(name)': render-target texture") }
        if image.texture == nil && !image.model.fullscreen { notes.append("image '\(name)': texture missing") }
        for effect in image.layer.effects where !knownEffects.contains(effect.name) {
            notes.append("image '\(name)': effect '\(effect.name)'")
        }
        return notes
    }
}
