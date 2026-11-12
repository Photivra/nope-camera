import Foundation

/// The values one manual control steps through on a lens, smallest first.
///
/// Interfaces draw a ruler or slider over ``values`` and send the chosen value; VoiceOver's
/// adjustable action sends ``ManualControlIntent/step(_:by:)``, which uses ``value(from:steppedBy:)``.
/// Every scale ends exactly at the lens's limits, so the whole range the hardware reports is
/// reachable.
public struct ControlScale: Equatable, Sendable {
    /// The one-third-stop ISO values marked on cameras (ISO 10 to 25,600).
    static let nominalISOValues: [Double] = [
        10, 12, 16, 20, 25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600,
        2000, 2500, 3200, 4000, 5000, 6400, 8000, 10_000, 12_800, 16_000, 20_000, 25_600,
    ]

    /// The one-third-stop shutter speeds marked on cameras, in seconds (1/16,000 s to 30 s).
    static let nominalShutterValues: [Double] =
        [16_000, 12_800, 10_000, 8000, 6400, 5000, 4000, 3200, 2500, 2000, 1600, 1250, 1000, 800, 640, 500, 400,
         320, 250, 200, 160, 125, 100, 80, 60, 50, 40, 30, 25, 20, 15, 13, 10, 8, 6, 5, 4].map { 1 / $0 }
        + [0.3, 0.4, 0.5, 0.6, 0.8, 1, 1.3, 1.6, 2, 2.5, 3.2, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30]

    /// The largest exposure compensation nope. offers, in EV either way: ±3 EV, as in the manual
    /// controls design, within the lens's own range.
    static let maximumCompensation = 3.0

    /// One third of a stop, in EV: the step of the ISO, shutter and compensation scales.
    static let thirdStop = 1.0 / 3.0

    /// The white balance temperature step, in kelvin.
    static let temperatureStep = 100.0

    /// The tint step.
    static let tintStep = 5.0

    /// The focus step on the relative 0 to 1 scale: twenty steps from closest to far.
    static let focusStep = 0.05

    /// The values, smallest first. Never empty.
    public let values: [Double]

    /// Creates a scale from values, sorted and without duplicates.
    ///
    /// - Parameter values: The values. An empty list gives `nil`.
    init?(values: [Double]) {
        guard !values.isEmpty else { return nil }
        self.init(nonEmpty: values)
    }

    /// Creates a scale from values that aren't empty, sorted and without duplicates.
    ///
    /// - Parameter values: At least one value.
    private init(nonEmpty values: [Double]) {
        self.values = Array(Set(values)).sorted()
    }

    /// The position of the value nearest to a value. Distances are compared as ratios when every
    /// value is positive (ISO, shutter, aperture), so "nearest" means nearest in stops.
    ///
    /// - Parameter value: Any value in the control's unit.
    /// - Returns: An index into ``values``.
    public func nearestIndex(to value: Double) -> Int {
        let logarithmic = values[0] > 0 && value > 0
        let distance: (Double) -> Double = { logarithmic ? abs(log2($0 / value)) : abs($0 - value) }
        var nearest = 0
        for index in values.indices where distance(values[index]) < distance(values[nearest]) {
            nearest = index
        }
        return nearest
    }

    /// The value a number of steps away from the value nearest to `value`, stopping at either
    /// end of the scale.
    ///
    /// - Parameters:
    ///   - value: The current value.
    ///   - steps: How many steps to move; negative moves down.
    /// - Returns: The new value.
    public func value(from value: Double, steppedBy steps: Int) -> Double {
        let index = nearestIndex(to: value) + steps
        return values[Swift.min(Swift.max(index, 0), values.count - 1)]
    }

    /// The scale's range, from the first value to the last.
    public var range: ClosedRange<Double> {
        values[0]...values[values.count - 1]
    }

    /// The marked values strictly inside a range, plus both ends of the range.
    ///
    /// - Parameters:
    ///   - nominal: The marked values.
    ///   - range: The lens's range.
    /// - Returns: The scale.
    static func bounded(_ nominal: [Double], to range: ClosedRange<Double>) -> ControlScale {
        ControlScale(nonEmpty: [range.lowerBound] + nominal.filter { range.contains($0) } + [range.upperBound])
    }

    /// Evenly spaced values from the start of a range to its end, ending exactly at the end. A
    /// step that would land within half a step of the end is replaced by the end itself.
    ///
    /// - Parameters:
    ///   - range: The range.
    ///   - step: The spacing, greater than 0.
    /// - Returns: The scale.
    static func stepped(_ range: ClosedRange<Double>, by step: Double) -> ControlScale {
        let inner = stride(from: range.lowerBound, to: range.upperBound - step / 2, by: step)
        return ControlScale(nonEmpty: Array(inner) + [range.upperBound])
    }

    /// The scale for a control on a lens, or `nil` when the lens reports no range for it.
    ///
    /// - ISO and shutter: the one-third-stop marked values within the lens's range, plus its
    ///   limits.
    /// - Exposure compensation: thirds of a stop within ±3 EV and the lens's range.
    /// - Aperture: the f-numbers the system recommends.
    /// - Focus: twenty steps from 0 (closest) to 1 (far).
    /// - White balance: the temperature in 100 K steps over ``WhiteBalance/temperatureRange``.
    ///
    /// - Parameters:
    ///   - control: The control.
    ///   - lens: The lens.
    /// - Returns: The scale, or `nil`.
    public static func scale(for control: ManualControl, on lens: Lens) -> ControlScale? {
        switch control {
        case .iso:
            lens.isoRange.map { bounded(nominalISOValues, to: $0) }
        case .shutter:
            lens.exposureDurationRange.map { bounded(nominalShutterValues, to: $0) }
        case .exposureCompensation:
            lens.manualControls.exposureCompensationRange.flatMap { range in
                let lower = Swift.max(range.lowerBound, -maximumCompensation)
                let upper = Swift.min(range.upperBound, maximumCompensation)
                guard lower <= upper else { return nil }
                let thirds = (-9...9).map { Double($0) * thirdStop }.filter { (lower...upper).contains($0) }
                return ControlScale(nonEmpty: thirds.isEmpty ? [lower, upper] : thirds)
            }
        case .aperture:
            lens.aperture.flatMap { ControlScale(values: $0.recommendedStops) }
        case .focus:
            stepped(0...1, by: focusStep)
        case .whiteBalance:
            stepped(WhiteBalance.temperatureRange, by: temperatureStep)
        }
    }

    /// The tint scale: steps of 5 over ``WhiteBalance/tintRange``.
    public static var tint: ControlScale {
        stepped(WhiteBalance.tintRange, by: tintStep)
    }
}
