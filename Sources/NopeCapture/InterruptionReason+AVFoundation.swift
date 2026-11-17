import AVFoundation
import NopeCore

extension InterruptionReason {
    /// Converts the reason in `AVCaptureSession.wasInterruptedNotification`.
    ///
    /// A missing reason, or one the app has no case for (such as sensitive content mitigation,
    /// iOS 26, or one added in a later iOS), becomes `InterruptionReason.other`.
    ///
    /// - Parameter reason: The value of `AVCaptureSessionInterruptionReasonKey`, or `nil`.
    public init(_ reason: AVCaptureSession.InterruptionReason?) {
        switch reason {
        case .videoDeviceNotAvailableInBackground: self = .backgrounded
        case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient: self = .inUseElsewhere
        case .videoDeviceNotAvailableWithMultipleForegroundApps: self = .multitasking
        case .videoDeviceNotAvailableDueToSystemPressure: self = .systemPressure
        default: self = .other
        }
    }
}
