import AVFoundation
import NopeCapture
import NopeCore
import SwiftUI
import UIKit

/// The live viewfinder for a `CameraPreviewSource`: an `AVCaptureVideoPreviewLayer` for the
/// AVFoundation backend, and a plain dark area for the simulated backend.
///
/// It lives in the app target because `NopeUI` may import only `NopeCore` and SwiftUI, and
/// `NopeCapture` may not import UIKit (AGENTS.md, "Architecture"). The app passes it to
/// `CameraScreen`.
struct Viewfinder: View {
    /// The preview handle from the camera model.
    let source: any CameraPreviewSource

    /// Creates the viewfinder.
    ///
    /// - Parameter source: The preview handle from the camera model.
    init(source: any CameraPreviewSource) {
        self.source = source
    }

    /// The preview layer, or a placeholder when there is no video.
    var body: some View {
        if let capture = source as? CaptureSessionPreviewSource {
            CameraPreviewView(source: capture)
        } else {
            Color(white: 0.12)
        }
    }
}

/// Shows an `AVCaptureSession` with `AVCaptureVideoPreviewLayer`, upright in every orientation.
///
/// The whole frame is shown (`resizeAspect`), so what is framed is what the 4:3 photo
/// contains. The layer mirrors the front camera's preview by default
/// (`AVCaptureConnection.automaticallyAdjustsVideoMirroring`); saved photos aren't mirrored.
/// `CaptureSessionPreviewSource.connect(_:)` attaches the session and rotates the layer with
/// `AVCaptureDevice.RotationCoordinator`.
struct CameraPreviewView: UIViewRepresentable {
    /// The preview handle whose session to show.
    let source: CaptureSessionPreviewSource

    /// Creates the preview view.
    ///
    /// - Parameter source: The preview handle whose session to show.
    init(source: CaptureSessionPreviewSource) {
        self.source = source
    }

    /// Creates the layer-backed view and connects it to the session.
    ///
    /// - Parameter context: The representable context.
    func makeUIView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.previewLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        source.connect(view.previewLayer)
        return view
    }

    /// Reconnects the layer if the session changed.
    ///
    /// - Parameters:
    ///   - view: The view.
    ///   - context: The representable context.
    func updateUIView(_ view: PreviewLayerView, context: Context) {
        if view.previewLayer.session !== source.session { source.connect(view.previewLayer) }
    }
}

/// A view whose backing layer is an `AVCaptureVideoPreviewLayer`, so it resizes with the view.
final class PreviewLayerView: UIView {
    /// Makes the backing layer a preview layer.
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    /// The backing layer.
    var previewLayer: AVCaptureVideoPreviewLayer {
        // The cast always succeeds: layerClass is AVCaptureVideoPreviewLayer.
        layer as! AVCaptureVideoPreviewLayer
    }
}
