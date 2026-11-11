import AVFoundation
import NopeCore

extension InterruptionReason {
    /// Converts the reason in `AVCaptureSession.wasInterruptedNotification`.
    ///
    /// A missing reason, or one added in a later iOS (such as sensitive content mitigation in
    /// iOS 26), becomes `InterruptionReason.other`.
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
