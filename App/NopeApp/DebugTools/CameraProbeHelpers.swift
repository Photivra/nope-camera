#if DEBUG
// Debug-only camera probe helpers (docs/TESTING.md, "Black frames"): the photo waiter and the
// video frame counter used by `ProbePipeline`. Compiled only in the Debug configuration.
//
// The tag check no longer uses either: it captures through the app's own backend, with no
// video data output (docs/TESTING.md, "Tag check").

import AVFoundation
import CoreImage
import Foundation
import os

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

/// Counts video frames, so the probe can tell that the camera is streaming, and on request
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
    let queue = DispatchQueue(label: "com.photivra.nope.probe.frames")
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
