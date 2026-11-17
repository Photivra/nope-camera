import Foundation

/// A point on the picture in unit coordinates: x from 0 (leading edge) to 1 (trailing edge), y
/// from 0 (top) to 1 (bottom). An interface scales it to the size it draws the picture at.
public struct GuidePoint: Equatable, Sendable {
    /// The horizontal position, 0 to 1.
    public let x: Double

    /// The vertical position, 0 (top) to 1 (bottom).
    public let y: Double

    /// Creates a point.
    ///
    /// - Parameters:
    ///   - x: The horizontal position, 0 to 1.
    ///   - y: The vertical position, 0 (top) to 1 (bottom).
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A straight guide line from one point to another, in unit coordinates.
public struct GuideLine: Equatable, Sendable {
    /// Where the line starts.
    public let start: GuidePoint

    /// Where the line ends.
    public let end: GuidePoint

    /// Creates a line.
    ///
    /// - Parameters:
    ///   - start: Where the line starts.
    ///   - end: Where the line ends.
    public init(start: GuidePoint, end: GuidePoint) {
        self.start = start
        self.end = end
    }

    /// A vertical line across the whole picture.
    ///
    /// - Parameter x: Its horizontal position, 0 to 1.
    static func vertical(at x: Double) -> GuideLine {
        GuideLine(start: GuidePoint(x: x, y: 0), end: GuidePoint(x: x, y: 1))
    }

    /// A horizontal line across the whole picture.
    ///
    /// - Parameter y: Its vertical position, 0 to 1.
    static func horizontal(at y: Double) -> GuideLine {
        GuideLine(start: GuidePoint(x: 0, y: y), end: GuidePoint(x: 1, y: y))
    }
}

/// Where each grid style's lines go, in unit coordinates, so every interface draws the same
/// guides (issue #40). Guides are on screen only.
public enum GridGeometry {
    /// The straight lines of a grid style.
    ///
    /// - Parameters:
    ///   - style: The style.
    ///   - aspectRatio: The picture's width divided by its height, such as 0.75 for a 4:3
    ///     picture held upright. Only ``GridStyle/square`` uses it.
    /// - Returns: The lines, vertical ones first.
    public static func lines(for style: GridStyle, aspectRatio: Double) -> [GuideLine] {
        switch style {
        case .thirds:
            return crossing(at: [1.0 / 3.0, 2.0 / 3.0])
        case .fourByFour:
            return crossing(at: [0.25, 0.5, 0.75])
        case .square:
            return squareFrame(aspectRatio: aspectRatio)
        }
    }

    /// Vertical and horizontal lines at the same positions.
    ///
    /// - Parameter positions: The positions, 0 to 1.
    private static func crossing(at positions: [Double]) -> [GuideLine] {
        positions.map(GuideLine.vertical(at:)) + positions.map(GuideLine.horizontal(at:))
    }

    /// The two lines that, with the picture's long edges, frame the largest centered square.
    ///
    /// - Parameter aspectRatio: The picture's width divided by its height.
    /// - Returns: Two horizontal lines for an upright picture, two vertical ones for a wide
    ///   picture, and none for a square picture or an invalid ratio.
    private static func squareFrame(aspectRatio: Double) -> [GuideLine] {
        guard aspectRatio > 0, aspectRatio != 1, aspectRatio.isFinite else { return [] }
        if aspectRatio < 1 {
            let margin = (1 - aspectRatio) / 2
            return [GuideLine.horizontal(at: margin), GuideLine.horizontal(at: 1 - margin)]
        }
        let margin = (1 - 1 / aspectRatio) / 2
        return [GuideLine.vertical(at: margin), GuideLine.vertical(at: 1 - margin)]
    }
}
