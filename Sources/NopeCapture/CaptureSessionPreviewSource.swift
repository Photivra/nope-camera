import AVFoundation
import NopeCore

/// The AVFoundation backend's preview handle: the capture session, for an
/// `AVCaptureVideoPreviewLayer` in the app target.
///
/// `NopeCapture` can't import UIKit, so the app creates the preview view and assigns
/// ``session`` to its layer on the main thread, as Apple's AVCam sample does.
///
/// `@unchecked Sendable`: the session is only handed to a preview layer; all configuration
/// happens on ``SystemCaptureHardware``'s serial queue.
public final class CaptureSessionPreviewSource: CameraPreviewSource, @unchecked Sendable {
    /// The session to show in an `AVCaptureVideoPreviewLayer`.
    public let session: AVCaptureSession

    /// Creates a preview handle.
    ///
    /// - Parameter session: The capture session.
    public init(session: AVCaptureSession) {
        self.session = session
    }
}
