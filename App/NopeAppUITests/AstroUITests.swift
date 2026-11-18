import XCTest

/// UI tests for the astro helper (issue #60) and the focus magnifier in night mode, against the
/// simulated backend. The `manual` scenario's wide lens has Bayer RAW, manual exposure and
/// manual focus, so the helper is offered there.
extension NopeAppUITests {
    /// Turns the astro helper on from the drive strip's Astro word (docs/design/BUILD-SPEC.md,
    /// 3.5), which replaced the quick-controls tray's Astro item, and waits until it is selected.
    @MainActor
    private func turnOnAstro(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        driveStripWord(app, "Astro").tap()
        let selected = app.buttons.matching(NSPredicate(format: "label == %@ AND selected == YES", "Astro")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5), file: file, line: line)
    }

    /// Opens a pushed-list picker in a form and chooses a value.
    @MainActor
    private func choose(_ app: XCUIApplication, _ value: String, in picker: String) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", picker)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), picker)
        row.tap()
        let option = app.buttons[value].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10), value)
        option.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10), "back from the \(picker) list")
    }

    /// While Astro is on, no interval series runs with it. Astro and Interval are now words of
    /// one drive strip, and Pro Tools no longer has Start (BUILD-SPEC.md, 3.4 and 3.5), so the
    /// series is reached only by choosing Interval, which turns Astro off; its Start is enabled.
    @MainActor
    func testIntervalStartIsDisabledWhileAstroIsOn() throws {
        let app = launch("manual")
        turnOnAstro(app)
        XCTAssertTrue(element(app, containing: "Astro frames").waitForExistence(timeout: 10))
        chooseDrive(app, "Interval Shooting")
        let start = app.buttons["Start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.isEnabled)
        XCTAssertFalse(element(app, containing: "Turn off Astro to start interval shooting.").exists)
        // As for the other form screens at the default size, the iOS 27.2 Simulator reports form
        // text as "partially unsupported" Dynamic Type; the form is audited at the largest size
        // in testIntervalSheetAtTheLargestTextSizeAndRightToLeft.
        try audit(app, checksDynamicType: false)
        app.buttons["Done"].tap()
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label == %@ AND selected == YES", "Astro")).firstMatch.exists,
            "Astro stayed on with Interval")
        XCTAssertFalse(element(app, containing: "Astro frames").exists)
    }

    @MainActor
    func testAstroHelperIsRedOnBlackAndSetsUpTheFrames() throws {
        let app = launch("manual", extraArguments: Self.signingOn + ["-NopeSimulatedViewfinder", "white"])
        // Astro is one choice of the drive strip, so no self-timer or burst runs with its own
        // start delay and frame count.
        turnOnAstro(app)
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label == %@ AND selected == YES", "Timer")).firstMatch.exists)
        // Night mode comes on with the helper; the viewfinder keeps its natural colors.
        XCTAssertTrue(element(app, containing: "Astro frames: 20").waitForExistence(timeout: 10))
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0, "white, blue or other colors remain")
        // Manual controls come on, with the helper's focus, shutter and ISO.
        XCTAssertTrue(app.buttons["More Manual Controls"].waitForExistence(timeout: 10))
        try audit(app)

        let viewfinderFrame = app.otherElements["Viewfinder"].frame
        app.buttons["Astro Settings"].tap()
        XCTAssertTrue(element(app, containing: "doesn't stack, merge or process them").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, containing: "Exposure Time in All").exists)
        XCTAssertTrue(element(app, containing: "Storage, at Most").exists)
        // The natural-color viewfinder (white here) shows at the sheet's rounded top corners.
        XCTAssertEqual(nonRedPixels(app, outside: viewfinderFrame), 0, "the settings are red on black too")
        try auditVisibleElements(app, skipDynamicType: true)
        choose(app, "5", in: "Frames")
        choose(app, "3 seconds", in: "Start Delay")
        try auditVisibleElements(app, skipDynamicType: true)
        let done = app.buttons["Done"]
        var swipes = 0
        while !(done.exists && done.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        done.tap()
        XCTAssertTrue(element(app, containing: "Astro frames: 5").waitForExistence(timeout: 10))

        // The shutter counts the start delay down on the Astro card, then takes the frames, each
        // saved as its own photo.
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(element(app, containing: "First frame in").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stop Frames"].exists)
        let thumbnail = app.descendants(matching: .any)["Last Photo"]
        XCTAssertTrue(
            XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "5 photos saved"), object: thumbnail)],
                timeout: 30) == .completed)
        try audit(app)

        // Single on the drive strip, which replaced the Astro pill, turns the helper off; night
        // mode, which the helper turned on, goes back off with the manual controls
        // (AstroNightModeUITests covers the other cases).
        driveStripWord(app, "Single").tap()
        XCTAssertTrue(element(app, containing: "Astro frames").waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["More Manual Controls"].exists, "manual controls go back off")
        XCTAssertGreaterThan(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0, "night mode goes back off")
    }

    @MainActor
    func testAstroFramesShowProgressAndStop() throws {
        let app = launch("astro", extraArguments: Self.nightModeOn)
        turnOnAstro(app)
        app.buttons["Astro Settings"].tap()
        choose(app, "300", in: "Frames")
        choose(app, "3 seconds", in: "Start Delay")
        let done = app.buttons["Done"]
        var swipes = 0
        while !(done.exists && done.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        done.tap()
        app.buttons["Take Photo"].tap()
        // The screen stays awake and dims while the frames run (issue #48's screen keeper).
        let brighten = app.buttons["Brighten Screen"]
        XCTAssertTrue(brighten.waitForExistence(timeout: 15))
        try audit(app)
        brighten.tap()
        let stop = app.buttons["Stop Frames"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "of 300").exists)
        try audit(app)
        stop.tap()
        XCTAssertFalse(stop.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, containing: "Astro frames: 300").waitForExistence(timeout: 10))
    }

    /// The frame number "Frame n of 300" shows, or `nil`.
    @MainActor
    private func frameNumber(_ app: XCUIApplication) -> Int? {
        let label = element(app, containing: "of 300").label
        return label.split(separator: " ").compactMap { Int($0) }.first
    }

    /// Leaving the app pauses the frames; coming back counts the start delay down again and the
    /// run continues from where it was (issue #64, owner decision).
    @MainActor
    func testAstroFramesPauseWhenLeavingAndContinueOnReturn() throws {
        let app = launch("astro")
        turnOnAstro(app)
        app.buttons["Astro Settings"].tap()
        choose(app, "300", in: "Frames")
        choose(app, "3 seconds", in: "Start Delay")
        let done = app.buttons["Done"]
        var swipes = 0
        while !(done.exists && done.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        done.tap()
        app.buttons["Take Photo"].tap()
        let brighten = app.buttons["Brighten Screen"]
        XCTAssertTrue(brighten.waitForExistence(timeout: 15))
        brighten.tap()
        let stop = app.buttons["Stop Frames"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        let started = NSPredicate { _, _ in (self.frameNumber(app) ?? 0) >= 3 }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: started, object: nil)], timeout: 20), .completed)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackgroundSuspended, timeout: 10) || app.state == .runningBackground)
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Away from the app")], timeout: 3)
        app.activate()
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "the run is still there")
        let pausedAt = try XCTUnwrap(frameNumber(app))
        // The start delay counts down again before the next frame, then the run continues.
        let continued = NSPredicate { _, _ in (self.frameNumber(app) ?? 0) > pausedAt + 1 }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: continued, object: nil)], timeout: 30), .completed)
        if brighten.exists { brighten.tap() }
        try audit(app)
        stop.tap()
        XCTAssertFalse(stop.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, containing: "Astro frames: 300").waitForExistence(timeout: 10))
    }

    @MainActor
    func testAstroAtTheLargestTextSizeAndRightToLeft() throws {
        let large = launch("manual", extraArguments: Self.largestTextSize)
        turnOnAstro(large)
        XCTAssertTrue(element(large, containing: "Astro frames").waitForExistence(timeout: 10))
        try auditScrollingScreen(large)
        // The sheet's rows grow with the text (its audit skips Dynamic Type, as Pro Tools' does:
        // the audit reports Form rows it pushes out of the window while enlarging the text).
        let settingsButton = large.buttons["Astro Settings"]
        var scrolls = 0
        while !settingsButton.isHittable && scrolls < 6 {
            large.swipeUp()
            scrolls += 1
        }
        settingsButton.tap()
        let total = large.staticTexts["Exposure Time in All"]
        scrolls = 0
        while !(total.exists && large.windows.firstMatch.frame.contains(total.frame)) && scrolls < 8 {
            large.swipeUp()
            scrolls += 1
        }
        XCTAssertGreaterThan(total.frame.height, 40, "the row's text is enlarged")
        large.terminate()

        let rightToLeft = launch("manual", extraArguments: Self.rightToLeft)
        turnOnAstro(rightToLeft)
        XCTAssertTrue(element(rightToLeft, containing: "Astro frames").waitForExistence(timeout: 10))
        try audit(rightToLeft)
        rightToLeft.buttons["Astro Settings"].tap()
        XCTAssertTrue(element(rightToLeft, containing: "Exposure Time in All").waitForExistence(timeout: 10))
        try auditVisibleElements(rightToLeft, skipDynamicType: true)
    }

    // MARK: - Magnifier in night mode

    /// The color class a quarter of the way across the viewfinder, at its middle height: black
    /// (`other`) on the target viewfinder, and the target's white (or red) once the 3× magnifier
    /// enlarges the middle third.
    @MainActor
    private func quarterColor(_ app: XCUIApplication) -> PixelColor {
        settle()
        let frame = app.otherElements["Viewfinder"].frame
        return centerColor(app, of: CGRect(x: frame.minX + frame.width / 4, y: frame.midY, width: 0, height: 0))
    }

    @MainActor
    func testMagnifierEnlargesTheNaturalAndTheRedNightViewfinder() throws {
        for (arguments, color) in [(Self.nightModeOn, PixelColor.white), (Self.redViewfinder, .red)] {
            let app = launch("aids", extraArguments: arguments + ["-NopeSimulatedViewfinder", "target"])
            XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 20))
            XCTAssertEqual(quarterColor(app), .other, "the target is black a quarter of the way across")
            quickControl(app, "Magnify")
            closeTray(app)
            XCTAssertEqual(quarterColor(app), color, "the magnifier enlarges the viewfinder")
            try audit(app)
            app.terminate()
        }
    }
}
