import NopeCore
import SwiftUI

/// A message in the middle of the picture when the camera isn't running (docs/design/BUILD-SPEC.md,
/// 3.7, figure `camera-paused`), on solid black so it stays readable over any scene. Every pause
/// uses the same place: another app or a call, split view, cooling down, could not start, no
/// picture, and the spinner while the camera starts. Nothing while the camera runs. No spinner
/// during the camera's first start, while ``StartIndicator`` stands in its place
/// (docs/design/LAUNCH-SCREEN.md, 6.3).
struct SessionStatusView: View {
    /// The camera's status.
    let status: SessionStatus

    /// Whether ``StartIndicator`` is shown, so the spinner isn't.
    @Environment(\.showsStartIndicator) private var showsStartIndicator

    /// Creates the status message.
    ///
    /// - Parameter status: The camera's status.
    init(status: SessionStatus) {
        self.status = status
    }

    /// The message, or nothing.
    var body: some View {
        if let message {
            // A large symbol above the words, so a paused camera reads clearly, also in a reduced
            // iPad window (issue #68, "iPad").
            VStack(spacing: NopeSpace.xs) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                message
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(NopeColor.label)
            .multilineTextAlignment(.center)
            .padding(NopeSpace.m)
            // Solid black: over the material backing the iPad audit reported this text as low
            // contrast.
            .nopeBackground(.solid, in: RoundedRectangle(cornerRadius: NopeRadius.small))
            .accessibilityElement(children: .combine)
            .padding(NopeSpace.m)
        } else if status == .starting, !showsStartIndicator {
            ProgressView {
                Text("Starting the camera…", bundle: .module, comment: "Shown briefly while the app checks camera access.")
            }
            .padding(NopeSpace.m)
            .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.small))
        }
    }

    /// The SF Symbol for the message.
    private var symbol: String {
        switch status {
        case .pausedForHeat, .interrupted(.systemPressure): "thermometer.high"
        case .failed: "exclamationmark.triangle"
        case .noPicture: "video.slash"
        default: "pause.circle"
        }
    }

    /// The message for the status, or `nil` when there is nothing to say.
    private var message: Text? {
        switch status {
        case .stopped, .starting, .running, .interrupted(.backgrounded):
            nil
        case .interrupted(.inUseElsewhere):
            Text("The camera is in use by another app or a call. It comes back when that ends.", bundle: .module, comment: "Shown over the viewfinder when another app or a phone or video call is using the camera.")
        case .interrupted(.multitasking):
            Text("The camera works only when nope. fills the screen.", bundle: .module, comment: "Shown on iPad in Split View, Slide Over or Stage Manager. Keep \"nope.\" unchanged: it is the app's name.")
        case .interrupted(.systemPressure), .pausedForHeat:
            Text("The camera is paused to let your device cool down.", bundle: .module, comment: "Shown over the viewfinder when the device is too hot to run the camera.")
        case .interrupted(.other):
            Text("The camera is paused by the system. It comes back by itself.", bundle: .module, comment: "Shown over the viewfinder when the system pauses the camera for another reason.")
        case .failed:
            Text("The camera couldn't start. Try another lens.", bundle: .module, comment: "Shown over the viewfinder when the camera fails to start.")
        case .noPicture:
            Text("The camera isn't sending a picture.", bundle: .module, comment: "Shown over the viewfinder when the camera runs but every picture it delivers is blank, even after the app restarted the camera.")
        }
    }
}

extension EnvironmentValues {
    /// Whether the camera screen shows ``StartIndicator`` for the camera's first start, so
    /// ``SessionStatusView`` draws no spinner under it. Set by ``CameraScreen``.
    @Entry var showsStartIndicator = false
}
