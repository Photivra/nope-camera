import XCTest

/// UI tests for the 1.0.0 Settings structure and its sheets (`docs/design/BUILD-SPEC.md`, 3.9
/// and 3.10, chunk G): the root rows and their order, Details in Each Photo, HEIF and JPEG
/// Copies, search with keywords and camera pointers, Show Processed Marker, Red Viewfinder,
/// presets with the More menu and the delete confirmation, and the night mode rule for the
/// iPad popover. Each screen is audited at the default and largest text sizes, right to left
/// and in night mode.
///
/// Most tests use the "denied" scenario, where the Settings button sits above the camera
/// content in every layout; the Processed marker test needs a ready camera without RAW.
extension NopeAppUITests {
    /// The identifiers of the Settings list's rows, in order, as the "denied" scenario on the
    /// Simulator shows them: no lens is known, so Photo Size and Show Processed Marker are left
    /// out, and the Simulator offers no Live Activity. Keep Screen On is always shown in the app.
    static let settingsRootRows = [
        "settings.presets", "settings.formats", "settings.copies", "settings.mirrorFrontCamera",
        "settings.details", "settings.signEachPhoto", "settings.assistantAccess", "settings.fastShutter", "settings.focusOnFaces",
        "settings.startInCleanView", "settings.overlays", "settings.nightMode", "settings.redViewfinder",
        "settings.keepScreenOn", "settings.accessibility", "settings.honesty", "settings.about",
    ]

    /// Opens Settings: from the Settings button where there is one, otherwise from Q.
    @MainActor
    func openSettingsScreen(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let settings = app.buttons["Settings"]
        if !settings.waitForExistence(timeout: 10) {
            let quick = app.buttons["Quick Menu"]
            XCTAssertTrue(quick.waitForExistence(timeout: 5), "no Settings button and no Q", file: file, line: line)
            quick.tap()
            XCTAssertTrue(settings.waitForExistence(timeout: 5), file: file, line: line)
        }
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), file: file, line: line)
    }

    /// The Settings element with an identifier, scrolled wholly into view: down the list, then
    /// back up.
    @MainActor @discardableResult
    func settingsElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let frame = settingsListFrame(app)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func point(_ fraction: CGFloat) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * fraction))
        }
        for towardEnd in [true, false] {
            var steps = 0
            while !(element.exists && element.isHittable && frame.contains(element.frame)) && steps < 15 {
                point(towardEnd ? 0.7 : 0.4).press(forDuration: 0.05, thenDragTo: point(towardEnd ? 0.4 : 0.7))
                steps += 1
            }
        }
        return element
    }

    /// Types a search into the Settings search field.
    @MainActor
    func searchSettings(_ app: XCUIApplication, for text: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // Return ends editing, so the keyboard and its bar are gone before an audit.
        field.typeText(text + "\n")
    }

    /// Flips a Settings switch: the system switch inside a row, or, in night mode, the row
    /// itself, which is the switch (`NightModeSwitch`).
    @MainActor
    func flipSwitch(_ row: XCUIElement) {
        let inner = row.switches.firstMatch
        if inner.exists { inner.tap() } else { row.tap() }
    }

    /// Checks that every root row is there, each below the one before it.
    @MainActor
    func assertSettingsRootRowsInOrder(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // From the top, so each row is found by scrolling down.
        settingsElement(app, "settings.presets")
        var previous: XCUIElement?
        for identifier in Self.settingsRootRows {
            let row = settingsElement(app, identifier)
            XCTAssertTrue(row.exists, "\(identifier) is missing", file: file, line: line)
            if let previous, previous.exists, previous.isHittable {
                XCTAssertLessThan(previous.frame.minY, row.frame.minY, "\(identifier) is out of order", file: file, line: line)
            }
            previous = row
        }
    }

    @MainActor
    func testSettingsRootRowsDoNotChange() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        assertSettingsRootRowsInOrder(app)
        // The rows that used to come and go: none appears or disappears when a switch changes.
        flipSwitch(settingsElement(app, "settings.nightMode"))
        flipSwitch(settingsElement(app, "settings.signEachPhoto"))
        assertSettingsRootRowsInOrder(app)
        XCTAssertFalse(app.switches["Manual Controls"].exists, "Manual Controls left Settings (issue 77)")
        XCTAssertFalse(app.switches["Remove All Optional Details"].exists, "the master switch is only on Details in Each Photo")
    }

    @MainActor
    func testRedViewfinderAlwaysShown() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        let red = settingsElement(app, "settings.redViewfinder")
        XCTAssertTrue(red.exists, "Red Viewfinder is shown with Night Mode off")
        XCTAssertTrue(red.label.contains("In Night Mode"), red.label)
        // Scrolled: rows under the translucent bar are judged as the other Settings tests do.
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testDetailsInEachPhotoPage() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        let row = settingsElement(app, "settings.details")
        XCTAssertTrue(row.label.contains("All Optional Removed"), row.label)
        row.tap()
        XCTAssertTrue(app.navigationBars["Details in Each Photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Remove All Optional Details"].exists)
        XCTAssertTrue(app.staticTexts["Other Details"].exists || app.staticTexts["OTHER DETAILS"].exists)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        // Location turns the master switch off, and the row says so.
        let location = settingsElement(app, "settings.details.location")
        XCTAssertTrue(location.exists)
        location.switches.firstMatch.tap()
        let deadline = Date().addingTimeInterval(5)
        while (location.switches.firstMatch.value as? String) != "1" && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let changed = settingsElement(app, "settings.details")
        XCTAssertTrue(changed.label.contains("Custom, Location On"), changed.label)
    }

    @MainActor
    func testDetailsInEachPhotoAtTheLargestTextSize() throws {
        let app = launch("denied", extraArguments: Self.largestTextSize)
        openSettingsScreen(app)
        settingsElement(app, "settings.details").tap()
        XCTAssertTrue(app.navigationBars["Details in Each Photo"].waitForExistence(timeout: 5))
        try audit(app, checksContrast: !isPad)
        settingsElement(app, "settings.details.standardFileTags")
        try audit(app, afterScrolling: true, checksContrast: !isPad)
    }

    @MainActor
    func testCopiesPageWithRAWOnly() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        let row = settingsElement(app, "settings.copies")
        XCTAssertTrue(row.label.contains("Not Saved"), row.label)
        row.tap()
        XCTAssertTrue(app.navigationBars["HEIF and JPEG Copies"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "No HEIF or JPEG copy is saved now").exists)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        // Editable with RAW only: a file option changes, and Restore Defaults appears.
        XCTAssertFalse(app.buttons["Restore Defaults"].exists)
        let copySize = settingsElement(app, "settings.copies.copySize")
        // The menu opens from its value, a button inside the row.
        let menu = copySize.buttons.firstMatch
        if menu.exists { menu.tap() } else { copySize.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.85)).tap() }
        let half = app.buttons["Half Size"]
        XCTAssertTrue(half.waitForExistence(timeout: 5), copySize.debugDescription)
        half.tap()
        let restore = settingsElement(app, "settings.copies.restoreDefaults")
        XCTAssertTrue(restore.exists)
        restore.tap()
        XCTAssertFalse(app.buttons["Restore Defaults"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCopiesPageAtTheLargestTextSize() throws {
        let app = launch("denied", extraArguments: Self.largestTextSize)
        openSettingsScreen(app)
        settingsElement(app, "settings.copies").tap()
        XCTAssertTrue(app.navigationBars["HEIF and JPEG Copies"].waitForExistence(timeout: 5))
        try audit(app, checksContrast: !isPad)
        settingsElement(app, "settings.copies.copySize")
        try audit(app, afterScrolling: true, checksContrast: !isPad)
    }

    @MainActor
    func testSettingsSearchFindsLocationByKeyword() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        searchSettings(app, for: "gps")
        let result = app.buttons["settings.search.settings.details.location"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Location"), result.label)
        XCTAssertTrue(result.label.contains("Details in Each Photo"), result.label)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        result.tap()
        XCTAssertTrue(app.navigationBars["Details in Each Photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings.details.location").firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsSearchFindsEveryRootRowByName() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        for name in ["Formats", "Mirror Front Camera", "Sign Each Photo", "Fast Shutter", "Focus on Faces", "Red Viewfinder", "Honesty"] {
            let field = app.searchFields.firstMatch
            field.tap()
            if let text = field.value as? String, !text.isEmpty, text != field.placeholderValue {
                field.buttons.firstMatch.tap()
                // In the iPad popover, clearing the field ended the search: the keyboard left,
                // and typing failed with "Neither element nor any descendant has keyboard
                // focus". Tapping the field again gives it the focus on both devices.
                field.tap()
            }
            field.typeText(name)
            let found = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            XCTAssertTrue(found.waitForExistence(timeout: 5), "search didn't find \(name)")
        }
    }

    @MainActor
    func testSettingsSearchPointsToCamera() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        searchSettings(app, for: "manual")
        let pointer = app.descendants(matching: .any).matching(identifier: "settings.search.camera.manualControls").firstMatch
        XCTAssertTrue(pointer.waitForExistence(timeout: 5))
        XCTAssertTrue(pointer.label.contains("On the camera, beside the lenses"), pointer.label)
        XCTAssertNotEqual(pointer.elementType, .button, "a pointer doesn't navigate")
        XCTAssertFalse(app.buttons["settings.search.camera.manualControls"].exists)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        // "reset" finds Presets and Restore Defaults.
        let field = app.searchFields.firstMatch
        field.tap()
        field.buttons.firstMatch.tap()
        // As in testSettingsSearchFindsEveryRootRowByName: clearing ends the search on iPad.
        field.tap()
        field.typeText("reset\n")
        XCTAssertTrue(app.buttons["settings.search.settings.presets"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.search.settings.copies.restoreDefaults"].exists)
    }

    @MainActor
    func testSettingsSearchNoResults() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        searchSettings(app, for: "zqxj")
        XCTAssertTrue(element(app, containing: "No Results").waitForExistence(timeout: 5))
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testShowProcessedMarkerSwitch() throws {
        let app = launch("noRAW")
        openSettingsScreen(app)
        let marker = settingsElement(app, "settings.showProcessedMarker")
        XCTAssertTrue(marker.exists, "Show Processed Marker is offered on a device with a lens without RAW")
        XCTAssertTrue(marker.label.hasPrefix("Show Processed Marker"), marker.label)
        let toggle = marker.switches.firstMatch
        let before = toggle.value as? String
        toggle.tap()
        XCTAssertNotEqual(toggle.value as? String, before)
        XCTAssertTrue(settingsElement(app, "settings.photoSize").exists, "Photo Size is offered for a lens without RAW")
        // Scrolled: rows under the translucent bar are judged as the other Settings tests do.
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testDeletePresetAsksFirst() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        settingsElement(app, "settings.presets").tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
        savePreset(app, named: "Street")
        let more = app.buttons["More for Street"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        try audit(app, checksDynamicType: false, checksContrast: !isPad)

        // Rename opens the Rename Preset page, which has no Delete button.
        more.tap()
        app.buttons["Rename"].tap()
        XCTAssertTrue(app.navigationBars["Rename Preset"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Delete Preset"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))

        // Delete asks first; Cancel keeps the preset.
        more.tap()
        app.buttons["Delete"].tap()
        let confirm = app.buttons["Delete Preset"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Delete “Street”?").exists)
        // The confirmation is the system's own; it isn't audited here.
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.tap()
        } else {
            // An iPad popover has no Cancel button: tapping outside it cancels.
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["Street"].waitForExistence(timeout: 5))
        more.tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertFalse(app.buttons["Street"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSettingsRedesignAtTheLargestTextSize() throws {
        let app = launch("denied", extraArguments: Self.largestTextSize)
        openSettingsScreen(app)
        try audit(app, checksContrast: !isPad)
        settingsElement(app, "settings.redViewfinder")
        try audit(app, afterScrolling: true, checksContrast: !isPad)
        searchSettings(app, for: "flash")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings.search.camera.flash").firstMatch.waitForExistence(timeout: 5))
        try audit(app, checksContrast: !isPad)
    }

    @MainActor
    func testSettingsRedesignRightToLeft() throws {
        let app = launch("denied", extraArguments: Self.rightToLeft)
        openSettingsScreen(app)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        searchSettings(app, for: "gps")
        XCTAssertTrue(app.buttons["settings.search.settings.details.location"].waitForExistence(timeout: 5))
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        app.buttons["settings.search.settings.details.location"].tap()
        XCTAssertTrue(app.navigationBars["Details in Each Photo"].waitForExistence(timeout: 5))
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testSettingsRedesignInNightMode() throws {
        let app = launch("denied", extraArguments: ["-NopeSettings.isNightModeOn", "YES"])
        openSettingsScreen(app)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        settingsElement(app, "settings.copies").tap()
        XCTAssertTrue(app.navigationBars["HEIF and JPEG Copies"].waitForExistence(timeout: 5))
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // Night Mode has the app's own red search field (issue #88) instead of the system's,
        // which iOS draws as gray glass. Turning Night Mode off brings the system field back,
        // and the Night Mode row, whose switch was just used, stays in view.
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(systemSearchField(app).exists, "no system search field in Night Mode")
        XCTAssertTrue(nightSearchField(app).exists, "the red search field in Night Mode")
        let nightMode = settingsElement(app, "settings.nightMode")
        flipSwitch(nightMode)
        XCTAssertTrue(systemSearchField(app).waitForExistence(timeout: 5), "the system field returns when Night Mode is off")
        XCTAssertFalse(nightSearchField(app).exists)
        settle()
        XCTAssertTrue(nightMode.exists && nightMode.isHittable, "the Night Mode row stays in view")
        searchSettings(app, for: "manual")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings.search.camera.manualControls").firstMatch.waitForExistence(timeout: 5))
    }

    /// On iPad, turning Night Mode on while the Settings popover is open moves Settings to the
    /// night-mode sheet at once (owner decision of 2026-11-17).
    @MainActor
    func testNightModeInTheSettingsPopoverSwitchesToTheSheet() throws {
        try XCTSkipUnless(isPad, "Settings is a popover only in a regular-width window")
        let app = launch("denied")
        openSettingsScreen(app)
        // The popover hangs from the Settings button at the window's top; the sheet is centered
        // lower in the window.
        let bar = app.navigationBars["Settings"]
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(bar.frame.minY, window.height * 0.1, "Settings opens as a popover")
        flipSwitch(settingsElement(app, "settings.nightMode"))
        let deadline = Date().addingTimeInterval(5)
        while !(bar.exists && bar.frame.minY > window.height * 0.1) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(bar.exists, "Settings stays open")
        XCTAssertGreaterThan(bar.frame.minY, window.height * 0.1, "Settings is now the night-mode sheet")
        try audit(app, checksDynamicType: false, checksContrast: false)
    }
}
