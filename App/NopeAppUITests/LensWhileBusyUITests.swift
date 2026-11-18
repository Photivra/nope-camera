import XCTest

/// The lens controls while the camera is busy (issue #96; docs/design/lens-while-busy.md,
/// section 7): during a countdown or an interval series every lens control stays where it is,
/// the lens in use enabled and selected, the others and Switch Camera disabled; a press on a
/// disabled one changes nothing. They run on iPhone (stacked layout) and iPad (column layout).
extension NopeAppUITests {
    /// The rear lenses of the `slowSaving` scenario, by their VoiceOver names.
    private static let otherLensNames = ["Ultra Wide", "Telephoto"]

    /// The lens in use at launch.
    private static let lensInUse = "Wide"

    /// The lens control of that name: a lens button, or a lens row at the largest text sizes.
    @MainActor
    private func lensControl(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// Waits until an element's `isEnabled` is the given value.
    @MainActor
    private func waitUntil(_ element: XCUIElement, isEnabled: Bool, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "enabled == %@", NSNumber(value: isEnabled))
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// Checks the lens controls while busy: every one exists, the lens in use is enabled and
    /// selected, the other lenses and Switch Camera (where the layout has it) are not enabled.
    @MainActor
    private func assertLensControlsAreBusy(
        _ app: XCUIApplication, hasSwitchCamera: Bool = true, file: StaticString = #filePath, line: UInt = #line
    ) {
        let inUse = lensControl(app, Self.lensInUse)
        XCTAssertTrue(inUse.exists, "the lens in use is shown", file: file, line: line)
        XCTAssertTrue(inUse.isEnabled, "the lens in use stays enabled", file: file, line: line)
        XCTAssertTrue(inUse.isSelected, "the lens in use stays selected", file: file, line: line)
        for name in Self.otherLensNames {
            let lens = lensControl(app, name)
            XCTAssertTrue(lens.exists, "\(name) is still shown", file: file, line: line)
            XCTAssertTrue(waitUntil(lens, isEnabled: false), "\(name) is disabled", file: file, line: line)
        }
        if hasSwitchCamera {
            let flip = app.buttons["Switch Camera"]
            XCTAssertTrue(flip.exists, "Switch Camera is still shown", file: file, line: line)
            XCTAssertTrue(waitUntil(flip, isEnabled: false), "Switch Camera is disabled", file: file, line: line)
        }
    }

    /// Checks that every lens control is enabled again.
    @MainActor
    private func assertLensControlsAreFree(
        _ app: XCUIApplication, hasSwitchCamera: Bool = true, file: StaticString = #filePath, line: UInt = #line
    ) {
        for name in Self.otherLensNames + [Self.lensInUse] {
            XCTAssertTrue(waitUntil(lensControl(app, name), isEnabled: true), "\(name) is enabled", file: file, line: line)
        }
        if hasSwitchCamera {
            XCTAssertTrue(waitUntil(app.buttons["Switch Camera"], isEnabled: true), "Switch Camera is enabled", file: file, line: line)
        }
    }

    /// Starts the 10-second self-timer from the shutter.
    @MainActor
    private func startTenSecondTimer(_ app: XCUIApplication) {
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 20))
        chooseDrive(app, "Timer: 10s")
        shutter.tap()
        XCTAssertTrue(app.buttons["Cancel Timer"].waitForExistence(timeout: 5))
    }

    /// Starts an interval series from the shutter and brightens the screen it dims.
    @MainActor
    private func startIntervalSeries(_ app: XCUIApplication) {
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 20))
        chooseDrive(app, "Interval")
        shutter.tap()
        XCTAssertTrue(element(app, containing: "photos taken").waitForExistence(timeout: 20))
        let brighten = app.buttons["Brighten Screen"]
        if brighten.waitForExistence(timeout: 10) {
            brighten.tap()
            _ = brighten.waitForNonExistence(timeout: 3)
        }
    }

    /// 4. During a self-timer countdown every lens button and Switch Camera stays in place; only
    /// the lens in use is enabled. After Cancel Timer all are enabled again.
    @MainActor
    func testLensControlsAreDisabledInPlaceDuringTheCountdown() throws {
        let app = launch("slowSaving")
        let inUse = lensControl(app, Self.lensInUse)
        XCTAssertTrue(inUse.waitForExistence(timeout: 20))
        assertLensControlsAreFree(app)
        let frames = (Self.otherLensNames + [Self.lensInUse]).map { lensControl(app, $0).frame } + [app.buttons["Switch Camera"].frame]

        startTenSecondTimer(app)
        assertLensControlsAreBusy(app)
        let busyFrames = (Self.otherLensNames + [Self.lensInUse]).map { lensControl(app, $0).frame } + [app.buttons["Switch Camera"].frame]
        XCTAssertEqual(busyFrames, frames, "nothing moved")
        // No audit here: it can outlast the ten seconds; testLensControlsAreDisabledDuringAnIntervalSeries
        // audits the same disabled controls.

        app.buttons["Cancel Timer"].tap()
        XCTAssertTrue(app.buttons["Cancel Timer"].waitForNonExistence(timeout: 5))
        assertLensControlsAreFree(app)
        let freeFrames = (Self.otherLensNames + [Self.lensInUse]).map { lensControl(app, $0).frame } + [app.buttons["Switch Camera"].frame]
        XCTAssertEqual(freeFrames, frames, "nothing moved")
    }

    /// 5. The same during an interval series, the waits between photos included: at the default
    /// text size, in night mode and right to left, each with the accessibility audit.
    @MainActor
    func testLensControlsAreDisabledDuringAnIntervalSeries() throws {
        for arguments in [[], Self.nightModeOn, Self.rightToLeft] {
            let app = launch("slowSaving", extraArguments: arguments)
            startIntervalSeries(app)
            XCTAssertTrue(element(app, containing: "Next photo in").waitForExistence(timeout: 15), "a wait between photos")
            assertLensControlsAreBusy(app)
            try audit(app)
            app.buttons["Stop"].tap()
            XCTAssertFalse(element(app, containing: "photos taken").waitForExistence(timeout: 5))
            assertLensControlsAreFree(app)
        }
    }

    /// 5. At the largest text size the lens rows stay in the list: the row in use enabled and
    /// selected, the others disabled.
    @MainActor
    func testLensRowsAreDisabledDuringAnIntervalSeriesAtTheLargestTextSize() throws {
        let app = launch("slowSaving", extraArguments: Self.largestTextSize)
        startIntervalSeries(app)
        // The scrolling layout lists the front camera as a row and has no Switch Camera.
        assertLensControlsAreBusy(app, hasSwitchCamera: false)
        XCTAssertFalse(lensControl(app, "Front").isEnabled)
        // iPad: an open contrast finding over the picture and at the largest size (docs/TESTING.md).
        try auditScrollingScreen(app, checksContrast: !isPad)
        app.buttons["Stop"].tap()
        XCTAssertFalse(element(app, containing: "photos taken").waitForExistence(timeout: 5))
        assertLensControlsAreFree(app, hasSwitchCamera: false)
    }

    /// 6. The close-up hint during a countdown: the sentence and Dismiss stay; only "Switch to
    /// Ultra Wide" is disabled.
    @MainActor
    func testTheCloseUpSwitchIsDisabledDuringTheCountdown() throws {
        let app = launch("tooClose")
        let switchLens = app.buttons["Switch to Ultra Wide"]
        XCTAssertTrue(switchLens.waitForExistence(timeout: 20))
        XCTAssertTrue(switchLens.isEnabled)
        startTenSecondTimer(app)
        XCTAssertTrue(switchLens.exists)
        XCTAssertTrue(waitUntil(switchLens, isEnabled: false))
        XCTAssertTrue(element(app, containing: "The subject may be too close to focus.").exists)
        XCTAssertTrue(app.buttons["Dismiss"].isEnabled)
        try audit(app)
        // The audit can outlast the countdown; then its photo ends the busy state instead.
        let cancel = app.buttons["Cancel Timer"]
        if cancel.exists { cancel.tap() }
        XCTAssertTrue(waitUntil(switchLens, isEnabled: true, timeout: 30))
    }

    /// 7. A press on a disabled lens during the countdown changes nothing: the lens in use stays
    /// selected and the countdown's photo is taken.
    @MainActor
    func testPressingADisabledLensDuringTheCountdownChangesNothing() throws {
        let app = launch("slowSaving")
        startTenSecondTimer(app)
        let ultraWide = lensControl(app, "Ultra Wide")
        XCTAssertTrue(waitUntil(ultraWide, isEnabled: false))
        ultraWide.tap()
        app.buttons["Switch Camera"].tap()
        XCTAssertTrue(lensControl(app, Self.lensInUse).isSelected)
        XCTAssertFalse(ultraWide.isSelected)
        XCTAssertTrue(app.buttons["Cancel Timer"].exists, "the countdown goes on")
        let thumbnail = app.descendants(matching: .any)["Last Photo"]
        let saved = NSPredicate(format: "value CONTAINS %@", "Saved")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: saved, object: thumbnail)], timeout: 30), .completed,
            "the countdown's photo was saved")
        XCTAssertTrue(lensControl(app, Self.lensInUse).isSelected)
        assertLensControlsAreFree(app)
    }
}
