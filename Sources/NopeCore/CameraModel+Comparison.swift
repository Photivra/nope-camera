import Foundation

/// The comparison shot (issue #55): the app's photo, then the phone's fully processed version.
extension CameraModel {
    /// Whether the next photo is a comparison shot: the comparison is on, and the shutter takes
    /// one photo (single or self-timer, not a burst, a bracket, an interval series or an astro
    /// run). An
    /// interface shows "Hold the camera steady or use a tripod. Two photos are taken, a moment
    /// apart." while it is `true`.
    public var comparisonAppliesToNextPhoto: Bool {
        comparison.isOn && drive.mode != .burst && !astro.isOn && manual.intervalProgress == nil
            && manual.bracketFrames() == nil
    }

    /// The backend that takes the phone's version when the next photo is a comparison shot,
    /// otherwise `nil`.
    var comparisonBackendForNextPhoto: (any ComparisonCaptureBackend)? {
        guard comparisonAppliesToNextPhoto else { return nil }
        return comparison.backend
    }

    /// Takes the phone's version right after the app's photo, saves the app's photo as usual, and
    /// opens the compare view.
    ///
    /// Privacy: only the app's photo goes to ``PhotoSaver``. The phone's version is a
    /// ``PhoneProcessedPhoto``, which the saver can't take, and it is dropped when the app's photo
    /// fails to save. If the phone's version can't be taken, the app's photo is still saved and
    /// the compare view says why there is nothing to compare.
    ///
    /// Side effects: takes a second photo; may show the add-only Photos prompt; adds the app's
    /// photo to Photos.
    ///
    /// - Parameters:
    ///   - photo: the app's photo, just taken.
    ///   - started: When the app's photo was started.
    ///   - request: the app's request, which the phone's version repeats.
    ///   - settings: The settings the app's photo is saved with.
    ///   - backend: The backend that takes the phone's version.
    func saveComparing(
        _ photo: CapturedPhoto, started: ContinuousClock.Instant, request: CaptureRequest, settings: SaveSettings,
        backend: any ComparisonCaptureBackend
    ) async {
        let captureDuration = now() - started
        let secondStart = now()
        let phone = await comparison.takePhonePhoto(request, with: backend)
        guard let saver else {
            captureStatus = .failed(.savingUnavailable)
            return
        }
        captureStatus = .saving
        do {
            let result = try await saver.saveReturningFiles(photo, settings: settings, captureDuration: captureDuration)
            captureStatus = .saved(result.saved)
            await comparison.present(
                phone, saved: result.saved, files: result.files, delay: secondStart - started,
                mirrorsPhoneImage: request.metadata.mirrorsHorizontally)
        } catch {
            captureStatus = .failed(error)
        }
        deviceStatus.refresh()
    }
}
