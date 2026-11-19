import Foundation
import NopeCore

/// One camera's answers about manual control, copied from `AVCaptureDevice` and its active
/// format into plain values, so ``LensCatalog`` can turn them into `NopeCore`'s
/// `ManualCapabilities` without a camera.
struct ManualControlSupport: Equatable, Sendable {
    /// `isExposureModeSupported(.custom)`.
    let customExposure: Bool
    /// `isExposureModeSupported(.continuousAutoExposure)`.
    let continuousAutoExposure: Bool
    /// `isExposureModeSupported(.locked)`.
    let lockedExposure: Bool
    /// iOS 27: `supportsExposureModeCustom(lensAperture: autoLensAperture, duration: currentExposureDuration, iso: autoISO)`.
    let shutterPriority: Bool
    /// iOS 27: `supportsExposureModeCustom(lensAperture: autoLensAperture, duration: autoExposureDuration, iso: currentISO)`.
    let isoPriority: Bool
    /// iOS 27, variable aperture only: `supportsExposureModeCustom(lensAperture: currentLensAperture, duration: autoExposureDuration, iso: autoISO)`.
    let aperturePriority: Bool
    /// `minExposureTargetBias` to `maxExposureTargetBias`, in EV.
    let exposureBiasRange: ClosedRange<Double>
    /// `isFocusModeSupported(.continuousAutoFocus)`.
    let continuousAutoFocus: Bool
    /// `isFocusModeSupported(.locked)`.
    let lockedFocus: Bool
    /// `isLockingFocusWithCustomLensPositionSupported`.
    let lensPositionFocus: Bool
    /// `isLockingWhiteBalanceWithCustomDeviceGainsSupported`.
    let customWhiteBalance: Bool
    /// `isExposureRectOfInterestSupported`.
    let exposureRegion: Bool
    /// `isFocusPointOfInterestSupported`.
    let focusPoint: Bool
    /// `isExposurePointOfInterestSupported`.
    let exposurePoint: Bool
    /// `isAutoFocusRangeRestrictionSupported`.
    let focusRangeRestriction: Bool

    /// A camera with no manual control.
    static let none = ManualControlSupport(
        customExposure: false, continuousAutoExposure: false, lockedExposure: false, shutterPriority: false,
        isoPriority: false, aperturePriority: false, exposureBiasRange: 0...0, continuousAutoFocus: false,
        lockedFocus: false, lensPositionFocus: false, customWhiteBalance: false, exposureRegion: false)

    /// Creates a description; each parameter is the AVFoundation answer of the same name above.
    ///
    /// - Parameters:
    ///   - customExposure: Custom exposure.
    ///   - continuousAutoExposure: Continuous auto exposure.
    ///   - lockedExposure: Locked exposure.
    ///   - shutterPriority: Shutter priority.
    ///   - isoPriority: ISO priority.
    ///   - aperturePriority: Aperture priority.
    ///   - exposureBiasRange: The exposure bias range, in EV.
    ///   - continuousAutoFocus: Continuous autofocus.
    ///   - lockedFocus: Locked focus.
    ///   - lensPositionFocus: Focus locked at a lens position.
    ///   - customWhiteBalance: White balance locked with custom gains.
    ///   - exposureRegion: The exposure region of interest.
    ///   - focusPoint: The focus point of interest. Defaults to `false`.
    ///   - exposurePoint: The exposure point of interest. Defaults to `false`.
    ///   - focusRangeRestriction: The autofocus range restriction. Defaults to `false`.
    init(
        customExposure: Bool, continuousAutoExposure: Bool, lockedExposure: Bool, shutterPriority: Bool,
        isoPriority: Bool, aperturePriority: Bool, exposureBiasRange: ClosedRange<Double>, continuousAutoFocus: Bool,
        lockedFocus: Bool, lensPositionFocus: Bool, customWhiteBalance: Bool, exposureRegion: Bool,
        focusPoint: Bool = false, exposurePoint: Bool = false, focusRangeRestriction: Bool = false
    ) {
        self.customExposure = customExposure
        self.continuousAutoExposure = continuousAutoExposure
        self.lockedExposure = lockedExposure
        self.shutterPriority = shutterPriority
        self.isoPriority = isoPriority
        self.aperturePriority = aperturePriority
        self.exposureBiasRange = exposureBiasRange
        self.continuousAutoFocus = continuousAutoFocus
        self.lockedFocus = lockedFocus
        self.lensPositionFocus = lensPositionFocus
        self.customWhiteBalance = customWhiteBalance
        self.exposureRegion = exposureRegion
        self.focusPoint = focusPoint
        self.exposurePoint = exposurePoint
        self.focusRangeRestriction = focusRangeRestriction
    }

    /// The `NopeCore` capabilities. Metering modes need auto exposure; spot and whole frame
    /// also need the exposure region of interest. Exposure compensation needs auto exposure and
    /// a bias range wider than 0. The focus point and the range restriction need autofocus, and
    /// the exposure point needs auto exposure.
    var capabilities: ManualCapabilities {
        let compensates = continuousAutoExposure && exposureBiasRange.lowerBound < exposureBiasRange.upperBound
        let metering: [MeteringMode] =
            continuousAutoExposure ? [.center] + (exposureRegion ? [.spot, .wholeFrame] : []) : []
        return ManualCapabilities(
            supportsManualExposure: customExposure,
            supportsShutterPriority: shutterPriority,
            supportsISOPriority: isoPriority,
            supportsAperturePriority: aperturePriority,
            exposureCompensationRange: compensates ? exposureBiasRange : nil,
            supportsExposureLock: lockedExposure,
            supportsAutoFocus: continuousAutoFocus,
            supportsFocusLock: lockedFocus,
            supportsManualFocus: lensPositionFocus,
            supportsManualWhiteBalance: customWhiteBalance,
            meteringModes: metering,
            supportsFocusPoint: focusPoint && continuousAutoFocus,
            supportsExposurePoint: exposurePoint && continuousAutoExposure,
            supportsNearFocusLimit: focusRangeRestriction && continuousAutoFocus)
    }
}

/// The exposure region for a metering mode, in the camera's normalized coordinates (0 to 1,
/// landscape, as `exposureRectOfInterest` uses).
struct MeteringRegion: Equatable, Sendable {
    /// The left edge.
    let x: Double
    /// The top edge.
    let y: Double
    /// The width.
    let width: Double
    /// The height.
    let height: Double

    /// Creates a region.
    ///
    /// - Parameters:
    ///   - x: The left edge.
    ///   - y: The top edge.
    ///   - width: The width.
    ///   - height: The height.
    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The region for a metering mode, or `nil` for `MeteringMode.center`, which the hardware
    /// sets by resetting the exposure point to the center (that also resets the region to its
    /// default size, `AVCaptureDevice.exposureRectOfInterest`).
    ///
    /// - Parameters:
    ///   - mode: The metering mode.
    ///   - minimumWidth: The lens's `minExposureRectOfInterestSize.width`.
    ///   - minimumHeight: The lens's `minExposureRectOfInterestSize.height`.
    /// - Returns: The whole frame for `MeteringMode.wholeFrame`; the smallest region the lens
    ///   allows, centered, for `MeteringMode.spot`.
    static func region(for mode: MeteringMode, minimumWidth: Double, minimumHeight: Double) -> MeteringRegion? {
        switch mode {
        case .center:
            return nil
        case .wholeFrame:
            return MeteringRegion(x: 0, y: 0, width: 1, height: 1)
        case .spot:
            let width = minimumWidth.clampedToUnit
            let height = minimumHeight.clampedToUnit
            return MeteringRegion(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
        }
    }
}

/// The camera's white balance gains, kept inside the range the camera accepts.
struct WhiteBalanceGains: Equatable, Sendable {
    /// The red gain.
    let red: Double
    /// The green gain.
    let green: Double
    /// The blue gain.
    let blue: Double

    /// Creates gains.
    ///
    /// - Parameters:
    ///   - red: The red gain.
    ///   - green: The green gain.
    ///   - blue: The blue gain.
    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The gains with each channel between 1 and the camera's maximum. A gain outside that range
    /// makes `setWhiteBalanceModeLocked(with:)` throw (`AVCaptureDevice.h`), which happens for
    /// temperatures and tints the sensor can't reach.
    ///
    /// - Parameter maximum: The camera's `maxWhiteBalanceGain`.
    /// - Returns: The limited gains.
    func limited(toMaximum maximum: Double) -> WhiteBalanceGains {
        let range = 1...Swift.max(1, maximum)
        return WhiteBalanceGains(
            red: Swift.min(Swift.max(red, range.lowerBound), range.upperBound),
            green: Swift.min(Swift.max(green, range.lowerBound), range.upperBound),
            blue: Swift.min(Swift.max(blue, range.lowerBound), range.upperBound))
    }
}

/// Lets through at most one reading per interval, so the camera's readings reach the interface
/// at a reduced rate (AGENTS.md, "Battery"), and makes sure the last one is not lost.
///
/// A reading is triggered by a change the camera reports. When changes stop inside an interval
/// (the lens comes to rest at its nearest position, autofocus stops searching), the last change
/// would otherwise never be sent, and the close-up hint would judge an old reading
/// (docs/design/device-feedback-1.0.md, section 6). So a reading held back schedules one more,
/// at the end of the interval, that reads the camera's values then.
struct ReadingThrottle: Sendable {
    /// The shortest time between two readings, in seconds: four readings a second, enough for
    /// a meter that a person reads.
    static let interval = 0.25

    /// What to do with a reading.
    enum Decision: Equatable, Sendable {
        /// Send it now.
        case send
        /// Hold it back, and call ``sendsLater(_:at:)`` with the ticket after the delay, in
        /// seconds: a reading of the values then is sent, unless one was sent since.
        case later(delay: Double, ticket: Int)
        /// Hold it back: a later reading is already scheduled.
        case drop
    }

    /// When the last reading was let through, in seconds, or `nil` before the first.
    private var lastTime: Double?

    /// The ticket of the reading scheduled for later, or `nil` when none is.
    private var pendingTicket: Int?

    /// The number of the next ticket.
    private var nextTicket = 0

    /// Creates a throttle that lets the first reading through.
    init() {}

    /// What to do with a reading at a time, recorded.
    ///
    /// - Parameter time: The time of the reading, in seconds on any steady clock.
    /// - Returns: ``Decision/send`` for the first reading and for each one at least
    ///   ``interval`` after the last one sent; otherwise ``Decision/later(delay:ticket:)`` once,
    ///   then ``Decision/drop`` until that one is due.
    mutating func decide(at time: Double) -> Decision {
        guard let lastTime, time - lastTime < Self.interval else {
            lastTime = time
            pendingTicket = nil
            return .send
        }
        guard pendingTicket == nil else { return .drop }
        let ticket = nextTicket
        nextTicket += 1
        pendingTicket = ticket
        return .later(delay: lastTime + Self.interval - time, ticket: ticket)
    }

    /// Whether the reading scheduled with a ticket should be sent now, recorded.
    ///
    /// - Parameters:
    ///   - ticket: The ticket from ``decide(at:)``.
    ///   - time: The time now, in seconds on the same clock.
    /// - Returns: `true` when it is still the scheduled one: no reading was sent since.
    mutating func sendsLater(_ ticket: Int, at time: Double) -> Bool {
        guard pendingTicket == ticket else { return false }
        pendingTicket = nil
        lastTime = time
        return true
    }
}

extension Double {
    /// The value limited to 0 through 1.
    fileprivate var clampedToUnit: Double {
        Swift.min(Swift.max(self, 0), 1)
    }
}
