import NopeCore
import SwiftUI

/// The result of the last capture, in words, announced to VoiceOver when it changes.
///
/// In this development stage a photo is held in memory and never saved, and the text says so
/// plainly. It stays on screen until the next capture (AGENTS.md, "Motion and timing").
struct CaptureStatusView: View {
    /// The last capture's status.
    let status: CaptureStatus

    /// Creates the status line.
    ///
    /// - Parameter status: The last capture's status.
    init(status: CaptureStatus) {
        self.status = status
    }

    /// The status text, or an empty line that keeps the layout steady.
    var body: some View {
        Text(verbatim: message ?? " ")
            .font(.callout)
            .multilineTextAlignment(.center)
            .accessibilityHidden(message == nil)
            .onChange(of: message) { _, newValue in
                guard let newValue else { return }
                AccessibilityNotification.Announcement(newValue).post()
            }
    }

    /// The message for the status, or `nil` when there is nothing to say.
    private var message: String? {
        switch status {
        case .idle:
            nil
        case .capturing:
            String(localized: "Taking photo…", bundle: .module, comment: "Shown while a photo is being taken.")
        case .captured:
            String(localized: "Captured (not saved yet: development build)", bundle: .module, comment: "Shown after a photo is taken. In this development version photos are kept in memory and not saved to Photos.")
        case .failed(.notRunning):
            String(localized: "No photo was taken: the camera is paused.", bundle: .module, comment: "Shown when the shutter is pressed while the camera is paused.")
        case .failed(.configurationFailed), .failed(.captureFailed):
            String(localized: "The photo wasn't taken. Try again.", bundle: .module, comment: "Shown when taking a photo failed.")
        }
    }
}
