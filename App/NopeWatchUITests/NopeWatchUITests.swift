import XCTest

/// UI tests of the Apple Watch app (issue #63) on the watch Simulator, with accessibility audits
/// for every state. The phone is simulated (`-NopeSimulatedPhone <scenario>`, Debug builds only),
/// because a UI test can't drive a paired iPhone.
final class NopeWatchUITests: XCTestCase {
    /// The largest accessibility text size.
    static let largestTextSize = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches the watch app with a simulated phone.
    ///
    /// - Parameters:
    ///   - scenario: The simulated phone's scenario.
    ///   - extraArguments: More launch arguments.
    /// - Returns: The running app.
    @MainActor
    func launch(_ scenario: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NopeSimulatedPhone", scenario] + extraArguments
        app.launch()
        return app
    }

    /// Runs every accessibility audit and fails with each issue's element, so a failure says
    /// what to fix.
    @MainActor
    func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            XCTFail("\(issue.compactDescription): \(issue.element?.debugDescription ?? "no element")")
            return true
        }
    }

    /// The status line.
    @MainActor
    func status(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["WatchStatus"]
    }

    /// The result line.
    @MainActor
    func result(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["WatchResult"]
    }

    @MainActor
    func testTheShutterTakesASignedPhoto() throws {
        let app = launch("ready")
        XCTAssertTrue(status(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(status(in: app).label, "Camera ready")
        try audit(app)
        let shutter = app.buttons["WatchShutter"]
        XCTAssertTrue(shutter.isEnabled)
        XCTAssertEqual(shutter.label, "Take Photo")
        shutter.tap()
        XCTAssertTrue(result(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(result(in: app).label, "Saved and signed")
        try audit(app)
    }

    @MainActor
    func testAnUnsignedPhotoIsAWarning() throws {
        let app = launch("notSigned")
        let shutter = app.buttons["WatchShutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        XCTAssertTrue(result(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(result(in: app).label, "Saved, not signed")
        try audit(app)
    }

    @MainActor
    func testNothingIsTakenWhenThePhonesCameraIsNotAvailable() throws {
        let app = launch("notRunning")
        XCTAssertTrue(status(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(status(in: app).label, "Camera not available. Open nope. on your phone.")
        XCTAssertFalse(app.buttons["WatchShutter"].isEnabled)
        try audit(app)
    }

    @MainActor
    func testDeclinedCameraAccessIsExplained() throws {
        let app = launch("permissionDenied")
        XCTAssertTrue(status(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(status(in: app).label, "Camera access is off. Turn it on in your phone's Settings app.")
        try audit(app)
    }

    @MainActor
    func testAPhoneThatCannotBeReachedIsShown() throws {
        let app = launch("unreachable")
        XCTAssertTrue(status(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(status(in: app).label, "Can't reach your phone. Keep it nearby with nope. open.")
        XCTAssertFalse(app.buttons["WatchShutter"].isEnabled)
        try audit(app)
    }

    @MainActor
    func testTheCountdownCanBeCancelled() throws {
        let app = launch("countdown")
        XCTAssertTrue(status(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(status(in: app).label, "Photo in 10 seconds")
        let cancel = app.buttons["WatchCancelTimer"]
        XCTAssertTrue(cancel.exists)
        try audit(app)
        cancel.tap()
        XCTAssertTrue(result(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(result(in: app).label, "Timer canceled. No photo taken.")
        XCTAssertTrue(app.buttons["WatchShutter"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTheDelayIsAPushedList() throws {
        let app = launch("ready")
        let delay = app.buttons["WatchDelay"]
        XCTAssertTrue(delay.waitForExistence(timeout: 10))
        delay.tap()
        let threeSeconds = app.buttons["3 seconds"]
        XCTAssertTrue(threeSeconds.waitForExistence(timeout: 10))
        try audit(app)
        threeSeconds.tap()
        XCTAssertTrue(app.buttons["WatchDelay"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["WatchDelay"].label.contains("3 seconds"))
    }

    @MainActor
    func testTheLargestTextSizePassesTheAudit() throws {
        let app = launch("ready", extraArguments: Self.largestTextSize)
        XCTAssertTrue(status(in: app).waitForExistence(timeout: 10))
        try audit(app)
        let shutter = app.buttons["WatchShutter"]
        shutter.tap()
        XCTAssertTrue(result(in: app).waitForExistence(timeout: 10))
        try audit(app)
    }
}
