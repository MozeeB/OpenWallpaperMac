import OWCore
import OWDesktop
import SwiftUI

/// Every display with what it shows: the default and each Space, single wallpapers and editable
/// rotations.
struct DisplaysPage: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(model.displays, id: \.key) { screen in
                    DisplayCard(model: model, screen: screen)
                }
                if model.displays.isEmpty {
                    ContentUnavailableView("No Displays", systemImage: "display")
                }
            }
            .padding(16)
        }
        .navigationTitle("Displays & Rotations")
    }
}

private struct DisplayCard: View {
    @Bindable var model: AppModel
    let screen: ScreenDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(screen.name, systemImage: "display").font(.title3).bold()
                if let space = model.spaces(on: screen.key)?.currentSpace, model.supportsSpaces {
                    Text("Now on \(space.name)").foregroundStyle(.secondary)
                }
                Spacer()
                if let active = model.activeWallpaper(for: screen.key) {
                    Text("Showing: \(active.title)").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            let slots = model.slots(on: screen.key)
            if slots.isEmpty {
                Text("Nothing assigned. The regular macOS wallpaper is shown. Pick a wallpaper in the library and use Set.")
                    .foregroundStyle(.secondary)
            }
            ForEach(slots, id: \.slot) { entry in
                SlotRow(model: model, title: entry.title, slot: entry.slot, assignment: entry.assignment,
                        isOnScreen: model.effectiveAssignment(for: screen.key)?.slot == entry.slot)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("displayCard.\(screen.name)")
    }
}

private struct SlotRow: View {
    @Bindable var model: AppModel
    let title: String
    let slot: AssignmentSlot
    let assignment: DisplayAssignment
    let isOnScreen: Bool
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                if isOnScreen {
                    Text("On screen").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.2), in: Capsule())
                }
                Spacer()
                Button("Remove") { model.clearAssignment(for: slot.display, space: slot.space) }
                    .help("Stop using a wallpaper here")
            }
            if let rotation = assignment.rotation {
                RotationEditor(model: model, slot: slot, rotation: rotation)
            } else {
                singleWallpaper
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $adding) {
            AddWallpapersSheet(model: model, excluding: [assignment.wallpaper]) { ids in
                model.makeRotation(in: slot, adding: ids)
            }
        }
    }

    private var singleWallpaper: some View {
        let wallpaper = model.library.first { $0.id == assignment.wallpaper }
        return HStack {
            Thumbnail(url: model.thumbnails[assignment.wallpaper], type: wallpaper?.type ?? .image)
                .frame(width: 80, height: 45)
            Text(wallpaper?.title ?? "Missing wallpaper")
            Spacer()
            Button("Make Rotation...") { adding = true }
                .accessibilityIdentifier("slot.makeRotation")
        }
    }
}
