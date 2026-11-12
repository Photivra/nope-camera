import Foundation

/// A white balance as a color temperature and a tint, the device-independent values
/// AVFoundation converts to and from the camera's gains
/// (`AVCaptureDevice.WhiteBalanceTemperatureAndTintValues`).
public struct WhiteBalance: Equatable, Sendable {
    /// The temperatures nope. offers, in kelvin: 2500 K to 10,000 K, the range in the manual
    /// controls design. AVFoundation converts any temperature; values the camera's gains can't
    /// reach are limited to the nearest gains it accepts.
    public static let temperatureRange: ClosedRange<Double> = 2500...10_000

    /// The tints nope. offers, from green (negative) to magenta (positive). A tool setting:
    /// AVFoundation converts any tint, and the camera's gain limit applies as for temperature.
    public static let tintRange: ClosedRange<Double> = -150...150

    /// The color temperature, in kelvin.
    public let temperature: Double

    /// The tint: negative toward green, positive toward magenta.
    public let tint: Double

    /// Creates a white balance.
    ///
    /// - Parameters:
    ///   - temperature: The color temperature, in kelvin.
    ///   - tint: The tint. Defaults to 0, no tint.
    public init(temperature: Double, tint: Double = 0) {
        self.temperature = temperature
        self.tint = tint
    }

    /// The same white balance with both values inside ``temperatureRange`` and ``tintRange``.
    public var limited: WhiteBalance {
        WhiteBalance(
            temperature: temperature.limited(to: Self.temperatureRange), tint: tint.limited(to: Self.tintRange))
    }
}

/// Common white balance starting points.
///
/// The temperatures are the conventional photographic values for each light, not measurements
/// of a scene; the person can adjust them.
public enum WhiteBalancePreset: String, Equatable, Hashable, Sendable, CaseIterable {
    /// Tungsten (incandescent) light, 3200 K.
    case tungsten
    /// Fluorescent light, 4000 K.
    case fluorescent
    /// Direct daylight, 5500 K.
    case daylight
    /// An overcast sky, 6500 K.
    case cloudy
    /// Open shade, 7500 K.
    case shade

    /// The preset's white balance, with no tint.
    public var whiteBalance: WhiteBalance {
        switch self {
        case .tungsten: WhiteBalance(temperature: 3200)
        case .fluorescent: WhiteBalance(temperature: 4000)
        case .daylight: WhiteBalance(temperature: 5500)
        case .cloudy: WhiteBalance(temperature: 6500)
        case .shade: WhiteBalance(temperature: 7500)
        }
    }
}

extension Double {
    /// The value, moved to the nearest end of a range when it lies outside.
    ///
    /// - Parameter range: The allowed values.
    /// - Returns: The value inside the range.
    func limited(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
