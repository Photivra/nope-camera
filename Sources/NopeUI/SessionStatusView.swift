import NopeCore
import SwiftUI

/// A message over the viewfinder when the camera isn't running, with a solid backing so it
/// stays readable over any scene. Nothing while the camera runs.
struct SessionStatusView: View {
    /// The camera's status.
    let status: SessionStatus

    /// Creates the status message.
    ///
    /// - Parameter status: The camera's status.
    init(status: SessionStatus) {
        self.status = status
    }

    /// The message, or nothing.
    var body: some View {
        if let message {
            Label {
                message
            } icon: {
                Image(systemName: symbol)
            }
            .font(.body)
            .multilineTextAlignment(.leading)
            .padding()
            .background(.black, in: .rect(cornerRadius: 12))
            .padding()
        } else if status == .starting {
            ProgressView {
                Text("Starting the camera…", bundle: .module, comment: "Shown briefly while the app checks camera access.")
            }
            .padding()
            .background(.black, in: .rect(cornerRadius: 12))
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
            Text("The camera isn't sending a picture. Restarting your iPhone usually fixes this.", bundle: .module, comment: "Shown over the viewfinder when the camera runs but every picture it delivers is blank, even after the app restarted the camera. Restarting the phone clears it.")
        }
    }
}
