import OWCore
import SwiftUI

struct WallpaperGrid: View {
    @Bindable var model: AppModel
    let items: [Wallpaper]
    /// Ordered selection: the order clicked becomes the rotation order.
    @Binding var selection: [WallpaperID]
    /// Selection mode: every click toggles and checkboxes are shown.
    var selecting = false

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView("Nothing Here", systemImage: "sparkles.rectangle.stack",
                                       description: Text("Use + to import wallpapers."))
                    .padding(.top, 80)
            }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items) { wallpaper in
                    cell(wallpaper)
                }
            }
            .padding(14)
        }
    }

    private func cell(_ wallpaper: Wallpaper) -> some View {
        let showChecks = selecting || selection.count > 1
        return WallpaperCell(
            wallpaper: wallpaper, thumbnail: model.thumbnails[wallpaper.id],
            selected: selection.contains(wallpaper.id),
            order: showChecks ? selection.firstIndex(of: wallpaper.id).map { $0 + 1 } : nil,
            showCheckbox: showChecks,
            activeLocations: model.activeLocations(for: wallpaper.id)
        )
        // Modified clicks are matched when the click happens, not after the double-click delay.
        .highPriorityGesture(TapGesture().modifiers(.command).onEnded { toggle(wallpaper.id) })
        .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { extend(to: wallpaper.id) })
        .onTapGesture(count: 2) { if !selecting { model.assign(wallpaper.id, to: nil) } }
        .onTapGesture { selecting ? toggle(wallpaper.id) : (selection = [wallpaper.id]) }
        .contextMenu { contextMenu(for: wallpaper) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("wallpaper.\(wallpaper.title)")
    }

    /// Command-click (or any click in selection mode) adds or removes one wallpaper.
    private func toggle(_ id: WallpaperID) {
        selection = selection.contains(id) ? selection.filter { $0 != id } : selection + [id]
    }

    /// Shift-click selects everything between the last selected wallpaper and this one.
    private func extend(to id: WallpaperID) {
        guard let anchor = selection.last, let from = items.firstIndex(where: { $0.id == anchor }),
              let to = items.firstIndex(where: { $0.id == id })
        else {
            selection = [id]
            return
        }
        let range = from <= to ? Array(items[from ... to]) : Array(items[to ... from].reversed())
        selection += range.map(\.id).filter { !selection.contains($0) }
    }

    @ViewBuilder
    private func contextMenu(for wallpaper: Wallpaper) -> some View {
        Button("Set on All Displays") { model.assign(wallpaper.id, to: nil) }
        ForEach(model.displays, id: \.key) { screen in
            Button("Set on \(screen.name)") { model.assign(wallpaper.id, to: screen.key) }
        }
        Divider()
        ForEach(model.displays, id: \.key) { screen in
            Button("Add to Rotation on \(screen.name)") { model.addToRotation(wallpaper.id, display: screen.key) }
        }
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([wallpaper.root]) }
        Button("Remove from Library", role: .destructive) { model.remove(wallpaper.id) }
    }
}

struct WallpaperCell: View {
    let wallpaper: Wallpaper
    let thumbnail: URL?
    let selected: Bool
    var order: Int?
    var showCheckbox = false
    var activeLocations: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Thumbnail(url: thumbnail, type: wallpaper.type)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
                if showCheckbox { checkbox.padding(6) }
                if !activeLocations.isEmpty {
                    Text(activeLocations.count == 1 ? activeLocations[0] : "Active on \(activeLocations.count) displays")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.green.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .help(activeLocations.joined(separator: "\n"))
                }
            }
            HStack(spacing: 4) {
                Text(wallpaper.title).font(.callout).lineLimit(1)
                Spacer(minLength: 2)
                badges
            }
        }
    }

    private var checkbox: some View {
        ZStack {
            Circle().fill(selected ? Color.accentColor : Color.black.opacity(0.35)).frame(width: 22, height: 22)
            Circle().stroke(.white, lineWidth: 1.5).frame(width: 22, height: 22)
            if let order {
                Text("\(order)").font(.caption.bold()).foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if wallpaper.usesAudio {
            Image(systemName: "waveform").help("Audio-reactive").foregroundStyle(.secondary)
        }
        switch wallpaper.support {
        case .full:
            EmptyView()
        case .partial:
            Image(systemName: "circle.lefthalf.filled").help("Partial support: some effects are skipped").foregroundStyle(.orange)
        case .previewOnly:
            Image(systemName: "eye").help("Preview only: this scene uses features not supported yet").foregroundStyle(.red)
        }
    }
}
