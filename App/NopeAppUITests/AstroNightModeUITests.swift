import XCTest

/// UI tests for night mode and Astro: Astro turns night mode on, and leaving Astro turns it off
/// again unless it was on before, the person changed it while Astro was on, or Keep Night Mode
/// After Astro is on (Settings › Screen). The `manual` scenario's wide lens offers Astro. Every
/// launch starts from the default settings (`SimulatedCameraLaunch.settingsStore()`), so a
/// relaunch (which keeps night mode as it was) can't be tested here; `AstroNightModeTests`
/// covers it.
extension NopeAppUITests {
    /// Keep Night Mode After Astro on, as a launch argument.
    static let keepsNightModeAfterAstro = ["-NopeSettings.keepsNightModeAfterAstro", "YES"]

    /// Chooses Astro on the drive strip and waits until it is selected.
    @MainActor
    private func chooseAstro(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        driveStripWord(app, "Astro").tap()
        let selected = app.buttons.matching(NSPredicate(format: "label == %@ AND selected == YES", "Astro")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(element(app, containing: "Astro frames").waitForExistence(timeout: 10), file: file, line: line)
    }

    /// Leaves Astro for Single on the drive strip and waits until Astro is off.
    @MainActor
    private func leaveAstro(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        driveStripWord(app, "Single").tap()
        XCTAssertTrue(element(app, containing: "Astro frames").waitForNonExistence(timeout: 5), file: file, line: line)
    }

    /// Whether night mode is on, as Q's Night Mode tile shows it. Q is closed again afterwards.
    @MainActor
    private func nightModeTileIsOn(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let quick = quickMenuButton(app)
        XCTAssertTrue(quick.waitForExistence(timeout: 10), file: file, line: line)
        scrollUntilHittable(app, quick)
        if !quick.isSelected { quick.tap() }
        let tile = app.buttons["Night Mode"]
        scrollUntilHittable(app, tile)
        XCTAssertTrue(tile.waitForExistence(timeout: 5), file: file, line: line)
        let isOn = tile.isSelected
        closeTray(app)
        return isOn
    }

    /// Closes Settings: Done on a sheet, outside the popover on iPad.
    @MainActor
    private func closeSettingsScreen(_ app: XCUIApplication) {
        let done = app.buttons["Done"]
        if done.exists {
            done.tap()
        } else {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
    }

    /// Opens Settings and checks the Keep Night Mode After Astro row: right after Night Mode, off
    /// by default, with its explanation.
    @MainActor
    private func checkKeepNightModeRow(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        openSettings(app, file: file, line: line)
        let nightMode = settingsElement(app, "settings.nightMode")
        let row = settingsElement(app, "settings.keepNightModeAfterAstro")
        XCTAssertTrue(row.exists, "the row is shown where the device offers Astro", file: file, line: line)
        // At the largest text size the switch and its explanation are stacked; on iOS 26.5 the
        // row's label then holds only the explanation and the title is the switch's own, so the
        // words are looked for in the row and the elements inside it (`row(_:shows:)`).
        XCTAssertTrue(self.row(row, shows: "Keep Night Mode After Astro"), row.debugDescription, file: file, line: line)
        XCTAssertTrue(self.row(row, shows: "stays on after you leave Astro"), row.debugDescription, file: file, line: line)
        if nightMode.exists, nightMode.isHittable {
            XCTAssertLessThan(nightMode.frame.minY, row.frame.minY, "the row follows Night Mode", file: file, line: line)
        }
        let red = settingsElement(app, "settings.redViewfinder")
        settingsElement(app, "settings.keepNightModeAfterAstro")
        if red.exists, red.isHittable {
            XCTAssertLessThan(row.frame.minY, red.frame.minY, "Red Viewfinder follows the row", file: file, line: line)
        }
        return row
    }

    @MainActor
    func testKeepNightModeAfterAstroSetting() throws {
        let app = launch("manual")
        let row = checkKeepNightModeRow(app)
        XCTAssertEqual(row.switches.firstMatch.value as? String, "0", "off by default")
        // Scrolled: rows under the translucent bar are judged as the other Settings tests do.
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
        // Search finds it by a keyword.
        flipSwitch(row)
        waitUntil(timeout: .seconds(5)) { (row.switches.firstMatch.value as? String) == "1" }
        XCTAssertEqual(row.switches.firstMatch.value as? String, "1")
        searchSettings(app, for: "stars")
        XCTAssertTrue(
            app.buttons["settings.search.settings.keepNightModeAfterAstro"].waitForExistence(timeout: 5),
            "search finds the row by a keyword")
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        app.terminate()

        // Night mode: Settings is a red-on-black sheet with no search field.
        let night = launch("manual", extraArguments: Self.nightModeOn)
        _ = checkKeepNightModeRow(night)
        try audit(night, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testKeepNightModeAfterAstroSettingAtTheLargestTextSizeAndRightToLeft() throws {
        let large = launch("manual", extraArguments: Self.largestTextSize)
        _ = checkKeepNightModeRow(large)
        try audit(large, afterScrolling: true, checksContrast: !isPad)
        large.terminate()

        let rightToLeft = launch("manual", extraArguments: Self.rightToLeft)
        _ = checkKeepNightModeRow(rightToLeft)
        try audit(rightToLeft, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testLeavingAstroTurnsNightModeBackOff() throws {
        let app = launch("manual", extraArguments: ["-NopeSimulatedViewfinder", "white"])
        XCTAssertFalse(nightModeTileIsOn(app))
        chooseAstro(app)
        // Astro turns night mode on.
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0, "the camera is red on black")
        try audit(app)
        leaveAstro(app)
        // Night mode was off before Astro: it is off again.
        XCTAssertGreaterThan(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0, "night mode went off")
        XCTAssertFalse(nightModeTileIsOn(app))
        try audit(app)

        // Changed by the person while Astro is on (here off and on again in Q): theirs, kept.
        chooseAstro(app)
        quickControl(app, "Night Mode")
        XCTAssertFalse(app.buttons["Night Mode"].isSelected)
        app.buttons["Night Mode"].tap()
        XCTAssertTrue(app.buttons["Night Mode"].isSelected)
        closeTray(app)
        leaveAstro(app)
        XCTAssertTrue(nightModeTileIsOn(app), "the person's night mode stays on")
        app.terminate()

        // On before Astro: stays on.
        let before = launch("manual", extraArguments: Self.nightModeOn)
        chooseAstro(before)
        leaveAstro(before)
        XCTAssertTrue(nightModeTileIsOn(before), "night mode that was on before Astro stays on")
        before.terminate()

        // Keep Night Mode After Astro: stays on.
        let keep = launch("manual", extraArguments: Self.keepsNightModeAfterAstro)
        chooseAstro(keep)
        leaveAstro(keep)
        XCTAssertTrue(nightModeTileIsOn(keep), "Keep Night Mode After Astro keeps it on")
        try audit(keep)
    }

    @MainActor
    func testLeavingAstroAtTheLargestTextSizeAndRightToLeft() throws {
        let large = launch("manual", extraArguments: Self.largestTextSize)
        chooseAstro(large)
        try auditScrollingScreen(large)
        leaveAstro(large)
        XCTAssertFalse(nightModeTileIsOn(large), "night mode went off")
        try auditScrollingScreen(large)
        large.terminate()

        let rightToLeft = launch("manual", extraArguments: Self.rightToLeft)
        chooseAstro(rightToLeft)
        try audit(rightToLeft)
        leaveAstro(rightToLeft)
        XCTAssertFalse(nightModeTileIsOn(rightToLeft), "night mode went off")
        try audit(rightToLeft)
    }

    /// Issue #108: only the app forgets, at launch, that Astro turned night mode on. Each launch
    /// starts as if the app had been left with Astro on: night mode on, and the record that
    /// Astro turned it on. The app forgets the record, so leaving Astro keeps night mode on; the
    /// Lock Screen camera (simulated: XCTest can't launch the capture extension) leaves the
    /// record alone, so leaving Astro there still turns night mode off.
    @MainActor
    func testOnlyTheAppForgetsThatAstroTurnedNightModeOn() throws {
        let leftInAstro = Self.nightModeOn + ["-NopeAstro.isNightModeFromAstro", "YES"]
        let app = launch("manual", extraArguments: leftInAstro)
        XCTAssertTrue(nightModeTileIsOn(app))
        chooseAstro(app)
        leaveAstro(app)
        XCTAssertTrue(nightModeTileIsOn(app), "the app forgot the record at launch: night mode is the person's")
        app.terminate()

        // The flag last: it takes no value.
        let lockScreen = launch("manual", extraArguments: leftInAstro + ["-NopeSimulatedLockScreenCamera"])
        XCTAssertTrue(nightModeTileIsOn(lockScreen))
        chooseAstro(lockScreen)
        leaveAstro(lockScreen)
        XCTAssertFalse(nightModeTileIsOn(lockScreen), "the Lock Screen camera left the record: night mode went off")
        try audit(lockScreen)
    }
}
