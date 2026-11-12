#if DEBUG
// Debug-only metadata tag check (issue #1, step 2). Compiled only in the Debug configuration.
//
// Privacy: this is the only code that writes photos to the app container, and it exists only
// in Debug builds. Release builds never write photos to the container ("Photos never linger",
// AGENTS.md). Files use complete file protection, and no location or GPS metadata is supplied.

import AVFoundation
import CoreImage
import Foundation
import NopeCapture
import os

/// Captures test files with every physical camera and writes them, with a JSON report per lens,
/// to `Documents/TagCheck/`.
///
/// Capture setup follows docs/research/capability-survey.md, item 12 ("Avoiding processing"),
/// in the same order as the app's capture backend (`SystemCaptureHardware`), which fixes the
/// black frames of the first device runs (docs/TESTING.md, "Black frames"). Each lens also gets
/// a JPEG of one live video frame, and every file's decoded brightness is in the report.
/// Not thread-safe: create it and call ``runAll()`` on one serial queue, off the main thread,
/// because `AVCaptureSession.startRunning()` blocks.
final class TagCheckCapturer {
    /// The shortest wait after the session starts, in seconds, before checking whether auto
    /// exposure, focus and white balance have settled. Tool settings, not platform values: the
    /// files only need a plausible exposure. The first device run captured black frames
    /// (ExposureTime 0, ISO 0) after a fixed 1-second wait with no video output attached.
    private static let minimumSettleSeconds = 1.0

    /// The longest wait for the camera to settle, in seconds; the report records a timeout.
    private static let settleTimeoutSeconds = 5.0

    /// How often to check the settle conditions, in seconds.
    private static let settlePollSeconds = 0.05

    /// Video frames that must arrive before the camera counts as streaming. An assumption: a
    /// few frames give auto exposure something to measure.
    private static let minimumFrames = 10

    /// How long to wait for one capture to finish, in seconds, before reporting a failure.
    private static let captureTimeoutSeconds = 30.0

    /// The longest wait for `setPreparedPhotoSettingsArray` to finish, in seconds.
    private static let prepareTimeoutSeconds = 5.0

    /// The longest wait for the photo output's `captureReadiness` to be `.ready`, in seconds.
    private static let readinessTimeoutSeconds = 2.0

    /// The longest wait for a live video frame to be saved as a JPEG, in seconds.
    private static let previewFrameTimeoutSeconds = 2.0

    /// The physical camera types the tag check uses. Virtual multi-camera devices (dual, triple,
    /// TrueDepth, LiDAR depth) are never used: they can fuse frames from several cameras.
    private static let physicalDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
    ]

    /// Receives one status line per step, for the screen.
    private let report: @Sendable (String) -> Void

    /// Receives the running session to show in the screen's viewfinder, or `nil` between lenses.
    private let showPreview: @Sendable (CaptureSessionPreviewSource?) -> Void

    /// The output folder, `Documents/TagCheck/`.
    private let folder: URL

    /// Logs progress. Lens names and file names are marked private.
    private let logger = Logger(subsystem: "com.photivra.nope", category: "TagCheck")

    /// Creates a capturer.
    /// - Parameters:
    ///   - report: Called with each status line, from the capture queue.
    ///   - showPreview: Called with the running session for each lens, and `nil` after it, from
    ///     the capture queue.
    init(
        report: @escaping @Sendable (String) -> Void,
        showPreview: @escaping @Sendable (CaptureSessionPreviewSource?) -> Void
    ) {
        self.report = report
        self.showPreview = showPreview
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appending(path: "TagCheck", directoryHint: .isDirectory)
    }

    /// Replaces `Documents/TagCheck/` with fresh files from every physical lens, then writes
    /// `summary.json`.
    ///
    /// Side effects: deletes and recreates `Documents/TagCheck/`, runs the camera, writes files.
    func runAll() {
        do {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            status("Could not create the TagCheck folder: \(error.localizedDescription)")
            return
        }
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: Self.physicalDeviceTypes, mediaType: .video, position: .unspecified
        ).devices.filter { !$0.isVirtualDevice }
        status("Found \(devices.count) physical camera(s)")

        var usedNames = Set<String>()
        var lenses: [[String: Any]] = []
        for device in devices {
            let name = Self.uniqueName(for: device, avoiding: &usedNames)
            lenses.append(captureAll(with: device, lensName: name))
        }
        var summary = TagCheckReport.deviceInfo()
        summary["lenses"] = lenses
        write(json: summary, to: "summary.json")
        status("Done: \(lenses.count) lens(es)")
    }

    // MARK: - One lens

    /// Captures the RAW, stripped RAW and processed files with one camera and writes its report.
    /// - Parameters:
    ///   - device: A physical camera.
    ///   - lensName: The file name prefix, for example `back-wide`.
    /// - Returns: A short summary for `summary.json`: the lens name and each file's outcome.
    private func captureAll(with device: AVCaptureDevice, lensName: String) -> [String: Any] {
        status("\(lensName): starting")
        var lensReport = TagCheckReport.deviceInfo()
        lensReport["lens"] = lensName
        var outcome: [String: Any] = ["lens": lensName]

        let session = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        let frameCounter = VideoFrameCounter()
        do {
            try configure(session: session, device: device, output: output, frameCounter: frameCounter)
        } catch {
            status("\(lensName): failed to configure (\(error.localizedDescription))")
            outcome["error"] = error.localizedDescription
            return outcome
        }
        session.startRunning()
        showPreview(CaptureSessionPreviewSource(session: session))
        defer {
            showPreview(nil)
            session.stopRunning()
        }
        let bayerFormat = output.availableRawPhotoPixelFormatTypes.first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
        let processedFormat = Self.processedFormat(for: output)
        lensReport["prepared"] = prepare(
            output: output,
            settings: bayerFormat.map { rawSettings($0, output: output) }
                ?? processedSettings(processedFormat.codec, output: output))
        let settle = waitUntilSettled(session: session, device: device, frameCounter: frameCounter)
        lensReport["settle"] = settle
        if settle["settled"] as? Bool != true {
            status("\(lensName): camera didn't settle in \(Self.settleTimeoutSeconds) s; capturing anyway")
        }
        lensReport["previewFrame"] = savePreviewFrame(from: frameCounter, lensName: lensName, outcome: &outcome)

        lensReport.merge(TagCheckReport.describe(device: device, output: output)) { _, new in new }
        var captures: [String: Any] = [:]

        if let bayerFormat {
            let raw = capture(settings: rawSettings(bayerFormat, output: output), output: output, device: device)
            captures["raw"] = record(raw, lensName: lensName, suffix: "raw.dng", isRAW: true, outcome: &outcome) {
                $0.fileDataRepresentation()
            }
            let remover = PrivateMetadataRemover()
            captures["rawStripped"] = record(
                raw, lensName: lensName, suffix: "raw-stripped.dng", isRAW: true, outcome: &outcome
            ) {
                $0.fileDataRepresentation(with: remover)
            }
            if var stripped = captures["rawStripped"] as? [String: Any] {
                stripped["removedKeys"] = remover.removedKeys
                captures["rawStripped"] = stripped
            }
        } else {
            status("\(lensName): no Bayer RAW format; processed photo only")
            outcome["raw"] = "no Bayer RAW format"
        }

        let processed = capture(
            settings: processedSettings(processedFormat.codec, output: output), output: output, device: device)
        captures["speed"] = record(
            processed, lensName: lensName, suffix: "speed.\(processedFormat.fileExtension)", isRAW: false,
            outcome: &outcome
        ) {
            $0.fileDataRepresentation()
        }

        lensReport["captures"] = captures
        write(json: lensReport, to: "\(lensName)-report.json")
        status("\(lensName): finished")
        return outcome
    }

    /// Configures a photo session for one physical camera with as little processing as the
    /// public API allows (capability survey, item 12), in the order the app's backend uses.
    ///
    /// 1. The `.photo` preset, the camera, the photo output and a video data output feeding
    ///    `frameCounter` are committed, so the camera's active format is the photo format.
    /// 2. The photo output's switches are committed before `startRunning()`, as
    ///    `AVCapturePhotoOutput.h` recommends for settings that reconfigure the pipeline:
    ///    `.speed`, no ProRAW, zero shutter lag and responsive capture off, no deferred delivery,
    ///    constant color or content-aware distortion correction, and an explicit
    ///    `maxPhotoDimensions` (the format's smallest supported size, the native 12 MP).
    /// 3. The camera is locked to zoom 1.0, geometric distortion correction off and continuous
    ///    auto exposure, focus and white balance.
    ///
    /// - Throws: An error if the device can't be opened or added, or can't be locked.
    private func configure(
        session: AVCaptureSession, device: AVCaptureDevice, output: AVCapturePhotoOutput,
        frameCounter: VideoFrameCounter
    ) throws {
        session.beginConfiguration()
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw TagCheckError.cannotAddToSession
        }
        session.addInput(input)
        session.addOutput(output)
        let videoOutput = AVCaptureVideoDataOutput()
        if session.canAddOutput(videoOutput) {
            videoOutput.setSampleBufferDelegate(frameCounter, queue: frameCounter.queue)
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()

        session.beginConfiguration()
        // ProRAW is demosaiced and may be multi-frame; only Bayer RAW is wanted (AGENTS.md).
        output.isAppleProRAWEnabled = false
        output.maxPhotoQualityPrioritization = .speed
        // Responsive capture requires zero shutter lag, so it goes off first. Zero shutter lag
        // (on by default since iOS 17) takes the photo from a buffer of earlier frames.
        output.isResponsiveCaptureEnabled = false
        output.isZeroShutterLagEnabled = false
        if output.isAutoDeferredPhotoDeliverySupported { output.isAutoDeferredPhotoDeliveryEnabled = false }
        if output.isConstantColorSupported { output.isConstantColorEnabled = false }
        if output.isContentAwareDistortionCorrectionSupported {
            output.isContentAwareDistortionCorrectionEnabled = false
        }
        if let smallest = device.activeFormat.supportedMaxPhotoDimensions.min(by: {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }) {
            output.maxPhotoDimensions = smallest
        }
        session.commitConfiguration()

        // Bayer RAW requires videoZoomFactor 1.0 (AVCapturePhotoOutput.h, "Bayer RAW rules").
        try device.lockForConfiguration()
        device.videoZoomFactor = 1.0
        if device.isGeometricDistortionCorrectionSupported { device.isGeometricDistortionCorrectionEnabled = false }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        device.unlockForConfiguration()
    }

    /// Prepares the photo output for the first capture (`setPreparedPhotoSettingsArray`): RAW
    /// captures need extra buffers, and unprepared captures allocate them on demand
    /// (`AVCapturePhotoOutput.h`).
    /// - Returns: For the report: whether it was prepared, any error, and whether it timed out.
    private func prepare(output: AVCapturePhotoOutput, settings: AVCapturePhotoSettings) -> [String: Any] {
        let done = DispatchSemaphore(value: 0)
        let result = OSAllocatedUnfairLock(initialState: (prepared: false, error: ""))
        output.setPreparedPhotoSettingsArray([settings]) { prepared, error in
            result.withLock { $0 = (prepared, error?.localizedDescription ?? "") }
            done.signal()
        }
        let timedOut = done.wait(timeout: .now() + Self.prepareTimeoutSeconds) == .timedOut
        let (prepared, error) = result.withLock { $0 }
        return ["prepared": prepared, "error": error, "timedOut": timedOut]
    }

    /// Saves one live video frame as `<lens>-preview.jpg` and measures it, to show whether the
    /// camera itself sees an exposed scene.
    /// - Returns: For the report: the file name and its luminance, or an error.
    private func savePreviewFrame(
        from frameCounter: VideoFrameCounter, lensName: String, outcome: inout [String: Any]
    ) -> [String: Any] {
        let fileName = "\(lensName)-preview.jpg"
        guard let frame = frameCounter.snapshot(timeout: Self.previewFrameTimeoutSeconds) else {
            outcome["preview.jpg"] = "failed: no video frame"
            return ["error": "no video frame within \(Self.previewFrameTimeoutSeconds) s"]
        }
        write(data: frame.jpeg, to: fileName)
        outcome["preview.jpg"] = "done"
        return ["file": fileName, "luminance": frame.luminance]
    }

    /// Waits until the session is running, frames are arriving, and auto exposure, focus and
    /// white balance have stopped adjusting; at least ``minimumSettleSeconds``, at most
    /// ``settleTimeoutSeconds``.
    /// - Returns: For the report: whether it settled, how long it took, and each condition.
    private func waitUntilSettled(
        session: AVCaptureSession, device: AVCaptureDevice, frameCounter: VideoFrameCounter
    ) -> [String: Any] {
        let start = Date()
        Thread.sleep(forTimeInterval: Self.minimumSettleSeconds)
        var settled = false
        while Date().timeIntervalSince(start) < Self.settleTimeoutSeconds {
            settled =
                session.isRunning && frameCounter.count >= Self.minimumFrames && !device.isAdjustingExposure
                && !device.isAdjustingFocus && !device.isAdjustingWhiteBalance
            if settled { break }
            Thread.sleep(forTimeInterval: Self.settlePollSeconds)
        }
        return [
            "settled": settled,
            "timedOut": !settled,
            "waitedSeconds": Date().timeIntervalSince(start),
            "minimumSettleSeconds": Self.minimumSettleSeconds,
            "timeoutSeconds": Self.settleTimeoutSeconds,
            "sessionRunning": session.isRunning,
            "framesDelivered": frameCounter.count,
            "isAdjustingExposure": device.isAdjustingExposure,
            "isAdjustingFocus": device.isAdjustingFocus,
            "isAdjustingWhiteBalance": device.isAdjustingWhiteBalance,
        ]
    }

    // MARK: - Capture

    /// RAW-only settings written as DNG, with no processed image (capability survey, item 12).
    private func rawSettings(_ pixelFormat: OSType, output: AVCapturePhotoOutput) -> AVCapturePhotoSettings {
        speedSettings(
            AVCapturePhotoSettings(
                rawPixelFormatType: pixelFormat, rawFileType: .dng, processedFormat: nil, processedFileType: nil),
            output: output)
    }

    /// Settings for one processed photo in its file container (HEIC or JPEG).
    private func processedSettings(_ codec: AVVideoCodecType, output: AVCapturePhotoOutput) -> AVCapturePhotoSettings {
        speedSettings(
            AVCapturePhotoSettings(
                rawPixelFormatType: 0, rawFileType: nil, processedFormat: [AVVideoCodecKey: codec],
                processedFileType: codec == .hevc ? .heic : .jpg),
            output: output)
    }

    /// Applies the per-photo settings shared by every capture: speed prioritization (required
    /// for Bayer RAW), no flash, no content-aware distortion correction, no constant color, and
    /// the output's `maxPhotoDimensions`. No location is set on the settings, so no GPS
    /// metadata is supplied.
    private func speedSettings(_ settings: AVCapturePhotoSettings, output: AVCapturePhotoOutput) -> AVCapturePhotoSettings {
        settings.photoQualityPrioritization = .speed
        settings.flashMode = .off
        settings.isAutoContentAwareDistortionCorrectionEnabled = false
        settings.isConstantColorEnabled = false
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        return settings
    }

    /// HEVC in a HEIF container when the output offers it, otherwise JPEG.
    private static func processedFormat(for output: AVCapturePhotoOutput) -> (
        codec: AVVideoCodecType, fileExtension: String
    ) {
        output.availablePhotoCodecTypes.contains(.hevc) ? (.hevc, "heic") : (.jpeg, "jpg")
    }

    /// Waits for the output to be ready, then captures one photo and waits for it, recording the
    /// readiness and the camera's exposure state at the shutter.
    /// - Returns: The finished capture; its `photo` is `nil` on failure or timeout.
    private func capture(
        settings: AVCapturePhotoSettings, output: AVCapturePhotoOutput, device: AVCaptureDevice
    ) -> PhotoCaptureWaiter {
        let start = Date()
        while output.captureReadiness != .ready, Date().timeIntervalSince(start) < Self.readinessTimeoutSeconds {
            Thread.sleep(forTimeInterval: Self.settlePollSeconds)
        }
        let waiter = PhotoCaptureWaiter(requestedSettings: settings)
        waiter.deviceStateAtCapture = TagCheckReport.exposureState(of: device)
        waiter.deviceStateAtCapture["captureReadiness"] = output.captureReadiness.rawValue
        waiter.deviceStateAtCapture["readinessWaitSeconds"] = Date().timeIntervalSince(start)
        output.capturePhoto(with: settings, delegate: waiter)
        waiter.wait(seconds: Self.captureTimeoutSeconds)
        return waiter
    }

    /// Writes one capture's file and returns its report entry.
    /// - Parameters:
    ///   - capture: The finished capture.
    ///   - lensName: The file name prefix.
    ///   - suffix: The file name suffix, for example `raw.dng`.
    ///   - isRAW: `true` for a DNG, which is decoded with `CIRAWFilter` for the luminance check.
    ///   - outcome: The lens summary; receives `done` or the failure for this file.
    ///   - fileData: Produces the file bytes from the photo.
    /// - Returns: The file name, requested and resolved settings, `photo.metadata`, and the
    ///   decoded image's luminance.
    private func record(
        _ capture: PhotoCaptureWaiter, lensName: String, suffix: String, isRAW: Bool, outcome: inout [String: Any],
        fileData: (AVCapturePhoto) -> Data?
    ) -> [String: Any] {
        let fileName = "\(lensName)-\(suffix)"
        var entry = TagCheckReport.describe(capture)
        entry["file"] = fileName
        guard let photo = capture.photo, let data = fileData(photo) else {
            let reason = capture.failureDescription ?? "no file data"
            status("\(fileName): failed (\(reason))")
            outcome[suffix] = "failed: \(reason)"
            entry["error"] = reason
            return entry
        }
        write(data: data, to: fileName)
        let luminance = ImageLuminance.measure(data: data, isRAW: isRAW)
        entry["luminance"] = luminance
        let black = ["looksBlack", "looksFlat", "looksZeroFilled"].contains { luminance[$0] as? Bool == true }
        outcome[suffix] = black ? "done, but the image looks black or flat" : "done"
        status("\(fileName): \(outcome[suffix] ?? "")")
        return entry
    }

    // MARK: - Files and status

    /// Writes bytes with complete file protection.
    private func write(data: Data, to fileName: String) {
        do {
            try data.write(to: folder.appending(path: fileName), options: [.atomic, .completeFileProtection])
        } catch {
            status("\(fileName): write failed (\(error.localizedDescription))")
        }
    }

    /// Writes a JSON report with sorted keys.
    private func write(json: [String: Any], to fileName: String) {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: TagCheckReport.jsonSafe(json), options: [.prettyPrinted, .sortedKeys])
            write(data: data, to: fileName)
        } catch {
            status("\(fileName): JSON failed (\(error.localizedDescription))")
        }
    }

    /// Shows a status line and logs it as a private value.
    private func status(_ text: String) {
        logger.info("Tag check: \(text, privacy: .private)")
        report(text)
    }

    /// A file name prefix such as `back-wide` or `front-ultrawide`, unique within one run.
    private static func uniqueName(for device: AVCaptureDevice, avoiding used: inout Set<String>) -> String {
        let position = device.position == .front ? "front" : "back"
        let kind =
            switch device.deviceType {
            case .builtInUltraWideCamera: "ultrawide"
            case .builtInTelephotoCamera: "telephoto"
            default: "wide"
            }
        let base = "\(position)-\(kind)"
        var name = base
        var index = 2
        while used.contains(name) {
            name = "\(base)-\(index)"
            index += 1
        }
        used.insert(name)
        return name
    }
}

/// Tag check failures that have no system error.
enum TagCheckError: LocalizedError {
    /// The session refused the camera input or the photo output.
    case cannotAddToSession

    /// A plain English description, for the status list.
    var errorDescription: String? {
        "The capture session refused the camera or the photo output."
    }
}

/// Receives one photo capture's delegate callbacks and lets the capture queue wait for them.
///
/// `@unchecked Sendable`: the delegate writes its properties on AVFoundation's callback queue
/// before signalling the semaphore, and the capture queue reads them only after the wait, so
/// the semaphore orders every access.
final class PhotoCaptureWaiter: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    /// The settings passed to `capturePhoto(with:delegate:)`.
    let requestedSettings: AVCapturePhotoSettings
    /// The camera's exposure, ISO, aperture, focus and white balance state just before the
    /// capture was requested. Set on the capture queue before the capture starts.
    var deviceStateAtCapture: [String: Any] = [:]
    /// The delivered photo, or `nil` on failure.
    private(set) var photo: AVCapturePhoto?
    /// The settings AVFoundation resolved for this capture.
    private(set) var resolvedSettings: AVCaptureResolvedPhotoSettings?
    /// The first error reported, if any.
    private(set) var error: (any Error)?
    /// `true` if the capture didn't finish before the timeout.
    private(set) var timedOut = false
    /// Signalled when the capture finishes.
    private let finished = DispatchSemaphore(value: 0)

    /// Creates a waiter for one capture.
    /// - Parameter requestedSettings: The settings the capture uses.
    init(requestedSettings: AVCapturePhotoSettings) {
        self.requestedSettings = requestedSettings
    }

    /// A short description of why there is no photo, or `nil` if there is one.
    var failureDescription: String? {
        if timedOut { return "timed out" }
        if let error { return error.localizedDescription }
        return photo == nil ? "no photo delivered" : nil
    }

    /// Blocks the calling queue until the capture finishes or the timeout passes.
    /// - Parameter seconds: The timeout, in seconds.
    func wait(seconds: Double) {
        timedOut = finished.wait(timeout: .now() + seconds) == .timedOut
    }

    /// Stores the delivered photo, or the error.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        self.photo = photo
        if self.error == nil { self.error = error }
    }

    /// Stores the resolved settings and ends the wait.
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: (any Error)?
    ) {
        self.resolvedSettings = resolvedSettings
        if self.error == nil { self.error = error }
        finished.signal()
    }
}

/// Removes private metadata through the system API when a photo is written to file data: the
/// planned native removal path (issue #1, "Privacy"), tested here on real captures.
///
/// Removes the `{MakerApple}` and `{GPS}` dictionaries, and every key inside another dictionary
/// whose name contains "SerialNumber" or "UniqueID" (for example BodySerialNumber,
/// LensSerialNumber, CameraSerialNumber, ImageUniqueID, RawDataUniqueID). UniqueCameraModel is
/// kept: it doesn't match, and RAW developers need it to find the camera profile.
final class PrivateMetadataRemover: NSObject, AVCapturePhotoFileDataRepresentationCustomizer {
    /// Top-level dictionaries removed whole.
    static let removedDictionaries = ["{MakerApple}", "{GPS}"]
    /// Key name fragments; a matching key inside any dictionary is removed.
    static let removedKeyFragments = ["serialnumber", "uniqueid"]

    /// The key paths removed from the last photo, for example `{Exif}.BodySerialNumber`.
    private(set) var removedKeys: [String] = []

    /// Returns the photo's metadata without the private keys.
    /// - Parameter photo: The photo being written.
    /// - Returns: The replacement metadata dictionary.
    func replacementMetadata(for photo: AVCapturePhoto) -> [String: Any]? {
        var metadata = photo.metadata
        removedKeys = []
        for name in Self.removedDictionaries where metadata[name] != nil {
            metadata[name] = nil
            removedKeys.append(name)
        }
        for (name, value) in metadata {
            guard var dictionary = value as? [String: Any] else { continue }
            for key in dictionary.keys where Self.matches(key) {
                dictionary[key] = nil
                removedKeys.append("\(name).\(key)")
            }
            metadata[name] = dictionary
        }
        removedKeys.sort()
        return metadata
    }

    /// `true` if a key name contains one of ``removedKeyFragments``, ignoring case.
    private static func matches(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return removedKeyFragments.contains { lowered.contains($0) }
    }
}
#endif

#if DEBUG
/// Counts video frames, so the tag check can tell that the camera is streaming, and on request
/// saves one frame as a JPEG.
///
/// `@unchecked Sendable`: the state is protected by a lock; AVFoundation calls the delegate on
/// ``queue`` while the capture queue reads ``count`` and calls ``snapshot(timeout:)``.
final class VideoFrameCounter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// One saved video frame.
    struct Frame {
        /// The frame as JPEG data.
        let jpeg: Data
        /// The frame's luminance, from ``ImageLuminance``, plus `pixelFormat` and the raw
        /// first-plane byte statistics (`plane0Min`, `plane0Max`, `plane0Mean`), read straight
        /// from the pixel buffer without any color conversion.
        let luminance: [String: Any]
    }

    /// The counter's state.
    private struct State {
        /// Frames delivered so far.
        var count = 0
        /// Whether the next frame should be saved.
        var wantsSnapshot = false
        /// The saved frame, once there is one.
        var snapshot: Frame?
    }

    /// The serial queue the video data output delivers frames on.
    let queue = DispatchQueue(label: "com.photivra.nope.tagcheck.frames")
    /// The state, behind a lock.
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    /// Encodes the saved frame.
    private let context = CIContext(options: [.cacheIntermediates: false])

    /// Frames delivered so far.
    var count: Int { state.withLock { $0.count } }

    /// Saves the next frame as a JPEG and waits for it, polling.
    /// - Parameter timeout: The longest wait, in seconds.
    /// - Returns: The frame, or `nil` if none arrived in time.
    func snapshot(timeout: Double) -> Frame? {
        state.withLock {
            $0.snapshot = nil
            $0.wantsSnapshot = true
        }
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let frame = state.withLockUnchecked({ $0.snapshot }) { return frame }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    /// Counts one frame, and saves it if a snapshot was requested. Other frames are dropped
    /// immediately.
    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        let wantsSnapshot = state.withLock {
            $0.count += 1
            defer { $0.wantsSnapshot = false }
            return $0.wantsSnapshot
        }
        guard wantsSnapshot, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let jpeg = context.jpegRepresentation(of: image, colorSpace: sRGB) else { return }
        var luminance = ImageLuminance.measure(image)
        luminance.merge(Self.planeStatistics(pixelBuffer)) { _, new in new }
        let frame = Frame(jpeg: jpeg, luminance: luminance)
        state.withLockUnchecked { $0.snapshot = frame }
    }

    /// The pixel format and the minimum, maximum and mean byte of the buffer's first plane (the
    /// luma plane of a 4:2:0 biplanar buffer), sampled every 16th byte. For a 32-bit BGRA
    /// buffer the bytes mix the channels, which is enough to tell zeros from an image.
    private static func planeStatistics(_ pixelBuffer: CVPixelBuffer) -> [String: Any] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let isPlanar = CVPixelBufferIsPlanar(pixelBuffer)
        guard
            let base = isPlanar
                ? CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) : CVPixelBufferGetBaseAddress(pixelBuffer)
        else { return ["plane0Error": "no base address"] }
        let rowBytes = isPlanar ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) : CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = isPlanar ? CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) : CVPixelBufferGetHeight(pixelBuffer)
        let bytes = Data(bytes: base, count: rowBytes * height)
        var minimum = UInt8.max
        var maximum = UInt8.min
        var total = 0
        var samples = 0
        for index in stride(from: 0, to: bytes.count, by: 16) {
            let value = bytes[index]
            minimum = min(minimum, value)
            maximum = max(maximum, value)
            total += Int(value)
            samples += 1
        }
        return [
            "pixelFormat": TagCheckReport.fourCharacterCode(CVPixelBufferGetPixelFormatType(pixelBuffer)),
            "plane0Min": Int(minimum), "plane0Max": Int(maximum),
            "plane0Mean": samples > 0 ? Double(total) / Double(samples) : 0,
        ]
    }
}
#endif
