import Foundation

/// The f-numbers a lens supports.
///
/// Most iPhone lenses have a fixed aperture, where ``minimumFNumber`` equals ``maximumFNumber``
/// and ``recommendedStops`` has one value. Lenses with a variable aperture (iOS 27 and later)
/// report a range (capability survey, item 5).
public struct ApertureRange: Equatable, Sendable {
    /// The widest aperture, as the smallest f-number (for example 1.78).
    public let minimumFNumber: Double

    /// The narrowest aperture, as the largest f-number.
    public let maximumFNumber: Double

    /// The f-numbers the system recommends offering, widest first.
    public let recommendedStops: [Double]

    /// Creates an aperture range.
    ///
    /// - Parameters:
    ///   - minimumFNumber: The widest aperture, as an f-number.
    ///   - maximumFNumber: The narrowest aperture, as an f-number.
    ///   - recommendedStops: The f-numbers to offer, widest first.
    public init(minimumFNumber: Double, maximumFNumber: Double, recommendedStops: [Double]) {
        self.minimumFNumber = minimumFNumber
        self.maximumFNumber = maximumFNumber
        self.recommendedStops = recommendedStops
    }

    /// A fixed aperture with one f-number.
    ///
    /// - Parameter fNumber: The lens's f-number.
    /// - Returns: A range whose minimum, maximum and only stop are `fNumber`.
    public static func fixed(_ fNumber: Double) -> ApertureRange {
        ApertureRange(minimumFNumber: fNumber, maximumFNumber: fNumber, recommendedStops: [fNumber])
    }

    /// Whether the aperture can change: `false` for a fixed aperture.
    public var isVariable: Bool {
        maximumFNumber > minimumFNumber
    }
}
