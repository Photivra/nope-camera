import XCTest

/// UI tests for the viewfinder overlays (issues #40, #47, #51 and #52) against the simulated
/// backend: the grid and level from Q, the quick menu, the histogram and live readout with
/// the manual controls, their switches in Settings and Pro Tools, and accessibility audits of
/// each state at the default and largest text sizes and right-to-left.
final class OverlayUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// The launch arguments for the largest accessibility text size.
    private static let largestTextSize = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    /// The launch arguments for right-to-left layout.
    private static let rightToLeft = ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]

    /// Manual controls on, and every live aid on.
    private static let liveAidsOn = [
        "-NopeSettings.showsManualControls", "YES", "-NopeSettings.overlays.showsHistogram", "YES",
        "-NopeSettings.overlays.showsLiveReadout", "YES", "-NopeSettings.overlays.showsFocusPeaking", "YES",
    ]

    /// Launches the app with a simulated camera scenario and a tilted simulated level.
    @MainActor
    private func launch(_ scenario: String = "manual", _ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NopeSimulatedCamera", scenario, "-NopeSimulatedGravity", "tilted"] + arguments
        app.launchAfterThePreviousRunExits()
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 20))
        return app
    }

    /// Runs the accessibility audit. A finding on an element that isn't wholly in the window (a
    /// row below the fold, measured at its clipped edge) is skipped, as in `NopeAppUITests`.
    @MainActor
    private func audit(
        _ app: XCUIApplication, checksDynamicType: Bool = true, checksContrast: Bool = true, visibleBottom: CGFloat? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Animations finish")], timeout: 2)
        // The text below the fold before the audit: the audit scrolls such text into view itself
        // and measures it while the scroll view moves (on iPad at the largest size it reported a
        // manual control row, 1,324 points down, as low contrast at the place it scrolled it
        // to), and afterwards its frame reads as inside the window.
        let windowBeforeAudit = app.windows.firstMatch.frame
        let belowTheFold = Set(
            app.staticTexts.allElementsBoundByIndex.filter { !windowBeforeAudit.contains($0.frame) }.map(\.label))
        var issues: [XCUIAccessibilityAuditIssue] = []
        try app.performCompleteAccessibilityAudit { issue in
            issues.append(issue)
            return true
        }
        let window = app.windows.firstMatch.frame
        // A form row scrolled under the navigation bar is measured against the bar.
        let navigationBar = app.navigationBars.firstMatch
        let barBottom = navigationBar.exists ? navigationBar.frame.maxY : 0
        for issue in issues {
            if !checksDynamicType && issue.auditType == .dynamicType { continue }
            if !checksContrast && issue.auditType == .contrast { continue }
            // A finding the audit can't attach to any element can't be placed on screen; after a
            // scroll at the largest text size the audit reports such Dynamic Type findings for
            // rows it pushed past the edge. Findings on real elements still fail.
            if issue.element == nil && [.contrast, .textClipped, .dynamicType].contains(issue.auditType) { continue }
            if let element = issue.element, element.exists, !window.contains(element.frame) { continue }
            if let element = issue.element, element.exists, belowTheFold.contains(element.label) { continue }
            if issue.auditType == .contrast, let element = issue.element, element.exists, element.frame.minY < barBottom { continue }
            // In the scrolling layout the shutter row is pinned over the bottom of the scroll
            // view; an element partly under it is measured against the shutter row.
            if let visibleBottom, let element = issue.element, element.exists, element.frame.maxY > visibleBottom { continue }
            XCTFail("\(issue.compactDescription): \(issue.element?.debugDescription ?? "no element")", file: file, line: line)
        }
    }

    /// Q, the quick menu that replaced the quick-controls tray (docs/design/BUILD-SPEC.md, 3.6).
    @MainActor
    private func quickMenuButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'quickMenuButton' OR label == 'Quick Menu'")).firstMatch
    }

    /// Opens Q.
    @MainActor
    private func openTray(_ app: XCUIApplication) {
        let quick = quickMenuButton(app)
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        quick.tap()
    }

    /// Opens Settings: from its button in the iPad's column, otherwise from Q.
    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["Settings"]
        if !settings.exists {
            openTray(app)
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
        }
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testGridAndLevelFromTheQuickControls() throws {
        let app = launch()
        XCTAssertFalse(app.otherElements["Level"].exists)
        openTray(app)
        let level = app.buttons["Level"]
        XCTAssertTrue(level.waitForExistence(timeout: 5))
        XCTAssertFalse(level.isSelected)
        level.tap()
        XCTAssertTrue(level.isSelected)
        let levelOverlay = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Level' AND value CONTAINS 'clockwise'")).firstMatch
        XCTAssertTrue(levelOverlay.waitForExistence(timeout: 5))
        XCTAssertEqual(levelOverlay.value as? String, "Tilted 5° clockwise")

        let grid = app.buttons["Grid"]
        grid.tap()
        // The golden grids were removed (issue #76); 4 × 4 is a menu choice like them.
        let fourByFour = app.buttons["4 × 4"]
        XCTAssertTrue(fourByFour.waitForExistence(timeout: 5))
        fourByFour.tap()
        // Q stays open after a menu choice; Q itself is audited with every tile in
        // QuickMenuUITests.
        let hide = app.buttons["Hide Controls"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        XCTAssertEqual(grid.value as? String, "4 × 4")
        for _ in 0..<3 where hide.exists {
            quickMenuButton(app).tap()
            _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Q closes")], timeout: 1)
        }
        XCTAssertFalse(hide.exists)
        try audit(app)
        app.terminate()

        // Both stay on for the next launch and show in clean view; the tray shows them as on.
        let again = launch("manual", ["-NopeSimulatedViewfinder", "white", "-NopeSettings.overlays.showsGrid", "YES", "-NopeSettings.overlays.showsLevel", "YES"])
        XCTAssertTrue(again.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS 'clockwise'")).firstMatch.waitForExistence(timeout: 5))
        try audit(again)
    }

    @MainActor
    func testGridOnlyAndLevelOnly() throws {
        let grid = launch("manual", ["-NopeSettings.overlays.showsGrid", "YES"])
        try audit(grid)
        grid.terminate()
        let level = launch("manual", ["-NopeSettings.overlays.showsLevel", "YES"])
        XCTAssertTrue(level.otherElements["Level"].waitForExistence(timeout: 5))
        try audit(level)
    }

    @MainActor
    func testFlatLevelSaysItPointsDown() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-NopeSimulatedCamera", "manual", "-NopeSimulatedGravity", "flat", "-NopeSettings.overlays.showsLevel", "YES"]
        app.launchAfterThePreviousRunExits()
        let level = app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS 'Pointing straight down'")).firstMatch
        XCTAssertTrue(level.waitForExistence(timeout: 20))
    }

    @MainActor
    func testHistogramAndReadoutShowWithTheManualControls() throws {
        let app = launch("manual", Self.liveAidsOn)
        let histogram = app.otherElements["Histogram"]
        XCTAssertTrue(histogram.waitForExistence(timeout: 10))
        XCTAssertEqual(histogram.value as? String, "Highlights and shadows clipped")
        XCTAssertTrue(app.otherElements["Live Camera Readout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1/120 · ISO 100 · f/1.8 · Auto"].exists)
        try audit(app)

        // Clean view hides both; the guides and peaking would stay.
        openTray(app)
        app.buttons["Hide Controls"].tap()
        XCTAssertFalse(histogram.waitForExistence(timeout: 2))
        XCTAssertFalse(app.otherElements["Live Camera Readout"].exists)
    }

    /// The readout pinned from Q stays in clean view (issue #52).
    @MainActor
    func testPinnedReadoutStaysInCleanView() throws {
        let app = launch("manual", ["-NopeSettings.overlays.showsLiveReadout", "YES"])
        let readout = app.otherElements["Live Camera Readout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 10))
        openTray(app)
        let menu = app.buttons["Readout"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let pin = app.buttons["Keep Readout in Clean View"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        let hide = app.buttons["Hide Controls"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        hide.tap()
        XCTAssertTrue(app.buttons["Show Controls"].waitForExistence(timeout: 5))
        XCTAssertTrue(readout.exists)
        try audit(app)
        app.terminate()

        // Starting in clean view: the readout shows only when pinned. (UI test launches start
        // from empty settings, so each launch sets the switches it needs.)
        let unpinned = launch("manual", ["-NopeSettings.overlays.showsLiveReadout", "YES", "-NopeSettings.startsInCleanView", "YES"])
        XCTAssertTrue(unpinned.buttons["Show Controls"].waitForExistence(timeout: 10))
        XCTAssertFalse(unpinned.otherElements["Live Camera Readout"].waitForExistence(timeout: 3))
        unpinned.terminate()
        let pinned = launch("manual", [
            "-NopeSettings.overlays.showsLiveReadout", "YES", "-NopeSettings.overlays.pinsLiveReadout", "YES",
            "-NopeSettings.startsInCleanView", "YES",
        ])
        XCTAssertTrue(pinned.otherElements["Live Camera Readout"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testHistogramIsNeverShownInFullAuto() throws {
        let app = launch("manual", ["-NopeSettings.overlays.showsHistogram", "YES", "-NopeSettings.overlays.showsLiveReadout", "YES"])
        XCTAssertTrue(app.otherElements["Live Camera Readout"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["Histogram"].exists)
    }

    @MainActor
    func testLiveAidsAtTheLargestTextSizeAndRightToLeft() throws {
        let large = launch("manual", Self.liveAidsOn + Self.largestTextSize)
        XCTAssertTrue(large.otherElements["Histogram"].waitForExistence(timeout: 10))
        XCTAssertTrue(large.otherElements["Live Camera Readout"].exists)
        try audit(large, visibleBottom: large.scrollViews.firstMatch.frame.maxY)
        large.terminate()

        let mirrored = launch("manual", Self.liveAidsOn + Self.rightToLeft)
        XCTAssertTrue(mirrored.otherElements["Histogram"].waitForExistence(timeout: 10))
        try audit(mirrored)
    }

    @MainActor
    func testOverlaySettingsAndProTools() throws {
        let app = launch("manual", ["-NopeSettings.showsManualControls", "YES", "-NopeSettings.overlays.showsLiveReadout", "YES"])
        openSettings(app)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Viewfinder Overlays'")).firstMatch
        var swipes = 0
        while !row.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        row.tap()
        XCTAssertTrue(app.navigationBars["Viewfinder Overlays"].waitForExistence(timeout: 5))
        // Dynamic Type is audited at the largest size (testOverlaySettingsAtTheLargestTextSize):
        // at the default size the iOS 27.2 Simulator reports form rows as "partially
        // unsupported", as for the other settings screens (NopeAppUITests). iPad: Settings is a
        // popover, whose rows the audit reports as low contrast against its material, an open
        // finding (docs/TESTING.md); contrast is checked on iPhone.
        try audit(app, checksDynamicType: false, checksContrast: UIDevice.current.userInterfaceIdiom != .pad)

        // A switch row toggles from its switch, at the trailing end.
        let gridSwitch = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Grid'")).firstMatch
        gridSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(gridSwitch.value as? String, "1")

        // A grid style; the golden grids and Turn Spiral were removed (issue #76).
        let fourByFour = app.buttons["4 × 4"].firstMatch
        var styleSwipes = 0
        while !(fourByFour.exists && fourByFour.isHittable) && styleSwipes < 6 {
            app.swipeUp()
            styleSwipes += 1
        }
        fourByFour.tap()
        XCTAssertTrue(fourByFour.isSelected)
        XCTAssertFalse(app.buttons["Golden Spiral"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Turn Spiral'")).firstMatch.exists)
        try audit(app, checksDynamicType: false, checksContrast: UIDevice.current.userInterfaceIdiom != .pad)

        // Pro Tools has the live aid switches too.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].firstMatch.tap()
        app.buttons["More Manual Controls"].tap()
        app.buttons["Pro Tools"].tap()
        // The form loads rows as they scroll in; the live aids are its last section but Done.
        for name in ["Focus Peaking", "Histogram", "Live Camera Readout", "Keep Readout in Clean View"] {
            let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            var proSwipes = 0
            while !(toggle.exists && toggle.isHittable) && proSwipes < 8 {
                app.swipeUp()
                proSwipes += 1
            }
            XCTAssertTrue(toggle.exists, name)
        }
    }

    @MainActor
    func testOverlaySettingsAtTheLargestTextSize() throws {
        // The readout on, so its Keep Readout in Clean View switch is audited too.
        let app = launch("manual", Self.largestTextSize + [
            "-NopeSettings.overlays.showsGrid", "YES", "-NopeSettings.overlays.gridStyle", "fourByFour",
            "-NopeSettings.overlays.showsLiveReadout", "YES",
        ])
        openSettings(app)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Viewfinder Overlays'")).firstMatch
        var swipes = 0
        while !row.isHittable && swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        row.tap()
        XCTAssertTrue(app.navigationBars["Viewfinder Overlays"].waitForExistence(timeout: 5))
        // iPad: Settings is a popover, whose section headers the audit reports as low contrast
        // against its material, an open finding (docs/TESTING.md); contrast is checked on iPhone.
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        try audit(app, checksContrast: !isPad)
        app.swipeUp()
        app.swipeUp()
        try audit(app, checksContrast: !isPad)
    }
}
