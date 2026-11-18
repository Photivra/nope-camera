import XCTest

/// UI tests for the hand-off from the launch screen to the camera (docs/design/LAUNCH-SCREEN.md,
/// 6.3 and 8): during the camera's first start the app draws the launch screen's mark at the
/// window's center on black, with "Starting the camera…" under it and no spinner, in the light
/// and the dark appearance, in night mode, at the largest text size and right to left; when the
/// first start ends the mark is gone, and it stays gone.
///
/// They use the `slowStart` scenario, whose camera stays starting until the app first goes to
/// the background. A UI test can't capture the launch screen itself, which iOS draws before the
/// app runs; docs/TESTING.md, "Launch screen", has the checks by hand.
extension NopeAppUITests {
    /// The first start's indicator.
    @MainActor
    func startIndicator(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["startIndicator"]
    }

    /// Launches the slow-start scenario and waits for the ready camera under the indicator.
    @MainActor
    func launchSlowStart(_ extraArguments: [String] = [], file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = launch("slowStart", extraArguments: extraArguments)
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 20), "the camera isn't ready", file: file, line: line)
        XCTAssertTrue(startIndicator(app).waitForExistence(timeout: 5), "no first start indicator", file: file, line: line)
        return app
    }

    /// Asserts what the first start shows: one element "Starting the camera…", no spinner, and
    /// the mark's frame, 78 × 54 points, centered across the window and 3 points above its
    /// center, within a point (the screenshot's pixels).
    @MainActor
    func assertFirstStart(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let indicator = startIndicator(app)
        XCTAssertEqual(indicator.label, "Starting the camera…", file: file, line: line)
        XCTAssertEqual(app.activityIndicators.count, 0, "a spinner shows during the first start", file: file, line: line)
        let window = app.windows.firstMatch.frame
        guard let box = LaunchPixels.screen()?.litBox(around: CGPoint(x: window.midX, y: window.midY)) else {
            XCTFail("no mark at the window's center", file: file, line: line)
            return
        }
        XCTAssertEqual(box.width, 78, accuracy: 1, "the mark's width", file: file, line: line)
        XCTAssertEqual(box.height, 54, accuracy: 1, "the mark's height", file: file, line: line)
        XCTAssertEqual(box.midX, window.midX, accuracy: 1, "the mark isn't centered across the window", file: file, line: line)
        XCTAssertEqual(box.midY, window.midY - 3, accuracy: 1, "the mark isn't 3 points above the window's center", file: file, line: line)
        // The words are under the mark, inside the window.
        let indicatorFrame = indicator.frame
        XCTAssertGreaterThanOrEqual(indicatorFrame.minX, window.minX - 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(indicatorFrame.maxX, window.maxX + 0.5, file: file, line: line)
    }

    /// Asserts that the picture is black outside the indicator and the controls drawn over it
    /// (the format status and the drive strip in the iPad's full-window picture): no pixel
    /// brighter than a sixteenth of full scale.
    @MainActor
    func assertPictureIsBlack(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        settle()
        let picture = app.otherElements["Viewfinder"].frame
        XCTAssertFalse(picture.isEmpty, "no picture", file: file, line: line)
        guard let pixels = LaunchPixels.screen() else {
            XCTFail("the screenshot couldn't be read", file: file, line: line)
            return
        }
        let indicator = startIndicator(app)
        var excluded = indicator.exists ? [indicator.frame] : []
        for query in [app.buttons, app.staticTexts, app.images] {
            excluded += query.allElementsBoundByIndex.map(\.frame).filter { $0.intersects(picture) }
        }
        let count = pixels.litCount(in: picture.insetBy(dx: 2, dy: 2), outside: excluded.map { $0.insetBy(dx: -4, dy: -4) })
        XCTAssertEqual(count, 0, "the picture isn't black", file: file, line: line)
    }

    /// In the light appearance the first start is the launch screen's black with its mark, the
    /// status bar's content is white, and the screen passes the audit.
    @MainActor
    func testFirstStartIsBlackWithTheMarkInTheLightAppearance() throws {
        useAppearance(.light)
        let app = launchSlowStart()
        assertFirstStart(app)
        assertPictureIsBlack(app)
        XCTAssertLessThan(lightShare(app), 0.1, "the screen isn't black")
        XCTAssertGreaterThan(LaunchPixels.screen()?.lightCount(inTop: 44) ?? 0, 0, "the status bar's content isn't white")
        XCTAssertFalse(app.buttons["Settings"].exists && !isPad, "a Settings button shows over the starting camera")
        try audit(app)
    }

    /// In night mode the first start is red on black from the first frame, the mark included.
    @MainActor
    func testFirstStartIsRedInNightMode() throws {
        let app = launchSlowStart(Self.nightModeOn)
        assertFirstStart(app)
        XCTAssertEqual(nonRedPixels(app, outside: .zero), 0, "white, green or blue shows during the first start")
        try audit(app)
    }

    /// At the largest text size the words wrap under the mark, which stays at the window's
    /// center over the scrolling layout; right to left, in the dark appearance, changes nothing
    /// about its place.
    @MainActor
    func testFirstStartAtTheLargestTextSizeAndRightToLeft() throws {
        let large = launchSlowStart(Self.largestTextSize)
        assertFirstStart(large)
        try auditScrollingScreen(large)
        large.terminate()

        useAppearance(.dark)
        let rightToLeft = launchSlowStart(Self.rightToLeft)
        assertFirstStart(rightToLeft)
        assertPictureIsBlack(rightToLeft)
        try audit(rightToLeft)
    }

    /// While the camera's first start is slow, the shutter and Q are there under the indicator,
    /// whole, inside the window, drawn and usable, in the iPhone's stacked layout and the iPad's
    /// column. On iPad the indicator's plate spanned the window and hid the shutter and the lower
    /// half of Q (second review of 1.0.0); their frames were still right, so the lower half of
    /// each is checked for lit pixels too (the shutter's white ring, Q's letter).
    @MainActor
    func testFirstStartKeepsTheControlsWhole() throws {
        let app = launchSlowStart()
        settle()
        let window = app.windows.firstMatch.frame
        let pixels = LaunchPixels.screen()
        XCTAssertNotNil(pixels, "the screenshot couldn't be read")
        for name in ["Take Photo", "Quick Menu"] {
            let button = app.buttons[name]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "no \(name)")
            let frame = button.frame
            XCTAssertTrue(window.contains(frame), "\(name) isn't whole inside the window: \(frame) in \(window)")
            XCTAssertGreaterThanOrEqual(frame.width, 44, name)
            XCTAssertGreaterThanOrEqual(frame.height, 44, name)
            XCTAssertTrue(button.isHittable, "\(name) can't be pressed")
            let lowerHalf = CGRect(x: frame.minX, y: frame.midY, width: frame.width, height: frame.height / 2)
            XCTAssertGreaterThan(pixels?.litCount(in: lowerHalf, outside: []) ?? 0, 0, "the lower half of \(name) isn't drawn")
        }
        XCTAssertTrue(startIndicator(app).exists, "the first start ended during the test")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "First start, controls"
        add(shot)
    }

    /// When the camera runs the indicator fades and the picture stays black in the light
    /// appearance; it doesn't come back after the app goes to the background and returns, or
    /// after a lens change, when the spinner is used as before.
    @MainActor
    func testFirstStartIndicatorEndsAndStaysGone() throws {
        useAppearance(.light)
        let app = launchSlowStart()
        // The scenario's camera starts when the app first goes to the background.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(startIndicator(app).waitForNonExistence(timeout: 10), "the indicator didn't end")
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        XCTAssertLessThan(lightShare(app), 0.1, "the camera isn't black after the first start")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 10))
        XCTAssertFalse(startIndicator(app).exists, "the indicator came back after the background")

        let ultraWide = app.buttons["Ultra Wide"]
        XCTAssertTrue(ultraWide.waitForExistence(timeout: 10))
        ultraWide.tap()
        XCTAssertTrue(ultraWide.waitForSelection(), "the lens didn't change")
        XCTAssertFalse(startIndicator(app).exists, "the indicator came back after a lens change")
    }

    /// On first run the indicator ends when the statements show, and no Settings button is drawn
    /// before them.
    @MainActor
    func testFirstRunEndsTheFirstStart() throws {
        let app = launch("allow")
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 10))
        XCTAssertTrue(startIndicator(app).waitForNonExistence(timeout: 5), "the indicator shows over first run")
        XCTAssertTrue(app.buttons["Settings"].exists, "first run has no Settings button")
    }
}

extension XCUIElement {
    /// Waits up to five seconds for the element to be selected.
    @MainActor
    fileprivate func waitForSelection() -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !isSelected && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        return isSelected
    }
}

/// A screenshot's pixels as 8-bit sRGB, for the launch hand-off's checks.
private struct LaunchPixels {
    /// The bytes, four per pixel (red, green, blue, alpha).
    let bytes: [UInt8]
    /// The width in pixels.
    let width: Int
    /// The height in pixels.
    let height: Int
    /// Pixels per point.
    let scale: CGFloat

    /// A brightness, out of 255, above which a pixel counts as lit: a sixteenth of full scale.
    static let litThreshold = 16

    /// The current screen.
    @MainActor
    static func screen() -> LaunchPixels? {
        let image = XCUIScreen.main.screenshot().image
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
        return LaunchPixels(bytes: bytes, width: width, height: height, scale: image.scale)
    }

    /// The brightest channel of a pixel.
    private func brightness(column: Int, row: Int) -> Int {
        let index = (min(max(row, 0), height - 1) * width + min(max(column, 0), width - 1)) * 4
        return max(Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
    }

    /// The bounding box, in points, of the lit pixels near a point: from 70 points to each side,
    /// 60 points above and 36 below, which holds the mark's frame (39 to each side, 30 above and
    /// 24 below the window's center) and not the words (40 below). `nil` when nothing is lit.
    func litBox(around center: CGPoint) -> CGRect? {
        let area = CGRect(x: center.x - 70, y: center.y - 60, width: 140, height: 96)
        var minColumn = Int.max, maxColumn = Int.min, minRow = Int.max, maxRow = Int.min
        for row in Int(area.minY * scale)..<Int(area.maxY * scale) {
            for column in Int(area.minX * scale)..<Int(area.maxX * scale)
            where brightness(column: column, row: row) > Self.litThreshold * 4 {
                minColumn = min(minColumn, column)
                maxColumn = max(maxColumn, column)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
            }
        }
        guard minColumn <= maxColumn else { return nil }
        return CGRect(
            x: CGFloat(minColumn) / scale, y: CGFloat(minRow) / scale, width: CGFloat(maxColumn - minColumn + 1) / scale,
            height: CGFloat(maxRow - minRow + 1) / scale)
    }

    /// Counts the lit pixels in a frame, outside other frames, sampled every point.
    func litCount(in frame: CGRect, outside excluded: [CGRect]) -> Int {
        var count = 0
        for y in stride(from: frame.minY, to: frame.maxY, by: 1) {
            for x in stride(from: frame.minX, to: frame.maxX, by: 1)
            where !excluded.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) {
                if brightness(column: Int(x * scale), row: Int(y * scale)) > Self.litThreshold { count += 1 }
            }
        }
        return count
    }

    /// Counts the light pixels (brighter than 200 of 255 in every channel) in the top band of the
    /// screen, where the status bar is.
    func lightCount(inTop points: CGFloat) -> Int {
        var count = 0
        for row in 0..<min(Int(points * scale), height) {
            for column in 0..<width {
                let index = (row * width + column) * 4
                if min(bytes[index], bytes[index + 1], bytes[index + 2]) > 200 { count += 1 }
            }
        }
        return count
    }
}
