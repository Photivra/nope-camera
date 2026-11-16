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
            "Opens nope. and turns on the steady light. It turns off when nope. closes.",
            comment: "Describes nope.'s Turn On the Light action in the Shortcuts app. The light is the torch beside the camera. Keep \"nope.\" unchanged."))

    /// The light needs the camera, which runs only in the foreground.
    static let openAppWhenRun = true

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// Hands the request to the camera screen and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await inbox.submit(.setLight(isOn: true))
        return .result(dialog: IntentDialog(ShortcutDialog.message(for: outcome)))
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
            "Turns off nope.'s steady light.",
            comment: "Describes nope.'s Turn Off the Light action in the Shortcuts app. The light is the torch beside the camera. Keep \"nope.\" unchanged."))

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// Hands the request to the camera screen, if one is open, and says the light is off.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await inbox.submit(.setLight(isOn: false))
        return .result(dialog: IntentDialog(ShortcutDialog.message(for: outcome)))
    }
}
