import OWCore
import SwiftUI

/// Interval, shuffle, Next and Stop for a running rotation. Used in Active Rotations and on the
/// Displays page.
struct RotationControls: View {
    @Bindable var model: AppModel
    let slot: AssignmentSlot
    let rotation: Rotation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IntervalPicker(interval: rotation.interval) { interval in
                model.updateRotation(in: slot) { $0.with(interval: interval) }
            }
            HStack {
                Toggle("Shuffle", isOn: Binding(
                    get: { rotation.shuffle },
                    set: { value in model.updateRotation(in: slot) { $0.with(shuffle: value) } }
                ))
                Spacer()
                Button("Next") { model.nextWallpaper(on: slot.display) }
                    .disabled(model.effectiveAssignment(for: slot.display)?.slot != slot)
                    .help("Show the next wallpaper now (only for the rotation on screen)")
                Button("Stop Rotation") { model.stopRotation(on: slot.display, space: slot.space) }
                    .accessibilityIdentifier("rotation.stop.\(slot.display.rawValue)")
            }
        }
    }
}

/// Full editor for one rotation: controls plus the ordered wallpaper list.
struct RotationEditor: View {
    @Bindable var model: AppModel
    let slot: AssignmentSlot
    let rotation: Rotation
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RotationControls(model: model, slot: slot, rotation: rotation)
            Divider()
            ForEach(Array(rotation.items.enumerated()), id: \.element) { index, id in
                itemRow(index: index, id: id)
            }
            Button("Add Wallpapers...") { adding = true }
                .accessibilityIdentifier("rotation.add")
        }
        .sheet(isPresented: $adding) {
            AddWallpapersSheet(model: model, excluding: Set(rotation.items)) { ids in
                model.updateRotation(in: slot) { $0.adding(ids) }
            }
        }
    }

    private func itemRow(index: Int, id: WallpaperID) -> some View {
        let wallpaper = model.library.first { $0.id == id }
        let showing = model.effectiveAssignment(for: slot.display)?.slot == slot
            && model.activeWallpaper(for: slot.display)?.id == id
        return HStack(spacing: 8) {
            Thumbnail(url: model.thumbnails[id], type: wallpaper?.type ?? .image)
                .frame(width: 56, height: 32)
            Text("\(index + 1). \(wallpaper?.title ?? "Missing wallpaper")").lineLimit(1)
            if showing {
                Text("Showing").font(.caption).foregroundStyle(.green)
            }
            Spacer()
            Button { model.updateRotation(in: slot) { $0.moving(at: index, by: -1) } } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .help("Move up")
            Button { model.updateRotation(in: slot) { $0.moving(at: index, by: 1) } } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == rotation.items.count - 1)
            .help("Move down")
            Button { model.updateRotation(in: slot) { $0.removing(id) } } label: {
                Image(systemName: "minus.circle")
            }
            .help("Remove from rotation")
        }
        .buttonStyle(.borderless)
    }
}

/// Small thumbnail with a type icon fallback.
struct Thumbnail: View {
    let url: URL?
    let type: WallpaperType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: TypeStyle.symbol(type)).foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Checklist of library wallpapers to add to a rotation.
struct AddWallpapersSheet: View {
    @Bindable var model: AppModel
    let excluding: Set<WallpaperID>
    let onAdd: ([WallpaperID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: [WallpaperID] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Wallpapers").font(.title2).bold()
            List(model.library.filter { !excluding.contains($0.id) }) { wallpaper in
                Toggle(isOn: Binding(
                    get: { chosen.contains(wallpaper.id) },
                    set: { on in chosen = on ? chosen + [wallpaper.id] : chosen.filter { $0 != wallpaper.id } }
                )) {
                    HStack {
                        Thumbnail(url: model.thumbnails[wallpaper.id], type: wallpaper.type).frame(width: 56, height: 32)
                        Text(wallpaper.title)
                    }
                }
            }
            .frame(minHeight: 240)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add \(chosen.count)") {
                    onAdd(chosen)
                    dismiss()
                }
                .disabled(chosen.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420, height: 400)
    }
}
