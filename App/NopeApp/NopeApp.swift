import AVKit
import NopeCapture
import NopeCore
import NopeDevelop
import NopeSigning
import NopeUI
import SwiftUI
import UIKit

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
    @State private var model = CameraModel(backend: Self.backend, saver: Self.makeSaver())

    /// The person's settings, stored on the device only.
    @State private var settings = NopeSettings(defaults: Self.makeSettingsStore())

    /// Location tagging for photos (issue #43): off until the person turns Location on.
    @State private var location = LocationTagging(provider: Self.makeLocationProvider())

    /// Keeps the iPhone camera in portrait while sheets rotate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Which way up the person holds the iPhone, for the camera's upright icons.
    @State private var orientation = DeviceOrientation()

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
        CameraScreen(model: model, settings: settings) { source in
            Viewfinder(source: source)
        }
        .environment(\.cameraUprightRotation, orientation.rotation)
        .environment(\.cameraPresentsSheet, SheetPresentationAction { AppDelegate.setSheetPresented($0) })
        // Open Settings goes to nope.'s own page in the Settings app (UIKit,
        // `openSettingsURLString`), opened only when the person taps the button.
        .environment(
            \.openAppSettings,
            CameraAction {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
        // The last-photo thumbnail opens the Photos app (issue #36), only when the person taps
        // it. Add-only access can't read the library, and iOS has no documented way to open
        // Photos at one asset, so this opens Photos with its `photos-redirect:` URL, which isn't
        // documented by Apple either (an owner decision; docs/TESTING.md, "On-device checks").
        .environment(
            \.openPhotosApp,
            CameraAction {
                guard let url = URL(string: "photos-redirect://") else { return }
                UIApplication.shared.open(url)
            })
        .onCameraCaptureEvent { event in
            guard event.phase == .ended else { return }
            Task { await model.send(.capture) }
        }
        // The person's save settings (formats, metadata, signing) apply from the next photo.
        .onChange(of: settings.save, initial: true) { _, save in
            model.saveSettings = save
        }
        // Location runs only while the Location switch is on and the camera is running
        // (AGENTS.md, "Battery"); LocationTagging holds the rule.
        .task(id: [settings.metadata.isOn(.location), model.sessionStatus == .running]) {
            // Set once: assigning an observed property, even the same object, redraws the camera.
            if model.location !== location { model.location = location }
            await location.update(
                isOn: settings.metadata.isOn(.location), cameraIsRunning: model.sessionStatus == .running)
        }
        // The "Manual controls" option from Settings shows or hides the manual controls.
        .task(id: settings.showsManualControls) {
            await model.send(.manual(.setEnabled(settings.showsManualControls)))
        }
        // "Start in clean view": applied when the camera opens and whenever the option changes;
        // the camera's own button still toggles clean view at any time.
        .task(id: settings.startsInCleanView) {
            await model.send(.setCleanView(settings.startsInCleanView))
        }
        // The remembered flash mode and light brightness (issue #38); the light itself always
        // starts off.
        .task(id: settings.flashMode) {
            await model.send(.light(.setFlashMode(settings.flashMode)))
        }
        .task(id: settings.torchLevel) {
            await model.send(.light(.setTorchLevel(settings.torchLevel)))
        }
    }

    /// Where settings are stored: the app's standard `UserDefaults`, or in Debug builds launched
    /// by the UI tests, an empty store of their own, so every test starts from the defaults.
    private static func makeSettingsStore() -> UserDefaults {
        #if DEBUG
        if let store = SimulatedCameraLaunch.settingsStore() { return store }
        #endif
        return .standard
    }

    /// The location service for this launch: a simulated one for a UI test scenario in Debug
    /// builds, otherwise Core Location.
    private static func makeLocationProvider() -> any LocationProviding {
        #if DEBUG
        if let provider = SimulatedLocationLaunch.provider() { return provider }
        #endif
        return CoreLocationProvider()
    }

    /// The save pipeline for this launch: simulated steps for a UI test scenario in Debug builds,
    /// otherwise the RAW developer, the ImageIO read-back and add-only PhotoKit.
    ///
    /// Every file is signed with Content Credentials when the signature switch is on: a new
    /// Secure Enclave key per file on a device (`platformKeyProvider()`), fully offline. If
    /// signing fails, the photo is saved unsigned and the status says so.
    private static func makeSaver() -> PhotoSaver {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        #if DEBUG
        if let saver = SimulatedCameraLaunch.saver(appVersion: version) { return saver }
        #endif
        return PhotoSaver(
            developer: RAWDeveloper(),
            signer: ContentCredentialsSigner(
                keyProvider: platformKeyProvider(), generator: ClaimGenerator(version: version)),
            reader: ImageIOReadBack(), library: PhotoKitLibrary(),
            appVersion: version, thumbnailer: ImageIOThumbnailer())
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
