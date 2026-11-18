import XCTest

/// UI tests for the level's tap (docs/design/level-haptic.md, section 10). A haptic can't be
/// observed in a UI test, so these cover what can be: the path from tilted to level runs, with a
/// sheet over the camera and during a burst, the words are right, and the audits pass.
///
/// `-NopeSimulatedGravity becomesLevel` (and `becomesFlatLevel`) sends a tilted reading, then a
/// level one a few seconds later (`SimulatedGravity`).
extension NopeAppUITests {
    /// The level switched on.
    static let levelOn = ["-NopeSettings.overlays.showsLevel", "YES"]

    /// How long the simulated sequence stays tilted, in seconds, as
    /// `SimulatedGravity.levelAfterSeconds` in the app.
    static let levelAfterSeconds: TimeInterval = 8

    /// The new sentence of the Level switch's explanation.
    static let levelTapSentence = "On iPhone, you feel a tap when it's level."

    /// The new sentence of the Accessibility page's Feedback row.
    static let feedbackTapSentence = "and marks the moment the level is level."

    /// Launches the camera with the level on and a simulated reading sequence, in a simulated
    /// camera scenario.
    @MainActor
    func launchLevel(_ sequence: String, scenario: String = "manual", extraArguments: [String] = []) -> XCUIApplication {
        let app = launch(scenario, extraArguments: ["-NopeSimulatedGravity", sequence] + Self.levelOn + extraArguments)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 20))
        return app
    }

    /// Waits until the level reads a value.
    @MainActor
    func levelReads(_ app: XCUIApplication, _ value: String, timeout: TimeInterval = 20) -> Bool {
        app.otherElements.matching(NSPredicate(format: "label == 'Level' AND value == %@", value)).firstMatch
            .waitForExistence(timeout: timeout)
    }

    /// Waits for a number of seconds without touching the app.
    @MainActor
    func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Time passes")], timeout: seconds)
    }

    /// Scrolls the open Settings page until the element is in view, as ``settingsElement(_:_:)``
    /// does, with more steps for the largest text size, where the Settings list is far longer
    /// than the screen; returns the element. In view means partly: at the largest size a long
    /// row can be taller than the iPad popover.
    @MainActor @discardableResult
    func scrollIntoView(_ app: XCUIApplication, _ element: XCUIElement) -> XCUIElement {
        let frame = settingsListFrame(app)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func point(_ fraction: CGFloat) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * fraction))
        }
        for towardEnd in [true, false] {
            var steps = 0
            while !(element.exists && frame.intersects(element.frame)) && steps < 40 {
                point(towardEnd ? 0.7 : 0.4).press(forDuration: 0.05, thenDragTo: point(towardEnd ? 0.4 : 0.7))
                steps += 1
            }
        }
        return element
    }

    /// Opens a Settings row by its identifier, scrolling to it.
    @MainActor
    func openLevelSettingsRow(_ app: XCUIApplication, _ identifier: String) {
        scrollIntoView(app, app.descendants(matching: .any).matching(identifier: identifier).firstMatch).tap()
    }

    /// The four audited variants of a Settings page: the default size, the largest accessibility
    /// size, right to left and night mode, with whether the Dynamic Type check applies.
    static var settingsVariants: [(name: String, arguments: [String], checksDynamicType: Bool)] {
        [
            ("default", [], false), ("largest text size", largestTextSize, true), ("right to left", rightToLeft, false),
            ("night mode", nightModeOn, false),
        ]
    }

    // 1.
    @MainActor
    func testLevelBecomesLevel() throws {
        let app = launchLevel("becomesLevel")
        XCTAssertTrue(levelReads(app, "Tilted 5° clockwise"))
        try audit(app)
        XCTAssertTrue(levelReads(app, "Level"))
        try audit(app)
    }

    // 2.
    @MainActor
    func testFlatLevelBecomesLevel() throws {
        let app = launchLevel("becomesFlatLevel")
        XCTAssertTrue(levelReads(app, "Pointing down, not level"))
        try audit(app)
        XCTAssertTrue(levelReads(app, "Pointing straight down, level"))
        try audit(app)
    }

    // 3.
    @MainActor
    func testLevelBecomesLevelUnderASheetAndDuringABurst() throws {
        // Settings is open while the level becomes level; the value is right once it closes.
        let app = launchLevel("becomesLevel")
        XCTAssertTrue(levelReads(app, "Tilted 5° clockwise"))
        openSettingsScreen(app)
        pause(Self.levelAfterSeconds + 2)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(levelReads(app, "Level", timeout: 10))
        app.terminate()

        // A burst runs while the level becomes level; slow saving keeps it running, as in
        // testBurstRunsUntilStoppedAndSavesEachFrame.
        let burst = launchLevel("becomesLevel", scenario: "slowSaving")
        XCTAssertTrue(levelReads(burst, "Tilted 5° clockwise"))
        chooseDrive(burst, "Burst")
        burst.buttons["Take Photo"].tap()
        let stop = burst.buttons["Stop Burst"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(levelReads(burst, "Level"))
        if stop.exists { stop.tap() }
        XCTAssertFalse(stop.waitForExistence(timeout: 10))
        XCTAssertTrue(levelReads(burst, "Level", timeout: 5))
    }

    // 4.
    @MainActor
    func testLevelExplanationSaysItTaps() throws {
        for variant in Self.settingsVariants {
            let app = launch("denied", extraArguments: variant.arguments)
            openSettingsScreen(app)
            openLevelSettingsRow(app, "settings.overlays")
            XCTAssertTrue(app.navigationBars["Viewfinder Overlays"].waitForExistence(timeout: 5), variant.name)
            let explanation = scrollIntoView(app, element(app, containing: Self.levelTapSentence))
            XCTAssertTrue(explanation.exists, "\(variant.name): the Level explanation says it taps")
            // iPad: Settings is a popover, whose headers the audit reports as low contrast
            // against its material, an open finding (docs/TESTING.md); contrast is checked on
            // iPhone.
            try audit(app, afterScrolling: variant.checksDynamicType, checksDynamicType: variant.checksDynamicType, checksContrast: !isPad)
            app.terminate()
        }
    }

    // 5.
    @MainActor
    func testAccessibilityFeedbackMentionsTheLevel() throws {
        for variant in Self.settingsVariants {
            let app = launch("denied", extraArguments: variant.arguments)
            openSettingsScreen(app)
            openLevelSettingsRow(app, "settings.accessibility")
            XCTAssertTrue(app.navigationBars["Accessibility"].waitForExistence(timeout: 5), variant.name)
            let feedback = scrollIntoView(app, element(app, containing: Self.feedbackTapSentence))
            XCTAssertTrue(feedback.exists, "\(variant.name): the Feedback row mentions the level")
            try audit(app, afterScrolling: true, checksDynamicType: variant.checksDynamicType, checksContrast: !isPad)
            app.terminate()
        }
    }

    // 6.
    @MainActor
    func testSettingsSearchFindsLevelByTap() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        let level = app.descendants(matching: .any).matching(identifier: "settings.search.camera.level").firstMatch
        for (index, word) in ["haptic", "tap"].enumerated() {
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            if index > 0 {
                field.buttons.firstMatch.tap()
                // As in testSettingsSearchFindsEveryRootRowByName: clearing ends the search on
                // iPad.
                field.tap()
            }
            field.typeText(word + "\n")
            XCTAssertTrue(level.waitForExistence(timeout: 5), "search for \"\(word)\" finds Level")
            XCTAssertTrue(level.label.contains("Level"), level.label)
        }
    }
}
