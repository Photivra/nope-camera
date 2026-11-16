import NopeCore
import SwiftUI

/// The exposure mode, metering, AE and AF locks, exposure bracketing and interval shooting, in a
/// standard form, opened from the last button of the manual controls row.
///
/// Each section appears only when the selected lens supports it. The sheet follows the system
/// appearance.
struct ProToolsSheet: View {
    /// The camera model.
    let model: CameraModel

    /// The person's settings, for the live aid switches, or `nil` to leave them out.
    let settings: NopeSettings?

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - settings: The person's settings, for the focus peaking, histogram and live readout
    ///     switches, or `nil` to leave them out.
    init(model: CameraModel, settings: NopeSettings? = nil) {
        self.model = model
        self.settings = settings
    }

    /// The manual controls model.
    private var manual: ManualControlsModel { model.manual }

    /// The form.
    var body: some View {
        NavigationStack {
            Form {
                if manual.exposureModes.count > 1 {
                    exposureModeSection
                }
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
                if let settings {
                    Section { LiveAidToggles(settings: settings) }
                }
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

    /// The exposure mode picker: P, S, I or M, as the lens supports.
    private var exposureModeSection: some View {
        Section {
            Picker(
                selection: Binding(get: { manual.settings.exposureMode }, set: { send(.setExposureMode($0)) })
            ) {
                ForEach(manual.exposureModes, id: \.self) { mode in
                    Text(verbatim: ControlText.name(mode)).tag(mode)
                }
            } label: {
                Text("Exposure Mode", bundle: .module, comment: "Name of the picker for the exposure mode: P, S, I or M.")
            }
            .accessibilityIdentifier("exposure-mode")
        }
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

    /// The interval, photo count, and start or stop: the same section as the Drive menu's
    /// Interval sheet.
    private var intervalSection: some View {
        IntervalSection(model: model) { dismiss() }
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
            Group {
                if progress.isPaused {
                    Text("Paused: \(progress.taken) of \(progress.total) photos taken", bundle: .module, comment: "Interval shooting progress while the series is paused because the camera is paused (for example by a call) or nope. is in the background: it continues when the camera is back. Both numbers are counts of photos; the second is at least 2. Keep \"nope.\" unchanged.")
                } else {
                    Text("\(progress.taken) of \(progress.total) photos taken", bundle: .module, comment: "Interval shooting progress: how many photos of the series are taken so far. Both numbers are counts of photos; the second is at least 2.")
                }
            }
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
