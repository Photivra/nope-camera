import XCTest

/// UI tests for the comparison shot (issue #55) against the simulated backend: the Compare switch,
/// its pill and hint, the compare view's pictures and its details list, the failure of the second
/// photo, and accessibility audits of each state at the default and largest text sizes,
/// right-to-left and in night mode.
extension NopeAppUITests {
    /// Allows the camera in the `allow` scenario and waits for the shutter.
    @MainActor
    private func allowCamera(_ app: XCUIApplication) {
        let allow = app.buttons["Continue"]
        if allow.waitForExistence(timeout: 10) { allow.tap() }
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 20))
    }

    /// Turns Compare on from Q, closes Q (its panel covers the hints on the picture's lower
    /// edge), checks the hint, and takes the photos.
    @MainActor
    private func takeComparisonShot(_ app: XCUIApplication) {
        quickControl(app, "Compare")
        closeTray(app)
        XCTAssertTrue(
            element(app, containing: "Two photos are taken, a moment apart.").waitForExistence(timeout: 5))
        app.buttons["Take Photo"].tap()
    }

    /// Waits for the compare view's Pictures tab.
    @MainActor
    private func waitForPictures(_ app: XCUIApplication) -> XCUIElement {
        let picture = app.descendants(matching: .any)["ComparisonPicture"]
        XCTAssertTrue(picture.waitForExistence(timeout: 20))
        return picture
    }

    /// Closes the compare view with Done and waits until it is gone.
    @MainActor
    private func closeComparison(_ app: XCUIApplication) {
        let view = app.descendants(matching: .any)["Comparison"]
        app.navigationBars.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(view.waitForNonExistence(timeout: 10), app.debugDescription)
        // The camera's elements come back once the dismissal has finished.
        settle()
    }

    /// RAW only, the default (issue #80): the compare view shows the DNG next to the phone's
    /// version, and its details compare the DNG's metadata.
    @MainActor
    func testComparisonOfARAWOnlyPhotoPassesTheAudit() throws {
        let app = launch("allow")
        allowCamera(app)
        takeComparisonShot(app)
        _ = waitForPictures(app)
        try audit(app)
        app.buttons["Details"].tap()
        XCTAssertTrue(app.staticTexts[deviceText("Only in Phone Version", iPad: "Only in iPad Version")].waitForExistence(timeout: 5))
        try audit(app)
        closeComparison(app)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testComparisonShotShowsBothPicturesAndTheirDetails() throws {
        let app = launch("allow")
        allowCamera(app)
        takeComparisonShot(app)
        let picture = waitForPictures(app)
        XCTAssertTrue(app.staticTexts[deviceText("Phone Processing", iPad: "iPad Processing")].exists)
        XCTAssertTrue(element(app, containing: "Not saved: it is discarded when you close this view.").exists)
        XCTAssertEqual(picture.value as? String, deviceText("Split: 50% nope., 50% phone processing", iPad: "Split: 50% nope., 50% iPad processing"))
        XCTAssertTrue(app.buttons["Split"].isSelected)
        try audit(app)

        // The divider has a slider (and is adjustable with VoiceOver), and each full picture has
        // its own button.
        app.sliders["Divider"].adjust(toNormalizedSliderPosition: 0.8)
        // The picture's value follows the slider a moment later; on the CI runner it was read
        // before it had changed.
        XCTAssertTrue(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", "Split: 8"), object: picture)],
                timeout: 10) == .completed,
            String(describing: picture.value))
        app.buttons["nope. Only"].tap()
        XCTAssertTrue(app.buttons["nope. Only"].isSelected)
        XCTAssertEqual(picture.value as? String, "nope. Only")
        let phoneOnly = deviceText("Phone Only", iPad: "iPad Only")
        app.buttons[phoneOnly].tap()
        XCTAssertEqual(picture.value as? String, phoneOnly)
        app.buttons["Zoom In"].tap()
        XCTAssertEqual(app.buttons["Zoom Out"].value as? String, "2×")
        try audit(app)

        // The metadata, grouped, with the identifying value hidden until asked.
        app.buttons["Details"].tap()
        XCTAssertTrue(app.staticTexts[deviceText("Only in Phone Version", iPad: "Only in iPad Version")].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Make").exists)
        try audit(app)
        let uniqueID = element(app, containing: "ImageUniqueID")
        let show = app.buttons["Show Value"].firstMatch
        // Slow drags that hold at the end, not swipes: a swipe's fling kept the list moving, so on
        // the iPad runner Show Value was found hittable and had scrolled away when it was tapped.
        func scrollToShowValue() {
            var drags = 0
            while !(uniqueID.exists && show.exists && show.isHittable) && drags < 12 {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                start.press(
                    forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -250)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
                drags += 1
            }
            settle()
        }
        scrollToShowValue()
        XCTAssertTrue(show.isHittable, "Show Value isn't on screen")
        XCTAssertFalse(element(app, containing: "0A1B2C3D4E5F6071").exists)
        try audit(app, afterScrolling: true)
        // The audit can scroll the list while it measures; Show Value is brought back first.
        scrollToShowValue()
        show.tap()
        XCTAssertTrue(element(app, containing: "0A1B2C3D4E5F6071").waitForExistence(timeout: 5))

        // Done discards the comparison. That only nope.'s photo is saved is checked by the unit
        // tests (ComparisonTests), which see what reaches the library.
        closeComparison(app)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["ComparisonPicture"].exists)

        // The pill turns Compare off, and the hint goes with it.
        app.buttons["Compare"].firstMatch.tap()
        let turnOff = app.buttons["Turn Off Compare"]
        if turnOff.waitForExistence(timeout: 3) { turnOff.tap() }
        XCTAssertFalse(element(app, containing: "Two photos are taken, a moment apart.").waitForExistence(timeout: 3))
    }

    @MainActor
    func testCompareViewAtTheLargestTextSizeAndRightToLeft() throws {
        for arguments in [Self.largestTextSize, Self.rightToLeft] {
            let app = launch("allow", extraArguments: arguments)
            allowCamera(app)
            takeComparisonShot(app)
            _ = waitForPictures(app)
            try audit(app, afterScrolling: true)
            app.buttons["Details"].tap()
            XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
            try audit(app, afterScrolling: true)
            app.terminate()
        }
    }

    @MainActor
    func testFailedSecondPhotoIsExplainedAndNopesPhotoIsSaved() throws {
        let app = launch("comparisonFails", extraArguments: Self.nightModeOn)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 20))
        takeComparisonShot(app)
        XCTAssertTrue(app.staticTexts["Nothing to Compare"].waitForExistence(timeout: 20))
        XCTAssertTrue(element(app, containing: "Your nope. photo was saved.").exists)
        try audit(app)
        closeComparison(app)
    }

    @MainActor
    func testHonestyScreenSaysTheComparisonPhotoIsNeverSaved() throws {
        let app = launch("denied")
        openSettings(app)
        let honesty = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Honesty")).firstMatch
        var rowSwipes = 0
        while !honesty.isHittable && rowSwipes < 8 {
            app.swipeUp()
            rowSwipes += 1
        }
        honesty.tap()
        let statement = element(app, containing: "The Comparison Photo Is Never Saved")
        var swipes = 0
        while !statement.exists && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(statement.exists)
    }
}
