// The Live Activity (issue #64) is shown by the NopeControls widget extension and started by the
// app, so its attributes, its Stop intent and its views are in both (App/Shared). The Lock Screen
// capture extension also builds App/Shared, but has no Live Activity.
#if !NOPE_CAPTURE_EXTENSION
import ActivityKit
import AppIntents
import NopeCore
import SwiftUI

/// The Live Activity that shows a series and its saving on the Lock Screen and in the Dynamic
/// Island. It has no fixed attributes; everything it shows is in its content state,
/// `LiveActivityContent`: counts and status only, never image data, location or metadata.
///
/// It is updated from the device only: the app never asks for a push token
/// (`Activity.request(attributes:content:pushType:)` with no push type), and nothing is sent
/// anywhere (AGENTS.md, "No network").
struct SeriesActivityAttributes: ActivityAttributes {
    /// What the activity shows.
    typealias ContentState = LiveActivityContent
}

/// Stops the interval series or astro run from the Live Activity's Stop button.
///
/// A `LiveActivityIntent` runs in the app's process, not the widget extension's (App Intents,
/// `LiveActivityIntent`), so the app's ``SeriesActivityActions/stop`` does the work; it holds no
/// rules of its own. It isn't offered in the Shortcuts app: it only acts on a Live Activity.
struct StopSeriesIntent: LiveActivityIntent {
    /// The action's name.
    static let title = LocalizedStringResource(
        "Stop Series",
        comment: "The name of the action behind the Stop button on nope.'s Live Activity: stops interval shooting or the night sky helper's frames. Keep \"nope.\" unchanged if it appears.")

    /// What the action does.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Stops nope.'s interval shooting or astro frames. Every photo already taken is saved.",
            comment: "Describes the action behind the Stop button on nope.'s Live Activity. Keep \"nope.\" unchanged."))

    /// Not listed in the Shortcuts app.
    static let isDiscoverable = false

    /// Creates the action.
    init() {}

    /// Stops the series in the app.
    ///
    /// - Returns: An empty result.
    @MainActor
    func perform() async throws -> some IntentResult {
        await SeriesActivityActions.stop?()
        return .result()
    }
}

/// What the Live Activity's buttons do, set by the app when its camera screen starts. In the
/// widget extension it stays `nil`: the intents run in the app.
@MainActor
enum SeriesActivityActions {
    /// Stops the interval series and ends the activity.
    static var stop: (@MainActor () async -> Void)?
}

/// The Live Activity's colors: the system's, or red on black in night mode (issue #61), the same
/// red as the app's night mode.
enum SeriesActivityStyle {
    /// Night mode's red.
    static let nightRed = Color(.sRGB, red: 1, green: 0, blue: 0)

    /// The color of the text and symbols.
    ///
    /// - Parameter content: What the activity shows.
    /// - Returns: The red in night mode, otherwise the system's primary color.
    static func foreground(_ content: LiveActivityContent) -> Color {
        content.isNightMode ? nightRed : .primary
    }
}

/// The symbol for what runs: SF Symbols, labeled with its name for VoiceOver.
struct SeriesActivityIcon: View {
    /// What runs.
    let kind: LiveActivityContent.Kind

    /// The symbol.
    var body: some View {
        Image(systemName: symbolName)
            .accessibilityLabel(SeriesActivityText.title(kind))
    }

    /// The symbol's name.
    private var symbolName: String {
        switch kind {
        case .interval: "timer"
        case .astro: "moon.stars"
        case .burst: "square.stack.3d.down.right"
        case .timer: "clock"
        }
    }
}

/// The Live Activity's localized text. Each function returns a `Text`, so it can be shown and
/// used as a VoiceOver label.
enum SeriesActivityText {
    /// The name of what runs.
    ///
    /// - Parameter kind: What runs.
    /// - Returns: The name.
    static func title(_ kind: LiveActivityContent.Kind) -> Text {
        switch kind {
        case .interval:
            Text("Interval Shooting", comment: "Title on nope.'s Live Activity: a series of photos taken at a fixed interval.")
        case .astro:
            Text("Astro", comment: "Title on nope.'s Live Activity: the night sky helper, which takes a series of single RAW frames.")
        case .burst:
            Text("Burst", comment: "Title on nope.'s Live Activity: a rapid run of single photos.")
        case .timer:
            Text("Self-Timer", comment: "Title on nope.'s Live Activity: the countdown before a photo.")
        }
    }

    /// The main line: what is happening, with the counts.
    ///
    /// - Parameter content: What the activity shows.
    /// - Returns: The line.
    static func status(_ content: LiveActivityContent) -> Text {
        let countdown = countdown(to: content.countdownEnd)
        return switch content.statusLine {
        case .photoIn:
            Text("Photo in \(countdown)", comment: "Live Activity: the self-timer's countdown. The placeholder is the time left, such as 0:07, counted down by the system.")
        case .astroStartsIn:
            Text("First frame in \(countdown)", comment: "Live Activity: the countdown before the night sky helper's first frame. The placeholder is the time left, such as 0:07, counted down by the system.")
        case .takingPhoto:
            Text("Taking the photo…", comment: "Live Activity: the self-timer's photo is being taken.")
        case .photosTaken(let taken, let total):
            Text("\(taken) of \(total) photos taken", comment: "Live Activity: interval shooting progress. Both numbers are counts of photos; the second is at least 2.")
        case .frame(let number, let total):
            Text("Frame \(number) of \(total)", comment: "Live Activity: which frame of the night sky helper's series is being taken, of how many.")
        case .burstPhotosTaken(let taken):
            Text("Photos taken: \(taken)", comment: "Live Activity: how many photos a running burst has taken.")
        case .paused(let taken, let total):
            Text("Paused: \(taken) of \(total) photos taken. Open nope. to continue.", comment: "Live Activity after the person left nope. during interval shooting: the series continues when nope. is opened again. Both numbers are counts of photos. Keep \"nope.\" unchanged.")
        case .framesPaused(let taken, let total):
            Text("Paused: \(taken) of \(total) frames. Open nope. to continue.", comment: "Live Activity after the person left nope. during the night sky helper's frames, or the camera paused them: the run continues when nope. is open again, after its start delay. Both numbers are counts of frames. Keep \"nope.\" unchanged.")
        case .saving(let saved, let taken):
            Text("Saving: \(saved) of \(taken) photos saved", comment: "Live Activity after the person left nope. during a burst or the night sky helper: the photos already taken are being saved. Both numbers are counts of photos.")
        case .savingPhoto:
            Text("Saving the photo…", comment: "Live Activity: the self-timer's photo is being saved.")
        case .savingPaused:
            Text("Saving paused. Open nope. to finish.", comment: "Live Activity: iOS gave nope. no more time in the background before every photo was saved; opening nope. lets it finish. Keep \"nope.\" unchanged.")
        case .seriesDone(let taken, let total):
            Text("Done: \(taken) of \(total) photos taken", comment: "Live Activity: interval shooting finished. Both numbers are counts of photos.")
        case .seriesStopped(let taken, let total):
            Text("Stopped: \(taken) of \(total) photos taken", comment: "Live Activity: interval shooting was stopped early. Both numbers are counts of photos.")
        case .photosSaved(let saved):
            Text("Photos saved: \(saved)", comment: "Live Activity: a burst, the night sky helper or the self-timer finished. The number is how many photos were saved.")
        case .stoppedPhotosSaved(let saved):
            Text("Stopped. Photos saved: \(saved)", comment: "Live Activity: a burst or the night sky helper stopped early, for example because the camera stopped. The number is how many photos were saved.")
        case .noPhotoTaken:
            Text("Stopped. No photo taken.", comment: "Live Activity: the self-timer or the night sky helper's countdown was cancelled before any photo was taken.")
        case .failed:
            Text("A photo wasn't saved. Open nope. for details.", comment: "Live Activity: a photo couldn't be taken or saved; nope. says why. Keep \"nope.\" unchanged.")
        }
    }

    /// The system's countdown, drawn without updates.
    ///
    /// - Parameter end: When the countdown ends, or `nil`.
    /// - Returns: The time left, such as 0:07.
    static func countdown(to end: Date?) -> Text {
        let end = end ?? .now
        return Text(timerInterval: min(Date.now, end)...end, countsDown: true)
    }

    /// The line about signatures. Honesty wording, in the Honesty table: it never implies a
    /// photo is signed when it isn't.
    ///
    /// - Parameter line: The line to show.
    /// - Returns: The line.
    static func signing(_ line: LiveActivitySigningLine) -> Text {
        switch line {
        case .signed:
            Text("Signed.", tableName: "Honesty", comment: "Live Activity, after photos were saved: every saved photo has a Content Credentials signature. Honesty wording: says only that they are signed.")
        case .notSigned:
            Text("Not signed. Open nope. for details.", tableName: "Honesty", comment: "Live Activity, after one photo was saved without a Content Credentials signature; nope. says why. Honesty wording: never imply the photo is signed. Keep \"nope.\" unchanged.")
        case .notAllSigned:
            Text("Not every photo is signed. Open nope. for details.", tableName: "Honesty", comment: "Live Activity, after photos were saved and at least one has no Content Credentials signature; nope. says why. Honesty wording: never imply they are all signed. Keep \"nope.\" unchanged.")
        }
    }
}

/// The Stop button, shown while an interval series runs or is paused.
struct SeriesStopButton: View {
    /// The button, which runs ``StopSeriesIntent`` in the app.
    var body: some View {
        Button(intent: StopSeriesIntent()) {
            Label {
                Text("Stop", comment: "Button on nope.'s Live Activity that stops interval shooting or the night sky helper's frames. Every photo already taken is saved.")
            } icon: {
                Image(systemName: "stop.fill")
            }
        }
        .accessibilityHint(
            Text("Every photo already taken is saved.", comment: "VoiceOver hint of the Stop button on nope.'s Live Activity."))
    }
}

/// The status lines and progress, shared by the Lock Screen and the expanded Dynamic Island.
struct SeriesActivityDetails: View {
    /// What the activity shows.
    let content: LiveActivityContent

    /// The lines.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Lines wrap instead of being cut off at large text sizes or beside Stop.
            SeriesActivityText.status(content)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let line = content.signingLine {
                SeriesActivityText.signing(line)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let progress = content.progress {
                ProgressView(value: progress)
                    .tint(SeriesActivityStyle.foreground(content))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The Lock Screen and banner layout.
struct SeriesActivityLockScreenView: View {
    /// What the activity shows.
    let content: LiveActivityContent

    /// The layout: symbol, title and lines, and Stop when it applies.
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SeriesActivityIcon(kind: content.kind)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                SeriesActivityText.title(content.kind)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                SeriesActivityDetails(content: content)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            if content.canStop {
                SeriesStopButton()
            }
        }
        .padding()
        .foregroundStyle(SeriesActivityStyle.foreground(content))
    }
}

/// The short count beside the Dynamic Island: the countdown, or the number of photos.
struct SeriesActivityCompactCount: View {
    /// What the activity shows.
    let content: LiveActivityContent

    /// The count, labeled with the full status line for VoiceOver.
    var body: some View {
        Group {
            if let end = content.countdownEnd {
                SeriesActivityText.countdown(to: end)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } else if let count = content.compactCount {
                Text(count, format: .number)
                    .monospacedDigit()
            } else {
                Image(systemName: "exclamationmark.triangle")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SeriesActivityText.status(content))
    }
}
#endif
