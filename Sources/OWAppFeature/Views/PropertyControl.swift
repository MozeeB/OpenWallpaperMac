import AppKit
import OWCore
import SwiftUI

/// One editor row for a user property. Values are validated by `PropertyDefinition` downstream.
struct PropertyControl: View {
    let definition: PropertyDefinition
    let value: PropertyValue
    let onChange: (PropertyValue) -> Void

    var body: some View {
        switch definition.kind {
        case .bool:
            Toggle(definition.label, isOn: Binding(get: { value.boolValue ?? false }, set: { onChange(.bool($0)) }))
        case let .slider(lower, upper, step):
            LabeledContent(definition.label) {
                HStack {
                    Slider(value: Binding(get: { value.doubleValue ?? lower }, set: { onChange(.number($0)) }),
                           in: lower ... max(upper, lower + step), step: step)
                    Text(format(value.doubleValue ?? lower, step: step)).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
            .accessibilityIdentifier("property.\(definition.key)")
        case .color:
            ColorPicker(definition.label, selection: Binding(get: { color }, set: { onChange(.color(ColorConversion.rgb($0))) }),
                        supportsOpacity: false)
        case .combo(let options):
            Picker(definition.label, selection: Binding(get: { comboValue }, set: { onChange(.string($0)) })) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
        case .text:
            TextField(definition.label, text: Binding(get: { comboValue }, set: { onChange(.string(String($0.prefix(4096)))) }))
        }
    }

    private var color: Color {
        guard case .color(let rgb) = value else { return .white }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private var comboValue: String {
        if case .string(let text) = value { return text }
        return ""
    }

    private func format(_ number: Double, step: Double) -> String {
        let decimals = step >= 1 ? 0 : min(Int((-log10(step)).rounded(.up)), 4)
        return String(format: "%.\(decimals)f", number)
    }
}

enum ColorConversion {
    static func rgb(_ color: Color) -> OWCore.RGBColor {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return OWCore.RGBColor(red: Double(converted.redComponent), green: Double(converted.greenComponent), blue: Double(converted.blueComponent))
    }
}
