import AppIntents
import NopeCore

/// "Open Assistant Access" for the Shortcuts app (issue #82): opens the app's Settings at the
/// Assistant Access page, where the person decides whether assistants may use the app's
/// actions. It changes nothing, so it isn't gated (``AssistantActionKind/opensScreen``) and
/// works while access is off. The app declares no URL scheme; this action is the only link to
/// the page from outside the app (`docs/design/assistant-access.md`, decision 10).
struct OpenAssistantAccessIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Open Assistant Access", comment: "The name of nope.'s action that opens nope.'s Settings at the Assistant Access page, in the Shortcuts app. Assistant Access is the name of the page.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens nope.'s Settings at Assistant Access, where you choose which assistants and Shortcuts can use nope. It changes nothing.",
            comment: "Describes nope.'s Open Assistant Access action in the Shortcuts app. Assistant Access is the name of the page in nope.'s Settings. Keep \"nope.\" unchanged. Draft for the Honesty review."))

    /// The page is in the app, so the app opens.
    static let supportedModes: IntentModes = .foreground(.immediate)

    /// The app's session, which asks the camera screen to open the page.
    @Dependency private var gate: AssistantGate

    /// Asks the camera screen to open Settings at the page.
    ///
    /// - Returns: An empty result.
    @MainActor
    func perform() async throws -> some IntentResult {
        gate.session.requestSettingsPage()
        return .result()
    }
}
