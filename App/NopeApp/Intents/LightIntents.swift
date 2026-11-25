import AppIntents
import NopeCore

/// "Turn On the Light" for Siri and the Shortcuts app (issue #62): opens the app to the camera
/// and turns the light (the torch) on, as the Light switch in the quick-controls tray does.
///
/// The intent holds no rules (AGENTS.md, "Siri and Shortcuts"). The light works only while the
/// camera runs, and the camera runs only in the foreground (AGENTS.md, "Battery"), so the app
/// opens first; it turns off again when the app leaves the screen.
struct TurnOnLightIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Turn On the Light", comment: "The name of nope.'s action that turns the camera's steady light (the torch) on, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens nope. and turns on the steady light. It turns off when nope. closes. Needs Assistant Access, in nope. › Settings › Privacy.",
            comment: "Describes nope.'s Turn On the Light action in the Shortcuts app. The light is the torch beside the camera. Keep \"nope.\" unchanged."))

    /// Runs in the background first, so a refused or cancelled request never opens the app;
    /// the app opens once the request is allowed (`continueInForeground`; issue #82, device
    /// check 1 in docs/TESTING.md). The camera needs the app in the foreground.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// Every gated action needs an unlocked device (issue #82).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// The Assistant Access check (issue #82).
    @Dependency private var gate: AssistantGate

    /// Hands the request to the camera screen and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = try await gate.answer(.turnOnLight, question: AssistantQuestions.light(isOn: true), intent: self, opensApp: true) {
            AssistantAnswer(await inbox.submit(.setLight(isOn: true)))
        }
        return .result(dialog: IntentDialog(answer.sentence))
    }
}

/// "Turn Off the Light" for Siri and the Shortcuts app (issue #62): turns the light off, as the
/// Light switch does.
///
/// It doesn't open the app: when no camera screen is open, the camera isn't running and the
/// light is already off (``ShortcutRequest/outcomeWithoutCameraScreen``).
struct TurnOffLightIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Turn Off the Light", comment: "The name of nope.'s action that turns the camera's steady light (the torch) off, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Turns off nope.'s steady light. Needs Assistant Access, in nope. › Settings › Privacy.",
            comment: "Describes nope.'s Turn Off the Light action in the Shortcuts app. The light is the torch beside the camera. Keep \"nope.\" unchanged."))

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// Every gated action needs an unlocked device (issue #82).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// The Assistant Access check (issue #82).
    @Dependency private var gate: AssistantGate

    /// Hands the request to the camera screen, if one is open, and says the light is off.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = try await gate.answer(.turnOffLight, question: AssistantQuestions.light(isOn: false), intent: self, opensApp: false) {
            AssistantAnswer(await inbox.submit(.setLight(isOn: false)))
        }
        return .result(dialog: IntentDialog(answer.sentence))
    }
}
