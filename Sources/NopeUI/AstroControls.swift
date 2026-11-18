import NopeCore
import SwiftUI

/// The words of the astro helper (issue #60). The claims about what the app does with the frames
/// are in the Honesty table.
@MainActor
enum AstroText {
    /// "Astro".
    static var title: Text {
        Text("Astro", bundle: .module, comment: "Quick control, pill and its Voice Control name on the camera: the helper for night sky photos, which takes a series of single RAW frames for stacking in other software.")
    }

    /// "Astro Settings".
    static var settings: Text {
        Text("Astro Settings", bundle: .module, comment: "Button on the camera and title of the sheet with the night sky helper's frame count, start delay and estimates.")
    }

    /// What the app does with the frames, and what it doesn't.
    static var honesty: Text {
        Text(
            "nope. takes single RAW frames one after another and saves each one as its own photo. It doesn't stack, merge or process them: stack them in other software.",
            tableName: "Honesty", bundle: .module,
            comment: "Explains the night sky (astro) helper. Keep \"nope.\" unchanged: it is the app's name. Must not claim more than the English: the frames are never combined. Honesty wording: a fluent human must review every translation before release.")
    }

    /// What VoiceOver hears when Astro comes on. From the drive strip it also turns on the
    /// manual controls and night mode (docs/design/BUILD-SPEC.md, section 4); from a preset it
    /// turns on the manual controls only, so night mode is named only while it is on.
    ///
    /// - Parameter isNightModeOn: Whether night mode is on.
    /// - Returns: The announcement.
    static func turnedOn(isNightModeOn: Bool) -> String {
        if isNightModeOn {
            String(localized: "Astro on. Manual controls and night mode are on.", bundle: .module, comment: "Announced to VoiceOver when Astro is chosen on the drive strip: Astro also turns on the manual controls and night mode.")
        } else {
            String(localized: "Astro on. Manual controls are on.", bundle: .module, comment: "Announced to VoiceOver when Astro comes on while night mode is off, for example from a settings preset: Astro also turns on the manual controls.")
        }
    }

    /// What the shutter does while the helper is on, for VoiceOver, or `nil` while it is off.
    ///
    /// - Parameter model: The camera model.
    static func shutterValue(_ model: CameraModel) -> Text? {
        guard model.astro.isOn else { return nil }
        if model.astro.isRunning {
            return Text("Taking astro frames. Press to stop.", bundle: .module, comment: "VoiceOver value of the shutter while the night sky helper takes its frames: pressing the shutter stops them.")
        }
        if model.drive.countdown.isRunning {
            return DriveText.shutterValue(model)
        }
        return Text("Astro. Press to start the frames after the start delay.", bundle: .module, comment: "VoiceOver value of the shutter while the night sky helper is on: one press starts the self-timer, then the series of frames.")
    }

    /// What to announce when a run ends, or `nil` when the person stopped it or a frame failed
    /// (the failure banner says why).
    ///
    /// - Parameter result: How the run ended.
    static func endMessage(_ result: BurstResult) -> String? {
        switch result.end {
        case .stopped, .failed:
            nil
        case .limitReached, .countReached:
            // Astro runs end at their own frame count with limitReached; countReached is a Siri
            // burst's, listed so the switch covers every case.
            String(localized: "Astro finished. Frames saved: \(result.saved)", bundle: .module, comment: "Announced to VoiceOver when the night sky helper has taken all its frames. The number is how many frames were saved.")
        case .storageFull:
            String(localized: "Astro stopped: storage is full. Frames saved: \(result.saved)", bundle: .module, comment: "Announced to VoiceOver when the night sky helper stops because the next frame wouldn't fit in storage. The number is how many frames were saved.")
        case .batteryLow:
            String(localized: "Astro stopped: the battery is low. Frames saved: \(result.saved)", bundle: .module, comment: "Announced to VoiceOver when the night sky helper stops because the battery is nearly empty and not charging. The number is how many frames were saved.")
        case .cameraStopped:
            String(localized: "Astro stopped: the camera stopped. Frames saved: \(result.saved)", bundle: .module, comment: "Announced to VoiceOver when the night sky helper stops because the camera was interrupted or switched lenses. The number is how many frames were saved.")
        }
    }
}

/// The astro helper's settings: what the app does with the frames, the frame count and start
/// delay, each frame's exposure, and what the run will take. A standard form with pushed-list
/// pickers.
struct AstroSheet: View {
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
            Form {
                Section {
                    AstroText.honesty
                }
                framesSection
                exposureSection
                if let estimate = model.astroEstimate {
                    estimateSection(estimate)
                }
                Section {
                    Label {
                        Text(
                            "Use a tripod. Turn on Magnify to check focus on a bright star or a distant light, and fine-tune it with the Focus control.",
                            bundle: .module,
                            comment: "Tip in the night sky helper's settings. Magnify and Focus are the names of the camera's focus magnifier and manual focus control.")
                    } icon: {
                        Image(systemName: "hand.raised")
                    }
                }
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
            .navigationTitle(AstroText.settings)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The frame count and the start delay.
    private var framesSection: some View {
        Section {
            Picker(selection: Binding(get: { model.astro.frameCount }, set: { send(.setFrameCount($0)) })) {
                ForEach(AstroModel.frameCounts, id: \.self) { count in
                    Text(verbatim: count.formatted()).tag(count)
                }
            } label: {
                Text("Frames", bundle: .module, comment: "Picker for how many photos one bracket takes.")
            }
            .pickerStyle(.navigationLink)
            Picker(selection: Binding(get: { model.astro.startDelay }, set: { send(.setStartDelay($0)) })) {
                ForEach(SelfTimerDelay.allCases, id: \.self) { delay in
                    Text(verbatim: DriveText.spokenSeconds(delay.seconds)).tag(delay)
                }
            } label: {
                Text("Start Delay", bundle: .module, comment: "Picker in the night sky helper's settings: how long the self-timer waits before the first frame, so touching the phone doesn't shake it.")
            }
            .pickerStyle(.navigationLink)
        }
    }

    /// Each frame's shutter, ISO and focus, as the manual controls have them.
    private var exposureSection: some View {
        Section {
            ForEach([ManualControl.shutter, .iso, .focus], id: \.self) { control in
                LabeledContent {
                    Text(verbatim: model.manual.value(of: control).map { ControlText.value($0, of: control) } ?? "–")
                } label: {
                    Text(verbatim: ControlText.name(control))
                }
            }
        } header: {
            Text("Each Frame", bundle: .module, comment: "Section title in the night sky helper's settings: the exposure every frame is taken with.")
        } footer: {
            Text(
                "Set when Astro is turned on: focus at the far end, and the longest shutter and highest ISO this lens allows. Change them with the manual controls.",
                bundle: .module,
                comment: "Explains the exposure in the night sky helper's settings. Astro is the helper's name on the camera.")
        }
    }

    /// The total exposure time, the storage the run can take, and whether it fits.
    ///
    /// - Parameter estimate: The estimate.
    private func estimateSection(_ estimate: AstroEstimate) -> some View {
        Section {
            if let seconds = estimate.totalExposureSeconds {
                LabeledContent {
                    Text(verbatim: Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2, fractionalPart: .hide(rounded: .up))))
                } label: {
                    Text("Exposure Time in All", bundle: .module, comment: "Row in the night sky helper's settings: the shutter time of all frames added together.")
                }
            }
            LabeledContent {
                Text(verbatim: estimate.bytes.formatted(.byteCount(style: .file)))
            } label: {
                Text("Storage, at Most", bundle: .module, comment: "Row in the night sky helper's settings: the most storage all frames can take, an upper estimate.")
            }
            if !estimate.fits {
                Label {
                    Text("Not every frame fits in the free storage. The frames stop when storage is full.", bundle: .module, comment: "Warning in the night sky helper's settings when the frames chosen may not all fit in the free storage.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(CameraStyle.secondaryText)
            }
        } footer: {
            Text(
                "The frames take longer than their exposure time: each one also needs time to save. They stop early if storage runs out, the battery is nearly empty, or the camera stops.",
                bundle: .module,
                comment: "Explains the estimates in the night sky helper's settings.")
        }
    }

    /// Sends an astro intent.
    ///
    /// - Parameter intent: The intent.
    private func send(_ intent: AstroIntent) {
        let model = model
        Task { await model.send(.astro(intent)) }
    }
}

/// Announcements for the astro helper without looking at the screen: that it came on, with the
/// manual controls and night mode, and the start and the end of the frames (AGENTS.md, "Taking photos without seeing the screen"). The countdown before the
/// first frame has the self-timer's own ticks and numbers (``DriveFeedback``).
struct AstroFeedback: ViewModifier {
    /// The astro helper.
    let astro: AstroModel

    /// Whether night mode is on, so the announcement names it only then.
    let isNightModeOn: Bool

    /// Creates the feedback.
    ///
    /// - Parameters:
    ///   - astro: The astro helper.
    ///   - isNightModeOn: Whether night mode is on.
    init(astro: AstroModel, isNightModeOn: Bool) {
        self.astro = astro
        self.isNightModeOn = isNightModeOn
    }

    /// The content with the feedback attached.
    ///
    /// - Parameter content: The camera.
    func body(content: Content) -> some View {
        content
            .onChange(of: astro.isOn) { _, isOn in
                if isOn { Self.announce(AstroText.turnedOn(isNightModeOn: isNightModeOn)) }
            }
            .onChange(of: astro.isRunning) { _, isRunning in
                if isRunning {
                    Self.announce(String(localized: "Astro frames started.", bundle: .module, comment: "Announced to VoiceOver when the night sky helper starts taking its frames."))
                }
            }
            .onChange(of: astro.lastRun) { _, result in
                if let result, let message = AstroText.endMessage(result) { Self.announce(message) }
            }
    }

    /// Posts a VoiceOver announcement.
    ///
    /// - Parameter message: What to say.
    private static func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}

extension View {
    /// Adds the astro helper's announcements (``AstroFeedback``).
    ///
    /// - Parameters:
    ///   - astro: The astro helper.
    ///   - isNightModeOn: Whether night mode is on.
    func astroFeedback(_ astro: AstroModel, isNightModeOn: Bool) -> some View {
        modifier(AstroFeedback(astro: astro, isNightModeOn: isNightModeOn))
    }
}
