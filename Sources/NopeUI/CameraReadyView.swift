import NopeCore
import SwiftUI

/// The camera when it is ready: the format badge, the viewfinder with any pause message, the
/// last capture's status, the lens buttons and the shutter, plus two slots for more controls.
///
/// ``CameraLayout`` picks the arrangement from the screen's shape:
/// - **Stacked** (taller than wide): top bar, badge, viewfinder, status, controls, lenses and
///   shutter, top to bottom. At accessibility text sizes the whole screen scrolls with a
///   fixed-height viewfinder, so no control is clipped (AGENTS.md, "Larger Text").
/// - **Side by side** (wider than tall): the viewfinder fills the height with the format badge
///   on its top edge, and everything else is in a column on the trailing edge; the shutter
///   stays at its bottom and the rest scrolls when it doesn't fit.
///
/// Slots, for controls added to the camera screen:
/// - `topBar`: buttons at the top, such as Settings. Stacked: first, above the badge, across the
///   screen's width. Side by side: first, at the top of the column. Supply your own `HStack`.
/// - `controls`: extra controls, such as manual exposure controls. Stacked: between the capture
///   status and the lens buttons. Side by side: above the capture status, near the shutter.
///   Lay them out to fit a narrow column (for example with `ViewThatFits`).
///
/// An empty slot takes no space.
struct CameraReadyView<Viewfinder: View, TopBar: View, Controls: View>: View {
    /// The model to render and send intents to.
    let model: CameraModel

    /// The lenses, in display order.
    let lenses: [Lens]

    /// The live viewfinder from the app.
    let viewfinder: Viewfinder

    /// The top bar slot.
    let topBar: TopBar

    /// The extra controls slot.
    let controls: Controls

    /// The current text size; accessibility sizes switch to scrolling layouts.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The minimum viewfinder height in the scrolling stacked layout, in points: enough to frame
    /// a shot while the enlarged controls take the rest of the screen.
    private static var scrollingViewfinderHeight: CGFloat { 280 }

    /// Creates the ready view.
    ///
    /// - Parameters:
    ///   - model: The model to render.
    ///   - lenses: The lenses, in display order.
    ///   - viewfinder: Makes the live viewfinder.
    ///   - topBar: Makes the top bar slot's content.
    ///   - controls: Makes the extra controls slot's content.
    init(
        model: CameraModel, lenses: [Lens], @ViewBuilder viewfinder: () -> Viewfinder,
        @ViewBuilder topBar: () -> TopBar, @ViewBuilder controls: () -> Controls
    ) {
        self.model = model
        self.lenses = lenses
        self.viewfinder = viewfinder()
        self.topBar = topBar()
        self.controls = controls()
    }

    /// The arrangement ``CameraLayout`` chooses for the available space.
    var body: some View {
        GeometryReader { proxy in
            switch CameraLayout.arrangement(for: proxy.size, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
            case .stacked:
                stacked
            case .sideBySide(let columnWidth):
                sideBySide(columnWidth: columnWidth)
            }
        }
        .padding()
    }

    /// The stacked arrangement, scrolling at accessibility text sizes.
    @ViewBuilder private var stacked: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                stack(viewfinderHeight: Self.scrollingViewfinderHeight)
            }
        } else {
            stack(viewfinderHeight: nil)
        }
    }

    /// The screen's parts, top to bottom.
    ///
    /// - Parameter viewfinderHeight: A fixed viewfinder height, or `nil` to fill the free space.
    private func stack(viewfinderHeight: CGFloat?) -> some View {
        VStack(spacing: CameraLayout.spacing) {
            topBar
            formatBadge
            viewfinderArea
                .frame(maxWidth: .infinity, minHeight: viewfinderHeight, maxHeight: viewfinderHeight ?? .infinity)
            CaptureStatusView(status: model.captureStatus)
            controls
            lensPicker(perRow: nil)
            shutter
        }
    }

    /// The side-by-side arrangement: the viewfinder at full height, the column beside it.
    ///
    /// The format badge sits on the viewfinder's top edge, with its solid backing, so the RAW or
    /// no-RAW statement is never scrolled out of view (issue #1, "Clean view": warnings that
    /// change what the photo is are never hidden). The shutter stays at the bottom of the
    /// column, outside the scrolling part, so it is always on screen and in reach of the thumb
    /// (AGENTS.md, "Touch targets"). The rest of the column scrolls when it doesn't fit, and
    /// starts scrolled to the bottom, so the lens buttons are next to the shutter.
    ///
    /// - Parameter columnWidth: The column's width, in points.
    private func sideBySide(columnWidth: CGFloat) -> some View {
        HStack(spacing: CameraLayout.spacing) {
            viewfinderArea
                .overlay(alignment: .top) {
                    formatBadge
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(CameraLayout.spacing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: CameraLayout.spacing) {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: CameraLayout.spacing) {
                            topBar
                            Spacer(minLength: 0)
                            controls
                            CaptureStatusView(status: model.captureStatus)
                            lensPicker(perRow: CameraLayout.lensesPerColumnRow)
                        }
                        // At least as tall as the visible area, so the lenses sit just above the
                        // shutter; taller content scrolls.
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .defaultScrollAnchor(.bottom)
                }
                shutter
            }
            .frame(width: columnWidth)
        }
    }

    /// The format badge, when the selected lens's format is known.
    @ViewBuilder private var formatBadge: some View {
        if let format = model.captureFormat {
            FormatBadge(format: format)
        }
    }

    /// The lens buttons.
    ///
    /// - Parameter perRow: A fixed number of buttons per row, or `nil` for one row that becomes
    ///   one column when the text is too large.
    private func lensPicker(perRow: Int?) -> some View {
        LensPicker(lenses: lenses, selectedID: model.selectedLensID, perRow: perRow) { id in
            Task { await model.send(.selectLens(id)) }
        }
    }

    /// The shutter.
    private var shutter: some View {
        ShutterButton(isEnabled: model.canCapture) {
            Task { await model.send(.capture) }
        }
    }

    /// The viewfinder, with the session's pause or error message on top of it.
    ///
    /// VoiceOver reads it as one element that names the lens and the format (AGENTS.md,
    /// "VoiceOver"). Smart Invert leaves it alone.
    private var viewfinderArea: some View {
        ZStack {
            viewfinder
                .accessibilityIgnoresInvertColors()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Viewfinder", bundle: .module, comment: "VoiceOver name of the live camera view."))
                .accessibilityValue(viewfinderDescription)
            SessionStatusView(status: model.sessionStatus)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    /// "Lens: Wide. Format: single-frame RAW." for VoiceOver.
    private var viewfinderDescription: Text {
        guard let lens = model.selectedLens, let format = model.captureFormat else { return Text(verbatim: "") }
        let lensName = LensName.string(for: lens.kind)
        let formatName = FormatBadge.spokenName(for: format)
        return Text(
            "Lens: \(lensName). Format: \(formatName).", bundle: .module,
            comment: "VoiceOver value of the viewfinder. The first value is a lens name such as Wide; the second is a format such as single-frame RAW.")
    }
}
