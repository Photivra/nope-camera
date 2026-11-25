import Foundation

/// Whether a lens lets the app turn off the camera's geometric distortion correction, as the
/// camera reports it (issue #80).
///
/// Geometric distortion correction reshapes the picture to lessen a wide lens's fisheye effect,
/// so it changes pixels. The app turns it off wherever the camera allows (`docs/PRIVACY.md`,
/// "Processing"). Apple's documentation says "RAW photo captures never have GDC applied,
/// regardless of the value of AVCaptureDevice.geometricDistortionCorrectionEnabled"
/// (`AVCaptureDevice.h`, `geometricDistortionCorrectionSupported`), so this matters only for a
/// lens's processed fallback. An interface discloses it in the lens's processing note and in
/// the photo's details.
///
/// The value is what the camera reports, not a measurement: whether a lens that offers no
/// switch corrects its photos anyway is checked on real devices (`docs/TESTING.md`).
public enum DistortionCorrection: Equatable, Sendable, CaseIterable {
    /// The camera lets apps turn the correction off
    /// (`AVCaptureDevice.isGeometricDistortionCorrectionSupported` is `true`), and the app turns
    /// it off.
    case turnedOff

    /// The camera offers apps no switch for the correction
    /// (`AVCaptureDevice.isGeometricDistortionCorrectionSupported` is `false`) and doesn't report
    /// whether its processed photos are corrected, so they may be.
    case notSwitchable
}
