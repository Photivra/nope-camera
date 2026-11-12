import NopeCore
import SwiftUI

/// Metering, AE and AF locks, exposure bracketing and interval shooting, in a standard form.
///
/// Each section appears only when the selected lens supports it. The sheet follows the system
/// appearance.
struct ProToolsSheet: View {
    /// The intervals offered, in seconds: 1 second to 1 hour.
    static let intervals: [Double] = [1, 2, 3, 5, 10, 15, 20, 30, 60, 120, 300, 600, 900, 1800, 3600]

    /// The photo counts offered for a series, from 2 to the 999 nope. allows.
    static let photoCounts = [2, 3, 5, 10, 20, 30, 50, 100, 200, 500, 999]

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

    /// The manual controls model.
    private var manual: ManualControlsModel { model.manual }

    /// The form.
    var body: some View {
        NavigationStack {
            Form {
                if manual.capabilities.meteringModes.count > 1 {
                    meteringSection
                }
                if manual.capabilities.supportsExposureLock || manual.capabilities.supportsFocusLock {
                    locksSection
                }
                if !manual.bracketFrameCounts.isEmpty {
                    bracketSection
                }
                intervalSection
                // Done is a row of the form, not a bar button: the accessibility audit can't
                // measure the contrast of the glass bar button.
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module, comment: "Closes the Pro Tools sheet.")
                    }
                }
            }
            .navigationTitle(Text("Pro Tools", bundle: .module, comment: "Button that opens metering, locks, bracketing and interval shooting."))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Sends a manual intent.
    ///
    /// - Parameter intent: The intent.
    private func send(_ intent: ManualControlIntent) {
        Task { await model.send(.manual(intent)) }
    }

    /// The metering mode picker.
    private var meteringSection: some View {
        Section {
            Picker(
                selection: Binding(get: { manual.settings.metering }, set: { send(.setMetering($0)) })
            ) {
                ForEach(manual.capabilities.meteringModes, id: \.self) { mode in
                    Text(verbatim: ControlText.name(mode)).tag(mode)
                }
            } label: {
                Text("Metering", bundle: .module, comment: "Picker for how auto exposure measures the scene.")
            }
        }
    }

    /// The AE-L and AF-L switches.
    private var locksSection: some View {
        Section {
            if manual.capabilities.supportsExposureLock {
                Toggle(isOn: Binding(get: { manual.settings.exposureLocked }, set: { send(.setExposureLock($0)) })) {
                    Text("Exposure Lock (AE-L)", bundle: .module, comment: "Switch that locks auto exposure. AE-L is the usual camera abbreviation.")
                }
                .disabled(!manual.canLockExposure && !manual.settings.exposureLocked)
            }
            if manual.capabilities.supportsFocusLock {
                Toggle(isOn: Binding(get: { manual.settings.focusLocked }, set: { send(.setFocusLock($0)) })) {
                    Text("Focus Lock (AF-L)", bundle: .module, comment: "Switch that locks autofocus. AF-L is the usual camera abbreviation.")
                }
                .disabled(!manual.canLockFocus && !manual.settings.focusLocked)
            }
        }
    }

    /// The bracketing switch, frame count and step.
    private var bracketSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { manual.bracket != nil },
                    set: { isOn in
                        let first = manual.bracketFrameCounts[0]
                        send(.setBracket(isOn ? BracketSettings(frameCount: first, step: 1) : nil))
                    })
            ) {
                Text("Bracketing", bundle: .module, comment: "Switch for exposure bracketing: several photos at different exposures from one press.")
            }
            if let bracket = manual.bracket {
                Picker(
                    selection: Binding(
                        get: { bracket.frameCount },
                        set: { send(.setBracket(BracketSettings(frameCount: $0, step: bracket.step))) })
                ) {
                    ForEach(manual.bracketFrameCounts, id: \.self) { count in
                        Text(verbatim: count.formatted()).tag(count)
                    }
                } label: {
                    Text("Frames", bundle: .module, comment: "Picker for how many photos one bracket takes.")
                }
                Picker(
                    selection: Binding(
                        get: { bracket.step },
                        set: { send(.setBracket(BracketSettings(frameCount: bracket.frameCount, step: $0))) })
                ) {
                    ForEach(BracketSettings.steps, id: \.self) { step in
                        Text(verbatim: ControlText.step(step)).tag(step)
                    }
                } label: {
                    Text("Step", bundle: .module, comment: "Picker for the exposure difference between bracketed photos.")
                }
            }
        } footer: {
            Text(
                "Each frame is a separate single-frame photo. Nothing is merged.", tableName: "Honesty", bundle: .module,
                comment: "Explains exposure bracketing. Must not claim more than the English: the photos are never combined.")
        }
    }

    /// The interval, photo count, and start or stop.
    private var intervalSection: some View {
        Section {
            Text("Interval Shooting", bundle: .module, comment: "Section title: a series of photos taken at a fixed interval.")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Picker(
                selection: Binding(
                    get: { manual.interval.interval },
                    set: { send(.setInterval(IntervalSettings(interval: $0, count: manual.interval.count))) })
            ) {
                ForEach(Self.intervals, id: \.self) { seconds in
                    Text(verbatim: Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
                        .tag(seconds)
                }
            } label: {
                Text("Interval", bundle: .module, comment: "Picker for the time between photos in interval shooting.")
            }
            Picker(
                selection: Binding(
                    get: { manual.interval.count },
                    set: { send(.setInterval(IntervalSettings(interval: manual.interval.interval, count: $0))) })
            ) {
                ForEach(Self.photoCounts, id: \.self) { count in
                    Text(verbatim: count.formatted()).tag(count)
                }
            } label: {
                Text("Photos", bundle: .module, comment: "Picker for how many photos an interval series takes.")
            }
            if manual.intervalProgress == nil {
                Button {
                    send(.startInterval)
                    dismiss()
                } label: {
                    Text("Start", bundle: .module, comment: "Button that starts interval shooting.")
                }
                .disabled(!model.canCapture)
            } else {
                Button(role: .destructive) {
                    send(.stopInterval)
                } label: {
                    Text("Stop", bundle: .module, comment: "Button that stops interval shooting.")
                }
            }
        } footer: {
            Text(
                "Each photo is separate. Nothing is combined. Keep nope. open while the series runs.", tableName: "Honesty",
                bundle: .module,
                comment: "Explains interval shooting. Keep \"nope.\" unchanged: it is the app's name. Must not claim more than the English.")
        }
    }
}

/// The progress of a running interval series and a button to stop it. It stays on screen, even
/// in clean view, until the series ends.
struct IntervalProgressView: View {
    /// The progress.
    let progress: IntervalProgress

    /// Stops the series.
    let stop: () -> Void

    /// Creates the progress view.
    ///
    /// - Parameters:
    ///   - progress: The progress.
    ///   - stop: Stops the series.
    init(progress: IntervalProgress, stop: @escaping () -> Void) {
        self.progress = progress
        self.stop = stop
    }

    /// The count and the Stop button.
    var body: some View {
        HStack(spacing: 12) {
            Text("\(progress.taken) of \(progress.total) photos taken", bundle: .module, comment: "Interval shooting progress: how many photos of the series are taken so far. Both numbers are counts of photos; the second is at least 2.")
                .font(.callout.monospacedDigit())
            Button(role: .destructive, action: stop) {
                Text("Stop", bundle: .module, comment: "Button that stops interval shooting.")
                    .frame(minHeight: 44)
            }
            // Borderless: red on the black backing passes the contrast audit; on a bordered fill
            // it doesn't.
        }
        .padding(.horizontal, 12)
        .background(.black, in: .rect(cornerRadius: 10))
    }
}
