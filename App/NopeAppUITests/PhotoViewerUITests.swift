import XCTest

/// UI tests for the Last Photo viewer (docs/design/BUILD-SPEC.md, 3.14; docs/design/viewer.html;
/// docs/design/ACCESSIBILITY.md, "Last Photo viewer"): opening and closing, paging, the status
/// variants, zoom and its preview hint, hiding the controls, the actions, photos that arrive or
/// fail while it is open, the fallback, and the audits at the largest text size, right to left,
/// in night mode, sideways and on iPad.
///
/// The simulated previews (`SimulatedPreviewer`) are 30 × 40 pixels and the simulated photos
/// 4032 pixels wide, so every preview is smaller than its photo and the hint shows when zoomed.
extension NopeAppUITests {
    /// Night mode on at launch.
    private static let viewerNightMode = ["-NopeSettings.isNightModeOn", "YES"]

    /// The Lock Screen camera's environment: no way to open Photos (`NopeApp`, Debug only).
    private static let lockScreenCamera = ["-NopeSimulatedLockScreenCamera"]

    /// The viewer's photo element.
    @MainActor
    private func viewerPhoto(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["ViewerPhoto"]
    }

    /// Waits until an element's attribute matches a predicate format, such as
    /// `label == 'Photo 2 of 3'` or `value CONTAINS 'Zoomed in.'`.
    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ arguments: CVarArg..., timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: format, argumentArray: arguments)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// Takes a photo with the shutter and waits until Last Photo says it was saved.
    @MainActor
    private func takeViewerPhoto(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let shutter = app.buttons["Take Photo"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 15), file: file, line: line)
        XCTAssertTrue(wait(shutter, "isEnabled == true"), file: file, line: line)
        shutter.tap()
        XCTAssertTrue(lastPhoto(app, says: "Saved", timeout: 15), file: file, line: line)
        // The thumbnail shows "Saving…" while busy; wait until the button is back.
        XCTAssertTrue(app.buttons["Last Photo"].waitForExistence(timeout: 10), file: file, line: line)
    }

    /// Chooses Interval on the drive strip (the lowest button of that name), starts the default
    /// series (10 photos, 10 seconds apart) and brightens the screen the series dims.
    @MainActor
    private func startIntervalSeries(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let take = app.buttons["Take Photo"]
        XCTAssertTrue(take.waitForExistence(timeout: 20), file: file, line: line)
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", "Interval"))
        let lowest = matches.allElementsBoundByIndex.enumerated().max { $0.element.frame.minY < $1.element.frame.minY }
        matches.element(boundBy: lowest?.offset ?? 0).tap()
        XCTAssertTrue(app.buttons["Interval Settings"].waitForExistence(timeout: 5), file: file, line: line)
        take.tap()
        // The series dims the screen; a tap on the cover brightens it, and the series continues.
        let brighten = app.buttons["Brighten Screen"]
        XCTAssertTrue(brighten.waitForExistence(timeout: 15), file: file, line: line)
        brighten.tap()
        XCTAssertTrue(wait(brighten, "exists == false"), file: file, line: line)
    }

    /// Opens the viewer from Last Photo and returns its photo element.
    @MainActor
    @discardableResult
    private func openViewer(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let thumbnail = app.buttons["Last Photo"]
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 10), file: file, line: line)
        thumbnail.tap()
        let photo = viewerPhoto(app)
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "the viewer didn't open", file: file, line: line)
        // Let the zoom transition finish.
        settle()
        return photo
    }

    /// Closes the viewer with Close and waits for the camera.
    @MainActor
    private func closeViewer(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["Close"].tap()
        XCTAssertTrue(wait(viewerPhoto(app), "exists == false"), "the viewer didn't close", file: file, line: line)
        XCTAssertTrue(app.buttons["Last Photo"].waitForExistence(timeout: 10), file: file, line: line)
    }

    /// One photo: the status and caption facts in the photo's value, the audit, and Close back to
    /// the camera without bringing Photos to the front.
    @MainActor
    func testViewerOpensFromLastPhoto() throws {
        let app = launch("allow", extraArguments: Self.signingOn)
        continuePastFirstRun(app)
        takeViewerPhoto(app)
        let photo = openViewer(app)
        XCTAssertEqual(photo.label, "Photo")
        let value = photo.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("RAW."), value)
        XCTAssertTrue(value.contains("Saved and signed."), value)
        XCTAssertTrue(value.contains("Wide."), value)
        XCTAssertTrue(app.buttons["Close"].exists)
        XCTAssertTrue(app.buttons["Photo Details"].exists)
        XCTAssertTrue(app.buttons["Open in Photos"].exists)
        XCTAssertFalse(app.buttons["New Photo"].exists)
        // Close is where Last Photo was: leading, below the photo.
        if !isPad {
            XCTAssertLessThan(app.buttons["Close"].frame.midX, app.buttons["Photo Details"].frame.minX)
            XCTAssertGreaterThan(app.buttons["Close"].frame.minY, photo.frame.maxY - 1)
            XCTAssertGreaterThanOrEqual(app.buttons["Close"].frame.width, 44)
        }
        try audit(app)
        closeViewer(app)
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        XCTAssertNotEqual(photos.state, .runningForeground)
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Three photos: the viewer opens on the newest; a swipe and the arrow keys page, the first
    /// and last spring back, and the label gives the position.
    @MainActor
    func testViewerPagesThroughSessionPhotos() throws {
        let app = launch("noRAW", extraArguments: Self.signingOn)
        for _ in 0..<3 { takeViewerPhoto(app) }
        let photo = openViewer(app)
        XCTAssertEqual(photo.label, "Photo 3 of 3")
        photo.swipeLeft()
        XCTAssertFalse(wait(photo, "label != 'Photo 3 of 3'", timeout: 2), "the last photo didn't spring back")
        photo.swipeRight()
        XCTAssertTrue(wait(photo, "label == 'Photo 2 of 3'"))
        try audit(app)
        // The arrow keys reach the viewer's commands on iPhone only: on the iPad Simulator keys
        // go to the focused button, as for Space (testSpaceTakesAPhoto, an open finding).
        guard !isPad else { return }
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(wait(photo, "label == 'Photo 1 of 3'"))
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertFalse(wait(photo, "label != 'Photo 1 of 3'", timeout: 2), "the first photo didn't stay")
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(wait(photo, "label == 'Photo 2 of 3'"))
    }

    /// The three status variants (decision V11): Processed and signed, Not signed after a failure,
    /// and Not signed with signing off.
    @MainActor
    func testViewerStatusForProcessedAndUnsigned() throws {
        let processed = launch("noRAW", extraArguments: Self.signingOn)
        takeViewerPhoto(processed)
        var value = openViewer(processed).value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("Processed: no RAW on this lens, HEIF."), value)
        XCTAssertTrue(value.contains("Saved and signed."), value)
        try audit(processed)
        processed.terminate()

        let failed = launch("signingFails", extraArguments: Self.signingOn)
        takeViewerPhoto(failed)
        value = openViewer(failed).value as? String ?? ""
        XCTAssertTrue(value.contains("Saved. Not signed: the signature couldn't be created."), value)
        try audit(failed)
        failed.terminate()

        let off = launch("noRAW")
        takeViewerPhoto(off)
        value = openViewer(off).value as? String ?? ""
        XCTAssertTrue(value.contains("Saved. Not signed: signing is off in Settings."), value)
        try audit(off)
    }

    /// Double tap and pinch zoom in, with the preview hint; while zoomed a swipe down doesn't
    /// close the viewer and a swipe doesn't page; a double tap returns to fit.
    @MainActor
    func testViewerZoomShowsPreviewHint() throws {
        let app = launch("noRAW", extraArguments: Self.signingOn)
        takeViewerPhoto(app)
        takeViewerPhoto(app)
        let photo = openViewer(app)
        XCTAssertFalse(element(app, containing: "A screen-size preview").exists)
        photo.doubleTap()
        XCTAssertTrue(wait(photo, "value CONTAINS 'Zoomed in. A screen-size preview, not the full photo.'"))
        try audit(app)
        photo.swipeDown()
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "a swipe down closed the zoomed photo")
        XCTAssertTrue((photo.value as? String ?? "").contains("Zoomed in."), "a swipe down ended the zoom")
        photo.swipeRight()
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "a swipe down closed the zoomed photo")
        XCTAssertEqual(photo.label, "Photo 2 of 2", "a swipe paged the zoomed photo")
        XCTAssertTrue((photo.value as? String ?? "").contains("Zoomed in."), "a swipe ended the zoom")
        photo.doubleTap()
        XCTAssertTrue(wait(photo, "NOT (value CONTAINS 'Zoomed in.')"))
        photo.pinch(withScale: 3, velocity: 2)
        XCTAssertTrue(wait(photo, "value CONTAINS 'Zoomed in.'"))
        // In the iOS 27.2 Simulator a synthesized pinch in left the zoomed photo zoomed (not
        // explained yet); pinching back to fit is a device check (docs/TESTING.md). A double tap
        // returns to fit.
        photo.doubleTap()
        XCTAssertTrue(wait(photo, "NOT (value CONTAINS 'Zoomed in.')"))
        // Not zoomed in, a swipe down past a third of the photo's height closes the viewer.
        let start = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(wait(photo, "exists == false"), "a swipe down didn't close the viewer")
        XCTAssertTrue(app.buttons["Last Photo"].waitForExistence(timeout: 10))
    }

    /// A tap hides the controls and another shows them; nothing hides by itself.
    @MainActor
    func testViewerHidesAndShowsControls() throws {
        let app = launch("noRAW", extraArguments: Self.signingOn)
        takeViewerPhoto(app)
        let photo = openViewer(app)
        let close = app.buttons["Close"]
        photo.tap()
        XCTAssertTrue(wait(close, "exists == false"), "a tap didn't hide the controls")
        XCTAssertTrue(photo.exists)
        try audit(app)
        photo.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5), "a second tap didn't show the controls")
        try audit(app)
    }

    /// Photo Details opens What's in This Photo for the photo shown, and Done returns to it; Open
    /// in Photos brings Photos to the front.
    @MainActor
    func testViewerActions() throws {
        let app = launch("signingFails", extraArguments: Self.signingOn)
        takeViewerPhoto(app)
        let photo = openViewer(app)
        app.buttons["Photo Details"].tap()
        XCTAssertTrue(app.navigationBars["What's in This Photo"].waitForExistence(timeout: 10))
        try audit(app, checksDynamicType: false)
        app.buttons["Done"].tap()
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "Done didn't return to the viewer")
        app.buttons["Open in Photos"].tap()
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        XCTAssertTrue(photos.wait(for: .runningForeground, timeout: 15))
        app.activate()
    }

    /// A photo taken while the viewer is open (a running interval series, as from Apple Watch or
    /// Siri) is added as the last page; the page shown stays, and New Photo goes to the newest.
    @MainActor
    func testViewerNewPhotoWhileOpen() throws {
        let app = launch("noRAW", extraArguments: Self.signingOn)
        startIntervalSeries(app)
        XCTAssertTrue(lastPhoto(app, says: "Saved", timeout: 20))
        let photo = openViewer(app)
        XCTAssertEqual(photo.label, "Photo")
        // The series takes its next photo 10 seconds after the first.
        let newPhoto = app.buttons["New Photo"]
        XCTAssertTrue(newPhoto.waitForExistence(timeout: 25), "New Photo didn't appear")
        XCTAssertTrue(photo.label.hasPrefix("Photo 1 of"), "the page shown changed: \(photo.label)")
        try audit(app)
        newPhoto.tap()
        XCTAssertTrue(wait(newPhoto, "exists == false"))
        // New Photo goes to the newest page, "Photo n of n". The series takes a photo every 10
        // seconds, so by now that may be the third photo rather than the second.
        let words = photo.label.split(separator: " ")
        XCTAssertTrue(words.count == 4 && words[1] == words[3] && words[1] != "1", "not the newest page: \(photo.label)")
        closeViewer(app)
        app.buttons["Stop"].tap()
    }

    /// A photo that fails while the viewer is open shows the Photo Not Saved chip; the chip
    /// closes the viewer, where the failure banner waits.
    @MainActor
    func testViewerFailureWhileOpen() throws {
        let app = launch("firstSaveOnly", extraArguments: Self.signingOn)
        startIntervalSeries(app)
        XCTAssertTrue(lastPhoto(app, says: "Saved", timeout: 20))
        openViewer(app)
        let chip = app.buttons["Photo Not Saved"]
        XCTAssertTrue(chip.waitForExistence(timeout: 25), "the chip didn't appear")
        try audit(app)
        chip.tap()
        XCTAssertTrue(wait(viewerPhoto(app), "exists == false"))
        XCTAssertTrue(element(app, containing: "the photo library couldn't add the photo").waitForExistence(timeout: 10))
    }

    /// Leaving the app closes the viewer and releases the previews (decision V7); the viewer then
    /// shows the fallback, with the thumbnail no larger than 160 points.
    @MainActor
    func testViewerFallbackWhenPreviewReleased() throws {
        let app = launch("noRAW", extraArguments: Self.signingOn)
        takeViewerPhoto(app)
        openViewer(app)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackgroundSuspended, timeout: 10) || app.state == .runningBackground)
        app.activate()
        XCTAssertTrue(app.buttons["Last Photo"].waitForExistence(timeout: 15), "the viewer didn't close in the background")
        XCTAssertFalse(viewerPhoto(app).exists)
        let photo = openViewer(app)
        XCTAssertTrue(wait(photo, "value CONTAINS 'Preview Not Kept.'"))
        let title = app.staticTexts["Preview Not Kept"]
        XCTAssertFalse(title.exists, "the fallback's words are part of the photo's value")
        // No zoom on the fallback.
        photo.doubleTap()
        XCTAssertFalse(wait(photo, "value CONTAINS 'Zoomed in.'", timeout: 2))
        try audit(app)
    }

    /// The largest text size: the facts above the photo and three full-width rows.
    @MainActor
    func testViewerLargestText() throws {
        let app = launch("noRAW", extraArguments: Self.signingOn + Self.largestTextSize)
        takeViewerPhoto(app)
        takeViewerPhoto(app)
        let photo = openViewer(app)
        let close = app.buttons["Close"]
        let details = app.buttons["Photo Details"]
        XCTAssertTrue(close.exists)
        XCTAssertGreaterThan(details.frame.width, app.windows.firstMatch.frame.width * 0.8, "Photo Details isn't a full-width row")
        XCTAssertGreaterThanOrEqual(photo.frame.height, 279)
        try audit(app)
    }

    /// Right to left: the rows mirror (Close on the right on iPhone), and swiping follows the
    /// layout direction.
    @MainActor
    func testViewerRightToLeft() throws {
        let app = launch("signingFails", extraArguments: Self.signingOn + Self.rightToLeft)
        takeViewerPhoto(app)
        takeViewerPhoto(app)
        let photo = openViewer(app)
        if !isPad {
            XCTAssertGreaterThan(app.buttons["Close"].frame.minX, app.buttons["Photo Details"].frame.maxX)
        }
        try audit(app, checksContrast: !isPad)
        // Right to left the earlier photo is to the right: a swipe left shows it.
        photo.swipeLeft()
        XCTAssertTrue(wait(photo, "label == 'Photo 1 of 2'"))
    }

    /// Night mode: red on black, the photo included (decision V4), with no other light anywhere
    /// on the screen.
    @MainActor
    func testViewerNightModeIsAllRed() throws {
        let app = launch("signingFails", extraArguments: Self.signingOn + Self.viewerNightMode)
        takeViewerPhoto(app)
        takeViewerPhoto(app)
        let photo = openViewer(app)
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0, "white, blue or other colors remain in the viewer")
        try audit(app)
        photo.doubleTap()
        XCTAssertTrue(wait(photo, "value CONTAINS 'Zoomed in.'"))
        settle()
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0, "the zoomed photo or the hint isn't red")
        app.buttons["Photo Details"].tap()
        XCTAssertTrue(app.navigationBars["What's in This Photo"].waitForExistence(timeout: 10))
        settle()
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0, "Photo Details from the viewer isn't red")
    }

    /// iPhone sideways: the viewer turns with the phone and uses the trailing column.
    @MainActor
    func testViewerSideways() throws {
        try XCTSkipIf(isPad, "iPhone only; the iPad's orientations are in testViewerOnIPad")
        let app = launch("noRAW", extraArguments: Self.signingOn)
        takeViewerPhoto(app)
        let photo = openViewer(app)
        rotate(app, to: .landscapeLeft)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "the viewer didn't turn with the phone")
        XCTAssertGreaterThan(app.buttons["Close"].frame.minX, photo.frame.maxX - 1, "Close isn't in the trailing column")
        try audit(app)
        rotate(app, to: .portrait)
        XCTAssertTrue(photo.exists, "the viewer closed when the phone turned")
    }

    /// Space (Take Photo with nothing focused) closes the viewer and takes no photo, as the
    /// hardware shutter does (decision V1); the next Space takes one.
    ///
    /// Escape is a device check (docs/TESTING.md): in the iOS 27.2 Simulator a synthesized Escape
    /// (`typeKey(.escape)`) didn't reach the viewer's Escape command, while the arrow keys reached
    /// theirs; the cause isn't known yet. The hardware buttons can't be pressed in the Simulator.
    @MainActor
    func testViewerEscapeAndHardwareShutterClose() throws {
        // Space reaches the Camera menu's command on iPhone only (testSpaceTakesAPhoto).
        try XCTSkipIf(isPad, "Space bar shutter on iPad: open finding")
        let app = launch("noRAW", extraArguments: Self.signingOn)
        takeViewerPhoto(app)
        let photo = openViewer(app)
        XCTAssertEqual(photo.label, "Photo")
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(wait(viewerPhoto(app), "exists == false"), "Space didn't close the viewer")
        let reopened = openViewer(app)
        XCTAssertEqual(reopened.label, "Photo", "Space took a photo while the viewer was open")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Last Photo"].waitForExistence(timeout: 10))
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(wait(openViewer(app), "label == 'Photo 2 of 2'"), "the next Space didn't take a photo")
    }

    /// iPad: the column arrangement in both orientations, and the fallback.
    @MainActor
    func testViewerOnIPad() throws {
        try XCTSkipUnless(isPad, "iPad only")
        let app = launch("noRAW", extraArguments: Self.signingOn)
        takeViewerPhoto(app)
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            rotate(app, to: orientation)
            let photo = openViewer(app)
            XCTAssertGreaterThan(app.buttons["Close"].frame.minX, photo.frame.maxX - 1, "Close isn't in the trailing column")
            XCTAssertGreaterThan(app.buttons["Photo Details"].frame.minX, photo.frame.maxX - 1)
            try audit(app)
            closeViewer(app)
        }
        XCUIDevice.shared.press(.home)
        _ = app.wait(for: .runningBackgroundSuspended, timeout: 10)
        app.activate()
        let photo = openViewer(app)
        XCTAssertTrue(wait(photo, "value CONTAINS 'Preview Not Kept.'"))
        try audit(app)
    }

    /// The Lock Screen camera has no way to open Photos, so its viewer has no Open in Photos.
    @MainActor
    func testLockScreenViewerHasNoOpenInPhotos() throws {
        let app = launch("noRAW", extraArguments: Self.signingOn + Self.lockScreenCamera)
        takeViewerPhoto(app)
        openViewer(app)
        XCTAssertTrue(app.buttons["Photo Details"].exists)
        XCTAssertFalse(app.buttons["Open in Photos"].exists)
        try audit(app)
    }
}
