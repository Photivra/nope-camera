import XCTest

/// UI tests for the drive modes' cards on the picture's lower edge (docs/design/BUILD-SPEC.md,
/// 3.5; docs/design/drive.html): Timer and Burst running, Interval idle and running, Astro ready,
/// counting down and running, with an accessibility audit in each state, at the largest text
/// size, right to left and in night mode. They run on iPhone (stacked layout) and iPad (column
/// layout).
extension NopeAppUITests {
    /// The drive strip's word of that name: the lowest button with the label.
    @MainActor
    private func driveCardsWord(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", name))
        let lowest = matches.allElementsBoundByIndex.enumerated().max { $0.element.frame.minY < $1.element.frame.minY }
        return matches.element(boundBy: lowest?.offset ?? 0)
    }

    /// The mode card on screen.
    @MainActor
    private func modeCard(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "ModeCard").firstMatch
    }

    /// Waits until an element's value is the given text.
    @MainActor
    private func waitForCardValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// The share of the picture from the top of the card (or the element above it) down to the
    /// picture's lower edge: everything the bottom stack covers.
    @MainActor
    private func coveredShare(_ app: XCUIApplication, from top: CGFloat) -> CGFloat {
        let picture = app.otherElements["Viewfinder"].frame
        return max(picture.maxY - top, 0) / picture.height
    }

    /// Brightens the screen if a series dimmed it, so the card can be used.
    @MainActor
    private func brightenIfDimmed(_ app: XCUIApplication) {
        let brighten = app.buttons["Brighten Screen"]
        if brighten.waitForExistence(timeout: 3) {
            brighten.tap()
            _ = brighten.waitForNonExistence(timeout: 3)
        }
    }

    /// Interval: the idle card names the series and is the button Interval Settings.
    @MainActor
    func testIntervalCardOpensSettings() throws {
        let app = launch("noRAW")
        let interval = driveCardsWord(app, "Interval")
        XCTAssertTrue(interval.waitForExistence(timeout: 20))
        interval.tap()
        let card = app.buttons["Interval Settings"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForCardValue(card, "Every 10 seconds, 10 photos"))
        try audit(app)
        card.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // Clean view hides the idle card.
        app.otherElements["Viewfinder"].swipeUp()
        if app.buttons["Show Controls"].waitForExistence(timeout: 3) {
            XCTAssertFalse(card.exists)
            app.buttons["Show Controls"].tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5))
        }
    }

    /// Interval running: the count, the next photo's time, a progress bar and Stop; the screen
    /// dims and brightens; Stop returns to the idle card.
    @MainActor
    func testIntervalCardRunsAndStops() throws {
        let app = launch("noRAW")
        driveCardsWord(app, "Interval").tap()
        XCTAssertTrue(app.buttons["Interval Settings"].waitForExistence(timeout: 5))
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(element(app, containing: "photos taken").waitForExistence(timeout: 20))
        let brighten = app.buttons["Brighten Screen"]
        XCTAssertTrue(brighten.waitForExistence(timeout: 10))
        try audit(app)
        brighten.tap()
        XCTAssertFalse(brighten.waitForExistence(timeout: 2))
        XCTAssertTrue(element(app, containing: "Next photo in").waitForExistence(timeout: 15))
        XCTAssertTrue(element(app, containing: "of 10 photos taken").exists)
        // The other words are disabled while the series runs.
        XCTAssertFalse(driveCardsWord(app, "Single").isEnabled)
        try audit(app)
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.exists)
        stop.tap()
        XCTAssertFalse(element(app, containing: "photos taken").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Interval Settings"].waitForExistence(timeout: 5))
    }

    /// Timer: no card while idle (the shutter shows the delay); counting down, "Photo in" and
    /// Cancel Timer.
    @MainActor
    func testTimerCardCountsDown() throws {
        let app = launch("noRAW")
        driveCardsWord(app, "Timer").tap()
        let timer = driveCardsWord(app, "Timer")
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        XCTAssertFalse(modeCard(app).exists, "Timer has no idle card")
        // Ten seconds, so the countdown is still running after the audit.
        timer.tap()
        let ten = app.buttons["10 seconds"]
        XCTAssertTrue(ten.waitForExistence(timeout: 5))
        ten.tap()
        app.buttons["Take Photo"].tap()
        let cancel = app.buttons["Cancel Timer"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Photo in").exists)
        try audit(app)
        cancel.tap()
        XCTAssertFalse(cancel.waitForExistence(timeout: 3))
        XCTAssertFalse(modeCard(app).exists)
    }

    /// Burst: the idle card offers Start Burst; the count rises and Stop Burst stops it
    /// (docs/design/BURST.md).
    @MainActor
    func testBurstCardShowsCountAndStops() throws {
        let app = launch("slowSaving")
        driveCardsWord(app, "Burst").tap()
        XCTAssertTrue(modeCard(app).waitForExistence(timeout: 5), "Burst has an idle card")
        let start = app.buttons["Start Burst"]
        XCTAssertTrue(start.exists)
        start.tap()
        let stop = app.buttons["Stop Burst"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Photos taken").exists)
        try audit(app)
        stop.tap()
        XCTAssertFalse(stop.waitForExistence(timeout: 10))
    }

    /// Astro: the ready card is the button Astro Settings and, with the readouts, covers no
    /// more than a quarter of the picture; the start delay counts down on the card; the running
    /// card covers no more than a sixth; nothing is white in night mode.
    @MainActor
    func testAstroCardsCoverage() throws {
        let app = launch("astro", extraArguments: Self.nightModeOn)
        let astro = driveCardsWord(app, "Astro")
        XCTAssertTrue(astro.waitForExistence(timeout: 20))
        astro.tap()
        let card = app.buttons["Astro Settings"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue((card.value as? String)?.hasPrefix("Astro frames: 20") == true, "\(card.value ?? "")")
        XCTAssertLessThanOrEqual(coveredShare(app, from: card.frame.minY), 0.25)
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0, "white, blue or other colors remain")
        try audit(app)

        // Many frames, so the run outlasts the test, and a short start delay, so they start
        // during it.
        card.tap()
        for (picker, value) in [("Frames", "300"), ("Start Delay", "3 seconds")] {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", picker)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), picker)
            row.tap()
            let option = app.buttons[value].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5), value)
            option.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
        }
        let done = app.buttons["Done"]
        var swipes = 0
        while !(done.exists && done.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        done.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        app.buttons["Take Photo"].tap()
        XCTAssertTrue(element(app, containing: "First frame in").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Stop Frames"].exists)
        let running = element(app, containing: "Frame ")
        XCTAssertTrue(running.waitForExistence(timeout: 15))
        brightenIfDimmed(app)
        XCTAssertLessThanOrEqual(coveredShare(app, from: modeCard(app).frame.minY), 1.0 / 6.0)
        XCTAssertFalse(app.buttons["More Manual Controls"].exists, "the readouts step back during the run")
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0)
        try audit(app)
        app.buttons["Stop Frames"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
    }

    /// At the largest text size the camera scrolls; the cards are full width under the picture.
    @MainActor
    func testDriveCardsAtTheLargestTextSize() throws {
        let app = launch("noRAW", extraArguments: Self.largestTextSize)
        let interval = app.buttons["Interval"]
        XCTAssertTrue(interval.waitForExistence(timeout: 20))
        interval.tap()
        XCTAssertTrue(app.buttons["Interval Settings"].waitForExistence(timeout: 5))
        try auditScrollingScreen(app)
        // Ten seconds, so the countdown is still running after the audit.
        app.buttons["Timer"].tap()
        app.buttons["Timer"].tap()
        let ten = app.buttons["10 seconds"]
        XCTAssertTrue(ten.waitForExistence(timeout: 5))
        ten.tap()
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(app.buttons["Cancel Timer"].waitForExistence(timeout: 5))
        try auditScrollingScreen(app)
        let cancel = app.buttons["Cancel Timer"]
        if cancel.exists { cancel.tap() }
    }

    /// Right to left: the card's text leads from the right and Stop trails on the left.
    @MainActor
    func testDriveCardsRightToLeft() throws {
        let app = launch("noRAW", extraArguments: Self.rightToLeft)
        driveCardsWord(app, "Interval").tap()
        let card = app.buttons["Interval Settings"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        try audit(app)
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(element(app, containing: "photos taken").waitForExistence(timeout: 20))
        brightenIfDimmed(app)
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        let text = element(app, containing: "photos taken")
        XCTAssertLessThan(stop.frame.midX, text.frame.midX, "Stop trails on the left")
        try audit(app)
        stop.tap()
    }

    /// Night mode: the interval cards are red on black, outlined, and pass the audit.
    @MainActor
    func testDriveCardsNightMode() throws {
        let app = launch("noRAW", extraArguments: Self.nightModeOn)
        driveCardsWord(app, "Interval").tap()
        XCTAssertTrue(app.buttons["Interval Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0)
        try audit(app)
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(element(app, containing: "photos taken").waitForExistence(timeout: 20))
        brightenIfDimmed(app)
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0)
        try audit(app)
        app.buttons["Stop"].tap()
    }

    /// Sideways on an iPhone, the card turns upright with the rest of the bottom stack.
    @MainActor
    func testDriveCardsSideways() throws {
        guard !isPad else { throw XCTSkip("An iPad window rotates for real; the column layout covers it.") }
        let app = launch("noRAW")
        driveCardsWord(app, "Interval").tap()
        XCTAssertTrue(app.buttons["Interval Settings"].waitForExistence(timeout: 5))
        try turnSideways(app, mode: "Interval")
        defer { XCUIDevice.shared.orientation = .portrait }
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.height, window.width, "the iPhone camera layout turned")
        let card = app.buttons["Interval Settings"]
        XCTAssertTrue(card.exists)
        XCTAssertTrue(card.isHittable)
        // Text drawn a quarter turn is measured unturned by the audit (isTurnedTextFinding in
        // NopeAppUITests.swift); those findings are skipped, as in testCameraShellSideways.
        try app.performCompleteAccessibilityAudit { issue in
            guard let element = issue.element else { return issue.auditType == .textClipped || issue.auditType == .contrast }
            return issue.auditType == .contrast && element.exists && element.frame.height > element.frame.width
        }
    }
}
