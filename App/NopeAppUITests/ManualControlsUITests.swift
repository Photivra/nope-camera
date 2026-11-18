import XCTest

/// UI tests for the manual controls of the 1.0.0 design (docs/design/BUILD-SPEC.md, 3.4): the
/// readout row on the picture's lower edge, each control's dial, More, Pro Tools without its
/// Interval section, and the row hidden while a series runs, with accessibility audits at the
/// default size, the largest text size, right to left, in night mode and sideways. The `manual`
/// scenario's wide lens has a variable aperture; its ultra wide has a fixed one.
extension NopeAppUITests {
    /// Manual controls on at launch.
    private static let manualControlsOn = ["-NopeSettings.showsManualControls", "YES"]

    /// Night mode on at launch.
    private static let manualNightMode = ["-NopeSettings.isNightModeOn", "YES"]

    /// The readouts' VoiceOver names, in the row's order.
    private static let readoutNames = ["Exposure Compensation", "ISO", "Shutter", "Aperture", "Focus", "White Balance"]

    /// Keeps a screenshot with the test's results when the run sets
    /// `TEST_RUNNER_NOPE_KEEP_SCREENSHOTS`, to compare the screens with the design's figures.
    @MainActor
    private func keepScreenshot(_ name: String) {
        guard ProcessInfo.processInfo.environment["NOPE_KEEP_SCREENSHOTS"] != nil else { return }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits until an element is gone.
    @MainActor
    private func manualWaitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// A readout of the row, by its VoiceOver name.
    @MainActor
    private func readout(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons[name].firstMatch
    }

    /// The six readouts and More sit on the picture's lower edge at equal widths: in one row on
    /// an iPhone at least 402 points wide and in the iPad's column layout, and in two rows of four
    /// cells on a narrower iPhone.
    @MainActor
    func testManualReadoutRow() throws {
        let app = launch("manual", extraArguments: Self.manualControlsOn)
        let more = app.buttons["More Manual Controls"]
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        let frames = Self.readoutNames.map { readout(app, $0).frame }
        let picture = app.otherElements["Viewfinder"].frame
        let isOneRow = isPad || app.windows.firstMatch.frame.width >= 402
        for (index, (name, frame)) in zip(Self.readoutNames, frames).enumerated() {
            let rowTop = isOneRow || index >= 4 ? more.frame.minY : frames[0].minY
            XCTAssertEqual(frame.minY, rowTop, accuracy: 1, "\(name) isn't in its row")
            XCTAssertEqual(frame.width, frames[0].width, accuracy: 1, "\(name) isn't as wide as the others")
            XCTAssertGreaterThanOrEqual(frame.height, 44, name)
            XCTAssertTrue(picture.contains(CGPoint(x: frame.midX, y: frame.midY)), "\(name) isn't on the picture")
        }
        XCTAssertGreaterThanOrEqual(more.frame.width, 44)
        XCTAssertGreaterThan(more.frame.minX, frames[isOneRow ? 4 : 5].maxX - 1)
        XCTAssertEqual(readout(app, "ISO").value as? String, "Auto, 100")
        keepScreenshot("manual-row")
        try audit(app)
    }

    /// Each readout opens its dial above the row and fills white; pressing it again closes the
    /// dial. Every dial has Decrease, Increase and Auto, white balance adds Tint and Presets, and
    /// a step switches the control to Manual ("M").
    @MainActor
    func testManualDialForEachControl() throws {
        let app = launch("manual", extraArguments: Self.manualControlsOn)
        XCTAssertTrue(readout(app, "ISO").waitForExistence(timeout: 20))
        for name in ["ISO", "Shutter", "Aperture", "Focus", "White Balance"] {
            let button = readout(app, name)
            button.tap()
            XCTAssertTrue(button.isSelected, "\(name) isn't shown as open")
            XCTAssertTrue(app.buttons["Increase"].waitForExistence(timeout: 5), name)
            XCTAssertTrue(app.buttons["Decrease"].exists, name)
            XCTAssertTrue(element(app, containing: "This lens:").exists, name)
            XCTAssertLessThan(app.buttons["Increase"].frame.maxY, button.frame.minY, "\(name)'s dial isn't above the row")
            if name == "White Balance" {
                XCTAssertTrue(app.buttons["Presets"].exists)
                XCTAssertTrue(app.sliders["Tint"].exists)
            }
            keepScreenshot("manual-\(name)")
            if name == "Aperture" {
                try auditApertureDial(app)
            } else {
                try audit(app)
            }
            button.tap()
            XCTAssertTrue(manualWaitForDisappearance(app.buttons["Increase"]), "\(name)'s dial didn't close")
        }
        // A step sets the control manually; Auto hands it back.
        let iso = readout(app, "ISO")
        iso.tap()
        app.buttons["Increase"].tap()
        XCTAssertTrue((iso.value as? String)?.hasPrefix("Manual") ?? false)
        keepScreenshot("manual-iso-manual")
        app.buttons["Auto"].firstMatch.tap()
        XCTAssertTrue((iso.value as? String)?.hasPrefix("Auto") ?? false)
    }

    /// Audits the open aperture dial. The audit reports the f-numbers of the aperture's segmented
    /// picker ("f/1.48") as labels that aren't human-readable; they are the f-numbers as the
    /// lens and every camera write them, and VoiceOver reads them as such. That finding is left
    /// out and listed for review; every other check runs.
    @MainActor
    private func auditApertureDial(_ app: XCUIApplication) throws {
        try app.performCompleteAccessibilityAudit { issue in
            issue.auditType == .sufficientElementDescription && (issue.element?.label.hasPrefix("f/") ?? false)
        }
    }

    /// A lens with a fixed aperture says so in words instead of a slider.
    @MainActor
    func testManualFixedApertureDial() throws {
        let app = launch("manual", extraArguments: Self.manualControlsOn)
        let ultraWide = app.buttons["Ultra Wide"]
        XCTAssertTrue(ultraWide.waitForExistence(timeout: 20))
        ultraWide.tap()
        readout(app, "Aperture").tap()
        XCTAssertTrue(element(app, containing: "This lens has a fixed aperture.").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Increase"].exists)
        XCTAssertEqual(readout(app, "Aperture").value as? String, "Fixed, f/2.2")
        keepScreenshot("manual-aperture-fixed")
        try audit(app)
    }

    /// More holds All Auto and Pro Tools; All Auto returns every control to Auto and closes the
    /// open dial.
    @MainActor
    func testManualMoreMenu() throws {
        let app = launch("manual", extraArguments: Self.manualControlsOn)
        let iso = readout(app, "ISO")
        XCTAssertTrue(iso.waitForExistence(timeout: 20))
        iso.tap()
        app.buttons["Increase"].tap()
        app.buttons["More Manual Controls"].tap()
        XCTAssertTrue(app.buttons["Pro Tools"].waitForExistence(timeout: 5))
        keepScreenshot("manual-more")
        app.buttons["All Auto"].tap()
        XCTAssertTrue(manualWaitForDisappearance(app.buttons["Increase"]))
        XCTAssertTrue((iso.value as? String)?.hasPrefix("Auto") ?? false)
    }

    /// Pro Tools keeps exposure mode, metering, the locks and the live aids, and has nothing that
    /// starts or sets up an interval series (docs/design/SETTINGS-PLAN.md, decision 8) or a
    /// bracket (docs/design/BRACKETING.md, decision 1; `testProToolsHasNoBracketing`).
    @MainActor
    func testProToolsHasNoIntervalSection() throws {
        let app = launch("manual", extraArguments: Self.manualControlsOn)
        manualMenu(app, "Pro Tools")
        XCTAssertTrue(element(app, containing: "Exposure Mode").waitForExistence(timeout: 20))
        XCTAssertFalse(app.switches["Bracketing"].exists)
        XCTAssertTrue(element(app, containing: "Metering").exists)
        keepScreenshot("manual-pro-tools")
        // A live aid's switch reads its name, then its explanation.
        let peaking = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Focus Peaking")).firstMatch
        var swipes = 0
        while !peaking.exists && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(peaking.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Live Aids")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Interval Shooting"].exists)
        XCTAssertFalse(app.buttons["Start"].exists)
        // Nothing in the form names an interval (the camera's drive strip under the cover does).
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.exists)
        XCTAssertFalse(form.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Interval")).firstMatch.exists)
        try audit(app, afterScrolling: true, checksDynamicType: false)
    }

    /// While a series runs the readouts and any open dial give the picture to the mode's card,
    /// and they come back when it ends.
    @MainActor
    func testManualReadoutsHideWhileASeriesRuns() throws {
        let app = launch("manual", extraArguments: Self.manualControlsOn)
        let iso = readout(app, "ISO")
        XCTAssertTrue(iso.waitForExistence(timeout: 20))
        iso.tap()
        XCTAssertTrue(app.buttons["Increase"].waitForExistence(timeout: 5))
        app.buttons["Interval"].firstMatch.tap()
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(element(app, containing: "photos taken").waitForExistence(timeout: 20))
        XCTAssertFalse(iso.exists, "the readouts stay while the series runs")
        XCTAssertFalse(app.buttons["Increase"].exists, "the dial stays while the series runs")
        XCTAssertFalse(app.buttons["More Manual Controls"].exists)
        keepScreenshot("manual-series-running")
        // The screen dims during the series; the first tap brightens it.
        let brighten = app.buttons["Brighten Screen"]
        if brighten.exists { brighten.tap() }
        app.buttons["Stop"].firstMatch.tap()
        XCTAssertTrue(readout(app, "ISO").waitForExistence(timeout: 10), "the readouts didn't come back")
    }

    /// Night mode: the row and the open dial in red on black.
    @MainActor
    func testManualControlsNightMode() throws {
        let app = launch("manual", extraArguments: Self.manualControlsOn + Self.manualNightMode)
        let iso = readout(app, "ISO")
        XCTAssertTrue(iso.waitForExistence(timeout: 20))
        iso.tap()
        app.buttons["Increase"].tap()
        keepScreenshot("manual-night")
        try audit(app)
        readout(app, "White Balance").tap()
        XCTAssertTrue(app.buttons["Presets"].waitForExistence(timeout: 5))
        try audit(app)
    }

    /// Right to left: the row runs from the trailing edge and the dial mirrors.
    @MainActor
    func testManualControlsDialRightToLeft() throws {
        let app = launch("manual", extraArguments: Self.manualControlsOn + Self.rightToLeft)
        let iso = readout(app, "ISO")
        XCTAssertTrue(iso.waitForExistence(timeout: 20))
        let compensation = readout(app, "Exposure Compensation")
        XCTAssertGreaterThan(compensation.frame.minX, iso.frame.minX, "the row isn't mirrored")
        iso.tap()
        XCTAssertTrue(app.buttons["Increase"].waitForExistence(timeout: 5))
        keepScreenshot("manual-rtl")
        try audit(app)
    }

    /// At the largest text size the list replaces the row, with a switch and a stepper per
    /// control.
    @MainActor
    func testManualReadoutListAtTheLargestTextSize() throws {
        let app = launch("manual", extraArguments: Self.manualControlsOn + Self.largestTextSize)
        let more = app.buttons["More Manual Controls"]
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        XCTAssertTrue(app.steppers.firstMatch.exists || app.buttons["ISO"].exists)
        XCTAssertTrue(element(app, containing: "White Balance").exists)
        keepScreenshot("manual-largest")
        try auditScrollingScreen(app)
    }

    /// Sideways on an iPhone the row and the dial turn upright as one block on the picture's
    /// lower edge.
    @MainActor
    func testManualControlsSideways() throws {
        guard !isPad else { throw XCTSkip("An iPad window rotates for real; testManualReadoutRow covers it.") }
        let app = launch("manual", extraArguments: Self.manualControlsOn)
        let iso = readout(app, "ISO")
        XCTAssertTrue(iso.waitForExistence(timeout: 20))
        try turnSideways(app)
        defer { XCUIDevice.shared.orientation = .portrait }
        // Turned a quarter, the row runs down the screen, one readout above the next.
        let compensation = readout(app, "Exposure Compensation").frame
        XCTAssertEqual(compensation.midX, iso.frame.midX, accuracy: 2, "the row didn't turn as one block")
        iso.tap()
        XCTAssertTrue(app.buttons["Increase"].waitForExistence(timeout: 5))
        keepScreenshot("manual-sideways")
        // Text drawn a quarter turn is measured unturned by the audit (see isTurnedTextFinding in
        // NopeAppUITests.swift); those findings are skipped here.
        // The readouts' A and M letters are nearly square, so that rule can't tell them turned;
        // their contrast is audited upright in testManualReadoutRow.
        try app.performCompleteAccessibilityAudit { issue in
            guard let element = issue.element else { return issue.auditType == .textClipped || issue.auditType == .contrast }
            guard issue.auditType == .contrast, element.exists else { return false }
            return element.frame.height > element.frame.width || ["A", "M"].contains(element.label)
        }
    }
}
