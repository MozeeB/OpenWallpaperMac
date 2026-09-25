import OWAppFeature
import SwiftUI

@main
struct OpenWallpaperMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Wallpaper Library", id: LibraryWindow.windowID) {
            LibraryWindow(model: delegate.model)
        }
        .defaultLaunchBehavior(.presented)
        // Otherwise a window closed before quitting stays closed on the next launch.
        .restorationBehavior(.disabled)
        MenuBarExtra {
            MenuBarContent(model: delegate.model)
        } label: {
            MenuBarLabel()
        }
        Settings {
            SettingsView(model: delegate.model)
        }
    }
}

/// Thin shell: all behaviour lives in the OWAppFeature package so it can be unit-tested.
///
/// A regular Dock app: the library opens on launch (except when started at login), closing the
/// window keeps wallpapers running, and clicking the Dock icon reopens the library.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let mode = AppEnvironment.mode()
    lazy var model = AppEnvironment.makeModel(mode: mode)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // The launch Apple event is only readable while this method runs.
        if AppDelegate.isLoginItemLaunch() {
            DispatchQueue.main.async { AppDelegate.closeLibraryWindows() }
        } else {
            NSApp.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { AppDelegate.ensureLibraryVisible() }
        }
        Task { await model.bootstrap() }
    }

    /// Safety net: a normal launch must always show the library.
    static func ensureLibraryVisible() {
        let visible = NSApp.windows.contains {
            $0.isVisible && $0.identifier?.rawValue.hasPrefix(LibraryWindow.windowID) == true
        }
        if !visible { WindowOpener.shared.openLibrary() }
    }

    private static func closeLibraryWindows() {
        NSApp.windows
            .filter { $0.identifier?.rawValue.hasPrefix(LibraryWindow.windowID) == true }
            .forEach { $0.close() }
    }

    /// Dock icon clicked (or app reopened from Finder): show the library if it is not open.
    ///
    /// `hasVisibleWindows` is always true here because the desktop wallpaper windows count as
    /// visible, so check for the library window itself.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppDelegate.ensureLibraryVisible()
        return true
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

    /// Wallpapers keep running after the library window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// True when macOS started the app as a login item (so it should start quietly).
    private static func isLoginItemLaunch() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication,
              let property = event.paramDescriptor(forKeyword: keyAEPropData)
        else { return false }
        return property.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
