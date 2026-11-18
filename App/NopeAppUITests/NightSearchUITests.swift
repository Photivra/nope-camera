import XCTest

/// UI tests for the red search field in Night Mode (issues #88 and #98,
/// `docs/design/night-search-field.md`): Settings and the Every Tag page show the app's own
/// field in Night Mode, all red with the keyboard closed and outside the keyboard's frame while
/// it is open; it finds rows by name and keyword, clears and cancels; a search is kept when
/// Night Mode changes from outside Settings; and it passes the accessibility audits at the
/// largest text size and right to left.
extension NopeAppUITests {
    /// The red search field.
    @MainActor
    func nightSearchField(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "nightSearchField").firstMatch
    }

    /// The system search field: a search field that isn't the red one, which VoiceOver and
    /// XCTest also see as a search field.
    @MainActor
    func systemSearchField(_ app: XCUIApplication) -> XCUIElement {
        app.searchFields.matching(NSPredicate(format: "identifier != %@", "nightSearchField")).firstMatch
    }

    /// Types into the red search field; a final "\n" ends editing, so the keyboard closes.
    @MainActor
    func typeInNightSearch(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = nightSearchField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no red search field", file: file, line: line)
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard didn't open", file: file, line: line)
        field.typeText(text)
    }

    /// Waits until the keyboard is gone.
    @MainActor
    func waitForKeyboardToClose(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "the keyboard is still open", file: file, line: line)
    }

    @MainActor
    func testNightSearchFieldIsRed() throws {
        let app = launch("denied", extraArguments: Self.nightModeOn)
        openSettingsScreen(app)
        let field = nightSearchField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Settings has the red search field in Night Mode")
        XCTAssertEqual(field.label, "Search Settings")
        XCTAssertEqual(field.elementType, .searchField, "VoiceOver hears a search field")
        XCTAssertFalse(systemSearchField(app).exists, "the system field isn't shown in Night Mode")
        // Under the title, above the list.
        XCTAssertLessThan(field.frame.maxY, settingsElement(app, "settings.presets").frame.minY + 1)
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0, "the field at rest isn't all red")
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        // With text and results.
        typeInNightSearch(app, "gps\n")
        waitForKeyboardToClose(app)
        XCTAssertTrue(app.buttons["settings.search.settings.details.location"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nightSearchField.cancel"].exists, "Cancel shows while there is text")
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0, "the field with results isn't all red")
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        // No result.
        app.buttons["nightSearchField.clear"].tap()
        nightSearchField(app).typeText("zqxj\n")
        waitForKeyboardToClose(app)
        XCTAssertTrue(element(app, containing: "No Results").waitForExistence(timeout: 5))
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0, "the empty state isn't all red")
        // With the keyboard open, everything outside the keyboard is red (decision 5).
        nightSearchField(app).tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        settle()
        // The keyboard as iOS draws it: its frame, and above it the bar for suggestions (empty,
        // with autocorrection off) and the rounded panel's edge, which XCTest's frame leaves out
        // (seen on the iPhone 18 Pro Simulator, iOS 27.2), across the whole width.
        let window = app.windows.firstMatch.frame
        let drawnKeyboard = CGRect(
            x: window.minX, y: keyboard.frame.minY - 60, width: window.width, height: window.maxY - keyboard.frame.minY + 60)
        XCTAssertEqual(nonRedPixels(app, outside: drawnKeyboard), 0, "something outside the keyboard isn't red")
    }

    @MainActor
    func testNightSearchFindsByKeyword() throws {
        let app = launch("denied", extraArguments: Self.nightModeOn)
        openSettingsScreen(app)
        typeInNightSearch(app, "gps\n")
        let result = app.buttons["settings.search.settings.details.location"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Details in Each Photo"), result.label)
        result.tap()
        XCTAssertTrue(app.navigationBars["Details in Each Photo"].waitForExistence(timeout: 5))
        // Going back shows the same search: its text and results (section 3).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(nightSearchField(app).value as? String, "gps")
        XCTAssertTrue(result.waitForExistence(timeout: 5), "the results are kept on going back")
        // A pointer to the camera, and Keep Screen On by a keyword, as with the system field.
        app.buttons["nightSearchField.clear"].tap()
        nightSearchField(app).typeText("manual\n")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "settings.search.camera.manualControls").firstMatch.waitForExistence(timeout: 5))
        app.buttons["nightSearchField.clear"].tap()
        nightSearchField(app).typeText("auto-lock\n")
        XCTAssertTrue(app.buttons["settings.search.settings.keepScreenOn"].waitForExistence(timeout: 5))
        // Assistant Access, added with the red field, by a keyword; its results are red too.
        app.buttons["nightSearchField.clear"].tap()
        nightSearchField(app).typeText("siri\n")
        waitForKeyboardToClose(app)
        XCTAssertTrue(app.buttons["settings.search.settings.assistantAccess"].waitForExistence(timeout: 5))
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0, "the Assistant Access results aren't all red")
    }

    @MainActor
    func testNightSearchCancelAndClear() throws {
        let app = launch("denied", extraArguments: Self.nightModeOn)
        openSettingsScreen(app)
        XCTAssertFalse(app.buttons["nightSearchField.cancel"].exists, "no Cancel at rest")
        XCTAssertFalse(app.buttons["nightSearchField.clear"].exists, "no Clear Text without text")
        typeInNightSearch(app, "formats")
        let clear = app.buttons["nightSearchField.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertEqual(clear.label, "Clear text")
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
        // Clear Text empties the field and keeps the keyboard; the list returns.
        clear.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard stays after Clear Text")
        XCTAssertFalse(clear.waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["settings.search.settings.formats"].exists, "the list returns")
        // Cancel empties the field, closes the keyboard and returns to the list.
        nightSearchField(app).typeText("formats")
        XCTAssertTrue(app.buttons["settings.search.settings.formats"].waitForExistence(timeout: 5))
        let cancel = app.buttons["nightSearchField.cancel"]
        XCTAssertEqual(cancel.label, "Cancel")
        cancel.tap()
        waitForKeyboardToClose(app)
        XCTAssertFalse(app.buttons["settings.search.settings.formats"].exists)
        XCTAssertFalse(cancel.waitForExistence(timeout: 2), "Cancel goes when the search ends")
        XCTAssertTrue(settingsElement(app, "settings.presets").exists)
        // Return keeps the text and the results and closes the keyboard.
        typeInNightSearch(app, "formats\n")
        waitForKeyboardToClose(app)
        XCTAssertTrue(app.buttons["settings.search.settings.formats"].exists)
        XCTAssertEqual(nightSearchField(app).value as? String, "formats")
        // Accessibility page: the keyboard and menus aren't red, and Night Mode doesn't dim.
        cancel.tap()
        settingsElement(app, "settings.accessibility").tap()
        XCTAssertTrue(app.navigationBars["Accessibility"].waitForExistence(timeout: 5))
        // The Night Mode entries are the page's last section.
        scrollToTheEndOfTheSettingsPage(app)
        XCTAssertTrue(element(app, containing: "The keyboard and menus are drawn by iOS and are not red.").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Night Mode doesn't change the screen's brightness.").exists)
    }

    /// Night Mode switched from outside Settings, as Siri or Control Center do, keeps the
    /// search and its results, in both directions (decision 7).
    @MainActor
    func testNightSearchKeptWhenNightModeChanges() throws {
        let app = launch("denied", extraArguments: Self.nightModeOn + ["-NopeSimulatedNightModeSwitch", "30,20"])
        openSettingsScreen(app)
        typeInNightSearch(app, "gps\n")
        let result = app.buttons["settings.search.settings.details.location"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        // Night Mode turns off: the system field returns with the same text and results.
        let systemField = systemSearchField(app)
        XCTAssertTrue(systemField.waitForExistence(timeout: 40), "Night Mode didn't turn off")
        XCTAssertFalse(nightSearchField(app).exists)
        XCTAssertEqual(systemField.value as? String, "gps")
        XCTAssertTrue(result.exists, "the results are kept")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        // Night Mode turns on again: the red field has the text.
        XCTAssertTrue(nightSearchField(app).waitForExistence(timeout: 40), "Night Mode didn't turn on again")
        XCTAssertEqual(nightSearchField(app).value as? String, "gps")
        XCTAssertTrue(result.exists, "the results are kept")
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0)
    }

    @MainActor
    func testNightSearchAtLargestTextSize() throws {
        let app = launch("denied", extraArguments: Self.nightModeOn + Self.largestTextSize)
        openSettingsScreen(app)
        let field = nightSearchField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(field.frame.height, 44)
        try audit(app, checksContrast: !isPad)
        typeInNightSearch(app, "gps\n")
        waitForKeyboardToClose(app)
        // At accessibility sizes Cancel is under the field, not beside it.
        let cancel = app.buttons["nightSearchField.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(cancel.frame.minY, nightSearchField(app).frame.maxY - 1, "Cancel isn't under the field")
        XCTAssertTrue(app.buttons["settings.search.settings.details.location"].waitForExistence(timeout: 5))
        try audit(app, checksContrast: !isPad)
    }

    @MainActor
    func testNightSearchRightToLeft() throws {
        let app = launch("denied", extraArguments: Self.nightModeOn + Self.rightToLeft)
        openSettingsScreen(app)
        typeInNightSearch(app, "gps\n")
        waitForKeyboardToClose(app)
        let field = nightSearchField(app)
        let clear = app.buttons["nightSearchField.clear"]
        let cancel = app.buttons["nightSearchField.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        // Mirrored: Clear Text and Cancel at the trailing edge, which is the left.
        XCTAssertLessThan(cancel.frame.maxX, field.frame.minX + 1, "Cancel isn't on the left")
        XCTAssertLessThan(clear.frame.midX, field.frame.midX, "Clear Text isn't on the left")
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    /// Issue #98: the Every Tag page of What's in This Photo uses the red field in Night Mode,
    /// named "Search" as the page's system field is.
    @MainActor
    func testEveryTagNightSearchField() throws {
        let app = launch("manual", extraArguments: Self.detailsKept + Self.nightModeOn)
        openPhotoDetails(app)
        let raw = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "RAW (DNG), ")).firstMatch
        XCTAssertTrue(scrollDetails(app, to: raw))
        raw.tap()
        XCTAssertTrue(app.navigationBars["RAW (DNG)"].waitForExistence(timeout: 5))
        let field = nightSearchField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Every Tag has the red search field in Night Mode")
        XCTAssertEqual(field.label, "Search")
        XCTAssertFalse(systemSearchField(app).exists, "the system field isn't shown in Night Mode")
        // The navigation bar is left out: its back button is the system's glass, outside this
        // issue (the field is under the bar).
        let bar = app.navigationBars.firstMatch.frame
        XCTAssertEqual(nonRedPixels(app, outside: bar), 0, "Every Tag with the field isn't all red")
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        // Search filters by name and opens the groups that match; Cancel clears it.
        typeInNightSearch(app, "DNGVersion\n")
        waitForKeyboardToClose(app)
        let version = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "DNGVersion")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        XCTAssertFalse(disclosureRow(app, "EXIF").exists, "a group without a match is left out")
        XCTAssertEqual(nonRedPixels(app, outside: bar), 0, "Every Tag while searching isn't all red")
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        app.buttons["nightSearchField.cancel"].tap()
        XCTAssertTrue(disclosureRow(app, "EXIF").waitForExistence(timeout: 5))
    }
}
