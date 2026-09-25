import AppKit
import XCTest

/// The app is a regular Dock app: the library opens on launch, closing it keeps the app (and
/// wallpapers) running, and reopening the app (Dock click / Finder) shows the library again.
final class DockBehaviourUITests: XCTestCase {
    func testLibraryOpensOnLaunchAndReopensAfterClosing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()
        defer { app.terminate() }

        let library = app.windows["Wallpaper Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10), "library window is shown on launch")

        library.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(library.waitForNonExistence(timeout: 5), "closing the window hides it")
        XCTAssertEqual(app.state, .runningForeground, "app keeps running after its window closes")

        // Re-opening a running app sends the same "reopen" event as clicking its Dock icon.
        let reopened = expectation(description: "reopen")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Resolve the build under test (not another installed copy with the same bundle id):
        // .../Products/Debug/OpenWallpaperMacUITests-Runner.app/Contents/PlugIns/<tests>.xctest
        let products = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let bundleURL = products.appendingPathComponent("OpenWallpaperMac.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.path), bundleURL.path)
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in reopened.fulfill() }
        wait(for: [reopened], timeout: 10)
        XCTAssertTrue(library.waitForExistence(timeout: 10), "reopening the app shows the library again")
    }
}
