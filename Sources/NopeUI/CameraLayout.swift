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

    /// The height left in the stacked layout once the status line, the whole 4:3 picture, the
    /// lens row, the drive strip and the shutter row at its smallest have their place, in points
    /// (docs/design/finish-1.0.md, 1.2, "Spare height"); zero when the rows overlay the picture
    /// (``bandsOverlayPicture(in:bandsHeight:)``) or nothing is left.
    ///
    /// `bandsHeight` must be the rows' own height, without the gap ``rowGap(spareHeight:)``
    /// puts between them, or the gap would feed back into the height it is worked out from.
    ///
    /// - Parameters:
    ///   - space: The space between the status line and the shutter row at its smallest.
    ///   - bandsHeight: The height of the lens row and drive strip together, without the gap.
    /// - Returns: The spare height, in points.
    static func spareHeight(in space: CGSize, bandsHeight: CGFloat) -> CGFloat {
        guard !bandsOverlayPicture(in: space, bandsHeight: bandsHeight) else { return 0 }
        return max(space.height - pictureHeight(forWidth: space.width) - bandsHeight, 0)
    }

    /// The smallest gap between the lens row and the drive strip, in points: what the lens row's
    /// own 6 points below its controls (``lensRowInset``) lack of the 8 points between two
    /// targets (``NopeSize/targetGap``), so 2 points.
    static var minimumRowGap: CGFloat {
        max(NopeSize.targetGap - lensRowInset, 0)
    }

    /// The largest gap between the lens row and the drive strip, in points (``NopeSpace/l``,
    /// docs/design/finish-1.0.md, 1.2).
    static var maximumRowGap: CGFloat { NopeSpace.l }

    /// The gap the spare height adds between the lens row and the drive strip, in points (issue
    /// #116; docs/design/finish-1.0.md, 1.2): the first 2 points of the spare height
    /// (``minimumRowGap``), which bring the lens controls 8 points from the drive strip's
    /// targets, then a third of the rest, rounded down to a whole point, and never more than 24
    /// points (``maximumRowGap``). The shutter row takes what is left. The picture keeps its size.
    ///
    /// For example, a 440 × 956 point iPhone has 41 spare points and gets a 15-point gap; a
    /// 393 × 852 point iPhone has 3 and gets 2.
    ///
    /// - Parameter spareHeight: The spare height (``spareHeight(in:bandsHeight:)``), in points.
    /// - Returns: The gap, in whole points; zero when there is no spare height.
    static func rowGap(spareHeight: CGFloat) -> CGFloat {
        guard spareHeight > 0 else { return 0 }
        let first = min(spareHeight, minimumRowGap)
        let rest = max(spareHeight - minimumRowGap, 0) / 3
        return min((first + rest).rounded(.down), maximumRowGap)
    }

    /// How far the lens row's controls move up, toward the picture, so they stay 8 points from
    /// the drive strip's targets when the spare height gives less than 2 points of gap
    /// (``minimumRowGap``), in points: the 2 points on a screen where the rows overlay the
    /// picture (a 4.7 or 5.4-inch iPhone). The rows take no more height than before, so the
    /// picture is covered no further; the controls are then 4 points below the rows' top edge.
    ///
    /// - Parameter rowGap: The gap from ``rowGap(spareHeight:)``, in points.
    /// - Returns: The points taken from above the lens row's controls, from 0 to 2.
    static func lensRowLift(rowGap: CGFloat) -> CGFloat {
        max(minimumRowGap - rowGap, 0)
    }

    /// The space the shutter row's contents move down by, in points, so the shutter stays 8
    /// points (``NopeSize/targetGap``) below the drive strip's targets when the row is too short
    /// to center the shutter with 8 points above it: 4 points in a row at its smallest, 88
    /// points (``NopeSize/shutterRowMin``), which leaves the shutter 8 points below the strip
    /// and 4 above the safe area's lower edge. Zero once the row is 92 points or taller.
    ///
    /// - Parameter shutterRowHeight: The shutter row's height, in points.
    /// - Returns: The space added above the row's contents, in points.
    static func shutterRowTopPadding(shutterRowHeight: CGFloat) -> CGFloat {
        let roomAbove = NopeSize.targetGap - (shutterRowHeight - NopeSize.shutter) / 2
        return min(max(2 * roomAbove, 0), shutterRowHeight - NopeSize.shutter)
    }

    /// The smallest height of the column layout at which Q, the shutter and Last Photo get 16
    /// points around the shutter instead of 8, in points (docs/design/finish-1.0.md, 1.4): a
    /// full-size iPad window has it in both orientations; a short window, such as the iPhone
    /// Duo's inner display held like a book, keeps 8.
    static var roomyColumnMinHeight: CGFloat { 600 }

    /// The gap above and below the shutter in the column layout, in points (issue #116;
    /// docs/design/finish-1.0.md, 1.4): 16 (``NopeSpace/m``) when the column is at least
    /// ``roomyColumnMinHeight`` tall, otherwise 8 (``NopeSpace/xs``). The column sits beside the
    /// picture, so the gap costs the picture nothing.
    ///
    /// - Parameter columnHeight: The column's height, in points: the window's, inside the safe
    ///   area.
    /// - Returns: The gap, in points.
    static func columnShutterGap(columnHeight: CGFloat) -> CGFloat {
        columnHeight >= roomyColumnMinHeight ? NopeSpace.m : NopeSpace.xs
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
