import XCTest

/// UI tests for interval shooting that stops after a time (owner decision 2026-11-18): Interval
/// Settings' Stop After picker, its hours and minutes, the most photos it can take and the check
/// that the interval is shorter than the time; the idle card; and the running card with the
/// photos taken, the time left, a progress bar and Stop. Each state is audited at the default
/// size, the largest text size, right to left and in night mode. They run on iPhone and iPad.
extension NopeAppUITests {
    /// Opens a menu picker of a form row and chooses one of its options.
    @MainActor
    private func chooseInPicker(_ app: XCUIApplication, _ picker: String, _ option: String) {
        let row = formRow(app, picker)
        XCTAssertTrue(row.waitForExistence(timeout: 5), picker)
        row.tap()
        let item = app.buttons.matching(NSPredicate(format: "label == %@", option)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(picker): \(option)")
        item.tap()
        XCTAssertTrue(item.waitForNonExistence(timeout: 5), "the menu or page closes")
    }

    /// The form row of that name in Interval Settings: a menu picker is a button whose label is
    /// its name and its choice ("Hours, 1"); Stop After, a picker on its own page, is named by
    /// its label alone.
    @MainActor
    private func formRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.collectionViews.buttons.matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@", name, name + ",")
        ).firstMatch
    }

    /// Opens Interval Settings from the drive strip and chooses Stop After: Time.
    @MainActor
    private func openTimedIntervalSettings(_ app: XCUIApplication) {
        chooseDrive(app, "Interval Shooting")
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
        chooseInPicker(app, "Stop After", "Time")
        XCTAssertTrue(formRow(app, "Hours").waitForExistence(timeout: 5))
    }

    /// Audits Interval Settings with Stop After: Time without the Dynamic Type check. At the
    /// default size the audit enlarges the text in place, and this sheet, two rows taller than
    /// the one for a number of photos, then runs past the window's edge: the audit reported every
    /// row below Minutes as "partially unsupported" in three audits in a row, at 440 to 650 of 874
    /// points, with nothing to scroll. The sheet's text is checked at the largest text size,
    /// where it is laid out for real and scrolls (`testIntervalTimeAtTheLargestTextSize...`).
    @MainActor
    private func auditTimedIntervalSettings(_ app: XCUIApplication) throws {
        try audit(app, checksDynamicType: false)
    }

    /// Closes Interval Settings with its Done row, scrolling to it at the largest text sizes.
    @MainActor
    private func closeIntervalSettings(_ app: XCUIApplication) {
        let done = app.buttons["Done"]
        for _ in 0..<6 where !done.exists || !done.isHittable {
            app.collectionViews.firstMatch.swipeUp()
        }
        done.tap()
    }

    /// Brightens the screen if a series dimmed it, so the card can be used.
    @MainActor
    private func brightenTimedSeries(_ app: XCUIApplication) {
        let brighten = app.buttons["Brighten Screen"]
        if brighten.waitForExistence(timeout: 3) {
            brighten.tap()
            _ = brighten.waitForNonExistence(timeout: 3)
        }
    }

    /// Interval Settings with Stop After: Time: hours and minutes, the most photos, the check that
    /// the interval is shorter than the time, and the idle card that names the time.
    @MainActor
    func testIntervalStopAfterTimeSettings() throws {
        let app = launch("noRAW")
        openTimedIntervalSettings(app)
        // One hour by default, ten seconds apart.
        XCTAssertTrue(element(app, containing: "At most 360").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "The time keeps running while the series is paused").exists)
        XCTAssertTrue(app.buttons["Start"].isEnabled)
        try auditTimedIntervalSettings(app)

        // An interval as long as the time: Start is disabled and the sheet says why.
        chooseInPicker(app, "Interval", "1 hr")
        let reason = element(app, containing: "Choose an interval shorter than the time.")
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start"].isEnabled)
        XCTAssertFalse(element(app, containing: "At most").exists)
        try auditTimedIntervalSettings(app)

        // Two hours: two photos at most, and Start again.
        chooseInPicker(app, "Hours", "2")
        XCTAssertTrue(element(app, containing: "At most 2").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start"].isEnabled)
        XCTAssertFalse(reason.exists)

        // Back to a number of photos: the count is as it was, and the time rows go.
        chooseInPicker(app, "Stop After", "Number of Photos")
        XCTAssertTrue(formRow(app, "Photos").waitForExistence(timeout: 5))
        XCTAssertFalse(formRow(app, "Hours").exists)
        chooseInPicker(app, "Stop After", "Time")
        closeIntervalSettings(app)
        let card = app.buttons["Interval Settings"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "Every 1 hour, for 2 hours")
        try audit(app)

        // The card says why the shutter can't start a series whose interval is too long.
        card.tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
        chooseInPicker(app, "Hours", "1")
        closeIntervalSettings(app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "Every 1 hour, for 1 hour, Choose an interval shorter than the time.")
        XCTAssertFalse(app.buttons["Take Photo"].isEnabled)
        try audit(app)
    }

    /// The running card of a series that stops after a time: the photos taken and the time
    /// left, the next photo's time, and Stop; VoiceOver reads the time in words.
    @MainActor
    func testIntervalTimeCardRunsAndStops() throws {
        let app = launch("noRAW")
        openTimedIntervalSettings(app)
        closeIntervalSettings(app)
        let card = app.buttons["Interval Settings"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "Every 10 seconds, for 1 hour")
        app.buttons["Take Photo"].tap()
        let progress = element(app, containing: "photo")
        XCTAssertTrue(element(app, containing: "taken · ").waitForExistence(timeout: 20))
        brightenTimedSeries(app)
        // VoiceOver reads the units in full: "1 photo taken · 1 hour left" or "... 59 minutes left".
        let spoken = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", ".*photos? taken · .*(hour|minute).* left.*")).firstMatch
        XCTAssertTrue(spoken.waitForExistence(timeout: 5), progress.label)
        XCTAssertTrue(element(app, containing: "Next photo in").waitForExistence(timeout: 15))
        XCTAssertFalse(element(app, containing: " of 10 photos").exists, "no count of a set number")
        try audit(app)
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.exists)
        stop.tap()
        XCTAssertFalse(element(app, containing: "taken · ").waitForExistence(timeout: 5))
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    /// The sheet and the running card at the largest text size, right to left and in night mode.
    @MainActor
    func testIntervalTimeAtTheLargestTextSizeRightToLeftAndNightMode() throws {
        for arguments in [Self.largestTextSize, Self.rightToLeft, Self.nightModeOn] {
            let app = launch("noRAW", extraArguments: arguments)
            openTimedIntervalSettings(app)
            if arguments == Self.largestTextSize {
                // The form scrolls: audited at the top, then at its end with the estimate.
                try audit(app)
                let estimate = element(app, containing: "At most 360")
                for _ in 0..<4 where !estimate.exists || !estimate.isHittable {
                    app.collectionViews.firstMatch.swipeUp()
                }
                XCTAssertTrue(estimate.waitForExistence(timeout: 5))
                try audit(app, afterScrolling: true)
            } else {
                XCTAssertTrue(element(app, containing: "At most 360").waitForExistence(timeout: 5))
                try auditTimedIntervalSettings(app)
            }
            closeIntervalSettings(app)
            XCTAssertTrue(app.buttons["Interval Settings"].waitForExistence(timeout: 5))
            app.buttons["Take Photo"].tap()
            let text = element(app, containing: "taken · ")
            XCTAssertTrue(text.waitForExistence(timeout: 20))
            brightenTimedSeries(app)
            let stop = app.buttons["Stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 5))
            if arguments == Self.largestTextSize {
                // Without the contrast check: during a series the camera screen dims again after
                // a while (SeriesScreenKeeper), and the scrolled camera's own "Off" (Manual
                // Controls) at the window's lower edge was measured dimmed. The card's colors are
                // contrast-checked at the default size, right to left and in night mode.
                try auditScrollingScreen(app, checksContrast: false)
            } else {
                if arguments == Self.rightToLeft {
                    XCTAssertLessThan(stop.frame.midX, text.frame.midX, "Stop trails on the left")
                } else {
                    XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0)
                }
                try audit(app)
            }
            if stop.exists { stop.tap() }
            app.terminate()
        }
    }
}
