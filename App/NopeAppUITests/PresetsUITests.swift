import XCTest

/// UI tests for settings presets (issue #72): saving, applying, Factory Defaults, undo, renaming
/// and deleting, from Settings and from Q, the quick menu, with accessibility audits at the
/// default and largest text sizes, right to left and in night mode.
///
/// Settings are changed through the interface here, not with launch arguments: a launch argument
/// overrides the stored value, so Factory Defaults couldn't be seen to reset it.
extension NopeAppUITests {
    /// Opens Settings and its Presets screen.
    @MainActor
    func openPresetsInSettings(_ app: XCUIApplication) {
        openSettings(app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Presets")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
    }

    /// Scrolls the list until a button is on screen, then taps it.
    @MainActor
    func tapListButton(_ app: XCUIApplication, _ label: String) {
        let button = app.buttons[label]
        var swipes = 0
        while !(button.exists && button.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        button.tap()
    }

    /// Saves the current settings as a preset from the Presets screen.
    @MainActor
    func savePreset(_ app: XCUIApplication, named name: String) {
        tapListButton(app, "Save Current Settings")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(name)
        app.navigationBars["Save Preset"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
    }

    /// The Mirror Front Camera switch in Settings, scrolled into view.
    @MainActor
    func mirrorSwitch(_ app: XCUIApplication) -> XCUIElement {
        let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Mirror Front Camera")).firstMatch
        var swipes = 0
        while !(toggle.exists && toggle.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        return toggle
    }

    /// The Factory Defaults row, whose label also holds its explanation.
    @MainActor
    func factoryDefaults(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Factory Defaults")).firstMatch
    }

    /// Scrolls Settings back to its first row, Presets, and opens it.
    @MainActor
    func openPresetsRow(_ app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Presets")).firstMatch
        var swipes = 0
        while !(row.exists && row.isHittable) && swipes < 8 {
            app.swipeDown()
            swipes += 1
        }
        row.tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
    }

    /// Goes back one screen.
    @MainActor
    func backOneScreen(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    func testPresetsSaveApplyUndoRenameAndDelete() throws {
        let app = launch("allow")
        continuePastFirstRun(app)
        openPresetsInSettings(app)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)

        // Save the settings with Mirror Front Camera on.
        backOneScreen(app)
        let mirror = mirrorSwitch(app)
        mirror.switches.firstMatch.tap()
        XCTAssertEqual(mirror.value as? String, "1")
        openPresetsRow(app)
        tapListButton(app, "Save Current Settings")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        backOneScreen(app)
        savePreset(app, named: "Selfie")

        // Factory Defaults turns it off; the saved preset is kept.
        factoryDefaults(app).tap()
        XCTAssertTrue(element(app, containing: "Factory Defaults applied.").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Selfie"].exists)
        XCTAssertTrue(app.buttons["Undo"].exists)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        backOneScreen(app)
        XCTAssertEqual(mirrorSwitch(app).value as? String, "0")

        // The preset turns it on again, and Undo turns it back off.
        openPresetsRow(app)
        app.buttons["Selfie"].tap()
        XCTAssertTrue(element(app, containing: "“Selfie” applied.").waitForExistence(timeout: 5))
        backOneScreen(app)
        XCTAssertEqual(mirrorSwitch(app).value as? String, "1")
        openPresetsRow(app)
        app.buttons["Undo"].tap()
        XCTAssertFalse(app.buttons["Undo"].waitForExistence(timeout: 2))
        backOneScreen(app)
        XCTAssertEqual(mirrorSwitch(app).value as? String, "0")

        // Rename, then delete, from the preset's More menu (which replaced the Rename or Delete
        // page).
        openPresetsRow(app)
        tapListButton(app, "More for Selfie")
        let rename = app.buttons["Rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        XCTAssertTrue(app.navigationBars["Rename Preset"].waitForExistence(timeout: 5))
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        // Tap the field's trailing end, so the cursor is after the name, and add an "s".
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText("s")
        app.navigationBars["Rename Preset"].buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Selfies"].waitForExistence(timeout: 5))
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        tapListButton(app, "More for Selfies")
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["Delete Preset"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(element(app, containing: "No saved presets yet").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["More for Selfies"].exists)
    }

    @MainActor
    func testPresetsFromTheTrayInNightMode() throws {
        let app = launch("allow", extraArguments: ["-NopeSimulatedViewfinder", "white"])
        continuePastFirstRun(app)
        let viewfinder = app.otherElements["Viewfinder"].frame
        quickControl(app, "Night Mode")
        XCTAssertTrue(app.buttons["Night Mode"].isSelected)
        // Presets is further along Q, which stays open after a switch.
        let presets = app.buttons["Presets"]
        XCTAssertTrue(presets.waitForExistence(timeout: 5))
        presets.tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
        settle()
        // The white viewfinder keeps its natural colors behind the sheet; it shows at the sheet's
        // rounded top corners, so its frame is left out of the check.
        XCTAssertEqual(nonRedPixels(app, outside: viewfinder), 0, "the presets sheet is red on black")
        try audit(app)

        // Applying from Q works as in Settings: Factory Defaults turns night mode off.
        factoryDefaults(app).tap()
        XCTAssertTrue(element(app, containing: "Factory Defaults applied.").waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let quick = quickMenuButton(app)
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        if !quick.isSelected { quick.tap() }
        XCTAssertTrue(app.buttons["Night Mode"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Night Mode"].isSelected)
    }

    @MainActor
    func testPresetsAtTheLargestTextSize() throws {
        let app = launch("allow", extraArguments: Self.largestTextSize)
        continuePastFirstRun(app)
        quickControl(app, "Presets")
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
        try audit(app, checksContrast: !isPad)
        savePreset(app, named: "Bugs at night")
        app.swipeDown()
        app.swipeDown()
        tapListButton(app, "Bugs at night")
        XCTAssertTrue(element(app, containing: "“Bugs at night” applied.").waitForExistence(timeout: 5))
        try audit(app, checksContrast: !isPad)
    }

    @MainActor
    func testPresetsInRightToLeftLayout() throws {
        let app = launch("allow", extraArguments: Self.rightToLeft)
        continuePastFirstRun(app)
        openPresetsInSettings(app)
        savePreset(app, named: "Astro")
        app.buttons["Astro"].tap()
        XCTAssertTrue(element(app, containing: "“Astro” applied.").waitForExistence(timeout: 5))
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }
}
