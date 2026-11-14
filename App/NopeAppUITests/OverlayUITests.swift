import XCTest

/// UI tests for the viewfinder overlays (issues #40, #47, #51 and #52) against the simulated
/// backend: the grid and level from the quick-controls tray, the histogram and live readout with
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
        app.launch()
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 20))
        return app
    }

    /// Runs the accessibility audit. A finding on an element that isn't wholly in the window (a
    /// row below the fold, measured at its clipped edge) is skipped, as in `NopeAppUITests`.
    @MainActor
    private func audit(
        _ app: XCUIApplication, checksDynamicType: Bool = true, visibleBottom: CGFloat? = nil, file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Animations finish")], timeout: 2)
        var issues: [XCUIAccessibilityAuditIssue] = []
        try app.performAccessibilityAudit { issue in
            issues.append(issue)
            return true
        }
        let window = app.windows.firstMatch.frame
        // A form row scrolled under the navigation bar is measured against the bar.
        let navigationBar = app.navigationBars.firstMatch
        let barBottom = navigationBar.exists ? navigationBar.frame.maxY : 0
        for issue in issues {
            if !checksDynamicType && issue.auditType == .dynamicType { continue }
            if issue.element == nil && (issue.auditType == .contrast || issue.auditType == .textClipped) { continue }
            if let element = issue.element, element.exists, !window.contains(element.frame) { continue }
            if issue.auditType == .contrast, let element = issue.element, element.exists, element.frame.minY < barBottom { continue }
            // In the scrolling layout the shutter row is pinned over the bottom of the scroll
            // view; an element partly under it is measured against the shutter row.
            if let visibleBottom, let element = issue.element, element.exists, element.frame.maxY > visibleBottom { continue }
            XCTFail("\(issue.compactDescription): \(issue.element?.debugDescription ?? "no element")", file: file, line: line)
        }
    }

    /// Opens the quick-controls tray.
    @MainActor
    private func openTray(_ app: XCUIApplication) {
        let tray = app.buttons["Quick Controls"]
        XCTAssertTrue(tray.waitForExistence(timeout: 10))
        tray.tap()
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
        let spiral = app.buttons["Golden Spiral"]
        XCTAssertTrue(spiral.waitForExistence(timeout: 5))
        spiral.tap()
        // The tray stays open after a menu choice; the tray itself is audited with every item
        // in NopeAppUITests.testQuickControlsTrayOpensAndCloses.
        let hide = app.buttons["Hide Controls"]
        for _ in 0..<3 where hide.exists {
            app.buttons["Quick Controls"].tap()
            _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Tray closes")], timeout: 1)
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
        app.launch()
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
        app.buttons["Quick Controls"].tap()
        app.buttons["Hide Controls"].tap()
        XCTAssertFalse(histogram.waitForExistence(timeout: 2))
        XCTAssertFalse(app.otherElements["Live Camera Readout"].exists)
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
        let app = launch("manual", ["-NopeSettings.showsManualControls", "YES"])
        app.buttons["Settings"].tap()
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
        // unsupported", as for the other settings screens (NopeAppUITests).
        try audit(app, checksDynamicType: false)

        // A switch row toggles from its switch, at the trailing end.
        let gridSwitch = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Grid'")).firstMatch
        gridSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(gridSwitch.value as? String, "1")

        let spiral = app.buttons["Golden Spiral"].firstMatch
        var styleSwipes = 0
        while !(spiral.exists && spiral.isHittable) && styleSwipes < 6 {
            app.swipeUp()
            styleSwipes += 1
        }
        spiral.tap()
        let turn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Turn Spiral'")).firstMatch
        XCTAssertTrue(turn.waitForExistence(timeout: 5))
        XCTAssertTrue(turn.label.contains("1 of 8"))
        turn.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '2 of 8'")).firstMatch.waitForExistence(timeout: 5))
        try audit(app, checksDynamicType: false)

        // Pro Tools has the live aid switches too.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].firstMatch.tap()
        app.buttons["More Manual Controls"].tap()
        app.buttons["Pro Tools"].tap()
        // The form loads rows as they scroll in; the live aids are its last section but Done.
        for name in ["Focus Peaking", "Histogram", "Live Camera Readout"] {
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
        let app = launch("manual", Self.largestTextSize + ["-NopeSettings.overlays.showsGrid", "YES", "-NopeSettings.overlays.gridStyle", "goldenSpiral"])
        app.buttons["Settings"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Viewfinder Overlays'")).firstMatch
        var swipes = 0
        while !row.isHittable && swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        row.tap()
        XCTAssertTrue(app.navigationBars["Viewfinder Overlays"].waitForExistence(timeout: 5))
        try audit(app)
        app.swipeUp()
        app.swipeUp()
        try audit(app)
    }
}
