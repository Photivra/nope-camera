#if DEBUG
// Debug-only camera probe (docs/TESTING.md, "Black frames"). Compiled only in the Debug
// configuration: Release builds contain none of this code.
//
// The probe runs the simplest capture pipeline from Apple's documented sample flow ("Setting up
// a capture session", "Capturing still and Live Photos", AVCam): the `.photo` preset, the
// default video camera, a preview layer, a video data output and one default HEVC photo. It
// records the app, scene and session state around it, so a black frame can be traced to the
// pipeline or to the environment.
//
// Privacy: like the tag check, it writes one photo and one video frame to the app container in
// Debug builds only, with complete file protection and no location.

@preconcurrency import AVFoundation
import CoreImage
import SwiftUI
import UIKit
import os

/// Decides whether this launch runs the debug-only camera probe instead of the camera screen.
enum CameraProbeLaunch {
    /// The launch argument that starts the probe: `-NopeCameraProbe`.
    static let argument = "-NopeCameraProbe"

    /// `true` when the current process was launched with ``argument``.
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }
}

/// The probe screen: the session's preview layer full-screen, with one status line on top.
struct CameraProbeScreen: View {
    /// The probe, created once per screen.
    @State private var probe = CameraProbe()

    /// The full-screen preview and the status line.
    var body: some View {
        ZStack(alignment: .top) {
            CameraPreviewView(session: probe.session)
                .ignoresSafeArea()
            Text(verbatim: probe.status)
                .padding()
                .background(.regularMaterial)
        }
        .task {
            await probe.run()
        }
    }
}

/// Runs the probe and writes `probe-report.json`, `probe-photo.heic` and `probe-frame.jpg` to
/// `Documents/TagCheck/`.
///
/// Main-actor isolated for the status line and the app and scene state; the session work runs
/// on ``queue`` because `startRunning()` blocks.
@MainActor
@Observable
final class CameraProbe {
    /// The session shown by the preview layer.
    let session = AVCaptureSession()

    /// One line of progress, in English (debug tool, not localized).
    private(set) var status = "Camera probe: starting"

    /// The queue that owns the session.
    @ObservationIgnored private let queue = DispatchQueue(label: "com.photivra.nope.probe")

    /// Logs progress; values are private.
    @ObservationIgnored private let logger = Logger(subsystem: "com.photivra.nope", category: "CameraProbe")

    /// Session notifications seen during the run, oldest first.
    @ObservationIgnored private let events = OSAllocatedUnfairLock(initialState: [String]())

    /// Runs the probe once and writes the report.
    func run() async {
        let launchEnvironment = environment()
        let accessGranted = await AVCaptureDevice.requestAccess(for: .video)
        observeSessionNotifications()
        update("Camera probe: running")
        let pipeline = ProbePipeline(session: session)
        let result: ProbeReport = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: pipeline.run(environment: {
                    DispatchQueue.main.sync { MainActor.assumeIsolated { ProbeReport(self.environment()) } }
                }))
            }
        }
        var report = result.value
        report["environmentAtLaunch"] = launchEnvironment
        report["requestAccess"] = accessGranted
        report["sessionEvents"] = events.withLock { $0 }
        report["deviceInfo"] = TagCheckReport.deviceInfo()
        ProbePipeline.write(json: report, to: ProbePipeline.folder().appending(path: "probe-report.json"))
        let frameLuma = (report["frame"] as? [String: Any])?["luminance"] as? [String: Any]
        let photoLuma = (report["photo"] as? [String: Any])?["luminance"] as? [String: Any]
        update(
            "Camera probe: done. Frame max luma \(frameLuma?["maxLuma"] ?? "?"), photo max luma \(photoLuma?["maxLuma"] ?? "?")"
        )
    }

    // MARK: - Environment

    /// App, scene, window and camera authorization state, read on the main actor.
    private func environment() -> [String: Any] {
        let application = UIApplication.shared
        let scenes = application.connectedScenes.map { scene -> [String: Any] in
            var entry: [String: Any] = ["activationState": scene.activationState.rawValue]
            if let windowScene = scene as? UIWindowScene {
                entry["windows"] = windowScene.windows.count
                entry["keyWindow"] = windowScene.keyWindow != nil
            }
            return entry
        }
        return [
            "applicationState": application.applicationState.rawValue,
            "scenes": scenes,
            "authorizationStatus": AVCaptureDevice.authorizationStatus(for: .video).rawValue,
            "isLowPowerModeEnabled": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
            "arguments": ProcessInfo.processInfo.arguments.dropFirst().map { $0 },
        ]
    }

    /// Records the session's interruption, runtime error and start and stop notifications.
    private func observeSessionNotifications() {
        let names: [Notification.Name] = [
            AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification,
            AVCaptureSession.runtimeErrorNotification, AVCaptureSession.didStartRunningNotification,
            AVCaptureSession.didStopRunningNotification,
        ]
        let events = events
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { note in
                let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int).map { " reason=\($0)" }
                let error = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError).map { " error=\($0.domain) \($0.code)" }
                let text = name.rawValue + (reason ?? "") + (error ?? "")
                events.withLock { $0.append(text) }
            }
        }
    }

    // MARK: - Helpers

    /// Shows and logs a status line.
    private func update(_ text: String) {
        status = text
        logger.info("\(text, privacy: .private)")
    }

}

/// A JSON report dictionary passed between the probe queue and the main actor.
///
/// `@unchecked Sendable`: each value is created on one queue and handed over once, never shared.
struct ProbeReport: @unchecked Sendable {
    /// The report entries.
    var value: [String: Any]

    /// Wraps report entries.
    init(_ value: [String: Any]) {
        self.value = value
    }
}

/// The probe's capture work, run on the probe's serial queue.
///
/// `@unchecked Sendable`: it is created on the main actor and then used only on that queue.
final class ProbePipeline: @unchecked Sendable {
    /// How long the session runs before a frame and a photo are taken, in seconds. A tool
    /// setting: enough for auto exposure to converge in a lit room.
    static let runSeconds = 3.0

    /// The longest wait for the photo, in seconds.
    static let captureTimeoutSeconds = 10.0

    /// `-NopeProbeNoVideoOutput`: leave out the video data output, as the camera screen does,
    /// to tell whether attaching one changes the photo.
    static var omitsVideoOutput: Bool {
        ProcessInfo.processInfo.arguments.contains("-NopeProbeNoVideoOutput")
    }

    /// The session, also shown by the screen's preview layer.
    let session: AVCaptureSession

    /// Creates the pipeline for a session.
    init(session: AVCaptureSession) {
        self.session = session
    }

    /// Configures and starts the session, waits ``runSeconds``, saves a frame and a photo, and
    /// stops the session.
    /// - Parameter environment: Reads the app and scene state on the main actor.
    func run(environment: () -> ProbeReport) -> ProbeReport {
        let frames = VideoFrameCounter()
        let photoOutput = AVCapturePhotoOutput()
        var report: [String: Any] = [:]
        report["configuration"] = Self.configure(session: session, photoOutput: photoOutput, frames: frames)
        session.startRunning()
        report["afterStart"] = Self.sessionState(session)
        Thread.sleep(forTimeInterval: Self.runSeconds)
        report["environmentAtCapture"] = environment().value
        let captured = Self.captureFrameAndPhoto(
            session: session, photoOutput: photoOutput, frames: frames, folder: Self.folder())
        report.merge(captured) { _, new in new }
        session.stopRunning()
        return ProbeReport(report)
    }

    // MARK: - Pipeline

    /// Apple's sample configuration: `.photo` preset, the default camera, a photo output and a
    /// default video data output, in one configuration transaction.
    static func configure(
        session: AVCaptureSession, photoOutput: AVCapturePhotoOutput, frames: VideoFrameCounter
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(for: .video) else {
            result["error"] = "no default video device"
            return result
        }
        result["deviceType"] = device.deviceType.rawValue
        result["isSuspended"] = device.isSuspended
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                result["error"] = "cannot add input"
                return result
            }
            session.addInput(input)
        } catch {
            result["error"] = error.localizedDescription
            return result
        }
        guard session.canAddOutput(photoOutput) else {
            result["error"] = "cannot add photo output"
            return result
        }
        session.addOutput(photoOutput)
        result["videoDataOutput"] = !omitsVideoOutput
        let videoOutput = AVCaptureVideoDataOutput()
        if !omitsVideoOutput, session.canAddOutput(videoOutput) {
            videoOutput.setSampleBufferDelegate(frames, queue: frames.queue)
            session.addOutput(videoOutput)
        }
        result["isMultitaskingCameraAccessSupported"] = session.isMultitaskingCameraAccessSupported
        result["isMultitaskingCameraAccessEnabled"] = session.isMultitaskingCameraAccessEnabled
        return result
    }

    /// Saves one video frame, then captures one default HEVC photo (JPEG without HEVC), as
    /// AVCam does.
    static func captureFrameAndPhoto(
        session: AVCaptureSession, photoOutput: AVCapturePhotoOutput, frames: VideoFrameCounter, folder: URL
    ) -> [String: Any] {
        var result: [String: Any] = ["beforeCapture": sessionState(session)]
        if let device = (session.inputs.first as? AVCaptureDeviceInput)?.device {
            result["exposureState"] = TagCheckReport.exposureState(of: device)
            result["isSuspended"] = device.isSuspended
        }
        result["framesDelivered"] = frames.count
        if !omitsVideoOutput, let frame = frames.snapshot(timeout: 2) {
            write(data: frame.jpeg, to: folder.appending(path: "probe-frame.jpg"))
            result["frame"] = ["file": "probe-frame.jpg", "luminance": frame.luminance]
        } else {
            result["frame"] = ["error": "no frame"]
        }
        let settings =
            photoOutput.availablePhotoCodecTypes.contains(.hevc)
            ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc]) : AVCapturePhotoSettings()
        let waiter = PhotoCaptureWaiter(requestedSettings: settings)
        photoOutput.capturePhoto(with: settings, delegate: waiter)
        waiter.wait(seconds: captureTimeoutSeconds)
        var photoEntry = TagCheckReport.describe(waiter)
        if let photo = waiter.photo, let data = photo.fileDataRepresentation() {
            write(data: data, to: folder.appending(path: "probe-photo.heic"))
            photoEntry["file"] = "probe-photo.heic"
            photoEntry["bytes"] = data.count
            photoEntry["luminance"] = ImageLuminance.measure(data: data, isRAW: false)
            photoEntry["exif"] = photo.metadata["{Exif}"] ?? [:]
        } else {
            photoEntry["error"] = waiter.failureDescription ?? "no file data"
        }
        result["photo"] = photoEntry
        result["afterCapture"] = sessionState(session)
        return result
    }

    /// The session's running and interruption state.
    static func sessionState(_ session: AVCaptureSession) -> [String: Any] {
        ["isRunning": session.isRunning, "isInterrupted": session.isInterrupted]
    }

    /// `Documents/TagCheck/`, created if needed.
    static func folder() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appending(path: "TagCheck", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes bytes with complete file protection.
    static func write(data: Data, to url: URL) {
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Writes a JSON report with sorted keys.
    static func write(json: [String: Any], to url: URL) {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: TagCheckReport.jsonSafe(json), options: [.prettyPrinted, .sortedKeys])
        else { return }
        write(data: data, to: url)
    }
}
#endif
