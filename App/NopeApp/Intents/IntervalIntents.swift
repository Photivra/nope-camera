import AppIntents
import NopeCore

/// "Start Interval Shooting" for Siri and the Shortcuts app (issue #62): opens the app to the
/// camera and starts an interval series, as Start in Interval Settings does. The series stops
/// after a number of photos or, with a duration, after a time.
///
/// The intent holds no rules (AGENTS.md, "Siri and Shortcuts"): it hands an
/// ``IntervalShortcut`` to the app's ``ShortcutInbox`` and says the outcome. The series is the
/// same as the Interval drive mode's: full-auto photos, or the manual settings while manual
/// controls are on. It runs only while the app is open, with the screen kept awake and dimmed
/// (`SeriesScreenKeeper`), so the app opens first.
struct StartIntervalIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Start Interval Shooting", comment: "The name of nope.'s action that starts a series of photos taken at a fixed interval, in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens nope. and starts a series of photos at a fixed interval. Needs Assistant Access, in nope. › Settings › Privacy.",
            comment: "Describes nope.'s Start Interval Shooting action in the Shortcuts app. Keep \"nope.\" unchanged."))

    /// Runs in the background first, so a refused or cancelled request never opens the app;
    /// the app opens once the request is allowed (`continueInForeground`; issue #82, device
    /// check 1 in docs/TESTING.md). The camera needs the app in the foreground.
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    /// The time between photos in seconds, or `nil` for the interval chosen in Interval Settings.
    @Parameter(
        title: LocalizedStringResource(
            "Seconds Between Photos", comment: "A setting of nope.'s Start Interval Shooting action: the time from one photo to the next, in seconds."),
        // A compile-time constant: IntervalSettings.intervalRange, which also checks the value.
        inclusiveRange: (1, 3600))
    var intervalSeconds: Int?

    /// How many photos, or `nil` for the number chosen in Interval Settings. Without a duration,
    /// the series stops after this number of photos.
    @Parameter(
        title: LocalizedStringResource(
            "Number of Photos", comment: "A setting of nope.'s actions: how many photos to take."),
        // A compile-time constant: IntervalSettings.countRange, which also checks the value.
        inclusiveRange: (2, 999))
    var count: Int?

    /// How long the series runs in minutes, or `nil` to keep the end chosen in Interval
    /// Settings. With a duration the series stops after that time, instead of after a number of
    /// photos; it takes priority over the number of photos.
    @Parameter(
        title: LocalizedStringResource(
            "Duration in Minutes",
            comment: "A setting of nope.'s Start Interval Shooting action: the series stops after this many minutes, instead of after a number of photos."),
        // A compile-time constant: IntervalSettings.durationRange (1 minute to 24 hours) in
        // minutes, which also checks the value.
        inclusiveRange: (1, 1440))
    var durationMinutes: Int?

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// Every gated action needs an unlocked device (issue #82).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// The Assistant Access check (issue #82).
    @Dependency private var gate: AssistantGate

    /// How the action reads in the Shortcuts editor.
    static var parameterSummary: some ParameterSummary {
        Summary("Start interval shooting") {
            \.$intervalSeconds
            \.$count
            \.$durationMinutes
        }
    }

    /// Hands the request to the camera screen and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts, and the number of photos
    ///   saved ("Photos Saved"): 0, since the series saves its photos after it starts.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let series = IntervalShortcut(
            intervalSeconds: intervalSeconds.map(Double.init), count: count,
            durationSeconds: durationMinutes.map { Double($0) * 60 })
        let answer = await gate.answer(
            .startInterval, question: AssistantQuestions.startInterval(series), intent: self, opensApp: true
        ) {
            AssistantAnswer(await inbox.submit(.startInterval(series)))
        }
        return .result(value: answer.photosSaved, dialog: IntentDialog(answer.sentence))
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
            "Stops nope.'s interval series. Photos already taken are kept. Needs Assistant Access, in nope. › Settings › Privacy.",
            comment: "Describes nope.'s Stop Interval Shooting action in the Shortcuts app. Keep \"nope.\" unchanged."))

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// Every gated action needs an unlocked device (issue #82).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// The Assistant Access check (issue #82).
    @Dependency private var gate: AssistantGate

    /// Hands the request to the camera screen, if one is open, and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await gate.answer(.stopInterval, question: AssistantQuestions.stopInterval, intent: self, opensApp: false) {
            AssistantAnswer(await inbox.submit(.stopInterval))
        }
        return .result(dialog: IntentDialog(answer.sentence))
    }
}
