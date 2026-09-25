import OWCore
import SwiftUI

/// Menu shown from the menu bar icon.
public struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Button("Open Library…") { openLibrary() }
            .keyboardShortcut("l")
            .accessibilityIdentifier("menu.openLibrary")
        Divider()
        ForEach(model.displays, id: \.key) { screen in
            Menu(screen.name) {
                ForEach(model.library) { wallpaper in
                    Button(wallpaper.title) { model.assign(wallpaper.id, to: screen.key) }
                }
                if model.assignment(for: screen.key) != nil {
                    Divider()
                    Button("Show System Wallpaper") { model.clearAssignment(for: screen.key) }
                }
            }
            if let active = model.activeWallpaper(for: screen.key) {
                Text("  \(active.title)").foregroundStyle(.secondary)
            }
        }
        Divider()
        Button(model.isPaused ? "Resume Wallpapers" : "Pause Wallpapers") { model.togglePause() }
            .keyboardShortcut("p")
            .accessibilityIdentifier("menu.togglePause")
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit OpenWallpaperMac") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openLibrary() {
        openWindow(id: LibraryWindow.windowID)
        NSApplication.shared.activate()
    }
}
