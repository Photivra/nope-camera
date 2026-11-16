import SwiftUI

/// How the camera screen arranges the picture and its controls (issue #68, "Point budget",
/// "Landscape", "iPad").
///
/// The rule depends only on the space and the text size, so it covers iPhone and iPad in every
/// orientation and window size:
/// - at accessibility text sizes, every window scrolls the bands with a shorter picture
///   (``scrolling``), because only that layout has room for the enlarged manual controls list:
///   the column has no room for it, and offered only All Auto and Pro Tools there;
/// - otherwise, a space taller than wide, on a phone-sized screen, stacks the bands: top bar,
///   picture, lens row, manual readout and shutter row (``stacked``);
/// - a space wider than tall, or a full-size iPad window, puts the picture beside a control
///   column on the trailing edge with the shutter centered (``column``).
///
/// The iPhone keeps its interface in portrait, so it uses ``stacked`` in both orientations and
/// turns icons and text upright instead (``UprightUnit``); it meets ``column`` only while a
/// rotated sheet is open over the camera. A window that is regular in both size classes rotates
/// for real, as on iPad: the unfolded inner display of a foldable iPhone (iPhone Duo) is such a
/// window, and the system turns it with the device whatever the app asks, so it uses ``column``
/// (``scrolling`` at accessibility sizes) and nothing turns upright
/// (``isRegularSize(horizontal:vertical:)``). The Duo's outer display is a compact-width iPhone
/// window and stays portrait.
enum CameraLayout: Equatable {
    /// Bands above and below the picture: an iPhone in portrait.
    case stacked

    /// The stacked bands in a scrolling column with a shorter picture, at accessibility text
    /// sizes in every window, so no control is clipped and every manual control is in the
    /// enlarged list (AGENTS.md, "Larger Text").
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
        // At accessibility sizes every window scrolls: only the scrolling layout has room for
        // the enlarged manual controls list, so every control stays settable.
        if isAccessibilitySize { return .scrolling }
        if size.width > size.height { return .column }
        return isRegularSize ? .column : .stacked
    }

    /// Whether a window is regular in both size classes: a full-size iPad window, or the
    /// unfolded inner display of a foldable iPhone. Such a window rotates with the device, so
    /// the camera uses ``column`` beside the picture and turns nothing upright by itself.
    ///
    /// - Parameters:
    ///   - horizontal: The horizontal size class.
    ///   - vertical: The vertical size class.
    /// - Returns: `true` when both are regular.
    static func isRegularSize(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) -> Bool {
        horizontal == .regular && vertical == .regular
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
