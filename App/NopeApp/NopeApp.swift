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
    /// The capture backend for this launch, created once. The camera screen and, in Debug
    /// builds, the tag check share it, so the app never owns more than one capture session.
    private static let backend = makeBackend()

    /// The camera model shared by the app's single scene.
    @State private var model = CameraModel(backend: Self.backend)

    /// The app's single window, showing the camera screen.
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Debug builds only: `-NopeTagCheck`, `-NopeCameraProbe` or an armed run replace the
            // camera screen (docs/TESTING.md, "Tag check"). Release builds don't contain them.
            switch DebugRunLaunch.decision {
            case .perform(.tagCheck):
                // Drives the app's own backend: no second capture session.
                TagCheckScreen(backend: Self.backend)
            case .perform(.probe):
                // Apple's sample capture pipeline with its own session; the app's backend never
                // starts in this launch. Run it only on a freshly restarted phone
                // (docs/TESTING.md, "Black frames").
                CameraProbeScreen()
            case .armed(let run):
                Text(verbatim: "Debug run \(run.rawValue) armed. Close nope. and open it from the Home Screen.")
                    .padding()
            case .none:
                cameraScreen
            }
            #else
            cameraScreen
            #endif
        }
        // The Camera menu: Space takes a photo from a hardware keyboard, listed in the iPad
        // menu bar and keyboard shortcuts overlay.
        .commands { CameraCommands(model: model) }
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
