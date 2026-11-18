import XCTest

/// UI tests for focus bracketing (docs/design/BRACKETING.md, section 8): the Type control, the
/// range set on the picture, a series that runs, stops, pauses and ends, the viewer and What's in
/// This Photo, a lens whose focus can't be set, and the accessibility audit at the largest text
/// size, right to left, in night mode and on iPad.
extension NopeAppUITests {
    /// Chooses Bracket, then Focus in Bracket Settings, with no start delay and `frames` frames,
    /// and closes the sheet.
    @MainActor
    private func chooseFocusBracket(
        _ app: XCUIApplication, frames: String? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        chooseBracket(app, file: file, line: line)
        openBracketSettings(app, file: file, line: line)
        chooseFocusType(app, file: file, line: line)
        chooseInBracketSettings(app, "Start Delay", "Off", file: file, line: line)
        if let frames { chooseInBracketSettings(app, "Frames", frames, file: file, line: line) }
        closeBracketSettings(app)
        XCTAssertTrue(waitForValue(bracketCard(app), containing: "Focus bracket:"), file: file, line: line)
    }

    /// Chooses Focus in the Type control of the open Bracket Settings.
    @MainActor
    private func chooseFocusType(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let focus = app.segmentedControls.buttons["Focus"].exists
            ? app.segmentedControls.buttons["Focus"] : app.buttons.matching(NSPredicate(format: "label == %@", "Focus")).firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 5), "no Focus type", file: file, line: line)
        focus.tap()
        XCTAssertTrue(element(app, containing: "Focus Range").waitForExistence(timeout: 5), "no focus sections", file: file, line: line)
    }

    /// Taps Brighten Screen if the series has dimmed the screen.
    @MainActor
    private func brightenIfDimmed(_ app: XCUIApplication) {
        let brighten = app.buttons["Brighten Screen"]
        if brighten.waitForExistence(timeout: 2) { brighten.tap() }
    }

    /// Bracket Settings offers Type; Focus shows the range, frames, step, order, start delay,
    /// Return Focus When Done, storage and the Honesty sentences, and no distance. The idle card
    /// names the type, the frames and the range, with Nearest and Farthest.
    @MainActor
    func testBracketTypeFocus() throws {
        let app = launch("manual")
        chooseBracket(app)
        openBracketSettings(app)
        chooseFocusType(app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Nearest Focus")).firstMatch.exists)
        XCTAssertTrue(element(app, containing: "Focus Step").exists)
        XCTAssertTrue(element(app, containing: "doesn’t report focus as a distance").exists)
        XCTAssertFalse(element(app, containing: " cm").exists, "a distance is shown")
        let returns = app.switches["Return Focus When Done"]
        scrollUntilHittable(app, returns)
        XCTAssertEqual(returns.value as? String, "1")
        XCTAssertTrue(element(app, containing: "Stack them in other software").exists)
        try auditBracketSettings(app, afterScrolling: true)
        closeBracketSettings(app)
        let card = bracketCard(app)
        XCTAssertTrue(waitForValue(card, containing: "Focus bracket: 10 frames"))
        XCTAssertTrue(waitForValue(card, containing: "Focus 0.00 to 1.00, nearest first"))
        XCTAssertEqual(app.buttons["Nearest Focus"].value as? String, "0.00")
        XCTAssertEqual(app.buttons["Farthest Focus"].value as? String, "1.00")
        XCTAssertTrue(waitForValue(app.buttons["Take Photo"], containing: "Bracket, focus, 10 frames"))
        // The idle card covers no more than 30% of the picture.
        let top = app.descendants(matching: .any).matching(identifier: "ModeCard").firstMatch.frame.minY
        XCTAssertLessThanOrEqual(pictureShareFromCard(app, top: top), 0.3)
        try audit(app)
    }

    /// Nearest Focus opens the dial on the picture; Increase moves it in steps of 0.01 and Set
    /// keeps it; Cancel leaves the range as it was.
    @MainActor
    func testFocusRangeSetOnThePicture() throws {
        let app = launch("manual")
        chooseFocusBracket(app)
        app.buttons["Nearest Focus"].tap()
        let dial = app.descendants(matching: .any)["FocusRangeDial"]
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Tap the nearest thing you want sharp").exists)
        for _ in 0..<3 { app.buttons["Increase"].tap() }
        XCTAssertTrue(element(app, containing: "0.03").waitForExistence(timeout: 5))
        try audit(app)
        app.buttons["Set Nearest Focus"].tap()
        XCTAssertTrue(app.buttons["Nearest Focus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Nearest Focus"].value as? String, "0.03")
        app.buttons["Farthest Focus"].tap()
        XCTAssertTrue(app.buttons["Set Farthest Focus"].waitForExistence(timeout: 5))
        app.buttons["Decrease"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Farthest Focus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Farthest Focus"].value as? String, "1.00")
    }

    /// The shutter starts the series; the card counts the frames with the focus the lens reports
    /// and has Stop Bracket; Stop keeps every photo taken and the end card says how many.
    @MainActor
    func testFocusBracketRunsAndStops() throws {
        // Each save takes half a second here.
        let app = launch("astro")
        chooseFocusBracket(app, frames: "20")
        app.buttons["Take Photo"].tap()
        brightenIfDimmed(app)
        let stop = app.buttons["Stop Bracket"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, containing: "Frame ").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Focus 0.").exists)
        XCTAssertTrue(waitForValue(app.buttons["Take Photo"], containing: "Press to stop"))
        XCTAssertFalse(bracketWord(app, "Single").isEnabled, "the other words are dimmed")
        try audit(app, checksContrast: false)
        stop.tap()
        XCTAssertTrue(element(app, containing: "Bracket stopped:").waitForExistence(timeout: 15))
        XCTAssertTrue(element(app, containing: "of 20 photos saved").exists)
        XCTAssertTrue(element(app, containing: "Focus is back to Auto").exists)
        XCTAssertTrue(bracketLastPhoto(app, says: "Saved"))
    }

    /// Leaving the app pauses the series; it continues on return and finishes.
    @MainActor
    func testFocusBracketPausesAndContinues() throws {
        let app = launch("astro")
        chooseFocusBracket(app, frames: "12")
        app.buttons["Take Photo"].tap()
        brightenIfDimmed(app)
        XCTAssertTrue(app.buttons["Stop Bracket"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackgroundSuspended, timeout: 10) || app.state == .runningBackground)
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Away from the app")], timeout: 3)
        app.activate()
        brightenIfDimmed(app)
        XCTAssertTrue(element(app, containing: "12 photos saved").waitForExistence(timeout: 40), "the series didn't continue")
    }

    /// The end cards: every photo saved, and the frames whose focus the lens reported off their
    /// plan counted (the `focusShort` lens stops 0.05 short).
    @MainActor
    func testFocusBracketEndCards() throws {
        let app = launch("focusShort")
        chooseFocusBracket(app, frames: "3")
        app.buttons["Take Photo"].tap()
        brightenIfDimmed(app)
        XCTAssertTrue(element(app, containing: "3 photos saved").waitForExistence(timeout: 20))
        XCTAssertTrue(element(app, containing: "frames were not at their planned focus").exists)
        XCTAssertTrue(element(app, containing: "Focus is back to Auto").exists)
        try audit(app)
    }

    /// A lens whose focus can't be set: with the focus bracket on, switching to it turns
    /// Bracket off and selects Single; a lens that can only take a focus bracket has the Type
    /// control dimmed on Focus.
    @MainActor
    func testFocusNotOfferedWithoutManualFocus() throws {
        let app = launch("manual")
        chooseFocusBracket(app)
        let flip = app.buttons["Switch Camera"]
        XCTAssertTrue(flip.waitForExistence(timeout: 5))
        flip.tap()
        XCTAssertTrue(bracketWord(app, "Single").waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(10)
        while bracketWord(app).exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertFalse(bracketWord(app).exists, "the front camera's focus can't be set")
        XCTAssertTrue(bracketWord(app, "Single").isSelected)
        // The aid lenses take no exposure bracket but can take a focus bracket.
        let aids = launch("aids")
        chooseBracket(aids)
        XCTAssertTrue(waitForValue(bracketCard(aids), containing: "Focus bracket:"))
        openBracketSettings(aids)
        XCTAssertFalse(aids.segmentedControls.firstMatch.isEnabled, "the Type control isn't dimmed")
        try auditBracketSettings(aids)
    }

    /// Each frame is a page of the viewer with its chip, and What's in This Photo shows the focus
    /// the lens reported and the planned focus.
    @MainActor
    func testFocusBracketViewerAndDetails() throws {
        let app = launch("manual")
        chooseFocusBracket(app, frames: "3")
        openPhotoDetails(app)
        XCTAssertTrue(element(app, containing: "Planned Focus").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Reported by the lens").exists)
        XCTAssertTrue(element(app, containing: "not a distance").exists)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        app.buttons["Done"].firstMatch.tap()
        let photo = app.descendants(matching: .any)["ViewerPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["BracketChip"].waitForExistence(timeout: 5))
        XCTAssertTrue(photo.label.contains("Focus bracket, frame 3 of 3, focus 1.00."), photo.label)
    }

    /// At the largest text size the card's buttons stack, the track is left out, and Bracket
    /// Settings wraps each value; both pass the audit.
    @MainActor
    func testFocusBracketAtTheLargestTextSize() throws {
        let app = launch("manual", extraArguments: Self.largestTextSize)
        let word = app.buttons["Bracket"]
        XCTAssertTrue(word.waitForExistence(timeout: 20))
        scrollUntilHittable(app, word)
        word.tap()
        let card = bracketCard(app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        scrollUntilHittable(app, card)
        card.tap()
        XCTAssertTrue(app.navigationBars["Bracket Settings"].waitForExistence(timeout: 5))
        chooseFocusType(app)
        try audit(app)
        closeBracketSettings(app)
        XCTAssertTrue(waitForValue(bracketCard(app), containing: "Focus bracket:"))
        try auditScrollingScreen(app)
    }

    /// Right to left: the card, the dial and Bracket Settings mirror and pass the audit.
    @MainActor
    func testFocusBracketRightToLeft() throws {
        let app = launch("manual", extraArguments: Self.rightToLeft)
        chooseFocusBracket(app)
        try audit(app)
        app.buttons["Farthest Focus"].tap()
        XCTAssertTrue(app.buttons["Set Farthest Focus"].waitForExistence(timeout: 5))
        try audit(app)
        app.buttons["Cancel"].tap()
        openBracketSettings(app)
        try auditBracketSettings(app)
    }

    /// Night mode: the card, the track, the dial and Bracket Settings are red on black; the
    /// marks differ by fill, not color.
    @MainActor
    func testFocusBracketNightMode() throws {
        let app = launch("manual", extraArguments: Self.nightModeOn)
        chooseFocusBracket(app)
        let viewfinderFrame = app.otherElements["Viewfinder"].frame
        XCTAssertEqual(bracketNonRedPixels(app, outside: viewfinderFrame), 0, "white, blue or other colors remain")
        try audit(app)
        app.buttons["Nearest Focus"].tap()
        XCTAssertTrue(app.buttons["Set Nearest Focus"].waitForExistence(timeout: 5))
        XCTAssertEqual(bracketNonRedPixels(app, outside: viewfinderFrame), 0, "the dial isn't all red")
        app.buttons["Cancel"].tap()
        openBracketSettings(app)
        settle()
        XCTAssertEqual(bracketNonRedPixels(app, outside: viewfinderFrame), 0, "Bracket Settings isn't all red")
        try auditBracketSettings(app)
    }

    /// On iPad the card sits on the picture's lower edge and Bracket Settings is a centered
    /// sheet; a series runs and ends.
    @MainActor
    func testFocusBracketOnIPad() throws {
        guard isPad else { throw XCTSkip("The iPad layout; the iPhone tests cover the stacked layout.") }
        let app = launch("manual")
        chooseFocusBracket(app, frames: "3")
        try audit(app)
        openBracketSettings(app)
        try auditBracketSettings(app)
        closeBracketSettings(app)
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(element(app, containing: "3 photos saved").waitForExistence(timeout: 20))
    }

    /// The share of the picture from a card's top down to the picture's lower edge.
    @MainActor
    private func pictureShareFromCard(_ app: XCUIApplication, top: CGFloat) -> CGFloat {
        let picture = app.otherElements["Viewfinder"].frame
        return max(picture.maxY - top, 0) / picture.height
    }
}
