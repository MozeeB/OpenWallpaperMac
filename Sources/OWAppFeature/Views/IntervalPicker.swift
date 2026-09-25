import OWCore
import SwiftUI

/// Preset or custom rotation interval. Calls `onChange` only with valid values (5 s to 24 h).
struct IntervalPicker: View {
    static let customTag: TimeInterval = -1

    let interval: TimeInterval
    var label = "Switch every"
    let onChange: (TimeInterval) -> Void

    @State private var customMode = false
    @State private var value: Double = 2
    @State private var unit: Rotation.Unit = .minutes

    private var isPreset: Bool { Rotation.presetIntervals.contains(interval) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(label, selection: Binding(
                get: { customMode || !isPreset ? Self.customTag : interval },
                set: { choice in
                    if choice == Self.customTag {
                        customMode = true
                    } else {
                        customMode = false
                        onChange(choice)
                    }
                }
            )) {
                ForEach(Rotation.presetIntervals, id: \.self) { Text(Rotation.label(for: $0)).tag($0) }
                Divider()
                Text(isPreset ? "Custom..." : "Custom (\(Rotation.label(for: interval)))").tag(Self.customTag)
            }
            .accessibilityIdentifier("rotation.interval")
            if customMode || !isPreset {
                customFields
            }
        }
        .onAppear(perform: loadCustom)
        .onChange(of: interval) { loadCustom() }
    }

    private var customFields: some View {
        HStack {
            TextField("Every", value: $value, format: .number)
                .frame(width: 64)
                .onSubmit(commit)
                .accessibilityIdentifier("rotation.customValue")
            Picker("Unit", selection: $unit) {
                ForEach(Rotation.Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Button("Apply", action: commit)
                .disabled(Rotation.customInterval(value, unit: unit) == nil)
                .accessibilityIdentifier("rotation.customApply")
            if Rotation.customInterval(value, unit: unit) == nil {
                Text("5 s to 24 h").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func loadCustom() {
        let parts = Rotation.split(interval)
        value = parts.value
        unit = parts.unit
    }

    private func commit() {
        guard let seconds = Rotation.customInterval(value, unit: unit) else { return }
        customMode = !Rotation.presetIntervals.contains(seconds)
        onChange(seconds)
    }
}
