import XCTest

/// Select mode, rotating, editing the interval of a running rotation, and the Active filter.
final class RotationEditingUITests: XCTestCase {
    func testSelectModeRotateEditIntervalAndActiveFilter() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()
        defer { app.terminate() }

        let plasma = app.descendants(matching: .any)["wallpaper.Plasma"]
        let scene = app.descendants(matching: .any)["wallpaper.Synthetic Scene"]
        XCTAssertTrue(plasma.waitForExistence(timeout: 10))

        // Select mode: plain clicks toggle.
        app.checkBoxes["library.select"].firstMatch.click()
        plasma.click()
        scene.click()
        XCTAssertTrue(app.staticTexts["Rotate 2 Wallpapers"].waitForExistence(timeout: 5))
        app.buttons["rotation.applyAll"].click()

        // Edit the running rotation on the Displays & Rotations page.
        app.descendants(matching: .any)["sidebar.displays"].firstMatch.click()
        let interval = app.popUpButtons["rotation.interval"].firstMatch
        XCTAssertTrue(interval.waitForExistence(timeout: 5), "running rotation is editable")
        // Coordinate click: SwiftUI pop-ups in scroll views do not always post the menu-open notification.
        interval.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(app.menuItems["1 min"].firstMatch.waitForExistence(timeout: 5))
        // Keyboard selection (5 s -> 10 s -> 30 s -> 1 min); clicking items in SwiftUI pop-ups can hang XCTest.
        for _ in 0 ..< 3 { app.typeKey(.downArrow, modifierFlags: []) }
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.popUpButtons.matching(NSPredicate(format: "value == '1 min'")).firstMatch.waitForExistence(timeout: 5))

        // Active filter lists what is on screen.
        app.descendants(matching: .any)["sidebar.active"].firstMatch.click()
        XCTAssertTrue(plasma.waitForExistence(timeout: 5))
        XCTAssertTrue(scene.exists)
    }
}
