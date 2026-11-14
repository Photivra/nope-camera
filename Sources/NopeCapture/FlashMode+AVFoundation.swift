import AVFoundation
import NopeCore

extension FlashMode {
    /// Converts an AVFoundation flash mode, such as one of the photo output's
    /// `supportedFlashModes`.
    ///
    /// - Parameter mode: The AVFoundation flash mode.
    /// - Returns: `nil` for a mode added in a later iOS, which nope. doesn't offer.
    init?(_ mode: AVCaptureDevice.FlashMode) {
        switch mode {
        case .off: self = .off
        case .auto: self = .auto
        case .on: self = .on
        @unknown default: return nil
        }
    }

    /// The AVFoundation flash mode for `AVCapturePhotoSettings.flashMode`.
    var captureFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: .off
        case .auto: .auto
        case .on: .on
        }
    }
}
