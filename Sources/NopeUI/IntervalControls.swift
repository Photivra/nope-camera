import NopeCore
import SwiftUI

/// The interval, and the number of photos or the time, of interval shooting (issue #48), with
/// Start or Stop: one section, shown in Interval Settings (``IntervalSheet``). The drive strip
/// and its card are the one home of Interval; Pro Tools has no Interval section
/// (docs/design/BUILD-SPEC.md, 3.4).
///
/// A series works in full auto and with manual controls on; `NopeCore` holds the series
/// (`ManualControlsModel.interval` and `ManualControlIntent.startInterval`).
struct IntervalSection: View {
    /// The camera model.
    let model: CameraModel

    /// Runs after Start, such as closing the sheet so the series can be seen.
    let didStart: () -> Void

    /// Creates the section.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - didStart: Runs after Start.
    init(model: CameraModel, didStart: @escaping () -> Void) {
        self.model = model
        self.didStart = didStart
    }

    /// The manual controls model, which holds the series.
    private var manual: ManualControlsModel { model.manual }

    /// The settings in use.
    private var settings: IntervalSettings { manual.interval }

    /// The pickers and the button, with the honesty footer.
    var body: some View {
        // No title row: the sheet's title says "Interval Shooting", and Stop After takes the row
        // the title had, so the form for a number of photos is no taller than before.
        Section {
            Picker(selection: Binding(get: { settings.interval }, set: { send(.setInterval(settings.with(interval: $0))) })) {
                // The listed values, plus the one in use when Siri, Shortcuts or a preset set
                // another, so the picker never shows a blank selection.
                ForEach(settings.intervalChoices, id: \.self) { seconds in
                    Text(verbatim: Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
                        .tag(seconds)
                }
            } label: {
                Text("Interval", bundle: .module, comment: "Picker for the time between photos in interval shooting.")
            }
            stopAfterPicker
            switch settings.stopAfter {
            case .numberOfPhotos: countPicker
            case .time: timeRows
            }
            startOrStop
        } footer: {
            VStack(alignment: .leading, spacing: NopeSpace.xs) {
                if manual.intervalProgress == nil, let blocker = model.intervalBlocker {
                    Self.reason(blocker)
                }
                Text(verbatim: Self.scheduleSentence(settings, shutterIsLonger: manual.isShutterLongerThanInterval))
                    .accessibilityIdentifier("IntervalSchedule")
                if settings.stopAfter == .time {
                    Text(
                        "The time keeps running while the series is paused, so the series ends on time.", bundle: .module,
                        comment: "Explains interval shooting that stops after a time: if nope. leaves the screen or the camera is interrupted, the time still counts, and the series ends at the time it would have ended. Keep \"nope.\" unchanged if used.")
                }
                Text(
                    "Each photo is separate. Nothing is combined. Keep nope. open while the series runs.", tableName: "Honesty",
                    bundle: .module,
                    comment: "Explains interval shooting. Keep \"nope.\" unchanged: it is the app's name. Must not claim more than the English.")
                Text(
                    "Each photo is taken in full auto, or with your manual settings while Manual Controls are on.",
                    bundle: .module,
                    comment: "Explains which exposure the photos of an interval series use. \"Manual Controls\" is the option's name in Settings.")
            }
        }
    }

    /// Number of Photos or Time, on a page of its own, as in Astro Settings: as a menu, the
    /// value "Number of Photos" was cut off at the accessibility text sizes, and the audit found
    /// the text under it didn't follow Dynamic Type at the default size.
    private var stopAfterPicker: some View {
        Picker(
            selection: Binding(get: { settings.stopAfter }, set: { send(.setInterval(settings.with(stopAfter: $0))) })
        ) {
            ForEach(IntervalSettings.StopAfter.allCases, id: \.self) { stopAfter in
                Self.name(of: stopAfter).tag(stopAfter)
            }
        } label: {
            Text("Stop After", bundle: .module, comment: "Picker for what ends an interval series: a number of photos, or a time.")
        }
        .pickerStyle(.navigationLink)
    }

    /// The number of photos, for a series that stops after a number of photos.
    private var countPicker: some View {
        Picker(selection: Binding(get: { settings.count }, set: { send(.setInterval(settings.with(count: $0))) })) {
            ForEach(settings.countChoices, id: \.self) { count in
                Text(verbatim: count.formatted()).tag(count)
            }
        } label: {
            Text("Photos", bundle: .module, comment: "Picker for how many photos an interval series takes.")
        }
    }

    /// The hours and minutes of a series that stops after a time, and the most photos it can take.
    @ViewBuilder private var timeRows: some View {
        Picker(
            selection: Binding(
                get: { settings.durationHours },
                set: { send(.setInterval(settings.with(hours: $0, minutes: settings.durationMinutes))) })
        ) {
            ForEach(IntervalSettings.listedHours, id: \.self) { hours in
                Text(verbatim: hours.formatted()).tag(hours)
            }
        } label: {
            Text("Hours", bundle: .module, comment: "Picker for the whole hours of the time an interval series runs before it stops.")
        }
        Picker(
            selection: Binding(
                get: { settings.durationMinutes },
                set: { send(.setInterval(settings.with(hours: settings.durationHours, minutes: $0))) })
        ) {
            ForEach(IntervalSettings.listedMinutes, id: \.self) { minutes in
                Text(verbatim: minutes.formatted()).tag(minutes)
            }
        } label: {
            Text("Minutes", bundle: .module, comment: "Picker for the minutes, past the whole hours, of the time an interval series runs before it stops.")
        }
        if settings.isIntervalShorterThanTime {
            // A plain row rather than LabeledContent, whose label the audit found doesn't fully
            // follow Dynamic Type in this form.
            HStack(alignment: .firstTextBaseline, spacing: NopeSpace.s) {
                Text("Photos", bundle: .module, comment: "Picker for how many photos an interval series takes.")
                Spacer(minLength: NopeSpace.s)
                Text("At most \(settings.maximumPhotoCount)", bundle: .module, comment: "The most photos an interval series that stops after a time can take: one at the start and one each interval after, while the next start is before the time is up. A photo that takes longer than the interval delays the ones after it, so it can take fewer. The number is a count of photos, at least 2.")
                    // The primary color: the secondary one failed the contrast audit in night mode.
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("IntervalPhotoEstimate")
        }
    }

    /// Start, or Stop while a series runs.
    @ViewBuilder private var startOrStop: some View {
        if manual.intervalProgress == nil {
            Button {
                send(.startInterval)
                didStart()
            } label: {
                Text("Start", bundle: .module, comment: "Button that starts interval shooting.")
            }
            .disabled(!model.canCapture || model.intervalBlocker != nil)
        } else {
            Button(role: .destructive) {
                send(.stopInterval)
            } label: {
                Text("Stop", bundle: .module, comment: "Button that stops interval shooting.")
            }
        }
    }

    /// The name of what ends a series, in the Stop After picker.
    ///
    /// - Parameter stopAfter: What ends the series.
    /// - Returns: "Number of Photos" or "Time".
    static func name(of stopAfter: IntervalSettings.StopAfter) -> Text {
        switch stopAfter {
        case .numberOfPhotos:
            Text("Number of Photos", bundle: .module, comment: "Choice of the Stop After picker of interval shooting: the series stops once it has taken the chosen number of photos.")
        case .time:
            Text("Time", bundle: .module, comment: "Choice of the Stop After picker of interval shooting: the series stops once the chosen hours and minutes have passed.")
        }
    }

    /// The sentence under the rows that says how the photos are spaced: start to start
    /// (issue #123). "Takes 10 photos, starting one every 10 seconds.", or for a series that stops
    /// after a time, "Takes photos for 1 hour, starting one every 10 seconds.". When the shutter
    /// set by hand is longer than the interval, the app knows before the series starts that the
    /// photos can't keep to it, and says so instead (decision 10 of the 1.0.0 plan).
    ///
    /// - Parameters:
    ///   - settings: The series.
    ///   - shutterIsLonger: Whether the manual shutter time is longer than the interval
    ///     (`ManualControlsModel.isShutterLongerThanInterval`).
    /// - Returns: The sentence.
    static func scheduleSentence(_ settings: IntervalSettings, shutterIsLonger: Bool) -> String {
        if shutterIsLonger {
            return String(
                localized: "The shutter time is longer than the interval, so photos follow one another.", table: "Honesty",
                bundle: .module,
                comment: "Under the rows of Interval Shooting, before a series starts, when the shutter time set by hand is longer than the time between photo starts: each photo starts as soon as the one before it is saved, so the photos can't keep to the interval. Must not claim more than the English. Draft for the Honesty review.")
        }
        let interval = ModeCardText.spokenDuration(settings.interval)
        switch settings.stopAfter {
        case .numberOfPhotos:
            return String(
                localized: "Takes \(settings.count) photos, starting one every \(interval).", table: "Honesty", bundle: .module,
                comment: "Under the rows of Interval Shooting: how the series' photos are spaced. Each photo starts one interval after the last one started, however long a photo takes to be taken and saved. The number is a count of photos, at least 2; the placeholder is a duration formatted by the system, such as \"10 seconds\". Must not claim more than the English. Draft for the Honesty review.")
        case .time:
            return String(
                localized: "Takes photos for \(ModeCardText.spokenDuration(settings.duration)), starting one every \(interval).",
                table: "Honesty", bundle: .module,
                comment: "Under the rows of Interval Shooting, for a series that stops after a time: how long it runs and how its photos are spaced. Each photo starts one interval after the last one started. Both placeholders are durations formatted by the system, such as \"1 hour, 30 minutes\" and \"10 seconds\". Must not claim more than the English. Draft for the Honesty review.")
        }
    }

    /// Why Start is unavailable, said beside the disabled button.
    ///
    /// - Parameter blocker: Why a series can't start now.
    /// - Returns: The sentence.
    static func reason(_ blocker: IntervalBlocker) -> Text {
        switch blocker {
        case .astroIsOn:
            Text("Turn off Astro to start interval shooting.", bundle: .module, comment: "Shown under the disabled Start button of interval shooting while the night sky helper is on. Astro is the helper's name on the camera.")
        case .driveIsBusy:
            Text("Interval shooting can start when the self-timer or burst ends.", bundle: .module, comment: "Shown under the disabled Start button of interval shooting while the self-timer counts down or a burst runs.")
        case .intervalNotShorterThanTime:
            ModeCardText.intervalNotShorterThanTime
        }
    }

    /// Sends a manual intent.
    ///
    /// - Parameter intent: The intent.
    private func send(_ intent: ManualControlIntent) {
        Task { await model.send(.manual(intent)) }
    }
}

/// Interval Settings, opened from the selected Interval word of the drive strip and from the
/// interval card (docs/design/BUILD-SPEC.md, 3.5): the series' interval, what ends it (a number
/// of photos or a time), and Start. In the Interval drive mode the shutter starts the series too.
struct IntervalSheet: View {
    /// The camera model.
    let model: CameraModel

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The form.
    var body: some View {
        NavigationStack {
            NopeForm {
                IntervalSection(model: model) { dismiss() }
                // Done is a row of the form, not a bar button, as in Pro Tools: the audit can't
                // measure the contrast of the glass bar button.
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module, comment: "Button that closes a sheet, such as Settings or Pro Tools.")
                    }
                }
            }
            .navigationTitle(Text("Interval Shooting", bundle: .module, comment: "Section title: a series of photos taken at a fixed interval."))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
