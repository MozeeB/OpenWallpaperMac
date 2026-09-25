import OWCore
import SwiftUI

/// Details, display assignment and user properties for the selected wallpaper.
struct InspectorView: View {
    @Bindable var model: AppModel
    let wallpaper: Wallpaper
    @State private var editingDisplay: DisplayKey?

    var body: some View {
        Form {
            Section {
                LabeledContent("Type", value: TypeStyle.title(wallpaper.type))
                LabeledContent("Source", value: wallpaper.origin == .wallpaperEngine ? "Wallpaper Engine project" : "OpenWallpaperMac")
                LabeledContent("Support", value: supportText)
                if wallpaper.usesAudio { LabeledContent("Audio", value: "Reacts to system audio") }
            } header: {
                Text(wallpaper.title).font(.title2).bold()
            }
            Section("Displays") {
                Button("Set on All Displays") { model.assign(wallpaper.id, to: nil) }
                    .accessibilityIdentifier("inspector.setAll")
                ForEach(model.displays, id: \.key) { screen in
                    HStack {
                        Text(screen.name)
                        Spacer()
                        if model.assignment(for: screen.key)?.wallpaper == wallpaper.id {
                            Label("Active", systemImage: "checkmark").foregroundStyle(.green)
                        } else {
                            Button("Set") { model.assign(wallpaper.id, to: screen.key) }
                        }
                    }
                }
            }
            if let display = assignedDisplay, !wallpaper.properties.isEmpty {
                propertiesSection(display: display)
            }
            if let display = assignedDisplay {
                Section("Scaling") {
                    Picker("Fill", selection: fillBinding(display)) {
                        ForEach(FillMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
            }
            Section {
                Button("Remove from Library", role: .destructive) { model.remove(wallpaper.id) }
            }
        }
        .formStyle(.grouped)
    }

    private var assignedDisplay: DisplayKey? {
        if let editingDisplay, model.assignment(for: editingDisplay)?.wallpaper == wallpaper.id { return editingDisplay }
        return model.state.assignments.first { $0.wallpaper == wallpaper.id }?.display
    }

    private var supportText: String {
        switch wallpaper.support {
        case .full: return "Full"
        case .partial: return "Partial (some effects skipped)"
        case .previewOnly: return "Preview image only"
        }
    }

    @ViewBuilder
    private func propertiesSection(display: DisplayKey) -> some View {
        Section {
            let values = wallpaper.properties.resolve(model.assignment(for: display)?.overrides ?? [:])
            ForEach(wallpaper.properties) { definition in
                PropertyControl(definition: definition, value: values[definition.key] ?? definition.defaultValue) { value in
                    model.setOverride(value, key: definition.key, display: display)
                }
            }
            Button("Reset to Defaults") { model.resetOverrides(display: display) }
        } header: {
            HStack {
                Text("Properties")
                Spacer()
                let assigned = model.state.assignments.filter { $0.wallpaper == wallpaper.id }.map(\.display)
                if assigned.count > 1 {
                    Picker("Display", selection: Binding(get: { display }, set: { editingDisplay = $0 })) {
                        ForEach(assigned, id: \.self) { key in
                            Text(model.displays.first { $0.key == key }?.name ?? key.rawValue).tag(key)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            }
        }
    }

    private func fillBinding(_ display: DisplayKey) -> Binding<FillMode> {
        Binding(
            get: { model.assignment(for: display)?.fill ?? .fill },
            set: { model.setFill($0, display: display) }
        )
    }
}
