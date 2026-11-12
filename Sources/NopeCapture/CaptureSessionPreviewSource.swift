import AVFoundation
import NopeCore

/// The AVFoundation backend's preview handle: the capture session, for an
/// `AVCaptureVideoPreviewLayer` in the app target, and the rotation that keeps the viewfinder
/// and photos upright.
///
/// `NopeCapture` can't import UIKit, so the app creates the preview view and passes its layer to
/// ``connect(_:)`` on the main thread, as Apple's AVCam sample does.
///
/// `@unchecked Sendable`: the session is only handed to a preview layer; all configuration
/// happens on ``SystemCaptureHardware``'s serial queue. ``rotation`` is main-actor isolated.
public final class CaptureSessionPreviewSource: CameraPreviewSource, @unchecked Sendable {
    /// The session to show in an `AVCaptureVideoPreviewLayer`.
    public let session: AVCaptureSession

    /// Turns the preview and the photos upright for the camera in use; ``SystemCaptureHardware``
    /// tells it which camera that is.
    let rotation = PreviewRotation()

    /// Creates a preview handle.
    ///
    /// - Parameter session: The capture session.
    public init(session: AVCaptureSession) {
        self.session = session
    }

    /// Shows the session in a preview layer and keeps the layer upright in every orientation.
    ///
    /// Call it once for each new layer, on the main actor; a later layer replaces the earlier
    /// one for rotation. The rotation comes from `AVCaptureDevice.RotationCoordinator` (iOS 17),
    /// which also gives the angle written to each photo's orientation.
    ///
    /// - Parameter previewLayer: The app's preview layer.
    @MainActor public func connect(_ previewLayer: AVCaptureVideoPreviewLayer) {
        if previewLayer.session !== session { previewLayer.session = session }
        rotation.connect(previewLayer)
    }
}
