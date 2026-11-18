import XCTest

/// UI tests for Q, the quick menu (docs/design/BUILD-SPEC.md, 3.6): the panel of tiles, its
/// menus and foot, and the list at accessibility text sizes, with accessibility audits at the
/// default and largest text sizes, right to left, in night mode, with double-length text and in Spanish.
extension NopeAppUITests {
    /// The tiles' identifiers in display order (``QuickControls/builders``).
    static let quickTileOrder = [
        "flash", "light", "exposure", "closeUp", "farFocus", "fastShutter", "magnifier", "focusPeaking", "grid", "level",
        "liveReadout", "night", "compare", "presets",
    ]

    /// The launch arguments that turn manual controls on.
    static let quickManualOn = ["-NopeSettings.showsManualControls", "YES"]

    /// The launch arguments that turn night mode on.
    static let quickNightModeOn = ["-NopeSettings.isNightModeOn", "YES"]

    /// The launch arguments for Apple's double-length pseudo-language: every localized string is
    /// shown twice ("Grid Grid"), which stands in for a long language while the app ships in
    /// English only. Xcode's App Language option "Double-Length Pseudolanguage" sets the same.
    static let quickDoubleLength = ["-NSDoubleLocalizedStrings", "YES"]

    /// The Q button, by its identifier, or by its name where the layout doesn't set one.
    @MainActor
    func quickMenuButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'quickMenuButton' OR label == 'Quick Menu'")).firstMatch
    }

    /// Opens Q and returns the panel (or the list at accessibility sizes).
    @MainActor
    @discardableResult
    func openQuickMenu(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let button = quickMenuButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 20), file: file, line: line)
        button.tap()
        let panel = app.descendants(matching: .any)["quickMenu"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), file: file, line: line)
        settle()
        attachQuickScreenshot("Q open")
        return panel
    }

    /// A tile by its item's identifier.
    @MainActor
    func quickTile(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.buttons["quick.\(id)"]
    }

    /// The identifiers of the tiles shown, in reading order: row by row, and within a row from
    /// the leading edge.
    @MainActor
    func shownQuickTiles(_ app: XCUIApplication, rightToLeft: Bool = false) -> [String] {
        let shown = Self.quickTileOrder.filter { quickTile(app, $0).exists }
        return shown.sorted { first, second in
            let a = quickTile(app, first).frame, b = quickTile(app, second).frame
            if abs(a.minY - b.minY) > 1 { return a.minY < b.minY }
            return rightToLeft ? a.maxX > b.maxX : a.minX < b.minX
        }
    }

    /// Attaches a screenshot to the test, kept for review.
    @MainActor
    func attachQuickScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Runs only the contrast audit, failing on any finding.
    @MainActor
    func auditContrastOnly(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        var issues: [XCUIAccessibilityAuditIssue] = []
        try app.performCompleteAccessibilityAudit(for: .contrast) { issue in
            issues.append(issue)
            return true
        }
        for issue in issues where issue.element != nil {
            XCTFail("\(issue.compactDescription): \(issue.element?.debugDescription ?? "")", file: file, line: line)
        }
    }

    @MainActor
    func testQuickMenuTiles() throws {
        let app = launch("aids")
        let panel = openQuickMenu(app)
        XCTAssertTrue(quickMenuButton(app).isSelected)
        // The tiles keep the registry's order, in rows from the leading edge; nothing that moved
        // to the drive strip or the foot is a tile, and Far Focus waits for manual controls.
        let shown = shownQuickTiles(app)
        XCTAssertEqual(shown, Self.quickTileOrder.filter(shown.contains))
        XCTAssertTrue(shown.contains("focusPeaking"))
        XCTAssertFalse(shown.contains("farFocus"))
        XCTAssertFalse(app.buttons["quick.drive"].exists)
        XCTAssertFalse(app.buttons["quick.astro"].exists)
        // Three to a row at the default size, and every tile names its value.
        let first = quickTile(app, shown[0]).frame, third = quickTile(app, shown[2]).frame
        XCTAssertEqual(first.minY, third.minY, accuracy: 1)
        XCTAssertEqual(quickTile(app, "focusPeaking").value as? String, "Off")
        XCTAssertEqual(quickTile(app, "grid").value as? String, "Off")
        // The foot, under the tiles; the shutter row stays clear.
        let hide = app.buttons["quick.hideControls"], settings = app.buttons["quick.settings"]
        XCTAssertTrue(hide.exists && settings.exists)
        XCTAssertGreaterThan(hide.frame.minY, quickTile(app, shown.last!).frame.maxY)
        XCTAssertLessThanOrEqual(panel.frame.maxY, app.buttons["Take Photo"].frame.minY)
        attachQuickScreenshot("Q, full auto")
        try audit(app)
        // Q closes it again; so do the shutter and a tap on the picture above the panel.
        quickMenuButton(app).tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        openQuickMenu(app)
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        let reopened = openQuickMenu(app)
        // Halfway between the picture's top and the panel's.
        let viewfinder = app.otherElements["Viewfinder"].frame
        let y = (max(viewfinder.minY, app.buttons["Photo Format"].frame.maxY) + reopened.frame.minY) / 2
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: viewfinder.midX, dy: y)).tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testQuickMenuTogglesStayOpen() throws {
        let app = launch("aids")
        let panel = openQuickMenu(app)
        // A switch tile changes and the panel stays open.
        let level = quickTile(app, "level")
        level.tap()
        XCTAssertTrue(level.isSelected)
        XCTAssertEqual(level.value as? String, "On")
        XCTAssertTrue(panel.exists)
        let peaking = quickTile(app, "focusPeaking")
        peaking.tap()
        XCTAssertEqual(peaking.value as? String, "On")
        XCTAssertTrue(panel.exists)
        try audit(app)
        level.tap()
        peaking.tap()
        XCTAssertEqual(level.value as? String, "Off")
        // Hide Controls closes the panel and turns on clean view.
        app.buttons["quick.hideControls"].tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        let show = app.buttons["Show Controls"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()
        // Settings closes the panel and opens Settings.
        openQuickMenu(app)
        app.buttons["quick.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(panel.exists)
    }

    @MainActor
    func testQuickMenuMenuTile() throws {
        let app = launch("aids")
        let panel = openQuickMenu(app)
        // Grid is a menu of its styles; choosing one keeps the panel open and shows it.
        let grid = quickTile(app, "grid")
        grid.tap()
        let thirds = app.buttons["Thirds"]
        XCTAssertTrue(thirds.waitForExistence(timeout: 5))
        attachQuickScreenshot("Q, Grid menu")
        thirds.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertEqual(grid.value as? String, "Thirds")
        // Fast Shutter's value is the short form of the choice.
        let fastShutter = quickTile(app, "fastShutter")
        XCTAssertEqual(fastShutter.value as? String, "Standard")
        fastShutter.tap()
        let freeze = app.buttons["Freeze Motion (1/500 s)"]
        XCTAssertTrue(freeze.waitForExistence(timeout: 5))
        freeze.tap()
        XCTAssertEqual(fastShutter.value as? String, "1/500")
        attachQuickScreenshot("Q, tiles on")
        try audit(app)
        // Exposure is a button tile: it closes the panel and opens its dial.
        let exposure = quickTile(app, "exposure")
        XCTAssertTrue(exposure.exists)
        exposure.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reset Exposure"].exists || app.sliders.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testQuickMenuWithManualControls() throws {
        let app = launch("manual", extraArguments: Self.quickManualOn)
        openQuickMenu(app)
        let shown = shownQuickTiles(app)
        XCTAssertEqual(shown, Self.quickTileOrder.filter(shown.contains))
        // Exposure and Fast Shutter are full-auto controls; Focus Peaking stays.
        XCTAssertFalse(shown.contains("exposure"))
        XCTAssertFalse(shown.contains("fastShutter"))
        XCTAssertTrue(shown.contains("focusPeaking"))
        attachQuickScreenshot("Q, manual")
        try audit(app)
    }

    @MainActor
    func testQuickMenuLargestText() throws {
        let app = launch("aids", extraArguments: Self.largestTextSize)
        // The scrolling layout shows Q as a list with Done, ending with Hide Controls and
        // Settings, which is the only way to Settings there.
        let list = openQuickMenu(app)
        XCTAssertTrue(app.buttons["quick.done"].exists)
        XCTAssertTrue(quickTile(app, "exposure").waitForExistence(timeout: 5))
        attachQuickScreenshot("Q, largest text")
        try audit(app)
        let level = quickTile(app, "closeUp")
        level.tap()
        XCTAssertEqual(level.value as? String, "On")
        level.tap()
        app.buttons["quick.done"].tap()
        XCTAssertTrue(list.waitForNonExistence(timeout: 5))
        openQuickMenu(app)
        let settings = app.buttons["quick.settings"]
        var swipes = 0
        while !settings.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testQuickMenuRightToLeft() throws {
        let app = launch("aids", extraArguments: Self.rightToLeft)
        openQuickMenu(app)
        // Rows start at the trailing edge, which is on the right.
        let shown = shownQuickTiles(app, rightToLeft: true)
        XCTAssertEqual(shown, Self.quickTileOrder.filter(shown.contains))
        XCTAssertGreaterThan(quickTile(app, shown[0]).frame.minX, quickTile(app, shown[1]).frame.minX)
        attachQuickScreenshot("Q, right to left")
        try audit(app)
    }

    @MainActor
    func testQuickMenuNightMode() throws {
        let app = launch("aids", extraArguments: Self.quickNightModeOn)
        let panel = openQuickMenu(app)
        let night = quickTile(app, "night")
        XCTAssertTrue(night.isSelected)
        attachQuickScreenshot("Q, night mode")
        try audit(app)
        // Turning night mode off from its tile leaves the panel open.
        night.tap()
        XCTAssertFalse(night.isSelected)
        XCTAssertTrue(panel.exists)
        try audit(app)
    }

    @MainActor
    func testQuickMenuLongLanguage() throws {
        // The app ships in English only, so long text is tested with Apple's double-length
        // pseudo-language (every string twice, as Xcode's App Language option sets it), at the
        // largest size below the accessibility sizes, where the tiles are at their widest:
        // names and values wrap between words, nothing is cut, and the column count drops
        // rather than breaking a word. The second run adds right-to-left layout.
        let extraLarge = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        for (name, rightToLeft) in [("double length", false), ("double length, right to left", true)] {
            let direction = rightToLeft ? Self.rightToLeft : []
            let app = launch("aids", extraArguments: Self.quickDoubleLength + direction + extraLarge)
            openQuickMenu(app)
            let shown = shownQuickTiles(app, rightToLeft: rightToLeft)
            XCTAssertEqual(shown, Self.quickTileOrder.filter(shown.contains), name)
            // The pseudo-language is on: the tile's name is the English name twice.
            XCTAssertEqual(quickTile(app, "grid").label, "Grid Grid", name)
            attachQuickScreenshot("Q, \(name), extra large text")
            try audit(app)
        }
    }

    @MainActor
    func testQuickMenuInSpanish() throws {
        // Spanish and Latin American Spanish (a device set to Mexico uses es-419) at the largest
        // size below the accessibility sizes, where the tiles are at their widest: names and
        // values wrap between words and nothing is cut. A name that is the same in both shows
        // that es-419 holds every string, not only its regional wording.
        for language in ["es", "es-MX"] {
            let app = launch(
                "aids",
                extraArguments: [
                    "-AppleLanguages", "(\(language))", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL",
                ])
            openQuickMenu(app)
            let shown = shownQuickTiles(app)
            XCTAssertEqual(shown, Self.quickTileOrder.filter(shown.contains), language)
            XCTAssertEqual(quickTile(app, "grid").label, "Cuadrícula", language)
            // The Settings button carries the regional name of Settings.
            XCTAssertEqual(app.buttons["quick.settings"].label, language == "es" ? "Ajustes" : "Configuración", language)
            attachQuickScreenshot("Q, \(language), extra large text")
            try audit(app)
        }
    }
}
