#if DEBUG
// Debug-only metadata tag check (issue #1, step 2). Compiled only in the Debug configuration.
//
// Privacy: this is the only code that writes photos to the app container, and it exists only
// in Debug builds. Release builds never write photos to the container ("Photos never linger",
// AGENTS.md). Files use complete file protection, and no location or GPS metadata is supplied.

import AVFoundation
import Foundation
import os

/// Captures test files with every physical camera and writes them, with a JSON report per lens,
/// to `Documents/TagCheck/`.
///
/// Capture setup follows docs/research/capability-survey.md, item 12 ("Avoiding processing").
/// Not thread-safe: create it and call ``runAll()`` on one serial queue, off the main thread,
/// because `AVCaptureSession.startRunning()` blocks.
final class TagCheckCapturer {
    /// How long to let auto exposure settle after the session starts, in seconds. A tool
    /// setting, not a platform value: the files only need a plausible exposure.
    private static let settleSeconds = 1.0

    /// How long to wait for one capture to finish, in seconds, before reporting a failure.
    private static let captureTimeoutSeconds = 30.0

    /// The physical camera types the tag check uses. Virtual multi-camera devices (dual, triple,
    /// TrueDepth, LiDAR depth) are never used: they can fuse frames from several cameras.
    private static let physicalDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
    ]

    /// Receives one status line per step, for the screen.
    private let report: @Sendable (String) -> Void

    /// The output folder, `Documents/TagCheck/`.
    private let folder: URL

    /// Logs progress. Lens names and file names are marked private.
    private let logger = Logger(subsystem: "com.photivra.nope", category: "TagCheck")

    /// Creates a capturer.
    /// - Parameter report: Called with each status line, from the capture queue.
    init(report: @escaping @Sendable (String) -> Void) {
        self.report = report
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
        do {
            try configure(session: session, device: device, output: output)
        } catch {
            status("\(lensName): failed to configure (\(error.localizedDescription))")
            outcome["error"] = error.localizedDescription
            return outcome
        }
        session.startRunning()
        defer { session.stopRunning() }
        Thread.sleep(forTimeInterval: Self.settleSeconds)

        lensReport.merge(TagCheckReport.describe(device: device, output: output)) { _, new in new }
        var captures: [String: Any] = [:]

        if let bayerFormat = output.availableRawPhotoPixelFormatTypes.first(where: {
            AVCapturePhotoOutput.isBayerRAWPixelFormat($0)
        }) {
            let raw = capture(settings: Self.speedSettings(.init(rawPixelFormatType: bayerFormat)), output: output)
            captures["raw"] = record(raw, lensName: lensName, suffix: "raw.dng", outcome: &outcome) {
                $0.fileDataRepresentation()
            }
            let remover = PrivateMetadataRemover()
            captures["rawStripped"] = record(
                raw, lensName: lensName, suffix: "raw-stripped.dng", outcome: &outcome
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

        let processedFormat = Self.processedFormat(for: output)
        let processed = capture(
            settings: Self.speedSettings(.init(format: [AVVideoCodecKey: processedFormat.codec])), output: output)
        captures["speed"] = record(
            processed, lensName: lensName, suffix: "speed.\(processedFormat.fileExtension)", outcome: &outcome
        ) {
            $0.fileDataRepresentation()
        }

        lensReport["captures"] = captures
        write(json: lensReport, to: "\(lensName)-report.json")
        status("\(lensName): finished")
        return outcome
    }

    /// Configures a photo session for one physical camera with as little processing as the
    /// public API allows (capability survey, item 12).
    ///
    /// - Throws: An error if the device can't be opened or added, or can't be locked to set
    ///   zoom and distortion correction.
    private func configure(
        session: AVCaptureSession, device: AVCaptureDevice, output: AVCapturePhotoOutput
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
        // ProRAW is demosaiced and may be multi-frame; only Bayer RAW is wanted (AGENTS.md).
        output.isAppleProRAWEnabled = false
        output.maxPhotoQualityPrioritization = .speed
        if output.isAutoDeferredPhotoDeliverySupported { output.isAutoDeferredPhotoDeliveryEnabled = false }
        if output.isConstantColorSupported { output.isConstantColorEnabled = false }
        if output.isContentAwareDistortionCorrectionSupported {
            output.isContentAwareDistortionCorrectionEnabled = false
        }
        session.commitConfiguration()

        // Bayer RAW requires videoZoomFactor 1.0 (AVCapturePhotoOutput.h, "Bayer RAW rules").
        try device.lockForConfiguration()
        device.videoZoomFactor = 1.0
        if device.isGeometricDistortionCorrectionSupported { device.isGeometricDistortionCorrectionEnabled = false }
        device.unlockForConfiguration()
    }

    // MARK: - Capture

    /// Applies the per-photo settings shared by every capture: speed prioritization (required
    /// for Bayer RAW), no flash, no content-aware distortion correction, no constant color.
    /// No location is set on the settings, so no GPS metadata is supplied.
    private static func speedSettings(_ settings: AVCapturePhotoSettings) -> AVCapturePhotoSettings {
        settings.photoQualityPrioritization = .speed
        settings.flashMode = .off
        settings.isAutoContentAwareDistortionCorrectionEnabled = false
        settings.isConstantColorEnabled = false
        return settings
    }

    /// HEVC in a HEIF container when the output offers it, otherwise JPEG.
    private static func processedFormat(for output: AVCapturePhotoOutput) -> (
        codec: AVVideoCodecType, fileExtension: String
    ) {
        output.availablePhotoCodecTypes.contains(.hevc) ? (.hevc, "heic") : (.jpeg, "jpg")
    }

    /// Captures one photo and waits for it.
    /// - Returns: The finished capture; its `photo` is `nil` on failure or timeout.
    private func capture(settings: AVCapturePhotoSettings, output: AVCapturePhotoOutput) -> PhotoCaptureWaiter {
        let waiter = PhotoCaptureWaiter(requestedSettings: settings)
        output.capturePhoto(with: settings, delegate: waiter)
        waiter.wait(seconds: Self.captureTimeoutSeconds)
        return waiter
    }

    /// Writes one capture's file and returns its report entry.
    /// - Parameters:
    ///   - capture: The finished capture.
    ///   - lensName: The file name prefix.
    ///   - suffix: The file name suffix, for example `raw.dng`.
    ///   - outcome: The lens summary; receives `done` or the failure for this file.
    ///   - fileData: Produces the file bytes from the photo.
    /// - Returns: The file name, requested and resolved settings, and `photo.metadata`.
    private func record(
        _ capture: PhotoCaptureWaiter, lensName: String, suffix: String, outcome: inout [String: Any],
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
        outcome[suffix] = "done"
        status("\(fileName): done")
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
