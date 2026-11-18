import XCTest

/// UI tests for the camera shell of the 1.0.0 design (docs/design/BUILD-SPEC.md, 3.1, 3.4's
/// button, 3.5's strip, 3.11 and 3.12): the row order, the Manual Controls button (issue #77), the
/// drive strip, Q, and the layouts at the largest text size, right to left, in night mode and
/// sideways, each with an accessibility audit.
extension NopeAppUITests {
    /// Manual controls on at launch.
    private static let shellManualOn = ["-NopeSettings.showsManualControls", "YES"]

    /// Night mode on at launch.
    private static let shellNightMode = ["-NopeSettings.isNightModeOn", "YES"]

    /// Waits until an element's value is the given text.
    @MainActor
    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// Waits until an element is gone.
    @MainActor
    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// Waits until a button is selected or not.
    @MainActor
    private func waitForSelection(_ element: XCUIElement, _ isSelected: Bool, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "isSelected == %@", NSNumber(value: isSelected))
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// Audits the scrolling camera as `auditScrollingScreen(_:checksContrast:)` does, and also
    /// skips contrast findings on a row cut by the scroll view's lower edge: the hard scroll edge
    /// above the pinned shutter row covers part of it, so the audit samples the edge, not the row.
    /// Every row is measured whole in another audit, before or after scrolling.
    @MainActor
    private func auditScrollingCamera(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        let pinnedTop = app.buttons["Quick Menu"].frame.minY - 2 * 8
        try auditScrollingScreen(app, checksContrast: false, file: file, line: line)
        try app.performCompleteAccessibilityAudit(for: .contrast) { issue in
            guard let element = issue.element, element.exists else { return true }
            return element.frame.maxY > pinnedTop || !app.frame.contains(element.frame)
        }
    }

    /// The drive strip's word of that name: the lowest button with the label, since a pill on the
    /// status line may share it (the Astro pill, until the pills of the strip's modes go).
    @MainActor
    private func driveWord(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", name))
        let lowest = matches.allElementsBoundByIndex.enumerated().max { $0.element.frame.minY < $1.element.frame.minY }
        return matches.element(boundBy: lowest?.offset ?? 0)
    }

    /// The camera's rows, top to bottom, in the stacked layout: status, picture, lens row
    /// (Manual Controls, lenses, Switch Camera), drive strip, shutter row with Q; the shutter on
    /// the screen's center line, and Last Photo and Q the same distance from it.
    @MainActor
    func testStackedLayoutRowOrder() throws {
        let app = launch("allow")
        continuePastFirstRun(app)
        guard !isPad else { throw XCTSkip("The stacked layout is the iPhone's; the column is tested in testColumnLayoutOrder.") }
        let status = app.buttons["Photo Format"].frame
        let picture = app.otherElements["Viewfinder"].frame
        let manual = app.buttons["ManualControlsButton"].frame
        let wide = app.buttons["Wide"].frame
        let flip = app.buttons["Switch Camera"].frame
        let single = app.buttons["Single"].frame
        let shutter = app.buttons["Take Photo"]
        let quick = app.buttons["Quick Menu"]
        XCTAssertLessThanOrEqual(status.maxY, picture.minY + 1, "the status isn't above the picture")
        // Below the picture, or on a short screen (4.7-inch iPhone) over its lower edge.
        if manual.minY < picture.maxY - 1 {
            XCTAssertLessThanOrEqual(single.maxY, shutter.frame.minY, "the rows run into the shutter row")
        }
        XCTAssertGreaterThan(manual.minY, picture.midY, "the lens row isn't at the picture's lower edge")
        XCTAssertEqual(manual.midY, wide.midY, accuracy: 2, "Manual Controls isn't in the lens row")
        XCTAssertEqual(flip.midY, wide.midY, accuracy: 2, "Switch Camera isn't in the lens row")
        XCTAssertLessThan(manual.maxX, wide.minX, "Manual Controls isn't before the lenses")
        XCTAssertGreaterThan(flip.minX, wide.maxX, "Switch Camera isn't after the lenses")
        XCTAssertGreaterThan(single.minY, wide.maxY - 1, "the drive strip isn't below the lens row")
        XCTAssertGreaterThan(shutter.frame.minY, single.maxY - 1, "the shutter isn't below the drive strip")
        XCTAssertEqual(quick.frame.midY, shutter.frame.midY, accuracy: 2, "Q isn't beside the shutter")
        // The picture spans the window's width in the stacked layout.
        XCTAssertEqual(shutter.frame.midX, picture.midX, accuracy: 1, "the shutter isn't centered")
        // No Settings button on the stacked camera: Settings opens from Q.
        XCTAssertFalse(app.buttons["Settings"].exists)
        try audit(app)

        shutter.tap()
        let lastPhoto = app.descendants(matching: .any)["Last Photo"]
        XCTAssertTrue(lastPhoto.waitForExistence(timeout: 15))
        // The thumbnail slides in; measure it where it comes to rest.
        settle()
        // The thumbnail's element includes its signature badge, which sticks out past its
        // trailing corner, so its center is measured from its leading edge (52 points across).
        let thumbnailCenter = lastPhoto.frame.minX + 26
        XCTAssertEqual(
            shutter.frame.midX - thumbnailCenter, quick.frame.midX - shutter.frame.midX, accuracy: 1,
            "Last Photo and Q aren't the same distance from the shutter")
        try audit(app)
    }

    /// The column layout (iPad, the iPhone Duo's inner display): Settings, the lenses and Manual
    /// Controls at the top of the column; Q above the shutter and Last Photo below it; the drive
    /// strip on the picture's lower edge.
    @MainActor
    func testColumnLayoutOrder() throws {
        guard isPad else { throw XCTSkip("The column layout is checked on iPad.") }
        let app = launch("allow")
        continuePastFirstRun(app)
        // Both orientations: the picture is 3:4 or 4:3, and the column is on the trailing edge.
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1.5)
            let picture = app.otherElements["Viewfinder"].frame
            let settings = app.buttons["Settings"].frame
            let manual = app.buttons["ManualControlsButton"].frame
            let quick = app.buttons["Quick Menu"].frame
            let shutter = app.buttons["Take Photo"].frame
            let single = app.buttons["Single"].frame
            for frame in [settings, manual, quick, shutter] {
                XCTAssertGreaterThanOrEqual(frame.minX, picture.maxX - 1, "a column control is over the picture")
            }
            XCTAssertLessThan(settings.maxY, manual.minY)
            XCTAssertLessThan(manual.maxY, quick.minY)
            XCTAssertLessThan(quick.maxY, shutter.minY + 1)
            XCTAssertTrue(picture.contains(CGPoint(x: single.midX, y: single.midY)), "the drive strip isn't on the picture")
            try audit(app)
            app.buttons["Quick Menu"].tap()
            XCTAssertTrue(app.buttons["Hide Controls"].waitForExistence(timeout: 5))
            try audit(app)
            app.buttons["Quick Menu"].tap()
            XCTAssertTrue(waitForDisappearance(app.buttons["Hide Controls"]))
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// From full auto, one tap turns manual controls on and shows the readouts; another turns
    /// them off. VoiceOver reads "Manual Controls, On".
    @MainActor
    func testManualControlsButtonInAuto() throws {
        let app = launch("manual")
        let button = app.buttons["ManualControlsButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        XCTAssertEqual(button.value as? String, "Off")
        XCTAssertFalse(app.buttons["More Manual Controls"].exists)
        button.tap()
        XCTAssertTrue(waitForValue(button, "On"))
        XCTAssertTrue(button.isSelected)
        XCTAssertTrue(app.buttons["More Manual Controls"].waitForExistence(timeout: 5))
        try audit(app)
        button.tap()
        XCTAssertTrue(waitForValue(button, "Off"))
        XCTAssertTrue(waitForDisappearance(app.buttons["More Manual Controls"]))
    }

    /// With manual controls on, one tap turns them off, and the next turns them on again.
    @MainActor
    func testManualControlsButtonInManual() throws {
        let app = launch("manual", extraArguments: Self.shellManualOn)
        let button = app.buttons["ManualControlsButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForValue(button, "On"))
        XCTAssertTrue(app.buttons["More Manual Controls"].waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(waitForValue(button, "Off"))
        XCTAssertTrue(waitForDisappearance(app.buttons["More Manual Controls"]))
        button.tap()
        XCTAssertTrue(waitForValue(button, "On"))
        try audit(app)
    }

    /// Clean view hides the Manual Controls button, the lenses, the drive strip and Q, and
    /// keeps the shutter and Show Controls.
    @MainActor
    func testCleanViewHidesManualControlsButton() throws {
        let app = launch("manual")
        let quick = app.buttons["Quick Menu"]
        XCTAssertTrue(quick.waitForExistence(timeout: 20))
        quick.tap()
        let hide = app.buttons["Hide Controls"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        hide.tap()
        let show = app.buttons["Show Controls"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        for name in ["ManualControlsButton", "Quick Menu", "Single", "Wide", "Switch Camera"] {
            XCTAssertFalse(app.buttons[name].exists, name)
        }
        XCTAssertTrue(app.buttons["Take Photo"].exists)
        try audit(app)
        show.tap()
        XCTAssertTrue(app.buttons["ManualControlsButton"].waitForExistence(timeout: 5))
    }

    /// Each word of the drive strip is one tap from the default screen and selects its mode; the
    /// shutter's VoiceOver value says the mode, and with Timer its disc shows the delay.
    @MainActor
    func testDriveStripSelectsEachMode() throws {
        let app = launch("noRAW")
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 20))
        let single = app.buttons["Single"]
        XCTAssertTrue(single.isSelected)
        let expected = [
            ("Timer", "Self-timer: 3 seconds"),
            ("Burst", "Burst, fast."),
            ("Interval", "Interval shooting. Press to start the series."),
        ]
        for (word, value) in expected {
            driveWord(app, word).tap()
            // A pill of the same name may appear above the strip, so the selected word is found
            // by its state.
            let selected = app.buttons.matching(NSPredicate(format: "label == %@ AND selected == YES", word)).firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout: 5), word)
            XCTAssertTrue(waitForValue(shutter, value), word)
            XCTAssertFalse(single.isSelected, word)
        }
        // Choosing Interval only selects it; its settings open from the selected word.
        XCTAssertFalse(app.navigationBars.firstMatch.exists)
        try audit(app)
        single.tap()
        XCTAssertTrue(waitForSelection(single, true))
        XCTAssertTrue(waitForValue(shutter, ""))
    }

    /// The selected Timer opens a menu of 3 and 10 seconds; the delay chosen is kept when Timer
    /// is chosen again.
    @MainActor
    func testTimerDelayMenu() throws {
        let app = launch("noRAW")
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 20))
        let timer = app.buttons["Timer"]
        timer.tap()
        XCTAssertTrue(waitForValue(shutter, "Self-timer: 3 seconds"))
        timer.tap()
        let ten = app.buttons["10 seconds"]
        XCTAssertTrue(ten.waitForExistence(timeout: 5))
        ten.tap()
        XCTAssertTrue(waitForValue(shutter, "Self-timer: 10 seconds"))
        app.buttons["Single"].tap()
        XCTAssertTrue(waitForValue(shutter, ""))
        timer.tap()
        XCTAssertTrue(waitForValue(shutter, "Self-timer: 10 seconds"))
        // The countdown: the disc becomes a stop square and the other words are disabled.
        shutter.tap()
        let cancel = app.buttons["Cancel Timer"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Burst"].isEnabled)
        try audit(app)
        cancel.tap()
        XCTAssertTrue(app.buttons["Burst"].waitForExistence(timeout: 5))
    }

    /// Interval settings open from the selected Interval word.
    @MainActor
    func testIntervalWordOpensSettings() throws {
        let app = launch("noRAW")
        let interval = app.buttons["Interval"]
        XCTAssertTrue(interval.waitForExistence(timeout: 20))
        interval.tap()
        XCTAssertTrue(waitForSelection(interval, true))
        interval.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
    }

    /// Astro from the strip turns the helper on with manual controls and night mode; the
    /// selected word opens its settings; choosing Single turns it off.
    @MainActor
    func testAstroFromStrip() throws {
        let app = launch("astro")
        XCTAssertTrue(app.buttons["Astro"].waitForExistence(timeout: 20))
        driveWord(app, "Astro").tap()
        let selected = app.buttons.matching(NSPredicate(format: "label == %@ AND selected == YES", "Astro")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        let manual = app.buttons["ManualControlsButton"]
        XCTAssertTrue(waitForValue(manual, "On"))
        XCTAssertTrue(element(app, containing: "Astro frames").waitForExistence(timeout: 5))
        try audit(app)
        driveWord(app, "Astro").tap()
        XCTAssertTrue(app.navigationBars["Astro Settings"].waitForExistence(timeout: 5))
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["Single"].waitForExistence(timeout: 5))
        app.buttons["Single"].tap()
        XCTAssertTrue(waitForDisappearance(selected))
        XCTAssertTrue(waitForValue(manual, "Off"))
    }

    /// Q opens and closes the quick menu; the shutter and Q close it; Settings opens from it.
    @MainActor
    func testQuickButtonOpensMenuAndSettings() throws {
        let app = launch("allow")
        continuePastFirstRun(app)
        let quick = app.buttons["Quick Menu"]
        quick.tap()
        let hide = app.buttons["Hide Controls"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        XCTAssertTrue(quick.isSelected)
        try audit(app)
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(waitForDisappearance(hide))
        quick.tap()
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        quick.tap()
        XCTAssertTrue(waitForDisappearance(hide))
        guard !isPad else { return }
        quick.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    /// At the largest text size the camera scrolls: Manual Controls, every lens (the front
    /// camera too) and every drive mode are full-width rows; Q and the shutter stay pinned.
    @MainActor
    func testCameraShellAtTheLargestTextSize() throws {
        let app = launch("manual", extraArguments: Self.largestTextSize)
        let manual = app.buttons["ManualControlsButton"]
        XCTAssertTrue(manual.waitForExistence(timeout: 20))
        try auditScrollingCamera(app)
        manual.tap()
        XCTAssertTrue(waitForValue(manual, "On"))
        for name in ["Wide", "Front", "Single", "Timer", "Burst", "Interval"] {
            XCTAssertTrue(app.buttons[name].exists, name)
        }
        XCTAssertTrue(app.buttons["Quick Menu"].isHittable)
        XCTAssertTrue(app.buttons["Take Photo"].isHittable)
        try auditScrollingCamera(app)
        // Q's list takes the scrolling content's place, and Done brings the rows back.
        app.buttons["Quick Menu"].tap()
        let done = app.buttons["quick.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(manual.exists)
        done.tap()
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
    }

    /// Right to left, the rows mirror: Q is on the left of the shutter, Switch Camera before
    /// Manual Controls, and Timer to the left of Single.
    @MainActor
    func testCameraShellRightToLeft() throws {
        let app = launch("manual", extraArguments: Self.rightToLeft)
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 20))
        if !isPad {
            XCTAssertLessThan(app.buttons["Quick Menu"].frame.maxX, shutter.frame.minX)
            XCTAssertLessThan(app.buttons["Switch Camera"].frame.maxX, app.buttons["ManualControlsButton"].frame.minX)
            XCTAssertLessThanOrEqual(app.buttons["Timer"].frame.maxX, app.buttons["Single"].frame.minX)
        }
        try audit(app)
        app.buttons["ManualControlsButton"].tap()
        XCTAssertTrue(app.buttons["More Manual Controls"].waitForExistence(timeout: 5))
        try audit(app)
    }

    /// Night mode: the strip, the lens row, Manual Controls and Q pass the audit in red on black.
    @MainActor
    func testCameraShellNightMode() throws {
        let app = launch("manual", extraArguments: Self.shellNightMode)
        let manual = app.buttons["ManualControlsButton"]
        XCTAssertTrue(manual.waitForExistence(timeout: 20))
        try audit(app)
        manual.tap()
        XCTAssertTrue(waitForValue(manual, "On"))
        app.buttons["Timer"].tap()
        try audit(app)
    }

    /// The smallest iPhone: the rows overlay the picture and every control stays hittable.
    @MainActor
    func testCameraShellOnTheSmallestScreen() throws {
        let app = launch("manual", extraArguments: Self.shellManualOn)
        XCTAssertTrue(app.buttons["ManualControlsButton"].waitForExistence(timeout: 20))
        for name in ["ManualControlsButton", "Wide", "Switch Camera", "Single", "Interval", "Take Photo", "Quick Menu"] {
            XCTAssertTrue(app.buttons[name].isHittable, name)
        }
        try audit(app)
    }

    /// Sideways on an iPhone the layout stays portrait: Manual Controls shows a letter, the strip
    /// shows symbols, and the selected mode is named on the picture.
    @MainActor
    func testCameraShellSideways() throws {
        guard !isPad else { throw XCTSkip("An iPad window rotates for real; the column layout covers it.") }
        let app = launch("manual")
        XCTAssertTrue(app.buttons["ManualControlsButton"].waitForExistence(timeout: 20))
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1.5)
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThan(window.height, window.width, "the iPhone camera layout turned")
            // The iPhone Duo Simulator's outer display doesn't pass the turn to the app; its
            // turned layout is checked on a device (docs/TESTING.md, iPhone Duo).
            if app.staticTexts["Auto"].exists {
                XCUIDevice.shared.orientation = .portrait
                throw XCTSkip("The device didn't report the turn to the app.")
            }
            XCTAssertTrue(app.buttons["Single"].exists)
            XCTAssertTrue(app.staticTexts["Single"].exists, "the mode isn't named on the picture")
            app.buttons["Timer"].tap()
            XCTAssertTrue(waitForSelection(app.buttons["Timer"], true))
            app.buttons["Single"].tap()
            // Q opens upright over the picture and closes again.
            app.buttons["Quick Menu"].tap()
            XCTAssertTrue(app.buttons["Hide Controls"].waitForExistence(timeout: 5))
            app.buttons["Quick Menu"].tap()
            XCTAssertTrue(waitForDisappearance(app.buttons["Hide Controls"]))
            // Text drawn a quarter turn is measured unturned by the audit (see
            // isTurnedTextFinding in NopeAppUITests.swift); those findings are skipped here.
            try app.performCompleteAccessibilityAudit { issue in
                guard let element = issue.element else { return issue.auditType == .textClipped || issue.auditType == .contrast }
                return issue.auditType == .contrast && element.exists && element.frame.height > element.frame.width
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
