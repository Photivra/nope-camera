import Foundation

/// Why the camera couldn't start or couldn't take a photo.
///
/// Each case says how an interface should present it. None of them is the person's fault, and
/// none asks them to change a setting.
public enum CaptureError: Error, Equatable, Sendable, CaseIterable {
    /// The camera isn't running, for example during an interruption.
    ///
    /// Say that no photo was taken because the camera is paused.
    case notRunning

    /// The selected lens couldn't be opened or configured.
    ///
    /// Say that the camera couldn't start, and offer to try another lens.
    case configurationFailed

    /// The system reported an error while taking the photo, or returned no file.
    ///
    /// Say that the photo wasn't taken and that the person can try again.
    case captureFailed

    /// The camera delivered a photo whose pixels are all one value (a zero-filled buffer): it
    /// is running and sending frames, but no picture. The photo is discarded.
    ///
    /// ``CameraModel`` restarts the camera once and retries; if the retry is blank too, it moves
    /// to ``SessionStatus/noPicture``. Say that no photo was taken because the camera sent a
    /// blank picture.
    case blankPicture
}
