import XCTest

/// UI tests for Bracket on the drive strip (docs/design/BRACKETING.md, section 7): the word in
/// full auto, the card and its states, Bracket Settings with the order, the frames and the start
/// delay, a frame the lens can't give, the saved card, What's in This Photo, a lens without
/// brackets, and the accessibility audit at the default and largest text sizes, right to left,
/// in night mode, sideways and on iPad.
extension NopeAppUITests {
    /// The drive strip's word of that name: the lowest button with the label (a sheet or the
    /// quick menu may hold another).
    @MainActor
    func bracketWord(_ app: XCUIApplication, _ name: String = "Bracket") -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", name))
        let lowest = matches.allElementsBoundByIndex.enumerated().max { $0.element.frame.minY < $1.element.frame.minY }
        return matches.element(boundBy: lowest?.offset ?? 0)
    }

    /// The bracket's idle card: the button Bracket Settings.
    @MainActor
    func bracketCard(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Bracket Settings"]
    }

    /// Chooses Bracket on the strip and waits for its card.
    @MainActor
    func chooseBracket(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let word = bracketWord(app)
        XCTAssertTrue(word.waitForExistence(timeout: 20), "no Bracket word", file: file, line: line)
        word.tap()
        XCTAssertTrue(bracketCard(app).waitForExistence(timeout: 5), "no bracket card", file: file, line: line)
    }

    /// Waits until an element's VoiceOver value contains the text.
    @MainActor
    func waitForValue(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// Waits until the last-photo thumbnail's value contains the text.
    @MainActor
    func bracketLastPhoto(_ app: XCUIApplication, says text: String, timeout: TimeInterval = 20) -> Bool {
        waitForValue(app.descendants(matching: .any)["Last Photo"], containing: text, timeout: timeout)
    }

    /// Opens Bracket Settings from the card.
    @MainActor
    func openBracketSettings(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        bracketCard(app).tap()
        XCTAssertTrue(app.navigationBars["Bracket Settings"].waitForExistence(timeout: 5), file: file, line: line)
    }

    /// Chooses a value of one of Bracket Settings' pushed-list pickers.
    @MainActor
    func chooseInBracketSettings(_ app: XCUIApplication, _ picker: String, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", picker)).firstMatch
        scrollUntilHittable(app, row)
        XCTAssertTrue(row.waitForExistence(timeout: 5), picker, file: file, line: line)
        row.tap()
        let option = app.buttons[value].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), value, file: file, line: line)
        option.tap()
        XCTAssertTrue(app.navigationBars["Bracket Settings"].waitForExistence(timeout: 5), file: file, line: line)
    }

    /// Presses Bracket Settings' Done row, scrolling down to it.
    @MainActor
    func closeBracketSettings(_ app: XCUIApplication) {
        let done = app.buttons["Done"]
        scrollUntilHittable(app, done)
        done.tap()
        XCTAssertTrue(bracketCard(app).waitForExistence(timeout: 5))
    }

    /// Audits Bracket Settings. As for Settings and the Photo Format sheet
    /// (`testSettingsScreensPassAccessibilityAudits`), the audit reports the form's system section
    /// headers ("The Frames") as "Dynamic Type font sizes are partially unsupported" at the
    /// default text size, so the Dynamic Type check is left out there; the same form is audited
    /// in full at the largest size in `testBracketAtTheLargestTextSize`.
    ///
    /// On iPad the sheet is page sized over the camera, and the audit reports camera text that
    /// the sheet's edge cuts as "Potentially inaccessible text" with no element (in the failing
    /// run's recording, card and row text at the sheet's two sides), as it does beside a popover
    /// (`isTextCutByAPopover`). There only that element-less finding is skipped; every finding on
    /// an element still fails.
    @MainActor
    func auditBracketSettings(_ app: XCUIApplication, afterScrolling: Bool = false, file: StaticString = #filePath, line: UInt = #line) throws {
        guard isPad else {
            try audit(app, afterScrolling: afterScrolling, checksDynamicType: false, file: file, line: line)
            return
        }
        settle()
        let window = app.windows.firstMatch.frame
        try app.performCompleteAccessibilityAudit(for: Self.auditTypes(contrast: !afterScrolling, dynamicType: false)) { issue in
            if issue.auditType == .elementDetection, issue.element == nil { return true }
            // A row cut by the window's edge is measured at its clipped edge (see auditVisibleElements).
            guard let element = issue.element else { return issue.auditType == .contrast }
            return !window.contains(element.frame)
        }
    }

    /// The share of the picture from a point down to its lower edge.
    @MainActor
    private func pictureShare(_ app: XCUIApplication, from top: CGFloat) -> CGFloat {
        let picture = app.otherElements["Viewfinder"].frame
        return max(picture.maxY - top, 0) / picture.height
    }

    /// Bracket is one tap from the default screen in full auto; one press saves three separate
    /// photos; the idle card names the type, frames, step and offsets and covers no more than an
    /// eighth of the picture; choosing Single turns the bracket off.
    @MainActor
    func testBracketFromStripInFullAuto() throws {
        let app = launch("manual", extraArguments: Self.signingOn)
        XCTAssertFalse(app.buttons["More Manual Controls"].waitForExistence(timeout: 3), "manual controls are off")
        chooseBracket(app)
        let card = bracketCard(app)
        XCTAssertTrue(waitForValue(card, containing: "Exposure bracket: 3 frames, 1 EV apart"))
        XCTAssertTrue(waitForValue(card, containing: "1, 0, +1 EV"))
        XCTAssertTrue(bracketWord(app).isSelected)
        XCTAssertTrue(waitForValue(app.buttons["Take Photo"], containing: "Bracket, exposure, 3 frames"))
        if !isPad {
            XCTAssertLessThanOrEqual(pictureShare(app, from: card.frame.minY), 1.0 / 8.0)
        }
        try audit(app)
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(bracketLastPhoto(app, says: "3 photos saved and signed."))
        bracketWord(app, "Single").tap()
        XCTAssertFalse(card.waitForExistence(timeout: 3))
        XCTAssertFalse(bracketWord(app).isSelected)
    }

    /// The card and the selected word open Bracket Settings, which has Frames, Step, Order,
    /// Start Delay, The Frames and the Honesty sentence; choosing Bracket doesn't open it.
    @MainActor
    func testBracketCardOpensSettings() throws {
        let app = launch("manual")
        chooseBracket(app)
        XCTAssertFalse(app.navigationBars["Bracket Settings"].exists, "choosing Bracket opened the sheet")
        openBracketSettings(app)
        for row in ["Frames", "Step", "Order", "Start Delay"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", row)).firstMatch.exists, row)
        }
        XCTAssertTrue(element(app, containing: "Frame 1,").exists)
        try auditBracketSettings(app)
        XCTAssertTrue(scrollUntilFound(app, element(app, containing: "A bracket never fires the flash.")))
        try auditBracketSettings(app, afterScrolling: true)
        closeBracketSettings(app)
        // The selected word opens it too.
        bracketWord(app).tap()
        XCTAssertTrue(app.navigationBars["Bracket Settings"].waitForExistence(timeout: 5))
        closeBracketSettings(app)
    }

    /// The order and the frame count change the card and The Frames.
    @MainActor
    func testBracketSettingsOrderAndFrames() throws {
        let app = launch("manual")
        chooseBracket(app)
        openBracketSettings(app)
        chooseInBracketSettings(app, "Order", "Metered First")
        chooseInBracketSettings(app, "Frames", "5")
        XCTAssertTrue(element(app, containing: "Frame 1, 0 EV").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Frame 5, +2 EV").exists)
        try auditBracketSettings(app)
        closeBracketSettings(app)
        let card = bracketCard(app)
        XCTAssertTrue(waitForValue(card, containing: "Exposure bracket: 5 frames, 1 EV apart"))
        XCTAssertTrue(waitForValue(card, containing: "0, -1, +1, -2, +2 EV") || waitForValue(card, containing: "0, −1, +1, −2, +2 EV"))
    }

    /// In dim light the brightest frames of a wide bracket are beyond the lens: The Frames marks
    /// them with the offset they will have and why, before the photo is taken.
    @MainActor
    func testBracketLimitedFrameIsMarked() throws {
        let app = launch("dimManual")
        chooseBracket(app)
        openBracketSettings(app)
        chooseInBracketSettings(app, "Frames", "7")
        chooseInBracketSettings(app, "Step", "2 EV")
        let limited = element(app, containing: "Frame 7,")
        XCTAssertTrue(scrollUntilFound(app, limited))
        XCTAssertTrue(limited.label.contains("not +6"), limited.label)
        XCTAssertTrue(limited.label.contains("This lens can't go brighter than frame 6."), limited.label)
        try auditBracketSettings(app, afterScrolling: true)
    }

    /// A start delay counts down on the card, as Timer does; Cancel and the shutter stop it and
    /// nothing is taken.
    @MainActor
    func testBracketStartDelayCountsDownAndCancels() throws {
        let app = launch("manual")
        chooseBracket(app)
        openBracketSettings(app)
        chooseInBracketSettings(app, "Start Delay", "10 seconds")
        closeBracketSettings(app)
        XCTAssertTrue(waitForValue(bracketCard(app), containing: "after 10 seconds"))
        XCTAssertTrue(bracketWord(app).isSelected, "Timer isn't shown selected while a bracket is on")
        let shutter = app.buttons["Take Photo"]
        shutter.tap()
        XCTAssertTrue(element(app, containing: "Bracket in").waitForExistence(timeout: 5))
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.exists)
        try audit(app)
        cancel.tap()
        XCTAssertTrue(bracketCard(app).waitForExistence(timeout: 5))
        // The shutter cancels it too.
        shutter.tap()
        XCTAssertTrue(element(app, containing: "Bracket in").waitForExistence(timeout: 5))
        shutter.tap()
        XCTAssertTrue(bracketCard(app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["Last Photo"].exists, "a photo was taken")
    }

    /// While the frames are saved the card says how many; then "3 photos saved" until the next
    /// action. The viewer's chip (`BracketChip`) is checked where the viewer shows it.
    @MainActor
    func testBracketSavedCardAndViewerChip() throws {
        // Each save takes half a second here.
        let app = launch("astro")
        chooseBracket(app)
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(element(app, containing: "Saving:").waitForExistence(timeout: 10))
        XCTAssertFalse(bracketWord(app, "Single").isEnabled, "the other words are dimmed")
        let saved = element(app, containing: "3 photos saved")
        XCTAssertTrue(saved.waitForExistence(timeout: 15))
        try audit(app)
        // The next action brings the idle card back.
        bracketWord(app).tap()
        XCTAssertTrue(app.navigationBars["Bracket Settings"].waitForExistence(timeout: 5))
        chooseInBracketSettings(app, "Step", "2 EV")
        closeBracketSettings(app)
        XCTAssertTrue(waitForValue(bracketCard(app), containing: "2 EV apart"))
        // The viewer's chip on the last frame, and its words in the photo's label.
        app.buttons["Last Photo"].tap()
        let photo = app.descendants(matching: .any)["ViewerPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        let chip = app.descendants(matching: .any)["BracketChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(photo.label.hasPrefix("Photo 3 of 3. Exposure bracket, frame 3 of 3, "), photo.label)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    /// A bracket that stops part-way as the first capture (`manualFirstSaveOnly`: the first save
    /// works, the rest fail): the banner says so, and Last Photo shows the frame saved and opens
    /// the viewer on it (owner decision, 2026-11-18). Before, Last Photo stayed empty and the
    /// viewer couldn't be opened.
    @MainActor
    func testBracketStoppedPartWayShowsTheSavedFrame() throws {
        let app = launch("manualFirstSaveOnly")
        chooseBracket(app)
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(element(app, containing: "Bracket stopped: 1 of 3 photos saved.").waitForExistence(timeout: 15))
        XCTAssertTrue(bracketLastPhoto(app, says: "Saved"), "Last Photo doesn't show the frame saved")
        app.buttons["Last Photo"].tap()
        let photo = app.descendants(matching: .any)["ViewerPhoto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "the viewer didn't open")
        XCTAssertTrue(photo.label.hasPrefix("Photo. Exposure bracket, frame 1 of 3, "), photo.label)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    /// What's in This Photo has a Bracket group for a bracket's frame, from session values.
    @MainActor
    func testBracketDetailsGroup() throws {
        // Signing off, the default: the thumbnail then says "Saved. Not signed…", which
        // openPhotoDetails waits for.
        let app = launch("manual")
        chooseBracket(app)
        openBracketSettings(app)
        chooseInBracketSettings(app, "Order", "Brightest First")
        closeBracketSettings(app)
        openPhotoDetails(app)
        XCTAssertTrue(element(app, containing: "Planned Exposure").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "This Frame").exists)
        XCTAssertTrue(element(app, containing: "Brightest First").exists)
        XCTAssertTrue(element(app, containing: "Not written to the files").exists)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    /// Bracket isn't offered on a lens that can't bracket; switching to one with Bracket selected
    /// selects Single.
    @MainActor
    func testBracketNotOfferedOnALensWithout() throws {
        let app = launch("manual")
        chooseBracket(app)
        let flip = app.buttons["Switch Camera"]
        XCTAssertTrue(flip.waitForExistence(timeout: 5))
        flip.tap()
        XCTAssertTrue(bracketWord(app, "Single").waitForExistence(timeout: 10))
        waitUntil(timeout: .seconds(10)) { !bracketWord(app).exists }
        XCTAssertFalse(bracketWord(app).exists, "the front camera can't bracket")
        XCTAssertTrue(bracketWord(app, "Single").isSelected)
        XCTAssertFalse(bracketCard(app).exists)
        try audit(app)
    }

    /// At the largest text size the camera scrolls: Bracket is a full-width row and the card is
    /// full-width text; Bracket Settings wraps each value.
    @MainActor
    func testBracketAtTheLargestTextSize() throws {
        let app = launch("manual", extraArguments: Self.largestTextSize)
        let word = app.buttons["Bracket"]
        XCTAssertTrue(word.waitForExistence(timeout: 20))
        scrollUntilHittable(app, word)
        word.tap()
        XCTAssertTrue(bracketCard(app).waitForExistence(timeout: 5))
        try auditScrollingScreen(app)
        let card = bracketCard(app)
        scrollUntilHittable(app, card)
        card.tap()
        XCTAssertTrue(app.navigationBars["Bracket Settings"].waitForExistence(timeout: 5))
        try audit(app)
    }

    /// Right to left: the strip, the card and Bracket Settings mirror and pass the audit.
    @MainActor
    func testBracketRightToLeft() throws {
        let app = launch("manual", extraArguments: Self.rightToLeft)
        chooseBracket(app)
        try audit(app)
        openBracketSettings(app)
        try auditBracketSettings(app)
    }

    /// Night mode: the strip, the card and Bracket Settings are red on black.
    @MainActor
    func testBracketNightMode() throws {
        let app = launch("manual", extraArguments: Self.nightModeOn)
        chooseBracket(app)
        let viewfinderFrame = app.otherElements["Viewfinder"].frame
        XCTAssertEqual(bracketNonRedPixels(app, outside: viewfinderFrame), 0, "white, blue or other colors remain")
        try audit(app)
        openBracketSettings(app)
        settle()
        // The natural-color viewfinder shows at the sheet's rounded top corners (and beside the
        // page-sized sheet on iPad), as in Astro Settings
        // (testAstroHelperIsRedOnBlackAndSetsUpTheFrames).
        XCTAssertEqual(bracketNonRedPixels(app, outside: viewfinderFrame), 0, "Bracket Settings isn't all red")
        try auditBracketSettings(app)
    }

    /// Sideways on an iPhone the strip shows Bracket's symbol and the mode is named in a pill.
    @MainActor
    func testBracketSideways() throws {
        guard !isPad else { throw XCTSkip("An iPad window rotates for real; testBracketOnIPad covers it.") }
        let app = launch("manual")
        chooseBracket(app)
        try turnSideways(app, mode: "Bracket")
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(bracketWord(app).exists)
        XCTAssertTrue(app.staticTexts["Bracket"].exists, "the mode isn't named on the picture")
        XCTAssertTrue(bracketCard(app).exists)
        // Text drawn a quarter turn is measured unturned by the audit, as in
        // testCameraShellSideways; those findings are skipped.
        try app.performCompleteAccessibilityAudit { issue in
            guard let element = issue.element else { return issue.auditType == .textClipped || issue.auditType == .contrast }
            return issue.auditType == .contrast && element.exists && element.frame.height > element.frame.width
        }
    }

    /// On iPad the card sits on the picture's lower edge in the column layout, and Bracket
    /// Settings is a sheet.
    @MainActor
    func testBracketOnIPad() throws {
        guard isPad else { throw XCTSkip("The iPad layout; the iPhone tests cover the stacked layout.") }
        let app = launch("manual", extraArguments: Self.signingOn)
        chooseBracket(app)
        try audit(app)
        openBracketSettings(app)
        try auditBracketSettings(app)
        closeBracketSettings(app)
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(bracketLastPhoto(app, says: "3 photos saved and signed."))
    }

    /// Counts sampled screen pixels that aren't black or red, as `nonRedPixels(_:outside:)` does
    /// (below the status bar, above the home indicator, outside the viewfinder), and also
    /// outside the window's lower trailing corner on iPad, where the system draws its window
    /// corner control outside the app's views (one white sample in some runs on the iPad
    /// Simulator). Samples every fourth point.
    ///
    /// - Parameters:
    ///   - app: The app.
    ///   - viewfinder: The viewfinder's frame, which keeps its natural color.
    /// - Returns: The count, or -1 when the screenshot can't be read.
    @MainActor
    func bracketNonRedPixels(_ app: XCUIApplication, outside viewfinder: CGRect) -> Int {
        settle()
        let window = app.windows.firstMatch.frame
        let corner = isPad ? CGRect(x: window.maxX - 64, y: window.maxY - 64, width: 64, height: 64) : .null
        let image = XCUIScreen.main.screenshot().image
        guard let cgImage = image.cgImage else { return -1 }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return -1 }
        // The status bar (60 points) and the home indicator band (20 points) are the system's,
        // as in nonRedPixels(_:outside:).
        var count = 0
        for y in stride(from: CGFloat(60), to: window.height - 20, by: 4) {
            for x in stride(from: CGFloat(0), to: window.width, by: 4) {
                let point = CGPoint(x: x, y: y)
                guard !viewfinder.contains(point), !corner.contains(point) else { continue }
                let px = min(Int(x * image.scale), width - 1)
                let py = min(Int(y * image.scale), height - 1)
                let index = (py * width + px) * 4
                let (red, green, blue) = (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
                if max(green, blue) > max(24, red / 4) { count += 1 }
            }
        }
        return count
    }

    /// Swipes up until the element exists, at most eight times.
    @MainActor
    private func scrollUntilFound(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp() }
        return element.exists
    }
}
