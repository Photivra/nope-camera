import XCTest

/// Smoke tests: the app launches, every state on the first screen passes the accessibility
/// audit, and the camera permission flow reaches the ready state.
final class NopeAppUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPermissionFlowPassesAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()

        let allow = app.buttons["Allow Camera Access"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()

        allow.tap()
        XCTAssertTrue(app.staticTexts["Wide"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["RAW"].exists)
        try app.performAccessibilityAudit()
    }
}
