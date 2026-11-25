import XCTest

/// UI tests for the Rate or Review row, the last section of About and Licenses
/// (`docs/store/STORE-PAGE-PLAN.md`, section 12): hidden while the app has no App Store ID, and,
/// with one (`-NopeSimulatedAppStoreID`, Debug builds only), a plain link with its header and
/// footer, found by search, audited at the default and largest text sizes, right to left and in
/// night mode. The tests never tap the link: the Simulator has no App Store, and opening it is a
/// device check (`docs/TESTING.md`). XCUITest can't read an element's VoiceOver hint, so the
/// hint ("Opens the App Store.") is checked on the manual VoiceOver pass.
extension NopeAppUITests {
    /// An App Store ID for the tests: any digits make the row show.
    static let testAppStoreID = ["-NopeSimulatedAppStoreID", "1234567890"]

    /// Launch arguments that simulate an app with no App Store ID (the real one is set).
    static let noAppStoreID = ["-NopeSimulatedAppStoreID", "none"]

    /// The row's identifier (`SettingsID.rateOrReview`).
    static let rateOrReviewRow = "settings.about.rateOrReview"

    /// The footer under the row.
    static let rateOrReviewFooter = "Opens the App Store. Ratings and reviews there are public."

    /// Launches the app with the "denied" scenario and the arguments, and opens About and
    /// Licenses.
    @MainActor
    func openAbout(_ arguments: [String]) -> XCUIApplication {
        let app = launch("denied", extraArguments: arguments)
        openSettings(app)
        open(app, row: "About and Licenses")
        XCTAssertTrue(app.navigationBars["About and Licenses"].waitForExistence(timeout: 5))
        return app
    }

    /// The source code link, by its VoiceOver name, whatever element type it is reported as.
    @MainActor
    func sourceCodeLink(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Source code address")).firstMatch
    }

    @MainActor
    func testRateOrReviewIsHiddenWithoutAnAppStoreID() throws {
        let app = openAbout(Self.noAppStoreID)
        scrollToTheEndOfTheSettingsPage(app)
        XCTAssertTrue(sourceCodeLink(app).exists, "the page's end is on screen")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: Self.rateOrReviewRow).firstMatch.exists)
        XCTAssertFalse(element(app, containing: Self.rateOrReviewFooter).exists)
        XCTAssertFalse(app.staticTexts["App Store"].exists)
        // Search doesn't list a row that isn't there.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        searchSettings(app, for: "review")
        XCTAssertFalse(app.buttons["settings.search." + Self.rateOrReviewRow].waitForExistence(timeout: 2))
    }

    @MainActor
    func testRateOrReviewIsALinkLastOnAbout() throws {
        let app = openAbout(Self.testAppStoreID)
        let row = settingsElement(app, Self.rateOrReviewRow)
        XCTAssertTrue(row.exists)
        // A link, not a button, on every device and OS: the row adds the link trait and removes
        // the button trait iOS 26 reports for a `Link` in a `Form`.
        XCTAssertEqual(row.elementType, .link, "\(row.elementType.rawValue)")
        XCTAssertEqual(row.label, "Rate or Review")
        // No value: the address tells a listener nothing the hint doesn't.
        XCTAssertTrue((row.value as? String ?? "").isEmpty)
        XCTAssertTrue(app.staticTexts["App Store"].exists)
        XCTAssertTrue(element(app, containing: Self.rateOrReviewFooter).exists)
        // Last: below the source code link.
        let source = sourceCodeLink(app)
        XCTAssertTrue(source.exists, "the source code link is on screen with the row")
        XCTAssertLessThan(source.frame.minY, row.frame.minY)
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testSettingsSearchFindsRateOrReview() throws {
        for word in ["rating", "feedback"] {
            let app = launch("denied", extraArguments: Self.testAppStoreID)
            openSettingsScreen(app)
            searchSettings(app, for: word)
            let result = app.buttons["settings.search." + Self.rateOrReviewRow]
            XCTAssertTrue(result.waitForExistence(timeout: 5), word)
            result.tap()
            XCTAssertTrue(app.navigationBars["About and Licenses"].waitForExistence(timeout: 5), word)
            let row = app.descendants(matching: .any).matching(identifier: Self.rateOrReviewRow).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), word)
        }
    }

    @MainActor
    func testRateOrReviewAtTheLargestTextSize() throws {
        let app = openAbout(Self.testAppStoreID + Self.largestTextSize)
        let row = settingsElement(app, Self.rateOrReviewRow)
        XCTAssertTrue(row.exists)
        XCTAssertEqual(row.label, "Rate or Review")
        scrollToTheEndOfTheSettingsPage(app)
        XCTAssertTrue(element(app, containing: Self.rateOrReviewFooter).exists)
        // The audit's Dynamic Type and clipped-text checks cover the row and the footer.
        try audit(app, afterScrolling: true, checksContrast: !isPad)
    }

    @MainActor
    func testRateOrReviewRightToLeft() throws {
        let app = openAbout(Self.testAppStoreID + Self.rightToLeft)
        let row = settingsElement(app, Self.rateOrReviewRow)
        XCTAssertTrue(row.exists)
        // The row's element spans the list in both directions, so the drawn text is checked:
        // "Rate or Review" is all in the right half of the row, none in the left half.
        let frame = row.frame
        let (left, right) = frame.divided(atDistance: frame.width / 2, from: .minXEdge)
        let paper = CGPoint(x: frame.midX, y: frame.minY + 3)
        let leftInk = inkPixels(app, in: left, background: paper)
        let rightInk = inkPixels(app, in: right, background: paper)
        XCTAssertGreaterThan(rightInk, 0, "no link text in the row's right half")
        XCTAssertEqual(leftInk, 0, "link text in the row's left half")
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testRateOrReviewInNightModeIsAllRed() throws {
        let app = openAbout(Self.testAppStoreID + Self.nightModeOn)
        let row = settingsElement(app, Self.rateOrReviewRow)
        XCTAssertTrue(row.exists)
        settle()
        // The back button is the system's glass, outside night mode's reach on every pushed
        // Settings page; the iPad window corner is left out by the count.
        let back = app.navigationBars.buttons.element(boundBy: 0).frame.insetBy(dx: -6, dy: -6)
        let pixels = nonRedPixels(app, outside: back)
        if pixels != 0 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "About, Rate or Review, night mode"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertEqual(pixels, 0, "white, blue or other colors remain on About")
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }
}
