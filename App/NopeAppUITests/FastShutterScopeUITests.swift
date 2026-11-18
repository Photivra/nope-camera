import XCTest

/// UI tests for where Fast Shutter is used (`docs/design/BUILD-SPEC.md`, 3.16;
/// `docs/design/SETTING-SCOPE.md`): the note under the Settings row, the two paragraphs of the
/// Fast Shutter page, the page's top line while Manual Controls are on, and the Q tile and the
/// pill, which are shown only while Manual Controls are off. Each screen is audited at the
/// default and largest text sizes, right to left and in night mode.
///
/// Manual Controls off is the "aids" scenario, a ready camera in full auto; on is the "manual"
/// scenario with `-NopeSettings.showsManualControls YES`.
extension NopeAppUITests {
    /// The note under the Fast Shutter row.
    static let fastShutterNote = "Used only while Manual Controls are off."

    /// The page's top line while Manual Controls are on.
    static let fastShutterNotUsedNow = "settings.fastShutter.notUsedNow"

    /// Launches a ready camera with Manual Controls off or on.
    ///
    /// - Parameters:
    ///   - manualControlsOn: Whether Manual Controls are on.
    ///   - arguments: More launch arguments.
    @MainActor
    func launchForFastShutter(manualControlsOn: Bool, _ arguments: [String] = []) -> XCUIApplication {
        manualControlsOn
            ? launch("manual", extraArguments: ["-NopeSettings.showsManualControls", "YES"] + arguments)
            : launch("aids", extraArguments: arguments)
    }

    /// Opens the Fast Shutter page from Settings and waits for it.
    @MainActor
    func openFastShutterPage(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        settingsElement(app, "settings.fastShutter").tap()
        XCTAssertTrue(app.navigationBars["Fast Shutter"].waitForExistence(timeout: 5), file: file, line: line)
    }

    /// The window's bottom trailing corner, where iPadOS draws the window's resize handle: a
    /// gray arc of the system's, outside the app's views, so night mode's red can't reach it
    /// (seen in the night mode screenshot on the iPad Simulator, iOS 27.2). Empty on iPhone.
    @MainActor
    func windowCorner(_ app: XCUIApplication) -> CGRect {
        guard isPad else { return .null }
        let window = app.windows.firstMatch.frame
        let side: CGFloat = 40
        return CGRect(x: window.maxX - side, y: window.maxY - side, width: side, height: side)
    }

    /// The identifiers of the Settings list's rows, read while scrolling it from the top to the
    /// end, so rows the list hasn't drawn yet are counted too.
    @MainActor
    func settingsRootRowIdentifiers(_ app: XCUIApplication) -> Set<String> {
        settingsElement(app, "settings.presets")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'settings.'"))
        let frame = settingsListFrame(app)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func point(_ fraction: CGFloat) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * fraction))
        }
        var found = Set<String>()
        for _ in 0..<12 {
            let before = found.count
            found.formUnion(rows.allElementsBoundByIndex.map(\.identifier))
            if found.contains("settings.about"), found.count == before { break }
            point(0.75).press(forDuration: 0.05, thenDragTo: point(0.35))
        }
        return found
    }

    @MainActor
    func testFastShutterRowSaysWhereItIsUsed() throws {
        let choices = [
            ("handheld", "Standard"), ("freezeMotion", "Freeze Motion (1/500 s)"),
            ("freezeFastMotion", "Freeze Fast Motion (1/1000 s)"),
        ]
        for manualControlsOn in [false, true] {
            for (choice, value) in choices {
                let app = launchForFastShutter(manualControlsOn: manualControlsOn, ["-NopeSettings.fastShutter", choice])
                openSettings(app)
                let row = settingsElement(app, "settings.fastShutter")
                XCTAssertTrue(row.exists, "\(choice), manual \(manualControlsOn)")
                // VoiceOver reads the title, the value, then the note; the note is the same in
                // every case.
                XCTAssertTrue(row.label.hasPrefix("Fast Shutter"), row.label)
                XCTAssertTrue(row.label.contains(value), row.label)
                XCTAssertTrue(row.label.hasSuffix(Self.fastShutterNote), row.label)
                if let valueRange = row.label.range(of: value), let noteRange = row.label.range(of: Self.fastShutterNote) {
                    XCTAssertLessThan(valueRange.lowerBound, noteRange.lowerBound, row.label)
                }
                // Only the Fast Shutter row has the note.
                let noted = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", Self.fastShutterNote))
                for element in noted.allElementsBoundByIndex {
                    XCTAssertTrue(row.frame.insetBy(dx: -1, dy: -1).contains(element.frame), element.debugDescription)
                }
                if choice == "freezeFastMotion" {
                    try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
                }
                app.terminate()
            }
        }
    }

    @MainActor
    func testFastShutterPageExplainsWhereItIsUsed() throws {
        let app = launchForFastShutter(manualControlsOn: false)
        openSettings(app)
        openFastShutterPage(app)
        XCTAssertTrue(element(app, containing: "Used only while Manual Controls are off. The camera keeps the shutter at least as fast").exists)
        XCTAssertTrue(element(app, containing: "With Manual Controls on, this choice is not used.").exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: Self.fastShutterNotUsedNow).firstMatch.exists)
        XCTAssertFalse(element(app, containing: "In full auto, the camera prefers").exists, "the old explanation is gone")
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testFastShutterPageWithManualControlsOn() throws {
        let app = launchForFastShutter(manualControlsOn: true)
        openSettings(app)
        let rowsBefore = settingsRootRowIdentifiers(app)
        openFastShutterPage(app)
        let notUsed = app.descendants(matching: .any).matching(identifier: Self.fastShutterNotUsedNow).firstMatch
        XCTAssertTrue(notUsed.waitForExistence(timeout: 5))
        XCTAssertTrue(notUsed.label.contains("Manual Controls are on, so this choice is not used now."), notUsed.label)
        // The line comes first, and every choice stays enabled.
        let freeze = app.buttons["Freeze Motion (1/500 s)"]
        XCTAssertTrue(freeze.exists)
        XCTAssertLessThan(notUsed.frame.minY, app.buttons["Standard"].frame.minY)
        for name in ["Standard", "Freeze Motion (1/500 s)", "Freeze Fast Motion (1/1000 s)"] {
            XCTAssertTrue(app.buttons[name].isEnabled, name)
        }
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        freeze.tap()
        XCTAssertTrue(freeze.isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let row = settingsElement(app, "settings.fastShutter")
        XCTAssertTrue(row.label.contains("Freeze Motion (1/500 s)"), row.label)
        XCTAssertTrue(row.label.hasSuffix(Self.fastShutterNote), row.label)
        XCTAssertEqual(settingsRootRowIdentifiers(app), rowsBefore, "the choice changes no row of the root")
    }

    @MainActor
    func testFastShutterNoteLargestTextAndRightToLeft() throws {
        for (arguments, checksDynamicType) in [(Self.largestTextSize, true), (Self.rightToLeft, false)] {
            let app = launchForFastShutter(manualControlsOn: true, arguments)
            openSettings(app)
            let row = settingsElement(app, "settings.fastShutter")
            XCTAssertTrue(row.label.hasSuffix(Self.fastShutterNote), row.label)
            // The audit's clipped-text check covers truncation of the note and the value.
            try audit(app, afterScrolling: true, checksDynamicType: checksDynamicType, checksContrast: !isPad)
            // The audit's text size changes redraw the list: find the row again.
            settingsElement(app, "settings.fastShutter").tap()
            XCTAssertTrue(app.navigationBars["Fast Shutter"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: Self.fastShutterNotUsedNow).firstMatch.exists)
            try audit(app, checksDynamicType: checksDynamicType, checksContrast: !isPad)
            // The paragraphs at the page's end, scrolled inside the list (on iPad a swipe over
            // the window can miss the popover).
            let second = element(app, containing: "With Manual Controls on, this choice is not used.")
            let frame = settingsListFrame(app)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            var drags = 0
            while !(second.exists && second.isHittable && frame.contains(second.frame)) && drags < 10 {
                origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * 0.75))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * 0.35)))
                drags += 1
            }
            XCTAssertTrue(second.exists, "the second paragraph")
            try audit(app, afterScrolling: true, checksDynamicType: checksDynamicType, checksContrast: !isPad)
            app.terminate()
        }
    }

    @MainActor
    func testFastShutterNoteNightModeIsAllRed() throws {
        let app = launchForFastShutter(manualControlsOn: true, Self.nightModeOn)
        openSettings(app)
        let row = settingsElement(app, "settings.fastShutter")
        XCTAssertTrue(row.label.hasSuffix(Self.fastShutterNote), row.label)
        settle()
        let groupPixels = nonRedPixels(app, outsideAll: [windowCorner(app)])
        if groupPixels != 0 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Camera group, night mode"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertEqual(groupPixels, 0, "white, blue or other colors remain in the Camera group")
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
        settingsElement(app, "settings.fastShutter").tap()
        XCTAssertTrue(app.navigationBars["Fast Shutter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: Self.fastShutterNotUsedNow).firstMatch.exists)
        settle()
        // The back button is the system's glass, drawn outside the app's views where night
        // mode's red filter can't reach it (as the search field, see `SettingsSearchField`): its
        // gray rim was the only light that wasn't red on this page (90 samples, all inside it).
        // It is on every page pushed in Settings and isn't part of this change.
        let back = app.navigationBars.buttons.element(boundBy: 0).frame.insetBy(dx: -6, dy: -6)
        let pagePixels = nonRedPixels(app, outsideAll: [back, windowCorner(app)])
        if pagePixels != 0 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Fast Shutter page, night mode"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertEqual(pagePixels, 0, "white, blue or other colors remain on the Fast Shutter page")
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testFastShutterLeavesCameraWithManualControlsOn() throws {
        for manualControlsOn in [false, true] {
            let app = launchForFastShutter(manualControlsOn: manualControlsOn, ["-NopeSettings.fastShutter", "freezeMotion"])
            XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 20))
            // The pill on the status line, only while the choice is used.
            let pill = app.buttons["Fast Shutter"]
            if manualControlsOn {
                XCTAssertFalse(pill.waitForExistence(timeout: 3), "no Fast Shutter pill with Manual Controls on")
            } else {
                XCTAssertTrue(pill.waitForExistence(timeout: 10), "the Fast Shutter pill with Manual Controls off")
            }
            // The tile in Q, likewise.
            openQuickMenu(app)
            let tile = quickTile(app, "fastShutter")
            XCTAssertEqual(tile.exists, !manualControlsOn, "the Q tile, manual \(manualControlsOn)")
            if !manualControlsOn { XCTAssertEqual(tile.value as? String, "1/500") }
            try audit(app)
            app.terminate()
        }
    }
}
