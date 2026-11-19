import SwiftUI

/// The launch screen's mark: the app icon's frame, "n" and period without the icon's ground
/// (docs/design/LAUNCH-SCREEN.md, 5 and 6.3).
///
/// The shapes are the three filled paths of `App/NopeApp/AppIcon.icon/Assets` (frame.svg, n.svg
/// and period.svg), on their 1024-unit grid, which are also the paths of the launch image
/// (`LaunchMark.svg`, a copy of docs/design/launch-mark.svg); `scripts/check-launch-screen.sh`
/// checks the files agree. They are the outlines of the icon's 8-unit square-cap strokes on its
/// 128-unit grid (docs/design/icon.html), so the mark drawn here and the launch image cover the
/// same pixels. Shapes, not text: no font (AGENTS.md, "Name and wordmark").
///
/// The colors are fixed, as the launch image's are: ``NopeColor/mark`` and
/// ``NopeColor/markPeriod``, not ``NopeColor/label`` or ``NopeColor/fact``, which is the system
/// teal and changes with Increase Contrast. In night mode both are white, so `NightModeStyle`'s
/// multiply turns the whole mark the night red; the teal would multiply to a red too dark to
/// see. Hidden from VoiceOver: ``StartIndicator`` carries the label.
struct StartMark: View {
    /// Whether night mode is on.
    @Environment(\.isNightMode) private var isNightMode

    /// Creates the mark. It reads night mode from the environment.
    init() {}

    /// The frame and "n" in ``NopeColor/mark`` and the period in ``NopeColor/markPeriod``, or all
    /// white in night mode.
    var body: some View {
        ZStack {
            StartMarkShape(part: .frame)
            StartMarkShape(part: .letter)
        }
        .foregroundStyle(isNightMode ? Color.white : NopeColor.mark)
        .overlay {
            StartMarkShape(part: .period)
                .foregroundStyle(isNightMode ? Color.white : NopeColor.markPeriod)
        }
        .accessibilityHidden(true)
    }
}

/// One of the three shapes of ``StartMark``, scaled from the icon's 1024-unit grid to the rect
/// it is drawn in (``NopeSize/startMark`` square).
struct StartMarkShape: Shape {
    /// The icon's layers.
    enum Part: CaseIterable, Sendable {
        /// The four corners of the picture frame (frame.svg).
        case frame

        /// The "n" (n.svg).
        case letter

        /// The period (period.svg).
        case period
    }

    /// The layer this shape draws.
    let part: Part

    /// Creates the shape of one layer.
    ///
    /// - Parameter part: The layer to draw.
    init(part: Part) {
        self.part = part
    }

    /// The side of the icon's grid that the paths use: 1024 units.
    static let gridSide: CGFloat = 1024

    /// The shape in the rect, scaled uniformly from the 1024-unit grid.
    ///
    /// - Parameter rect: The rect to draw in, normally a ``NopeSize/startMark`` square.
    /// - Returns: The path.
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Self.gridSide
        return Self.gridPath(part).applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale))
    }

    /// A layer's path on the 1024-unit grid, as written in its SVG file.
    ///
    /// - Parameter part: The layer.
    /// - Returns: The path, in grid units.
    static func gridPath(_ part: Part) -> Path {
        switch part {
        case .frame: frame
        case .letter: letter
        case .period: period
        }
    }

    /// frame.svg: `M96 192H320V256H160V416H96Z` and its three mirror images.
    private static var frame: Path {
        Path { path in
            for corner in [
                [(96, 192), (320, 192), (320, 256), (160, 256), (160, 416), (96, 416)],
                [(928, 192), (704, 192), (704, 256), (864, 256), (864, 416), (928, 416)],
                [(96, 768), (320, 768), (320, 704), (160, 704), (160, 544), (96, 544)],
                [(928, 768), (704, 768), (704, 704), (864, 704), (864, 544), (928, 544)],
            ] {
                path.addLines(corner.map { CGPoint(x: $0.0, y: $0.1) })
                path.closeSubpath()
            }
        }
    }

    /// n.svg: `M352 288H416V324.0608A168 168 0 0 1 688 456V640H624V456A104 104 0 0 0 416 456V640H352Z`.
    ///
    /// Both arcs are centered on (520, 456), the arch's center (65, 57) on the 128-unit grid.
    /// The outer one (radius 168) runs clockwise on screen from the top of the stem to the right
    /// side; the inner one (radius 104) runs back counterclockwise over the top.
    private static var letter: Path {
        let center = CGPoint(x: 520, y: 456)
        let stemTop = CGPoint(x: 416, y: 324.0608)
        let outerStart = Angle(radians: atan2(stemTop.y - center.y, stemTop.x - center.x))
        return Path { path in
            path.move(to: CGPoint(x: 352, y: 288))
            path.addLine(to: CGPoint(x: 416, y: 288))
            path.addLine(to: stemTop)
            // A positive delta turns clockwise on screen, where y grows downward.
            path.addRelativeArc(center: center, radius: 168, startAngle: outerStart, delta: Angle(radians: -outerStart.radians))
            path.addLine(to: CGPoint(x: 688, y: 640))
            path.addLine(to: CGPoint(x: 624, y: 640))
            path.addLine(to: CGPoint(x: 624, y: 456))
            path.addRelativeArc(center: center, radius: 104, startAngle: .zero, delta: .degrees(-180))
            path.addLine(to: CGPoint(x: 416, y: 640))
            path.addLine(to: CGPoint(x: 352, y: 640))
            path.closeSubpath()
        }
    }

    /// period.svg: a circle of radius 48 at (776, 576), (97, 72) radius 6 on the 128-unit grid.
    private static var period: Path {
        Path(ellipseIn: CGRect(x: 776 - 48, y: 576 - 48, width: 96, height: 96))
    }
}

extension VerticalAlignment {
    /// The center of the start mark, which ``StartIndicator`` puts at the window's center.
    private enum StartMarkCenter: AlignmentID {
        /// A view without its own guide is aligned by its center.
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    /// The center of the start mark, which ``StartIndicator`` puts at the window's center.
    static let startMarkCenter = VerticalAlignment(StartMarkCenter.self)
}

/// The camera's first start (docs/design/LAUNCH-SCREEN.md, 6.3): the launch screen's mark at the
/// same point, until the picture arrives.
///
/// ``CameraScreen`` shows it over the whole screen while `CameraModel.isFirstStart` is `true`
/// and fades it out with ``NopeMotion/fade`` when the first start ends, so the app's first
/// frames are the launch screen and the mark is part of the first screen, as Apple's Human
/// Interface Guidelines ("Launching") ask of a launch screen with a mark.
///
/// The mark is ``NopeSize/startMark`` square with its center at the center of the window, not of
/// the safe area or the picture, where the launch screen draws its image
/// (`UIImageRespectsSafeAreaInsets` off). While the camera is ready and starting, "Starting the
/// camera…" is centered under it, its top edge ``wordsTop`` under the mark's center, on a plate of
/// ``NopeMaterial/solid`` that can't be seen on the black picture. While it shows, nothing is drawn
/// under the plate: the scrolling layout waits to draw its scrolling content (LAUNCH-SCREEN.md,
/// 13.2), and where the plate would come within ``NopeSpace/s`` of the pinned row, the words and
/// the plate are left out and the mark is shown alone (``wordsFit(plateExtent:roomBelowCenter:)``).
/// Before the camera state is known there are no words and no plate: that frame is the launch
/// screen again. It turns with
/// ``SwiftUICore/EnvironmentValues/cameraUprightRotation`` about the mark's center, so it is
/// upright on an iPhone held sideways, as the launch screen was. It takes no touches, and
/// VoiceOver reads it as one element, "Starting the camera…".
struct StartIndicator: View {
    /// Whether the words are shown under the mark: while the camera is ready and its session
    /// starts, not before the camera state is known.
    let showsWords: Bool

    /// The top edge of the scrolling layout's pinned row in the window (global coordinates), in
    /// points, or `nil` in the other layouts, where nothing is drawn under the plate.
    let pinnedRowTop: CGFloat?

    /// The size of the words, once laid out; `nil` before, when they aren't drawn.
    @State private var wordsSize: CGSize?

    /// The distance from the mark's center to the top edge of the words: 40 points.
    static let wordsTop: CGFloat = 40

    /// Which way up the person holds the iPhone.
    @Environment(\.cameraUprightRotation) private var rotation

    /// Whether night mode is on: the words are white, drawn in the full night red.
    @Environment(\.isNightMode) private var isNightMode

    /// Creates the indicator.
    ///
    /// - Parameters:
    ///   - showsWords: Whether "Starting the camera…" is shown under the mark.
    ///   - pinnedRowTop: The top edge of the pinned row in the window (global coordinates), in
    ///     points, or `nil` where there is no pinned row under the indicator.
    init(showsWords: Bool, pinnedRowTop: CGFloat? = nil) {
        self.showsWords = showsWords
        self.pinnedRowTop = pinnedRowTop
    }

    /// How far below the mark's center the plate reaches, in points, upright: ``wordsTop``, the
    /// words' height and ``NopeSpace/m`` of padding.
    ///
    /// - Parameter wordsHeight: The height of the wrapped words, in points.
    /// - Returns: The distance from the mark's center to the plate's bottom edge.
    static func plateBottom(wordsHeight: CGFloat) -> CGFloat {
        wordsTop + wordsHeight + NopeSpace.m
    }

    /// How far below the window's center the plate reaches on screen, in points: its upright
    /// bottom (``plateBottom(wordsHeight:)``), or half its width when it is turned a quarter turn
    /// on an iPhone held sideways.
    ///
    /// - Parameters:
    ///   - wordsSize: The size of the wrapped words, in points.
    ///   - isSideways: Whether the indicator is turned a quarter turn.
    /// - Returns: The plate's extent below the window's center.
    static func plateExtent(wordsSize: CGSize, isSideways: Bool) -> CGFloat {
        guard isSideways else { return plateBottom(wordsHeight: wordsSize.height) }
        return max(wordsSize.width, NopeSize.startMark) / 2 + NopeSpace.m
    }

    /// Whether the words and their plate fit above the pinned row (LAUNCH-SCREEN.md, 13.2, part
    /// 2): the plate's bottom edge must stay at least ``NopeSpace/s`` above the row's top edge.
    ///
    /// - Parameters:
    ///   - plateExtent: How far below the window's center the plate reaches, in points
    ///     (``plateExtent(wordsSize:isSideways:)``).
    ///   - roomBelowCenter: How far below the window's center the pinned row's top edge is, in
    ///     points, or `nil` where there is no pinned row, when they always fit.
    /// - Returns: `true` when the words and the plate are shown.
    static func wordsFit(plateExtent: CGFloat, roomBelowCenter: CGFloat?) -> Bool {
        guard let roomBelowCenter else { return true }
        return plateExtent + NopeSpace.s <= roomBelowCenter
    }

    /// Whether the words and their plate are drawn: they are meant to show, they have been laid
    /// out, and they fit above the pinned row.
    ///
    /// - Parameter windowCenter: The window's vertical center in global coordinates, in points.
    private func drawsWords(windowCenter: CGFloat) -> Bool {
        guard showsWords, let wordsSize else { return false }
        return Self.wordsFit(
            plateExtent: Self.plateExtent(wordsSize: wordsSize, isSideways: rotation.isSideways),
            roomBelowCenter: pinnedRowTop.map { $0 - windowCenter })
    }

    /// The mark at the window's center, with the words under it.
    var body: some View {
        GeometryReader { proxy in
            let window = proxy.size
            // The area the indicator lays out in, upright for the person: a sideways iPhone's
            // portrait window turned a quarter turn.
            let upright = rotation.isSideways ? CGSize(width: window.height, height: window.width) : window
            ZStack(alignment: Alignment(horizontal: .center, vertical: .startMarkCenter)) {
                Color.clear
                markAndWords(width: upright.width, drawsWords: drawsWords(windowCenter: proxy.frame(in: .global).midY))
            }
            .frame(width: upright.width, height: upright.height)
            // About the window's center, which is the mark's center.
            .rotationEffect(rotation.angle)
            .position(x: window.width / 2, y: window.height / 2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// The mark, and under it the words on their plate.
    ///
    /// - Parameters:
    ///   - width: The upright width of the window, which the words wrap within, less
    ///     ``NopeSpace/l`` on each side.
    ///   - drawsWords: Whether the words and the plate are drawn, or only laid out.
    @ViewBuilder private func markAndWords(width: CGFloat, drawsWords: Bool) -> some View {
        // The words' top edge is ``wordsTop`` under the mark's center: the mark's square ends half
        // its side under the center, so the gap is the difference (negative: the words start
        // inside the mark's empty lower margin, under its frame).
        VStack(spacing: Self.wordsTop - NopeSize.startMark / 2) {
            StartMark()
                .frame(width: NopeSize.startMark, height: NopeSize.startMark)
                .alignmentGuide(.startMarkCenter) { $0[VerticalAlignment.center] }
            if drawsWords {
                words(width: width)
            }
        }
        // A hidden copy of the words, laid out at the same width whether or not they are drawn,
        // so their size is known before they are (LAUNCH-SCREEN.md, 13.2). It takes no room.
        .background(alignment: .top) {
            if showsWords {
                words(width: width)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { wordsSize = $0 }
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .padding(NopeSpace.m)
        .background {
            if drawsWords {
                Color.clear.nopeBackground(.solid, in: RoundedRectangle(cornerRadius: NopeRadius.large))
            }
        }
        // One element, the mark and the words with their plate.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("Starting the camera…", bundle: .module, comment: "Shown briefly while the app checks camera access."))
        .accessibilityIdentifier("startIndicator")
    }
}

extension StartIndicator {
    /// "Starting the camera…", as wide as the words need, up to the window less the margins,
    /// where they wrap. A flexible frame took the whole width, so the plate behind them became a
    /// black band across the window that hid the iPad column's shutter and the lower half of Q
    /// (second review of 1.0.0).
    ///
    /// - Parameter width: The upright width of the window, less ``NopeSpace/l`` on each side.
    /// - Returns: The words.
    fileprivate func words(width: CGFloat) -> some View {
        StartWordsWidth(maximumWidth: max(width - 2 * NopeSpace.l, 0)) {
            Text("Starting the camera…", bundle: .module, comment: "Shown briefly while the app checks camera access.")
                .font(.subheadline)
                .foregroundStyle(isNightMode ? NopeColor.label : NopeColor.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Lays out its one subview at most ``maximumWidth`` wide and takes the subview's own size, so
/// the plate behind the first start's words is only as wide as the words (wrapped where they
/// don't fit), never the whole window.
struct StartWordsWidth: Layout {
    /// The widest the subview may be, in points.
    let maximumWidth: CGFloat

    /// Creates the layout.
    ///
    /// - Parameter maximumWidth: The widest the subview may be, in points.
    init(maximumWidth: CGFloat) {
        self.maximumWidth = maximumWidth
    }

    /// The subview's size when offered the smaller of the proposed width and ``maximumWidth``.
    ///
    /// - Parameters:
    ///   - proposal: The size offered.
    ///   - subviews: The one subview.
    ///   - cache: Unused.
    /// - Returns: The subview's size.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = min(proposal.width ?? maximumWidth, maximumWidth)
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    /// Places the subview at the center of the bounds, at their size.
    ///
    /// - Parameters:
    ///   - bounds: Where the subview goes.
    ///   - proposal: The size offered.
    ///   - subviews: The one subview.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// The top edge of the scrolling layout's pinned row (Last Photo, shutter, Q) in the window, in
/// global coordinates, so ``CameraScreen`` can tell ``StartIndicator`` how much room there is
/// under the mark (LAUNCH-SCREEN.md, 13.2). `nil` in the other layouts.
struct PinnedRowTop: PreferenceKey {
    /// Creates the key. It holds no state.
    init() {}

    /// No pinned row.
    static let defaultValue: CGFloat? = nil

    /// The first pinned row's top edge reported; there is at most one.
    ///
    /// - Parameters:
    ///   - value: The value so far.
    ///   - nextValue: The next view's value.
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = value ?? nextValue()
    }
}
