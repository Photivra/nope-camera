import XCTest

/// UI tests for the Burst Limit setting (issue #121; `docs/design/finish-1.0.md`, section 5.1):
/// the row last in Settings › Camera, Off by default, its menu and explanation, search, presets
/// and Factory Defaults, with accessibility audits in light, dark and night mode, at the largest
/// text size and right to left. The burst that stops at the limit comes with the shutter work
/// (`docs/plans/1.0.0-finish.md`, section 4.2), and its tests with it (`BurstUITests`).
extension NopeAppUITests {
    /// The Burst Limit explanation.
    static let burstLimitExplanation =
        "In Burst, one press takes this many photos; press again to stop early. Off: a tap takes one photo, and holding takes photos until you let go."

    /// Opens Settings and checks the Burst Limit row: after Focus on Faces, with its explanation.
    @MainActor @discardableResult
    func checkBurstLimitRow(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        openSettingsScreen(app, file: file, line: line)
        let faces = settingsElement(app, "settings.focusOnFaces")
        let row = settingsElement(app, "settings.burstLimit")
        XCTAssertTrue(row.exists, "Burst Limit is in Settings", file: file, line: line)
        XCTAssertTrue(self.row(row, shows: "Burst Limit"), row.debugDescription, file: file, line: line)
        XCTAssertTrue(self.row(row, shows: Self.burstLimitExplanation), row.debugDescription, file: file, line: line)
        if faces.exists, faces.isHittable {
            XCTAssertLessThan(faces.frame.minY, row.frame.minY, "Burst Limit follows Focus on Faces", file: file, line: line)
        }
        let start = settingsElement(app, "settings.startInCleanView")
        if start.exists, start.isHittable, row.isHittable {
            XCTAssertLessThan(row.frame.minY, start.frame.minY, "Burst Limit is last in Camera", file: file, line: line)
        }
        return row
    }

    @MainActor
    func testBurstLimitRow() throws {
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            useAppearance(appearance)
            let app = launch("denied")
            let row = checkBurstLimitRow(app)
            XCTAssertTrue(self.row(row, shows: "Off"), "Off by default: \(row.debugDescription)")
            try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
            for choice in ["3", "5", "10", "20", "50", "Off"] {
                chooseCopiesOption(app, choice, inRow: "settings.burstLimit")
                XCTAssertTrue(self.row(settingsElement(app, "settings.burstLimit"), shows: choice), choice)
            }
            app.terminate()
        }
        useAppearance(.light)
        let night = launch("denied", extraArguments: Self.nightModeOn + ["-NopeSettings.burstLimit", "ten"])
        let row = checkBurstLimitRow(night)
        XCTAssertTrue(self.row(row, shows: "10"), row.debugDescription)
        XCTAssertEqual(nonRedPixels(night, outside: .zero), 0)
        try audit(night, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testBurstLimitRowAtTheLargestTextSizeAndRightToLeft() throws {
        for arguments in [Self.largestTextSize, Self.rightToLeft] {
            let app = launch("denied", extraArguments: arguments + ["-NopeSettings.burstLimit", "twenty"])
            openSettingsScreen(app)
            let row = settingsElement(app, "settings.burstLimit")
            // At the largest size the list is many screens long: swipe on if the drags stopped short.
            for _ in 0..<30 where !(row.exists && row.isHittable) { app.swipeUp() }
            XCTAssertTrue(row.exists && row.isHittable, "Burst Limit is in Settings")
            XCTAssertTrue(self.row(row, shows: Self.burstLimitExplanation), "the explanation isn't cut: \(row.debugDescription)")
            try audit(app, afterScrolling: true, checksDynamicType: arguments == Self.largestTextSize, checksContrast: !isPad)
            app.terminate()
        }
    }

    @MainActor
    func testSettingsSearchFindsBurstLimit() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        for (index, word) in ["limit", "frames", "continuous", "Burst Limit"].enumerated() {
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            if index > 0 {
                field.buttons.firstMatch.tap()
                field.tap()
            }
            field.typeText(word + "\n")
            let result = app.buttons["settings.search.settings.burstLimit"]
            XCTAssertTrue(result.waitForExistence(timeout: 5), "search for \"\(word)\" finds Burst Limit")
            XCTAssertTrue(result.label.contains("Camera"), result.label)
        }
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        app.buttons["settings.search.settings.burstLimit"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "settings.burstLimit").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        settle()
        XCTAssertTrue(row.isHittable, "choosing the result scrolls to the row")
    }

    @MainActor
    func testBurstLimitPresetRoundTrip() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        chooseCopiesOption(app, "10", inRow: "settings.burstLimit")
        XCTAssertTrue(row(settingsElement(app, "settings.burstLimit"), shows: "10"))
        openPresetsRow(app)
        savePreset(app, named: "Sports")
        // Factory Defaults turns it off; the preset sets it again.
        factoryDefaults(app).tap()
        XCTAssertTrue(element(app, containing: "Factory Defaults applied.").waitForExistence(timeout: 5))
        backOneScreen(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(row(settingsElement(app, "settings.burstLimit"), shows: "Off"), "Factory Defaults turns it off")
        openPresetsRow(app)
        app.buttons["Sports"].tap()
        XCTAssertTrue(element(app, containing: "applied.").waitForExistence(timeout: 5))
        backOneScreen(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(row(settingsElement(app, "settings.burstLimit"), shows: "10"), "the preset sets it again")
    }
}
