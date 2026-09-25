import OWCore
import SwiftUI

struct WallpaperGrid: View {
    @Bindable var model: AppModel
    let items: [Wallpaper]
    @Binding var selection: WallpaperID?

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView("Library Empty", systemImage: "sparkles.rectangle.stack",
                                       description: Text("Use + to import wallpapers."))
                    .padding(.top, 80)
            }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items) { wallpaper in
                    WallpaperCell(wallpaper: wallpaper, thumbnail: model.thumbnails[wallpaper.id], selected: selection == wallpaper.id)
                        .onTapGesture(count: 2) { model.assign(wallpaper.id, to: nil) }
                        .onTapGesture { selection = wallpaper.id }
                        .contextMenu { contextMenu(for: wallpaper) }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("wallpaper.\(wallpaper.title)")
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func contextMenu(for wallpaper: Wallpaper) -> some View {
        Button("Set on All Displays") { model.assign(wallpaper.id, to: nil) }
        ForEach(model.displays, id: \.key) { screen in
            Button("Set on \(screen.name)") { model.assign(wallpaper.id, to: screen.key) }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let thumbnail, let image = NSImage(contentsOf: thumbnail) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: TypeStyle.symbol(wallpaper.type)).font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
            HStack(spacing: 4) {
                Text(wallpaper.title).font(.callout).lineLimit(1)
                Spacer(minLength: 2)
                badges
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
