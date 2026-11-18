import XCTest

/// UI tests for controls shown only where they work (issues #91 and #92,
/// docs/design/SETTING-SCOPE.md, 6): Close-Up and Far Focus leave Q and the status line while
/// focus is set by hand, and Flash while Burst is selected, and each comes back with the
/// person's choice. Audited at the default and largest text sizes, right to left and in night
/// mode.
extension NopeAppUITests {
    /// The launch arguments that turn manual controls on.
    static let scopeManualOn = ["-NopeSettings.showsManualControls", "YES"]

    /// The launch arguments that store the flash as On.
    static let scopeFlashOn = ["-NopeSettings.flashMode", "on"]

    /// The variants every scope test runs in: the default, night mode, and right to left.
    static let scopeVariants: [(name: String, arguments: [String])] = [
        ("default", []),
        ("night mode", ["-NopeSettings.isNightModeOn", "YES"]),
        ("right to left", rightToLeft),
    ]

    /// A pill on the status line by its name, never a tile of Q (whose tiles have the
    /// `quick.` identifiers).
    @MainActor
    func scopePill(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'quick.')", label)).firstMatch
    }

    /// Waits until an element is gone.
    @MainActor
    func scopeWaitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// Opens Q, runs `body`, and closes Q again with its own button (or Done in the list).
    @MainActor
    func inQuickMenu(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void)
        rethrows
    {
        let panel = openQuickMenu(app, file: file, line: line)
        try body()
        let done = app.buttons["quick.done"]
        if done.exists { done.tap() } else { quickMenuButton(app).tap() }
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), file: file, line: line)
    }

    /// The drive strip's word of that name: the lowest button with the label.
    @MainActor
    func scopeDriveWord(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", name))
        let lowest = matches.allElementsBoundByIndex.enumerated().max { $0.element.frame.minY < $1.element.frame.minY }
        return matches.element(boundBy: lowest?.offset ?? 0)
    }

    // MARK: - #91

    /// Close-Up, turned on, leaves Q and the status line while focus is set by hand in Manual
    /// Controls, with Far Focus; with focus back on Auto both return, Close-Up still On.
    @MainActor
    func testCloseUpAndFarFocusLeaveWhileFocusIsSetByHand() throws {
        for variant in Self.scopeVariants {
            let app = launch("aids", extraArguments: Self.scopeManualOn + variant.arguments)
            XCTAssertTrue(app.buttons["Focus"].firstMatch.waitForExistence(timeout: 20), variant.name)
            inQuickMenu(app) {
                let closeUp = quickTile(app, "closeUp")
                XCTAssertTrue(closeUp.waitForExistence(timeout: 5), variant.name)
                closeUp.tap()
                XCTAssertEqual(closeUp.value as? String, "On", variant.name)
                XCTAssertTrue(quickTile(app, "farFocus").exists, variant.name)
            }
            XCTAssertTrue(scopePill(app, "Close-Up").waitForExistence(timeout: 5), variant.name)

            // Focus by hand: one step on the Focus dial.
            let focus = app.buttons["Focus"].firstMatch
            focus.tap()
            XCTAssertTrue(app.buttons["Increase"].waitForExistence(timeout: 5), variant.name)
            app.buttons["Increase"].tap()
            XCTAssertTrue((focus.value as? String)?.hasPrefix("Manual") ?? false, variant.name)
            focus.tap()
            XCTAssertTrue(scopeWaitUntilGone(app.buttons["Increase"]), variant.name)
            XCTAssertTrue(scopeWaitUntilGone(scopePill(app, "Close-Up")), "\(variant.name): the pill claims Close-Up")
            attachQuickScreenshot("Focus by hand, \(variant.name)")
            try audit(app)
            try inQuickMenu(app) {
                XCTAssertFalse(quickTile(app, "closeUp").exists, "\(variant.name): Q claims Close-Up")
                XCTAssertFalse(quickTile(app, "farFocus").exists, "\(variant.name): Q offers Far Focus")
                XCTAssertTrue(quickTile(app, "magnifier").exists, variant.name)
                attachQuickScreenshot("Q, focus by hand, \(variant.name)")
                try audit(app)
            }

            // Focus on Auto again: the choice is back, unchanged.
            focus.tap()
            let auto = app.buttons["Auto"].firstMatch
            XCTAssertTrue(auto.waitForExistence(timeout: 5), variant.name)
            auto.tap()
            XCTAssertTrue((focus.value as? String)?.hasPrefix("Auto") ?? false, variant.name)
            focus.tap()
            XCTAssertTrue(scopePill(app, "Close-Up").waitForExistence(timeout: 5), variant.name)
            inQuickMenu(app) {
                XCTAssertEqual(quickTile(app, "closeUp").value as? String, "On", variant.name)
            }
            app.terminate()
        }
    }

    /// At the largest text size the manual controls are a list of steppers: a step on Focus
    /// takes Close-Up out of Q's list and off the status line.
    @MainActor
    func testCloseUpLeavesWhileFocusIsSetByHandAtTheLargestTextSize() throws {
        let app = launch("aids", extraArguments: Self.scopeManualOn + Self.largestTextSize)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 20))
        inQuickMenu(app) {
            let closeUp = quickTile(app, "closeUp")
            XCTAssertTrue(closeUp.waitForExistence(timeout: 5))
            closeUp.tap()
            XCTAssertEqual(closeUp.value as? String, "On")
        }
        XCTAssertTrue(scopePill(app, "Close-Up").waitForExistence(timeout: 5))

        XCTAssertTrue(app.steppers.firstMatch.waitForExistence(timeout: 20), "no manual controls list")
        let stepper = app.steppers.matching(NSPredicate(format: "label CONTAINS %@", "Focus")).firstMatch
        let increment = stepper.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Increment")).firstMatch
        let scrollView = app.scrollViews.firstMatch
        var drags = 0
        // Drag the row into view, holding at the end so the scroll view doesn't coast past it.
        while !(increment.exists && increment.isHittable) && drags < 12 {
            let visible = scrollView.frame.insetBy(dx: 0, dy: 60)
            let distance = max(-250, min(250, visible.midY - stepper.frame.midY))
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            start.press(
                forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)), withVelocity: .slow,
                thenHoldForDuration: 0.3)
            drags += 1
        }
        XCTAssertTrue(increment.isHittable, "Focus can't be set")
        increment.tap()
        XCTAssertTrue(scopeWaitUntilGone(scopePill(app, "Close-Up")), "the pill claims Close-Up")
        try auditScrollingScreen(app)
        try inQuickMenu(app) {
            XCTAssertFalse(quickTile(app, "closeUp").exists, "Q claims Close-Up")
            XCTAssertTrue(quickTile(app, "magnifier").waitForExistence(timeout: 5))
            attachQuickScreenshot("Q list, focus by hand, largest text")
            try audit(app)
        }
    }

    // MARK: - #92

    /// With the flash On, the Flash pill and Q's Flash tile leave while Burst is selected, and
    /// come back On in Single.
    @MainActor
    func testFlashLeavesInBurst() throws {
        for variant in Self.scopeVariants {
            let app = launch("burst", extraArguments: Self.scopeFlashOn + variant.arguments)
            let pill = scopePill(app, "Flash On")
            XCTAssertTrue(pill.waitForExistence(timeout: 20), variant.name)
            inQuickMenu(app) {
                XCTAssertEqual(quickTile(app, "flash").value as? String, "On", variant.name)
            }

            let burst = scopeDriveWord(app, "Burst")
            burst.tap()
            let selected = app.buttons.matching(NSPredicate(format: "label == %@ AND selected == YES", "Burst")).firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout: 5), variant.name)
            XCTAssertTrue(scopeWaitUntilGone(pill), "\(variant.name): the pill claims the flash in Burst")
            attachQuickScreenshot("Burst, flash stored On, \(variant.name)")
            try audit(app)
            try inQuickMenu(app) {
                XCTAssertFalse(quickTile(app, "flash").exists, "\(variant.name): Q offers the flash in Burst")
                XCTAssertTrue(quickTile(app, "light").exists, variant.name)
                attachQuickScreenshot("Q in Burst, \(variant.name)")
                try audit(app)
            }

            scopeDriveWord(app, "Single").tap()
            XCTAssertTrue(pill.waitForExistence(timeout: 5), variant.name)
            inQuickMenu(app) {
                XCTAssertEqual(quickTile(app, "flash").value as? String, "On", variant.name)
            }
            app.terminate()
        }
    }

    /// The same at the largest text size, where the drive modes are rows of the scrolling
    /// screen and Q is a list.
    @MainActor
    func testFlashLeavesInBurstAtTheLargestTextSize() throws {
        let app = launch("burst", extraArguments: Self.scopeFlashOn + Self.largestTextSize)
        let pill = scopePill(app, "Flash On")
        XCTAssertTrue(pill.waitForExistence(timeout: 20))
        let burst = scopeDriveWord(app, "Burst")
        XCTAssertTrue(burst.waitForExistence(timeout: 5))
        var swipes = 0
        while !burst.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        burst.tap()
        XCTAssertTrue(scopeWaitUntilGone(pill), "the pill claims the flash in Burst")
        try auditScrollingScreen(app)
        try inQuickMenu(app) {
            XCTAssertTrue(quickTile(app, "light").waitForExistence(timeout: 5))
            XCTAssertFalse(quickTile(app, "flash").exists, "Q offers the flash in Burst")
            attachQuickScreenshot("Q list in Burst, largest text")
            try audit(app)
        }
    }
}
