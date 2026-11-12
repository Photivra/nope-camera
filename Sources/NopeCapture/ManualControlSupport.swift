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
    /// iOS 26: `isExposureRectOfInterestSupported`.
    let exposureRegion: Bool

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
    init(
        customExposure: Bool, continuousAutoExposure: Bool, lockedExposure: Bool, shutterPriority: Bool,
        isoPriority: Bool, aperturePriority: Bool, exposureBiasRange: ClosedRange<Double>, continuousAutoFocus: Bool,
        lockedFocus: Bool, lensPositionFocus: Bool, customWhiteBalance: Bool, exposureRegion: Bool
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
    }

    /// The `NopeCore` capabilities. Metering modes need auto exposure; spot and whole frame
    /// also need the exposure region of interest. Exposure compensation needs auto exposure and
    /// a bias range wider than 0.
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
            meteringModes: metering)
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
/// at a reduced rate (AGENTS.md, "Battery").
struct ReadingThrottle: Sendable {
    /// The shortest time between two readings, in seconds: four readings a second, enough for
    /// a meter that a person reads.
    static let interval = 0.25

    /// When the last reading was let through, in seconds, or `nil` before the first.
    private var lastTime: Double?

    /// Creates a throttle that lets the first reading through.
    init() {}

    /// Whether a reading at a time should be sent, and records it if so.
    ///
    /// - Parameter time: The time of the reading, in seconds on any steady clock.
    /// - Returns: `true` for the first reading and for each one at least ``interval`` after the
    ///   last one let through.
    mutating func shouldSend(at time: Double) -> Bool {
        if let lastTime, time - lastTime < Self.interval { return false }
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
