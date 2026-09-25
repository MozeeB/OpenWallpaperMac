import OWCore
import SwiftUI
import UniformTypeIdentifiers

/// Main library window: filters, wallpaper grid and inspector.
public struct LibraryWindow: View {
    public static let windowID = "library"

    @Bindable var model: AppModel
    @State private var selection: [WallpaperID] = []
    @State private var query = ""
    @State private var typeFilter: WallpaperType?
    @State private var importing = false

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $typeFilter) {
                Label("All Wallpapers", systemImage: "square.grid.2x2").tag(WallpaperType?.none)
                ForEach(WallpaperType.allCases, id: \.self) { type in
                    Label(TypeStyle.title(type), systemImage: TypeStyle.symbol(type)).tag(Optional(type))
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } content: {
            WallpaperGrid(model: model, items: filtered, selection: $selection)
                .searchable(text: $query, prompt: "Search wallpapers")
                .navigationSplitViewColumnWidth(min: 380, ideal: 560)
        } detail: {
            if selection.count > 1 {
                RotationInspector(model: model, selection: selection)
            } else if let wallpaper = model.library.first(where: { $0.id == selection.first }) {
                InspectorView(model: model, wallpaper: wallpaper)
            } else {
                ContentUnavailableView("No Selection", systemImage: "photo.on.rectangle", description: Text(
                    "Import a video, web page, shader or Wallpaper Engine project. Command-click several to rotate them."
                ))
            }
        }
        .toolbar { toolbar }
        .fileImporter(isPresented: $importing, allowedContentTypes: ImportTypes.all, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await model.importItems(urls) }
        }
        .overlay(alignment: .bottom) { MessageBanner(model: model) }
        .frame(minWidth: 900, minHeight: 540)
        .onAppear { model.refreshDisplays() }
    }

    private var filtered: [Wallpaper] {
        model.library.filter { item in
            (typeFilter == nil || item.type == typeFilter)
                && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
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
