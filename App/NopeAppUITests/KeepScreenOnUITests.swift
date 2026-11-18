import XCTest

/// UI tests for Keep Screen On (issue #97, `docs/design/keep-screen-on.md`) and for a series on
/// a screen that is already dark (issue #99): the row in Settings › Screen, off by default, its
/// explanation and search; the dimming and the Brighten Screen cover; not used under a sheet or
/// while Battery Low shows; with accessibility audits in light, dark and night mode, at the
/// largest text size and right to left.
///
/// The times are shortened with `-NopeKeepScreenOnSeconds` (``keepScreenOnTimes``), and the
/// screen's brightness starts at a known value with `-NopeSimulatedBrightness`. The idle timer
/// itself can't be read by XCTest; the unit tests (`KeepScreenOnTests`) cover it.
extension NopeAppUITests {
    /// Keep Screen On on, dimming after 4 seconds (2 in Low Power Mode), the limit after 60, on
    /// a screen at 80%.
    static let keepScreenOnTimes = [
        "-NopeSettings.keepsScreenOn", "YES", "-NopeKeepScreenOnSeconds", "4,2,60", "-NopeSimulatedBrightness", "0.8",
    ]

    /// The cover of the dimmed screen.
    @MainActor
    func brightenScreen(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Brighten Screen"]
    }

    @MainActor
    func testKeepScreenOnRow() throws {
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            useAppearance(appearance)
            let app = launch("denied")
            openSettingsScreen(app)
            let red = settingsElement(app, "settings.redViewfinder")
            let row = settingsElement(app, "settings.keepScreenOn")
            XCTAssertTrue(row.exists, "Keep Screen On is in Settings")
            XCTAssertTrue(row.label.hasPrefix("Keep Screen On"), row.label)
            XCTAssertTrue(row.label.contains("While the camera is showing, the screen stays on for 30 minutes"), row.label)
            XCTAssertTrue(row.label.contains("Not used while Battery Low shows."), row.label)
            if red.exists {
                XCTAssertLessThan(red.frame.minY, row.frame.minY, "Keep Screen On comes after Red Viewfinder")
            }
            XCTAssertEqual(row.switches.firstMatch.value as? String, "0", "off by default")
            try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
            app.terminate()
        }
        useAppearance(.light)
        let night = launch("denied", extraArguments: Self.nightModeOn)
        openSettingsScreen(night)
        let row = settingsElement(night, "settings.keepScreenOn")
        XCTAssertTrue(row.exists)
        // The night row is the switch itself (NightModeSwitch).
        XCTAssertEqual(row.value as? String ?? row.switches.firstMatch.value as? String, "0")
        XCTAssertEqual(nonRedPixels(night, outside: .zero), 0)
        try audit(night, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
        // Night Mode's explanation no longer says the app never changes the brightness.
        let nightMode = settingsElement(night, "settings.nightMode")
        XCTAssertTrue(nightMode.label.contains("Night Mode doesn't change the screen's brightness."), nightMode.label)
    }

    @MainActor
    func testKeepScreenOnRowAtTheLargestTextSizeAndRightToLeft() throws {
        for arguments in [Self.largestTextSize, Self.rightToLeft] {
            let app = launch("denied", extraArguments: arguments)
            openSettingsScreen(app)
            // Near the end of a long list at the largest size: swipe until it is on screen.
            let row = app.descendants(matching: .any).matching(identifier: "settings.keepScreenOn").firstMatch
            for _ in 0..<30 where !(row.exists && row.isHittable) { app.swipeUp() }
            XCTAssertTrue(row.exists && row.isHittable, "Keep Screen On is in Settings")
            try audit(app, afterScrolling: true, checksDynamicType: arguments == Self.largestTextSize, checksContrast: !isPad)
            app.terminate()
        }
    }

    @MainActor
    func testKeepScreenOnDimsAndBrightens() throws {
        let app = launch("allow", extraArguments: Self.keepScreenOnTimes)
        continuePastFirstRun(app)
        let cover = brightenScreen(app)
        XCTAssertTrue(cover.waitForExistence(timeout: 20), "the screen didn't dim")
        XCTAssertEqual(cover.value as? String, "Screen dimmed to save battery. Tap to brighten it.")
        try audit(app)
        // The first touch only brightens.
        cover.tap()
        XCTAssertTrue(cover.waitForNonExistence(timeout: 5))
        XCTAssertFalse(lastPhoto(app, says: "Saved", timeout: 1), "the touch took no photo")
        // It dims again after the same time without a touch.
        XCTAssertTrue(cover.waitForExistence(timeout: 20), "the screen didn't dim again")
        // A photo from a hardware shutter or Siri while dimmed is taken; the screen stays dimmed.
        cover.tap()
        XCTAssertTrue(cover.waitForNonExistence(timeout: 5))
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(lastPhoto(app, says: "Saved", timeout: 15))
    }

    @MainActor
    func testKeepScreenOnInNightMode() throws {
        let app = launch("allow", extraArguments: Self.keepScreenOnTimes + Self.nightModeOn)
        continuePastFirstRun(app)
        let cover = brightenScreen(app)
        XCTAssertTrue(cover.waitForExistence(timeout: 20), "the screen didn't dim")
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0, "the cover isn't red on black")
        try audit(app)
    }

    @MainActor
    func testKeepScreenOffDoesNotDim() throws {
        let app = launch("allow", extraArguments: ["-NopeKeepScreenOnSeconds", "2,1,60", "-NopeSimulatedBrightness", "0.8"])
        continuePastFirstRun(app)
        XCTAssertFalse(brightenScreen(app).waitForExistence(timeout: 8), "the screen dimmed with Keep Screen On off")
    }

    @MainActor
    func testKeepScreenOnNotUsedUnderASheet() throws {
        let app = launch("allow", extraArguments: Self.keepScreenOnTimes)
        continuePastFirstRun(app)
        openSettings(app)
        // Settings over the camera: not used, so nothing dims under it.
        XCTAssertFalse(brightenScreen(app).waitForExistence(timeout: 8), "the screen dimmed under Settings")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
        // Back on the camera, the count starts again: no cover at once, then after the time.
        XCTAssertFalse(brightenScreen(app).exists, "the screen dimmed at once after the sheet closed")
        XCTAssertTrue(brightenScreen(app).waitForExistence(timeout: 20), "the screen didn't dim on the camera")
    }

    @MainActor
    func testKeepScreenOnNotUsedWhileBatteryLowShows() throws {
        let app = launch("noRAW", extraArguments: Self.keepScreenOnTimes + ["-NopeSimulatedDeviceStatus", "lowBattery"])
        let chip = app.buttons["Battery Low"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertTrue(
            (chip.value as? String)?.contains("Charge the device soon to keep taking photos. Keep Screen On is not used now.") == true,
            chip.value as? String ?? "")
        XCTAssertFalse(brightenScreen(app).waitForExistence(timeout: 8), "the screen dimmed while Battery Low shows")
        try audit(app)
        app.terminate()
        // Low Power Mode has its own sentence, with the same addition.
        let lowPower = launch("noRAW", extraArguments: Self.keepScreenOnTimes + ["-NopeSimulatedDeviceStatus", "lowBatteryLowPower"])
        let lowPowerChip = lowPower.buttons["Battery Low"]
        XCTAssertTrue(lowPowerChip.waitForExistence(timeout: 10))
        XCTAssertTrue(
            (lowPowerChip.value as? String)?.contains("Low Power Mode is on. Keep Screen On is not used now.") == true,
            lowPowerChip.value as? String ?? "")
        lowPower.terminate()
        // With the switch off, the warning says nothing about it.
        let off = launch("noRAW", extraArguments: ["-NopeSimulatedDeviceStatus", "lowBattery"])
        let offChip = off.buttons["Battery Low"]
        XCTAssertTrue(offChip.waitForExistence(timeout: 10))
        XCTAssertFalse((offChip.value as? String)?.contains("Keep Screen On") == true)
    }

    @MainActor
    func testSettingsSearchFindsKeepScreenOn() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        for (index, word) in ["auto-lock", "awake", "Keep Screen On"].enumerated() {
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            if index > 0 {
                field.buttons.firstMatch.tap()
                // As in testSettingsSearchFindsEveryRootRowByName: clearing ends the search on iPad.
                field.tap()
            }
            field.typeText(word + "\n")
            let result = app.buttons["settings.search.settings.keepScreenOn"]
            XCTAssertTrue(result.waitForExistence(timeout: 5), "search for \"\(word)\" finds Keep Screen On")
            XCTAssertTrue(result.label.contains("Screen"), result.label)
        }
        app.buttons["settings.search.settings.keepScreenOn"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "settings.keepScreenOn").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        settle()
        XCTAssertTrue(row.isHittable, "choosing the result scrolls to the row")
    }

    @MainActor
    func testKeepScreenOnPresetRoundTrip() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        let row = settingsElement(app, "settings.keepScreenOn")
        flipSwitch(row)
        XCTAssertEqual(switchValue(row), "1")
        settle()
        openPresetsRow(app)
        savePreset(app, named: "Tripod")
        // Factory Defaults turns it off; the preset turns it on again.
        factoryDefaults(app).tap()
        XCTAssertTrue(element(app, containing: "Factory Defaults applied.").waitForExistence(timeout: 5))
        backOneScreen(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(switchValue(settingsElement(app, "settings.keepScreenOn")), "0", "Factory Defaults turns it off")
        openPresetsRow(app)
        app.buttons["Tripod"].tap()
        XCTAssertTrue(element(app, containing: "applied.").waitForExistence(timeout: 5))
        backOneScreen(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(switchValue(settingsElement(app, "settings.keepScreenOn")), "1", "the preset turns it on")
    }

    /// A Settings switch's value: the system switch inside a row, or the row itself in night mode.
    @MainActor
    func switchValue(_ row: XCUIElement) -> String? {
        let inner = row.switches.firstMatch
        return (inner.exists ? inner.value : row.value) as? String
    }

    /// Issue #99: an interval series on a screen already at 10% or darker doesn't dim it and
    /// shows no Brighten Screen cover; above 10% it still does.
    @MainActor
    func testSeriesDoesNotDimAScreenAlreadyDark() throws {
        let app = launch("allow", extraArguments: ["-NopeSimulatedBrightness", "0.05"])
        continuePastFirstRun(app)
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 20))
        chooseDrive(app, "Interval")
        shutter.tap()
        XCTAssertTrue(element(app, containing: "photos taken").waitForExistence(timeout: 20))
        XCTAssertFalse(brightenScreen(app).waitForExistence(timeout: 8), "a dark screen was dimmed")
        app.terminate()
        let bright = launch("allow", extraArguments: ["-NopeSimulatedBrightness", "0.5"])
        continuePastFirstRun(bright)
        let brightShutter = bright.buttons["Take Photo"]
        XCTAssertTrue(brightShutter.waitForExistence(timeout: 20))
        chooseDrive(bright, "Interval")
        brightShutter.tap()
        XCTAssertTrue(brightenScreen(bright).waitForExistence(timeout: 15), "the series didn't dim the screen")
    }
}
