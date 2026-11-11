import NopeCore
import NopeUI
import SwiftUI

/// The nope. app: wires a capture backend into `NopeCore` and hosts `NopeUI`.
///
/// Until the AVFoundation adapter in `NopeCapture` is wired in, the app uses
/// ``developmentBackend``, which shows no system prompt and reports one simulated lens.
@main
struct NopeApp: App {
    /// A simulated backend for development builds: asking for access succeeds, and the device
    /// reports one wide lens with RAW. No camera hardware is used.
    static let developmentBackend = SimulatedCaptureBackend(
        permission: .notDetermined,
        permissionAfterRequest: .authorized,
        capabilities: DeviceCapabilities(lenses: [Lens(id: "simulated-wide", kind: .wide, supportsBayerRAW: true)])
    )

    /// The camera model shared by the app's single scene.
    @State private var model = CameraModel(backend: developmentBackend)

    /// The app's single window, showing the camera screen.
    var body: some Scene {
        WindowGroup {
            CameraScreen(model: model)
        }
    }
}
