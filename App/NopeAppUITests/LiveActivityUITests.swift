import XCTest

/// UI tests for the Live Activity (issue #64). XCTest can't reach the Lock Screen or the Dynamic
/// Island, so the layouts are audited in the app's Debug gallery (`-NopeLiveActivityGallery`),
/// which draws the same views as the NopeControls extension; the Settings switch is tested on the
/// camera's Settings screen.
extension NopeAppUITests {
    /// Launches the gallery of Live Activity layouts.
    @MainActor
    private func launchLiveActivityGallery(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NopeLiveActivityGallery"] + extraArguments
        app.launchAfterThePreviousRunExits()
        return app
    }

    /// Audits the gallery at its top and at its end.
    @MainActor
    private func auditLiveActivityGallery(_ app: XCUIApplication, checksDynamicType: Bool = true) throws {
        XCTAssertTrue(
            element(app, containing: "Paused: 42 of 120 photos taken. Open nope. to continue.").waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Stop"].firstMatch.exists, "Stop is offered while an interval series runs or is paused")
        try audit(app, checksDynamicType: checksDynamicType)
        let last = element(app, containing: "A photo wasn't saved. Open nope. for details.")
        var swipes = 0
        while !(last.exists && last.isHittable) && swipes < 40 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(last.exists)
        XCTAssertTrue(element(app, containing: "Not signed. Open nope. for details.").exists)
        try audit(app, afterScrolling: true, checksDynamicType: checksDynamicType)
    }

    @MainActor
    func testLiveActivityLayoutsPassAccessibilityAudits() throws {
        let app = launchLiveActivityGallery()
        XCTAssertTrue(element(app, containing: "Photo in").waitForExistence(timeout: 15))
        XCTAssertTrue(element(app, containing: "Frame 5 of 20").exists)
        try auditLiveActivityGallery(app)
        app.terminate()

        let large = launchLiveActivityGallery(Self.largestTextSize)
        try auditLiveActivityGallery(large)
        large.terminate()

        let rightToLeft = launchLiveActivityGallery(Self.rightToLeft)
        try auditLiveActivityGallery(rightToLeft, checksDynamicType: false)
        rightToLeft.terminate()

        let night = launchLiveActivityGallery(["-NopeLiveActivityGallery.night", "YES"])
        try auditLiveActivityGallery(night, checksDynamicType: false)
    }

    @MainActor
    func testLiveActivitySwitchIsOffByDefaultAndTurnsOn() throws {
        let app = launch("photosDenied")
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Live Activity")).firstMatch
        var swipes = 0
        while !(toggle.exists && toggle.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(toggle.exists, "Settings offers the Live Activity where the device shows them")
        XCTAssertEqual(toggle.value as? String, "0", "off by default")
        XCTAssertTrue(element(app, containing: "never sent anywhere").exists)
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        // Dynamic Type is checked at the largest size by the Settings audits
        // (testSettingsAtTheLargestTextSize), which include this switch.
        try audit(app, afterScrolling: true, checksDynamicType: false)
    }

    /// At the largest text size the explanation goes below the switch, at the row's full width:
    /// beside the switch it was a column 261 of 402 points wide and the row about 1,146 points
    /// tall. Below the switch the row is about 890 points tall on an iPhone 18 Pro.
    @MainActor
    func testLiveActivitySwitchAtTheLargestTextSize() throws {
        let app = launch("photosDenied", extraArguments: Self.largestTextSize)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Live Activity")).firstMatch
        var swipes = 0
        while !(toggle.exists && toggle.isHittable) && swipes < 20 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(toggle.exists)
        XCTAssertTrue(toggle.label.contains("never sent anywhere"), "the explanation is read with the switch")
        // The form's width: the window on iPhone, the Settings sheet on iPad.
        let form = app.navigationBars["Settings"].frame
        XCTAssertGreaterThan(toggle.frame.width, form.width * 0.8, "the explanation runs across the row")
        XCTAssertLessThan(toggle.frame.height, 1000, "the row is shorter than with the explanation beside the switch")
        XCTAssertEqual(toggle.value as? String, "0")
        // The switch itself, at the trailing end of the name; the text below it isn't a button.
        app.switches.matching(NSPredicate(format: "label == %@", "Live Activity")).firstMatch.switches.firstMatch.tap()
        XCTAssertTrue(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)], timeout: 5)
                == .completed)
        try audit(app, afterScrolling: true)
    }
}
