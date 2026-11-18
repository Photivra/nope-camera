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
        launch(scenario, request: String(delaySeconds))
    }

    /// Launches the app with a simulated camera and a request (`SimulatedShortcut`).
    @MainActor
    func launch(_ scenario: String, request: String) -> XCUIApplication {
        let app = XCUIApplication()
        // Signing on (off by default, issue #80), so Siri's answers about signed photos show.
        app.launchArguments = ["-NopeSimulatedCamera", scenario, "-NopeSimulatedShortcut", request, "-NopeSimulatedSigning"]
        app.launchAfterThePreviousRunExits()
        return app
    }

    /// What Siri would say, once the request ends.
    @MainActor
    func result(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["SimulatedShortcutResult"]
    }

    @MainActor
    func testARequestWithADelayCountsDownThenSaysThePhotoWasSaved() {
        // Ten seconds, so the countdown is still running when it is checked: on the CI runner a
        // three-second countdown had ended before the shutter's value was read.
        let app = launch("noRAW", delaySeconds: 10)
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

    @MainActor
    func testACountTakesABurstThenSaysThePhotosWereSaved() {
        let app = launch("noRAW", request: "burst3")
        let message = result(app)
        XCTAssertTrue(message.waitForExistence(timeout: 30))
        XCTAssertEqual(message.label, "Photos saved and signed.")
        // The burst of a chosen count isn't announced as stopped at the burst limit.
        XCTAssertFalse(app.staticTexts["Burst stopped at 3 photos, the most one burst takes."].exists)
    }

    @MainActor
    func testSwitchingLensesSaysWhichCamera() {
        let app = launch("slowSaving", request: "lens-ultraWide")
        let message = result(app)
        XCTAssertTrue(message.waitForExistence(timeout: 20))
        XCTAssertEqual(message.label, "Now using the ultra wide camera.")
        XCTAssertTrue(app.buttons["Ultra Wide"].isSelected)
    }

    @MainActor
    func testABracketIsTakenOnceInFullAuto() {
        // Manual controls stay off: the bracket is taken once without turning them on.
        let app = launch("manual", request: "bracket3")
        let message = result(app)
        XCTAssertTrue(message.waitForExistence(timeout: 30))
        XCTAssertEqual(message.label, "Photos saved and signed.")
        XCTAssertFalse(app.buttons["More Manual Controls"].exists)
    }

    @MainActor
    func testApplyPresetSaysWhatChangedAndCanBeUndone() throws {
        // Apply Preset with Factory Defaults, through the same path as the Presets list.
        let app = launch("noRAW", request: "preset-factory")
        let message = result(app)
        XCTAssertTrue(message.waitForExistence(timeout: 30))
        XCTAssertEqual(message.label, "Factory Defaults applied. You can undo it in Presets.")
        // The Presets list shows the result with Undo, as after applying it there. Settings is
        // in Q on the stacked camera (BUILD-SPEC.md, 3.1) and in the column on iPad.
        let settings = app.buttons["Settings"]
        if !settings.waitForExistence(timeout: 5) {
            app.buttons["Quick Menu"].tap()
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
        }
        settings.tap()
        let presets = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Presets")).firstMatch
        XCTAssertTrue(presets.waitForExistence(timeout: 5))
        presets.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
    }
}
