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

    /// A HEIF or JPEG couldn't be developed from the RAW, so nothing was saved.
    ///
    /// Say that the photo wasn't saved and that the person can try again.
    case developmentFailed

    /// A finished file failed the read-back: it held a tag, block or value that isn't on the
    /// metadata allowlist, its RAW image data changed, or it couldn't be read. Nothing was
    /// saved (AGENTS.md, "Fail closed").
    ///
    /// Say plainly that the photo wasn't saved because its details couldn't be confirmed as
    /// only the ones the person chose.
    case metadataNotAllowed

    /// nope. has no permission to add photos.
    ///
    /// Say that the photo wasn't saved, and that adding photos can be allowed in Settings.
    case photosAccessDenied

    /// Photos reported an error while adding the photo.
    ///
    /// Say that the photo wasn't saved and that the person can try again.
    case saveFailed

    /// This build of the app has no way to save photos (``CameraModel`` was created without a
    /// ``PhotoSaver``, as in previews and some tests).
    ///
    /// Say that the photo wasn't saved.
    case savingUnavailable
}
