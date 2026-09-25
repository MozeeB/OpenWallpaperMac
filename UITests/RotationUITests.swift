import XCTest

/// Select several wallpapers with Command-click and rotate them on every display.
final class RotationUITests: XCTestCase {
    func testRotateTwoWallpapersOnAllDisplaysThenStop() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()
        defer { app.terminate() }

        let plasma = app.descendants(matching: .any)["wallpaper.Plasma"]
        let scene = app.descendants(matching: .any)["wallpaper.Synthetic Scene"]
        XCTAssertTrue(plasma.waitForExistence(timeout: 10))
        plasma.click()
        XCUIElement.perform(withKeyModifiers: .command) { scene.click() }

        let applyAll = app.buttons["rotation.applyAll"]
        XCTAssertTrue(applyAll.waitForExistence(timeout: 5), "multi-selection shows the rotation panel")
        XCTAssertTrue(app.staticTexts["Rotate 2 Wallpapers"].exists)
        applyAll.click()

        XCTAssertTrue(app.staticTexts["Active Rotations"].waitForExistence(timeout: 5))
        let stopButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rotation.stop.'"))
        XCTAssertGreaterThan(stopButtons.count, 0)
        while stopButtons.firstMatch.exists { stopButtons.firstMatch.click() }
        XCTAssertFalse(app.staticTexts["Active Rotations"].waitForExistence(timeout: 2), "stopping removes the rotation")
    }
}
