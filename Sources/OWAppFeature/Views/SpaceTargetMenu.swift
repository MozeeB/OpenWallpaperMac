import OWCore
import SwiftUI

/// "Set" / "Rotate" control for one display: all Spaces (the display default) or a single Space.
/// Falls back to a plain button when Spaces cannot be distinguished.
struct SpaceTargetMenu: View {
    @Bindable var model: AppModel
    let title: String
    let display: DisplayKey
    let action: (SpaceKey?) -> Void

    var body: some View {
        if model.supportsSpaces, let info = model.spaces(on: display), !info.spaces.isEmpty {
            Menu(title) {
                Button("All Spaces") { action(nil) }
                Divider()
                ForEach(info.spaces.filter { !$0.isFullscreen }) { space in
                    Button(space.key == info.current ? "\(space.name) only (current)" : "\(space.name) only") {
                        action(space.key)
                    }
                }
            }
            .fixedSize()
        } else {
            Button(title) { action(nil) }
        }
    }
}

/// Lists a display's Space-specific wallpapers with a Remove control.
struct SpaceAssignmentsList: View {
    @Bindable var model: AppModel
    let display: DisplayKey

    var body: some View {
        ForEach(model.spaceAssignments(on: display), id: \.space.key) { entry in
            HStack {
                Text("  \(entry.space.name):").foregroundStyle(.secondary)
                Text(summary(entry.assignment)).lineLimit(1)
                Spacer()
                Button("Remove") { model.clearAssignment(for: display, space: entry.space.key) }
                    .buttonStyle(.borderless)
            }
            .font(.callout)
        }
    }

    private func summary(_ assignment: DisplayAssignment) -> String {
        if let rotation = assignment.rotation {
            return "\(rotation.items.count) wallpapers, every \(Rotation.label(for: rotation.interval))"
        }
        return model.library.first { $0.id == assignment.wallpaper }?.title ?? "Wallpaper"
    }
}
