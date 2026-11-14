import Foundation

/// A point in a picture, in normalized coordinates: (0, 0) is the top-left corner and (1, 1) the
/// bottom-right corner.
///
/// An interface sends a point in the viewfinder's own coordinates (where the person tapped,
/// divided by the viewfinder's size) with ``AutoControlIntent/focusAndExpose(at:)``.
/// ``CameraModel`` turns it into the camera's coordinates with
/// ``CameraPreviewSource/devicePoint(forViewfinderPoint:)`` before it reaches the hardware
/// (`focusPointOfInterest` and `exposurePointOfInterest` use the same 0-to-1 range).
public struct FramePoint: Equatable, Sendable {
    /// The horizontal position, from 0 (leading edge as drawn, left) to 1 (right).
    public let x: Double

    /// The vertical position, from 0 (top) to 1 (bottom).
    public let y: Double

    /// The middle of the picture.
    public static let center = FramePoint(x: 0.5, y: 0.5)

    /// Creates a point, moving each coordinate inside 0 through 1, so a tap at the very edge
    /// (or a rounding error just past it) is still a valid point of interest.
    ///
    /// - Parameters:
    ///   - x: The horizontal position, 0 to 1.
    ///   - y: The vertical position, 0 to 1.
    public init(x: Double, y: Double) {
        self.x = x.limited(to: 0...1)
        self.y = y.limited(to: 0...1)
    }

    /// The point for a location inside a frame of a size, for example a tap in the viewfinder.
    ///
    /// - Parameters:
    ///   - locationX: The horizontal location, in points from the left edge.
    ///   - locationY: The vertical location, in points from the top edge.
    ///   - width: The frame's width, in points.
    ///   - height: The frame's height, in points.
    /// - Returns: The normalized point, or `nil` for an empty frame.
    public static func normalized(locationX: Double, locationY: Double, width: Double, height: Double) -> FramePoint? {
        guard width > 0, height > 0 else { return nil }
        return FramePoint(x: locationX / width, y: locationY / height)
    }
}
