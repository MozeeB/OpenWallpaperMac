import Foundation
import Testing
@testable import OWCore
@testable import OWFormats

@Suite("Scene parsing")
struct SceneParsingTests {
    @Test("scene values accept literals and user bindings")
    func values() throws {
        #expect(SceneValues.value(2)?.fallback == [2])
        #expect(SceneValues.value("1 2 3")?.fallback == [1, 2, 3])
        #expect(SceneValues.value("")?.fallback == nil)
        let bound = try #require(SceneValues.value(["user": ["name": "speed"], "value": "0.5"]))
        #expect(bound.userKey == "speed")
        #expect(bound.resolve([:]) == [0.5])
        #expect(bound.resolve(["speed": .number(2)]) == [2])
        #expect(bound.resolve(["speed": .bool(true)]) == [1])
        #expect(bound.resolve(["speed": .string("nope")]) == [0.5])
        #expect(bound.resolve(["speed": .color(.white)]) == [1, 1, 1])
        #expect(bound.bool(["speed": .number(0)]) == false)
        #expect(SceneValue([]).scalar([:], default: 7) == 7)
        #expect(SceneValue([4]).vec3([:], default: .zero) == Vec3(4, 4, 4))
        #expect(SceneValues.vec3([1, 2]) == Vec3(1, 2, 0))
        #expect(SceneValues.vec2([3]) == Vec2(3, 3))
        #expect(SceneValues.vec2([]) == nil)
        #expect(SceneValues.bool(false as Any?, default: true) == false)
        #expect(SceneValues.floats("1 nan inf 2") == [1, 2])
        #expect(Blending(weName: "ADDITIVE") == .additive)
        #expect(Blending(weName: nil) == .translucent)
    }

    @Test("parses objects, effects and unsupported kinds")
    func objects() throws {
        let json: [String: Any] = [
            "general": ["orthogonalprojection": ["width": -5, "height": 720], "clearcolor": "1 0 0"],
            "objects": [
                ["id": 3, "name": "img", "image": "models/a.json", "origin": "10 20 0",
                 "effects": [["file": "effects\\waterripple\\effect.json",
                              "passes": [["constantshadervalues": ["Speed": 2, "bad": [1]]]]], ["nofile": 1]]],
                ["name": "fx", "particle": "particles/p.json"],
                ["name": "snd", "sound": ["a.mp3"]],
                ["name": "?"],
            ],
        ]
        let document = try SceneParser.parseScene(json)
        #expect(document.general.width == 1920)
        #expect(document.general.height == 720)
        #expect(document.general.clearColor == Vec3(1, 0, 0))
        guard case .image(let image) = document.objects[0] else { Issue.record("expected image"); return }
        #expect(image.id == 3)
        #expect(image.transform.origin == Vec3(10, 20, 0))
        #expect(image.effects.count == 1)
        #expect(image.effects[0].name == "waterripple")
        #expect(image.effects[0].constants["speed"]?.fallback == [2])
        guard case .particle(let particle) = document.objects[1] else { Issue.record("expected particle"); return }
        #expect(particle.id == 1)
        #expect(document.objects[2] == .unsupported(name: "snd", kind: "sound"))
        #expect(document.objects[3] == .unsupported(name: "?", kind: "unknown"))
    }

    @Test("rejects scenes with too many objects")
    func tooMany() {
        let objects = Array(repeating: [String: Any](), count: Limits.maxSceneObjects + 1)
        #expect(throws: SceneError.tooManyObjects(Limits.maxSceneObjects + 1)) {
            try SceneParser.parseScene(["objects": objects])
        }
    }

    @Test("material texture paths")
    func materials() {
        let material = SceneParser.parseMaterial(["passes": [["textures": ["bg", NSNull()], "blending": "additive"]]])
        #expect(material.primaryTexturePath?.string == "materials/bg.tex")
        #expect(material.blending == .additive)
        let rt = SceneParser.parseMaterial(["passes": [["textures": ["_rt_FullFrameBuffer"]]]])
        #expect(rt.primaryTexturePath == nil)
        #expect(rt.usesRenderTarget)
        let explicit = SceneParser.parseMaterial(["passes": [["textures": ["materials/x.tex"]]]])
        #expect(explicit.primaryTexturePath?.string == "materials/x.tex")
        #expect(SceneParser.parseMaterial([:]).primaryTexturePath == nil)
        let model = SceneParser.parseModel(["material": "materials/a.json", "puppet": "p.mdl", "width": 10, "fullscreen": true])
        #expect(model.usesPuppet && model.fullscreen && model.width == 10)
    }

    @Test("particle documents")
    func particles() {
        let system = ParticleParser.parse([
            "maxcount": 999_999,
            "emitter": [["name": "sphererandom", "rate": -3, "speedmin": 5, "speedmax": 1], ["name": "weird"]],
            "initializer": [
                ["name": "colorrandom", "min": "0 0 0", "max": "0.5 0.5 0.5"],
                ["name": "rotationrandom", "min": 0, "max": 3],
                ["name": "angularvelocityrandom", "max": 1],
                ["name": "alpharandom", "min": 0.2, "max": 0.8],
                ["name": "turbulentvelocityrandom"],
            ],
            "operator": [["name": "sizechange", "startvalue": 2, "endvalue": 0], ["name": "oscillate"]],
        ])
        #expect(system.maxCount == Limits.maxParticles)
        #expect(system.emitters.count == 1)
        #expect(system.emitters[0].shape == .sphere)
        #expect(system.emitters[0].rate == 0)
        #expect(system.emitters[0].speed == FloatRange(1, 5))
        #expect(system.initializer.colorMax == Vec3(0.5, 0.5, 0.5))
        #expect(system.operators.sizeStart == 2)
        #expect(system.unsupported == ["emitter:weird", "initializer:turbulentvelocityrandom", "operator:oscillate"])
    }
}

@Suite("Scene loading & support")
struct SceneLoadingTests {
    static let known: Set<String> = ["shake", "waterripple"]

    private func load(_ options: SyntheticScene.Options) throws -> LoadedScene {
        let archive = try PKGParser.parse(PKGWriter.build(files: SyntheticScene.sceneContents(options: options)))
        return try SceneLoader.load(entry: try SanitizedPath("scene.json"), from: PKGAssetSource(archive: archive))
    }

    @Test("synthetic scene is fully supported")
    func full() throws {
        let scene = try load(SyntheticScene.Options())
        #expect(scene.layers.count == 2)
        #expect(scene.general.cameraParallax)
        let report = SceneSupportAnalyzer.analyze(scene, knownEffects: Self.known)
        #expect(report.level == .full)
        #expect(report.renderableLayers == 2)
    }

    @Test("unknown effects, puppets and text make support partial")
    func partial() throws {
        var options = SyntheticScene.Options()
        options.effects = ["shake", "godrays"]
        options.includeUnsupported = true
        let report = SceneSupportAnalyzer.analyze(try load(options), knownEffects: Self.known)
        #expect(report.level == .partial)
        #expect(report.unsupported.contains("image 'background': effect 'godrays'"))
        #expect(report.unsupported.contains("image 'puppet': puppet warp animation"))
        #expect(report.unsupported.contains("text object 'label'"))
    }

    @Test("missing references are skipped; nothing renderable means preview only")
    func missing() throws {
        let files: [(String, Data)] = [
            ("scene.json", Data(#"{"objects":[{"name":"a","image":"models/none.json"},{"name":"p","particle":"particles/none.json"},{"name":"s","sound":["x"]}]}"#.utf8)),
        ]
        let archive = try PKGParser.parse(PKGWriter.build(files: files))
        let scene = try SceneLoader.load(entry: try SanitizedPath("scene.json"), from: PKGAssetSource(archive: archive))
        #expect(scene.layers.isEmpty)
        #expect(scene.skipped.count == 3)
        let report = SceneSupportAnalyzer.analyze(scene, knownEffects: [])
        #expect(report.level == .previewOnly)
        #expect(!report.unsupported.contains { $0.hasPrefix("sound") })
        #expect(throws: SceneError.self) {
            try SceneLoader.load(entry: try SanitizedPath("nope.json"), from: PKGAssetSource(archive: archive))
        }
    }
}
