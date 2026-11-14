import NopeCore
import SwiftUI

/// The words for the drive modes, the self-timer and bursts (issues #39 and #46).
@MainActor
enum DriveText {
    /// A number of seconds in the system's short form, such as "3s" or "3 Sek.".
    ///
    /// - Parameter seconds: The seconds.
    static func shortSeconds(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .narrow))
    }

    /// A number of seconds in words, such as "3 seconds", for VoiceOver.
    ///
    /// - Parameter seconds: The seconds.
    static func spokenSeconds(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .wide))
    }

    /// A mode's name, as the Drive menu lists it.
    ///
    /// - Parameter mode: The mode.
    static func name(of mode: DriveMode) -> Text {
        switch mode {
        case .single:
            Text("Single Photo", bundle: .module, comment: "Drive menu option on the camera: each press of the shutter takes one photo.")
        case .timer(let delay):
            Text("Timer: \(shortSeconds(delay.seconds))", bundle: .module, comment: "Drive menu option on the camera: a self-timer. The value is a short number of seconds, such as 3s or 10s, formatted by the system.")
        case .burst:
            Text("Burst", bundle: .module, comment: "Drive menu option on the camera: holding the shutter takes a rapid run of separate photos.")
        }
    }

    /// The SF Symbol for a mode.
    ///
    /// - Parameter mode: The mode.
    static func systemImage(for mode: DriveMode) -> String {
        switch mode {
        case .single: "timer"
        case .timer: "timer"
        case .burst: "square.stack.3d.down.right"
        }
    }

    /// What the shutter does now, for VoiceOver, or `nil` in single mode with nothing running.
    ///
    /// - Parameter drive: The drive model.
    static func shutterValue(_ drive: DriveModel) -> Text? {
        if drive.countdown.isRunning {
            return Text("Counting down. Press to cancel.", bundle: .module, comment: "VoiceOver value of the shutter while the self-timer counts down: pressing the shutter cancels the photo.")
        }
        if drive.burstProgress != nil {
            return Text("Taking a burst. Press to stop.", bundle: .module, comment: "VoiceOver value of the shutter while a burst runs: pressing the shutter stops it.")
        }
        switch drive.mode {
        case .single: return nil
        case .timer(let delay):
            return Text("Self-timer: \(spokenSeconds(delay.seconds))", bundle: .module, comment: "VoiceOver value of the shutter when the self-timer is on. The value is a number of seconds in words, such as 3 seconds, formatted by the system.")
        case .burst:
            return Text("Burst. Press to start, press again to stop.", bundle: .module, comment: "VoiceOver value of the shutter in burst mode: one press starts a rapid run of separate photos, the next press stops it.")
        }
    }

    /// What to announce when a burst ends other than by the person, or `nil`.
    ///
    /// - Parameter result: How the burst ended.
    static func endMessage(_ result: BurstResult) -> String? {
        switch result.end {
        case .stopped, .failed:
            nil
        case .limitReached:
            String(localized: "Burst stopped at \(result.saved) photos, the most one burst takes.", bundle: .module, comment: "Announced and shown when a burst stops because it reached its maximum number of photos. The number is that count of photos, such as 50.")
        case .storageFull:
            String(localized: "Burst stopped: storage is full.", bundle: .module, comment: "Announced and shown when a burst stops because the next photo wouldn't fit in the device's free storage.")
        case .cameraStopped:
            String(localized: "Burst stopped: the camera stopped.", bundle: .module, comment: "Announced and shown when a burst stops because the camera was interrupted or switched lenses.")
        }
    }
}

extension QuickControls {
    /// Drive: a menu of single, the 3 and 10 second self-timer, and burst (issue #68). Bracket
    /// and interval shooting stay in Pro Tools, behind the manual controls.
    ///
    /// - Parameter context: The model and settings.
    static func drive(_ context: CameraControlContext) -> QuickControlItem? {
        let drive = context.model.drive
        return QuickControlItem(
            id: "drive",
            title: Text("Drive", bundle: .module, comment: "Quick control on the camera: a menu that chooses what the shutter does: one photo, a self-timer, or a burst."),
            systemImage: DriveText.systemImage(for: drive.mode),
            kind: .menu(
                DriveMode.allCases.map { mode in
                    QuickControlItem.Option(
                        id: optionID(mode), title: DriveText.name(of: mode), isSelected: drive.mode == mode
                    ) {
                        context.send(.drive(.setMode(mode)))
                    }
                }))
    }

    /// A stable identifier for a drive mode's menu option.
    ///
    /// - Parameter mode: The mode.
    private static func optionID(_ mode: DriveMode) -> String {
        switch mode {
        case .single: "single"
        case .timer(let delay): "timer\(delay.seconds)"
        case .burst: "burst"
        }
    }
}

extension StatePills {
    /// The self-timer's delay ("3s") or "Burst" while the drive mode isn't single; its action
    /// returns to single photos.
    ///
    /// - Parameter context: The model and settings.
    static func drive(_ context: CameraControlContext) -> StatePill? {
        let mode = context.model.drive.mode
        let text: String
        let label: Text
        switch mode {
        case .single:
            return nil
        case .timer(let delay):
            text = DriveText.shortSeconds(delay.seconds)
            label = Text("Self-Timer", bundle: .module, comment: "VoiceOver and Voice Control name of the pill on the camera that shows the self-timer is on.")
        case .burst:
            text = String(localized: "Burst", bundle: .module, comment: "Drive menu option on the camera: holding the shutter takes a rapid run of separate photos.")
            label = Text("Burst", bundle: .module, comment: "Drive menu option on the camera: holding the shutter takes a rapid run of separate photos.")
        }
        return StatePill(
            id: "drive", systemImage: DriveText.systemImage(for: mode), text: Text(verbatim: text), label: label,
            actions: [
                StatePill.Action(
                    id: "single",
                    title: Text("Back to Single Photo", bundle: .module, comment: "Action of the self-timer or burst pill on the camera: the shutter takes one photo per press again.")
                ) {
                    context.send(.drive(.setMode(.single)))
                }
            ])
    }
}

/// The large countdown number in the middle of the picture while the self-timer runs. VoiceOver
/// hears each number through an announcement instead (``DriveFeedback``), so it is hidden from
/// assistive technologies.
struct CountdownNumber: View {
    /// The drive model.
    let drive: DriveModel

    /// Creates the number.
    ///
    /// - Parameter drive: The drive model.
    init(drive: DriveModel) {
        self.drive = drive
    }

    /// The number, or nothing.
    var body: some View {
        if let remaining = drive.countdown.remainingSeconds {
            Text(remaining, format: .number)
                .font(.system(size: 96, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .darkBacking()
                .accessibilityHidden(true)
        }
    }
}

/// A running countdown or burst: what it is doing and a button to stop it. It stays on screen,
/// even in clean view, until it ends, so stopping never depends on a gesture.
struct DriveProgressView: View {
    /// The camera model.
    let model: CameraModel

    /// Creates the view.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The text and the button, or nothing.
    var body: some View {
        if let remaining = model.drive.countdown.remainingSeconds {
            row(
                Text("Photo in \(DriveText.shortSeconds(remaining))", bundle: .module, comment: "Self-timer progress on the camera: the photo is taken after this many seconds. The value is a short number of seconds, such as 3s, formatted by the system."),
                button: Text("Cancel Timer", bundle: .module, comment: "Button that stops the self-timer without taking a photo.")
            ) {
                Task { await model.send(.drive(.cancelTimer)) }
            }
        } else if let progress = model.drive.burstProgress {
            row(
                Text("Photos taken: \(progress.taken)", bundle: .module, comment: "Burst progress on the camera: how many photos of the running burst are taken so far."),
                button: Text("Stop Burst", bundle: .module, comment: "Button that stops a running burst. Every photo already taken is saved.")
            ) {
                Task { await model.send(.drive(.stopBurst)) }
            }
        }
    }

    /// One row: the text and its button.
    ///
    /// - Parameters:
    ///   - text: What is running.
    ///   - button: The button's name.
    ///   - action: Stops it.
    private func row(_ text: Text, button: Text, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            text.font(.callout.monospacedDigit())
            Button(role: .destructive, action: action) {
                button.frame(minHeight: CameraStyle.minimumTarget)
            }
            // Borderless on black, as the interval progress is: red passes the contrast audit there.
        }
        .padding(.horizontal, 12)
        .background(.black, in: .rect(cornerRadius: CameraStyle.cornerRadius))
    }
}

/// Feedback for the self-timer and bursts without looking at the screen: a haptic tick and a
/// spoken number each second of the countdown, and spoken start and end of a burst (AGENTS.md,
/// "Taking photos without seeing the screen"). Saved photos are announced by the camera's
/// usual save feedback.
struct DriveFeedback: ViewModifier {
    /// The drive model.
    let drive: DriveModel

    /// Creates the feedback.
    ///
    /// - Parameter drive: The drive model.
    init(drive: DriveModel) {
        self.drive = drive
    }

    /// The content with the feedback attached.
    ///
    /// - Parameter content: The camera.
    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.impact(weight: .light), trigger: drive.countdown.remainingSeconds) { _, new in new != nil }
            .onChange(of: drive.countdown.remainingSeconds) { _, remaining in
                if let remaining { Self.announce(remaining.formatted()) }
            }
            .onChange(of: drive.burstProgress != nil) { _, isRunning in
                if isRunning {
                    Self.announce(String(localized: "Burst started.", bundle: .module, comment: "Announced to VoiceOver when a burst starts."))
                }
            }
            .onChange(of: drive.lastBurst) { _, result in
                if let result, let message = DriveText.endMessage(result) { Self.announce(message) }
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
    /// Adds the self-timer and burst feedback (``DriveFeedback``).
    ///
    /// - Parameter drive: The drive model.
    func driveFeedback(_ drive: DriveModel) -> some View {
        modifier(DriveFeedback(drive: drive))
    }

    /// Adds what the shutter does in the current drive mode to its VoiceOver value.
    ///
    /// - Parameter drive: The drive model.
    func shutterDriveValue(_ drive: DriveModel) -> some View {
        accessibilityValue(DriveText.shutterValue(drive) ?? Text(verbatim: ""))
    }
}
