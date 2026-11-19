import XCTest

/// UI test for the Standard File Tags switch in Details in Each Photo (owner decision
/// 2026-11-16): on by default, outside "Remove All Optional Details", with an accessibility audit.
extension NopeAppUITests {
    @MainActor
    func testStandardFileTagsAreOnByDefaultAndCanBeTurnedOff() throws {
        let app = launch("denied")
        openSettings(app)
        let details = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Details in Each Photo")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        details.tap()
        let tags = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Standard File Tags")).firstMatch
        var swipes = 0
        while !(tags.exists && tags.isHittable) && swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(tags.exists)
        XCTAssertEqual(tags.value as? String, "1")
        XCTAssertTrue(tags.label.contains(deviceText("Nothing in them identifies you or your phone", iPad: "Nothing in them identifies you or your iPad")), tags.label)
        // The master switch is on, and the standard tags stay on with it.
        tags.switches.firstMatch.tap()
        XCTAssertEqual(tags.value as? String, "0")
        try audit(app, afterScrolling: swipes > 0, checksDynamicType: false, checksContrast: !isPad)
    }
}
