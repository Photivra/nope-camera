import Foundation

/// The state of the most recent capture.
///
/// ``CameraModel/captureStatus`` holds it. Each case says how an interface should present it.
public enum CaptureStatus: Equatable, Sendable {
    /// No photo has been taken since the camera screen appeared. Show nothing.
    case idle

    /// A photo is being taken. Keep the shutter disabled until it finishes.
    case capturing

    /// A photo was taken and is held in memory only.
    ///
    /// In this development stage nothing is saved. Say so plainly: "Captured (not saved yet:
    /// development build)". Announce it to VoiceOver.
    case captured(CapturedPhoto)

    /// The photo wasn't taken. Present the error as its documentation says, and announce it.
    case failed(CaptureError)
}
