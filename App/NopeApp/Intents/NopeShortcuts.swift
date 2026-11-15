import AppIntents

/// The app's App Shortcuts: the Siri phrases that work without setting anything up (issue #62).
///
/// Each phrase names the app through `.applicationName`, as App Intents requires. The phrases
/// are localized in all launch languages in `AppShortcuts.xcstrings`.
struct NopeShortcuts: AppShortcutsProvider {
    /// Take a photo (optionally in 3 or 10 seconds), and night mode on or off.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TakePhotoIntent(),
            phrases: [
                "Take a photo with \(.applicationName)",
                "Take a picture with \(.applicationName)",
                "Take a photo in \(\.$delay) with \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource(
                "Take Photo", comment: "The name of nope.'s action that takes a photo, in the Shortcuts app and Siri."),
            systemImageName: "camera")
        AppShortcut(
            intent: SetNightModeIntent(isOn: true),
            phrases: ["Turn on night mode in \(.applicationName)"],
            shortTitle: LocalizedStringResource(
                "Night Mode On", comment: "The name of the shortcut that turns nope.'s night mode on, in the Shortcuts app."),
            systemImageName: "moon")
        AppShortcut(
            intent: SetNightModeIntent(isOn: false),
            phrases: ["Turn off night mode in \(.applicationName)"],
            shortTitle: LocalizedStringResource(
                "Night Mode Off", comment: "The name of the shortcut that turns nope.'s night mode off, in the Shortcuts app."),
            systemImageName: "moon.fill")
    }
}
