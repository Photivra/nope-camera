import XCTest

/// UI tests for What's in This Photo (`docs/design/BUILD-SPEC.md`, 3.15): the summary, the groups
/// in order, the disclosure rows, the processed and signature states, the hidden location, the
/// Every Tag page and the cover in the app switcher, with accessibility audits at the default
/// and largest text sizes, right to left, in night mode, sideways and on iPad.
///
/// The simulated camera reports 1/60 s and ISO 100 and saves files whose read-back is minimal;
/// `-NopeSimulatedFileTags full` gives the read-back realistic tags, each only where the current
/// settings allow it (`SimulatedFileTags`), and `-NopeSimulatedSaveSettings` sets the formats
/// and the details kept for the launch.
extension NopeAppUITests {
    /// The launch arguments that set the save settings: the formats, the optional details kept
    /// and whether photos are signed, as the JSON `NopeSettings` stores
    /// (`-NopeSimulatedSaveSettings`, debug builds only).
    static func detailsSettings(formats: [String], items: [String], signs: Bool) -> [String] {
        let quoted = { (values: [String]) in values.map { "\"\($0)\"" }.joined(separator: ",") }
        let json = """
            {"formats":[\(quoted(formats))],"developedLook":"standard","metadata":{"removesAllOptionalDetails":\(items.isEmpty),\
            "enabledItems":[\(quoted(items))],"signsPhotos":\(signs),"ownerName":"","copyrightNotice":""}}
            """
        // Base64: JSON text in a launch argument made the arguments domain ignore the others.
        return ["-NopeSimulatedSaveSettings", Data(json.utf8).base64EncodedString()]
    }

    /// RAW and HEIF, with the date, camera, lens, exposure and app name kept, signing on, and
    /// the fuller simulated tags.
    static let detailsKept =
        detailsSettings(
            formats: ["raw", "heif"],
            items: ["dateAndTime", "cameraMakeAndModel", "lensMakeAndModel", "exposureSettings", "appNameAndVersion"],
            signs: true) + ["-NopeSimulatedFileTags", "full"]

    /// RAW only, with the location kept and the fuller simulated tags.
    static let locationKept =
        detailsSettings(formats: ["raw"], items: ["location"], signs: false) + ["-NopeSimulatedFileTags", "full"]

    /// Scrolls the details until the element can be tapped, and says whether it exists.
    @MainActor
    @discardableResult
    func scrollDetails(_ app: XCUIApplication, to element: XCUIElement) -> Bool {
        scrollSheet(app, to: element)
        return element.exists
    }

    /// Scrolls the details back up until the element can be tapped, at most ten swipes.
    @MainActor
    func scrollDetailsBack(_ app: XCUIApplication, to element: XCUIElement) {
        for _ in 0..<20 where !(element.exists && element.isHittable) { app.swipeDown() }
    }

    /// A row of the summary by its fact: `kind`, `signature`, `details` or `location`
    /// (issue #118).
    @MainActor
    func summaryRow(_ app: XCUIApplication, _ fact: String) -> XCUIElement {
        app.descendants(matching: .any)["PhotoDetails.summary.\(fact)"]
    }

    /// Checks the summary's head and rows: each row one element with exactly these words, below
    /// the head and in the fixed order (kind, signature, details, location).
    @MainActor
    func checkSummary(
        _ app: XCUIApplication, head: [String], rows: [String], file: StaticString = #filePath, line: UInt = #line
    ) {
        let summary = app.descendants(matching: .any)["PhotoDetails.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), file: file, line: line)
        // The head scrolls away at the largest text size, so its words are read first.
        let headLabel = summary.label
        for words in head {
            XCTAssertTrue(headLabel.contains(words), "\(words) not in \(headLabel)", file: file, line: line)
        }
        var lastY = summary.frame.minY
        for (fact, label) in zip(["kind", "signature", "details", "location"], rows) {
            let row = summaryRow(app, fact)
            // At the largest text size the rows go below the screen: a short drag at a time, so
            // no row is passed.
            var drags = 0
            while !(row.exists && row.isHittable) && drags < 12 {
                let window = app.windows.firstMatch
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                    .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
                drags += 1
            }
            XCTAssertTrue(row.exists, fact, file: file, line: line)
            XCTAssertEqual(row.label, label, fact, file: file, line: line)
            // The head's words aren't repeated in a row, and a row's words aren't in the head.
            XCTAssertFalse(headLabel.contains(label), fact, file: file, line: line)
            // Each row is below the one before; after a drag the earlier ones have moved up.
            if drags == 0 { XCTAssertGreaterThan(row.frame.minY, lastY, fact, file: file, line: line) }
            lastY = row.frame.minY
        }
    }

    /// A disclosure row of the details by its title.
    @MainActor
    func disclosureRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    @MainActor
    func testDetailsSummaryForDefaultPhoto() throws {
        let app = launch("manual")
        openPhotoDetails(app)
        // The head, then one row for each fact (issue #118): "Saved." is gone, and the signing
        // row is the state with the reason under it.
        checkSummary(
            app, head: ["RAW (DNG)"],
            rows: [
                "RAW: one frame of sensor data", "Not signed, Signing is off in Settings", "No optional details in the files",
                "No location in the files",
            ])
        let summary = app.descendants(matching: .any)["PhotoDetails.summary"]
        XCTAssertFalse(summary.label.contains("Saved"), summary.label)
        // The lens and the time the shutter took it, from the session, as the viewer's caption
        // (BUILD-SPEC.md, 3.15, group 0; section 6, item 15).
        XCTAssertNotNil(
            summary.label.range(of: "1× · [0-9]{1,2}:[0-9]{2}", options: .regularExpression), summary.label)
        // Exposure Settings is off: the camera's shutter and ISO, each "Not in the files".
        let shutter = element(app, containing: "1/60")
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        XCTAssertTrue(shutter.label.contains("Not in the files"), shutter.label)
        XCTAssertTrue(element(app, containing: "100, Not in the files").exists)
        XCTAssertTrue(element(app, containing: "Exposure Settings is off").exists)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        let lens = element(app, containing: "Lens, 1×")
        XCTAssertTrue(scrollDetails(app, to: lens))
        XCTAssertTrue(lens.label.contains("Not in the files"), lens.label)
        try audit(app, afterScrolling: true, checksDynamicType: false)
    }

    @MainActor
    func testDetailsGroupsInOrder() throws {
        let app = launch("manual", extraArguments: Self.detailsKept)
        openPhotoDetails(app)
        checkSummary(
            app, head: ["RAW (DNG) and HEIF"],
            rows: [
                "RAW: one frame of sensor data, and a HEIF copy developed by nope.", "Signed", "5 optional details in the files",
                "No location in the files",
            ])
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        var lastY = -CGFloat.infinity
        var scrolled = 0
        for header in [
            "Exposure", "Lens and Camera", "RAW Sensor Data", "Files", "Processing", "Details in This Photo",
            "Content Credentials", "Every Tag",
        ] {
            let heading = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", header)).firstMatch
            scrolled += scrollSheet(app, to: heading)
            XCTAssertTrue(heading.exists, header)
            // A heading reached without scrolling sits below the one before it.
            if scrolled == 0 { XCTAssertGreaterThan(heading.frame.minY, lastY, header) }
            lastY = heading.frame.minY
            scrolled = 0
        }
        XCTAssertTrue(scrollDetails(app, to: app.buttons["Open in Photos"]))
        // Files: the RAW, the HEIF and how they were added to Photos. The simulated read-back
        // reports no bit depth for a copy, so its color space and quality aren't listed here;
        // the unit tests cover them.
        let pairing = element(app, containing: "One photo: the RAW with its HEIF")
        scrollDetailsBack(app, to: pairing)
        XCTAssertTrue(pairing.exists)
        XCTAssertTrue(element(app, containing: "12-bit · lossless").exists)
        XCTAssertTrue(element(app, containing: "HEIF, ").exists)
        try audit(app, afterScrolling: true, checksDynamicType: false)
    }

    @MainActor
    func testDetailsDisclosureRows() throws {
        let app = launch("manual", extraArguments: Self.detailsKept)
        openPhotoDetails(app)
        let more = disclosureRow(app, "More Exposure Details")
        XCTAssertTrue(scrollDetails(app, to: more))
        more.tap()
        let program = element(app, containing: "Normal program")
        XCTAssertTrue(scrollDetails(app, to: program))
        XCTAssertTrue(scrollDetails(app, to: element(app, containing: "Pattern")))
        try audit(app, afterScrolling: true, checksDynamicType: false)
        scrollDetailsBack(app, to: more)
        more.tap()
        XCTAssertFalse(program.waitForExistence(timeout: 2))
        let sensor = disclosureRow(app, "More Sensor Details")
        XCTAssertTrue(scrollDetails(app, to: sensor))
        sensor.tap()
        XCTAssertTrue(scrollDetails(app, to: element(app, containing: "Lossless JPEG")))
        // In the Files starts open; Left Out and Always Saved start closed.
        let written = disclosureRow(app, "In the Files")
        XCTAssertTrue(scrollDetails(app, to: written))
        XCTAssertTrue(scrollDetails(app, to: element(app, containing: "Shown under Exposure")))
        let leftOut = disclosureRow(app, "Left Out")
        XCTAssertTrue(scrollDetails(app, to: leftOut))
        XCTAssertFalse(element(app, containing: "Sub-Second Time").exists)
        leftOut.tap()
        XCTAssertTrue(scrollDetails(app, to: element(app, containing: "Sub-Second Time, Off in Settings")))
        let saved = disclosureRow(app, "Always Saved")
        XCTAssertTrue(scrollDetails(app, to: saved))
        saved.tap()
        // The list loads rows as they scroll into view, so the opened rows may be below it.
        XCTAssertTrue(scrollDetails(app, to: element(app, containing: "Always kept")))
        let timing = disclosureRow(app, "Timing")
        XCTAssertTrue(scrollDetails(app, to: timing))
        timing.tap()
        XCTAssertTrue(scrollDetails(app, to: element(app, containing: "Taking the Photo")))
        try audit(app, afterScrolling: true, checksDynamicType: false)
    }

    @MainActor
    func testDetailsProcessedPhoto() throws {
        let app = launch("noRAW")
        openPhotoDetails(app)
        // A warning row begins with "Warning"; "iPhone" reads "iPad" on an iPad.
        checkSummary(
            app, head: ["HEIF"],
            rows: [
                deviceText(
                    "Warning, Processed by this iPhone, This lens can't save RAW",
                    iPad: "Warning, Processed by this iPad, This lens can't save RAW"),
                "Not signed, Signing is off in Settings", "No optional details in the files", "No location in the files",
            ])
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        XCTAssertTrue(scrollDetails(app, to: element(app, containing: "Distortion correction")))
        XCTAssertTrue(scrollDetails(app, to: element(app, containing: "nope. didn't change this file's picture.")))
        XCTAssertFalse(app.staticTexts["RAW Sensor Data"].exists)
        try audit(app, afterScrolling: true, checksDynamicType: false)
    }

    @MainActor
    func testDetailsSignatureStates() throws {
        let cases: [(scenario: String, arguments: [String], sentence: String)] = [
            ("manual", Self.signingOn, "The signature lets anyone check"),
            ("manual", [], "Sign Each Photo is off in Settings"),
            ("signingFails", Self.signingOn, "couldn't create the signature for this photo"),
        ]
        for (scenario, arguments, sentence) in cases {
            let app = launch(scenario, extraArguments: arguments)
            openPhotoDetails(app)
            let explanation = element(app, containing: sentence)
            XCTAssertTrue(scrollDetails(app, to: explanation), sentence)
            try audit(app, afterScrolling: true, checksDynamicType: false)
            app.terminate()
        }
    }

    @MainActor
    func testDetailsLocationHiddenUntilShown() throws {
        let app = launch("manual", extraArguments: Self.locationKept)
        openPhotoDetails(app)
        XCTAssertTrue(summaryRow(app, "location").waitForExistence(timeout: 5))
        XCTAssertEqual(summaryRow(app, "location").label, "Warning, Location is in the files")
        let show = app.buttons["Show Value, Location"]
        XCTAssertTrue(scrollDetails(app, to: show))
        let row = app.descendants(matching: .any).matching(identifier: "PhotoDetails.hiddenValue").firstMatch
        XCTAssertTrue(row.label.contains("Hidden"), row.label)
        XCTAssertFalse(row.label.contains("0.5°"), row.label)
        try audit(app, afterScrolling: true, checksDynamicType: false)
        show.tap()
        XCTAssertTrue(element(app, containing: "0.5°").waitForExistence(timeout: 5))
        XCTAssertFalse(show.exists)
        // Closed and opened again: hidden again. Done returns to the Last Photo viewer, Close to
        // the camera, and the thumbnail opens the viewer again.
        app.buttons["Done"].tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.buttons["Last Photo"].waitForExistence(timeout: 5))
        app.buttons["Last Photo"].tap()
        let details = app.buttons["Photo Details"]
        XCTAssertTrue(details.waitForExistence(timeout: 15))
        details.tap()
        XCTAssertTrue(scrollDetails(app, to: app.buttons["Show Value, Location"]))
        XCTAssertFalse(element(app, containing: "0.5°").exists)
        app.terminate()

        // Location on, with nothing to write.
        let empty = launch(
            "manual",
            extraArguments: Self.detailsSettings(formats: ["raw"], items: ["location"], signs: false)
                + ["-NopeSimulatedFileTags", "fullNoLocation"])
        openPhotoDetails(empty)
        XCTAssertTrue(scrollDetails(empty, to: element(empty, containing: "Location, On, but there was nothing to write")))
        XCTAssertFalse(empty.buttons["Show Value, Location"].exists)
        empty.terminate()

        // Location off.
        let off = launch("manual")
        openPhotoDetails(off)
        XCTAssertTrue(scrollDetails(off, to: element(off, containing: "Location, Off in Settings")))
    }

    @MainActor
    func testDetailsEveryTagPage() throws {
        let app = launch("manual", extraArguments: Self.detailsKept)
        openPhotoDetails(app)
        let raw = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "RAW (DNG), ")).firstMatch
        XCTAssertTrue(scrollDetails(app, to: raw))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "HEIF, ")).firstMatch.exists)
        raw.tap()
        XCTAssertTrue(app.navigationBars["RAW (DNG)"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "as nope. read them back").exists)
        for group in ["TIFF", "EXIF", "DNG"] {
            XCTAssertTrue(disclosureRow(app, group).exists, group)
        }
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        disclosureRow(app, "EXIF").tap()
        let exposureTime = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "ExposureTime")).firstMatch
        XCTAssertTrue(exposureTime.waitForExistence(timeout: 5))
        XCTAssertTrue((exposureTime.value as? String)?.contains("Exposure Settings") == true)
        // Search filters by name and opens the groups that match; Cancel clears it.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("DNGVersion")
        let version = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "DNGVersion")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        XCTAssertFalse(exposureTime.exists)
        // No audit while searching: the system search field's Clear Text button is 20 points,
        // a finding on the system control, not on this page.
        let cancel = app.buttons["Cancel"]
        if cancel.exists { cancel.tap() } else { search.buttons.firstMatch.tap() }
        XCTAssertTrue(exposureTime.waitForExistence(timeout: 5))
    }

    @MainActor
    func testDetailsEveryTagShowsHiddenValues() throws {
        let app = launch("manual", extraArguments: Self.locationKept)
        openPhotoDetails(app)
        let raw = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "RAW (DNG), ")).firstMatch
        XCTAssertTrue(scrollDetails(app, to: raw))
        raw.tap()
        let gps = disclosureRow(app, "GPS")
        XCTAssertTrue(gps.waitForExistence(timeout: 5))
        gps.tap()
        let latitude = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "GPSLatitude")).firstMatch
        XCTAssertTrue(scrollDetails(app, to: latitude))
        XCTAssertTrue((latitude.value as? String)?.hasPrefix("Hidden") == true)
        let show = app.buttons["Show Hidden Values"]
        XCTAssertTrue(scrollDetails(app, to: show))
        try audit(app, afterScrolling: true, checksDynamicType: false)
        show.tap()
        XCTAssertFalse(show.waitForExistence(timeout: 2))
        XCTAssertFalse((latitude.value as? String)?.hasPrefix("Hidden") == true)
    }

    /// The app leaves the screen with a location shown: when it returns the value is hidden
    /// again and the cover is gone. (The cover itself is drawn while the scene isn't active, when
    /// the app's elements can't be queried; `docs/TESTING.md` lists it as a device check.)
    @MainActor
    func testDetailsHiddenInAppSwitcher() throws {
        let app = launch("manual", extraArguments: Self.locationKept)
        openPhotoDetails(app)
        let show = app.buttons["Show Value, Location"]
        XCTAssertTrue(scrollDetails(app, to: show))
        show.tap()
        XCTAssertTrue(element(app, containing: "0.5°").waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["PhotoDetails.cover"].waitForExistence(timeout: 2))
        if app.navigationBars["What's in This Photo"].waitForExistence(timeout: 5) {
            XCTAssertTrue(scrollDetails(app, to: app.buttons["Show Value, Location"]))
            XCTAssertFalse(element(app, containing: "0.5°").exists)
        }
    }

    @MainActor
    func testDetailsLargestText() throws {
        let app = launch("signingFails", extraArguments: Self.largestTextSize + Self.detailsKept)
        openPhotoDetails(app)
        // The rows wrap under their own first word, and nothing is cut (the audit).
        checkSummary(
            app, head: ["RAW (DNG) and HEIF"],
            rows: [
                "RAW: one frame of sensor data, and a HEIF copy developed by nope.",
                "Warning, Not signed, The signature couldn't be made", "5 optional details in the files", "No location in the files",
            ])
        try audit(app)
        XCTAssertTrue(scrollDetails(app, to: element(app, containing: "Standard File Tags")))
        try audit(app, afterScrolling: true)
        XCTAssertTrue(scrollDetails(app, to: app.buttons["Open in Photos"]))
        try audit(app, afterScrolling: true)
    }

    @MainActor
    func testDetailsRightToLeft() throws {
        let app = launch("manual", extraArguments: Self.rightToLeft + Self.detailsKept)
        openPhotoDetails(app)
        checkSummary(
            app, head: ["RAW (DNG) and HEIF"],
            rows: [
                "RAW: one frame of sensor data, and a HEIF copy developed by nope.", "Signed", "5 optional details in the files",
                "No location in the files",
            ])
        // Right to left the rows' words end on the right, where the symbol column is.
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(summaryRow(app, "signature").frame.maxX, window.midX)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        XCTAssertTrue(scrollDetails(app, to: disclosureRow(app, "In the Files")))
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
        app.terminate()
        // A processed photo right to left.
        let processed = launch("noRAW", extraArguments: Self.rightToLeft)
        openPhotoDetails(processed)
        XCTAssertEqual(
            summaryRow(processed, "kind").label,
            deviceText(
                "Warning, Processed by this iPhone, This lens can't save RAW",
                iPad: "Warning, Processed by this iPad, This lens can't save RAW"))
        try audit(processed, checksDynamicType: false, checksContrast: !isPad)
        XCTAssertTrue(scrollDetails(processed, to: element(processed, containing: "nope. didn't change this file's picture.")))
        try audit(processed, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testDetailsNightModeIsAllRed() throws {
        let app = launch("signingFails", extraArguments: Self.signingOn + Self.nightModeOn)
        openPhotoDetails(app)
        settle()
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0, "white, blue or other colors remain in What's in This Photo")
        try audit(app, checksDynamicType: false)
        XCTAssertTrue(scrollDetails(app, to: element(app, containing: "couldn't create the signature for this photo")))
        settle()
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0, "white, blue or other colors remain after scrolling")
    }

    @MainActor
    func testDetailsSideways() throws {
        let app = launch("manual", extraArguments: Self.detailsKept)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        openPhotoDetails(app)
        XCTAssertTrue(element(app, containing: "RAW (DNG) and HEIF").waitForExistence(timeout: 5))
        // Sideways the sheet turns with the device; only its first screen is audited, since a
        // swipe in the portrait-held test runner doesn't scroll the turned list.
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testDetailsOnIPad() throws {
        guard isPad else { throw XCTSkip("The centered sheet is iPad only.") }
        let app = launch("manual", extraArguments: Self.detailsKept)
        openPhotoDetails(app)
        let summary = app.descendants(matching: .any)["PhotoDetails.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        // A centered sheet, narrower than the window. The page-sized sheet (3.11) leaves only a
        // narrow margin in portrait on an 11-inch iPad (780 of 820 points), so the test checks
        // that it is narrower and centered rather than a fixed share of the width.
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(summary.frame.width, window.width)
        XCTAssertEqual(summary.frame.midX, window.midX, accuracy: 2)
        try audit(app, checksDynamicType: false, checksContrast: false)
        let raw = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "RAW (DNG), ")).firstMatch
        XCTAssertTrue(scrollDetails(app, to: raw))
        raw.tap()
        XCTAssertTrue(app.navigationBars["RAW (DNG)"].waitForExistence(timeout: 5))
        try audit(app, checksDynamicType: false, checksContrast: false)
    }
}
