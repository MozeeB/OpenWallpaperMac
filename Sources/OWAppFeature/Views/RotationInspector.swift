import OWCore
import SwiftUI

/// Shown when several wallpapers are selected: rotate them on one or all displays, or on one Space.
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
                    HStack {
                        Thumbnail(url: model.thumbnails[wallpaper.id], type: wallpaper.type).frame(width: 48, height: 27)
                        Text("\(index + 1). \(wallpaper.title)")
                    }
                }
            } header: {
                Text("Rotate \(items.count) Wallpapers").font(.title2).bold()
            } footer: {
                Text("Plays in the order you selected them. You can reorder later under Displays & Rotations.")
            }
            Section("Rotation") {
                IntervalPicker(interval: interval) { interval = $0 }
                Toggle("Shuffle", isOn: $shuffle)
            }
            Section("Apply") {
                Button("Rotate on All Displays") { apply(to: nil, space: nil) }
                    .accessibilityIdentifier("rotation.applyAll")
                ForEach(model.displays, id: \.key) { screen in
                    SpaceTargetMenu(model: model, title: "Rotate on \(screen.name)", display: screen.key) { space in
                        apply(to: screen.key, space: space)
                    }
                }
            }
            ActiveRotationsSection(model: model)
        }
        .formStyle(.grouped)
    }

    private func apply(to display: DisplayKey?, space: SpaceKey?) {
        model.setRotation(items.map(\.id), interval: interval, shuffle: shuffle, display: display, space: space)
    }
}

/// Rotations on screen right now, editable in place (interval, shuffle, Next, Stop).
struct ActiveRotationsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        let rotating = model.displays.compactMap { screen -> (String, DisplayAssignment, Rotation)? in
            guard let assignment = model.effectiveAssignment(for: screen.key), let rotation = assignment.rotation else { return nil }
            return (title(for: screen.key, name: screen.name, space: assignment.space), assignment, rotation)
        }
        if !rotating.isEmpty {
            Section("Active Rotations") {
                ForEach(rotating, id: \.1.slot) { title, assignment, rotation in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(title).font(.headline)
                            Spacer()
                            if let position = model.rotationPosition(for: assignment.display) {
                                Text("\(position.current) of \(position.count)").foregroundStyle(.secondary)
                            }
                        }
                        RotationControls(model: model, slot: assignment.slot, rotation: rotation)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func title(for display: DisplayKey, name: String, space: SpaceKey?) -> String {
        guard let space, let info = model.spaces(on: display)?.spaces.first(where: { $0.key == space }) else { return name }
        return "\(name), \(info.name)"
    }
}
