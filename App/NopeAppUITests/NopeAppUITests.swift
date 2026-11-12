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
        XCTAssertTrue(app.staticTexts["Captured (not saved yet: development build)"].waitForExistence(timeout: 5))
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
        // Wait for the capture message too, so the audit doesn't measure it while it changes.
        XCTAssertTrue(
            app.staticTexts["No photo was taken: the camera sent a blank picture."].waitForExistence(timeout: 10))
        try auditVisibleElements(app)
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

    // MARK: - Manual controls

    /// The launch arguments that turn the "Manual controls" option on.
    private static let manualOn = ["-manualControlsEnabled", "YES"]

    @MainActor
    func testManualControlsAreHiddenByDefault() throws {
        let app = launch("manual")
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Pro Tools"].exists)
        XCTAssertFalse(app.buttons["Shutter"].exists)
        XCTAssertFalse(app.buttons["All Auto"].exists)
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testControlGridPanelAndAllAuto() throws {
        let app = launch("manual", extraArguments: Self.manualOn)
        let iso = app.buttons["ISO"]
        XCTAssertTrue(iso.waitForExistence(timeout: 10))
        for name in ["Exposure Compensation", "Shutter", "Aperture", "Focus", "White Balance"] {
            XCTAssertTrue(app.buttons[name].exists, name)
        }
        XCTAssertTrue((iso.value as? String)?.hasPrefix("Auto") ?? false)
        XCTAssertFalse(app.buttons["All Auto"].exists)
        try app.performAccessibilityAudit()

        // The panel replaces the lens buttons while it is open; Manual fixes the value in use.
        iso.tap()
        XCTAssertTrue(element(app, containing: "This lens:").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Wide"].exists)
        app.segmentedControls["panel-mode"].buttons["Manual"].tap()
        XCTAssertTrue(app.buttons["All Auto"].waitForExistence(timeout: 5))
        XCTAssertTrue((iso.value as? String)?.hasPrefix("Manual") ?? false)
        try app.performAccessibilityAudit()

        app.buttons["All Auto"].tap()
        XCTAssertTrue(app.buttons["Wide"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["All Auto"].exists)
        XCTAssertTrue((iso.value as? String)?.hasPrefix("Auto") ?? false)
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testExposureModesAndFixedAperture() throws {
        let app = launch("manual", extraArguments: Self.manualOn)
        let manual = app.segmentedControls["exposure-mode"].buttons["Manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 10))
        manual.tap()
        XCTAssertTrue((app.buttons["Shutter"].value as? String)?.hasPrefix("Manual") ?? false)
        app.buttons["Exposure Compensation"].tap()
        XCTAssertTrue(element(app, containing: "works only while ISO or the shutter is on Auto").waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()

        app.buttons["All Auto"].tap()
        app.buttons["Ultra Wide"].tap()
        let aperture = app.buttons["Aperture"]
        XCTAssertTrue(aperture.waitForExistence(timeout: 5))
        XCTAssertTrue((aperture.value as? String)?.hasPrefix("Fixed") ?? false)
        aperture.tap()
        XCTAssertTrue(app.staticTexts["This lens has a fixed aperture."].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    /// Audits the elements inside the window. In a scrolling screen the audit also measures
    /// elements scrolled out of the window, against whatever is drawn there (a blank
    /// screenshot), so issues on an element outside the window are skipped.
    ///
    /// - Parameter skipDynamicType: Also skips Dynamic Type reports. Pro Tools needs it: the audit
    ///   reports a different `Form` row of the interval section on each run, which it pushes out
    ///   of the window while enlarging the text; `testProToolsGrowsWithTheLargestTextSize`
    ///   measures that those rows do grow.
    @MainActor
    private func auditVisibleElements(_ app: XCUIApplication, skipDynamicType: Bool = false) throws {
        let window = app.windows.firstMatch.frame
        try app.performAccessibilityAudit { issue in
            if skipDynamicType, issue.auditType == .dynamicType { return true }
            guard let element = issue.element else { return false }
            return !window.contains(element.frame)
        }
    }

    /// Audits Pro Tools (see ``auditVisibleElements(_:skipDynamicType:)``).
    @MainActor
    private func auditProTools(_ app: XCUIApplication) throws {
        try auditVisibleElements(app, skipDynamicType: true)
    }

    /// The height of a Pro Tools row's text, scrolling down to it if needed.
    @MainActor
    private func rowTextHeight(_ app: XCUIApplication, _ label: String) -> CGFloat {
        let text = app.staticTexts[label]
        var swipes = 0
        let window = app.windows.firstMatch.frame
        while !(text.exists && window.contains(text.frame)), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(text.exists, label)
        return text.frame.height
    }

    @MainActor
    func testProToolsBracketing() throws {
        let app = launch("manual", extraArguments: Self.manualOn)
        let tools = app.buttons["Pro Tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        tools.tap()
        let bracketing = app.switches["Bracketing"]
        XCTAssertTrue(bracketing.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Each frame is a separate single-frame photo. Nothing is merged."].exists)
        try auditProTools(app)
        bracketing.switches.firstMatch.tap()
        XCTAssertTrue(element(app, containing: "Frames").waitForExistence(timeout: 5))
        try auditProTools(app)
        app.buttons["Done"].tap()

        app.buttons["Take Photo"].tap()
        XCTAssertTrue(
            app.staticTexts["3 photos captured (not saved yet: development build)"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testIntervalShootingShowsProgressAndStops() throws {
        let app = launch("manual", extraArguments: Self.manualOn)
        let tools = app.buttons["Pro Tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        tools.tap()
        let start = app.buttons["Start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(element(app, containing: "photos taken").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Captured (not saved yet: development build)"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
        app.buttons["Stop"].tap()
        XCTAssertFalse(element(app, containing: "photos taken").waitForExistence(timeout: 2))
    }

    @MainActor
    func testCleanViewHidesControlsButKeepsTheShutter() throws {
        let app = launch("manual", extraArguments: Self.manualOn)
        let hide = app.buttons["Hide Controls"]
        XCTAssertTrue(hide.waitForExistence(timeout: 10))
        hide.tap()
        XCTAssertTrue(app.buttons["Show Controls"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Take Photo"].exists)
        XCTAssertFalse(app.buttons["Wide"].exists)
        XCTAssertFalse(app.buttons["ISO"].exists)
        XCTAssertFalse(element(app, containing: "RAW · Single frame").exists)
        try app.performAccessibilityAudit()
        app.buttons["Show Controls"].tap()
        XCTAssertTrue(app.buttons["Wide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ISO"].exists)
    }

    @MainActor
    func testCleanViewKeepsTheNoRAWWarning() throws {
        let app = launch("allow")
        app.buttons["Allow Camera Access"].tap()
        let telephoto = app.buttons["Telephoto"]
        XCTAssertTrue(telephoto.waitForExistence(timeout: 10))
        telephoto.tap()
        app.buttons["Hide Controls"].tap()
        XCTAssertTrue(element(app, containing: "No RAW on This Lens").waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testManualControlsListAtTheLargestTextSize() throws {
        let app = launch(
            "manual",
            extraArguments: Self.manualOn + [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ])
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.steppers.firstMatch.waitForExistence(timeout: 5))
        try auditVisibleElements(app)
    }

    @MainActor
    func testManualControlsRightToLeft() throws {
        let app = launch(
            "manual",
            extraArguments: Self.manualOn + ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"])
        XCTAssertTrue(app.buttons["ISO"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testProToolsGrowsWithTheLargestTextSize() throws {
        let labels = ["Metering", "Interval", "Photos"]
        let regular = launch("manual", extraArguments: Self.manualOn)
        XCTAssertTrue(regular.buttons["Pro Tools"].waitForExistence(timeout: 10))
        regular.buttons["Pro Tools"].tap()
        XCTAssertTrue(regular.staticTexts["Metering"].waitForExistence(timeout: 5))
        let regularHeights = labels.map { rowTextHeight(regular, $0) }
        regular.terminate()

        let large = launch(
            "manual",
            extraArguments: Self.manualOn + [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ])
        let tools = large.buttons["Pro Tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        tools.tap()
        XCTAssertTrue(large.staticTexts["Metering"].waitForExistence(timeout: 5))
        for (label, regularHeight) in zip(labels, regularHeights) {
            XCTAssertGreaterThan(rowTextHeight(large, label), regularHeight * 2, label)
        }
        try auditProTools(large)
    }
}
