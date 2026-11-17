import XCTest

/// UI tests for the 1.0.0 button types (docs/design/BUILD-SPEC.md, section 8, chunk 0). The types
/// are audited in the app's Debug gallery (`-NopeButtonGallery`), which draws each type in each
/// state, before the camera's views move to them.
extension NopeAppUITests {
    /// Launches the gallery of button types.
    @MainActor
    private func launchButtonGallery(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NopeButtonGallery"] + extraArguments
        app.launchAfterThePreviousRunExits()
        return app
    }

    /// Checks the gallery shows its types, then audits it at its top and at its end.
    @MainActor
    private func auditButtonGallery(_ app: XCUIApplication, checksDynamicType: Bool = true) throws {
        XCTAssertTrue(app.buttons["Switch Camera"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Stop"].exists)
        try audit(app, checksDynamicType: checksDynamicType, checksContrast: false)
        try auditContrastOfEnabledControls(app)
        let last = app.buttons["5×"]
        var swipes = 0
        while !(last.exists && last.isHittable) && swipes < 20 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(last.exists)
        try audit(app, afterScrolling: true, checksDynamicType: checksDynamicType)
    }

    /// Runs the contrast audit and fails on every finding except those on a disabled control.
    ///
    /// The gallery shows each type's disabled state at the token's 40% opacity
    /// (`NopeMotion.disabledOpacity`). WCAG 2.2 exempts text that is "part of an inactive user
    /// interface component" from the contrast minimum (1.4.3), but the audit reports it ("Contrast
    /// nearly passed"); every enabled state is held to the full check. The findings are judged
    /// after the audit, because querying the app from inside its handler can make it time out.
    @MainActor
    private func auditContrastOfEnabledControls(_ app: XCUIApplication) throws {
        settle()
        var issues: [XCUIAccessibilityAuditIssue] = []
        try app.performAccessibilityAudit(for: .contrast) { issue in
            issues.append(issue)
            return true
        }
        for issue in issues where issue.element?.isEnabled != false {
            XCTFail("\(issue.compactDescription): \(issue.element?.debugDescription ?? "no element")")
        }
    }

    @MainActor
    func testButtonTypesPassAccessibilityAudits() throws {
        let app = launchButtonGallery()
        try auditButtonGallery(app)
        app.terminate()

        let large = launchButtonGallery(Self.largestTextSize)
        try auditButtonGallery(large)
        large.terminate()

        let rightToLeft = launchButtonGallery(Self.rightToLeft)
        try auditButtonGallery(rightToLeft, checksDynamicType: false)
        rightToLeft.terminate()

        let night = launchButtonGallery(["-NopeButtonGallery.night", "YES"])
        try auditButtonGallery(night, checksDynamicType: false)
    }
}
