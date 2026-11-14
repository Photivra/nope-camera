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
    /// The golden ratio, phi: (1 + √5) / 2.
    public static let goldenRatio = (1 + 5.0.squareRoot()) / 2

    /// The straight lines of a grid style.
    ///
    /// - Parameters:
    ///   - style: The style. ``GridStyle/goldenSpiral`` has no straight lines; draw
    ///     ``GoldenSpiral/points(placement:)`` instead.
    ///   - aspectRatio: The picture's width divided by its height, such as 0.75 for a 4:3
    ///     picture held upright. Only ``GridStyle/square`` uses it.
    /// - Returns: The lines, vertical ones first.
    public static func lines(for style: GridStyle, aspectRatio: Double) -> [GuideLine] {
        switch style {
        case .thirds:
            return crossing(at: [1.0 / 3.0, 2.0 / 3.0])
        case .fourByFour:
            return crossing(at: [0.25, 0.5, 0.75])
        case .goldenRatio:
            // 1/phi² and 1/phi: the two lines split each side into the golden ratio.
            return crossing(at: [1 / (goldenRatio * goldenRatio), 1 / goldenRatio])
        case .square:
            return squareFrame(aspectRatio: aspectRatio)
        case .goldenSpiral:
            return []
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

/// The golden (Fibonacci) spiral: quarter circles in the squares that a golden rectangle divides
/// into, stretched to fill the picture (issue #40).
///
/// It is built in a landscape golden rectangle (phi wide, 1 high): a square is cut from the left,
/// then from the top, the right and the bottom of what is left, again and again, and each square
/// holds a quarter circle that continues the last one. The points are then scaled to the unit
/// square and moved to the ``SpiralPlacement``.
public enum GoldenSpiral {
    /// How many squares the spiral passes through. After ten the squares are smaller than a
    /// hundredth of the picture, too small to see.
    static let squareCount = 10

    /// The points drawn along each quarter circle; enough for a smooth curve at full screen.
    static let pointsPerQuarter = 16

    /// The sides of the golden rectangle the squares are cut from, in turn.
    private enum Side: CaseIterable {
        /// The left side.
        case left
        /// The top.
        case top
        /// The right side.
        case right
        /// The bottom.
        case bottom
    }

    /// The spiral as a polyline from its outer end to its center, in unit coordinates.
    ///
    /// - Parameter placement: Where the spiral sits.
    /// - Returns: ``squareCount`` × ``pointsPerQuarter`` + 1 points.
    public static func points(placement: SpiralPlacement) -> [GuidePoint] {
        unplacedPoints().map { place($0, placement) }
    }

    /// The spiral in the standard placement, in unit coordinates.
    static func unplacedPoints() -> [GuidePoint] {
        let phi = GridGeometry.goldenRatio
        var rectangle = (x: 0.0, y: 0.0, width: phi, height: 1.0)
        var points: [GuidePoint] = []
        for index in 0..<squareCount {
            let side = Side.allCases[index % 4]
            let size = min(rectangle.width, rectangle.height)
            // Each quarter circle's center is the corner of its square that touches the rest of
            // the rectangle; angles are measured clockwise from the positive x axis, with y down.
            let center: (x: Double, y: Double)
            let startAngle: Double
            switch side {
            case .left:
                center = (rectangle.x + size, rectangle.y + size)
                startAngle = .pi
                rectangle = (rectangle.x + size, rectangle.y, rectangle.width - size, rectangle.height)
            case .top:
                center = (rectangle.x, rectangle.y + size)
                startAngle = 1.5 * .pi
                rectangle = (rectangle.x, rectangle.y + size, rectangle.width, rectangle.height - size)
            case .right:
                center = (rectangle.x + rectangle.width - size, rectangle.y)
                startAngle = 0
                rectangle = (rectangle.x, rectangle.y, rectangle.width - size, rectangle.height)
            case .bottom:
                center = (rectangle.x + rectangle.width, rectangle.y + rectangle.height - size)
                startAngle = 0.5 * .pi
                rectangle = (rectangle.x, rectangle.y, rectangle.width, rectangle.height - size)
            }
            // The first point of each quarter is the last point of the one before, so it is
            // added only for the first square.
            for step in (index == 0 ? 0 : 1)...pointsPerQuarter {
                let angle = startAngle + 0.5 * .pi * Double(step) / Double(pointsPerQuarter)
                points.append(
                    GuidePoint(x: (center.x + size * cos(angle)) / phi, y: center.y + size * sin(angle)))
            }
        }
        return points
    }

    /// Moves a point of the standard spiral to a placement: mirrored left to right first if the
    /// placement is flipped, then turned clockwise a quarter turn at a time.
    ///
    /// - Parameters:
    ///   - point: A point of the standard spiral.
    ///   - placement: The placement.
    static func place(_ point: GuidePoint, _ placement: SpiralPlacement) -> GuidePoint {
        var placed = placement.isFlipped ? GuidePoint(x: 1 - point.x, y: point.y) : point
        for _ in 0..<placement.quarterTurns {
            // A clockwise quarter turn of the unit square, with y down: the top-left corner moves
            // to the top-right.
            placed = GuidePoint(x: 1 - placed.y, y: placed.x)
        }
        return placed
    }
}
