import NopeCore
import SwiftUI

/// The result of the last capture, in words, announced to VoiceOver when it changes.
///
/// It says whether the photo was saved and whether it is signed, or why it wasn't saved. A
/// missing signature is always stated, never hidden (issue #1). The signature and privacy
/// wording lives in `Honesty.xcstrings`. It stays on screen until the next capture (AGENTS.md,
/// "Motion and timing").
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
        case .saving:
            String(localized: "Saving…", bundle: .module, comment: "Shown while a photo that was just taken is being checked and added to the photo library.")
        case .saved(let photo):
            Self.message(for: photo.signature)
        case .savedBracket(let photos):
            Self.message(forBracket: photos)
        case .failed(.notRunning):
            String(localized: "No photo was taken: the camera is paused.", bundle: .module, comment: "Shown when the shutter is pressed while the camera is paused.")
        case .failed(.configurationFailed), .failed(.captureFailed):
            String(localized: "The photo wasn't taken. Try again.", bundle: .module, comment: "Shown when taking a photo failed.")
        case .failed(.blankPicture):
            String(localized: "No photo was taken: the camera sent a blank picture.", bundle: .module, comment: "Shown when the camera delivered a completely blank picture, so the app discarded it.")
        case .failed(.developmentFailed):
            String(localized: "Not saved: the photo couldn't be developed. Try again.", bundle: .module, comment: "Shown when the app couldn't turn the RAW photo into a HEIF or JPEG file, so nothing was saved. HEIF and JPEG are not mentioned to keep it short.")
        case .failed(.metadataNotAllowed):
            String(localized: "Not saved: nope. couldn't confirm that the photo holds only the details you chose.", table: "Honesty", bundle: .module, comment: "Shown when a finished photo file contained a metadata detail that is not on the privacy list, or couldn't be checked, so the app saved nothing. Honesty and privacy wording. Keep the name nope. unchanged, lowercase with its period.")
        case .failed(.photosAccessDenied):
            String(localized: "Not saved: nope. isn't allowed to add photos. You can allow it in the Settings app.", bundle: .module, comment: "Shown when the person hasn't allowed the app to add photos to their photo library. Keep the name nope. unchanged, lowercase with its period.")
        case .failed(.saveFailed):
            String(localized: "Not saved: the photo library couldn't add the photo. Try again.", bundle: .module, comment: "Shown when the system photo library reported an error while adding the photo.")
        case .failed(.savingUnavailable):
            String(localized: "Not saved: this version of the app can't save photos.", bundle: .module, comment: "Shown when this build of the app has no way to save photos, for example in a preview.")
        }
    }

    /// The message for a saved exposure bracket: how many photos were saved and signed, or, when
    /// one isn't signed, why, as for a single photo. A missing signature is never hidden.
    ///
    /// - Parameter photos: The saved photos.
    /// - Returns: The message.
    private static func message(forBracket photos: [SavedPhoto]) -> String {
        if let unsigned = photos.first(where: { $0.signature != .signed }) {
            return message(for: unsigned.signature)
        }
        return String(
            localized: "\(photos.count) photos saved and signed.", table: "Honesty", bundle: .module,
            comment: "Shown after an exposure bracket: each frame was added to the photo library as its own photo, each with a Content Credentials signature. The number is the count of photos, at least 3. Honesty wording: says only that they were saved and signed.")
    }

    /// The message for a saved photo: signed, or not signed with the reason.
    ///
    /// - Parameter signature: The photo's signature status.
    /// - Returns: The message.
    private static func message(for signature: SignatureStatus) -> String {
        switch signature {
        case .signed:
            String(localized: "Saved and signed.", table: "Honesty", bundle: .module, comment: "Shown after a photo was added to the photo library with a Content Credentials signature in every file. Honesty wording: says only that it was saved and signed.")
        case .unsigned(.turnedOff):
            String(localized: "Saved. Not signed: signing is off in Settings.", table: "Honesty", bundle: .module, comment: "Shown after a photo was saved without a Content Credentials signature because the person turned signing off in the app's settings. Honesty wording: never imply the photo is signed.")
        case .unsigned(.unavailable):
            String(localized: "Saved. Not signed: this development version can't sign photos yet.", table: "Honesty", bundle: .module, comment: "Shown after a photo was saved without a Content Credentials signature because signing isn't built into this development version yet. Honesty wording: never imply the photo is signed.")
        case .unsigned(.failed):
            String(localized: "Saved. Not signed: the signature couldn't be created.", table: "Honesty", bundle: .module, comment: "Shown after a photo was saved without a Content Credentials signature because creating the signature failed. Honesty wording: never imply the photo is signed.")
        }
    }
}
