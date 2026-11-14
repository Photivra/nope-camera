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

    /// The preview layer connected last, for converting viewfinder points. Main-actor
    /// isolated, like every layer call.
    @MainActor private weak var previewLayer: AVCaptureVideoPreviewLayer?

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
        self.previewLayer = previewLayer
        rotation.connect(previewLayer)
    }

    /// Converts a viewfinder point into the camera's coordinates with the connected layer's
    /// `captureDevicePointConverted(fromLayerPoint:)`, which accounts for the layer's video
    /// gravity, rotation and front-camera mirroring (`AVCaptureVideoPreviewLayer.h`).
    ///
    /// - Parameter point: The point in the viewfinder, 0 to 1 across and down as drawn.
    /// - Returns: The camera point, or `nil` before a layer is connected or while it has no
    ///   size.
    @MainActor public func devicePoint(forViewfinderPoint point: FramePoint) -> FramePoint? {
        guard let previewLayer, previewLayer.bounds.width > 0, previewLayer.bounds.height > 0 else { return nil }
        let layerPoint = CGPoint(
            x: previewLayer.bounds.minX + point.x * previewLayer.bounds.width,
            y: previewLayer.bounds.minY + point.y * previewLayer.bounds.height)
        let converted = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        return FramePoint(x: Double(converted.x), y: Double(converted.y))
    }
}
