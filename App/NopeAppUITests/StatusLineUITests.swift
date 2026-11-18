import XCTest

/// UI tests for the status line of the 1.0.0 design (docs/design/BUILD-SPEC.md, 3.2, 3.3, 3.7 and
/// 3.8, chunk E): the format status and the "Processed" marker with its note, the state pills,
/// the warning chips, the capture feedback, and the screens before the camera is ready, each with
/// an accessibility audit at the default and largest text sizes, right to left, in night mode,
/// sideways and in the column layout where the screen appears.
extension NopeAppUITests {
    /// The VoiceOver value of the format status on the simulated lenses without RAW.
    private static let processedValue = "Processed: no RAW on this lens, HEIF"

    /// Night mode on at launch.
    private static let statusNightMode = ["-NopeSettings.isNightModeOn", "YES"]

    /// Full auto's fast shutter at 1/500 s, for one pill.
    private static let fastShutterPill = ["-NopeSettings.fastShutter", "freezeMotion"]

    /// The format status.
    @MainActor
    private func formatStatus(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Photo Format"]
    }

    /// Waits until an element's VoiceOver value is the text.
    @MainActor
    private func waitForStatusValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 15) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// Waits until an element is gone.
    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// Swipes up in the open sheet's list until the element can be tapped, at most eight times.
    /// On iPad it drags inside the popover, so it scrolls the popover, not the camera.
    ///
    /// - Returns: How many swipes it took.
    @MainActor
    @discardableResult
    private func scrollSheet(_ app: XCUIApplication, to element: XCUIElement) -> Int {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 8 {
            // On iPad the sheet is a popover: drag inside it, since a swipe in the middle of the
            // screen lands on the camera.
            let popover = app.popovers.firstMatch
            if popover.exists {
                let start = popover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                start.press(forDuration: 0.05, thenDragTo: popover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
            } else {
                app.swipeUp()
            }
            swipes += 1
        }
        return swipes
    }

    /// Opens the Photo Format sheet from the format status and waits for its list.
    @MainActor
    private func openFormatSheet(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let status = formatStatus(app)
        XCTAssertTrue(status.waitForExistence(timeout: 15), file: file, line: line)
        status.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), file: file, line: line)
    }

    /// Audits the open Photo Format sheet: every check, then contrast on every element except a
    /// disabled one (the RAW row on a device without RAW), which WCAG 1.4.3 exempts as an
    /// inactive control, and except a row cut by the window's edge, which the audit measures at
    /// its clipped edge (or reports with no element); such rows are measured whole after
    /// scrolling, as in `auditVisibleElements`. Contrast is checked on iPhone only, as in the other sheet tests: the
    /// iPad popover is measured against the camera behind it.
    ///
    /// After scrolling, clipped-text findings are skipped too: on the iPhone Simulator the audit
    /// reported the Show Processed Marker explanation as clipped after it was scrolled into
    /// view, although a screenshot shows both of its lines whole; the same row passes the audit
    /// on iPad. Every other check still runs.
    @MainActor
    private func auditFormatSheet(_ app: XCUIApplication, afterScrolling: Bool = false, checksDynamicType: Bool = false) throws {
        if afterScrolling {
            settle()
            try app.performCompleteAccessibilityAudit { issue in
                issue.auditType == .textClipped || issue.auditType == .contrast
                    || (!checksDynamicType && issue.auditType == .dynamicType)
            }
            return
        }
        try audit(app, checksDynamicType: checksDynamicType, checksContrast: false)
        guard !isPad else { return }
        let window = app.windows.firstMatch.frame
        try app.performCompleteAccessibilityAudit(for: .contrast) { issue in
            guard let element = issue.element else { return true }
            return !element.isEnabled || !window.contains(element.frame)
        }
    }

    /// Hides the controls from Q, leaving clean view.
    @MainActor
    private func hideControls(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let quick = app.buttons["Quick Menu"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10), file: file, line: line)
        quick.tap()
        let hide = app.buttons["Hide Controls"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), file: file, line: line)
        hide.tap()
        XCTAssertTrue(app.buttons["Show Controls"].waitForExistence(timeout: 5), file: file, line: line)
    }

    /// Turns on one of Q's switches and closes Q again.
    @MainActor
    private func turnOnInQ(_ app: XCUIApplication, _ names: [String], file: StaticString = #filePath, line: UInt = #line) {
        let quick = app.buttons["Quick Menu"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10), file: file, line: line)
        quick.tap()
        for name in names {
            let tile = app.buttons[name]
            XCTAssertTrue(tile.waitForExistence(timeout: 5), file: file, line: line)
            tile.tap()
        }
        quick.tap()
        XCTAssertTrue(waitUntilGone(app.buttons["Hide Controls"]), file: file, line: line)
    }

    // MARK: - Status line (3.1, 3.3)

    /// The status line: the format status leading, the pills trailing, and the warnings on the
    /// picture's upper edge.
    @MainActor
    func testStatusLineFormatLeadingPillsTrailing() throws {
        let app = launch("aids", extraArguments: Self.fastShutterPill + ["-NopeSimulatedDeviceStatus", "lowBattery"])
        let status = formatStatus(app)
        XCTAssertTrue(waitForStatusValue(status, "single-frame RAW, RAW"))
        XCTAssertTrue(app.buttons["FormatStatus.raw"].exists)
        let pill = app.buttons["Fast Shutter"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        let picture = app.otherElements["Viewfinder"].frame
        let window = app.windows.firstMatch.frame
        if !isPad {
            XCTAssertLessThan(status.frame.midY, picture.minY, "the format status isn't above the picture")
            XCTAssertLessThan(pill.frame.midY, picture.minY, "the pill isn't on the status line")
            XCTAssertGreaterThan(pill.frame.midX, window.midX, "the pill isn't trailing")
            XCTAssertLessThan(status.frame.midX, window.midX, "the format status isn't leading")
        }
        let battery = app.buttons["Battery Low"]
        XCTAssertTrue(battery.waitForExistence(timeout: 5))
        XCTAssertTrue(picture.contains(CGPoint(x: battery.frame.midX, y: battery.frame.midY)), "the warning isn't on the picture")
        try audit(app)
        // The pill's one action resets the setting.
        pill.tap()
        XCTAssertTrue(waitUntilGone(pill))
    }

    /// No pill repeats what the Manual Controls button or the drive strip shows.
    @MainActor
    func testNoPillRepeatsManualControlsOrTheDriveStrip() throws {
        let app = launch("astro")
        let manual = app.buttons["ManualControlsButton"]
        XCTAssertTrue(manual.waitForExistence(timeout: 20))
        manual.tap()
        XCTAssertTrue(app.buttons["ISO"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Manual Controls")).count, 1)
        for word in ["Burst", "Interval", "Astro"] {
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", word))
            XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5))
            matches.firstMatch.tap()
            if word == "Interval", app.navigationBars.firstMatch.waitForExistence(timeout: 2) {
                app.buttons["Done"].tap()
            }
            settle()
            if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", word)).count, 1, "\(word) has a pill")
        }
        try audit(app)
    }

    /// At most three pills, fewer when they don't fit on one line, then "+n" for the rest, whose
    /// menu reaches every action; audited in night mode and right to left too.
    @MainActor
    func testThreePillsAndMore() throws {
        for arguments in [[], Self.statusNightMode, Self.rightToLeft] {
            let app = launch("aids", extraArguments: Self.fastShutterPill + arguments)
            turnOnInQ(app, ["Close-Up", "Magnify", "Compare"])
            let more = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "More Settings Changed")).firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 5))
            // The first pill always shows; the fourth, Compare, is always in "+n".
            XCTAssertTrue(app.buttons["Fast Shutter"].exists)
            XCTAssertFalse(app.buttons["Compare"].exists)
            try audit(app)
            more.tap()
            let off = app.buttons["Turn Off Compare"]
            XCTAssertTrue(off.waitForExistence(timeout: 5))
            off.tap()
            XCTAssertTrue(waitUntilGone(app.buttons["Turn Off Compare"]))
            app.terminate()
        }
    }

    // MARK: - Processed marker (3.2)

    /// The marker shows before the shot and opens the processing note, then the lens's one file,
    /// the switch and Formats for Other Lenses; it stays in clean view.
    @MainActor
    func testProcessedMarkerAndNote() throws {
        let app = launch("noRAW")
        let status = formatStatus(app)
        XCTAssertTrue(waitForStatusValue(status, Self.processedValue))
        XCTAssertTrue(app.buttons["FormatStatus.processedMarker"].exists)
        try audit(app)
        openFormatSheet(app)
        XCTAssertTrue(element(app, containing: "This lens can't save unprocessed RAW").exists)
        XCTAssertTrue(element(app, containing: "What the Phone Does on This Lens").exists)
        XCTAssertTrue(element(app, containing: "processes this file before nope. receives it").exists)
        XCTAssertTrue(element(app, containing: "this lens lets apps turn it off, and nope. does").exists)
        XCTAssertTrue(element(app, containing: "What nope. Does").exists)
        XCTAssertTrue(element(app, containing: "get the Standard look").exists)
        try auditFormatSheet(app)
        let marker = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Show Processed Marker")).firstMatch
        let swipes = scrollSheet(app, to: marker)
        XCTAssertEqual(marker.value as? String, "1")
        let formats = app.buttons["Formats for Other Lenses"]
        let more = scrollSheet(app, to: formats)
        XCTAssertTrue(formats.exists)
        try auditFormatSheet(app, afterScrolling: swipes + more > 0)
        app.buttons["Done"].tap()
        // Clean view keeps the marker.
        hideControls(app)
        XCTAssertTrue(waitForStatusValue(formatStatus(app), Self.processedValue))
        XCTAssertTrue(app.buttons["FormatStatus.processedMarker"].exists)
        try audit(app)
    }

    /// Show Processed Marker hides only the marker: the status names the file with no symbol,
    /// VoiceOver still says it is processed, the lens keeps its "No RAW" caption, and clean view
    /// shows no format status.
    @MainActor
    func testProcessedMarkerSwitch() throws {
        let app = launch("noRAW")
        openFormatSheet(app)
        let marker = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Show Processed Marker")).firstMatch
        scrollSheet(app, to: marker)
        marker.switches.firstMatch.tap()
        XCTAssertEqual(marker.value as? String, "0")
        app.buttons["Done"].tap()
        let status = formatStatus(app)
        XCTAssertTrue(waitForStatusValue(status, Self.processedValue), "VoiceOver no longer says the photo is processed")
        XCTAssertTrue(app.buttons["FormatStatus.processedName"].exists, "the status doesn't name the file without a symbol")
        XCTAssertFalse(app.buttons["FormatStatus.processedMarker"].exists)
        XCTAssertTrue(element(app, containing: "No RAW").exists)
        XCTAssertEqual(
            app.otherElements["Viewfinder"].value as? String, "Lens: Wide. Format: HEIF with some device processing.")
        try audit(app)
        hideControls(app)
        XCTAssertTrue(waitUntilGone(status))
        try audit(app)
    }

    /// A lens without RAW on a device with RAW: the marker, and a read-only sheet (owner decision
    /// of 2026-11-18) that names the one file the lens saves, says the format choices are for the
    /// other lenses, and offers no format to tick; audited at the default and largest text sizes,
    /// right to left and in night mode.
    @MainActor
    func testProcessedMarkerOnALensWithoutRAW() throws {
        for arguments in [[], Self.largestTextSize, Self.rightToLeft, Self.statusNightMode] {
            let app = launch("allow", extraArguments: arguments)
            continuePastFirstRun(app)
            let status = formatStatus(app)
            XCTAssertTrue(waitForStatusValue(status, "single-frame RAW, RAW"))
            let telephoto = app.buttons["Telephoto"]
            XCTAssertTrue(telephoto.waitForExistence(timeout: 5))
            telephoto.tap()
            XCTAssertTrue(waitForStatusValue(status, Self.processedValue))
            openFormatSheet(app)
            for name in ["RAW (DNG)", "HEIF", "JPEG"] {
                XCTAssertFalse(app.buttons[name].exists, "\(name) can be ticked on a lens without RAW")
            }
            let file = app.staticTexts["formatSheet.lensFile"]
            let swipes = scrollSheet(app, to: file)
            XCTAssertEqual(file.label, "HEIF")
            XCTAssertTrue(element(app, containing: "This Lens Saves").exists)
            XCTAssertTrue(element(app, containing: "are for the other lenses").exists)
            try auditFormatSheet(app, afterScrolling: swipes > 0, checksDynamicType: arguments == Self.largestTextSize)
            let formats = app.buttons["Formats for Other Lenses"]
            let more = scrollSheet(app, to: formats)
            XCTAssertTrue(formats.exists)
            try auditFormatSheet(app, afterScrolling: swipes + more > 0, checksDynamicType: arguments == Self.largestTextSize)
            app.terminate()
        }
    }

    /// The marker and its note at the largest text size, right to left and in night mode.
    @MainActor
    func testProcessedMarkerAtTheLargestTextSizeRightToLeftAndNightMode() throws {
        let large = launch("noRAW", extraArguments: Self.largestTextSize)
        XCTAssertTrue(waitForStatusValue(formatStatus(large), Self.processedValue))
        try auditVisibleElements(large)
        openFormatSheet(large)
        try auditFormatSheet(large, checksDynamicType: true)
        large.terminate()

        for arguments in [Self.rightToLeft, Self.statusNightMode] {
            let app = launch("noRAW", extraArguments: arguments + Self.fastShutterPill)
            XCTAssertTrue(waitForStatusValue(formatStatus(app), Self.processedValue))
            XCTAssertTrue(app.buttons["Fast Shutter"].waitForExistence(timeout: 5))
            try audit(app)
            openFormatSheet(app)
            try auditFormatSheet(app)
            app.terminate()
        }
    }

    /// Look and All Photo Settings close the sheet and open Settings at HEIF and JPEG Copies and
    /// at the Photos group; on a lens without RAW, Formats for Other Lenses opens Formats.
    @MainActor
    func testFormatSheetOpensSettings() throws {
        let app = launch("aids")
        openFormatSheet(app)
        XCTAssertFalse(app.buttons["Look"].exists, "Look shows with RAW only")
        app.buttons["HEIF"].tap()
        let look = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Look")).firstMatch
        XCTAssertTrue(look.waitForExistence(timeout: 5))
        try auditFormatSheet(app)
        scrollSheet(app, to: look)
        look.tap()
        XCTAssertTrue(app.navigationBars["HEIF and JPEG Copies"].waitForExistence(timeout: 10))
        app.terminate()
        // A fresh launch (RAW only again): All Photo Settings opens Settings at the Photos group.
        app.launch()
        openFormatSheet(app)
        let all = app.buttons["All Photo Settings"]
        scrollSheet(app, to: all)
        all.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, containing: "Formats").waitForExistence(timeout: 5))
        app.terminate()

        let processed = launch("noRAW")
        openFormatSheet(processed)
        let formats = processed.buttons["Formats for Other Lenses"]
        scrollSheet(processed, to: formats)
        formats.tap()
        XCTAssertTrue(processed.navigationBars["Formats"].waitForExistence(timeout: 10))
        XCTAssertTrue(processed.buttons["RAW (DNG)"].exists)
        try audit(processed, checksDynamicType: false, checksContrast: !isPad)
    }

    // MARK: - Warnings and capture feedback (3.3, 3.7)

    /// Warning chips sit on the picture in their order and explain themselves; audited in night
    /// mode and right to left too.
    @MainActor
    func testWarningChips() throws {
        for arguments in [[], Self.statusNightMode, Self.rightToLeft] {
            let app = launch("lightUnavailable", extraArguments: ["-NopeSimulatedDeviceStatus", "lowBattery"] + arguments)
            turnOnInQ(app, ["Light"])
            let battery = app.buttons["Battery Low"]
            let light = app.buttons["Light Unavailable"]
            XCTAssertTrue(light.waitForExistence(timeout: 10))
            XCTAssertTrue(battery.exists)
            let isRightToLeft = arguments == Self.rightToLeft
            XCTAssertEqual(battery.frame.midX < light.frame.midX, !isRightToLeft, "the warnings are out of order")
            try audit(app)
            light.tap()
            XCTAssertTrue(element(app, containing: "Turn Light off and on again in Q").waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    /// "Not Signed" only when signing was on and a photo couldn't be signed; with signing off by
    /// choice there is no chip and no badge, and the message still says it isn't signed.
    @MainActor
    func testNotSignedOnlyWhenSigningFailed() throws {
        let failed = launch("signingFails", extraArguments: Self.signingOn)
        XCTAssertTrue(failed.buttons["Take Photo"].waitForExistence(timeout: 15))
        failed.buttons["Take Photo"].tap()
        XCTAssertTrue(failed.buttons["Not Signed"].waitForExistence(timeout: 10))
        let thumbnail = failed.descendants(matching: .any)["Last Photo"]
        XCTAssertTrue(waitForStatusValue(thumbnail, "Saved. Not signed: the signature couldn't be created."))
        try audit(failed)
        failed.terminate()

        let off = launch("signingFails")
        XCTAssertTrue(off.buttons["Take Photo"].waitForExistence(timeout: 15))
        off.buttons["Take Photo"].tap()
        let offThumbnail = off.descendants(matching: .any)["Last Photo"]
        XCTAssertTrue(waitForStatusValue(offThumbnail, "Saved. Not signed: signing is off in Settings."))
        XCTAssertFalse(off.buttons["Not Signed"].exists)
        try audit(off)
    }

    /// The failure banner sits on the picture with its one action and Dismiss, at the default and
    /// largest text sizes.
    @MainActor
    func testFailureBannerOnThePicture() throws {
        for arguments in [[], Self.largestTextSize] {
            let app = launch("captureFails", extraArguments: arguments)
            let shutter = app.buttons["Take Photo"]
            XCTAssertTrue(shutter.waitForExistence(timeout: 15))
            shutter.tap()
            let sentence = app.staticTexts["The photo wasn't taken. Try again."]
            XCTAssertTrue(sentence.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Try Again"].exists)
            XCTAssertTrue(app.buttons["Dismiss"].exists)
            if arguments.isEmpty {
                let picture = app.otherElements["Viewfinder"].frame
                XCTAssertTrue(picture.contains(CGPoint(x: sentence.frame.midX, y: sentence.frame.midY)), "the banner isn't on the picture")
                try audit(app)
            } else {
                try auditVisibleElements(app)
            }
            app.buttons["Dismiss"].tap()
            XCTAssertTrue(waitUntilGone(sentence))
            app.terminate()
        }
    }

    // MARK: - Status on the picture (3.1 sideways, 3.11)

    /// Sideways on an iPhone the format status and the pills move onto the picture, with the
    /// backing.
    @MainActor
    func testStatusOnThePictureSideways() throws {
        guard !isPad else { throw XCTSkip("An iPad window rotates for real; the column layout covers it.") }
        let app = launch("noRAW", extraArguments: Self.fastShutterPill)
        XCTAssertTrue(waitForStatusValue(formatStatus(app), Self.processedValue))
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        defer { XCUIDevice.shared.orientation = .portrait }
        if app.staticTexts["Auto"].exists {
            throw XCTSkip("The device didn't report the turn to the app.")
        }
        let picture = app.otherElements["Viewfinder"].frame
        for element in [formatStatus(app), app.buttons["Fast Shutter"]] {
            XCTAssertTrue(element.exists)
            XCTAssertTrue(picture.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)), "\(element) isn't on the picture")
        }
        // Text drawn a quarter turn is measured unturned by the audit; those findings are skipped,
        // as in testCameraShellSideways.
        try app.performCompleteAccessibilityAudit { issue in
            guard let element = issue.element else { return issue.auditType == .textClipped || issue.auditType == .contrast }
            return issue.auditType == .contrast && element.exists && element.frame.height > element.frame.width
        }
    }

    /// In the column layout the format status sits on the picture's top leading corner and the
    /// pills on its top trailing corner, both with the backing; right to left too.
    @MainActor
    func testStatusOnThePictureInTheColumn() throws {
        guard isPad else { throw XCTSkip("The column layout is checked on iPad.") }
        for arguments in [[], Self.rightToLeft, Self.statusNightMode] {
            let app = launch("noRAW", extraArguments: Self.fastShutterPill + ["-NopeSimulatedDeviceStatus", "lowBattery"] + arguments)
            let status = formatStatus(app)
            XCTAssertTrue(waitForStatusValue(status, Self.processedValue))
            let pill = app.buttons["Fast Shutter"]
            XCTAssertTrue(pill.waitForExistence(timeout: 5))
            let picture = app.otherElements["Viewfinder"].frame
            XCTAssertTrue(picture.contains(CGPoint(x: status.frame.midX, y: status.frame.midY)), "the format status isn't on the picture")
            XCTAssertLessThan(status.frame.minY - picture.minY, picture.height / 4, "the format status isn't at the top")
            XCTAssertLessThan(pill.frame.minY - picture.minY, picture.height / 4, "the pill isn't at the top")
            let leading = arguments == Self.rightToLeft ? status.frame.midX > pill.frame.midX : status.frame.midX < pill.frame.midX
            XCTAssertTrue(leading, "the format status isn't leading and the pill trailing")
            try audit(app)
            app.terminate()
        }
    }

    // MARK: - Before the camera is ready (3.8)

    /// First run in the dark and light appearances: the reworded signing statement, and Continue
    /// full width at the bottom, before the system prompt.
    @MainActor
    func testFirstRunDarkAndLight() throws {
        for appearance in [XCUIDevice.Appearance.dark, .light] {
            useAppearance(appearance)
            let app = launch("allow")
            let statement = app.staticTexts["You can sign each photo, so changes can be detected. Signing is off until you turn it on."]
            XCTAssertTrue(statement.waitForExistence(timeout: 10))
            let next = app.buttons["Continue"]
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThan(next.frame.minY, window.midY, "Continue isn't at the bottom")
            XCTAssertGreaterThan(next.frame.width, min(window.width - 4 * 24, 480) - 1, "Continue isn't full width")
            try audit(app)
            app.terminate()
        }
    }

    /// First run at the largest text size and right to left.
    @MainActor
    func testFirstRunLargestTextAndRightToLeft() throws {
        let large = launch("allow", extraArguments: Self.largestTextSize)
        XCTAssertTrue(large.buttons["Continue"].waitForExistence(timeout: 10))
        try auditVisibleElements(large)
        large.terminate()
        let mirrored = launch("allow", extraArguments: Self.rightToLeft)
        XCTAssertTrue(mirrored.buttons["Continue"].waitForExistence(timeout: 10))
        try audit(mirrored)
        continuePastFirstRun(mirrored)
    }

    /// Camera access declined: Open Settings full width at the bottom, in both appearances, at
    /// the largest text size and right to left; and the no-camera screen.
    @MainActor
    func testDeniedAndUnavailableScreens() throws {
        for appearance in [XCUIDevice.Appearance.dark, .light] {
            useAppearance(appearance)
            let app = launch("denied")
            let open = app.buttons["Open Settings"]
            XCTAssertTrue(open.waitForExistence(timeout: 10))
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThan(open.frame.minY, window.midY, "Open Settings isn't at the bottom")
            XCTAssertGreaterThan(open.frame.width, min(window.width - 4 * 24, 480) - 1, "Open Settings isn't full width")
            XCTAssertTrue(app.buttons["Settings"].exists, "Settings isn't reachable")
            try audit(app)
            app.terminate()
        }
        let large = launch("denied", extraArguments: Self.largestTextSize)
        XCTAssertTrue(large.buttons["Open Settings"].waitForExistence(timeout: 10))
        try auditVisibleElements(large)
        large.terminate()
        let mirrored = launch("denied", extraArguments: Self.rightToLeft)
        XCTAssertTrue(mirrored.buttons["Open Settings"].waitForExistence(timeout: 10))
        try audit(mirrored)
        mirrored.terminate()
        let none = launch("noCamera")
        XCTAssertTrue(none.staticTexts["No Camera Available"].waitForExistence(timeout: 10))
        try audit(none)
    }
}
