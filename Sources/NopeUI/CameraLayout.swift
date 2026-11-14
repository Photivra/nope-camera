import SwiftUI

/// How the camera screen arranges the picture and its controls (issue #68, "Point budget",
/// "Landscape", "iPad").
///
/// The rule depends only on the space and the text size, so it covers iPhone and iPad in every
/// orientation and window size:
/// - a space taller than wide, on a phone-sized screen, stacks the bands: top bar, picture, lens
///   row, manual readout and shutter row (``stacked``), or scrolls them at accessibility text
///   sizes (``scrolling``, also on a portrait iPad);
/// - a space wider than tall, or a full-size iPad window, puts the picture beside a control
///   column on the trailing edge with the shutter centered (``column``).
///
/// The iPhone keeps its interface in portrait, so it uses ``stacked`` in both orientations and
/// turns icons and text upright instead (``UprightUnit``); it meets ``column`` only while a
/// rotated sheet is open over the camera.
enum CameraLayout: Equatable {
    /// Bands above and below the picture: an iPhone in portrait.
    case stacked

    /// The stacked bands in a scrolling column with a shorter picture, at accessibility text
    /// sizes, so no control is clipped (AGENTS.md, "Larger Text").
    case scrolling

    /// The picture beside a trailing control column: iPad, and any window wider than tall.
    case column

    /// The photo's long side divided by its short side. The `.photo` session preset delivers
    /// 4:3 photos, and the viewfinder shows the whole frame (`resizeAspect`), never cropped.
    static var photoAspectRatio: CGFloat { 4.0 / 3.0 }

    /// The top bar's height, in points (issue #68, "Point budget").
    static var topBarHeight: CGFloat { 44 }

    /// The shutter row's height, in points (issue #68, "Point budget").
    static var shutterRowHeight: CGFloat { 88 }

    /// The picture's height in the scrolling layout, in points: enough to frame a shot while the
    /// enlarged controls take the rest of the screen.
    static var scrollingPictureHeight: CGFloat { 280 }

    /// Chooses the arrangement.
    ///
    /// - Parameters:
    ///   - size: The space the camera screen has, inside the safe area.
    ///   - isAccessibilitySize: Whether the text size is one of the accessibility sizes.
    ///   - isRegularSize: Whether both size classes are regular, as in a full-size iPad window.
    /// - Returns: The arrangement.
    static func arrangement(for size: CGSize, isAccessibilitySize: Bool, isRegularSize: Bool) -> CameraLayout {
        if size.width > size.height { return .column }
        // At accessibility sizes a portrait iPad scrolls like the iPhone: the column is too
        // narrow for the enlarged manual controls list.
        if isAccessibilitySize { return .scrolling }
        return isRegularSize ? .column : .stacked
    }

    /// Whether the lens row and manual readout must overlay the bottom of the picture, on a dark
    /// backing, because the whole 4:3 picture and the bands don't fit one above the other, as on
    /// a 4.7-inch iPhone (issue #68, "Point budget").
    ///
    /// - Parameters:
    ///   - space: The space between the top bar and the shutter row.
    ///   - bandsHeight: The height of the lens row and manual readout together.
    /// - Returns: `true` when the bands overlay the picture.
    static func bandsOverlayPicture(in space: CGSize, bandsHeight: CGFloat) -> Bool {
        space.height < pictureHeight(forWidth: space.width) + bandsHeight
    }

    /// The height of the whole portrait 4:3 picture at a width.
    ///
    /// - Parameter width: The picture's width, in points.
    /// - Returns: The height, in points.
    static func pictureHeight(forWidth width: CGFloat) -> CGFloat {
        width * photoAspectRatio
    }

    /// The picture's width divided by its height in a space: portrait (3:4) when the space is
    /// taller than wide, otherwise landscape (4:3), because the preview turns with the
    /// interface.
    ///
    /// - Parameter size: The window's size.
    static func pictureAspectRatio(in size: CGSize) -> CGFloat {
        size.height > size.width ? 1 / photoAspectRatio : photoAspectRatio
    }
}
