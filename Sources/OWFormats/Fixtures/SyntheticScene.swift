import Foundation

/// Generates original, license-clean Wallpaper Engine–style scene projects.
///
/// Used by tests, `owctl make-sample` and the bundled samples so no third-party
/// Workshop content ever needs to live in the repository.
public enum SyntheticScene {
    public struct Options: Sendable {
        public var width = 64
        public var height = 36
        public var effects: [String] = ["shake"]
        public var includeParticles = true
        public var includeUnsupported = false
        public var packaged = true

        public init() {}
    }

    /// Files of a complete project folder: `project.json`, and either `scene.pkg` or loose files.
    public static func projectFiles(options: Options = Options()) -> [(String, Data)] {
        let sceneFiles = sceneContents(options: options)
        let project = json([
            "title": "Synthetic Scene",
            "type": "scene",
            "file": "scene.json",
            "general": ["properties": [
                "bgalpha": ["type": "slider", "text": "Background alpha", "value": 1.0, "min": 0, "max": 1, "order": 0],
                "showdots": ["type": "bool", "text": "Show particles", "value": true, "order": 1],
            ]],
        ])
        if options.packaged {
            return [("project.json", project), ("scene.pkg", PKGWriter.build(files: sceneFiles))]
        }
        return [("project.json", project)] + sceneFiles
    }

    /// The scene's own files (what goes inside `scene.pkg`).
    public static func sceneContents(options: Options = Options()) -> [(String, Data)] {
        var objects: [[String: Any]] = [imageObject(options: options)]
        var files: [(String, Data)] = [
            ("models/bg.json", json(["material": "materials/bg.json"])),
            ("materials/bg.json", json(["passes": [["shader": "genericimage2", "blending": "translucent", "textures": ["bg"]]]])),
            ("materials/bg.tex", gradientTexture(width: options.width, height: options.height)),
        ]
        if options.includeParticles {
            objects.append(particleObject())
            files += particleFiles()
        }
        if options.includeUnsupported {
            objects.append(["id": 9, "name": "puppet", "image": "models/puppet.json"])
            files.append(("models/puppet.json", json(["material": "materials/bg.json", "puppet": "models/puppet.mdl"])))
            objects.append(["id": 10, "name": "label", "text": ["value": "hi"]])
        }
        let scene = json([
            "general": [
                "clearcolor": "0.1 0.1 0.15",
                "orthogonalprojection": ["width": options.width, "height": options.height],
                "cameraparallax": true,
                "cameraparallaxamount": 0.5,
            ],
            "objects": objects,
        ])
        return [("scene.json", scene)] + files
    }

    private static func imageObject(options: Options) -> [String: Any] {
        [
            "id": 1, "name": "background", "image": "models/bg.json",
            "origin": "\(options.width / 2) \(options.height / 2) 0",
            "scale": "1 1 1", "angles": "0 0 0", "size": "\(options.width) \(options.height)",
            "alpha": ["user": "bgalpha", "value": 1.0],
            "color": "1 1 1",
            "parallaxDepth": "0.5 0.5",
            "effects": options.effects.map { name in
                ["file": "effects/\(name)/effect.json", "visible": true,
                 "passes": [["constantshadervalues": ["speed": 1.0, "strength": 0.05]]]]
            },
        ]
    }

    private static func particleObject() -> [String: Any] {
        ["id": 2, "name": "dots", "particle": "particles/dots.json", "origin": "32 18 0",
         "visible": ["user": "showdots", "value": true]]
    }

    private static func particleFiles() -> [(String, Data)] {
        let system = json([
            "maxcount": 64,
            "material": "materials/dot.json",
            "emitter": [["name": "boxrandom", "rate": 20, "distancemax": "32 18 0", "origin": "0 0 0"]],
            "initializer": [
                ["name": "lifetimerandom", "min": 1, "max": 2],
                ["name": "sizerandom", "min": 2, "max": 4],
                ["name": "velocityrandom", "min": "-5 5 0", "max": "5 15 0"],
                ["name": "colorrandom", "min": "200 200 255", "max": "255 255 255"],
            ],
            "operator": [
                ["name": "movement", "gravity": "0 -2 0"],
                ["name": "alphafade", "fadeintime": 0.1, "fadeouttime": 0.5],
            ],
        ])
        let material = json(["passes": [["shader": "genericparticle", "blending": "additive", "textures": ["dot"]]]])
        return [
            ("particles/dots.json", system),
            ("materials/dot.json", material),
            ("materials/dot.tex", solidTexture(width: 4, height: 4, rgba: [255, 255, 255, 255])),
        ]
    }

    public static func gradientTexture(width: Int, height: Int) -> Data {
        var pixels = Data(capacity: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                pixels.append(contentsOf: [
                    UInt8(x * 255 / max(width - 1, 1)), UInt8(y * 255 / max(height - 1, 1)), 128, 255,
                ])
            }
        }
        return TEXWriter.build(format: .rgba8888, width: width, height: height, pixels: pixels)
    }

    public static func solidTexture(width: Int, height: Int, rgba: [UInt8]) -> Data {
        let pixels = Data((0 ..< width * height).flatMap { _ in rgba })
        return TEXWriter.build(format: .rgba8888, width: width, height: height, pixels: pixels)
    }

    /// Writes `files` into `folder`, creating intermediate directories.
    public static func write(_ files: [(String, Data)], to folder: URL) throws {
        for (name, data) in files {
            let url = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }

    static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}
