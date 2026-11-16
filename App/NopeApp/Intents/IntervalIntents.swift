import AppIntents
import NopeCore

/// "Start Interval Shooting" for Siri and the Shortcuts app (issue #62): opens the app to the
/// camera and starts an interval series, as Start in Pro Tools does.
///
/// The intent holds no rules (AGENTS.md, "Siri and Shortcuts"): it hands an
/// ``IntervalShortcut`` to the app's ``ShortcutInbox`` and says the outcome. Interval shooting
/// is part of the manual controls; when they are off, Siri says so and nothing changes. The
/// series runs only while the app is open, with the screen kept awake and dimmed
/// (`SeriesScreenKeeper`), so the app opens first.
struct StartIntervalIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Start Interval Shooting", comment: "The name of nope.'s action that starts a series of photos taken at a fixed interval, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens nope. and starts a series of photos at a fixed interval. Needs Manual Controls on in nope. Settings.",
            comment: "Describes nope.'s Start Interval Shooting action in the Shortcuts app. \"Manual Controls\" is the option's name in Settings. Keep \"nope.\" unchanged."))

    /// The series needs the camera, which runs only in the foreground.
    static let openAppWhenRun = true

    /// The time between photos in seconds, or `nil` for the interval chosen in Pro Tools.
    @Parameter(
        title: LocalizedStringResource(
            "Seconds Between Photos", comment: "A setting of nope.'s Start Interval Shooting action: the time from one photo to the next, in seconds."),
        // A compile-time constant: IntervalSettings.intervalRange, which also checks the value.
        inclusiveRange: (1, 3600))
    var intervalSeconds: Int?

    /// How many photos, or `nil` for the number chosen in Pro Tools.
    @Parameter(
        title: LocalizedStringResource(
            "Number of Photos", comment: "A setting of nope.'s actions: how many photos to take."),
        // A compile-time constant: IntervalSettings.countRange, which also checks the value.
        inclusiveRange: (2, 999))
    var count: Int?

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// How the action reads in the Shortcuts editor.
    static var parameterSummary: some ParameterSummary {
        Summary("Start interval shooting") {
            \.$intervalSeconds
            \.$count
        }
    }

    /// Hands the request to the camera screen and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let series = IntervalShortcut(intervalSeconds: intervalSeconds.map(Double.init), count: count)
        let outcome = await inbox.submit(.startInterval(series))
        return .result(dialog: IntentDialog(ShortcutDialog.message(for: outcome)))
    }
}

/// "Stop Interval Shooting" for Siri and the Shortcuts app (issue #62): stops the running
/// series, as its Stop button does. Every photo already taken is saved.
///
/// It doesn't open the app: when no camera screen is open, no series runs
/// (``ShortcutRequest/outcomeWithoutCameraScreen``).
struct StopIntervalIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Stop Interval Shooting", comment: "The name of nope.'s action that stops a running series of interval photos, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Stops nope.'s interval series. Photos already taken are kept.",
            comment: "Describes nope.'s Stop Interval Shooting action in the Shortcuts app. Keep \"nope.\" unchanged."))

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// Hands the request to the camera screen, if one is open, and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await inbox.submit(.stopInterval)
        return .result(dialog: IntentDialog(ShortcutDialog.message(for: outcome)))
    }
}
