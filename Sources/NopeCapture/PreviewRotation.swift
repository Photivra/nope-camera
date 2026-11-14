import AVFoundation
import os

// Hardware adapter: a rotation coordinator needs a camera device, which the Simulator doesn't
// have, so this file is listed in scripts/coverage-exclusions.txt and verified on a device
// (docs/TESTING.md, "On-device checks").

/// Keeps the live viewfinder and captured photos upright in every orientation, with
/// `AVCaptureDevice.RotationCoordinator` (iOS 17 and later).
///
/// The coordinator reports two angles for the camera in use, relative to gravity
/// (`AVCaptureDevice.h`): one for the preview layer, applied to the layer's connection as it
/// changes, and one for capture, which ``SystemCaptureHardware`` applies to the photo output's
/// connection before each photo. The two can differ for some combinations of device and
/// interface orientation, so they are kept apart. Each camera may need a different angle, for
/// example a front camera on the landscape edge of an iPad, so a new coordinator is made for each
/// camera.
///
/// Privacy: setting the photo connection's angle changes no pixels. "In the
/// AVCapturePhotoOutput, orientation is handled using Exif tags" (`AVCaptureSession.h`,
/// `videoRotationAngle`), so the angle becomes the photo's Orientation, a locked metadata item
/// (docs/PRIVACY.md, "Locked").
///
/// The coordinator delivers its updates on the main queue, so the class is main-actor isolated;
/// only ``captureAngle`` is read from the capture queue, through a lock.
@MainActor
final class PreviewRotation {
    /// The app's preview layer. The coordinator holds it weakly too.
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    /// The unique ID of the camera in use, or `nil` before one is configured.
    private var deviceID: String?

    /// The coordinator for the camera in use and the preview layer.
    private var coordinator: AVCaptureDevice.RotationCoordinator?

    /// The coordinator's angle observations; replacing them stops the old ones.
    private var observations: [NSKeyValueObservation] = []

    /// The latest capture angle, in degrees, for the capture queue.
    private nonisolated let captureAngleStore = OSAllocatedUnfairLock<CGFloat?>(initialState: nil)

    /// Creates a rotation helper with no camera and no layer.
    nonisolated init() {}

    /// The angle, in degrees, to apply to the photo output's connection for an upright photo,
    /// or `nil` when no camera is configured yet. Safe to read from any thread.
    nonisolated var captureAngle: CGFloat? {
        captureAngleStore.withLock { $0 }
    }

    /// Uses a new preview layer.
    ///
    /// - Parameter previewLayer: The app's preview layer.
    func connect(_ previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        rebuild()
    }

    /// Follows a newly configured camera. Call it after the camera's input is in the session,
    /// so the preview layer's connection exists.
    ///
    /// - Parameter deviceID: The camera's `AVCaptureDevice.uniqueID`.
    func use(deviceID: String) {
        self.deviceID = deviceID
        rebuild()
    }

    /// Replaces the coordinator for the current camera and layer, and applies its angles at
    /// once.
    private func rebuild() {
        observations = []
        coordinator = nil
        captureAngleStore.withLock { $0 = nil }
        guard let deviceID, let device = AVCaptureDevice(uniqueID: deviceID) else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        self.coordinator = coordinator
        let captureAngleStore = captureAngleStore
        observations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) {
                [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                // Updates arrive on the main queue (AVCaptureDevice.h); `.initial` runs here.
                MainActor.assumeIsolated { self?.applyPreviewAngle(angle) }
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) {
                coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                captureAngleStore.withLock { $0 = angle }
            },
        ]
    }

    /// Rotates the preview layer's video, if its connection supports the angle (only 0, 90,
    /// 180 and 270 degrees are supported, `AVCaptureSession.h`).
    ///
    /// - Parameter angle: The coordinator's preview angle, in degrees.
    private func applyPreviewAngle(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
