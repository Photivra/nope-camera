import Foundation

/// One of the six manual controls, in the fixed order every interface shows them.
///
/// The order is the same on every device (the manual controls design: "Six slots in the same
/// order on every device"). A control the selected lens can't set stays in its place, and
/// ``ManualControlsModel/availability(of:)`` says why.
public enum ManualControl: String, Equatable, Hashable, Sendable, CaseIterable {
    /// Exposure compensation, in EV.
    case exposureCompensation
    /// The sensor gain, as an ISO value.
    case iso
    /// The exposure duration, in seconds.
    case shutter
    /// The lens aperture, as an f-number.
    case aperture
    /// The focus, as a relative lens position (no distance).
    case focus
    /// The white balance, as a color temperature in kelvin and a tint.
    case whiteBalance
}

/// Whether a manual control can be used on the selected lens right now.
public enum ControlAvailability: Equatable, Sendable {
    /// The control can be set.
    case adjustable

    /// The lens has one value that can't change, such as a fixed aperture. Show the value with
    /// "Fixed" and explain why when the person asks.
    ///
    /// - Parameter value: The fixed value, in the control's unit.
    case fixed(Double)

    /// The control can't be set now because of another control: exposure compensation has no
    /// effect while ISO, shutter and aperture are all set manually. Show it disabled with
    /// the reason.
    case blockedByManualExposure

    /// The lens or this version of iOS doesn't offer the control. Show "Not available".
    case unavailable

    /// Whether the control can be changed.
    public var isAdjustable: Bool {
        self == .adjustable
    }
}

/// The four exposure modes, named by which of ISO and shutter the person sets.
///
/// The mode is derived from ``ManualSettings``: it is not a separate setting, so the grid and
/// the mode picker can never disagree.
public enum ExposureMode: String, Equatable, Hashable, Sendable, CaseIterable {
    /// Program (P): the camera sets ISO and shutter.
    case program
    /// Shutter priority (S): the person sets the shutter, the camera sets ISO.
    case shutterPriority
    /// ISO priority (I): the person sets ISO, the camera sets the shutter.
    case isoPriority
    /// Manual (M): the person sets ISO and shutter.
    case manual
}

/// How the camera measures the scene for auto exposure.
///
/// AVFoundation offers no named metering patterns. nope. offers what the camera's exposure
/// region of interest can express (`AVCaptureDevice.exposureRectOfInterest`, iOS 26 and
/// later), and names each by the region it measures, not by a pattern it can't promise.
public enum MeteringMode: String, Equatable, Hashable, Sendable, CaseIterable {
    /// The camera's default: a region at the center of the frame.
    case center
    /// A small region at the center: the smallest region the lens supports.
    case spot
    /// The whole frame.
    case wholeFrame
}
