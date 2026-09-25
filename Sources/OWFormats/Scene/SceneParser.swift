import Foundation
import OWCore

/// Parses `scene.json`, `models/*.json` and `materials/*.json`. Unknown keys are ignored.
public enum SceneParser {
    public static func parseScene(_ json: [String: Any]) throws(SceneError) -> SceneDocument {
        let general = parseGeneral(json["general"] as? [String: Any] ?? [:])
        let rawObjects = json["objects"] as? [[String: Any]] ?? []
        guard rawObjects.count <= Limits.maxSceneObjects else { throw .tooManyObjects(rawObjects.count) }
        return SceneDocument(general: general, objects: rawObjects.enumerated().map { parseObject($1, index: $0) })
    }

    static func parseGeneral(_ raw: [String: Any]) -> SceneGeneral {
        let projection = raw["orthogonalprojection"] as? [String: Any] ?? [:]
        let width = SceneValues.float(projection["width"], default: 1920)
        let height = SceneValues.float(projection["height"], default: 1080)
        return SceneGeneral(
            clearColor: SceneValues.vec3(raw["clearcolor"], default: Vec3(0, 0, 0)),
            width: width > 0 && width <= 16_384 ? width : 1920,
            height: height > 0 && height <= 16_384 ? height : 1080,
            cameraParallax: SceneValues.bool(raw["cameraparallax"], default: false),
            parallaxAmount: SceneValues.float(raw["cameraparallaxamount"], default: 0.5),
            parallaxDelay: SceneValues.float(raw["cameraparallaxdelay"], default: 0.1),
            parallaxMouseInfluence: SceneValues.float(raw["cameraparallaxmouseinfluence"], default: 0.5)
        )
    }

    static func parseObject(_ raw: [String: Any], index: Int) -> SceneObject {
        let id = (raw["id"] as? NSNumber)?.intValue ?? index
        let name = raw["name"] as? String ?? "object \(id)"
        let transform = parseTransform(raw)
        let visible = SceneValues.value(raw["visible"]) ?? SceneValue([1])
        if let model = SceneValues.path(raw["image"]) {
            return .image(SceneImageLayer(
                id: id, name: name, model: model, transform: transform,
                size: (SceneValues.value(raw["size"])?.fallback).flatMap(SceneValues.vec2),
                visible: visible,
                alpha: SceneValues.value(raw["alpha"]) ?? SceneValue([1]),
                color: SceneValues.value(raw["color"]) ?? SceneValue([1, 1, 1]),
                effects: (raw["effects"] as? [[String: Any]] ?? []).compactMap(parseEffect)
            ))
        }
        if let particle = SceneValues.path(raw["particle"]) {
            return .particle(SceneParticleLayer(
                id: id, name: name, particle: particle, transform: transform, visible: visible
            ))
        }
        return .unsupported(name: name, kind: objectKind(raw))
    }

    static func parseTransform(_ raw: [String: Any]) -> LayerTransform {
        LayerTransform(
            origin: SceneValues.vec3(raw["origin"], default: .zero),
            scale: SceneValues.vec3(raw["scale"], default: .one),
            angles: SceneValues.vec3(raw["angles"], default: .zero),
            parallaxDepth: SceneValues.vec2(raw["parallaxDepth"], default: .zero)
        )
    }

    private static func objectKind(_ raw: [String: Any]) -> String {
        for kind in ["sound", "light", "text", "model", "camera"] where raw[kind] != nil {
            return kind
        }
        return "unknown"
    }

    static func parseEffect(_ raw: [String: Any]) -> SceneEffect? {
        guard let file = raw["file"] as? String, !file.isEmpty else { return nil }
        let components = file.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        let name = components.count >= 2 ? components[components.count - 2] : file
        let pass = (raw["passes"] as? [[String: Any]])?.first ?? [:]
        let constantsRaw = pass["constantshadervalues"] as? [String: Any] ?? [:]
        let constants = constantsRaw.reduce(into: [String: SceneValue]()) { result, item in
            if let value = SceneValues.value(item.value) { result[item.key.lowercased()] = value }
        }
        return SceneEffect(
            name: name.lowercased(), file: file,
            visible: SceneValues.value(raw["visible"]) ?? SceneValue([1]), constants: constants
        )
    }

    public static func parseModel(_ json: [String: Any]) -> ModelDocument {
        ModelDocument(
            material: SceneValues.path(json["material"]),
            width: (json["width"] as? NSNumber)?.floatValue,
            height: (json["height"] as? NSNumber)?.floatValue,
            fullscreen: SceneValues.bool(json["fullscreen"], default: false),
            usesPuppet: json["puppet"] != nil
        )
    }

    public static func parseMaterial(_ json: [String: Any]) -> MaterialDocument {
        let pass = (json["passes"] as? [[String: Any]])?.first ?? [:]
        let textures = (pass["textures"] as? [Any] ?? []).map { ($0 as? String) ?? "" }
        return MaterialDocument(
            shader: pass["shader"] as? String ?? "genericimage2",
            blending: Blending(weName: pass["blending"] as? String),
            textures: textures
        )
    }
}
