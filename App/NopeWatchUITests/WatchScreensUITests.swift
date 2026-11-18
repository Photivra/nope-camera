import XCTest

/// UI tests for the states of the watch screen in the 1.0.0 design (docs/design/watch.html,
/// BUILD-SPEC.md 3.13): every status and result, the unsigned result when signing is off by
/// choice, the largest text size, right to left and German. Each state is audited. Run them on
/// the 40 mm and the 46 mm Simulators; the phone is simulated (`-NopeSimulatedPhone`).
extension NopeWatchUITests {
    /// The launch arguments for right-to-left layout.
    static let rightToLeft = ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]

    /// The launch arguments for German, the longest launch language.
    static let german = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]

    /// The shortest height of Take Photo and Cancel Timer, in points (docs/design/watch.html).
    static let buttonMinHeight: CGFloat = 56

    /// Takes a photo in a scenario and returns the app once the result shows.
    ///
    /// - Parameters:
    ///   - scenario: The simulated phone's scenario.
    ///   - extraArguments: More launch arguments.
    /// - Returns: The running app.
    @MainActor
    func takePhoto(in scenario: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = launch(scenario, extraArguments: extraArguments)
        let shutter = app.buttons["WatchShutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntilEnabled(shutter))
        shutter.tap()
        return app
    }

    /// Waits until an element is enabled.
    ///
    /// - Parameter element: The element.
    /// - Returns: Whether it became enabled within 10 seconds.
    @MainActor
    func waitUntilEnabled(_ element: XCUIElement) -> Bool {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        return XCTWaiter().wait(for: [enabled], timeout: 10) == .completed
    }

    /// Checks the result line's words and audits the screen, with a screenshot for review.
    ///
    /// - Parameters:
    ///   - expected: The words of the result.
    ///   - app: The running app.
    ///   - name: The screenshot's name: the figure in docs/design/screens.
    @MainActor
    func expectResult(_ expected: String, in app: XCUIApplication, figure name: String) throws {
        XCTAssertTrue(result(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(result(in: app).label, expected)
        attachScreenshot(of: app, named: name)
        try audit(app)
    }

    /// Keeps a screenshot of the screen in the test results, to compare with the design.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - name: The figure's name.
    @MainActor
    func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls until an element can be tapped.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - app: The running app.
    @MainActor
    func scroll(to element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) is reached by scrolling")
    }

    // MARK: Results

    @MainActor
    func testSavedNotSignedWithSigningOffIsPlainStatus() throws {
        let app = takePhoto(in: "notSignedByChoice")
        try expectResult("Saved, not signed", in: app, figure: "watch-saved")
        XCTAssertTrue(app.buttons["WatchShutter"].isEnabled)
    }

    @MainActor
    func testSavedNotSignedWithoutAReasonKeepsTheWarning() throws {
        let app = takePhoto(in: "notSignedNoReason")
        try expectResult("Saved, not signed", in: app, figure: "watch-saved-no-reason")
    }

    @MainActor
    func testSeveralPhotosSavedAndSigned() throws {
        let app = takePhoto(in: "severalSigned")
        try expectResult("Photos saved and signed", in: app, figure: "watch-several-signed")
    }

    @MainActor
    func testSeveralPhotosSavedNotAllSigned() throws {
        let app = takePhoto(in: "severalNotSigned")
        try expectResult("Photos saved, not all signed", in: app, figure: "watch-several-unsigned")
        app.terminate()
        let byChoice = takePhoto(in: "severalNotSignedByChoice")
        try expectResult("Photos saved, not all signed", in: byChoice, figure: "watch-several-unsigned-by-choice")
    }

    @MainActor
    func testAPhotoNotSavedPointsToThePhone() throws {
        let app = takePhoto(in: "notSaved")
        try expectResult("Not saved. Your phone shows why.", in: app, figure: "watch-failed")
    }

    @MainActor
    func testABusyPhoneTakesNothing() throws {
        let app = takePhoto(in: "busy")
        try expectResult("The camera was busy. No photo taken.", in: app, figure: "watch-busy")
        XCTAssertTrue(waitUntilEnabled(app.buttons["WatchShutter"]), "the shutter is back")
    }

    @MainActor
    func testDifferentVersionsAskForAnUpdate() throws {
        let app = takePhoto(in: "otherVersion")
        try expectResult("Update nope. on your phone and watch.", in: app, figure: "watch-update")
    }

    @MainActor
    func testNoPhotoTakenWhenTheCameraStops() throws {
        let app = takePhoto(in: "becomesUnavailable")
        try expectResult("No photo taken.", in: app, figure: "watch-not-taken")
        XCTAssertEqual(status(in: app).label, "Camera not available. Open nope. on your phone.")
        XCTAssertFalse(app.buttons["WatchShutter"].isEnabled)
    }

    // MARK: Statuses

    @MainActor
    func testTakingThePhotoDisablesTheShutter() throws {
        let app = takePhoto(in: "taking")
        let taking = NSPredicate(format: "label == %@", "Taking photo…")
        XCTAssertTrue(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: taking, object: status(in: app))], timeout: 10)
                == .completed)
        XCTAssertFalse(app.buttons["WatchShutter"].isEnabled)
        attachScreenshot(of: app, named: "watch-taking")
        try audit(app)
    }

    @MainActor
    func testConnectingDisablesTheShutter() throws {
        let app = launch("connecting")
        XCTAssertTrue(status(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(status(in: app).label, "Connecting to your phone…")
        XCTAssertFalse(app.buttons["WatchShutter"].isEnabled)
        attachScreenshot(of: app, named: "watch-connecting")
        try audit(app)
    }

    @MainActor
    func testEveryCameraUnavailableMessage() throws {
        let messages = [
            ("needsPermission", "Open nope. on your phone to allow camera access.", "watch-no-access"),
            ("noCamera", "Your phone has no camera nope. can use.", "watch-no-camera"),
        ]
        for (scenario, message, figure) in messages {
            let app = launch(scenario)
            XCTAssertTrue(status(in: app).waitForExistence(timeout: 10))
            XCTAssertEqual(status(in: app).label, message)
            XCTAssertFalse(app.buttons["WatchShutter"].isEnabled)
            attachScreenshot(of: app, named: figure)
            try audit(app)
            app.terminate()
        }
    }

    @MainActor
    func testTheButtonsKeepTheirMinimumHeight() throws {
        let app = launch("countdown")
        let cancel = app.buttons["WatchCancelTimer"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(cancel.frame.height, Self.buttonMinHeight)
        attachScreenshot(of: app, named: "watch-countdown")
        app.terminate()
        let ready = launch("ready")
        let shutter = ready.buttons["WatchShutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(shutter.frame.height, Self.buttonMinHeight)
        attachScreenshot(of: ready, named: "watch-ready")
    }

    // MARK: Largest text size, right to left, German

    @MainActor
    func testTheLargestTextSizeScrollsToEveryControl() throws {
        let app = launch("unreachable", extraArguments: Self.largestTextSize)
        XCTAssertTrue(status(in: app).waitForExistence(timeout: 10))
        attachScreenshot(of: app, named: "watch-largest-warning")
        try audit(app)
        scroll(to: app.buttons["WatchDelay"], in: app)
        try audit(app)
        app.terminate()

        let countdown = launch("countdown", extraArguments: Self.largestTextSize)
        XCTAssertTrue(status(in: countdown).waitForExistence(timeout: 10))
        attachScreenshot(of: countdown, named: "watch-largest-countdown")
        try audit(countdown)
        scroll(to: countdown.buttons["WatchCancelTimer"], in: countdown)
        scroll(to: countdown.buttons["WatchDelay"], in: countdown)
        try audit(countdown)
    }

    @MainActor
    func testTheDelayListAtTheLargestTextSize() throws {
        let app = launch("ready", extraArguments: Self.largestTextSize)
        let delay = app.buttons["WatchDelay"]
        XCTAssertTrue(delay.waitForExistence(timeout: 10))
        scroll(to: delay, in: app)
        delay.tap()
        let tenSeconds = app.buttons["10 seconds"]
        XCTAssertTrue(tenSeconds.waitForExistence(timeout: 10))
        attachScreenshot(of: app, named: "watch-largest-delay")
        try audit(app)
        scroll(to: tenSeconds, in: app)
    }

    @MainActor
    func testRightToLeft() throws {
        let app = takePhoto(in: "notSignedByChoice", extraArguments: Self.rightToLeft)
        try expectResult("Saved, not signed", in: app, figure: "watch-rtl")
        let delay = app.buttons["WatchDelay"]
        scroll(to: delay, in: app)
        delay.tap()
        XCTAssertTrue(app.buttons["3 seconds"].waitForExistence(timeout: 10))
        attachScreenshot(of: app, named: "watch-rtl-delay")
        try audit(app)
    }

    @MainActor
    func testGerman() throws {
        let app = launch("unreachable", extraArguments: Self.german)
        XCTAssertTrue(status(in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(
            status(in: app).label, "Dein Telefon ist nicht erreichbar. Halte es in der Nähe und lass nope. geöffnet.")
        attachScreenshot(of: app, named: "watch-german-warning")
        try audit(app)
        app.terminate()

        let ready = launch("ready", extraArguments: Self.german)
        let shutter = ready.buttons["WatchShutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertEqual(shutter.label, "Foto aufnehmen")
        XCTAssertGreaterThanOrEqual(shutter.frame.height, Self.buttonMinHeight)
        attachScreenshot(of: ready, named: "watch-german")
        try audit(ready)
        let delay = ready.buttons["WatchDelay"]
        scroll(to: delay, in: ready)
        delay.tap()
        XCTAssertTrue(ready.buttons["3 Sekunden"].waitForExistence(timeout: 10))
        attachScreenshot(of: ready, named: "watch-german-delay")
        try audit(ready)
    }
}
