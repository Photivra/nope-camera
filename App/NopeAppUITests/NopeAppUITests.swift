import XCTest

/// UI tests for the camera screen against the simulated backend (the Simulator has no camera):
/// every state passes the accessibility audit, at the default and largest text sizes and in
/// right-to-left layout.
final class NopeAppUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches the app with a simulated camera scenario (`SimulatedCameraLaunch.Scenario`).
    @MainActor
    private func launch(_ scenario: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NopeSimulatedCamera", scenario] + extraArguments
        app.launch()
        return app
    }

    /// Any element whose accessibility label contains the text.
    @MainActor
    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Runs the accessibility audit at the largest text sizes, where the screen scrolls.
    ///
    /// A contrast issue is ignored only for an element that runs past the edge of the screen:
    /// the audit then measures the clipped edge. In CI the status text (white on black, see the
    /// failing run's screenshot on PR #32) ran past the bottom of the scrolling screen and failed
    /// this way intermittently. Every other issue, and contrast of any fully visible element,
    /// still fails the test.
    @MainActor
    private func auditScrollingScreen(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            guard issue.auditType == .contrast, let element = issue.element else { return false }
            return !app.frame.contains(element.frame)
        }
    }

    @MainActor
    func testPermissionCaptureAndFallbackPassAccessibilityAudits() throws {
        let app = launch("allow")
        let allow = app.buttons["Allow Camera Access"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()

        allow.tap()
        XCTAssertTrue(element(app, containing: "RAW · Single frame").waitForExistence(timeout: 10))
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Wide"].isSelected)
        XCTAssertEqual(app.otherElements["Viewfinder"].value as? String, "Lens: Wide. Format: single-frame RAW.")
        try app.performAccessibilityAudit()

        shutter.tap()
        XCTAssertTrue(
            app.staticTexts["Saved. Not signed: this development version can't sign photos yet."]
                .waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()

        let telephoto = app.buttons["Telephoto"]
        XCTAssertTrue(telephoto.exists)
        telephoto.tap()
        XCTAssertTrue(element(app, containing: "No RAW on This Lens").waitForExistence(timeout: 5))
        XCTAssertTrue(telephoto.isSelected)
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testInterruptionIsExplained() throws {
        let app = launch("interrupted")
        XCTAssertTrue(element(app, containing: "in use by another app or a call").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Take Photo"].isEnabled)
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testHeatPauseIsExplained() throws {
        let app = launch("hot")
        XCTAssertTrue(element(app, containing: "cool down").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Take Photo"].isEnabled)
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testCaptureFailureIsExplained() throws {
        let app = launch("captureFails")
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        XCTAssertTrue(app.staticTexts["The photo wasn't taken. Try again."].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testMetadataRejectionSavesNothingAndSaysSo() throws {
        let app = launch("metadataRejected")
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        XCTAssertTrue(
            app.staticTexts["Not saved: nope. couldn't confirm that the photo holds only the details you chose."]
                .waitForExistence(timeout: 5))
        XCTAssertTrue(shutter.isEnabled)
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testPhotosAccessDeniedIsExplained() throws {
        let app = launch("photosDenied")
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        XCTAssertTrue(
            app.staticTexts["Not saved: nope. isn't allowed to add photos. You can allow it in the Settings app."]
                .waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testSaveStatesAtTheLargestTextSize() throws {
        let app = launch(
            "metadataRejected",
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        XCTAssertTrue(element(app, containing: "Not saved").waitForExistence(timeout: 5))
        try auditScrollingScreen(app)
    }

    @MainActor
    func testBlankPictureExplainsRestartingTheDevice() throws {
        let app = launch("blankPicture")
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        XCTAssertTrue(element(app, containing: "isn't sending a picture").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, containing: "The camera isn't sending a picture").exists)
        XCTAssertTrue(app.staticTexts["No photo was taken: the camera sent a blank picture."].exists)
        XCTAssertFalse(shutter.isEnabled)
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testDeniedAndNoCameraStates() throws {
        let denied = launch("denied")
        XCTAssertTrue(denied.staticTexts["Camera Access Is Off"].waitForExistence(timeout: 10))
        try denied.performAccessibilityAudit()
        denied.terminate()

        let noCamera = launch("noCamera")
        XCTAssertTrue(noCamera.staticTexts["No Camera Available"].waitForExistence(timeout: 10))
        try noCamera.performAccessibilityAudit()
    }

    @MainActor
    func testLargestTextSize() throws {
        let app = launch(
            "interrupted",
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(element(app, containing: "in use by another app or a call").waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testBlankPictureAtTheLargestTextSize() throws {
        let app = launch(
            "blankPicture",
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        XCTAssertTrue(element(app, containing: "isn't sending a picture").waitForExistence(timeout: 10))
        try auditScrollingScreen(app)
    }

    @MainActor
    func testRightToLeftLayout() throws {
        let app = launch(
            "allow", extraArguments: ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"])
        let allow = app.buttons["Allow Camera Access"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10))
        allow.tap()
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }
}
