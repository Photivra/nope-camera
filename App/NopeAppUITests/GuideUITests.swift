import XCTest

/// UI tests for the how-to-use guide (issue #117; `docs/design/finish-1.0.md`, section 2): the
/// invitation card on the camera and its two buttons, a photo taken while it shows, every page
/// of the guide, both links, the How to Use nope. rows in Settings and About, search, and the
/// card and guide at the largest text size, right to left and in night mode. Each state is
/// audited.
///
/// The UI tests' settings store starts with the invitation answered, so the card doesn't change
/// the camera of the other tests; these tests pass `-NopeSimulatedGuideCard` to see it. The
/// store is emptied at every launch, so that Dismiss lasts across launches and Factory Defaults
/// is checked by the unit tests (`GuideInvitationTests`). XCUITest can't read VoiceOver hints or
/// announcements; they are checked on the manual VoiceOver pass (`docs/TESTING.md`).
extension NopeAppUITests {
    /// The launch argument that shows the invitation card.
    static let guideCard = ["-NopeSimulatedGuideCard"]

    /// The guide's page titles, in order.
    static let guideTitles = [
        "Take a photo", "Photos as the camera took them", "Private by design", "Lenses", "Auto and manual",
        "One photo or a series", "Q and Settings",
    ]

    /// Whether an audit issue is the text drawn in a guide page's picture: the camera's own
    /// controls (the drive words, Auto, a lens's magnification), shown as decoration and hidden
    /// from VoiceOver by design (`docs/design/finish-1.0.md`, 2.2), so the audit finds text with
    /// no element ("Potentially inaccessible text"). Only while the guide is open, and only a
    /// finding without an element: every text of the page itself is an element and is audited.
    @MainActor
    static func isGuidePictureText(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        issue.element == nil && issue.compactDescription.localizedCaseInsensitiveContains("inaccessible text")
            && app.buttons["guide.close"].exists
    }

    /// The invitation card.
    @MainActor
    func guideCard(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "GuideCard").firstMatch
    }

    /// Launches the camera with the invitation card and passes the first-run screen.
    @MainActor
    func launchWithGuideCard(_ arguments: [String] = []) -> XCUIApplication {
        let app = launch("allow", extraArguments: Self.guideCard + arguments)
        continuePastFirstRun(app)
        XCTAssertTrue(guideCard(app).waitForExistence(timeout: 10), "no invitation card")
        return app
    }

    /// Opens the guide from the card and waits for its first page.
    @MainActor
    func openGuideFromCard(_ app: XCUIApplication) {
        let open = app.buttons["guideCard.open"]
        scrollUntilHittable(app, open)
        open.tap()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[0]), "the guide didn't open at its first page")
    }

    /// Waits up to five seconds for the guide to show a page title.
    @MainActor
    func guideTitle(_ app: XCUIApplication, is title: String) -> Bool {
        let element = app.staticTexts.matching(identifier: "guide.title").firstMatch
        return waitUntil(timeout: .seconds(5)) { element.exists && element.label == title }
    }

    /// Keeps a screenshot with the test's results, for the guide's figures
    /// (`docs/design/screens/guide-*`).
    ///
    /// - Parameters:
    ///   - app: The app.
    ///   - name: The figure's name, such as "guide-page-2".
    @MainActor
    func keepGuideScreenshot(_ app: XCUIApplication, _ name: String) {
        settle()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Whether the guide's sheet is gone, within five seconds.
    @MainActor
    func guideIsClosed(_ app: XCUIApplication) -> Bool {
        let guide = app.buttons["guide.close"]
        return waitUntil(timeout: .seconds(5)) { !guide.exists }
    }

    @MainActor
    func testGuideCardShowsOnTheCameraWithoutBlockingTheShutter() throws {
        let app = launchWithGuideCard()
        let card = guideCard(app)
        XCTAssertTrue(app.staticTexts["How to use nope."].exists)
        let open = app.buttons["guideCard.open"]
        let dismiss = app.buttons["guideCard.dismiss"]
        XCTAssertEqual(open.label, "Open")
        XCTAssertEqual(dismiss.label, "Dismiss")
        // Both are 44-point targets.
        XCTAssertGreaterThanOrEqual(open.frame.height, 44)
        XCTAssertGreaterThanOrEqual(dismiss.frame.width, 44)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)
        // On the picture, never over the shutter, the lens row or the drive strip.
        let shutter = app.buttons["Take Photo"]
        XCTAssertFalse(card.frame.intersects(shutter.frame), "the card covers the shutter")
        XCTAssertFalse(card.frame.intersects(app.buttons["ManualControlsButton"].frame), "the card covers Auto")
        XCTAssertTrue(card.frame.maxY <= app.otherElements["Viewfinder"].frame.maxY + 1, "the card isn't on the picture")
        keepGuideScreenshot(app, "guide-invite")
        try audit(app)
        // A photo is taken while the card shows, and the card stays.
        shutter.tap()
        XCTAssertTrue(lastPhoto(app, says: "Saved."))
        XCTAssertTrue(card.exists, "taking a photo put the card away")
    }

    @MainActor
    func testGuideCardDismissIsFinal() throws {
        let app = launchWithGuideCard()
        app.buttons["guideCard.dismiss"].tap()
        XCTAssertTrue(waitUntil(timeout: .seconds(5)) { !self.guideCard(app).exists }, "Dismiss left the card")
        // It doesn't come back after Settings, nor after a photo.
        openSettings(app)
        app.buttons["Done"].tap()
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(lastPhoto(app, says: "Saved."))
        XCTAssertFalse(guideCard(app).exists)
    }

    @MainActor
    func testGuideCardGivesWayToADriveCard() throws {
        let app = launchWithGuideCard()
        chooseDrive(app, "Burst")
        XCTAssertTrue(waitUntil(timeout: .seconds(5)) { !self.guideCard(app).exists }, "the card shows with Burst's card")
        chooseDrive(app, "Single")
        XCTAssertTrue(guideCard(app).waitForExistence(timeout: 5), "the card didn't come back")
    }

    @MainActor
    func testGuideCardIsHiddenInCleanView() throws {
        let app = launchWithGuideCard()
        quickControl(app, "Hide Controls")
        XCTAssertTrue(waitUntil(timeout: .seconds(5)) { !self.guideCard(app).exists }, "the card shows in clean view")
        app.buttons["Show Controls"].tap()
        XCTAssertTrue(guideCard(app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testGuideHasSevenPagesAndOpenAnswersTheCard() throws {
        let app = launchWithGuideCard()
        openGuideFromCard(app)
        let number = app.staticTexts["guide.pageNumber"]
        XCTAssertFalse(app.buttons["guide.back"].exists, "Back on the first page")
        for (index, title) in Self.guideTitles.enumerated() {
            XCTAssertTrue(guideTitle(app, is: title), "page \(index + 1) isn't \(title)")
            XCTAssertEqual(number.label, "Page \(index + 1) of 7")
            XCTAssertEqual(app.buttons["guide.link"].exists, index == 1 || index == 2, "page \(index + 1)'s link")
            keepGuideScreenshot(app, "guide-page-\(index + 1)")
            try audit(app)
            if index < Self.guideTitles.count - 1 {
                app.buttons["guide.next"].tap()
            }
        }
        // Back goes back; Done on the last page closes the guide.
        app.buttons["guide.back"].tap()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[5]))
        app.buttons["guide.next"].tap()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[6]))
        XCTAssertEqual(app.buttons["guide.done"].label, "Done")
        app.buttons["guide.done"].tap()
        XCTAssertTrue(guideIsClosed(app))
        // Opening the guide answered the invitation.
        XCTAssertFalse(guideCard(app).exists)
        XCTAssertTrue(app.buttons["Take Photo"].isHittable)
    }

    @MainActor
    func testGuideSwipesBetweenPagesAndCloses() throws {
        let app = launchWithGuideCard()
        openGuideFromCard(app)
        app.staticTexts["guide.title"].swipeLeft()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[1]), "a swipe toward the leading edge didn't go forward")
        app.staticTexts["guide.title"].swipeRight()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[0]), "a swipe toward the trailing edge didn't go back")
        app.buttons["guide.close"].tap()
        XCTAssertTrue(guideIsClosed(app))
        XCTAssertFalse(guideCard(app).exists)
    }

    @MainActor
    func testGuideLinksOpenSettingsAtTheirPages() throws {
        let app = launchWithGuideCard()
        openGuideFromCard(app)
        app.buttons["guide.next"].tap()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[1]))
        let processing = app.buttons["guide.link"]
        XCTAssertTrue(processing.label.hasPrefix("About processing"), processing.label)
        processing.tap()
        XCTAssertTrue(app.navigationBars["Honesty"].waitForExistence(timeout: 10), "About processing didn't open Honesty")
        XCTAssertFalse(app.buttons["guide.close"].exists)
        // From Settings, the second link opens Details in Each Photo inside Settings.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let row = settingsElement(app, "settings.howToUse")
        row.tap()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[0]))
        app.buttons["guide.next"].tap()
        app.buttons["guide.next"].tap()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[2]))
        app.buttons["guide.link"].tap()
        XCTAssertTrue(app.navigationBars["Details in Each Photo"].waitForExistence(timeout: 10), "the link didn't open Details in Each Photo")
    }

    @MainActor
    func testGuideOpensFromSettingsAndAbout() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        let row = settingsElement(app, "settings.howToUse")
        XCTAssertTrue(row.exists)
        XCTAssertEqual(row.label, "How to Use nope.")
        // First in More.
        let accessibility = settingsElement(app, "settings.accessibility")
        XCTAssertLessThan(row.frame.minY, accessibility.frame.minY)
        keepGuideScreenshot(app, "guide-settings-row")
        // Dynamic Type is audited on the Settings list by the Settings tests at the largest size.
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
        row.tap()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[0]))
        XCTAssertEqual(app.staticTexts["guide.pageNumber"].label, "Page 1 of 7")
        try audit(app)
        app.buttons["guide.close"].tap()
        XCTAssertTrue(guideIsClosed(app))
        XCTAssertTrue(app.navigationBars["Settings"].exists, "closing the guide closed Settings")
        open(app, row: "About and Licenses")
        XCTAssertTrue(app.navigationBars["About and Licenses"].waitForExistence(timeout: 5))
        let about = settingsElement(app, "settings.about.howToUse")
        XCTAssertEqual(about.label, "How to Use nope.")
        try audit(app, checksContrast: !isPad)
        about.tap()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[0]), "About's row didn't open the guide at page 1")
        app.buttons["guide.close"].tap()
        XCTAssertTrue(guideIsClosed(app))
        XCTAssertTrue(app.navigationBars["About and Licenses"].exists)
    }

    @MainActor
    func testSettingsSearchFindsHowToUse() throws {
        for word in ["help", "tutorial"] {
            let app = launch("denied")
            openSettingsScreen(app)
            searchSettings(app, for: word)
            let result = app.buttons["settings.search.settings.howToUse"]
            XCTAssertTrue(result.waitForExistence(timeout: 5), word)
            XCTAssertTrue(result.label.hasPrefix("How to Use nope."), result.label)
            result.tap()
            let row = app.descendants(matching: .any).matching(identifier: "settings.howToUse").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), word)
            app.terminate()
        }
    }

    @MainActor
    func testGuideAtTheLargestTextSize() throws {
        let app = launchWithGuideCard(Self.largestTextSize)
        try auditVisibleElements(app)
        openGuideFromCard(app)
        // The page scrolls; Back, the page number and Next stay in reach.
        for index in 0..<Self.guideTitles.count {
            XCTAssertTrue(guideTitle(app, is: Self.guideTitles[index]))
            let forward = app.buttons[index == Self.guideTitles.count - 1 ? "guide.done" : "guide.next"]
            XCTAssertTrue(forward.isHittable, "page \(index + 1)'s Next is out of reach")
            if index == 1 { keepGuideScreenshot(app, "guide-page-largest") }
            try audit(app, afterScrolling: true)
            if index < Self.guideTitles.count - 1 { forward.tap() }
        }
    }

    @MainActor
    func testGuideRightToLeft() throws {
        let app = launchWithGuideCard(Self.rightToLeft)
        try audit(app)
        openGuideFromCard(app)
        app.buttons["guide.next"].tap()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[1]))
        // Back and Next swap sides.
        XCTAssertGreaterThan(app.buttons["guide.back"].frame.minX, app.buttons["guide.next"].frame.maxX, "Back isn't on the right")
        try audit(app)
        // A swipe toward the leading edge (the right) goes forward.
        app.staticTexts["guide.title"].swipeRight()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[2]), "a right-to-left swipe didn't go forward")
        app.staticTexts["guide.title"].swipeLeft()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[1]), "a right-to-left swipe didn't go back")
    }

    @MainActor
    func testGuideInNightModeIsAllRed() throws {
        let app = launchWithGuideCard(Self.nightModeOn)
        settle()
        let viewfinder = app.otherElements["Viewfinder"].frame
        XCTAssertEqual(nonRedPixels(app, outside: viewfinder), 0, "the camera with the card isn't all red")
        keepGuideScreenshot(app, "guide-invite-night")
        try audit(app)
        openGuideFromCard(app)
        app.buttons["guide.next"].tap()
        XCTAssertTrue(guideTitle(app, is: Self.guideTitles[1]))
        settle()
        // The bar's Close is the system's glass, outside night mode's reach, as on every sheet.
        let close = app.buttons["guide.close"].frame.insetBy(dx: -6, dy: -6)
        let pixels = nonRedPixels(app, outside: close)
        if pixels != 0 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Guide, night mode"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertEqual(pixels, 0, "the guide isn't all red")
        keepGuideScreenshot(app, "guide-page-night")
        try audit(app)
    }
}
