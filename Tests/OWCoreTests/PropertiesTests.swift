import Foundation
import Testing
@testable import OWCore

@Suite("Properties")
struct PropertiesTests {
    @Test("RGBColor parses 0...1 and 0...255 strings")
    func colorParsing() throws {
        let unit = try #require(RGBColor(weString: "0.5 0.25 1"))
        #expect(unit == RGBColor(red: 0.5, green: 0.25, blue: 1))
        let bytes = try #require(RGBColor(weString: "255,0,51"))
        #expect(abs(bytes.blue - 0.2) < 0.0001)
        #expect(RGBColor(weString: "1 2") == nil)
        #expect(RGBColor(red: 2, green: -1, blue: .nan) == RGBColor(red: 1, green: 0, blue: 0))
        #expect(RGBColor(red: 1, green: 0.5, blue: 0).weString == "1 0.5 0")
    }

    @Test("PropertyValue conversions")
    func conversions() {
        #expect(PropertyValue.bool(true).doubleValue == 1)
        #expect(PropertyValue.string("2.5").doubleValue == 2.5)
        #expect(PropertyValue.color(.white).doubleValue == nil)
        #expect(PropertyValue.number(0).boolValue == false)
        #expect(PropertyValue.string("TRUE").boolValue == true)
        #expect(PropertyValue.color(.white).boolValue == nil)
    }

    @Test("validation clamps and coerces")
    func validation() {
        let slider = PropertyDefinition(
            key: "speed", label: "Speed", order: 0,
            kind: .slider(min: 0, max: 10, step: 1), defaultValue: .number(5)
        )
        #expect(slider.validated(.number(50)) == .number(10))
        #expect(slider.validated(.number(.infinity)) == nil)
        #expect(slider.validated(.color(.white)) == nil)

        let combo = PropertyDefinition(
            key: "mode", label: "Mode", order: 1,
            kind: .combo([ComboOption(label: "One", value: "1"), ComboOption(label: "Two", value: "two")]),
            defaultValue: .string("1")
        )
        #expect(combo.validated(.number(1)) == .string("1"))
        #expect(combo.validated(.string("two")) == .string("two"))
        #expect(combo.validated(.string("three")) == nil)

        let color = PropertyDefinition(key: "c", label: "C", order: 2, kind: .color, defaultValue: .color(.black))
        #expect(color.validated(.string("1 1 1")) == .color(.white))
        #expect(color.validated(.number(1)) == nil)

        let flag = PropertyDefinition(key: "f", label: "F", order: 3, kind: .bool, defaultValue: .bool(false))
        #expect(flag.validated(.number(1)) == .bool(true))

        let text = PropertyDefinition(key: "t", label: "T", order: 4, kind: .text, defaultValue: .string(""))
        #expect(text.validated(.string("hi")) == .string("hi"))
        #expect(text.validated(.bool(true)) == nil)
    }

    @Test("resolve merges overrides over defaults")
    func resolve() {
        let definitions = [
            PropertyDefinition(key: "a", label: "A", order: 0, kind: .bool, defaultValue: .bool(false)),
            PropertyDefinition(
                key: "b", label: "B", order: 1,
                kind: .slider(min: 0, max: 1, step: 0.1), defaultValue: .number(0.5)
            ),
        ]
        let resolved = definitions.resolve(["a": .bool(true), "b": .color(.white), "zzz": .number(1)])
        #expect(resolved == ["a": .bool(true), "b": .number(0.5)])
    }

    @Test("AudioSpectrum normalises to 64 clamped bands")
    func spectrum() {
        let spectrum = AudioSpectrum(left: [2, -1, .nan], right: Array(repeating: 0.5, count: 100))
        #expect(spectrum.left.count == 64)
        #expect(spectrum.left.prefix(3) == [1, 0, 0])
        #expect(spectrum.right.count == 64)
        #expect(spectrum.average[0] == 0.75)
        #expect(spectrum.weArray.count == 128)
        #expect(AudioSpectrum.silent.left.allSatisfy { $0 == 0 })
    }
}
