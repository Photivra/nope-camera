import AppIntents
import NopeCore

/// Turns night mode on or off from Siri or the Shortcuts app (issues #61 and #62), with
/// ``NopeSettings/setNightMode(_:)``, as the Night Mode switch in Settings and the tray does.
///
/// It changes only the stored setting, so it runs without opening nope.; the camera screen
/// follows the change when it is open.
struct SetNightModeIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Set Night Mode", comment: "The name of nope.'s action that turns night mode on or off, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Turns nope.'s night mode on or off: every nope. screen in red on black.",
            comment: "Describes nope.'s Set Night Mode action in the Shortcuts app. Keep \"nope.\" unchanged."))

    /// Whether night mode should be on.
    @Parameter(
        title: LocalizedStringResource(
            "Night Mode", comment: "The setting of nope.'s Set Night Mode action: on or off."),
        default: true,
        displayName: Bool.IntentDisplayName(
            true: LocalizedStringResource("On", comment: "Night mode turned on, in nope.'s Set Night Mode action."),
            false: LocalizedStringResource("Off", comment: "Night mode turned off, in nope.'s Set Night Mode action.")))
    var isOn: Bool

    /// The person's settings, the same object the camera screen shows.
    @Dependency private var settings: NopeSettings

    /// How the action reads in the Shortcuts editor.
    static var parameterSummary: some ParameterSummary {
        Summary("Set night mode to \(\.$isOn)")
    }

    /// Creates the action with night mode on, for the Shortcuts app.
    init() {}

    /// Creates the action with a fixed choice, for the App Shortcuts phrases.
    ///
    /// - Parameter isOn: Whether night mode should be on.
    init(isOn: Bool) {
        self.isOn = isOn
    }

    /// Changes the setting and says the new state.
    ///
    /// - Returns: The new state, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        settings.setNightMode(isOn)
        let message =
            isOn
            ? LocalizedStringResource("Night mode is on.", comment: "Siri's answer after nope.'s night mode was turned on.")
            : LocalizedStringResource("Night mode is off.", comment: "Siri's answer after nope.'s night mode was turned off.")
        return .result(dialog: IntentDialog(message))
    }
}
