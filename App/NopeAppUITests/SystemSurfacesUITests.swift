import XCTest

/// UI tests for the Live Activity in the 1.0.0 design (docs/design/system.html, BUILD-SPEC.md
/// 3.13, chunk H), in the app's Debug gallery (`-NopeLiveActivityGallery`), which draws the same
/// views as the NopeControls extension. The audits of every layout are in
/// `LiveActivityUITests.swift`; these check the design's measures.
extension NopeAppUITests {
    /// The height, in points, of the tallest Live Activity row with Stop (interval shooting,
    /// paused) at the largest text size, measured on an iPhone 18 Pro Simulator (iOS 27.2) with
    /// release-1.0.0 at 4c4aa6b, before the 1.0.0 tokens and the Stop capsule: from the top of its
    /// title to the bottom of its status lines or Stop. BUILD-SPEC.md 3.13: "the largest Live
    /// Activity row is no taller than today".
    static let largestLiveActivityRowBefore: CGFloat = 722

    /// Launches the gallery of Live Activity layouts.
    ///
    /// - Parameter extraArguments: More launch arguments.
    /// - Returns: The running app.
    @MainActor
    private func launchSystemGallery(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NopeLiveActivityGallery"] + extraArguments
        app.launchAfterThePreviousRunExits()
        return app
    }

    /// The height of the paused interval row: from its title to the lower of its status lines
    /// and Stop.
    ///
    /// - Parameter app: The gallery.
    /// - Returns: The height in points.
    @MainActor
    private func pausedIntervalRowHeight(_ app: XCUIApplication) -> CGFloat {
        let details = element(app, containing: "Paused: 42 of 120 photos taken")
        XCTAssertTrue(details.waitForExistence(timeout: 15))
        let titles = app.staticTexts.matching(NSPredicate(format: "label == %@", "Interval Shooting")).allElementsBoundByIndex
        let title = titles.map(\.frame).filter { $0.maxY <= details.frame.minY + 1 }.max { $0.minY < $1.minY }
        let stops = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Stop")).allElementsBoundByIndex
        let stop = stops.map(\.frame).first { $0.minY < details.frame.maxY && $0.maxY > (title?.minY ?? 0) }
        guard let title else {
            XCTFail("the row's title is above its status lines")
            return .infinity
        }
        return max(details.frame.maxY, stop?.maxY ?? 0) - title.minY
    }

    @MainActor
    func testTheLargestLiveActivityRowIsNoTallerThanBefore() throws {
        let app = launchSystemGallery(Self.largestTextSize)
        let height = pausedIntervalRowHeight(app)
        XCTAssertLessThanOrEqual(height, Self.largestLiveActivityRowBefore, "the row is \(height) points tall")
    }

    @MainActor
    func testTheLiveActivityStopButtonIsACapsuleTarget() throws {
        for arguments in [[], ["-NopeLiveActivityGallery.night", "YES"]] {
            let app = launchSystemGallery(arguments)
            let stop = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Stop")).firstMatch
            XCTAssertTrue(stop.waitForExistence(timeout: 15))
            XCTAssertGreaterThanOrEqual(stop.frame.height, 44, "Stop is at least 44 points high")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = arguments.isEmpty ? "live-activity-lock" : "live-activity-night"
            attachment.lifetime = .keepAlways
            add(attachment)
            try audit(app)
            app.terminate()
        }
    }
}
