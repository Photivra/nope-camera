import NopeCore
import SwiftUI

/// The camera when it is ready: the format badge, the viewfinder with any pause message, the
/// last capture's status, the manual controls when they are on, the lens buttons and the
/// shutter, plus two slots for more controls.
///
/// ``CameraLayout`` picks the arrangement from the screen's shape:
/// - **Stacked** (taller than wide): top bar, badge, viewfinder, interval progress, status,
///   manual controls, controls slot, lenses and shutter, top to bottom. At accessibility text
///   sizes the whole screen scrolls with a fixed-height viewfinder, so no control is clipped
///   (AGENTS.md, "Larger Text").
/// - **Side by side** (wider than tall): the viewfinder fills the height with the format badge
///   on its top edge, and everything else is in a column on the trailing edge; the shutter
///   stays at its bottom and the rest scrolls when it doesn't fit.
///
/// Clean view hides everything but the viewfinder, the shutter and the button that brings the
/// controls back; the no-RAW badge, a running interval series and capture results stay. Hidden
/// controls stay reachable: the shutter offers "Show Controls" as a VoiceOver action, and Voice
/// Control can say it.
///
/// Slots, for controls added to the camera screen (hidden in clean view):
/// - `topBar`: buttons at the top, such as Settings. Stacked: first, above the badge, across the
///   screen's width. Side by side: first, at the top of the column. Supply your own `HStack`.
/// - `controls`: extra controls. Stacked: after the manual controls, above the lens buttons.
///   Side by side: the same order, in the column's scrolling part. Lay them out to fit a
///   300-point column (for example with `ViewThatFits`).
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

    /// The manual control whose panel is open, or `nil`.
    @State private var openControl: ManualControl?

    /// Whether Pro Tools is shown.
    @State private var showsProTools = false

    /// The size of the space the view has, in points, measured as it changes.
    @State private var size: CGSize = .zero

    /// The shortest vertical swipe on the viewfinder that toggles clean view, in points.
    private static var cleanViewSwipeDistance: CGFloat { 60 }

    /// The minimum viewfinder height in the scrolling stacked layout, in points: enough to frame
    /// a shot while the enlarged controls take the rest of the screen.
    private static var scrollingViewfinderHeight: CGFloat { 280 }

    /// The margin around the screen's content, in points: the system's standard padding.
    private static var margin: CGFloat { 16 }

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
    ///
    /// The size is measured with `onGeometryChange` rather than a `GeometryReader` around the
    /// content, so the stacked arrangement is laid out exactly as a plain stack.
    var body: some View {
        Group {
            let content = CGSize(width: max(size.width - 2 * Self.margin, 0), height: max(size.height - 2 * Self.margin, 0))
            switch CameraLayout.arrangement(for: content, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
            case .stacked:
                stacked
            case .sideBySide(let columnWidth):
                sideBySide(columnWidth: columnWidth)
                    .padding(Self.margin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onChange(of: model.selectedLensID) { openControl = nil }
        .onChange(of: model.manual.isEnabled) { openControl = nil }
        // While Pro Tools covers the screen, the camera controls under it are hidden from
        // assistive technologies, so VoiceOver reads only the form.
        .accessibilityHidden(showsProTools)
        .fullScreenCover(isPresented: $showsProTools) {
            ProToolsSheet(model: model)
        }
    }

    /// The stacked arrangement, scrolling at accessibility text sizes. The margin is inside the
    /// scroll view, so the content scrolls to the screen's edges.
    @ViewBuilder private var stacked: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                stack(viewfinderHeight: Self.scrollingViewfinderHeight)
                    .padding(Self.margin)
            }
        } else {
            stack(viewfinderHeight: nil)
                .padding(Self.margin)
        }
    }

    /// The screen's parts, top to bottom.
    ///
    /// - Parameter viewfinderHeight: A fixed viewfinder height, or `nil` to fill the free space.
    private func stack(viewfinderHeight: CGFloat?) -> some View {
        VStack(spacing: CameraLayout.spacing) {
            if !model.isCleanView { topBar }
            formatBadge
            viewfinderArea
                .frame(maxWidth: .infinity, minHeight: viewfinderHeight, maxHeight: viewfinderHeight ?? .infinity)
                .gesture(cleanViewSwipe, isEnabled: viewfinderHeight == nil)
            intervalProgress
            CaptureStatusView(status: model.captureStatus)
            cameraControls(lensesPerRow: nil)
            shutterRow
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
                .gesture(cleanViewSwipe, isEnabled: !dynamicTypeSize.isAccessibilitySize)
            VStack(spacing: CameraLayout.spacing) {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: CameraLayout.spacing) {
                            if !model.isCleanView { topBar }
                            Spacer(minLength: 0)
                            intervalProgress
                            CaptureStatusView(status: model.captureStatus)
                            cameraControls(lensesPerRow: CameraLayout.lensesPerColumnRow)
                        }
                        // At least as tall as the visible area, so the lenses sit just above the
                        // shutter; taller content scrolls.
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .defaultScrollAnchor(.bottom)
                }
                shutterRow
            }
            .frame(width: columnWidth)
        }
    }

    /// The format badge. The no-RAW badge changes what the photo is, so clean view never hides
    /// it.
    @ViewBuilder private var formatBadge: some View {
        if let format = model.captureFormat, !model.isCleanView || !format.isBayerRAW {
            FormatBadge(format: format)
        }
    }

    /// A running interval series, with its stop button.
    @ViewBuilder private var intervalProgress: some View {
        if let progress = model.manual.intervalProgress {
            IntervalProgressView(progress: progress) {
                Task { await model.send(.manual(.stopInterval)) }
            }
        }
    }

    /// The manual controls when they are on, the controls slot and the lens buttons; nothing in
    /// clean view.
    ///
    /// - Parameter lensesPerRow: A fixed number of lens buttons per row, or `nil` for one row
    ///   that becomes one column when the text is too large.
    @ViewBuilder private func cameraControls(lensesPerRow: Int?) -> some View {
        if !model.isCleanView {
            if model.manual.isEnabled {
                ManualControlsView(model: model, openControl: $openControl, showsProTools: $showsProTools)
            }
            controls
            // The lens buttons make room while a control's panel is open.
            if openControl == nil || !model.manual.isEnabled {
                LensPicker(lenses: lenses, selectedID: model.selectedLensID, perRow: lensesPerRow) { id in
                    Task { await model.send(.selectLens(id)) }
                }
            }
        }
    }

    /// The shutter, with the clean view button on its leading side.
    private var shutterRow: some View {
        ZStack {
            ShutterButton(isEnabled: model.canCapture) {
                Task { await model.send(.capture) }
            }
            .accessibilityActions {
                if model.isCleanView {
                    Button {
                        Task { await model.send(.setCleanView(false)) }
                    } label: {
                        Text("Show Controls", bundle: .module, comment: "Button and VoiceOver action that brings back the controls hidden by clean view.")
                    }
                }
            }
            CleanViewButton(isCleanView: model.isCleanView) {
                Task { await model.send(.setCleanView(!model.isCleanView)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Swipe down on the viewfinder for clean view, up to bring the controls back.
    private var cleanViewSwipe: some Gesture {
        DragGesture(minimumDistance: Self.cleanViewSwipeDistance).onEnded { drag in
            let height = drag.translation.height
            guard abs(height) >= Self.cleanViewSwipeDistance, abs(height) > abs(drag.translation.width) else { return }
            Task { await model.send(.setCleanView(height > 0)) }
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

/// The eye button that turns clean view on and off. Its name says what it does next: "Hide
/// Controls" or "Show Controls", so Voice Control can say either.
struct CleanViewButton: View {
    /// Whether clean view is on.
    let isCleanView: Bool

    /// Toggles clean view.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - isCleanView: Whether clean view is on.
    ///   - action: Toggles clean view.
    init(isCleanView: Bool, action: @escaping () -> Void) {
        self.isCleanView = isCleanView
        self.action = action
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            Label {
                isCleanView
                    ? Text("Show Controls", bundle: .module, comment: "Button and VoiceOver action that brings back the controls hidden by clean view.")
                    : Text("Hide Controls", bundle: .module, comment: "Button that turns on clean view: hides every control except the shutter.")
            } icon: {
                Image(systemName: isCleanView ? "eye" : "eye.slash")
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            // Primary on the gray fill: the secondary tint fails the contrast audit.
            .foregroundStyle(.primary)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
    }
}
