import XCTest

/// UI tests for the "Processed" marker of a lens without RAW, its processing note and its
/// Settings switch, Show Processed Marker (issue #80; BUILD-SPEC.md, 3.2), each with an accessibility audit at the default and largest text
/// sizes, in the dark setting, in night mode and in right-to-left layout.
extension NopeAppUITests {
    /// The first sentence of the processing note, which names the iPad on iPad.
    @MainActor
    private var notePhone: String {
        deviceText(
            "The phone's camera processes this file before nope. receives it.",
            iPad: "The iPad's camera processes this file before nope. receives it.")
    }

    /// The format status's VoiceOver value on the simulated lenses without RAW.
    private static let processedValue = "Processed: no RAW on this lens, HEIF"

    /// The processing note's last line, about the files nope. saves.
    private static let noteLast = "Nothing more to this lens's file."

    /// The note's line for a lens that lets the app turn off distortion correction (the
    /// simulated wide lens without RAW).
    private static let noteDistortionOff = "Distortion correction: this lens lets apps turn it off, and nope. does."

    /// The note's line for a lens that offers no switch (the simulated front camera without RAW).
    private static let noteDistortionMay = "doesn't let apps turn it off or report whether it's used"

    /// Opens the processing note from the marker and waits for its first sentence, scrolled into
    /// view at the largest text sizes (the list creates rows only as they scroll in).
    @MainActor
    private func openProcessingNote(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let chip = app.buttons["Photo Format"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15), file: file, line: line)
        chip.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), file: file, line: line)
        let note = element(app, containing: notePhone)
        swipeUntilHittable(app, note)
        XCTAssertTrue(note.exists, file: file, line: line)
    }

    /// Swipes up in the open list until the element is on screen or the list is at its end
    /// (``scrollSheet(_:to:)``: inside the popover on iPad, and without a cap of eight swipes,
    /// which ended inside the processing note at the largest text size on iPad).
    ///
    /// - Returns: How many swipes it took.
    @MainActor
    @discardableResult
    private func swipeUntilHittable(_ app: XCUIApplication, _ element: XCUIElement) -> Int {
        scrollSheet(app, to: element)
    }

    /// The Show Processed Marker switch in Settings.
    @MainActor
    private func markerSwitch(_ app: XCUIApplication) -> XCUIElement {
        app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Show Processed Marker")).firstMatch
    }

    /// Opens Settings and scrolls to the Show Processed Marker switch.
    ///
    /// - Returns: How many swipes it took.
    @MainActor
    @discardableResult
    private func openMarkerSwitch(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Int {
        openSettings(app, file: file, line: line)
        let swipes = swipeUntilHittable(app, markerSwitch(app))
        XCTAssertTrue(markerSwitch(app).exists, file: file, line: line)
        return swipes
    }

    @MainActor
    func testProcessedMarkerOpensTheLensProcessingNote() throws {
        let app = launch("noRAW")
        // The marker shows before the first photo, and VoiceOver names the processed format.
        XCTAssertTrue(formatChipValue(app, contains: Self.processedValue))
        XCTAssertTrue(app.buttons["FormatStatus.processedMarker"].exists)
        openProcessingNote(app)
        XCTAssertTrue(element(app, containing: Self.noteDistortionOff).exists)
        XCTAssertTrue(element(app, containing: Self.noteLast).exists)
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
        XCTAssertTrue(formatChipValue(app, contains: Self.processedValue))
        let swipes = openMarkerSwitch(app)
        let marker = markerSwitch(app)
        XCTAssertEqual(marker.value as? String, "1")
        // On by default; Settings no longer says so in words (BUILD-SPEC.md, section 4).
        XCTAssertFalse(marker.label.contains("On by default."))
        marker.switches.firstMatch.tap()
        XCTAssertEqual(marker.value as? String, "0")
        // The audit runs after the tap: on iPad, Settings is a popover over the camera, and the audit
        // can make the camera lay itself out again and scroll Settings, so a tap after it can miss.
        try audit(app, afterScrolling: swipes > 0, checksDynamicType: false, checksContrast: !isPad)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        // Only the marker goes: the status names the file without the triangle (BUILD-SPEC.md,
        // 3.2). VoiceOver still names the processed format, and the photo's details still say it.
        XCTAssertTrue(app.buttons["FormatStatus.processedName"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["FormatStatus.processedMarker"].exists)
        XCTAssertTrue(formatChipValue(app, contains: Self.processedValue))
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
        XCTAssertTrue(formatChipValue(app, contains: Self.processedValue))
        try auditVisibleElements(app)
        openProcessingNote(app)
        try audit(app, checksContrast: !isPad)
        let last = element(app, containing: Self.noteLast)
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
        XCTAssertTrue(formatChipValue(dark, contains: Self.processedValue))
        try audit(dark)
        openProcessingNote(dark)
        try audit(dark, checksDynamicType: false, checksContrast: !isPad)
        dark.buttons["Done"].tap()
        let swipes = openMarkerSwitch(dark)
        try audit(dark, afterScrolling: swipes > 0, checksDynamicType: false, checksContrast: !isPad)
        dark.terminate()

        let night = launch("noRAW", extraArguments: Self.nightModeOn)
        XCTAssertTrue(formatChipValue(night, contains: Self.processedValue))
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
        XCTAssertTrue(formatChipValue(app, contains: Self.processedValue))
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
