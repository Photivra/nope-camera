import AppIntents

/// The app's App Shortcuts: the Siri phrases that work without setting anything up (issue #62).
///
/// Each phrase names the app through `.applicationName`, as App Intents requires. The phrases
/// are localized in all launch languages in `AppShortcuts.xcstrings`.
struct NopeShortcuts: AppShortcutsProvider {
    /// Take a photo (optionally in 3 or 10 seconds), open the camera, switch lenses, the light
    /// and night mode on or off, and interval shooting. Apple allows at most ten App Shortcuts
    /// per app; this lists nine.
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
            intent: OpenCameraIntent(),
            phrases: ["Open the camera in \(.applicationName)"],
            shortTitle: LocalizedStringResource(
                "Open the Camera", comment: "The name of the action that opens nope.'s camera, in the Shortcuts app."),
            systemImageName: "camera.viewfinder")
        AppShortcut(
            intent: SwitchLensIntent(),
            phrases: ["Switch to \(\.$lens) in \(.applicationName)"],
            shortTitle: LocalizedStringResource(
                "Switch Lens", comment: "The name of nope.'s action that switches the camera to another lens, in the Shortcuts app."),
            systemImageName: "camera.aperture")
        AppShortcut(
            intent: TurnOnLightIntent(),
            phrases: ["Turn on the light in \(.applicationName)"],
            shortTitle: LocalizedStringResource(
                "Turn On the Light", comment: "The name of nope.'s action that turns the camera's steady light (the torch) on, in the Shortcuts app."),
            systemImageName: "flashlight.on.fill")
        AppShortcut(
            intent: TurnOffLightIntent(),
            phrases: ["Turn off the light in \(.applicationName)"],
            shortTitle: LocalizedStringResource(
                "Turn Off the Light", comment: "The name of nope.'s action that turns the camera's steady light (the torch) off, in the Shortcuts app."),
            systemImageName: "flashlight.off.fill")
        AppShortcut(
            intent: StartIntervalIntent(),
            phrases: ["Start interval shooting in \(.applicationName)"],
            shortTitle: LocalizedStringResource(
                "Start Interval Shooting", comment: "The name of nope.'s action that starts a series of photos taken at a fixed interval, in the Shortcuts app."),
            systemImageName: "timer")
        AppShortcut(
            intent: StopIntervalIntent(),
            phrases: ["Stop interval shooting in \(.applicationName)"],
            shortTitle: LocalizedStringResource(
                "Stop Interval Shooting", comment: "The name of nope.'s action that stops a running series of interval photos, in the Shortcuts app."),
            systemImageName: "stop.circle")
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
