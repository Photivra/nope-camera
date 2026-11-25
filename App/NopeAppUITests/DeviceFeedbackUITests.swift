import XCTest

/// UI tests for the device feedback of 1.0.0 (docs/design/device-feedback-1.0.md): Open Photos
/// in the Last Photo spot, the Honesty entries and About Close-Up Focus, the close-up hint after
/// a realistic sweep, the steady hint with Manual Controls, and the fade of the focus square and
/// Lock. Use the Whole Range is in FocusBracketUITests.
extension NopeAppUITests {
    /// The launch argument that makes the app behave as with VoiceOver or Switch Control on.
    static let assistiveTechnologyOn = ["-NopeSimulatedAssistiveTechnology"]

    /// Open Photos, in the Last Photo spot.
    @MainActor
    private func openPhotos(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["openPhotos"]
    }

    /// The Honesty entry Lenses Never Switch on Their Own.
    @MainActor
    private func closeUpEntry(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["settings.honesty.closeUpFocus"]
    }

    /// Waits until the camera can take a photo.
    @MainActor
    private func waitForTheShutter(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Take Photo"])
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 30), .completed, "the camera didn't start", file: file, line: line)
    }

    // MARK: - 1. Open Photos

    /// Before the first photo the spot holds Open Photos, with its name and hint; pressing it
    /// brings Photos to the front. After a photo, Last Photo has the spot; a new launch shows
    /// Open Photos again.
    @MainActor
    func testOpenPhotosBeforeTheFirstPhoto() throws {
        var app = launch("slowSaving")
        let button = openPhotos(app)
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        XCTAssertEqual(button.label, "Open Photos")
        XCTAssertFalse(app.descendants(matching: .any)["Last Photo"].exists)
        try audit(app)
        waitForTheShutter(app)
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(lastPhoto(app, says: "Saved", timeout: 20))
        XCTAssertFalse(button.exists, "Open Photos doesn't come back in the session")
        try audit(app)

        app = launch("slowSaving")
        XCTAssertTrue(openPhotos(app).waitForExistence(timeout: 20), "a new launch starts with Open Photos")
        openPhotos(app).tap()
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        XCTAssertTrue(photos.wait(for: .runningForeground, timeout: 20), "Photos didn't come to the front")
        photos.terminate()
    }

    /// The Lock Screen camera can't open Photos, so the spot is empty; a countdown before the
    /// first photo hides Open Photos, since leaving would interrupt it.
    @MainActor
    func testOpenPhotosIsNotOfferedWhereItCantBeUsed() throws {
        let locked = launch("slowSaving", extraArguments: ["-NopeSimulatedLockScreenCamera"])
        XCTAssertTrue(locked.buttons["Take Photo"].waitForExistence(timeout: 20))
        waitForTheShutter(locked)
        XCTAssertFalse(openPhotos(locked).exists)
        XCTAssertFalse(locked.descendants(matching: .any)["Last Photo"].exists)

        let app = launch("slowSaving")
        XCTAssertTrue(openPhotos(app).waitForExistence(timeout: 20))
        waitForTheShutter(app)
        chooseDrive(app, "Timer: 10s")
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(app.buttons["Cancel Timer"].waitForExistence(timeout: 5))
        XCTAssertFalse(openPhotos(app).exists, "Open Photos during the countdown")
        try audit(app)
        app.buttons["Cancel Timer"].tap()
        XCTAssertTrue(openPhotos(app).waitForExistence(timeout: 5))
    }

    /// Open Photos at the largest text size and right to left, and red in night mode.
    @MainActor
    func testOpenPhotosAtTheLargestTextSizeRightToLeftAndInNightMode() throws {
        let large = launch("slowSaving", extraArguments: Self.largestTextSize)
        XCTAssertTrue(openPhotos(large).waitForExistence(timeout: 20))
        try auditScrollingScreen(large)

        let mirrored = launch("slowSaving", extraArguments: Self.rightToLeft)
        XCTAssertTrue(openPhotos(mirrored).waitForExistence(timeout: 20))
        try audit(mirrored)

        let night = launch("slowSaving", extraArguments: Self.nightModeOn)
        XCTAssertTrue(openPhotos(night).waitForExistence(timeout: 20))
        settle()
        XCTAssertEqual(nonRedPixels(night, outside: night.otherElements["Viewfinder"].frame), 0, "Open Photos isn't red")
        try audit(night)
    }

    // MARK: - 3. Close-up focus

    /// The close-up hint has About Close-Up Focus, which opens Settings on Honesty with Lenses
    /// Never Switch on Their Own on screen; the entry names the ultra wide lens, which can focus
    /// here. The hint's three buttons pass the audit.
    @MainActor
    func testAboutCloseUpFocusOpensTheHonestyEntry() throws {
        let app = launch("tooClose")
        let about = app.buttons["About Close-Up Focus"]
        XCTAssertTrue(about.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Dismiss"].exists)
        XCTAssertTrue(app.buttons["Switch to Ultra Wide"].exists)
        try audit(app)
        about.tap()
        XCTAssertTrue(app.navigationBars["Honesty"].waitForExistence(timeout: 10))
        let entry = closeUpEntry(app)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.isHittable, "the entry is scrolled into view")
        XCTAssertTrue(entry.label.contains("Lenses Never Switch on Their Own"))
        XCTAssertTrue(entry.label.contains("try the Ultra Wide lens (0.5×)"))
        XCTAssertFalse(entry.label.contains(" cm"), "a distance is shown")
        try audit(app, afterScrolling: true)
    }

    /// The hint at the largest text size: the buttons wrap under one another.
    @MainActor
    func testTheCloseUpHintAtTheLargestTextSize() throws {
        let app = launch("tooClose", extraArguments: Self.largestTextSize)
        let about = app.buttons["About Close-Up Focus"]
        XCTAssertTrue(about.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Switch to Ultra Wide"].exists)
        try auditScrollingScreen(app, checksContrast: !isPad)
    }

    /// The realistic close-up: autofocus searches on the way in to the nearest position, then
    /// the lens rests there; the hint comes.
    @MainActor
    func testACloseUpSweepBringsTheHint() throws {
        let app = launch("closeUpSweep")
        XCTAssertTrue(element(app, containing: "The subject may be too close to focus.").waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Switch to Ultra Wide"].exists)
    }

    /// The Honesty page in both forms: the ultra wide lens named where it can focus, "move
    /// back" only where it can't; Your Photo Library Is Never Read in both. Search for "macro"
    /// finds Honesty.
    @MainActor
    func testHonestyEntriesInBothForms() throws {
        let app = launch("slowSaving")
        openSettings(app)
        open(app, row: "Honesty")
        XCTAssertTrue(app.navigationBars["Honesty"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Your Photo Library Is Never Read").exists)
        let entry = closeUpEntry(app)
        scrollUntilHittable(app, entry)
        XCTAssertTrue(entry.label.contains("For a close-up, move back until the picture is sharp."))
        XCTAssertFalse(entry.label.contains("Ultra Wide"), "the ultra wide lens here can't focus")

        let aids = launch("aids")
        openSettings(aids)
        searchSettings(aids, for: "macro")
        let result = aids.buttons["settings.search.settings.honesty"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(aids.navigationBars["Honesty"].waitForExistence(timeout: 5))
        let named = closeUpEntry(aids)
        scrollUntilHittable(aids, named)
        XCTAssertTrue(named.label.contains("try the Ultra Wide lens (0.5×)"))
    }

    /// The Honesty page with the new entries at the largest text size, right to left and in
    /// night mode.
    @MainActor
    func testHonestyEntriesAtTheLargestTextSizeRightToLeftAndInNightMode() throws {
        for arguments in [Self.largestTextSize, Self.rightToLeft, Self.nightModeOn] {
            let app = launch("aids", extraArguments: arguments)
            openSettings(app)
            // Through search: at the largest text size the Honesty row is far down the list.
            searchSettings(app, for: "macro")
            let result = app.buttons["settings.search.settings.honesty"]
            XCTAssertTrue(result.waitForExistence(timeout: 5))
            result.tap()
            XCTAssertTrue(app.navigationBars["Honesty"].waitForExistence(timeout: 5))
            let entry = closeUpEntry(app)
            scrollUntilHittable(app, entry)
            XCTAssertTrue(entry.exists)
            try audit(app, afterScrolling: true, checksContrast: !isPad || arguments != Self.nightModeOn)
        }
    }

    // MARK: - 4. The steady hint

    /// The dim scene shows the hint with Manual Controls off; turning them on removes it, and
    /// it stays away while a 1 s shutter is set.
    @MainActor
    func testTheSteadyHintLeavesWithManualControls() throws {
        let app = launch("dimLight")
        let hint = element(app, containing: "Hold it steady or use a tripod.")
        XCTAssertTrue(hint.waitForExistence(timeout: 20))
        let manual = app.buttons["ManualControlsButton"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()
        XCTAssertTrue(hint.waitForNonExistence(timeout: 5), "the hint stays with Manual Controls on")
        let shutter = app.buttons["Shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        let slider = app.sliders["Shutter"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        slider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertFalse(hint.waitForExistence(timeout: 3))
        try audit(app)
    }

    // MARK: - 5. The focus square and Lock

    /// A tap shows Lock, which fades after three seconds; a second tap brings it back; touch
    /// and hold locks, and AE/AF never fades.
    @MainActor
    func testTheFocusSquareAndLockFadeAfterATap() throws {
        let app = launch("aids")
        let viewfinder = app.otherElements["Viewfinder"]
        XCTAssertTrue(viewfinder.waitForExistence(timeout: 20))
        waitForTheShutter(app)
        viewfinder.tap()
        let lock = app.buttons["Lock Focus and Exposure"]
        XCTAssertTrue(lock.waitForExistence(timeout: 5))
        XCTAssertTrue(lock.waitForNonExistence(timeout: 8), "Lock didn't fade")
        // The viewfinder keeps its action, so the lock needs no timing.
        XCTAssertTrue(viewfinder.exists)
        viewfinder.tap()
        XCTAssertTrue(lock.waitForExistence(timeout: 5), "a second tap brings Lock back")
        // On the iPad Simulator the test's press and hold arrives as a tap (docs/TESTING.md,
        // issue #146).
        guard !isPad else { return }
        viewfinder.press(forDuration: 1.2)
        let unlock = app.buttons["Unlock Focus and Exposure"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(unlock.exists, "a locked square faded")
        XCTAssertTrue(app.buttons["Exposure and Focus Lock"].exists)
        try audit(app)
    }

    /// With VoiceOver or Switch Control on (simulated: the Simulator runs neither), Lock stays;
    /// the tapped state passes the audit and is red in night mode.
    @MainActor
    func testTheFocusSquareStaysWithAssistiveTechnology() throws {
        let app = launch("aids", extraArguments: Self.assistiveTechnologyOn + Self.nightModeOn)
        let viewfinder = app.otherElements["Viewfinder"]
        XCTAssertTrue(viewfinder.waitForExistence(timeout: 20))
        waitForTheShutter(app)
        viewfinder.tap()
        let lock = app.buttons["Lock Focus and Exposure"]
        XCTAssertTrue(lock.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(lock.exists, "Lock faded with assistive technology on")
        XCTAssertEqual(nonRedPixels(app, outside: viewfinder.frame), 0, "Lock isn't red")
        try audit(app)
        lock.tap()
        XCTAssertTrue(app.buttons["Unlock Focus and Exposure"].waitForExistence(timeout: 10))
        try audit(app)
    }

    /// The Accessibility page says how the lock works now.
    @MainActor
    func testTheAccessibilityPageExplainsTheFade() throws {
        let app = launch("aids")
        openSettings(app)
        open(app, row: "Accessibility")
        XCTAssertTrue(app.navigationBars["Accessibility"].waitForExistence(timeout: 5))
        let first = element(app, containing: "Lock appears under the focus square for a few seconds.")
        scrollUntilHittable(app, first)
        XCTAssertTrue(first.exists)
        XCTAssertTrue(element(app, containing: "With VoiceOver or Switch Control on, the focus square and Lock stay").exists)
        try audit(app, afterScrolling: true)
    }
}
