import Foundation
import NopeCore

/// What Siri and Shortcuts say for each ``ShortcutOutcome`` (issue #62): whether the photo was
/// saved and signed, or why not. Never image data or metadata.
enum ShortcutDialog {
    /// The sentence for an outcome, as each ``ShortcutOutcome`` case documents it.
    ///
    /// - Parameter outcome: How the request ended.
    /// - Returns: A whole, localized sentence.
    static func message(for outcome: ShortcutOutcome) -> LocalizedStringResource {
        switch outcome {
        case .saved(isSigned: true):
            LocalizedStringResource(
                "Photo saved and signed.", comment: "Siri's answer after nope. took and saved a signed photo.")
        case .saved(isSigned: false):
            LocalizedStringResource(
                "Photo saved. It isn't signed.",
                comment: "Siri's answer after nope. saved a photo without a Content Credentials signature.")
        case .savedSeveral(allSigned: true):
            LocalizedStringResource(
                "Photos saved and signed.",
                comment: "Siri's answer after nope. saved an exposure bracket, each frame its own signed photo.")
        case .savedSeveral(allSigned: false):
            LocalizedStringResource(
                "Photos saved. Not all of them are signed.",
                comment: "Siri's answer after nope. saved an exposure bracket in which some photos aren't signed.")
        case .notSaved:
            LocalizedStringResource(
                "The photo wasn't saved. nope. shows why.",
                comment: "Siri's answer when the photo couldn't be taken or saved. Keep \"nope.\" unchanged.")
        case .cancelled:
            LocalizedStringResource(
                "The timer was cancelled. No photo was taken.",
                comment: "Siri's answer when the self-timer was cancelled on the phone before the photo.")
        case .busy:
            LocalizedStringResource(
                "nope. is already taking a photo.",
                comment: "Siri's answer when a photo, countdown or burst is already running. Keep \"nope.\" unchanged.")
        case .lensUnavailable:
            LocalizedStringResource(
                "This device doesn't have that lens.",
                comment: "Siri's answer when the lens asked for doesn't exist on this iPhone or iPad.")
        case .cameraUnavailable(.needsPermission):
            LocalizedStringResource(
                "Open nope. to allow camera access.",
                comment: "Siri's answer when nope. hasn't asked for camera access yet. Keep \"nope.\" unchanged.")
        case .cameraUnavailable(.permissionDenied):
            LocalizedStringResource(
                "Camera access is off for nope. You can turn it on in the Settings app.",
                comment: "Siri's answer when camera access was declined. Keep \"nope.\" unchanged; Settings is the iOS app.")
        case .cameraUnavailable(.noCamera):
            LocalizedStringResource(
                "This device has no camera nope. can use.",
                comment: "Siri's answer on a device without a usable camera. Keep \"nope.\" unchanged.")
        case .cameraUnavailable(.notRunning):
            LocalizedStringResource(
                "The camera isn't available right now.",
                comment: "Siri's answer when the camera didn't start, is in use by another app or is paused.")
        }
    }
}
