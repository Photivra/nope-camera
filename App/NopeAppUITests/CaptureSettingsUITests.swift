import XCTest

/// UI tests for the capture and file settings added for issue #57 after 0.2.0: the copy size in
/// File Options, Face Detection, the photo size of a lens without RAW and the Far Focus limit,
/// each with an accessibility audit.
extension NopeAppUITests {
    /// Opens Settings from the camera.
    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 20))
        settingsButton.tap()
    }

    /// Scrolls to a navigation row whose label contains the text, and opens it, once Settings is
    /// open. The list creates rows only as they scroll into view, so the row is scrolled to
    /// rather than waited for: at the largest text size Photo Size is below the fold and didn't
    /// exist until then.
    @MainActor
    private func openSettingsRow(_ app: XCUIApplication, _ text: String) {
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), text)
        open(app, row: text)
    }

    /// Opens a pushed-list picker by its label and chooses an option in it.
    @MainActor
    private func pick(_ app: XCUIApplication, _ option: String, inPickerLabeled label: String) {
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), label)
        var swipes = 0
        while !picker.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        picker.tap()
        let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", option)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), option)
        item.tap()
    }

    @MainActor
    func testCopySizeInFileOptions() throws {
        let app = launch("denied")
        openSettings(app)
        openSettingsRow(app, "File Options")
        XCTAssertTrue(app.navigationBars["File Options"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Copy Size").exists)
        pick(app, "Half Size", inPickerLabeled: "Copy Size")
        let restore = app.buttons["Restore Defaults"]
        var swipes = 0
        while !(restore.exists && restore.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testFaceDetectionIsOnByDefaultAndCanBeTurnedOff() throws {
        let app = launch("denied")
        openSettings(app)
        let faces = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Face Detection")).firstMatch
        XCTAssertTrue(element(app, containing: "Formats").waitForExistence(timeout: 10))
        var swipes = 0
        while !(faces.exists && faces.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(faces.exists)
        XCTAssertEqual(faces.value as? String, "1")
        XCTAssertTrue(faces.label.contains("follow faces the camera finds"))
        faces.switches.firstMatch.tap()
        XCTAssertEqual(faces.value as? String, "0")
        try audit(app, afterScrolling: swipes > 0, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testPhotoSizeOfALensWithoutRAW() throws {
        let app = launch("noRAW")
        openSettings(app)
        openSettingsRow(app, "Photo Size")
        XCTAssertTrue(app.navigationBars["Photo Size"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, containing: "These lenses have no RAW").exists)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        pick(app, "48 MP", inPickerLabeled: "Front")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element(app, containing: "Custom").waitForExistence(timeout: 10))
    }

    @MainActor
    func testPhotoSizeAtTheLargestTextSize() throws {
        let app = launch("noRAW", extraArguments: Self.largestTextSize)
        openSettings(app)
        openSettingsRow(app, "Photo Size")
        XCTAssertTrue(app.navigationBars["Photo Size"].waitForExistence(timeout: 10))
        try audit(app, checksContrast: !isPad)
    }

    @MainActor
    func testNoPhotoSizeRowWhenEveryLensHasRAW() throws {
        let app = launch("denied")
        openSettings(app)
        XCTAssertTrue(element(app, containing: "Formats").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Photo Size")).firstMatch.exists)
    }

    @MainActor
    func testFarFocusNeedsManualControlsAndShowsAPill() throws {
        let app = launch("aids")
        let tray = app.buttons["Quick Controls"]
        XCTAssertTrue(tray.waitForExistence(timeout: 20))
        tray.tap()
        XCTAssertTrue(app.buttons["Close-Up"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Far Focus"].exists)
        tray.tap()
        app.terminate()

        let manual = launch("aids", extraArguments: ["-NopeSettings.showsManualControls", "YES"])
        quickControl(manual, "Far Focus")
        manual.buttons["Quick Controls"].tap()
        let pill = manual.buttons["Far Focus"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        try audit(manual)
        pill.tap()
        let off = manual.buttons["Turn Off Far Focus"]
        if off.waitForExistence(timeout: 5) { off.tap() }
        XCTAssertFalse(manual.buttons["Far Focus"].waitForExistence(timeout: 3))
    }
}
