import Foundation

/// The state of the most recent capture.
///
/// ``CameraModel/captureStatus`` holds it. Each case says how an interface should present it.
public enum CaptureStatus: Equatable, Sendable {
    /// No photo has been taken since the camera screen appeared. Show nothing.
    case idle

    /// A photo is being taken. Keep the shutter disabled until it finishes.
    case capturing

    /// The photo was taken and its files are being built, checked and saved. Keep the shutter
    /// disabled until it finishes.
    case saving

    /// The photo passed the metadata read-back and was added to Photos.
    ///
    /// Say that it was saved, and whether it is signed: "Saved and signed", or "Saved to
    /// Photos. Not signed:" with the ``SignatureStatus/UnsignedReason``. Announce it to
    /// VoiceOver.
    case saved(SavedPhoto)

    /// An exposure bracket was taken and every frame was saved as its own photo: separate
    /// single-frame photos, nothing merged, darkest first.
    ///
    /// Say how many photos were saved, and whether all of them are signed; when one isn't,
    /// say why, as for ``saved(_:)``. Announce it to VoiceOver.
    case savedBracket([SavedPhoto])

    /// The photo wasn't taken or wasn't saved. Present the error as its documentation says, and
    /// announce it.
    case failed(CaptureError)
}
