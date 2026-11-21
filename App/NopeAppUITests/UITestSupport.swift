import XCTest

/// Polls a condition until it holds or the time runs out, and says whether it held.
///
/// The deadline is on `ContinuousClock`, the monotonic clock, so a change to the simulator's or
/// test device's time can't cut a wait short or stretch it (issue #124). The condition is checked
/// first, then after each pause, and once more when the time is up. The pause is
/// `Thread.sleep`, not an `XCTWaiter` predicate: a predicate that queries the app from inside the
/// waiter stalled the test runner on CI (``NopeAppUITests/rotate(_:to:file:line:)``).
///
/// ```swift
/// let closed = waitUntil(timeout: .seconds(5)) { !card.exists }
/// XCTAssertTrue(closed)
/// ```
///
/// - Parameters:
///   - timeout: The longest wait.
///   - poll: The pause between checks; 0.2 seconds by default.
///   - condition: The condition, checked on the main actor. It may keep state between checks,
///     such as the last frame it read.
/// - Returns: Whether the condition held before the time ran out.
@MainActor
@discardableResult
func waitUntil(timeout: Duration, poll: Duration = .milliseconds(200), _ condition: () -> Bool) -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        Thread.sleep(forTimeInterval: poll.timeInterval)
    }
    return true
}

extension Duration {
    /// The duration in seconds, for `Thread.sleep(forTimeInterval:)` and the test log.
    var timeInterval: TimeInterval {
        let parts = components
        // `attoseconds` counts 10^-18 seconds.
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

/// Helpers shared by the UI test classes for the slower CI runner (docs/TESTING.md, "UI test
/// shards").
extension XCUIApplication {
    /// The domain and code of the error an accessibility audit throws when it can't finish within
    /// XCTest's time limit ("Audit failed to complete in time").
    private static let auditErrorDomain = "com.apple.xcode.xctest.accessibilityAudit"
    private static let auditTimedOutCode = -56

    /// Every single audit type in `XCUIAccessibilityAuditType.all`, one bit each.
    private static var singleAuditTypes: [XCUIAccessibilityAuditType] {
        let all = XCUIAccessibilityAuditType.all.rawValue
        return (0..<64).compactMap { bit in
            let value = UInt64(1) << UInt64(bit)
            return all & value != 0 ? XCUIAccessibilityAuditType(rawValue: value) : nil
        }
    }

    /// Runs the accessibility audit of the given types and judges each issue it reports: an
    /// issue the handler doesn't ignore fails the test, as with `performAccessibilityAudit(for:_:)`.
    ///
    /// XCTest gives an audit a fixed time and offers no way to set it. On the CI runner a full
    /// audit of a long screen at the largest text size sometimes didn't finish in that time, and
    /// an unfinished audit reports nothing. Then the same checks run again as one smaller audit per
    /// type, each within the limit, so every check still runs; any other error is thrown.
    ///
    /// Issues are judged after the audit, not inside its handler, because querying the app from
    /// inside the handler can make the audit time out. Before the handler sees a contrast issue,
    /// the element's contrast is measured from a screenshot, and the issue is set aside when the
    /// measured ratio is 7:1 or more (``isSetAsideByMeasuredContrast(_:)``; docs/TESTING.md,
    /// "Contrast findings set aside by measurement"). Every other issue reaches the handler.
    ///
    /// - Parameters:
    ///   - types: The audit types.
    ///   - file: The file a failure is reported in.
    ///   - line: The line a failure is reported at.
    ///   - handler: Returns `true` to ignore an issue, as for `performAccessibilityAudit`.
    @MainActor
    func performCompleteAccessibilityAudit(
        for types: XCUIAccessibilityAuditType = .all, file: StaticString = #filePath, line: UInt = #line,
        _ handler: @escaping (XCUIAccessibilityAuditIssue) throws -> Bool
    ) throws {
        var reported: [XCUIAccessibilityAuditIssue] = []
        let collect = { (issue: XCUIAccessibilityAuditIssue) -> Bool in
            reported.append(issue)
            return true
        }
        // Timed on the monotonic clock, as every wait in the UI tests is (issue #124).
        let clock = ContinuousClock()
        let started = clock.now
        do {
            try performAccessibilityAudit(for: types, collect)
        } catch let error as NSError
            where error.domain == Self.auditErrorDomain && error.code == Self.auditTimedOutCode {
            // The test log says which check was slow: XCTest's error doesn't.
            NSLog("Audit of types %llu didn't finish in %.1f s; running one audit per type", types.rawValue, (clock.now - started).timeInterval)
            // The audits per type report every issue again.
            reported.removeAll()
            for type in Self.singleAuditTypes where types.contains(type) {
                let typeStarted = clock.now
                do {
                    try performAccessibilityAudit(for: type, collect)
                } catch {
                    NSLog("Audit of type %llu alone failed after %.1f s", type.rawValue, (clock.now - typeStarted).timeInterval)
                    throw error
                }
                NSLog("Audit of type %llu alone took %.1f s", type.rawValue, (clock.now - typeStarted).timeInterval)
            }
        }
        for issue in reported {
            if isSetAsideByMeasuredContrast(issue) { continue }
            if try handler(issue) { continue }
            XCTFail("\(issue.compactDescription): \(issue.element?.debugDescription ?? "no element")", file: file, line: line)
        }
    }

    /// Launches a new run of the app once the previous one has exited. On the CI runner,
    /// launching right after `terminate()` sometimes waited the whole minute XCTest allows for a
    /// process ID while the previous process was still going away.
    @MainActor
    func launchAfterThePreviousRunExits() {
        let previous = XCUIApplication()
        if previous.state != .notRunning {
            previous.terminate()
            _ = previous.wait(for: .notRunning, timeout: 30)
        }
        launch()
    }
}
