import AppIntents
import NopeCore

/// "Switch Lens" for Siri and the Shortcuts app (issue #62): opens the app to the camera and
/// switches to a lens, as the lens buttons do.
///
/// The intent holds no rules (AGENTS.md, "Siri and Shortcuts"): it hands
/// ``ShortcutRequest/selectLens(_:)`` to the app's ``ShortcutInbox`` and says the outcome.
/// Switching needs the camera running, so the app opens first.
struct SwitchLensIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Switch Lens", comment: "The name of nope.'s action that switches the camera to another lens, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens nope. and switches the camera to a lens. Needs Assistant Access, in nope. › Settings › Privacy.",
            comment: "Describes nope.'s Switch Lens action in the Shortcuts app. Keep \"nope.\" unchanged."))

    /// Runs in the background first, so a refused or cancelled request never opens the app;
    /// the app opens once the request is allowed (`continueInForeground`; issue #82, device
    /// check 1 in docs/TESTING.md). The camera needs the app in the foreground.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    /// The lens to switch to. Siri asks when the phrase doesn't name one.
    @Parameter(
        title: LocalizedStringResource(
            "Lens", comment: "A setting of nope.'s Take Photo action: which camera to use."))
    var lens: PhotoLens

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// Every gated action needs an unlocked device (issue #82).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// The Assistant Access check (issue #82).
    @Dependency private var gate: AssistantGate

    /// How the action reads in the Shortcuts editor.
    static var parameterSummary: some ParameterSummary {
        Summary("Switch to \(\.$lens)")
    }

    /// Creates the action, for the Shortcuts app.
    init() {}

    /// Hands the request to the camera screen and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let kind = lens.kind
        let answer = await gate.answer(.switchLens, question: AssistantQuestions.switchLens(kind), intent: self, opensApp: true) {
            AssistantAnswer(await inbox.submit(.selectLens(kind)))
        }
        return .result(dialog: IntentDialog(answer.sentence))
    }
}
