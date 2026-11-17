import XCTest

/// UI tests for the "Processed" marker of a lens without RAW, its processing note and its
/// Settings switch (issue #80), each with an accessibility audit at the default and largest text
/// sizes, in the dark setting, in night mode and in right-to-left layout.
extension NopeAppUITests {
    /// The first sentence of the processing note.
    private static let notePhone = "The phone's camera makes this photo"

    /// The note's line for a lens that lets the app turn off distortion correction (the
    /// simulated wide lens without RAW).
    private static let noteDistortionOff = "Distortion correction: this lens lets apps turn it off, and nope. does."

    /// The note's line for a lens that offers no switch (the simulated front camera without RAW).
    private static let noteDistortionMay = "doesn't let apps turn it off or report whether it's used"

    /// Opens the processing note from the marker and waits for its first sentence.
    @MainActor
    private func openProcessingNote(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let chip = app.buttons["Photo Format"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15), file: file, line: line)
        chip.tap()
        XCTAssertTrue(element(app, containing: Self.notePhone).waitForExistence(timeout: 5), file: file, line: line)
    }

    /// Swipes up in the open list until the element is on screen, at most eight times.
    ///
    /// - Returns: How many swipes it took.
    @MainActor
    @discardableResult
    private func swipeUntilHittable(_ app: XCUIApplication, _ element: XCUIElement) -> Int {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        return swipes
    }

    /// The Processed Marker switch in Settings.
    @MainActor
    private func markerSwitch(_ app: XCUIApplication) -> XCUIElement {
        app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Processed Marker")).firstMatch
    }

    /// Opens Settings and scrolls to the Processed Marker switch.
    ///
    /// - Returns: How many swipes it took.
    @MainActor
    @discardableResult
    private func openMarkerSwitch(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Int {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15), file: file, line: line)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), file: file, line: line)
        let swipes = swipeUntilHittable(app, markerSwitch(app))
        XCTAssertTrue(markerSwitch(app).exists, file: file, line: line)
        return swipes
    }

    @MainActor
    func testProcessedMarkerOpensTheLensProcessingNote() throws {
        let app = launch("noRAW")
        // The marker shows before the first photo, and VoiceOver names the processed format.
        XCTAssertTrue(formatChipValue(app, contains: "HEIF with some device processing"))
        openProcessingNote(app)
        XCTAssertTrue(element(app, containing: "turns off what apps can").exists)
        XCTAssertTrue(element(app, containing: Self.noteDistortionOff).exists)
        XCTAssertTrue(element(app, containing: "saves the camera's file without changing its pixels").exists)
        // As for the format sheet (testFormatChipExplainsTheFormat).
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        app.buttons["Done"].tap()

        // The front camera offers no switch for distortion correction.
        let flip = app.buttons["Switch Camera"]
        XCTAssertTrue(flip.waitForExistence(timeout: 10))
        flip.tap()
        XCTAssertTrue(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", "Lens: Front"), object: app.otherElements["Viewfinder"])],
                timeout: 10) == .completed)
        openProcessingNote(app)
        XCTAssertTrue(element(app, containing: Self.noteDistortionMay).exists)
        XCTAssertFalse(element(app, containing: Self.noteDistortionOff).exists)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testProcessedMarkerSwitchHidesOnlyTheMarker() throws {
        let app = launch("noRAW")
        XCTAssertTrue(formatChipValue(app, contains: "device processing"))
        let swipes = openMarkerSwitch(app)
        let marker = markerSwitch(app)
        XCTAssertEqual(marker.value as? String, "1")
        XCTAssertTrue(marker.label.contains("On by default."))
        try audit(app, afterScrolling: swipes > 0, checksDynamicType: false, checksContrast: !isPad)
        marker.switches.firstMatch.tap()
        XCTAssertEqual(marker.value as? String, "0")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Photo Format"].waitForExistence(timeout: 2))
        // VoiceOver still names the processed format, and the photo's details still say it.
        XCTAssertEqual(
            app.otherElements["Viewfinder"].value as? String, "Lens: Wide. Format: HEIF with some device processing.")
        try audit(app)
        openPhotoDetails(app)
        let line = element(app, containing: Self.noteDistortionOff)
        swipeUntilHittable(app, line)
        XCTAssertTrue(line.exists)
        XCTAssertTrue(element(app, containing: "this lens can't save RAW").exists)
    }

    @MainActor
    func testProcessedMarkerAndNoteAtTheLargestTextSize() throws {
        let app = launch("noRAW", extraArguments: Self.largestTextSize)
        XCTAssertTrue(formatChipValue(app, contains: "device processing"))
        try auditVisibleElements(app)
        openProcessingNote(app)
        try audit(app, checksContrast: !isPad)
        let last = element(app, containing: "saves the camera's file without changing its pixels")
        let swipes = swipeUntilHittable(app, last)
        XCTAssertTrue(last.exists)
        try audit(app, afterScrolling: swipes > 0, checksContrast: !isPad)
        app.buttons["Done"].tap()
        let switchSwipes = openMarkerSwitch(app)
        try audit(app, afterScrolling: switchSwipes > 0, checksContrast: !isPad)
    }

    @MainActor
    func testProcessedMarkerAndNoteInTheDarkSettingAndNightMode() throws {
        useAppearance(.dark)
        let dark = launch("noRAW")
        XCTAssertTrue(formatChipValue(dark, contains: "device processing"))
        try audit(dark)
        openProcessingNote(dark)
        try audit(dark, checksDynamicType: false, checksContrast: !isPad)
        dark.buttons["Done"].tap()
        let swipes = openMarkerSwitch(dark)
        try audit(dark, afterScrolling: swipes > 0, checksDynamicType: false, checksContrast: !isPad)
        dark.terminate()

        let night = launch("noRAW", extraArguments: Self.nightModeOn)
        XCTAssertTrue(formatChipValue(night, contains: "device processing"))
        try audit(night)
        openProcessingNote(night)
        try audit(night, checksDynamicType: false, checksContrast: !isPad)
        night.buttons["Done"].tap()
        let nightSwipes = openMarkerSwitch(night)
        try audit(night, afterScrolling: nightSwipes > 0, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testProcessedMarkerAndNoteRightToLeft() throws {
        let app = launch("noRAW", extraArguments: Self.rightToLeft)
        XCTAssertTrue(formatChipValue(app, contains: "device processing"))
        try audit(app)
        openProcessingNote(app)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        app.buttons["Done"].tap()
        let swipes = openMarkerSwitch(app)
        try audit(app, afterScrolling: swipes > 0, checksDynamicType: false, checksContrast: !isPad)
    }

    /// Waits for the format chip and returns whether its VoiceOver value contains the text.
    @MainActor
    private func formatChipValue(_ app: XCUIApplication, contains text: String) -> Bool {
        let chip = app.buttons["Photo Format"]
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: chip)], timeout: 15)
            == .completed
    }
}
