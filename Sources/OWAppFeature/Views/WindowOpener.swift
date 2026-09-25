import AppKit
import SwiftUI

/// Lets AppKit code (the app delegate) open SwiftUI windows, which is otherwise only possible from a view.
///
/// `MenuBarLabel` is always on screen (it is the status-bar icon), so it registers the SwiftUI
/// `openWindow` action here as soon as the app starts.
@MainActor
public final class WindowOpener {
    public static let shared = WindowOpener()

    private var openLibraryAction: (() -> Void)?

    public init() {}

    func register(_ action: @escaping () -> Void) {
        openLibraryAction = action
    }

    public var isReady: Bool { openLibraryAction != nil }

    /// Shows the library window and brings the app to the front.
    public func openLibrary() {
        if let openLibraryAction {
            openLibraryAction()
        } else if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(LibraryWindow.windowID) == true }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }
}

/// Status-bar icon. Also registers the window-opening action with `WindowOpener`.
public struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Image(systemName: "sparkles.rectangle.stack")
            .onAppear {
                let open = openWindow
                WindowOpener.shared.register { open(id: LibraryWindow.windowID) }
            }
    }
}
