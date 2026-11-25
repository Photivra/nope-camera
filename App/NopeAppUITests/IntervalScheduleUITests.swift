import XCTest

/// UI tests for interval photos spaced start to start (issue #123): Interval Shooting says that
/// each photo starts one interval after the last, audited
/// at the default size, the largest text size, right to left and in night mode (all red). The
/// running card's "Each photo takes longer than the interval" needs photos slower than the
/// interval, which the simulated camera doesn't take; it is unit tested
/// (`IntervalTimeCardTests`, `IntervalScheduleTests`) and checked on a device (docs/TESTING.md,
/// "Clock and interval series on a device").
extension NopeAppUITests {
    /// The sentence under the rows of Interval Shooting, for the default ten photos; the wording
    /// for a time and for a manual shutter longer than the interval is unit tested.
    @MainActor
    func testIntervalSettingsSayEachPhotoStartsOneIntervalAfterTheLast() throws {
        for arguments in [[], Self.largestTextSize, Self.rightToLeft, Self.nightModeOn] {
            let app = launch("noRAW", extraArguments: arguments)
            XCTAssertTrue(app.otherElements["Viewfinder"].waitForExistence(timeout: 20))
            let viewfinder = app.otherElements["Viewfinder"].frame
            chooseDrive(app, "Interval Shooting")
            XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10))
            let sentence = app.staticTexts["IntervalSchedule"]
            for _ in 0..<6 where !sentence.exists || !sentence.isHittable {
                app.collectionViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(sentence.waitForExistence(timeout: 5))
            XCTAssertEqual(sentence.label, "Takes 10 photos, starting one every 10 seconds.")
            if arguments == Self.largestTextSize {
                try audit(app, afterScrolling: true)
            } else {
                try audit(app, checksDynamicType: false)
            }
            if arguments == Self.nightModeOn {
                // The viewfinder keeps its natural colors behind the sheet; it is left out.
                XCTAssertEqual(nonRedPixels(app, outside: viewfinder), 0, "the sheet is red on black")
            }
            app.terminate()
        }
    }
}
