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
public protocol CameraPreviewSource: AnyObject, Sendable {}

/// The preview source of ``SimulatedCaptureBackend``: it has no video.
///
/// An app shows a plain placeholder for it.
public final class SimulatedPreviewSource: CameraPreviewSource {
    /// Creates a simulated preview source.
    public init() {}
}
