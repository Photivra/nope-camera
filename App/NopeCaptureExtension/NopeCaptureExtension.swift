import AVKit
import ExtensionKit
import LockedCameraCapture
import NopeCapture
import NopeCore
import NopeDevelop
import NopeSigning
import NopeUI
import SwiftUI

/// The Lock Screen camera (LockedCameraCapture, iOS 18; issue #42): the app's camera, opened
/// from the "Open nope." control without unlocking the device.
///
/// The system starts it from ``OpenCameraIntent`` while the device is locked. It runs the same
/// `NopeCore` camera model and save pipeline as the app: single-frame Bayer RAW, the metadata
/// allowlist with its fail-closed read-back, a signature with a new key per photo, and add-only
/// saving to Photos (AGENTS.md, "Honesty"). It makes no network request.
///
/// While locked, the extension sees only what Apple allows it: its own container, not the
/// app's. So it keeps its own settings, starting from the app's defaults, and shows no button that
/// would open another app.
@main
struct NopeCaptureExtension: LockedCameraCaptureExtension {
    /// The extension's one scene: the camera screen.
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { _ in
            LockedCameraView()
        }
    }
}

/// The camera screen inside the Lock Screen capture extension.
///
/// It wires the same pieces as the app's camera screen (`NopeApp.cameraScreen`), less what a
/// locked device can't offer: opening the Settings or Photos app, Location (off by default),
/// and the storage and battery warnings, whose system reader uses app-only UIKit API.
struct LockedCameraView: View {
    /// The camera model, with the device's cameras and the full save pipeline.
    @State private var model = CameraModel(backend: AVFoundationCaptureBackend(), saver: Self.makeSaver())

    /// The extension's own settings, in its own container: the app's defaults until changed here.
    @State private var settings = NopeSettings(defaults: .standard)

    /// The camera screen, with the hardware shutter buttons.
    var body: some View {
        CameraScreen(model: model, settings: settings) { source in
            Viewfinder(source: source)
        }
        .environment(\.cameraGravitySource, MotionGravitySource())
        // The volume buttons and the Camera Control are the shutter while the camera runs, as in
        // the app (AVKit, `onCameraCaptureEvent`).
        .onCameraCaptureEvent(isEnabled: model.handlesHardwareButtons) { event in
            let phase: HardwareButtonPhase =
                switch event.phase {
                case .began: .pressed
                case .ended: .released
                default: .cancelled
                }
            Task { await model.send(.drive(.hardwareButton(phase))) }
        }
        .onChange(of: settings.save, initial: true) { _, save in
            model.saveSettings = save
        }
        .task(id: settings.showsManualControls) {
            await model.send(.manual(.setEnabled(settings.showsManualControls)))
        }
        .task(id: settings.fastShutter) {
            await model.send(.auto(.setFastShutter(settings.fastShutter)))
        }
        .task(id: settings.followsFaces) {
            await model.send(.auto(.setFollowsFaces(settings.followsFaces)))
        }
        .task(id: settings.photoSizes) {
            await model.send(.setPhotoSizes(settings.photoSizes))
        }
        .task(id: settings.startsInCleanView) {
            await model.send(.setCleanView(settings.startsInCleanView))
        }
        .task(id: settings.flashMode) {
            await model.send(.light(.setFlashMode(settings.flashMode)))
        }
        .task(id: settings.torchLevel) {
            await model.send(.light(.setTorchLevel(settings.torchLevel)))
        }
    }

    /// The same save pipeline as the app's: the RAW developer, the ImageIO read-back, add-only
    /// PhotoKit, and a signature with a new Secure Enclave key per file. If signing fails, the
    /// photo is saved unsigned and the status says so.
    private static func makeSaver() -> PhotoSaver {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return PhotoSaver(
            developer: RAWDeveloper(),
            signer: ContentCredentialsSigner(
                keyProvider: platformKeyProvider(), generator: ClaimGenerator(version: version)),
            reader: ImageIOReadBack(), library: PhotoKitLibrary(),
            appVersion: version, thumbnailer: ImageIOThumbnailer())
    }
}
