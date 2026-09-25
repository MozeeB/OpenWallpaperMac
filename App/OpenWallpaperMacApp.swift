import OWAppFeature
import SwiftUI

@main
struct OpenWallpaperMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("OpenWallpaperMac", systemImage: "sparkles.rectangle.stack") {
            MenuBarContent(model: delegate.model)
        }
        Window("Wallpaper Library", id: LibraryWindow.windowID) {
            LibraryWindow(model: delegate.model)
        }
        .defaultLaunchBehavior(delegate.mode == .uiTest ? .presented : .suppressed)
        Settings {
            SettingsView(model: delegate.model)
        }
    }
}

/// Thin shell: all behaviour lives in the OWAppFeature package so it can be unit-tested.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let mode = AppEnvironment.mode()
    lazy var model = AppEnvironment.makeModel(mode: mode)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await model.bootstrap() }
    }

    /// Flush pending saves and restore the system wallpaper before the process exits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.flush()
            model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
