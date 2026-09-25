import OWCore
import SwiftUI

/// Shown when several wallpapers are selected: rotate them on one or all displays, or on one Space.
struct RotationInspector: View {
    static let customTag: TimeInterval = -1

    @Bindable var model: AppModel
    let selection: [WallpaperID]
    @State private var preset: TimeInterval = Rotation.presetIntervals[0]
    @State private var customValue: Double = 2
    @State private var customUnit: Rotation.Unit = .minutes
    @State private var shuffle = false

    private var items: [Wallpaper] {
        selection.compactMap { id in model.library.first { $0.id == id } }
    }

    /// The chosen interval in seconds, or nil when the custom value is out of range.
    private var interval: TimeInterval? {
        preset == Self.customTag ? Rotation.customInterval(customValue, unit: customUnit) : preset
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, wallpaper in
                    Label("\(index + 1). \(wallpaper.title)", systemImage: TypeStyle.symbol(wallpaper.type))
                }
            } header: {
                Text("Rotate \(items.count) Wallpapers").font(.title2).bold()
            } footer: {
                Text("Order follows the order you selected them. Command-click to add or remove.")
            }
            intervalSection
            Section("Apply") {
                Button("Rotate on All Displays") { apply(to: nil, space: nil) }
                    .accessibilityIdentifier("rotation.applyAll")
                    .disabled(interval == nil)
                ForEach(model.displays, id: \.key) { screen in
                    SpaceTargetMenu(model: model, title: "Rotate on \(screen.name)", display: screen.key) { space in
                        apply(to: screen.key, space: space)
                    }
                    .disabled(interval == nil)
                }
            }
            ActiveRotationsSection(model: model)
        }
        .formStyle(.grouped)
    }

    private var intervalSection: some View {
        Section("Rotation") {
            Picker("Switch every", selection: $preset) {
                ForEach(Rotation.presetIntervals, id: \.self) { Text(Rotation.label(for: $0)).tag($0) }
                Divider()
                Text("Custom...").tag(Self.customTag)
            }
            .accessibilityIdentifier("rotation.interval")
            if preset == Self.customTag {
                HStack {
                    TextField("Every", value: $customValue, format: .number)
                        .frame(width: 70)
                        .accessibilityIdentifier("rotation.customValue")
                    Picker("Unit", selection: $customUnit) {
                        ForEach(Rotation.Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if let interval {
                    Text("Switches every \(Rotation.label(for: interval)).").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Choose between 5 seconds and 24 hours.").font(.caption).foregroundStyle(.red)
                }
            }
            Toggle("Shuffle", isOn: $shuffle)
        }
    }

    private func apply(to display: DisplayKey?, space: SpaceKey?) {
        guard let interval else { return }
        model.setRotation(items.map(\.id), interval: interval, shuffle: shuffle, display: display, space: space)
    }
}

/// Lists displays that are currently rotating, with Next and Stop controls.
struct ActiveRotationsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        let rotating = model.displays.filter { model.effectiveAssignment(for: $0.key)?.rotation != nil }
        if !rotating.isEmpty {
            Section("Active Rotations") {
                ForEach(rotating, id: \.key) { screen in
                    if let rotation = model.effectiveAssignment(for: screen.key)?.rotation {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(title(for: screen.key, name: screen.name))
                                Text("\(rotation.items.count) wallpapers, every \(Rotation.label(for: rotation.interval))"
                                     + (rotation.shuffle ? ", shuffled" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Next") { model.nextWallpaper(on: screen.key) }
                            Button("Stop") { model.stopRotation(on: screen.key) }
                                .accessibilityIdentifier("rotation.stop.\(screen.name)")
                        }
                    }
                }
            }
        }
    }

    private func title(for display: DisplayKey, name: String) -> String {
        guard let space = model.effectiveAssignment(for: display)?.space,
              let info = model.spaces(on: display)?.spaces.first(where: { $0.key == space })
        else { return name }
        return "\(name), \(info.name)"
    }
}
