import XCTest

/// End-to-end flow in an isolated state folder (`-UITestMode` seeds sample wallpapers and never
/// changes the real system wallpaper).
final class LibraryFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    func testAssignSampleShaderToAllDisplays() {
        let plasma = app.descendants(matching: .any)["wallpaper.Plasma"]
        XCTAssertTrue(plasma.waitForExistence(timeout: 10), "seeded sample appears in the library")
        plasma.click()

        let setAll = app.buttons["inspector.setAll"]
        XCTAssertTrue(setAll.waitForExistence(timeout: 5))
        setAll.click()
        XCTAssertTrue(app.staticTexts["Active"].firstMatch.waitForExistence(timeout: 5))

        let speed = app.descendants(matching: .any)["property.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 5), "shader properties are editable once assigned")
    }

    func testPauseToggle() {
        let pause = app.buttons["library.togglePause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.click()
        XCTAssertEqual(pause.label, "Resume")
        pause.click()
        XCTAssertEqual(pause.label, "Pause")
    }
}
