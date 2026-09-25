import Foundation
import Testing
@testable import OWCore
@testable import OWFormats

@Suite("Project loading")
struct ProjectTests {
    private func folder(_ files: [(String, String)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("owproj-\(UUID())")
        try SyntheticScene.write(files.map { ($0.0, Data($0.1.utf8)) }, to: url)
        return url
    }

    @Test("loads a Wallpaper Engine web project with properties")
    func weWeb() throws {
        let url = try folder([
            ("index.html", "<html></html>"),
            ("project.json", """
            {"title":"<b>Rain</b>","type":"web","file":"index.html","preview":"preview.gif",
             "general":{"supportsaudioprocessing":true,"properties":{
               "speed":{"type":"slider","text":"Speed","value":5,"min":0,"max":10,"precision":1,"order":2},
               "tint":{"type":"color","text":"Tint","value":"1 0 0","order":1},
               "mode":{"type":"combo","text":"Mode","value":2,"options":[{"label":"A","value":1},{"label":"B","value":2}]},
               "on":{"type":"bool","text":"On","value":"true"},
               "name":{"type":"textinput","text":"Name","value":"x"},
               "label":{"type":"text","text":"Just a label"},
               "file":{"type":"file","text":"Pick"}}}}
            """),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let wallpaper = try ProjectLoader.load(folder: url, id: WallpaperID("x"))
        #expect(wallpaper.title == "Rain")
        #expect(wallpaper.type == .web)
        #expect(wallpaper.origin == .wallpaperEngine)
        #expect(wallpaper.usesAudio)
        #expect(wallpaper.preview?.string == "preview.gif")
        #expect(wallpaper.properties.map(\.key) == ["mode", "name", "on", "tint", "speed"])
        let speed = try #require(wallpaper.properties.first { $0.key == "speed" })
        #expect(speed.kind == .slider(min: 0, max: 10, step: 0.1))
        #expect(wallpaper.defaultValues["mode"] == .string("2"))
        #expect(wallpaper.defaultValues["tint"] == .color(RGBColor(red: 1, green: 0, blue: 0)))
        #expect(wallpaper.defaultValues["on"] == .bool(true))
    }

    @Test("prefers native manifest")
    func native() throws {
        let url = try folder([
            ("a.metal", "//"),
            ("wallpaper.json", #"{"title":"Native","type":"shader","entry":"a.metal","usesAudio":true,"properties":{}}"#),
            ("project.json", #"{"type":"video","file":"missing.mp4"}"#),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let wallpaper = try ProjectLoader.load(folder: url)
        #expect(wallpaper.origin == .native)
        #expect(wallpaper.type == .shader)
        #expect(wallpaper.usesAudio)
    }

    @Test("reports manifest errors", arguments: [
        (#"{"file":"a"}"#, ProjectError.missingField("type")),
        (#"{"type":"application","file":"a"}"#, .unsupportedType("application")),
        (#"{"type":"video"}"#, .missingField("file")),
        (#"{"type":"video","file":"../a.mp4"}"#, .invalidPath("../a.mp4")),
        (#"{"type":"video","file":"gone.mp4"}"#, .entryNotFound("gone.mp4")),
    ])
    func errors(json: String, expected: ProjectError) throws {
        let url = try folder([("project.json", json)])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: expected) { try ProjectLoader.load(folder: url) }
    }

    @Test("missing and invalid manifests")
    func missing() throws {
        let empty = try folder([])
        #expect(throws: ProjectError.noManifest) { try ProjectLoader.load(folder: empty) }
        let bad = try folder([("project.json", "[1,2]")])
        #expect(throws: ProjectError.invalidJSON(.notAnObject)) { try ProjectLoader.load(folder: bad) }
    }

    @Test("scene entry may live inside scene.pkg")
    func packagedScene() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("owscene-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        try SyntheticScene.write(SyntheticScene.projectFiles(), to: url)
        let wallpaper = try ProjectLoader.load(folder: url)
        #expect(wallpaper.type == .scene)
        #expect(wallpaper.properties.count == 2)
    }

    @Test("property parser edge cases")
    func propertyEdges() {
        #expect(PropertyParser.definition(key: "", ["type": "bool"]) == nil)
        #expect(PropertyParser.definition(key: "s", ["type": "slider", "min": 5, "max": 1]) == nil)
        #expect(PropertyParser.definition(key: "c", ["type": "combo", "options": []]) == nil)
        let slider = PropertyParser.definition(key: "s", ["type": "slider", "min": "0", "max": "2", "value": 9])
        #expect(slider?.defaultValue == .number(2))
        #expect(slider?.kind == .slider(min: 0, max: 2, step: 0.02))
        let stepped = PropertyParser.definition(key: "s", ["type": "slider", "step": 0.5])
        #expect(stepped?.kind == .slider(min: 0, max: 100, step: 0.5))
        #expect(PropertyParser.cleanLabel("  <i></i> ") == nil)
        #expect(PropertyParser.stringValue(1.5) == "1.5")
        #expect(PropertyParser.stringValue([1]) == nil)
        #expect(PropertyParser.number(true as Any?) == 1)
        #expect(PropertyParser.boolValue(nil) == false)
    }
}
