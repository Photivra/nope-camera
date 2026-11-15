import XCTest

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

    /// Runs the accessibility audit of the given types, calling the handler for each issue as
    /// `performAccessibilityAudit(for:_:)` does.
    ///
    /// XCTest gives an audit a fixed time and offers no way to set it. On the CI runner a full
    /// audit of a long screen at the largest text size sometimes didn't finish in that time, and
    /// an unfinished audit reports nothing. Then the same checks run again as one smaller audit per
    /// type, each within the limit, so every check still runs; any other error is thrown.
    ///
    /// - Parameters:
    ///   - types: The audit types.
    ///   - handler: Returns `true` to ignore an issue, as for `performAccessibilityAudit`.
    @MainActor
    func performCompleteAccessibilityAudit(
        for types: XCUIAccessibilityAuditType = .all, _ handler: @escaping (XCUIAccessibilityAuditIssue) throws -> Bool
    ) throws {
        do {
            try performAccessibilityAudit(for: types, handler)
        } catch let error as NSError
            where error.domain == Self.auditErrorDomain && error.code == Self.auditTimedOutCode {
            for type in Self.singleAuditTypes where types.contains(type) {
                try performAccessibilityAudit(for: type, handler)
            }
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
