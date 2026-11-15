import XCTest

/// Siri and Shortcuts requests (issue #62), sent with the Debug-only `-NopeSimulatedShortcut`
/// launch argument through the same inbox the Take Photo intent uses, because XCTest can't speak
/// to Siri or run a shortcut.
final class ShortcutUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches the app with a simulated camera and a Take Photo request with this delay.
    @MainActor
    func launch(_ scenario: String, delaySeconds: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NopeSimulatedCamera", scenario, "-NopeSimulatedShortcut", String(delaySeconds)]
        app.launch()
        return app
    }

    /// What Siri would say, once the request ends.
    @MainActor
    func result(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["SimulatedShortcutResult"]
    }

    @MainActor
    func testARequestWithADelayCountsDownThenSaysThePhotoWasSaved() {
        let app = launch("noRAW", delaySeconds: 3)
        // The self-timer runs as it does from the shutter, with its countdown on screen.
        XCTAssertTrue(app.buttons["Cancel Timer"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["Take Photo"].value as? String, "Counting down. Press to cancel.")
        let message = result(app)
        XCTAssertTrue(message.waitForExistence(timeout: 30))
        XCTAssertEqual(message.label, "Photo saved and signed.")
    }

    @MainActor
    func testACancelledCountdownSaysNoPhotoWasTaken() {
        let app = launch("noRAW", delaySeconds: 10)
        let cancel = app.buttons["Cancel Timer"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 20))
        cancel.tap()
        let message = result(app)
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertEqual(message.label, "The timer was cancelled. No photo was taken.")
    }

    @MainActor
    func testARequestWithoutCameraAccessSaysWhy() {
        let app = launch("denied", delaySeconds: 0)
        let message = result(app)
        XCTAssertTrue(message.waitForExistence(timeout: 20))
        XCTAssertEqual(message.label, "Camera access is off for nope. You can turn it on in the Settings app.")
    }
}
