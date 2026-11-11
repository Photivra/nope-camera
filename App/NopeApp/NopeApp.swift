import AVKit
import NopeCapture
import NopeCore
import NopeUI
import SwiftUI

/// The nope. app: wires the capture backend into `NopeCore` and hosts `NopeUI`.
///
/// On a device it uses `AVFoundationCaptureBackend`. Debug builds launched by the UI tests with
/// `-NopeSimulatedCamera <scenario>` use a simulated backend instead (``SimulatedCameraLaunch``).
@main
struct NopeApp: App {
    /// The camera model shared by the app's single scene.
    @State private var model = CameraModel(backend: Self.makeBackend())

    /// The app's single window, showing the camera screen.
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Debug builds only: `-NopeTagCheck` runs the metadata tag check instead
            // (docs/TESTING.md, "Tag check"). Release builds don't contain it.
            if TagCheckLaunch.isRequested {
                TagCheckScreen()
            } else {
                cameraScreen
            }
            #else
            cameraScreen
            #endif
        }
    }

    /// The camera screen with the live viewfinder and the hardware shutter.
    ///
    /// The volume buttons and the Camera Control take a photo through `onCameraCaptureEvent`
    /// (AVKit, iOS 18), on release of the button, as the system Camera app does. The system
    /// delivers these events only while a capture session runs.
    private var cameraScreen: some View {
        CameraScreen(model: model) { source in
            Viewfinder(source: source)
        }
        .onCameraCaptureEvent { event in
            guard event.phase == .ended else { return }
            Task { await model.send(.capture) }
        }
    }

    /// The backend for this launch: the simulated one for a UI test scenario in Debug builds,
    /// otherwise the device's cameras.
    private static func makeBackend() -> any CaptureBackend {
        #if DEBUG
        if let backend = SimulatedCameraLaunch.backend() { return backend }
        #endif
        return AVFoundationCaptureBackend()
    }
}
