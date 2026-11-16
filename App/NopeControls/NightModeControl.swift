import AppIntents
import NopeCore
import SwiftUI
import WidgetKit

/// A switch for night mode in Control Center and on the Lock Screen (WidgetKit controls, iOS 18;
/// issues #42 and #61): every nope. screen in red on black.
///
/// It reads and writes the same setting as the Night Mode switch in the app
/// (``NopeSettings/isNightModeOn``), in the App Group's store. After a change the app, if it is
/// open, follows at once (``SharedSettingsSync``), and the Lock Screen camera gets the new value
/// the next time it opens. The app refreshes this control when night mode changes there.
struct NightModeControl: ControlWidget {
    /// The control: the moon symbol, its name and whether night mode is on.
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: NopeControlKind.nightMode, provider: NightModeValueProvider()) { isOn in
            ControlWidgetToggle(isOn: isOn, action: SetNightModeControlIntent()) {
                Label {
                    Text("Night Mode", comment: "The setting of nope.'s Set Night Mode action: on or off.")
                } icon: {
                    Image(systemName: "moon.fill")
                }
            } valueLabel: { isOn in
                isOn
                    ? Text("On", comment: "Night mode turned on, in nope.'s Set Night Mode action.")
                    : Text("Off", comment: "Night mode turned off, in nope.'s Set Night Mode action.")
            }
        }
        .displayName(
            LocalizedStringResource(
                "Night Mode", comment: "The setting of nope.'s Set Night Mode action: on or off."))
        .description(
            LocalizedStringResource(
                "Turns nope.'s night mode on or off: every nope. screen in red on black.",
                comment: "Describes nope.'s Set Night Mode action in the Shortcuts app. Keep \"nope.\" unchanged."))
    }
}

/// Reads whether night mode is on from the App Group's store each time the system shows the
/// control.
struct NightModeValueProvider: ControlValueProvider {
    /// The value in the controls gallery: off, the default.
    var previewValue: Bool { false }

    /// Whether night mode is on now.
    ///
    /// - Returns: The stored setting; off without the App Group.
    @MainActor
    func currentValue() async throws -> Bool {
        guard let store = SharedSettings.store() else { return false }
        return NopeSettings(defaults: store).isNightModeOn
    }
}

/// Turns night mode on or off from the control, with ``NopeSettings/setNightMode(_:)`` on the
/// App Group's store, then tells the app (``SharedSettings/changeSignal``) and hands the new
/// settings to the Lock Screen camera.
///
/// Hidden from the Shortcuts app, which has the app's own Set Night Mode action.
struct SetNightModeControlIntent: SetValueIntent {
    /// The action's name.
    static let title = LocalizedStringResource(
        "Set Night Mode", comment: "The name of nope.'s action that turns night mode on or off, in the Shortcuts app.")

    /// Only the control runs it.
    static let isDiscoverable = false

    /// Whether night mode should be on, set by the system from the switch.
    @Parameter(title: LocalizedStringResource("Night Mode", comment: "The setting of nope.'s Set Night Mode action: on or off."))
    var value: Bool

    /// Changes the setting.
    ///
    /// - Returns: An empty result; the control shows the new state.
    @MainActor
    func perform() async throws -> some IntentResult {
        guard let store = SharedSettings.store() else { return .result() }
        let settings = NopeSettings(defaults: store)
        settings.setNightMode(value)
        SharedSettings.changeSignal?.post()
        await SharedSettings.publishToLockScreenCamera(settings)
        return .result()
    }
}
