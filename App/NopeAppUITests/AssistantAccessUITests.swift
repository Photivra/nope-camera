import XCTest

/// Settings › Privacy › Assistant Access (issue #82; `docs/design/assistant-access.md`): the
/// row and its note, the page off and on, Ask First while off, the largest text size, right to
/// left, night mode, search, the Lock Screen camera's read-only row, and the requests sent with
/// the Debug-only simulated shortcut (`SimulatedShortcut`), which go through the same check as
/// the App Intents: the off answer and the refusal card, a cancelled question, the camera's hint
/// and the This Session list, and the tip after five confirmations.
///
/// Most tests use the "denied" scenario, as the other Settings tests do; the camera's hint and
/// cards need the ready camera ("slowSaving", which has an ultra wide lens).
extension NopeAppUITests {
    /// The row's note.
    static let assistantRowNote = "For Siri, Shortcuts and other assistants."

    /// The off answer.
    static let assistantOffAnswer = "Assistant Access is off. You can turn it on in nope. › Settings › Privacy."

    /// Access on, with a question before every action.
    static let assistantOnEveryAction = ["-NopeSettings.assistantAccess", "YES", "-NopeSettings.assistantAsk", "everyAction"]

    /// Access on, with no question.
    static let assistantOnNever = ["-NopeSettings.assistantAccess", "YES", "-NopeSettings.assistantAsk", "never"]

    /// Opens Settings › Assistant Access.
    @MainActor
    func openAssistantAccessPage(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        openSettingsScreen(app, file: file, line: line)
        settingsElement(app, "settings.assistantAccess").tap()
        XCTAssertTrue(app.navigationBars["Assistant Access"].waitForExistence(timeout: 5), file: file, line: line)
    }

    /// The element of an Ask First choice.
    @MainActor
    func askChoice(_ app: XCUIApplication, _ rawValue: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "settings.assistantAccess.ask.\(rawValue)").firstMatch
    }

    /// Whether an element is selected, as VoiceOver reads it.
    @MainActor
    func isSelected(_ element: XCUIElement) -> Bool {
        element.isSelected || (element.value as? String) == "1"
    }

    @MainActor
    func testAssistantAccessRowAndNote() throws {
        let app = launch("denied")
        openSettingsScreen(app)
        let row = settingsElement(app, "settings.assistantAccess")
        XCTAssertTrue(row.exists)
        XCTAssertTrue(row.label.contains("Assistant Access"), row.label)
        XCTAssertTrue(row.label.contains("Off"), row.label)
        XCTAssertTrue(row.label.hasSuffix(Self.assistantRowNote), row.label)
        // Last in the Privacy group: after Sign Each Photo, before the Camera group.
        let sign = settingsElement(app, "settings.signEachPhoto")
        XCTAssertLessThan(sign.frame.minY, row.frame.minY)
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testAssistantAccessPageDefault() throws {
        let app = launch("denied")
        openAssistantAccessPage(app)
        // Off, Every Action selected, the line at the top, and no requests yet.
        XCTAssertTrue(app.staticTexts["settings.assistantAccess.notUsedNow"].exists)
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.exists)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(isSelected(askChoice(app, "everyAction")))
        XCTAssertFalse(isSelected(askChoice(app, "never")))
        XCTAssertTrue(askChoice(app, "everyAction").label.contains("asks before it runs"), askChoice(app, "everyAction").label)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
        XCTAssertTrue(settingsElement(app, "settings.assistantAccess.session.empty").exists)
    }

    @MainActor
    func testAssistantAccessChoicesStayEnabledWhileOff() throws {
        let app = launch("denied")
        openAssistantAccessPage(app)
        let never = askChoice(app, "never")
        XCTAssertTrue(never.isEnabled)
        never.tap()
        XCTAssertTrue(isSelected(never), "a choice made while access is off is kept")
        // Turning access on: no row appears or disappears, except the line at the top.
        flipSwitch(settingsElement(app, "settings.assistantAccess.switch"))
        let line = app.staticTexts["settings.assistantAccess.notUsedNow"]
        waitUntil(timeout: .seconds(5)) { !line.exists }
        XCTAssertFalse(line.exists)
        XCTAssertTrue(askChoice(app, "everyAction").exists)
        XCTAssertTrue(isSelected(never))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let row = settingsElement(app, "settings.assistantAccess")
        XCTAssertTrue(row.label.contains("Never Ask"), row.label)
    }

    @MainActor
    func testAssistantAccessPageOn() throws {
        let app = launch("denied", extraArguments: Self.assistantOnEveryAction)
        openAssistantAccessPage(app)
        XCTAssertFalse(app.staticTexts["settings.assistantAccess.notUsedNow"].exists)
        XCTAssertEqual(app.switches.firstMatch.value as? String, "1")
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testAssistantAccessPageAtTheLargestTextSize() throws {
        let app = launch("denied", extraArguments: Self.largestTextSize)
        openAssistantAccessPage(app)
        settle()
        // The whole audit, judged here: on the iPhone 18 Pro and iPad Pro 11-inch Simulators
        // (iOS 27.2) it reports the switch's title, "Assistant Access", as "Dynamic Type font
        // sizes are partially unsupported" or "Text clipped" wherever it is drawn (beside the
        // switch, or on its own line above it, where it shows whole in the screenshots), and it
        // grows at every text size, which testAssistantAccessTitleGrowsAtEveryTextSize measures.
        // Those two findings on that title are set aside, and on iPad the same two on the
        // switch's explanation, an owner-approved exception (isApprovedAuditException,
        // docs/TESTING.md); every other finding fails, contrast on iPhone included.
        var findings: [String] = []
        let types: XCUIAccessibilityAuditType = isPad ? XCUIAccessibilityAuditType.all.subtracting(.contrast) : .all
        try app.performCompleteAccessibilityAudit(for: types) { issue in
            let isTitle = issue.element?.label == "Assistant Access" && [.dynamicType, .textClipped].contains(issue.auditType)
            if !isTitle, !self.isApprovedAuditException(issue) { findings.append("\(issue.compactDescription): \(issue.element?.label ?? "no element") \(issue.element?.frame ?? .zero)") }
            return true
        }
        XCTAssertEqual(findings, [])
        settingsElement(app, "settings.assistantAccess.session.empty")
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    /// The switch's title grows at every text size, measured as the other titles the audit
    /// misreports are (`testChooseDetailsTextGrowsAtEveryTextSize`).
    @MainActor
    func testAssistantAccessTitleGrowsAtEveryTextSize() throws {
        let categories = [
            "L", "XL", "XXL", "XXXL", "AccessibilityM", "AccessibilityL", "AccessibilityXL", "AccessibilityXXL",
            "AccessibilityXXXL",
        ]
        var previous: CGFloat?
        for category in categories {
            let app = launch("denied", extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategory" + category])
            openAssistantAccessPage(app)
            let row = settingsElement(app, "settings.assistantAccess.switch")
            XCTAssertTrue(row.exists, category)
            // The row's height: the title, the switch and the explanation, all growing.
            let height = row.frame.height
            if let previous { XCTAssertGreaterThan(height, previous, "the row isn't taller at \(category)") }
            previous = height
            app.terminate()
        }
    }

    @MainActor
    func testAssistantAccessPageRightToLeft() throws {
        let app = launch("denied", extraArguments: Self.rightToLeft)
        openAssistantAccessPage(app)
        // Mirrored: the switch is on the leading (left) side of its row.
        let row = settingsElement(app, "settings.assistantAccess.switch")
        let toggle = row.switches.firstMatch.exists ? row.switches.firstMatch : app.switches.firstMatch
        XCTAssertLessThan(toggle.frame.midX, app.windows.firstMatch.frame.midX)
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testAssistantAccessPageInNightModeIsAllRed() throws {
        let app = launch("denied", extraArguments: ["-NopeSettings.isNightModeOn", "YES"])
        openAssistantAccessPage(app)
        settle()
        // The back button is the system's glass, outside night mode's reach on every pushed
        // Settings page (as on Fast Shutter); the iPad window corner is left out by the count.
        let back = app.navigationBars.buttons.element(boundBy: 0).frame.insetBy(dx: -6, dy: -6)
        let pixels = nonRedPixels(app, outside: back)
        if pixels != 0 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Assistant Access page, night mode"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertEqual(pixels, 0, "white, blue or other colors remain on the Assistant Access page")
        try audit(app, checksDynamicType: false, checksContrast: !isPad)
    }

    @MainActor
    func testSettingsSearchFindsAssistantAccessByKeyword() throws {
        for word in ["siri", "shortcuts"] {
            let app = launch("denied")
            openSettingsScreen(app)
            searchSettings(app, for: word)
            let result = app.buttons["settings.search.settings.assistantAccess"]
            XCTAssertTrue(result.waitForExistence(timeout: 5), word)
            result.tap()
            XCTAssertTrue(app.navigationBars["Assistant Access"].waitForExistence(timeout: 5), word)
        }
    }

    @MainActor
    func testAssistantAccessIsReadOnlyInTheLockScreenCamera() throws {
        let app = launch("denied", extraArguments: ["-NopeSimulatedLockScreenCamera"] + Self.assistantOnNever)
        openSettingsScreen(app)
        let row = settingsElement(app, "settings.assistantAccess")
        XCTAssertTrue(row.exists)
        XCTAssertTrue(row.label.contains("Never Ask"), row.label)
        XCTAssertTrue(row.label.hasSuffix("Unlock to change."), row.label)
        // Not a link: tapping it opens nothing.
        XCTAssertFalse(row.elementType == .button && row.isEnabled && row.label.contains(Self.assistantRowNote))
        row.tap()
        XCTAssertFalse(app.navigationBars["Assistant Access"].waitForExistence(timeout: 2))
        try audit(app, afterScrolling: true, checksDynamicType: false, checksContrast: !isPad)
    }

    // MARK: Requests through the check

    /// Launches the ready camera with simulated requests and the given arguments.
    @MainActor
    func launchAssistantRequests(_ requests: String, _ arguments: [String]) -> XCUIApplication {
        launch("slowSaving", extraArguments: ["-NopeSimulatedShortcut", requests] + arguments)
    }

    /// What Siri would say, once the requests end.
    @MainActor
    func assistantAnswer(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["SimulatedShortcutResult"]
    }

    @MainActor
    func testEveryActionIsRefusedWhileAccessIsOff() throws {
        // Take Photo, a burst, a bracket, Switch Lens, Apply Preset and Start Interval Shooting.
        let app = launchAssistantRequests("0,burst2,bracket3,lens-ultraWide,preset-factory,interval", [])
        let answer = assistantAnswer(app)
        XCTAssertTrue(answer.waitForExistence(timeout: 30))
        XCTAssertEqual(answer.label, Self.assistantOffAnswer)
        // All six were refused, and none took a photo or changed the lens.
        let card = app.descendants(matching: .any).matching(identifier: "assistant.refusalCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, containing: "refused 6 requests since it opened").exists)
        XCTAssertFalse(app.descendants(matching: .any)["Last Photo"].exists, "no photo was taken")
        XCTAssertFalse(app.staticTexts["Interval shooting started."].exists)
        try audit(app, checksDynamicType: false, checksContrast: false)
        // Settings opens the page, where each request is listed as refused.
        app.buttons["assistant.refusalCard.settings"].tap()
        XCTAssertTrue(app.navigationBars["Assistant Access"].waitForExistence(timeout: 5))
        let line = settingsElement(app, "settings.assistantAccess.session.line")
        XCTAssertTrue(line.exists)
        XCTAssertEqual(line.label, "Start Interval Shooting. Refused.")
        // The list is lazy: only the lines on screen exist, so the card's count above is the
        // check that all six were refused.
    }

    @MainActor
    func testTheRefusalCardClosesUntilTheNextRefusal() throws {
        let app = launchAssistantRequests("lens-ultraWide", [])
        let card = app.descendants(matching: .any).matching(identifier: "assistant.refusalCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        XCTAssertTrue(element(app, containing: "refused 1 request since it opened.").exists, "the singular")
        app.buttons["assistant.refusalCard.close"].tap()
        waitUntil(timeout: .seconds(5)) { !card.exists }
        XCTAssertFalse(card.exists)
    }

    @MainActor
    func testACancelledQuestionChangesNothing() throws {
        let app = launchAssistantRequests(
            "lens-ultraWide", Self.assistantOnEveryAction + ["-NopeSimulatedAssistantAnswer", "cancel"])
        let answer = assistantAnswer(app)
        XCTAssertTrue(answer.waitForExistence(timeout: 30))
        // The system answers a cancelled question; the app adds no answer of its own (issue #126).
        XCTAssertEqual(answer.label, "No answer: the question was canceled.")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "assistant.notice").firstMatch.exists)
        openAssistantAccessPage(app)
        let line = settingsElement(app, "settings.assistantAccess.session.line")
        XCTAssertEqual(line.label, "Switch Lens. Asked, canceled.")
    }

    @MainActor
    func testAnActionThatRanIsShownOnTheCameraAndListed() throws {
        let app = launchAssistantRequests("lens-ultraWide", Self.assistantOnEveryAction)
        let answer = assistantAnswer(app)
        XCTAssertTrue(answer.waitForExistence(timeout: 30))
        XCTAssertEqual(answer.label, "Now using the ultra wide camera.")
        let notice = app.descendants(matching: .any).matching(identifier: "assistant.notice").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("Siri or Shortcuts"), notice.label)
        XCTAssertTrue(notice.label.contains("Now using the ultra wide camera."), notice.label)
        try audit(app, checksDynamicType: false, checksContrast: false)
        openAssistantAccessPage(app)
        let line = settingsElement(app, "settings.assistantAccess.session.line")
        XCTAssertEqual(line.label, "Switch Lens. Asked, allowed.")
    }

    /// The hint never leaves on a timer (ACCESSIBILITY.md; third review of 1.0.0, S7): it is
    /// still there after longer than the old 12 seconds, Close closes it, and on a second launch
    /// the next action on the camera closes it.
    @MainActor
    func testTheHintStaysUntilCloseOrTheNextAction() throws {
        let app = launchAssistantRequests("lens-ultraWide", Self.assistantOnEveryAction)
        let notice = app.descendants(matching: .any).matching(identifier: "assistant.notice").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 30))
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Longer than the old timer")], timeout: 14)
        XCTAssertTrue(notice.exists, "the hint left on a timer")
        let close = app.buttons["assistant.notice.close"]
        XCTAssertTrue(close.exists)
        XCTAssertEqual(close.label, "Close")
        close.tap()
        XCTAssertTrue(notice.waitForNonExistence(timeout: 5), "Close didn't close the hint")
        app.terminate()

        let again = launchAssistantRequests("lens-ultraWide", Self.assistantOnEveryAction)
        let hint = again.descendants(matching: .any).matching(identifier: "assistant.notice").firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 30))
        let wide = again.buttons["Wide"]
        XCTAssertTrue(wide.waitForExistence(timeout: 5))
        wide.tap()
        XCTAssertTrue(hint.waitForNonExistence(timeout: 5), "the next action didn't close the hint")
    }

    @MainActor
    func testWithNeverAnActionRunsWithoutAsking() throws {
        let app = launchAssistantRequests("lens-ultraWide", Self.assistantOnNever)
        XCTAssertTrue(assistantAnswer(app).waitForExistence(timeout: 30))
        XCTAssertEqual(assistantAnswer(app).label, "Now using the ultra wide camera.")
        openAssistantAccessPage(app)
        XCTAssertEqual(settingsElement(app, "settings.assistantAccess.session.line").label, "Switch Lens. Ran without asking.")
    }

    @MainActor
    func testTheTipShowsOnceAfterFiveConfirmations() throws {
        let five = Array(repeating: "lens-ultraWide", count: 5).joined(separator: ",")
        let app = launchAssistantRequests(five, Self.assistantOnEveryAction)
        let tip = app.descendants(matching: .any).matching(identifier: "assistant.tip").firstMatch
        XCTAssertTrue(tip.waitForExistence(timeout: 40))
        XCTAssertTrue(element(app, containing: "You’ve confirmed 5 assistant requests.").exists)
        try audit(app, checksDynamicType: false, checksContrast: false)
        app.buttons["assistant.tip.close"].tap()
        waitUntil(timeout: .seconds(5)) { !tip.exists }
        XCTAssertFalse(tip.exists, "closed for good")
    }

    @MainActor
    func testTheCardInNightModeAndAtTheLargestTextSize() throws {
        for arguments in [["-NopeSettings.isNightModeOn", "YES"], Self.largestTextSize] {
            let app = launchAssistantRequests("lens-ultraWide", arguments)
            let card = app.descendants(matching: .any).matching(identifier: "assistant.refusalCard").firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 30))
            XCTAssertTrue(app.buttons["assistant.refusalCard.settings"].exists)
            XCTAssertTrue(app.buttons["assistant.refusalCard.close"].exists)
            if arguments == Self.largestTextSize {
                try auditScrollingScreen(app)
            } else {
                try audit(app, checksDynamicType: false, checksContrast: false)
            }
            app.terminate()
        }
    }
}

