import XCTest

/// UI tests for the capture and file settings added for issue #57 after 0.2.0: the copy size in
/// HEIF and JPEG Copies (File Options before 1.0.0), Focus on Faces (Face Detection before
/// 1.0.0), the photo size of a lens without RAW and the Far Focus limit, each with an
/// accessibility audit.
extension NopeAppUITests {
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
        // A HEIF copy, so the copy size applies; RAW only is the default (issue #80).
        openSettingsRow(app, "Formats")
        let heif = app.buttons["HEIF"]
        XCTAssertTrue(heif.waitForExistence(timeout: 5))
        heif.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openSettingsRow(app, "HEIF and JPEG Copies")
        XCTAssertTrue(app.navigationBars["HEIF and JPEG Copies"].waitForExistence(timeout: 5))
        XCTAssertTrue(settingsElement(app, "settings.copies.copySize").exists)
        chooseCopiesOption(app, "Half Size", inRow: "settings.copies.copySize")
        let restore = app.buttons["Restore Defaults"]
        scrollToTheEndOfTheSettingsPage(app)
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        XCTAssertTrue(restore.isHittable)
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testFaceDetectionIsOffByDefaultAndCanBeTurnedOn() throws {
        let app = launch("denied")
        openSettings(app)
        let faces = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Focus on Faces")).firstMatch
        XCTAssertTrue(element(app, containing: "Formats").waitForExistence(timeout: 10))
        var swipes = 0
        while !(faces.exists && faces.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(faces.exists)
        XCTAssertEqual(faces.value as? String, "0")
        XCTAssertTrue(faces.label.contains("follow faces the camera finds."), faces.label)
        faces.switches.firstMatch.tap()
        XCTAssertEqual(faces.value as? String, "1")
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
        let quick = quickMenuButton(app)
        XCTAssertTrue(quick.waitForExistence(timeout: 20))
        quick.tap()
        XCTAssertTrue(app.buttons["Close-Up"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Far Focus"].exists)
        quick.tap()
        app.terminate()

        let manual = launch("aids", extraArguments: ["-NopeSettings.showsManualControls", "YES"])
        quickControl(manual, "Far Focus")
        quickMenuButton(manual).tap()
        XCTAssertTrue(manual.buttons["Hide Controls"].waitForNonExistence(timeout: 5))
        let pill = manual.buttons["Far Focus"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        try audit(manual)
        pill.tap()
        let off = manual.buttons["Turn Off Far Focus"]
        if off.waitForExistence(timeout: 5) { off.tap() }
        XCTAssertFalse(manual.buttons["Far Focus"].waitForExistence(timeout: 3))
    }
}
