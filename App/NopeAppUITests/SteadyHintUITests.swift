import XCTest

/// UI tests for "Hold it steady or use a tripod." across mode changes, against the simulated
/// backend. The `dimLight` scenario reports one reading, too dark for a handheld shutter, when
/// the camera starts; it reports no new reading after a mode change, so the hint shows again
/// only from a reading taken in the new mode, which this scenario never sends.
extension NopeAppUITests {
    /// Astro gives its own tripod advice, so the hint goes while it is on, and doesn't come back
    /// from the reading taken before it once it is off.
    @MainActor
    func testSteadyHintGivesWayToAstroAndDoesNotLinger() throws {
        let app = launch("dimLight")
        let hint = element(app, containing: "Hold it steady or use a tripod.")
        XCTAssertTrue(hint.waitForExistence(timeout: 20))
        try audit(app)
        driveStripWord(app, "Astro").tap()
        let astro = app.buttons.matching(NSPredicate(format: "label == %@ AND selected == YES", "Astro")).firstMatch
        XCTAssertTrue(astro.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "Astro frames").waitForExistence(timeout: 10))
        XCTAssertFalse(hint.exists)
        try audit(app)
        driveStripWord(app, "Single").tap()
        XCTAssertFalse(element(app, containing: "Astro frames").waitForExistence(timeout: 5))
        XCTAssertFalse(astro.exists)
        XCTAssertFalse(app.buttons["More Manual Controls"].exists, "manual controls go back off")
        XCTAssertFalse(hint.waitForExistence(timeout: 2))
        try audit(app)
    }
}
