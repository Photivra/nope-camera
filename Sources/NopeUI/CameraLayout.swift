import SwiftUI

/// How the camera screen arranges the picture and its controls (issue #68, "Point budget",
/// "Landscape", "iPad").
///
/// The rule depends only on the space and the text size, so it covers iPhone and iPad in every
/// orientation and window size:
/// - at accessibility text sizes, every window scrolls the bands with a shorter picture
///   (``scrolling``), because only that layout has room for the enlarged manual controls list:
///   the column has no room for it, and offered only All Auto and Pro Tools there;
/// - otherwise, a space taller than wide, on a phone-sized screen, stacks the rows: status line,
///   picture, lens row, drive strip and shutter row (``stacked``);
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

    /// The status line's height, in points (``NopeSize/statusRow``; issue #68, "Point budget").
    static var topBarHeight: CGFloat { NopeSize.statusRow }

    /// The shutter row's smallest height, in points (``NopeSize/shutterRowMin``; issue #68,
    /// "Point budget").
    static var shutterRowHeight: CGFloat { NopeSize.shutterRowMin }

    /// The picture's height in the scrolling layout, in points (``NopeSize/scrollingPicture``):
    /// enough to frame a shot while the enlarged controls take the rest of the screen.
    static var scrollingPictureHeight: CGFloat { NopeSize.scrollingPicture }

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

    /// Whether the lens row and drive strip must overlay the bottom of the picture, on a dark
    /// backing, because the whole 4:3 picture and the rows don't fit one above the other, as on
    /// a 4.7-inch iPhone or the outer display of an iPhone Duo (issue #68, "Point budget").
    ///
    /// - Parameters:
    ///   - space: The space between the status line and the shutter row.
    ///   - bandsHeight: The height of the lens row and drive strip together.
    /// - Returns: `true` when the bands overlay the picture.
    static func bandsOverlayPicture(in space: CGSize, bandsHeight: CGFloat) -> Bool {
        space.height < pictureHeight(forWidth: space.width) + bandsHeight
    }

    /// How far the lens row and drive strip reach up over the picture when they overlay it, in
    /// points; zero when they are below it. The picture is as wide as the space, or shorter
    /// when the space is too short for the whole picture, and the rows sit at the space's
    /// bottom.
    ///
    /// - Parameters:
    ///   - space: The space between the status line and the shutter row.
    ///   - bandsHeight: The height of the lens row and drive strip together.
    /// - Returns: The height of the picture under the rows, in points.
    static func rowsOverPicture(in space: CGSize, bandsHeight: CGFloat) -> CGFloat {
        guard bandsOverlayPicture(in: space, bandsHeight: bandsHeight) else { return 0 }
        let picture = min(pictureHeight(forWidth: space.width), space.height)
        return max(picture - (space.height - bandsHeight), 0)
    }

    /// The space above and below the lens row's controls, in points: half of what the 56-point
    /// row (``NopeSize/lensRow``) leaves around a 44-point control (``NopeSize/minTarget``), so
    /// 6 points between the picture's lower edge and the lens row, and between the lens row and
    /// the drive strip, as in the design (docs/design/screens/camera-auto: picture to 639, lens
    /// group 645 to 689, strip from 695). The row grows rather than lose this gap when its
    /// controls are taller, as with larger text.
    static var lensRowInset: CGFloat {
        (NopeSize.lensRow - NopeSize.minTarget) / 2
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

/// Lays out three views in a row with the middle one centered on the row, the first at the
/// leading edge and the last at the trailing edge: the lens row, whose lens group sits on the
/// same center line as the shutter (docs/design/BUILD-SPEC.md, 3.1). When a side is too wide to
/// leave the middle centered, the middle moves toward the other side just enough to keep the
/// spacing; it never overlaps a side. Right to left, the row mirrors.
struct CenteredRowLayout: Layout {
    /// The smallest space between neighbors, in points.
    let spacing: CGFloat

    /// Creates the layout.
    ///
    /// - Parameter spacing: The smallest space between neighbors, in points.
    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    /// The row's size: the proposed width, or the three widths and spacing when none is
    /// proposed; the tallest view's height.
    ///
    /// - Parameters:
    ///   - proposal: The proposed size.
    ///   - subviews: The three views.
    ///   - cache: Unused.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
        return CGSize(width: proposal.width ?? natural, height: sizes.map(\.height).max() ?? 0)
    }

    /// Places the views.
    ///
    /// - Parameters:
    ///   - bounds: The row's frame.
    ///   - proposal: The proposed size.
    ///   - subviews: The three views.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else {
            for subview in subviews { subview.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified) }
            return
        }
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let frames = Self.horizontalFrames(widths: (widths[0], widths[1], widths[2]), width: bounds.width, spacing: spacing)
        for (index, frame) in [frames.leading, frames.middle, frames.trailing].enumerated() {
            // A view with room for its natural width gets no width proposal at all: proposing
            // that width again can come back a fraction of a point short and cut its text.
            let width = frame.upperBound - frame.lowerBound
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.lowerBound, y: bounds.midY), anchor: .leading,
                proposal: width >= widths[index] ? .unspecified : ProposedViewSize(width: width, height: nil))
        }
    }

    /// Where each of three views goes along the row, from the row's leading edge.
    ///
    /// The middle view is centered when the sides allow it, otherwise moved toward the narrower
    /// side to keep `spacing` from the wider one. When the three don't fit at all, the middle
    /// keeps its width and the sides share what is left equally.
    ///
    /// - Parameters:
    ///   - widths: The natural widths of the leading, middle and trailing views, in points.
    ///   - width: The row's width, in points.
    ///   - spacing: The smallest space between neighbors, in points.
    /// - Returns: The start and end of each view, in points from the leading edge.
    static func horizontalFrames(
        widths: (leading: CGFloat, middle: CGFloat, trailing: CGFloat), width: CGFloat, spacing: CGFloat
    ) -> (leading: ClosedRange<CGFloat>, middle: ClosedRange<CGFloat>, trailing: ClosedRange<CGFloat>) {
        let needed = widths.leading + widths.middle + widths.trailing + 2 * spacing
        guard needed <= width else {
            let side = max((width - widths.middle - 2 * spacing) / 2, 0)
            let middleStart = side + spacing
            return (0...side, middleStart...(middleStart + widths.middle), (width - side)...width)
        }
        let lowest = widths.leading + spacing
        let highest = width - widths.trailing - spacing - widths.middle
        let middleStart = min(max((width - widths.middle) / 2, lowest), highest)
        return (
            0...widths.leading, middleStart...(middleStart + widths.middle), (width - widths.trailing)...width
        )
    }
}
