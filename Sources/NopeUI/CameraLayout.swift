import SwiftUI

/// How the camera screen arranges the viewfinder and its controls in the space it has.
///
/// The rule depends only on the screen's shape, so it covers iPhone and iPad in every
/// orientation and any window size: taller than wide stacks the controls above and below the
/// viewfinder; wider than tall puts the viewfinder at full height with the controls in a column
/// beside it, as native camera apps do in landscape (issue #1, "iPad": "a wide layout with
/// controls beside the viewfinder").
///
/// Measured on an iPhone 16 Pro Max in landscape, the stacked layout left the viewfinder an
/// 800 × 155 pt strip; the side-by-side layout gives it the full height.
enum CameraLayout: Equatable {
    /// Controls above and below the viewfinder: portrait iPhone and iPad.
    case stacked

    /// The viewfinder fills the height, with the controls in a column on the trailing edge.
    ///
    /// - Parameter columnWidth: The width of the controls column, in points.
    case sideBySide(columnWidth: CGFloat)

    /// The photo's width divided by its height in landscape. The `.photo` session preset
    /// delivers 4:3 photos, and the viewfinder shows the whole frame (`resizeAspect`).
    static var photoAspectRatio: CGFloat { 4.0 / 3.0 }

    /// The narrowest controls column, in points: two lens buttons side by side with room for
    /// larger text, so four lenses take two rows above the shutter. One lens per row was taller
    /// than an iPhone 18 Pro Max's landscape height in the Simulator, and a narrower column
    /// clipped the buttons' text at larger sizes.
    static var minimumColumnWidth: CGFloat { 300 }

    /// The narrowest controls column at accessibility text sizes, in points, so enlarged text
    /// wraps onto fewer lines. The column scrolls if it still doesn't fit.
    static var accessibilityMinimumColumnWidth: CGFloat { 360 }

    /// The lens buttons per row in the controls column, at every text size.
    static var lensesPerColumnRow: Int { 2 }

    /// The largest share of the width the controls column may take, so the viewfinder always
    /// keeps more than half the screen.
    static var maximumColumnFraction: CGFloat { 0.45 }

    /// The space between the viewfinder and the controls, in points.
    static var spacing: CGFloat { 12 }

    /// Chooses the arrangement for the space the screen's content has.
    ///
    /// In the side-by-side arrangement the column takes the width a full-height 4:3 viewfinder
    /// leaves free, kept between the minimum column width and ``maximumColumnFraction`` of the
    /// width. When the window is too narrow for both limits, the maximum wins, so the viewfinder
    /// never gets less than its share.
    ///
    /// - Parameters:
    ///   - size: The content's size, in points, inside the safe area and padding.
    ///   - isAccessibilitySize: Whether the text size is one of the accessibility sizes.
    /// - Returns: ``stacked`` when the space is at least as tall as it is wide, otherwise
    ///   ``sideBySide(columnWidth:)``.
    static func arrangement(for size: CGSize, isAccessibilitySize: Bool) -> CameraLayout {
        guard size.width > size.height else { return .stacked }
        let freeWidth = size.width - size.height * photoAspectRatio - spacing
        let minimum = isAccessibilitySize ? accessibilityMinimumColumnWidth : minimumColumnWidth
        let maximum = size.width * maximumColumnFraction
        return .sideBySide(columnWidth: min(max(freeWidth, minimum), maximum))
    }

    /// Splits items into rows of a fixed length, keeping their order; the last row is shorter
    /// when the count doesn't divide evenly.
    ///
    /// - Parameters:
    ///   - items: The items, in display order.
    ///   - perRow: The number of items per row; values below 1 count as 1.
    /// - Returns: The rows, or no rows for no items.
    static func rows<Item>(of items: [Item], perRow: Int) -> [[Item]] {
        let length = max(perRow, 1)
        return stride(from: 0, to: items.count, by: length).map { Array(items[$0..<min($0 + length, items.count)]) }
    }
}
