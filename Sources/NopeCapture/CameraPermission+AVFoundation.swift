import AVFoundation
import NopeCore

extension CameraPermission {
    /// Converts an AVFoundation authorization status to a `NopeCore` permission.
    ///
    /// A status added in a future iOS release is treated as `CameraPermission.restricted`:
    /// nope. must not assume access it can't confirm, and it must not ask again for a state it
    /// doesn't understand.
    ///
    /// - Parameter status: The value from
    ///   [`AVCaptureDevice.authorizationStatus(for:)`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/authorizationstatus(for:)).
    public init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .restricted
        }
    }
}
