import XCTest

/// Pinch on the viewfinder to switch lenses (issue #95; docs/design/pinch-lens.md, section 11):
/// spreading moves to the next longer rear lens and pinching to the next wider one; a long pinch
/// passes further lenses; nothing changes where a pinch isn't used; the Pinch setting in Settings ›
/// Camera. The simulated backend has three rear lenses (`slowSaving`), two (`aids`, `astro`) or
/// one (`noRAW`). They run on iPhone (stacked layout, and sideways) and iPad (column layout).
extension NopeAppUITests {
    /// The launch arguments that keep a pinch's lens label up long enough for an audit.
    private static let pinchLabelStays = ["-NopeSimulatedPinchLabelSeconds", "60"]

    /// The viewfinder.
    @MainActor
    private func pinchViewfinder(_ app: XCUIApplication) -> XCUIElement {
        app.otherElements["Viewfinder"]
    }

    /// The lens control of that name: a lens button, or a lens row at the largest text sizes.
    @MainActor
    private func pinchLens(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// Waits until the camera is running (the shutter is enabled).
    @MainActor
    private func waitForThePinchCamera(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 30), file: file, line: line)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: shutter)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 30), .completed, "the camera didn't start", file: file, line: line)
    }

    /// Turns the iPad to landscape before a test pinches inward. On the iPad Simulator in
    /// portrait, no simulated inward pinch (`pinch(withScale:velocity:)` at 0.4 to 0.75) reached
    /// the picture in our runs, while spreading did; in landscape both do. The column layout is
    /// the same in both orientations. Inward pinches in portrait are a device check
    /// (docs/TESTING.md, "Pinch to switch lenses on a device").
    @MainActor
    private func turnIPadForAnInwardPinch(_ app: XCUIApplication) {
        guard isPad else { return }
        rotate(app, to: .landscapeLeft)
    }

    /// Pinches on the viewfinder: a scale above 1 spreads the fingers, below 1 pinches them.
    @MainActor
    private func pinchOnViewfinder(_ app: XCUIApplication, scale: CGFloat) {
        pinchViewfinder(app).pinch(withScale: scale, velocity: scale > 1 ? 1 : -1)
    }

    /// Whether the lens of that name becomes the one in use: its button selected and the
    /// viewfinder's value naming it. The front camera has no lens button (Switch Camera), so only
    /// the value is checked for it.
    @MainActor
    private func lensBecomesSelected(_ app: XCUIApplication, _ name: String, timeout: TimeInterval = 10) -> Bool {
        let value = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Lens: \(name)."), object: pinchViewfinder(app))
        guard name != "Front" else { return XCTWaiter().wait(for: [value], timeout: timeout) == .completed }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == YES"), object: pinchLens(app, name))
        return XCTWaiter().wait(for: [selected, value], timeout: timeout) == .completed
    }

    /// Checks that a pinch each way leaves the lens in use as it is, with no label and no
    /// clean-view swipe.
    ///
    /// With a mode card over the lower part of the picture (a countdown, a burst, an interval
    /// series, Astro) only a spread is used: a simulated pinch inward starts its fingers near the
    /// picture's edges, one of them lands on the card, and the other is then a plain one-finger
    /// drag on the picture, not a pinch.
    @MainActor
    private func assertPinchChangesNothing(
        _ app: XCUIApplication, lensInUse name: String, _ message: String, scales: [CGFloat] = [1.6, 0.7],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for scale in scales {
            pinchOnViewfinder(app, scale: scale)
            XCTAssertFalse(
                app.descendants(matching: .any)["lensPinchLabel"].waitForExistence(timeout: 1), "no label: \(message)",
                file: file, line: line)
            XCTAssertTrue(
                (pinchViewfinder(app).value as? String)?.contains("Lens: \(name).") == true, "still \(name): \(message)",
                file: file, line: line)
            XCTAssertFalse(
                app.buttons["Show Controls"].exists, "no clean-view swipe after scale \(scale): \(message)", file: file, line: line)
        }
    }

    // MARK: - 1, 10. Pinch out and in

    /// 1. Spreading selects the next longer lens; pinching the next wider. With the label kept
    /// up, it shows the lens button's text, the lens's name and "No RAW" for the telephoto. On
    /// iPad this is the column layout (test 10).
    @MainActor
    func testPinchOutAndInSwitchesToTheNextLens() throws {
        let app = launch("slowSaving", extraArguments: Self.pinchLabelStays)
        waitForThePinchCamera(app)
        turnIPadForAnInwardPinch(app)
        XCTAssertTrue(lensBecomesSelected(app, "Wide"))
        pinchOnViewfinder(app, scale: 1.5)
        XCTAssertTrue(lensBecomesSelected(app, "Telephoto"), "spread: the next longer lens")
        let label = app.descendants(matching: .any)["lensPinchLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        for text in ["5×", "Telephoto", "No RAW"] {
            XCTAssertTrue(label.label.contains(text), label.label)
        }
        XCTAssertFalse(label.label.localizedCaseInsensitiveContains("zoom"))
        pinchOnViewfinder(app, scale: 0.7)
        XCTAssertTrue(lensBecomesSelected(app, "Wide"), "pinch: the next wider lens")
        pinchOnViewfinder(app, scale: 0.7)
        XCTAssertTrue(lensBecomesSelected(app, "Ultra Wide"))
        // At the widest lens a further pinch changes nothing; no wrap, never the front camera.
        pinchOnViewfinder(app, scale: 0.5)
        XCTAssertTrue(lensBecomesSelected(app, "Ultra Wide", timeout: 3), "still the ultra wide lens, not the front camera")
    }

    /// 2. One long pinch on three lenses ends on the third.
    @MainActor
    func testOneLongPinchCrossesThreeLenses() throws {
        let app = launch("slowSaving")
        waitForThePinchCamera(app)
        pinchLens(app, "Ultra Wide").tap()
        XCTAssertTrue(lensBecomesSelected(app, "Ultra Wide"))
        pinchOnViewfinder(app, scale: 3)
        XCTAssertTrue(lensBecomesSelected(app, "Telephoto"), "past the wide lens to the telephoto")
    }

    // MARK: - 3. Off

    /// 3. With Pinch set to Off, a pinch changes nothing.
    @MainActor
    func testPinchSetToOffChangesNothing() throws {
        let app = launch("slowSaving", extraArguments: ["-NopeSettings.pinch", "off"])
        waitForThePinchCamera(app)
        assertPinchChangesNothing(app, lensInUse: "Wide", "Pinch is Off")
    }

    // MARK: - 4. Where a pinch does nothing

    /// 4. On the front camera, and on a device with one rear lens.
    @MainActor
    func testPinchDoesNothingOnTheFrontCameraOrWithOneRearLens() throws {
        let app = launch("slowSaving")
        waitForThePinchCamera(app)
        app.buttons["Switch Camera"].tap()
        XCTAssertTrue(lensBecomesSelected(app, "Front"))
        waitForThePinchCamera(app)
        assertPinchChangesNothing(app, lensInUse: "Front", "front camera")

        let oneLens = launch("noRAW")
        waitForThePinchCamera(oneLens)
        assertPinchChangesNothing(oneLens, lensInUse: "Wide", "one rear lens")
    }

    /// 4. During a countdown, a burst and an interval series.
    @MainActor
    func testPinchDoesNothingDuringACountdownBurstOrIntervalSeries() throws {
        let app = launch("slowSaving")
        waitForThePinchCamera(app)
        chooseDrive(app, "Timer: 10s")
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(app.buttons["Cancel Timer"].waitForExistence(timeout: 5))
        assertPinchChangesNothing(app, lensInUse: "Wide", "countdown", scales: [1.6])
        XCTAssertFalse(app.buttons["Show Controls"].exists, "a pinch is no clean-view swipe")
        app.buttons["Cancel Timer"].tap()
        XCTAssertTrue(app.buttons["Cancel Timer"].waitForNonExistence(timeout: 5))

        driveStripWord(app, "Burst").tap()
        let start = app.buttons["Start Burst"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let stop = app.buttons["Stop Burst"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        assertPinchChangesNothing(app, lensInUse: "Wide", "burst", scales: [1.6])
        stop.tap()
        XCTAssertTrue(stop.waitForNonExistence(timeout: 10))

        chooseDrive(app, "Interval")
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(element(app, containing: "photos taken").waitForExistence(timeout: 20))
        let brighten = app.buttons["Brighten Screen"]
        if brighten.waitForExistence(timeout: 10) {
            brighten.tap()
            _ = brighten.waitForNonExistence(timeout: 3)
        }
        assertPinchChangesNothing(app, lensInUse: "Wide", "interval series", scales: [1.6])
        app.buttons["Stop"].tap()
        XCTAssertFalse(element(app, containing: "photos taken").waitForExistence(timeout: 5))
        // Free again: the same pinch now switches.
        pinchOnViewfinder(app, scale: 1.5)
        XCTAssertTrue(lensBecomesSelected(app, "Telephoto"))
    }

    /// 4. With Astro on, with Q open and with a dial open.
    @MainActor
    func testPinchDoesNothingWithAstroQOrADialOpen() throws {
        let astro = launch("astro")
        waitForThePinchCamera(astro)
        // On the ultra wide lens, so a spread would have a longer lens to go to.
        pinchLens(astro, "Ultra Wide").tap()
        XCTAssertTrue(lensBecomesSelected(astro, "Ultra Wide"))
        waitForThePinchCamera(astro)
        driveStripWord(astro, "Astro").tap()
        XCTAssertTrue(
            astro.buttons.matching(NSPredicate(format: "label == %@ AND selected == YES", "Astro")).firstMatch
                .waitForExistence(timeout: 5))
        assertPinchChangesNothing(astro, lensInUse: "Ultra Wide", "Astro on", scales: [1.6])

        let withQ = launch("aids")
        waitForThePinchCamera(withQ)
        quickMenuButton(withQ).tap()
        XCTAssertTrue(withQ.descendants(matching: .any)["quickMenu"].waitForExistence(timeout: 10))
        // On iPhone Q covers the middle of the picture, so the fingers land on Q's own tiles;
        // whatever they do there, the lens doesn't change.
        for scale: CGFloat in [1.6, 0.7] {
            pinchOnViewfinder(withQ, scale: scale)
            // The viewfinder's value only: a finger on Q's Hide Controls may hide the lens row.
            XCTAssertTrue(
                (pinchViewfinder(withQ).value as? String)?.contains("Lens: Wide.") == true, "Q open: still Wide after \(scale)")
            XCTAssertFalse(withQ.descendants(matching: .any)["lensPinchLabel"].exists, "Q open: no label")
        }

        let app = launch("aids")
        waitForThePinchCamera(app)
        turnIPadForAnInwardPinch(app)
        quickControl(app, "Exposure")
        XCTAssertTrue(app.sliders["Exposure"].waitForExistence(timeout: 10))
        assertPinchChangesNothing(app, lensInUse: "Wide", "exposure dial open")
        app.buttons["Close Exposure"].tap()
        pinchOnViewfinder(app, scale: 0.7)
        XCTAssertTrue(lensBecomesSelected(app, "Ultra Wide"), "with the dial closed the pinch switches")
    }

    // MARK: - 5, 10. Other touches

    /// 5. After a pinch the controls are still shown (no clean view), focus and exposure aren't
    /// locked, and a following tap still focuses. On iPad this is the column layout (test 10).
    @MainActor
    func testAfterAPinchControlsStayAndATapStillFocuses() throws {
        let app = launch("aids")
        waitForThePinchCamera(app)
        turnIPadForAnInwardPinch(app)
        try assertAPinchIsOnlyALensChange(app)
    }

    /// The checks of test 5, on the screen as it is.
    @MainActor
    private func assertAPinchIsOnlyALensChange(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        pinchOnViewfinder(app, scale: 0.7)
        XCTAssertTrue(lensBecomesSelected(app, "Ultra Wide"), file: file, line: line)
        XCTAssertTrue(app.buttons["Take Photo"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["Show Controls"].exists, "no clean view", file: file, line: line)
        XCTAssertTrue(pinchLens(app, "Wide").exists, "the lens row is still shown", file: file, line: line)
        XCTAssertFalse(app.buttons["Unlock Focus and Exposure"].exists, "not locked", file: file, line: line)
        XCTAssertFalse(app.buttons["Exposure and Focus Lock"].exists, "no lock pill", file: file, line: line)
        // The label goes after 0.8 s; then a tap focuses there, as before.
        XCTAssertTrue(app.descendants(matching: .any)["lensPinchLabel"].waitForNonExistence(timeout: 5), file: file, line: line)
        pinchViewfinder(app).tap()
        XCTAssertTrue(app.buttons["Lock Focus and Exposure"].waitForExistence(timeout: 10), "a tap focuses", file: file, line: line)
        pinchOnViewfinder(app, scale: 1.5)
        XCTAssertTrue(lensBecomesSelected(app, "Wide"), file: file, line: line)
    }

    // MARK: - 6. Magnify

    /// 6. With Magnify on, a pinch changes the lens and the Magnify pill stays.
    @MainActor
    func testPinchWithMagnifyOnKeepsMagnify() throws {
        let app = launch("aids")
        waitForThePinchCamera(app)
        turnIPadForAnInwardPinch(app)
        quickControl(app, "Magnify")
        quickMenuButton(app).tap()
        let pill = app.buttons["Magnify"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pinchOnViewfinder(app, scale: 0.7)
        XCTAssertTrue(lensBecomesSelected(app, "Ultra Wide"))
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "Magnify stays on")
    }

    // MARK: - 7. Largest text size

    /// 7. At the largest text size a pinch changes nothing, and the lens rows work.
    @MainActor
    func testPinchAtTheLargestTextSizeChangesNothing() throws {
        let app = launch("slowSaving", extraArguments: Self.largestTextSize)
        waitForThePinchCamera(app)
        scrollToTheTopOfTheCamera(app)
        assertPinchChangesNothing(app, lensInUse: "Wide", "scrolling layout")
        let telephoto = pinchLens(app, "Telephoto")
        scrollUntilHittable(app, telephoto)
        telephoto.tap()
        XCTAssertTrue(lensBecomesSelected(app, "Telephoto"), "the lens rows work")
    }

    /// Scrolls the scrolling layout back to its top, where the picture is.
    @MainActor
    private func scrollToTheTopOfTheCamera(_ app: XCUIApplication) {
        var swipes = 0
        while !pinchViewfinder(app).isHittable && swipes < 6 {
            app.swipeDown()
            swipes += 1
        }
    }

    // MARK: - 8. Settings

    /// 8. The Pinch row is under Camera, after Focus on Faces, with Switch Lenses; its menu
    /// changes it, and a pinch then does nothing; search finds it by "zoom" and "pinch".
    @MainActor
    func testPinchSettingRowMenuAndSearch() throws {
        let app = launch("slowSaving")
        waitForThePinchCamera(app)
        openSettings(app)
        let pinchRow = settingsElement(app, "settings.pinch")
        XCTAssertTrue(pinchRow.exists)
        XCTAssertTrue(row(pinchRow, shows: "Switch Lenses"), pinchRow.debugDescription)
        XCTAssertTrue(row(pinchRow, shows: "next longer lens"))
        XCTAssertTrue(row(pinchRow, shows: "Used only on the rear cameras."))
        let faces = settingsElement(app, "settings.focusOnFaces")
        settingsElement(app, "settings.pinch")
        XCTAssertLessThan(faces.frame.minY, pinchRow.frame.minY, "after Focus on Faces")
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
        chooseCopiesOption(app, "Off", inRow: "settings.pinch")
        XCTAssertTrue(row(settingsElement(app, "settings.pinch"), shows: "Off"))
        for word in ["zoom", "pinch"] {
            searchSettings(app, for: word)
            XCTAssertTrue(app.buttons["settings.search.settings.pinch"].waitForExistence(timeout: 5), word)
            let field = app.searchFields.firstMatch
            field.buttons.firstMatch.tap()
        }
        // The search stays active after Return; end it so the Done button shows again.
        for name in ["Cancel", "Close"] where app.buttons[name].exists {
            app.buttons[name].tap()
        }
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
        assertPinchChangesNothing(app, lensInUse: "Wide", "set to Off in Settings")
    }

    /// 8. With one rear lens the row isn't there and search doesn't find it.
    @MainActor
    func testPinchSettingIsAbsentWithOneRearLens() throws {
        let app = launch("noRAW")
        waitForThePinchCamera(app)
        openSettings(app)
        settingsElement(app, "settings.focusOnFaces")
        XCTAssertFalse(app.descendants(matching: .any)["settings.pinch"].exists)
        searchSettings(app, for: "pinch")
        XCTAssertFalse(app.buttons["settings.search.settings.pinch"].waitForExistence(timeout: 2))
    }

    // MARK: - 9. Accessibility audits

    /// 9. The camera with the label showing passes the audit: by default, in Night Mode and
    /// right to left. Increase Contrast has no launch argument; it is a device check
    /// (docs/TESTING.md, "Pinch to switch lenses on a device").
    @MainActor
    func testPinchLabelPassesAccessibilityAudits() throws {
        for arguments in [[], Self.nightModeOn, Self.rightToLeft] {
            let app = launch("slowSaving", extraArguments: Self.pinchLabelStays + arguments)
            waitForThePinchCamera(app)
            pinchOnViewfinder(app, scale: 1.5)
            XCTAssertTrue(lensBecomesSelected(app, "Telephoto"))
            XCTAssertTrue(app.descendants(matching: .any)["lensPinchLabel"].waitForExistence(timeout: 5))
            try audit(app, checksContrast: !isPad)
        }
    }

    /// 9. Settings with the Pinch row passes the audit at the largest text size and right to
    /// left.
    @MainActor
    func testPinchSettingPassesAccessibilityAudits() throws {
        for arguments in [Self.largestTextSize, Self.rightToLeft] {
            let app = launch("slowSaving", extraArguments: arguments)
            waitForThePinchCamera(app)
            openSettings(app)
            // Search opens the list scrolled to the row, however tall the rows above it are.
            searchSettings(app, for: "pinch")
            let result = app.buttons["settings.search.settings.pinch"]
            XCTAssertTrue(result.waitForExistence(timeout: 5))
            result.tap()
            let row = app.descendants(matching: .any).matching(identifier: "settings.pinch").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            try audit(app, afterScrolling: true, checksContrast: !isPad)
        }
    }

    // MARK: - 10. Sideways

    /// 10. Held sideways (iPhone) or turned to landscape (iPad): tests 1 and 5 again.
    @MainActor
    func testPinchSideways() throws {
        let app = launch("aids")
        waitForThePinchCamera(app)
        if isPad {
            rotate(app, to: .landscapeRight)
        } else {
            try turnSideways(app)
        }
        try assertAPinchIsOnlyALensChange(app)
    }
}
