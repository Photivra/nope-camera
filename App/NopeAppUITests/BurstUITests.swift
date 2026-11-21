import XCTest

/// UI tests for Burst as continuous shooting (docs/design/BURST.md; docs/design/burst.html): a
/// tap takes one photo, holding the shutter takes photos until it is let go, Start Burst runs a
/// burst without holding, the speed menu, the cards while held, saving and after, and the
/// shutter's VoiceOver value, hint and action. Each state is audited, also at the largest text
/// size, right to left, in night mode, sideways and on iPad. The `burst` scenario's camera takes
/// 0.4 s for each photo and its saves 0.5 s, so a tap ends before a second photo.
extension NopeAppUITests {
    /// The drive strip's word of that name: the lowest button with the label.
    @MainActor
    private func burstStripWord(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", name))
        let lowest = matches.allElementsBoundByIndex.enumerated().max { $0.element.frame.minY < $1.element.frame.minY }
        return matches.element(boundBy: lowest?.offset ?? 0)
    }

    /// Launches the burst scenario and chooses Burst on the strip.
    @MainActor
    private func launchBurst(extraArguments: [String] = []) -> XCUIApplication {
        let app = launch("burst", extraArguments: extraArguments)
        let word = burstStripWord(app, "Burst")
        XCTAssertTrue(word.waitForExistence(timeout: 20))
        word.tap()
        let selected = app.buttons.matching(NSPredicate(format: "label == %@ AND selected == YES", "Burst")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        return app
    }

    /// Waits until an element's value contains the text.
    @MainActor
    private func burstWaitForValue(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// The idle card: the speed, what the shutter does and Start Burst; it covers no more than a
    /// quarter of the picture.
    @MainActor
    func testBurstIdleCardShowsSpeedAndStart() throws {
        let app = launchBurst()
        XCTAssertTrue(element(app, containing: "Fast burst").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Hold the shutter. A tap takes one photo.").exists)
        let start = app.buttons["Start Burst"]
        XCTAssertTrue(start.exists)
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        let picture = app.otherElements["Viewfinder"].frame
        let card = app.descendants(matching: .any).matching(identifier: "ModeCard").firstMatch
        if !isPad {
            XCTAssertLessThanOrEqual(max(picture.maxY - card.frame.minY, 0) / picture.height, 0.25)
        }
        try audit(app)
    }

    /// A tap takes one photo: no summary, and the photo reads as a single photo.
    @MainActor
    func testBurstTapTakesOnePhoto() throws {
        let app = launchBurst(extraArguments: Self.signingOn)
        app.buttons["Take Photo"].tap()
        let lastPhoto = app.descendants(matching: .any)["Last Photo"]
        XCTAssertTrue(burstWaitForValue(lastPhoto, containing: "Saved and signed."))
        XCTAssertFalse((lastPhoto.value as? String)?.contains("photos saved") == true)
        XCTAssertFalse(element(app, containing: "photos saved").waitForExistence(timeout: 2), "one photo has no summary")
        XCTAssertTrue(element(app, containing: "Fast burst").exists, "the idle card is back")
        try audit(app)
    }

    /// Holding the shutter takes photos until it is let go, then the summary stays, with the
    /// count, the time and the measured rate. XCUITest can't look at the screen while a press
    /// lasts, so "Release to stop" and the missing Stop Burst while held are covered by the unit
    /// tests of the card (`burstRunningDetail`, the running card's accessory).
    @MainActor
    func testBurstHoldTakesPhotosUntilRelease() throws {
        let app = launchBurst(extraArguments: Self.signingOn)
        let shutter = app.buttons["Take Photo"]
        shutter.press(forDuration: 3.5)
        let summary = element(app, containing: "photos saved")
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(photosSaved(summary) ?? 0, 3, summary.label)
        XCTAssertTrue(summary.label.contains("a second"), summary.label)
        XCTAssertFalse(app.buttons["Stop Burst"].exists)
        let lastPhoto = app.descendants(matching: .any)["Last Photo"]
        XCTAssertTrue(burstWaitForValue(lastPhoto, containing: "photos saved and signed."))
        XCTAssertTrue(shutter.isEnabled)
        try audit(app)
    }

    /// Sliding the finger off the shutter ends the burst, though the finger stays down.
    @MainActor
    func testBurstSlideOffStops() throws {
        let app = launchBurst()
        let shutter = app.buttons["Take Photo"]
        let start = shutter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let away = start.withOffset(CGVector(dx: 0, dy: -250))
        // Off the shutter within half a second, then held there for three seconds: about six
        // more photos if sliding off didn't stop the burst.
        start.press(forDuration: 0.3, thenDragTo: away, withVelocity: .fast, thenHoldForDuration: 3)
        let summary = element(app, containing: "photos saved")
        let saved = summary.waitForExistence(timeout: 10) ? photosSaved(summary) : 1
        XCTAssertLessThanOrEqual(saved ?? 0, 3, summary.label)
    }

    /// The count of a summary card, from "12 photos saved", or `nil`.
    @MainActor
    private func photosSaved(_ summary: XCUIElement) -> Int? {
        Int(summary.label.prefix { $0.isNumber })
    }

    /// Start Burst: the stop square, Stop Burst, "Burst started." for VoiceOver; Stop Burst
    /// ends it, then the summary; the shutter also stops one.
    @MainActor
    func testBurstStartButtonRunsAndStops() throws {
        let app = launchBurst()
        let shutter = app.buttons["Take Photo"]
        app.buttons["Start Burst"].tap()
        let stop = app.buttons["Stop Burst"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(burstWaitForValue(shutter, containing: "Taking a burst. Press to stop."))
        XCTAssertTrue(element(app, containing: "a second").waitForExistence(timeout: 10), "the measured rate from the third photo")
        XCTAssertFalse(app.buttons["Interval"].isEnabled, "the other words are disabled")
        try audit(app)
        stop.tap()
        XCTAssertFalse(stop.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, containing: "photos saved").waitForExistence(timeout: 15))
        // The shutter stops a started burst too.
        app.buttons["Start Burst"].tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        shutter.tap()
        XCTAssertFalse(stop.waitForExistence(timeout: 10))
    }

    /// The selected Burst word opens the speed menu; Slow changes the card's title, the strip's
    /// value and the shutter's value.
    @MainActor
    func testBurstSpeedMenu() throws {
        let app = launchBurst()
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(burstWaitForValue(shutter, containing: "Burst, fast."))
        let word = burstStripWord(app, "Burst")
        XCTAssertEqual(word.value as? String, "Fast")
        word.tap()
        let slow = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Slow")).firstMatch
        XCTAssertTrue(slow.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "As fast as the camera is ready").exists)
        XCTAssertTrue(element(app, containing: "Up to 2 photos a second").exists)
        try audit(app)
        // The audit can close the menu.
        if !slow.exists { burstStripWord(app, "Burst").tap() }
        XCTAssertTrue(slow.waitForExistence(timeout: 5))
        slow.tap()
        XCTAssertTrue(element(app, containing: "Slow burst: up to 2 a second").waitForExistence(timeout: 5))
        XCTAssertTrue(burstWaitForValue(shutter, containing: "Burst, slow."))
        XCTAssertTrue(burstWaitForValue(burstStripWord(app, "Burst"), containing: "Slow"))
        try audit(app)
    }

    /// The summary stays until the next action: a lens change clears it.
    @MainActor
    func testBurstSummaryStaysUntilNextAction() throws {
        let app = launchBurst()
        app.buttons["Start Burst"].tap()
        let stop = app.buttons["Stop Burst"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        stop.tap()
        let summary = element(app, containing: "photos saved")
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(summary.exists, "nothing disappears on a timer")
        let ultraWide = app.buttons["Ultra Wide"]
        XCTAssertTrue(ultraWide.waitForExistence(timeout: 5))
        ultraWide.tap()
        XCTAssertFalse(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, containing: "Fast burst").waitForExistence(timeout: 5))
    }

    /// VoiceOver: the shutter's value and hint, the Start Burst action, and activation takes
    /// one photo.
    @MainActor
    func testBurstVoiceOverValueHintAndAction() throws {
        let app = launchBurst(extraArguments: Self.signingOn)
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(burstWaitForValue(shutter, containing: "Burst, fast."))
        // The hint and the action aren't exposed to XCUITest; the snapshot has the value. The
        // Start Burst action is the card's button by the same name, which the audit checks.
        XCTAssertTrue(app.buttons["Start Burst"].exists)
        shutter.tap()
        XCTAssertTrue(burstWaitForValue(app.descendants(matching: .any)["Last Photo"], containing: "Saved and signed."))
        try audit(app)
    }

    /// The largest text size: the scrolling layout, the Burst row's speed, the idle and running
    /// cards.
    @MainActor
    func testBurstLargestText() throws {
        let app = launchBurst(extraArguments: Self.largestTextSize)
        let start = app.buttons["Start Burst"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Fast burst").exists)
        try auditScrollingScreen(app)
        start.tap()
        let stop = app.buttons["Stop Burst"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        try auditScrollingScreen(app)
        if stop.exists { stop.tap() }
        XCTAssertTrue(element(app, containing: "photos saved").waitForExistence(timeout: 20))
        try auditScrollingScreen(app)
    }

    /// Right to left: the card mirrors, with Start Burst and Stop Burst trailing on the left.
    @MainActor
    func testBurstRightToLeft() throws {
        let app = launchBurst(extraArguments: Self.rightToLeft)
        let start = app.buttons["Start Burst"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let text = element(app, containing: "Fast burst")
        XCTAssertLessThan(start.frame.midX, text.frame.midX, "Start Burst trails on the left")
        try audit(app)
        start.tap()
        let stop = app.buttons["Stop Burst"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertLessThan(stop.frame.midX, element(app, containing: "Photos taken").frame.midX)
        try audit(app)
        stop.tap()
    }

    /// Night mode: the cards are red on black.
    @MainActor
    func testBurstNightModeIsAllRed() throws {
        let app = launchBurst(extraArguments: Self.nightModeOn)
        XCTAssertTrue(app.buttons["Start Burst"].waitForExistence(timeout: 5))
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0)
        try audit(app)
        app.buttons["Start Burst"].tap()
        let stop = app.buttons["Stop Burst"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0)
        try audit(app)
        stop.tap()
        XCTAssertTrue(element(app, containing: "photos saved").waitForExistence(timeout: 15))
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0)
    }

    /// Sideways on an iPhone, the idle card turns upright and Start Burst can be used.
    @MainActor
    func testBurstSideways() throws {
        guard !isPad else { throw XCTSkip("An iPad window rotates for real; testBurstOnIPad covers it.") }
        let app = launchBurst()
        XCTAssertTrue(app.buttons["Start Burst"].waitForExistence(timeout: 5))
        try turnSideways(app, mode: "Burst")
        defer { XCUIDevice.shared.orientation = .portrait }
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.height, window.width, "the iPhone camera layout turned")
        let start = app.buttons["Start Burst"]
        XCTAssertTrue(start.isHittable)
        // Text drawn a quarter turn is measured unturned by the audit; those findings are
        // skipped, as in testDriveCardsSideways.
        try app.performCompleteAccessibilityAudit { issue in
            guard let element = issue.element else { return issue.auditType == .textClipped || issue.auditType == .contrast }
            return issue.auditType == .contrast && element.exists && element.frame.height > element.frame.width
        }
    }

    /// Burst Limit 10 (issue #121): the idle card names the count and has no Start Burst, the
    /// shutter's value says it, and a tap runs to "10 of 10 photos saved".
    @MainActor
    func testBurstLimitTapRunsToTheCount() throws {
        let app = launchBurst(extraArguments: ["-NopeSettings.burstLimit", "ten"])
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(element(app, containing: "Fast burst · 10 photos").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "A press takes 10 photos. Press again to stop.").exists)
        XCTAssertFalse(app.buttons["Start Burst"].exists, "a press already starts the burst")
        XCTAssertTrue(burstWaitForValue(shutter, containing: "Burst, fast, 10 photos."))
        try audit(app)
        shutter.tap()
        XCTAssertTrue(app.buttons["Stop Burst"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "10 of 10 photos saved").waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["Start Burst"].exists)
        try audit(app)
    }

    /// Burst Limit 50: while it runs the card reads "3 of 50" with Stop Burst and the shutter
    /// says a press stops it; a second press of the shutter stops it early, and every photo taken
    /// is saved ("4 of 50 photos saved"). The stop square on the shutter is drawn only and is
    /// checked on a device (docs/TESTING.md, "Burst Limit on a device").
    @MainActor
    func testBurstLimitSecondPressStopsEarly() throws {
        let app = launchBurst(extraArguments: ["-NopeSettings.burstLimit", "fifty"])
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(element(app, containing: "Fast burst · 50 photos").waitForExistence(timeout: 5))
        shutter.tap()
        XCTAssertTrue(app.buttons["Stop Burst"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: " of 50").waitForExistence(timeout: 5))
        XCTAssertTrue(burstWaitForValue(shutter, containing: "Taking a burst. Press to stop."))
        try audit(app)
        shutter.tap()
        let summary = element(app, containing: "of 50 photos saved")
        XCTAssertTrue(summary.waitForExistence(timeout: 20))
        XCTAssertLessThan(photosSaved(summary) ?? 50, 50, summary.label)
        try audit(app)
    }

    /// iPad: the column layout, a press and hold, and a tap for one photo.
    @MainActor
    func testBurstOnIPad() throws {
        guard isPad else { throw XCTSkip("The column layout is the iPad's.") }
        let app = launchBurst(extraArguments: Self.signingOn)
        XCTAssertTrue(app.buttons["Start Burst"].waitForExistence(timeout: 5))
        try audit(app)
        let shutter = app.buttons["Take Photo"]
        shutter.tap()
        let lastPhoto = app.descendants(matching: .any)["Last Photo"]
        XCTAssertTrue(burstWaitForValue(lastPhoto, containing: "Saved and signed."))
        shutter.press(forDuration: 3)
        XCTAssertTrue(element(app, containing: "photos saved").waitForExistence(timeout: 15))
        XCTAssertTrue(burstWaitForValue(lastPhoto, containing: "photos saved and signed."))
        try audit(app)
    }
}
