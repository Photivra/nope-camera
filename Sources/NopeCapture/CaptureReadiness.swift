import AVFoundation
import NopeCore

/// Whether the photo output can take a photo now, simplified from
/// `AVCapturePhotoOutput.CaptureReadiness` (iOS 17 and later).
enum CaptureReadiness: Equatable, Sendable {
    /// Ready for a capture request.
    case ready
    /// Busy for now; a request would wait.
    case notReady
    /// The session isn't running.
    case sessionNotRunning

    /// Converts the system value. A value added in a later iOS counts as ``notReady``.
    ///
    /// - Parameter readiness: The photo output's `captureReadiness`.
    init(_ readiness: AVCapturePhotoOutput.CaptureReadiness) {
        switch readiness {
        case .ready: self = .ready
        case .sessionNotRunning: self = .sessionNotRunning
        default: self = .notReady
        }
    }

    /// Waits until the output reports ``ready``, so a capture isn't sent to an output that is
    /// still preparing. Apple: "Capturing only when the output is ready limits the number of
    /// requests inflight" (`AVCapturePhotoOutput.captureReadiness`).
    ///
    /// The output still accepts requests when it isn't ready, so after `timeout` the wait ends
    /// and the capture goes ahead.
    ///
    /// - Parameters:
    ///   - timeout: The longest wait, in seconds.
    ///   - interval: The time between checks, in seconds.
    ///   - read: Reads the current readiness.
    /// - Returns: `true` if the output became ready, `false` after the timeout.
    /// - Throws: `CaptureError.notRunning` as soon as the session isn't running.
    static func waitUntilReady(
        timeout: Double, interval: Double, read: @Sendable () async -> CaptureReadiness
    ) async throws(CaptureError) -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(timeout)
        var readiness = await read()
        while readiness != .ready {
            if readiness == .sessionNotRunning { throw .notRunning }
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .seconds(interval))
            readiness = await read()
        }
        return true
    }
}
