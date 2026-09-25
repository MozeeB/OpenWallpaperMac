import OWCore
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar destinations.
enum SidebarItem: Hashable {
    case all
    case active
    case type(WallpaperType)
    case displays
}

/// Main library window: sidebar, wallpaper grid (or the Displays & Rotations page) and inspector.
public struct LibraryWindow: View {
    public static let windowID = "library"

    @Bindable var model: AppModel
    @State private var selection: [WallpaperID] = []
    @State private var query = ""
    @State private var sidebar: SidebarItem? = .all
    @State private var selecting = false
    @State private var importing = false

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $sidebar) {
                Section("Library") {
                    Label("All Wallpapers", systemImage: "square.grid.2x2").tag(SidebarItem.all)
                    Label("Active", systemImage: "play.rectangle").tag(SidebarItem.active)
                        .accessibilityIdentifier("sidebar.active")
                    ForEach(WallpaperType.allCases, id: \.self) { type in
                        Label(TypeStyle.title(type), systemImage: TypeStyle.symbol(type)).tag(SidebarItem.type(type))
                    }
                }
                Section("Playback") {
                    Label("Displays & Rotations", systemImage: "rectangle.on.rectangle").tag(SidebarItem.displays)
                        .accessibilityIdentifier("sidebar.displays")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            if sidebar == .displays {
                DisplaysPage(model: model)
                    .navigationSplitViewColumnWidth(min: 460, ideal: 620)
            } else {
                WallpaperGrid(model: model, items: filtered, selection: $selection, selecting: selecting)
                    .searchable(text: $query, prompt: "Search wallpapers")
                    .navigationSplitViewColumnWidth(min: 380, ideal: 560)
            }
        } detail: {
            detail
        }
        .toolbar { toolbar }
        .fileImporter(isPresented: $importing, allowedContentTypes: ImportTypes.all, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await model.importItems(urls) }
        }
        .overlay(alignment: .bottom) { MessageBanner(model: model) }
        .frame(minWidth: 960, minHeight: 560)
        .onAppear { model.refreshDisplays() }
    }

    @ViewBuilder
    private var detail: some View {
        if selection.count > 1 {
            RotationInspector(model: model, selection: selection)
        } else if let wallpaper = model.library.first(where: { $0.id == selection.first }) {
            InspectorView(model: model, wallpaper: wallpaper)
        } else {
            ContentUnavailableView("No Selection", systemImage: "photo.on.rectangle", description: Text(
                "Click a wallpaper to set it. Use Select (or Command-click) to pick several and rotate them."
            ))
        }
    }

    private var filtered: [Wallpaper] {
        let active = model.activeWallpaperIDs
        return model.library.filter { item in
            let matchesSidebar: Bool
            switch sidebar ?? .all {
            case .all, .displays: matchesSidebar = true
            case .active: matchesSidebar = active.contains(item.id)
            case .type(let type): matchesSidebar = item.type == type
            }
            return matchesSidebar && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if selecting {
                Button("Select All") { selection = filtered.map(\.id) }
                    .accessibilityIdentifier("library.selectAll")
                Button("Clear") { selection = [] }
                    .disabled(selection.isEmpty)
            }
            Toggle(isOn: $selecting) { Label(selecting ? "Done" : "Select", systemImage: "checkmark.circle") }
                .toggleStyle(.button)
                .help("Select several wallpapers to rotate them")
                .accessibilityIdentifier("library.select")
            Button { importing = true } label: { Label("Import", systemImage: "plus") }
                .help("Import files or Wallpaper Engine project folders")
                .accessibilityIdentifier("library.import")
            Button { Task { await model.scanSteamLibrary() } } label: {
                Label("Scan Steam Library", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Find Wallpaper Engine projects in local Steam libraries")
            Button { model.togglePause() } label: {
                Label(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
            }
            .accessibilityIdentifier("library.togglePause")
        }
    }
}

enum ImportTypes {
    static let all: [UTType] = [.folder, .movie, .mpeg4Movie, .quickTimeMovie, .image, .html] + extra
    static let extra: [UTType] = ["metal", "pkg"].compactMap { UTType(filenameExtension: $0) }
}

enum TypeStyle {
    static func title(_ type: WallpaperType) -> String {
        switch type {
        case .image: return "Images"
        case .video: return "Videos"
        case .web: return "Web"
        case .shader: return "Shaders"
        case .scene: return "Scenes"
        }
    }

    static func symbol(_ type: WallpaperType) -> String {
        switch type {
        case .image: return "photo"
        case .video: return "film"
        case .web: return "globe"
        case .shader: return "wand.and.stars"
        case .scene: return "square.stack.3d.up"
        }
    }
}

/// Transient notices (import results, render fallbacks, audio hints).
struct MessageBanner: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(model.messages) { message in
                HStack(alignment: .top) {
                    Image(systemName: icon(message.level)).foregroundStyle(color(message.level))
                    Text(message.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.dismiss(message) } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .frame(maxWidth: 560)
        .accessibilityIdentifier("library.messages")
    }

    private func icon(_ level: AppMessage.Level) -> String {
        switch level {
        case .info: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private func color(_ level: AppMessage.Level) -> Color {
        switch level {
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
