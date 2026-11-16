import Foundation
import NopeCore

/// What Siri and Shortcuts say for each ``ShortcutOutcome`` (issue #62): whether the photo was
/// saved and signed, what changed, or why not. Never image data or metadata.
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
        case .lensSelected(.ultraWide):
            LocalizedStringResource(
                "Now using the ultra wide camera.", comment: "Siri's answer after nope. switched to the ultra wide rear camera.")
        case .lensSelected(.wide):
            LocalizedStringResource(
                "Now using the wide camera.", comment: "Siri's answer after nope. switched to the wide (main) rear camera.")
        case .lensSelected(.telephoto):
            LocalizedStringResource(
                "Now using the telephoto camera.", comment: "Siri's answer after nope. switched to the telephoto rear camera.")
        case .lensSelected(.front):
            LocalizedStringResource(
                "Now using the front camera.", comment: "Siri's answer after nope. switched to the front (selfie) camera.")
        case .lightOn:
            LocalizedStringResource(
                "The light is on.", comment: "Siri's answer after nope. turned its steady light (the torch) on.")
        case .lightOff:
            LocalizedStringResource(
                "The light is off.", comment: "Siri's answer after nope.'s steady light (the torch) was turned off, or was already off.")
        case .noLight:
            LocalizedStringResource(
                "This lens has no light.", comment: "Siri's answer when the lens in use has no steady light (torch), for example the front camera.")
        case .lightUnavailable:
            LocalizedStringResource(
                "The light isn't available right now.",
                comment: "Siri's answer when the system didn't allow the steady light (torch), for example because the phone is warm, or the night sky helper keeps it off.")
        case .intervalStarted:
            LocalizedStringResource(
                "Interval shooting started.", comment: "Siri's answer after nope. started a series of photos at a fixed interval.")
        case .intervalStopped:
            LocalizedStringResource(
                "Interval shooting stopped. The photos taken are saved.",
                comment: "Siri's answer after nope.'s interval series was stopped; the photos already taken are kept.")
        case .noIntervalRunning:
            LocalizedStringResource(
                "No interval series is running.", comment: "Siri's answer when asked to stop interval shooting while none runs.")
        case .focusRangeSet(.unlimited):
            LocalizedStringResource(
                "Autofocus has no range limit.", comment: "Siri's answer after nope.'s autofocus range limit (Close-Up or Far Focus) was lifted.")
        case .focusRangeSet(.closeUp):
            LocalizedStringResource(
                "Close-Up is on.", comment: "Siri's answer after nope. limited autofocus to near subjects. Close-Up is the camera control's name.")
        case .focusRangeSet(.far):
            LocalizedStringResource(
                "Far Focus is on.", comment: "Siri's answer after nope. limited autofocus to far subjects. Far Focus is the camera control's name.")
        case .focusRangeUnavailable:
            LocalizedStringResource(
                "This lens can't limit its focus range.", comment: "Siri's answer when the lens in use can't limit autofocus to near or far subjects.")
        case .photoSizeSet:
            LocalizedStringResource(
                "The photo size is set.", comment: "Siri's answer after nope. changed a lens's photo size; it applies from the next photo.")
        case .noPhotoSizeChoice:
            LocalizedStringResource(
                "This lens has only one photo size.", comment: "Siri's answer when the lens offers no choice of photo size.")
        case .bracketUnavailable:
            LocalizedStringResource(
                "This lens can't take that bracket.",
                comment: "Siri's answer when the lens in use can't take the exposure bracket asked for: it has no manual exposure, or takes fewer photos in one bracket.")
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
