import NopeCore
import SwiftUI

/// The camera when it is ready, in the approved clean layout (issue #68, "UX v3").
///
/// Full auto shows the format chip, Settings, the lens row below the 4:3 picture with the
/// quick-controls button (⋯) at its end, the shutter, the camera flip and, after the first photo
/// of the session, the last-photo thumbnail. Everything else appears only when it isn't at its
/// default: state pills (``StatePills``), warning chips (``CameraWarnings``), the manual
/// readout row and its dial when the "Manual controls" option is on, and a failure banner.
///
/// ``CameraLayout`` chooses the arrangement:
/// - **Stacked** (iPhone): top bar 44 points, the whole picture, the lens row, the manual
///   readout, and the shutter row 88 points. When the bands don't fit below the picture, as on a
///   4.7-inch iPhone, they overlay its bottom on a dark backing. The layout stays put when the
///   iPhone turns; icons and text blocks turn upright as units, and the chip, pills and warnings
///   move to the picture's upper edge.
/// - **Scrolling**: the same bands in a scroll view at accessibility text sizes.
/// - **Column** (iPad, or a window wider than tall): the picture beside a trailing column with
///   the shutter centered; pills, chip and warnings over the picture's top, and the manual
///   controls and tray over its bottom.
///
/// Clean view leaves only the picture, the shutter, a Show Controls button in the thumbnail's
/// place and any warning. Every gesture has a button: swiping the picture down or up is a
/// shortcut for Hide Controls (in the tray) and Show Controls.
struct CameraReadyView<Viewfinder: View>: View {
    /// The model to render and send intents to.
    let model: CameraModel

    /// The person's settings.
    let settings: NopeSettings

    /// The lenses, in display order.
    let lenses: [Lens]

    /// Opens Settings.
    let openSettings: () -> Void

    /// The live viewfinder from the app.
    let viewfinder: Viewfinder

    /// The current text size; accessibility sizes switch to the scrolling layout.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The horizontal size class; regular with a regular vertical class is a full-size iPad
    /// window.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The vertical size class.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Which way up the person holds the iPhone.
    @Environment(\.cameraUprightRotation) private var rotation

    /// Whether Reduce Motion is on: the thumbnail fades in instead of sliding.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tells the app that a sheet opened or closed, so it can rotate.
    @Environment(\.cameraPresentsSheet) private var presentsSheet

    /// Whether night mode is on, so the sheets opened here are red too.
    private var isNightMode: Bool { settings.isNightModeOn }

    /// The space the screen has.
    @State private var size = CGSize.zero

    /// The height of the lens row and manual readout, measured.
    @State private var bandsHeight: CGFloat = 0

    /// The manual control whose dial is open, or `nil`.
    @State private var openControl: ManualControl?

    /// Whether Pro Tools is shown.
    @State private var showsProTools = false

    /// Whether the format sheet is shown.
    @State private var showsFormats = false

    /// Whether the quick-controls tray is open.
    @State private var showsTray = false

    /// The photos the last good save added this session, or `nil` before the first.
    @State private var sessionPhotos: [SavedPhoto]?

    /// The failure the banner shows, or `nil`.
    @State private var bannerError: CaptureError?

    /// Counts good saves, for the light haptic.
    @State private var saveCount = 0

    /// Counts failures, for the error haptic.
    @State private var failureCount = 0

    /// The rear lens to return to from the front camera.
    @State private var lastRearLensID: Lens.ID?

    /// Whether the full-auto exposure dial is open (the Exposure tray item).
    @State private var showsExposureDial = false

    /// The viewfinder's size, to turn a touch into a point in the picture.
    @State private var viewfinderSize = CGSize.zero

    /// Creates the ready view.
    ///
    /// - Parameters:
    ///   - model: The model to render.
    ///   - settings: The person's settings.
    ///   - lenses: The lenses, in display order.
    ///   - openSettings: Opens Settings.
    ///   - viewfinder: Makes the live viewfinder.
    init(
        model: CameraModel, settings: NopeSettings, lenses: [Lens], openSettings: @escaping () -> Void,
        @ViewBuilder viewfinder: () -> Viewfinder
    ) {
        self.model = model
        self.settings = settings
        self.lenses = lenses
        self.openSettings = openSettings
        self.viewfinder = viewfinder()
    }

    /// The registries' context.
    private var context: CameraControlContext {
        var context = CameraControlContext(model: model, settings: settings)
        context.showsExposureDial = $showsExposureDial
        return context
    }

    /// The arrangement for the current space.
    private var layout: CameraLayout {
        CameraLayout.arrangement(
            for: size, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            isRegularSize: horizontalSizeClass == .regular && verticalSizeClass == .regular)
    }

    /// Whether the bands are shown: not in clean view.
    private var showsControls: Bool { !model.isCleanView }

    /// The screen.
    var body: some View {
        Group {
            switch layout {
            case .stacked: stacked
            case .scrolling: scrolling
            case .column: column
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        // While Pro Tools covers the screen, the camera controls under it are hidden from
        // assistive technologies, so VoiceOver reads only the form.
        .accessibilityHidden(showsProTools)
        .fullScreenCover(isPresented: $showsProTools) {
            ProToolsSheet(model: model)
                .nightModeStyle(isNightMode)
        }
        .adaptivePresentation(isPresented: $showsFormats) {
            if let format = model.captureFormat {
                FormatDetailsSheet(
                    settings: settings, format: format,
                    deviceSupportsBayerRAW: model.capabilities?.supportsBayerRAW ?? true)
                    .nightModeStyle(isNightMode)
                    .frame(idealWidth: 420, idealHeight: 560)
                    // Opaque: a translucent sheet or popover lets the live picture through and
                    // fails the contrast audit.
                    .presentationBackground(.background)
                    // Full height: at half height the explanation is cut off at large text sizes.
                    .presentationDetents([.large])
            }
        }
        .onChange(of: showsProTools || showsFormats) { _, isPresenting in presentsSheet(isPresenting) }
        .onChange(of: model.captureStatus) { _, status in record(status) }
        .onChange(of: model.selectedLensID, initial: true) { _, id in
            openControl = nil
            showsExposureDial = false
            if let id, let lens = model.capabilities?.lens(withID: id), lens.kind != .front { lastRearLensID = id }
        }
        .onChange(of: model.manual.isEnabled) {
            openControl = nil
            showsExposureDial = false
        }
        .onChange(of: model.isCleanView) {
            showsTray = false
            showsExposureDial = false
        }
        .onChange(of: model.manual.focusTarget?.isLocked) { wasLocked, isLocked in
            // Announced only when the lock itself changes, not on every tap.
            guard wasLocked == true || isLocked == true else { return }
            AccessibilityNotification.Announcement(FocusText.announcement(isLocked: isLocked == true)).post()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: saveCount)
        .sensoryFeedback(.error, trigger: failureCount)
    }

    // MARK: - Arrangements

    /// Top bar, picture with bands, shutter row (iPhone).
    private var stacked: some View {
        VStack(spacing: 0) {
            topBar
                .frame(minHeight: CameraLayout.topBarHeight)
                .padding(.horizontal, CameraStyle.targetSpacing)
            StackedMiddle(
                bandsHeight: bandsHeight,
                picture: { pictureArea(clusterOverPicture: rotation.isSideways) },
                dial: { stackedDial },
                bands: {
                    bands
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bandsHeight = $0 }
                })
            shutterRow
                .frame(minHeight: CameraLayout.shutterRowHeight)
                .padding(.horizontal)
        }
    }

    /// The stacked bands in a scroll view, with a shorter picture (accessibility text sizes).
    private var scrolling: some View {
        // The shutter row stays pinned below the scroll view, so the shutter is always in reach.
        VStack(spacing: 0) {
            scrollingContent
            shutterRow
                .padding(.horizontal)
                .padding(.vertical, CameraStyle.targetSpacing)
        }
    }

    /// Everything but the shutter row, scrolling.
    private var scrollingContent: some View {
        ScrollView {
            scrollingStack
        }
        .hardScrollEdges()
    }

    /// The scrolling layout's parts, top to bottom.
    private var scrollingStack: some View {
        Group {
            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: CameraStyle.targetSpacing) { topBarItems }
                    VStack(spacing: CameraStyle.targetSpacing) { topBarItems }
                }
                warningsAndBanner(sidewaysWidth: nil)
                picture
                    .aspectRatio(1 / CameraLayout.photoAspectRatio, contentMode: .fit)
                    .frame(height: CameraLayout.scrollingPictureHeight)
                if showsControls, showsExposureDial {
                    AutoExposureDial(model: model) { showsExposureDial = false }
                }
                if showsControls {
                    if model.manual.isEnabled {
                        ManualControlsList(model: model)
                        ManualOptionsMenu(model: model, openControl: $openControl, showsProTools: $showsProTools)
                    }
                    VStack(spacing: CameraStyle.targetSpacing) {
                        LensButtons(lenses: LensButtons.rear(lenses), selectedID: model.selectedLensID, isVertical: true) { select($0) }
                        QuickControlsButton(isOpen: showsTray) { showsTray.toggle() }
                        if showsTray {
                            QuickControlsTray(items: QuickControls.current(context)) { showsTray = false }
                        }
                    }
                }
            }
            .padding()
        }
    }

    /// The picture beside a trailing control column (iPad, wide windows).
    private var column: some View {
        HStack(spacing: 0) {
            ZStack {
                pictureArea(clusterOverPicture: true)
                    .aspectRatio(CameraLayout.pictureAspectRatio(in: size), contentMode: .fit)
                    .overlay(alignment: .bottom) {
                        VStack(spacing: CameraStyle.targetSpacing) {
                            if showsControls {
                                if showsTray {
                                    QuickControlsTray(items: QuickControls.current(context)) { showsTray = false }
                                }
                                if showsExposureDial {
                                    AutoExposureDial(model: model) { showsExposureDial = false }
                                }
                                if model.manual.isEnabled && !dynamicTypeSize.isAccessibilitySize {
                                    if let openControl {
                                        ControlDial(model: model, control: openControl)
                                    }
                                    ManualReadoutRow(model: model, openControl: $openControl, showsProTools: $showsProTools)
                                        .padding(4)
                                        .darkBacking()
                                }
                            }
                        }
                        .padding(CameraStyle.targetSpacing)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            controlColumn
        }
    }

    /// The trailing column: Settings, lenses and ⋯ at the top, the shutter centered, the camera
    /// flip and the thumbnail at the bottom. It scrolls if the text is too large to fit.
    private var controlColumn: some View {
        ZStack {
            VStack(spacing: CameraStyle.targetSpacing) {
                if showsControls {
                    SettingsButton(action: openSettings)
                    ScrollView {
                        VStack(spacing: CameraStyle.targetSpacing) {
                            LensButtons(lenses: LensButtons.rear(lenses), selectedID: model.selectedLensID, isVertical: true) { select($0) }
                            QuickControlsButton(isOpen: showsTray) { showsTray.toggle() }
                            if model.manual.isEnabled && dynamicTypeSize.isAccessibilitySize {
                                ManualOptionsMenu(model: model, openControl: $openControl, showsProTools: $showsProTools)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                Spacer(minLength: ShutterButton.diameter + 2 * CameraStyle.targetSpacing)
                if showsControls, let flip = flipTarget {
                    CameraFlipButton { select(flip) }
                }
                thumbnailOrShowControls
            }
            shutter
        }
        .frame(minWidth: ShutterButton.diameter + 2 * CameraStyle.targetSpacing)
        .padding(.vertical)
        .padding(.horizontal, CameraStyle.targetSpacing)
        // The column takes the width its controls need at the current text size; the picture
        // gets the rest.
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Parts

    /// The top bar: pills on the leading side, the format chip and Settings on the trailing side.
    /// While the iPhone is on its side, the pills and chip move over the picture and only
    /// Settings stays.
    private var topBar: some View {
        HStack(spacing: CameraStyle.targetSpacing) {
            if rotation.isSideways {
                Spacer(minLength: 0)
                if showsControls {
                    SettingsButton(action: openSettings).uprightUnit()
                }
            } else {
                topBarItems
            }
        }
    }

    /// The top bar's items in portrait.
    @ViewBuilder private var topBarItems: some View {
        StatePillRow(pills: showsControls ? StatePills.current(context) : StatePills.cleanView(context))
        Spacer(minLength: 0)
        formatChip
        if showsControls {
            SettingsButton(action: openSettings)
        }
    }

    /// The format chip; in clean view only its warning stays.
    @ViewBuilder private var formatChip: some View {
        if let format = model.captureFormat, showsControls || !format.isBayerRAW {
            FormatChip(format: format, savedFormats: settings.selectedFormats(deviceSupportsBayerRAW: format.isBayerRAW)) {
                showsFormats = true
            }
        }
    }

    /// The lens row (or the tray in its place) and the manual readout row.
    @ViewBuilder private var bands: some View {
        if showsControls {
            VStack(spacing: 0) {
                HStack(spacing: CameraStyle.targetSpacing) {
                    if showsTray {
                        QuickControlsTray(items: QuickControls.current(context)) { showsTray = false }
                    } else {
                        Spacer(minLength: 0)
                        LensButtons(lenses: LensButtons.rear(lenses), selectedID: model.selectedLensID) { select($0) }
                        Spacer(minLength: 0)
                    }
                    QuickControlsButton(isOpen: showsTray) { showsTray.toggle() }
                }
                .frame(minHeight: CameraStyle.minimumTarget)
                .padding(.horizontal, CameraStyle.targetSpacing)
                if model.manual.isEnabled {
                    ManualReadoutRow(model: model, openControl: $openControl, showsProTools: $showsProTools)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    /// The shutter row: thumbnail (or Show Controls) on the leading side, the shutter in the
    /// middle, the camera flip on the trailing side.
    private var shutterRow: some View {
        HStack(spacing: 0) {
            // Each side keeps its width even when empty, so the shutter stays centered.
            ZStack {
                Color.clear.frame(width: 1, height: 1)
                thumbnailOrShowControls
            }
            .frame(maxWidth: .infinity)
            shutter
            ZStack {
                Color.clear.frame(width: 1, height: 1)
                if showsControls, let flip = flipTarget {
                    CameraFlipButton { select(flip) }
                        .uprightUnit()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The shutter. Pressing it closes the tray and takes a photo.
    private var shutter: some View {
        ShutterButton(isEnabled: model.canCapture) {
            showsTray = false
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
    }

    /// The thumbnail slot, or in clean view the Show Controls button in its place.
    @ViewBuilder private var thumbnailOrShowControls: some View {
        if model.isCleanView {
            ShowControlsButton { Task { await model.send(.setCleanView(false)) } }
                .uprightUnit()
        } else {
            ThumbnailSlot(
                photos: sessionPhotos,
                isBusy: model.captureStatus == .capturing || model.captureStatus == .saving
            )
            .uprightUnit()
            .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            .animation(reduceMotion ? nil : .snappy, value: sessionPhotos)
        }
    }

    /// The picture with everything drawn over it: the session's pause message in the middle,
    /// warnings, the failure banner and a running interval series at the top, the open dial at
    /// the bottom.
    ///
    /// - Parameter clusterOverPicture: Whether the pills and format chip sit over the picture's
    ///   upper edge (iPhone on its side, iPad), rather than in the top bar.
    private func pictureArea(clusterOverPicture: Bool) -> some View {
        picture
            .overlay(alignment: overlayTopAlignment) {
                VStack(alignment: .leading, spacing: CameraStyle.targetSpacing) {
                    if clusterOverPicture {
                        HStack(spacing: CameraStyle.targetSpacing) {
                            StatePillRow(pills: showsControls ? StatePills.current(context) : StatePills.cleanView(context))
                            formatChip
                        }
                    }
                    warningsAndBanner(sidewaysWidth: sidewaysBannerWidth)
                }
                .uprightUnit(sidewaysWidth: rotation.isSideways ? sidewaysBannerWidth : nil)
                .padding(CameraStyle.targetSpacing)
            }
            .overlay(alignment: .bottom) {
            }
    }

    /// The open dial in the stacked layout, which places it over the picture's bottom, above
    /// the bands when they overlay the picture. The column layout puts it above the readout row.
    @ViewBuilder private var stackedDial: some View {
        if showsControls, let openControl, model.manual.isEnabled, !dynamicTypeSize.isAccessibilitySize {
            ControlDial(model: model, control: openControl)
                .uprightUnit(sidewaysWidth: sidewaysBannerWidth)
                .padding(CameraStyle.targetSpacing)
        } else if showsControls, showsExposureDial, !dynamicTypeSize.isAccessibilitySize {
            AutoExposureDial(model: model) { showsExposureDial = false }
                .uprightUnit(sidewaysWidth: sidewaysBannerWidth)
                .padding(CameraStyle.targetSpacing)
        }
    }

    /// The width text blocks wrap at while the iPhone is on its side: the picture's height,
    /// less margins, so a turned block fits across the picture.
    private var sidewaysBannerWidth: CGFloat? {
        guard rotation.isSideways else { return nil }
        let pictureHeight = min(CameraLayout.pictureHeight(forWidth: size.width), size.height)
        return max(pictureHeight - 4 * CameraStyle.targetSpacing, 200)
    }

    /// Where the top-of-picture overlay sits: the top in portrait, or the edge that is up while
    /// the iPhone is on its side (the physical right edge when the device's top points left).
    private var overlayTopAlignment: Alignment {
        switch rotation {
        case .portrait: .topLeading
        case .landscapeLeft: layoutDirection == .rightToLeft ? .leading : .trailing
        case .landscapeRight: layoutDirection == .rightToLeft ? .trailing : .leading
        }
    }

    /// The layout direction, to place overlays on physical edges.
    @Environment(\.layoutDirection) private var layoutDirection

    /// Warning chips, the failure banner and a running interval series.
    ///
    /// - Parameter sidewaysWidth: The wrapping width while the iPhone is on its side.
    @ViewBuilder private func warningsAndBanner(sidewaysWidth: CGFloat?) -> some View {
        let warnings = CameraWarnings.current(context, lastSignature: sessionPhotos?.first(where: { $0.signature != .signed })?.signature)
        if !warnings.isEmpty {
            HStack(spacing: CameraStyle.targetSpacing) {
                ForEach(warnings) { WarningChip(warning: $0) }
            }
        }
        if let bannerError {
            FailureBanner(
                error: bannerError, canCapture: model.canCapture,
                tryAgain: { Task { await model.send(.capture) } },
                dismiss: { self.bannerError = nil })
        }
        if let progress = model.manual.intervalProgress {
            IntervalProgressView(progress: progress) {
                Task { await model.send(.manual(.stopInterval)) }
            }
        }
        CameraHints(model: model)
    }

    /// The viewfinder with the focus square and the session's pause message over it.
    ///
    /// VoiceOver reads it as one element that names the lens and the format (AGENTS.md,
    /// "VoiceOver"), with the actions Focus on Center and Lock (or Unlock) Focus and Exposure.
    /// Smart Invert leaves it alone. A tap focuses and exposes there (or closes the tray when it
    /// is open), a press and hold locks, and a vertical swipe is a shortcut for clean view.
    private var picture: some View {
        ZStack {
            viewfinderLayer
            SessionStatusView(status: model.sessionStatus)
                .uprightUnit(sidewaysWidth: sidewaysBannerWidth)
        }
        .clipped()
        .contentShape(.rect)
    }

    /// The live picture, magnified when the focus magnifier is on, with the focus square. It
    /// is laid out left to right in every language: it is a picture, and a tapped point must
    /// mean the same place in the camera.
    private var viewfinderLayer: some View {
        viewfinderContent
            .scaleEffect(
                model.isMagnifying ? FocusMagnifier.scale : 1,
                anchor: magnifierAnchor)
            .overlay { FocusSquareLayer(model: model, part: .square) }
            .accessibilityIgnoresInvertColors()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Viewfinder", bundle: .module, comment: "VoiceOver name of the live camera view."))
            .accessibilityValue(viewfinderDescription)
            .accessibilityActions { viewfinderActions }
            .overlay { FocusSquareLayer(model: model, part: .lockButton) }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewfinderSize = $0 }
            .contentShape(.rect)
            .modifier(
                ViewfinderTouches(
                    allowsDrags: layout != .scrolling,
                    tap: { location in
                        guard !showsTray else {
                            showsTray = false
                            return
                        }
                        sendFocus(at: location, locks: false)
                    },
                    hold: { sendFocus(at: $0, locks: true) },
                    swipe: { height in Task { await model.send(.setCleanView(height > 0)) } }))
            .environment(\.layoutDirection, .leftToRight)
    }

    /// The point the magnifier is centered on.
    private var magnifierAnchor: UnitPoint {
        let anchor = FocusMagnifier.anchor(for: model.manual.focusTarget)
        return UnitPoint(x: anchor.x, y: anchor.y)
    }

    /// The viewfinder's VoiceOver, Voice Control and Switch Control actions: the same as a tap
    /// in the middle and the lock button (issue #68, "VoiceOver viewfinder actions").
    @ViewBuilder private var viewfinderActions: some View {
        if model.manual.capabilities.supportsTapToFocus {
            Button {
                Task { await model.send(.auto(.focusAndExpose(at: .center))) }
            } label: {
                FocusText.focusOnCenter
            }
            if model.manual.focusTarget?.isLocked == true {
                Button {
                    Task { await model.send(.auto(.unlockFocusAndExposure)) }
                } label: {
                    FocusText.unlock
                }
            } else {
                Button {
                    Task { await model.send(.auto(.lockFocusAndExposure(at: nil))) }
                } label: {
                    FocusText.lock
                }
            }
        }
    }

    /// The live viewfinder; in night mode with natural colors, a clear frame that
    /// ``CameraScreen`` fills from behind the red interface (``NaturalViewfinderFrame``), so the
    /// red tint doesn't reach the picture. The photo is never changed either way.
    @ViewBuilder private var viewfinderContent: some View {
        if isNightMode && !settings.tintsViewfinderInNightMode {
            Color.clear.anchorPreference(key: NaturalViewfinderFrame.self, value: .bounds) { $0 }
        } else {
            viewfinder
        }
    }

    /// Focuses and exposes at a touched location, through the magnifier when it is on.
    ///
    /// - Parameters:
    ///   - location: Where the viewfinder was touched, in its points.
    ///   - locks: Whether to lock there.
    private func sendFocus(at location: CGPoint, locks: Bool) {
        guard
            var point = FramePoint.normalized(
                locationX: location.x, locationY: location.y, width: viewfinderSize.width, height: viewfinderSize.height)
        else { return }
        if model.isMagnifying {
            point = point.unmagnified(scale: FocusMagnifier.scale, anchor: FocusMagnifier.anchor(for: model.manual.focusTarget))
        }
        let target = point
        Task { await model.send(.auto(locks ? .lockFocusAndExposure(at: target) : .focusAndExpose(at: target))) }
    }

    /// "Lens: Wide. Format: single-frame RAW." for VoiceOver.
    private var viewfinderDescription: Text {
        guard let lens = model.selectedLens, let format = model.captureFormat else { return Text(verbatim: "") }
        let lensName = LensName.string(for: lens.kind)
        let formatName = FormatChip.spokenName(for: format)
        return Text(
            "Lens: \(lensName). Format: \(formatName).", bundle: .module,
            comment: "VoiceOver value of the viewfinder. The first value is a lens name such as Wide; the second is a format such as single-frame RAW.")
    }

    // MARK: - Lenses

    /// The lens the camera flip switches to: the front camera from a rear lens, or the rear lens
    /// last used from the front camera. `nil` when the device has no front or no rear camera.
    private var flipTarget: Lens.ID? {
        guard let front = lenses.first(where: { $0.kind == .front }) else { return nil }
        let rear = LensButtons.rear(lenses)
        guard let firstRear = rear.first else { return nil }
        guard model.selectedLens?.kind == .front else { return front.id }
        let defaultRear = rear.first(where: { $0.kind == .wide }) ?? firstRear
        return lastRearLensID ?? defaultRear.id
    }

    /// Switches to a lens and closes the tray.
    ///
    /// - Parameter id: The lens.
    private func select(_ id: Lens.ID) {
        showsTray = false
        Task { await model.send(.selectLens(id)) }
    }

    // MARK: - Feedback

    /// Records a capture result: a good save updates the thumbnail quietly, with a light haptic
    /// and a low-priority VoiceOver announcement, and clears the banner; a failure shows the
    /// banner until it is dismissed or the next good save.
    ///
    /// - Parameter status: The new capture status.
    private func record(_ status: CaptureStatus) {
        if let photos = CaptureMessages.savedPhotos(in: status) {
            sessionPhotos = photos
            bannerError = nil
            saveCount += 1
            var announcement = AttributedString(CaptureMessages.message(forSaved: photos))
            announcement.accessibilitySpeechAnnouncementPriority = .low
            AccessibilityNotification.Announcement(announcement).post()
        } else if let error = CaptureMessages.error(in: status) {
            bannerError = error
            failureCount += 1
        }
    }
}

/// The middle of the stacked layout: the whole picture with the bands below it when they fit,
/// otherwise the bands over the bottom of the picture on a dark backing (4.7-inch iPhones). The
/// open dial sits over the bottom of the picture, above the bands.
struct StackedMiddle<Picture: View, Dial: View, Bands: View>: View {
    /// The measured height of the bands.
    let bandsHeight: CGFloat

    /// The picture with its overlays.
    let picture: Picture

    /// The open manual dial, or nothing.
    let dial: Dial

    /// The lens row and the manual readout.
    let bands: Bands

    /// The space between the top bar and the shutter row.
    @State private var space = CGSize.zero

    /// Creates the middle.
    ///
    /// - Parameters:
    ///   - bandsHeight: The measured height of the bands.
    ///   - picture: The picture with its overlays.
    ///   - dial: The open manual dial, or nothing.
    ///   - bands: The lens row and the manual readout.
    init(
        bandsHeight: CGFloat, @ViewBuilder picture: () -> Picture, @ViewBuilder dial: () -> Dial,
        @ViewBuilder bands: () -> Bands
    ) {
        self.bandsHeight = bandsHeight
        self.picture = picture()
        self.dial = dial()
        self.bands = bands()
    }

    /// The picture and the bands.
    var body: some View {
        Group {
            if CameraLayout.bandsOverlayPicture(in: space, bandsHeight: bandsHeight) {
                ZStack(alignment: .bottom) {
                    picture
                        .aspectRatio(1 / CameraLayout.photoAspectRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    VStack(spacing: 0) {
                        dial
                        bands
                            .darkBacking(Rectangle())
                    }
                }
            } else {
                VStack(spacing: 0) {
                    picture
                        .frame(width: space.width, height: CameraLayout.pictureHeight(forWidth: space.width))
                        .overlay(alignment: .bottom) { dial }
                    bands
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { space = $0 }
    }
}

/// Opens Settings. Its name, "Settings", is what VoiceOver reads and what Voice Control users
/// say; the Large Content Viewer shows it at accessibility text sizes.
struct SettingsButton: View {
    /// Opens Settings.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameter action: Opens Settings.
    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            Label {
                Text("Settings", bundle: .module, comment: "Title of the settings screen, and the camera button that opens it.")
            } icon: {
                Image(systemName: "gearshape")
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(.white)
            .padding(8)
            .frame(minWidth: CameraStyle.minimumTarget, minHeight: CameraStyle.minimumTarget)
            .background(Color(white: 0.2), in: .circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityShowsLargeContentViewer()
    }
}

/// Brings back the controls hidden by clean view. It sits in the thumbnail's place, so Show
/// Controls is always a visible button, not only a gesture.
struct ShowControlsButton: View {
    /// Turns clean view off.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameter action: Turns clean view off.
    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            Label {
                Text("Show Controls", bundle: .module, comment: "Button and VoiceOver action that brings back the controls hidden by clean view.")
            } icon: {
                Image(systemName: "eye")
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(.white)
            .padding(8)
            .frame(minWidth: ThumbnailSlot.side, minHeight: ThumbnailSlot.side)
            .background(Color(white: 0.2), in: .circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer()
    }
}

/// Where the ready camera reserves room for a viewfinder in natural colors while night mode is
/// on, for ``CameraScreen`` to draw it behind the red interface (issue #61). `nil` otherwise.
struct NaturalViewfinderFrame: PreferenceKey {
    /// Creates the key. It holds no state.
    init() {}

    /// No frame: the viewfinder is drawn in place.
    static var defaultValue: Anchor<CGRect>? { nil }

    /// Keeps the first frame reported.
    ///
    /// - Parameters:
    ///   - value: The frame so far.
    ///   - nextValue: The next frame reported.
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
