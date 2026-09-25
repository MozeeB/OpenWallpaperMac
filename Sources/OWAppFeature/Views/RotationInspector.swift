import OWCore
import SwiftUI

/// Shown when several wallpapers are selected: rotate them on one or all displays.
struct RotationInspector: View {
    @Bindable var model: AppModel
    let selection: [WallpaperID]
    @State private var interval: TimeInterval = Rotation.presetIntervals[0]
    @State private var shuffle = false

    private var items: [Wallpaper] {
        selection.compactMap { id in model.library.first { $0.id == id } }
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
            Section("Rotation") {
                Picker("Switch every", selection: $interval) {
                    ForEach(Rotation.presetIntervals, id: \.self) { Text(Rotation.label(for: $0)).tag($0) }
                }
                .accessibilityIdentifier("rotation.interval")
                Toggle("Shuffle", isOn: $shuffle)
            }
            Section("Apply") {
                Button("Rotate on All Displays") { apply(to: nil) }
                    .accessibilityIdentifier("rotation.applyAll")
                ForEach(model.displays, id: \.key) { screen in
                    Button("Rotate on \(screen.name)") { apply(to: screen.key) }
                }
            }
            ActiveRotationsSection(model: model)
        }
        .formStyle(.grouped)
    }

    private func apply(to display: DisplayKey?) {
        model.setRotation(items.map(\.id), interval: interval, shuffle: shuffle, display: display)
    }
}

/// Lists displays that are currently rotating, with Next and Stop controls.
struct ActiveRotationsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        let rotating = model.displays.filter { model.assignment(for: $0.key)?.rotation != nil }
        if !rotating.isEmpty {
            Section("Active Rotations") {
                ForEach(rotating, id: \.key) { screen in
                    if let rotation = model.assignment(for: screen.key)?.rotation {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(screen.name)
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
}
