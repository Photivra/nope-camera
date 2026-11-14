import Foundation

/// An opaque handle to the live camera feed, for the view that shows the viewfinder.
///
/// `NopeCore` can't show video: it imports only Foundation. A ``CaptureBackend`` hands out a
/// preview source through ``CaptureBackend/previewSource``, and the app target, which knows the
/// concrete type, turns it into a view (for the AVFoundation backend, a view backed by
/// `AVCaptureVideoPreviewLayer`). An interface receives that view from the app and never looks
/// inside the handle (AGENTS.md, "Architecture: interface separate from logic").
///
/// The live preview is processed by the system; it is a framing guide, not the photo.
public protocol CameraPreviewSource: AnyObject, Sendable {
    /// Converts a point in the viewfinder, as drawn, into the camera's own coordinates, the
    /// space `focusPointOfInterest` and `exposurePointOfInterest` use: the sensor's unrotated
    /// landscape frame, which differs from the screen when the preview is rotated or mirrored.
    ///
    /// ``CameraModel`` calls it for tap to focus (``AutoControlIntent/focusAndExpose(at:)``);
    /// an interface doesn't. On the main actor, because the conversion reads the preview view.
    ///
    /// - Parameter point: The point in the viewfinder, 0 to 1 across and down as drawn.
    /// - Returns: The point in the camera's coordinates, or `nil` when no viewfinder is shown
    ///   yet. The default implementation, for a source without video, returns `point`.
    @MainActor func devicePoint(forViewfinderPoint point: FramePoint) -> FramePoint?
}

extension CameraPreviewSource {
    /// Returns the point unchanged: a source without video has no rotation or mirroring.
    ///
    /// - Parameter point: The point in the viewfinder.
    /// - Returns: `point`.
    @MainActor public func devicePoint(forViewfinderPoint point: FramePoint) -> FramePoint? {
        point
    }
}

/// The preview source of ``SimulatedCaptureBackend``: it has no video.
///
/// An app shows a plain placeholder for it.
public final class SimulatedPreviewSource: CameraPreviewSource {
    /// Creates a simulated preview source.
    public init() {}
}
