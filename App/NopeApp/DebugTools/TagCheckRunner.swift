#if DEBUG
// Debug-only metadata tag check (issue #1, step 2). Compiled only in the Debug configuration.
//
// Privacy: this is the only code that writes photos to the app container, and it exists only
// in Debug builds. Release builds never write photos to the container ("Photos never linger",
// AGENTS.md). Files use complete file protection, and no location or GPS metadata is supplied.

import Foundation
import NopeCore
import os

/// Captures test files with every lens through the app's own capture backend and writes them,
/// with a JSON report per lens, to `Documents/TagCheck/`.
///
/// It drives the real `AVFoundationCaptureBackend` through the `CaptureBackend` API only, as the
/// camera screen does: one capture session owned by `NopeCapture`, lenses switched with
/// `startSession(_:)`, photos taken with `capturePhoto(_:)`, and `stopSession()` (a sequential
/// teardown) at the end. It creates no session, input or output of its own. An earlier version
/// built a separate session per lens with an extra video data output; after it ran, the camera
/// service delivered zero-filled buffers to every session until the phone was restarted
/// (docs/TESTING.md, "Black frames").
///
/// The files are therefore exactly what the app captures: the backend's processing switches
/// and photo settings (`CapturePolicy`, `PhotoSettingsFactory`), and its blank-picture check,
/// which rejects a zero-filled RAW buffer with `CaptureError.blankPicture`.
@MainActor
struct TagCheckRunner {
    /// How long a lens runs after `startSession(_:)` before its first capture, in seconds, so
    /// continuous auto exposure, focus and white balance can converge. A tool setting, not a
    /// platform value: the files only need a plausible exposure.
    static let settleSeconds = 2.0

    /// How long to wait after switching the same lens to another format, in seconds. A tool
    /// setting: the camera keeps running, only the photo output is re-prepared.
    static let formatSwitchSettleSeconds = 0.5

    /// The app's capture backend.
    let backend: any CaptureBackend

    /// Receives one status line per step.
    let progress: TagCheckProgress

    /// Logs progress. Lens names and file names are marked private.
    private let logger = Logger(subsystem: "com.photivra.nope", category: "TagCheck")

    /// Creates a runner.
    /// - Parameters:
    ///   - backend: The app's capture backend.
    ///   - progress: Receives one status line per step.
    init(backend: any CaptureBackend, progress: TagCheckProgress) {
        self.backend = backend
        self.progress = progress
    }

    /// Asks for camera access if needed, replaces `Documents/TagCheck/` with fresh files from
    /// every lens, writes `summary.json`, and stops the camera.
    ///
    /// Side effects: may show the camera permission prompt; deletes and recreates
    /// `Documents/TagCheck/`; runs the camera; writes files.
    func run() async {
        defer { progress.finish() }
        guard await hasCameraAccess() else {
            status("Camera access denied. Allow it in Settings and relaunch.")
            return
        }
        guard TagCheckFiles.resetFolder() else {
            status("Could not create the TagCheck folder")
            return
        }
        let lenses = await backend.deviceCapabilities().lenses
        status("Found \(lenses.count) lens(es)")
        var usedNames = Set<String>()
        var summaries: [[String: Any]] = []
        progress.showsPreview = true
        for lens in lenses {
            summaries.append(await check(lens, name: Self.uniqueName(for: lens.kind, avoiding: &usedNames)))
        }
        progress.showsPreview = false
        // Stop and tear down the one session before writing the summary; stopSession returns
        // only once the session has stopped and its input and output are removed.
        await backend.stopSession()
        var summary = TagCheckReport.deviceInfo()
        summary["lenses"] = summaries
        await TagCheckFiles.write(json: ProbeReport(summary), to: "summary.json")
        status("Done: \(summaries.count) lens(es)")
    }

    /// Returns `true` once camera access is authorized, asking if the person hasn't decided.
    private func hasCameraAccess() async -> Bool {
        status("Checking camera access")
        var permission = await backend.currentPermission()
        if permission == .notDetermined { permission = await backend.requestPermission() }
        return permission == .authorized
    }

    // MARK: - One lens

    /// Captures the Bayer RAW (when the lens has it) and the processed `.speed` photo with one
    /// lens, and writes its report.
    /// - Parameters:
    ///   - lens: A lens from the backend's capabilities.
    ///   - name: The file name prefix, for example `back-wide`.
    /// - Returns: A short summary for `summary.json`: the lens name and each file's outcome.
    private func check(_ lens: Lens, name: String) async -> [String: Any] {
        status("\(name): starting")
        var report = TagCheckReport.deviceInfo()
        report["lens"] = name
        report["lensCapabilities"] = TagCheckReport.describe(lens)
        var outcome: [String: Any] = ["lens": name]
        var captures: [String: Any] = [:]
        var settle = Self.settleSeconds
        if let pixelFormat = lens.bayerRAWFormat {
            let request = CaptureRequest(lens: lens, format: .bayerRAW(pixelFormat: pixelFormat))
            captures["raw"] = await capture(request, fileName: "\(name)-raw.dng", settle: settle, outcome: &outcome)
            settle = Self.formatSwitchSettleSeconds
        } else {
            status("\(name): no Bayer RAW format; processed photo only")
            outcome["raw"] = "no Bayer RAW format"
        }
        let fallback = lens.processedFallback
        let processed = CaptureRequest(lens: lens, format: .processedFallback(fallback))
        let fileExtension = fallback == .heif ? "heic" : "jpg"
        captures["speed"] = await capture(
            processed, fileName: "\(name)-speed.\(fileExtension)", settle: settle, outcome: &outcome)
        report["captures"] = captures
        await TagCheckFiles.write(json: ProbeReport(report), to: "\(name)-report.json")
        status("\(name): finished")
        return outcome
    }

    /// Configures the backend for one request, waits, captures, then writes and measures the
    /// file.
    /// - Parameters:
    ///   - request: The lens and format.
    ///   - fileName: The output file name.
    ///   - settle: Seconds to wait between starting and capturing.
    ///   - outcome: The lens summary; receives `done` or the failure for this file.
    /// - Returns: The report entry: format, size, exposure, ISO, ImageIO properties and the
    ///   decoded luminance, or the error.
    private func capture(
        _ request: CaptureRequest, fileName: String, settle: Double, outcome: inout [String: Any]
    ) async -> [String: Any] {
        var entry: [String: Any] = ["file": fileName, "format": "\(request.format)", "settleSeconds": settle]
        let photo: CapturedPhoto
        do throws(CaptureError) {
            try await backend.startSession(request)
            try? await Task.sleep(for: .seconds(settle))
            photo = try await backend.capturePhoto(request)
        } catch {
            // blankPicture means the backend found the RAW buffer zero-filled and dropped it.
            entry["error"] = "\(error)"
            outcome[fileName] = "failed: \(error)"
            status("\(fileName): failed (\(error))")
            return entry
        }
        entry["bytes"] = photo.data.count
        entry["dimensions"] = ["width": photo.dimensions.width, "height": photo.dimensions.height]
        entry["exposureDurationSeconds"] = photo.exposureDuration
        entry["iso"] = photo.iso
        let measured = await TagCheckFiles.writeAndMeasure(photo.data, to: fileName, isRAW: request.format.isBayerRAW)
        entry.merge(measured.value) { _, new in new }
        let luminance = measured.value["luminance"] as? [String: Any] ?? [:]
        let black = ["looksBlack", "looksFlat", "looksZeroFilled"].contains { luminance[$0] as? Bool == true }
        outcome[fileName] = black ? "done, but the image looks black or flat" : "done"
        status("\(fileName): \(outcome[fileName] ?? "")")
        return entry
    }

    // MARK: - Status

    /// Shows a status line and logs it as a private value.
    private func status(_ text: String) {
        logger.info("Tag check: \(text, privacy: .private)")
        progress.append(text)
    }

    /// A file name prefix such as `back-wide` or `front-wide`, unique within one run.
    private static func uniqueName(for kind: Lens.Kind, avoiding used: inout Set<String>) -> String {
        let base =
            switch kind {
            case .ultraWide: "back-ultrawide"
            case .wide: "back-wide"
            case .telephoto: "back-telephoto"
            case .front: "front-wide"
            }
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

/// The tag check's files in `Documents/TagCheck/`, written and measured on a private serial
/// queue so decoding a 12 MP DNG doesn't block the main actor.
enum TagCheckFiles {
    /// The queue for every file write and measurement.
    private static let queue = DispatchQueue(label: "com.photivra.nope.tagcheck.files")

    /// `Documents/TagCheck/`.
    static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appending(path: "TagCheck", directoryHint: .isDirectory)
    }

    /// Deletes and recreates the folder.
    /// - Returns: `false` if it couldn't be created.
    static func resetFolder() -> Bool {
        try? FileManager.default.removeItem(at: folder)
        return (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
    }

    /// Writes a file with complete file protection, then decodes and measures it.
    /// - Parameters:
    ///   - data: The file bytes.
    ///   - fileName: The file name in the folder.
    ///   - isRAW: `true` for a DNG.
    /// - Returns: `properties` (ImageIO) and `luminance` (``ImageLuminance``), or `writeError`.
    static func writeAndMeasure(_ data: Data, to fileName: String, isRAW: Bool) async -> ProbeReport {
        await withCheckedContinuation { continuation in
            queue.async {
                var result: [String: Any] = [:]
                if let error = write(data, to: fileName) { result["writeError"] = error }
                result["properties"] = TagCheckReport.imageProperties(of: data)
                result["luminance"] = ImageLuminance.measure(data: data, isRAW: isRAW)
                continuation.resume(returning: ProbeReport(result))
            }
        }
    }

    /// Writes a JSON report with sorted keys.
    /// - Parameters:
    ///   - report: The report.
    ///   - fileName: The file name in the folder.
    static func write(json report: ProbeReport, to fileName: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if let data = try? JSONSerialization.data(
                    withJSONObject: TagCheckReport.jsonSafe(report.value), options: [.prettyPrinted, .sortedKeys])
                {
                    _ = write(data, to: fileName)
                }
                continuation.resume()
            }
        }
    }

    /// Writes bytes with complete file protection.
    /// - Returns: The error's description, or `nil` on success.
    private static func write(_ data: Data, to fileName: String) -> String? {
        do {
            try data.write(to: folder.appending(path: fileName), options: [.atomic, .completeFileProtection])
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
#endif
