import XCTest

/// UI tests for the flash and the torch (issue #38) and night mode (issue #61), against the
/// simulated backend: its wide lens has a flash and a torch; the other lenses have neither.
extension NopeAppUITests {
    /// The launch arguments that start in night mode.
    static let nightModeOn = ["-NopeSettings.isNightModeOn", "YES"]

    /// The launch arguments that start in night mode with the viewfinder tinted red.
    static let redViewfinder = nightModeOn + ["-NopeSettings.tintsViewfinderInNightMode", "YES"]

    @MainActor
    func testLightStaysOnWhileTakingPhotosAndTurnsOffFromItsPill() throws {
        let app = launch("allow")
        continuePastFirstRun(app)
        quickControl(app, "Light")
        let lightPill = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", "Light", "25%")).firstMatch
        XCTAssertTrue(lightPill.waitForExistence(timeout: 5), "the Light pill shows the brightness")
        closeTray(app)
        try audit(app)
        // The light stays on through a capture.
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Last Photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(lightPill.exists, "the light is still on after the photo")
        // A brightness from the pill's menu.
        lightPill.tap()
        let half = app.buttons["Brightness 50%"]
        XCTAssertTrue(half.waitForExistence(timeout: 5))
        half.tap()
        let halfPill = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", "Light", "50%")).firstMatch
        XCTAssertTrue(halfPill.waitForExistence(timeout: 5))
        // The pill stays in clean view, so the light can always be turned off in one place.
        quickControl(app, "Hide Controls")
        XCTAssertTrue(app.buttons["Show Controls"].waitForExistence(timeout: 5))
        XCTAssertTrue(halfPill.exists)
        try audit(app)
        halfPill.tap()
        let off = app.buttons["Turn Off Light"]
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        off.tap()
        XCTAssertFalse(halfPill.waitForExistence(timeout: 2))
    }

    @MainActor
    func testFlashMenuPillAndLensesWithoutALight() throws {
        let app = launch("allow")
        continuePastFirstRun(app)
        quickControl(app, "Flash")
        let flashOn = app.buttons["Flash On"]
        XCTAssertTrue(flashOn.waitForExistence(timeout: 5))
        flashOn.tap()
        let flashPill = app.buttons["Flash On"]
        XCTAssertTrue(flashPill.waitForExistence(timeout: 5), "the flash pill shows a flash that isn't off")
        try audit(app)
        // The steady light replaces the flash: no flash pill while the light is on.
        app.buttons["Light"].tap()
        let lightPill = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", "Light", "25%")).firstMatch
        XCTAssertTrue(lightPill.waitForExistence(timeout: 5))
        XCTAssertFalse(flashPill.exists)
        closeTray(app)
        lightPill.tap()
        app.buttons["Turn Off Light"].tap()
        // The pill's action turns the flash off.
        XCTAssertTrue(flashPill.waitForExistence(timeout: 5))
        flashPill.tap()
        XCTAssertFalse(flashPill.waitForExistence(timeout: 2))
        // The ultra wide has neither: Q doesn't offer them.
        closeTray(app)
        app.buttons["Ultra Wide"].tap()
        quickMenuButton(app).tap()
        XCTAssertTrue(app.buttons["Hide Controls"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Light"].exists)
        XCTAssertFalse(app.buttons["Flash"].exists)
        XCTAssertTrue(app.buttons["Night Mode"].exists)
    }

    @MainActor
    func testRefusedLightIsExplainedAndCanBeCleared() throws {
        let app = launch("lightUnavailable")
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        quickControl(app, "Light")
        let warning = app.buttons["Light Unavailable"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue((warning.value as? String)?.contains("didn't allow it") == true)
        try audit(app)
        // Turning the switch off clears the warning.
        app.buttons["Light"].tap()
        XCTAssertFalse(warning.waitForExistence(timeout: 2))
    }

    @MainActor
    func testNightModeFromTheTrayIsRedOnBlack() throws {
        let app = launch("allow", extraArguments: ["-NopeSimulatedViewfinder", "white"])
        continuePastFirstRun(app)
        XCTAssertGreaterThan(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0, "the check sees white")
        quickControl(app, "Night Mode")
        XCTAssertTrue(app.buttons["Night Mode"].isSelected)
        closeTray(app)
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0, "white, blue or other colors remain")
        // The viewfinder keeps its natural colors by default.
        XCTAssertEqual(centerColor(app, of: app.otherElements["Viewfinder"].frame), .white)
        try audit(app)
    }

    /// What's in This Photo is red on black in night mode, as the camera's other sheets are.
    @MainActor
    func testNightModeCameraWithPhotoWarningAndLight() throws {
        let app = launch("signingFails", extraArguments: Self.signingOn + Self.nightModeOn)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        app.buttons["Take Photo"].tap()
        XCTAssertTrue(app.buttons["Not Signed"].waitForExistence(timeout: 10))
        quickControl(app, "Light")
        XCTAssertTrue(app.buttons["Light"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(nonRedPixels(app, outside: app.otherElements["Viewfinder"].frame), 0)
        try audit(app)
        app.terminate()

        let large = launch("signingFails", extraArguments: Self.signingOn + Self.nightModeOn + Self.largestTextSize)
        XCTAssertTrue(large.buttons["Take Photo"].waitForExistence(timeout: 10))
        try auditScrollingScreen(large)
    }

    @MainActor
    func testRedViewfinderOption() throws {
        let app = launch("photosDenied", extraArguments: Self.redViewfinder + ["-NopeSimulatedViewfinder", "white"])
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        settle()
        XCTAssertEqual(centerColor(app, of: app.otherElements["Viewfinder"].frame), .red)
    }

    /// The viewfinder is drawn behind the camera interface in every mode, so it stays the same
    /// view when night mode changes; in the scrolling layout it must still move with the
    /// picture.
    ///
    /// The manual controls list is shown so the scrolling layout is taller than the screen on
    /// the iPad too: without it, a portrait iPad fits the whole layout at the largest text size,
    /// so a drag only bounced and the picture returned to where it was.
    @MainActor
    func testViewfinderFollowsThePictureInTheScrollingLayout() throws {
        let app = launch(
            "manual",
            extraArguments: Self.largestTextSize + ["-NopeSettings.showsManualControls", "YES", "-NopeSimulatedViewfinder", "white"])
        let viewfinder = app.otherElements["Viewfinder"]
        XCTAssertTrue(viewfinder.waitForExistence(timeout: 10))
        settle()
        let before = viewfinder.frame
        XCTAssertEqual(centerColor(app, of: before), .white)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)))
        settle()
        let after = viewfinder.frame
        XCTAssertLessThan(after.minY, before.minY - 40, "the layout scrolled")
        // The white picture is where the viewfinder element is now, and not below it, where it
        // was before the scroll.
        let visible = after.intersection(app.windows.firstMatch.frame)
        XCTAssertEqual(centerColor(app, of: visible), .white)
        let below = CGRect(x: after.minX, y: after.maxY + 8, width: after.width, height: 2)
        XCTAssertNotEqual(centerColor(app, of: below), .white)
    }

    @MainActor
    func testNightModeSettingsScreensPassAccessibilityAudits() throws {
        let app = launch("photosDenied", extraArguments: Self.nightModeOn)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        openSettings(app)
        let tint = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Red Viewfinder")).firstMatch
        var swipes = 0
        while !tint.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(tint.exists, "the Red Viewfinder option shows while night mode is on")
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0, "white, blue or other colors remain in Settings")
        app.buttons["Done"].tap()
        // As in testSettingsScreensPassAccessibilityAudits: Dynamic Type is checked at the
        // largest size below.
        try auditSettingsScreens(app, checksDynamicType: false, checksContrast: !isPad)
    }

    // The largest text size and right to left are separate tests: together with the default
    // size they took 770 seconds in one CI test (build 43786103024), most of a shard.

    @MainActor
    func testNightModeSettingsScreensAtTheLargestTextSize() throws {
        let large = launch("photosDenied", extraArguments: Self.nightModeOn + Self.largestTextSize)
        XCTAssertTrue(large.buttons["Take Photo"].waitForExistence(timeout: 10))
        try auditSettingsScreens(large, checksContrast: !isPad)
    }

    @MainActor
    func testNightModeSettingsScreensRightToLeft() throws {
        let rightToLeft = launch("photosDenied", extraArguments: Self.nightModeOn + Self.rightToLeft)
        XCTAssertTrue(rightToLeft.buttons["Take Photo"].waitForExistence(timeout: 10))
        try auditSettingsScreens(rightToLeft, checksDynamicType: false, checksContrast: !isPad)
    }

    /// The Details in Each Photo footer and header (Choose Details before 1.0.0), which the
    /// audit's Dynamic Type check is not asked about (``NopeAppUITests/measuredDynamicTypeLabels``),
    /// are measured here instead: each is larger at every one of the nine text sizes than at the
    /// size before, in night mode, where Settings is a sheet on iPad too.
    @MainActor
    func testChooseDetailsTextGrowsAtEveryTextSize() throws {
        let categories = [
            "L", "XL", "XXL", "XXXL", "AccessibilityM", "AccessibilityL", "AccessibilityXL", "AccessibilityXXL",
            "AccessibilityXXXL",
        ]
        // The master switch's title isn't measured since 1.0.0: in night mode its row is the
        // switch (NightModeSwitch), whose title has no element of its own and whose row keeps
        // its height until the title wraps; the audit checks the switch at the largest size.
        let labels = Self.measuredDynamicTypeLabels
        var previous: [String: CGFloat] = [:]
        for category in categories {
            let app = launch(
                "photosDenied",
                extraArguments: Self.nightModeOn + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategory" + category])
            XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
            openSettings(app)
            open(app, row: "Details in Each Photo")
            XCTAssertTrue(app.navigationBars["Details in Each Photo"].waitForExistence(timeout: 5))
            for label in labels {
                // "Location" is also the switch's title; the header is the first match, above it.
                let text = app.staticTexts[label].firstMatch
                XCTAssertTrue(text.waitForExistence(timeout: 5), "\(label) at \(category)")
                // The text's area: a line that wraps gets narrower and taller.
                let area = text.frame.width * text.frame.height
                if let before = previous[label] {
                    XCTAssertGreaterThan(area, before, "\(label) isn't larger at \(category) than at the size before")
                }
                previous[label] = area
            }
            app.terminate()
        }
    }

    // MARK: - Pixels

    /// A color class of a sampled pixel.
    enum PixelColor: Equatable {
        /// Red only: green and blue near zero.
        case red
        /// All three channels high.
        case white
        /// Anything else.
        case other
    }

    /// The status bar's height, in points: the system draws it, outside the app's views.
    private static var statusBarHeight: CGFloat { 60 }

    /// The band at the bottom where the system draws the home indicator, which is skipped: night
    /// mode hides it (`persistentSystemOverlays`), but the system shows it again for a few
    /// seconds after a swipe, such as the one that scrolls the quick-controls tray to a later
    /// item.
    private static var homeIndicatorHeight: CGFloat { 20 }

    /// Counts sampled screen pixels outside a frame (and below the status bar) that aren't
    /// black or red: any white, green or blue light. Samples every fourth point.
    @MainActor
    func nonRedPixels(_ app: XCUIApplication, outside excluded: CGRect) -> Int {
        // Anti-aliased edges and the system's glass highlights mix in a little green and blue;
        // a pixel counts when green or blue is more than a quarter of its red (and visible).
        countPixels(app, outside: excluded) { red, green, blue in max(green, blue) > max(24, red / 4) }
    }

    /// At the largest text size the camera scrolls, and the viewfinder, drawn behind the
    /// interface, stays inside the scroll view: no yellow from a pure yellow viewfinder shows in
    /// the pinned shutter row or above the scroll view, before or after scrolling the picture
    /// past the top. It ran into the shutter row on short screens (iPhone SE, the iPhone Duo's
    /// outer display) and past the top when scrolled.
    @MainActor
    func testViewfinderStaysInsideTheScrollingLayout() throws {
        let app = launch(
            "manual",
            extraArguments: ["-NopeSettings.showsManualControls", "YES", "-NopeSimulatedViewfinder", "yellow"]
                + Self.largestTextSize)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 20))
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(yellowPixels(app, outside: scrollView.frame), -1)
        XCTAssertEqual(yellowPixels(app, outside: scrollView.frame), 0, "the viewfinder shows outside the scroll view")
        // Scroll the picture partly past the scroll view's top edge.
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -250)))
        XCTAssertEqual(yellowPixels(app, outside: scrollView.frame), 0, "the scrolled viewfinder shows outside the scroll view")
    }

    /// In right-to-left layout the viewfinder, drawn behind the interface, fills the picture's
    /// frame and nothing else. Beside the control column (iPad) it was drawn a column's width
    /// to the left, under the column, which left the picture's right edge black; the warning
    /// chips then crossed the picture's edge, and their contrast audit failed on some runs.
    @MainActor
    func testViewfinderFillsThePictureRightToLeft() throws {
        let app = launch("manual", extraArguments: Self.rightToLeft + ["-NopeSimulatedViewfinder", "yellow"])
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 20))
        let viewfinder = app.otherElements["Viewfinder"]
        XCTAssertTrue(viewfinder.waitForExistence(timeout: 5))
        let frame = viewfinder.frame
        XCTAssertEqual(yellowPixels(app, outside: frame), 0, "the viewfinder shows outside the picture's frame")
        // Halfway down, just inside each side edge, where no control is drawn over the picture.
        XCTAssertTrue(isYellow(app, at: CGPoint(x: frame.minX + 8, y: frame.midY)), "the picture's left edge isn't the viewfinder")
        XCTAssertTrue(isYellow(app, at: CGPoint(x: frame.maxX - 8, y: frame.midY)), "the picture's right edge isn't the viewfinder")
    }

    /// Whether the screen is pure yellow (the simulated yellow viewfinder) at a point.
    @MainActor
    private func isYellow(_ app: XCUIApplication, at point: CGPoint) -> Bool {
        let image = XCUIScreen.main.screenshot().image
        guard let pixels = Pixels(image) else { return false }
        let (red, green, blue) = pixels.color(x: Int(point.x * image.scale), y: Int(point.y * image.scale))
        return red > 200 && green > 200 && blue < 60
    }

    /// Counts sampled pure yellow pixels (the simulated yellow viewfinder) outside a frame, or
    /// -1 when the screenshot can't be read.
    @MainActor
    private func yellowPixels(_ app: XCUIApplication, outside frame: CGRect) -> Int {
        settle()
        let image = XCUIScreen.main.screenshot().image
        guard let pixels = Pixels(image) else { return -1 }
        let scale = image.scale
        let size = app.windows.firstMatch.frame.size
        // A point's margin inside the frame's edges, for anti-aliasing.
        let inside = frame.insetBy(dx: -1, dy: -1)
        var count = 0
        for y in stride(from: CGFloat(0), to: size.height, by: 4) {
            for x in stride(from: CGFloat(0), to: size.width, by: 4) where !inside.contains(CGPoint(x: x, y: y)) {
                let (red, green, blue) = pixels.color(x: Int(x * scale), y: Int(y * scale))
                if red > 200, green > 200, blue < 60 { count += 1 }
            }
        }
        return count
    }

    /// Closes Q, the quick menu that replaced the quick-controls tray, if it is open.
    @MainActor
    func closeTray(_ app: XCUIApplication) {
        let quick = quickMenuButton(app)
        guard quick.exists, quick.isSelected else { return }
        quick.tap()
        _ = app.descendants(matching: .any)["quickMenu"].waitForNonExistence(timeout: 5)
    }

    /// Counts sampled pixels of a screenshot that match a test.
    @MainActor
    private func countPixels(
        _ app: XCUIApplication, outside excluded: CGRect, matching test: (Int, Int, Int) -> Bool
    ) -> Int {
        settle()
        let image = XCUIScreen.main.screenshot().image
        guard let pixels = Pixels(image) else { return -1 }
        let scale = image.scale
        var count = 0
        let size = app.windows.firstMatch.frame.size
        for y in stride(from: Self.statusBarHeight, to: size.height - Self.homeIndicatorHeight, by: 4) {
            for x in stride(from: CGFloat(0), to: size.width, by: 4) where !excluded.contains(CGPoint(x: x, y: y)) {
                let (red, green, blue) = pixels.color(x: Int(x * scale), y: Int(y * scale))
                if test(red, green, blue) { count += 1 }
            }
        }
        return count
    }

    /// The color class of the pixel at the center of a frame.
    @MainActor
    func centerColor(_ app: XCUIApplication, of frame: CGRect) -> PixelColor {
        let image = XCUIScreen.main.screenshot().image
        guard let pixels = Pixels(image) else { return .other }
        let (red, green, blue) = pixels.color(x: Int(frame.midX * image.scale), y: Int(frame.midY * image.scale))
        if min(red, green, blue) > 230 { return .white }
        if red > 230 && max(green, blue) < 24 { return .red }
        return .other
    }
}

/// A screenshot's pixels as 8-bit sRGB, for sampling colors.
private struct Pixels {
    /// The bytes, four per pixel (red, green, blue, alpha).
    let bytes: [UInt8]
    /// The width in pixels.
    let width: Int
    /// The height in pixels.
    let height: Int

    /// Draws the image into an sRGB bitmap.
    ///
    /// - Parameter image: The screenshot.
    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
        self.width = width
        self.height = height
    }

    /// The color at a pixel, clamped to the image.
    ///
    /// - Parameters:
    ///   - x: The column, from the left.
    ///   - y: The row, from the top.
    func color(x: Int, y: Int) -> (Int, Int, Int) {
        let index = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
    }
}
