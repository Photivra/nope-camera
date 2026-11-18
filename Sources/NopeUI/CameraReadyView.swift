import NopeCore
import SwiftUI

/// The camera when it is ready, in direction B of the 1.0.0 design (docs/design/BUILD-SPEC.md,
/// 3.1, 3.11 and 3.12).
///
/// Full auto shows the format status, the picture, the lens row (Manual Controls, the lenses,
/// Switch Camera), the drive strip (Single, Timer, Burst, Interval, Astro), and the shutter row:
/// the last photo after the first of the session, the shutter, and Q, which opens the quick
/// menu. Everything else appears only when it isn't at its default: state pills
/// (``StatePills``), warning chips (``CameraWarnings``), and on the picture's lower edge the
/// hints, the open dial, the running mode's card and the manual readouts.
///
/// ``CameraLayout`` chooses the arrangement:
/// - **Stacked** (iPhone, the iPhone Duo's outer display, compact iPad windows): the status line
///   (format status leading, pills trailing), the whole picture, the lens row and drive strip,
///   and the shutter row. When the rows don't fit below the picture, as on a 4.7-inch iPhone,
///   they overlay its bottom (``StackedMiddle``). The layout stays put when the iPhone turns;
///   icons and text blocks turn upright as units, the status moves onto the picture's upper
///   edge, Manual Controls shows "A" or "M", and the drive strip shows symbols with the mode
///   named in a pill on the picture. No Settings button: Settings opens from Q.
/// - **Scrolling**: at accessibility text sizes, in every window. The status, a 280-point
///   picture, then every control as a full-width row; the shutter row stays pinned.
/// - **Column** (iPad, the iPhone Duo's inner display, any window wider than tall): the picture
///   beside a trailing column with Settings, the lenses and Manual Controls at the top, Q, the
///   shutter and the last photo centered, and Switch Camera at the bottom. Format status and
///   warnings sit on the picture's top leading corner and pills on its top trailing corner; the
///   bottom stack and the drive strip are centered on its lower edge.
///
/// Clean view leaves only the picture, the shutter, a Show Controls button in the last photo's
/// place, any warning and any running series. Every gesture has a button: swiping the picture
/// down or up is a shortcut for Hide Controls (in the quick menu) and Show Controls.
///
/// The picture's frame is left clear and reported (``ViewfinderFrame``): ``CameraScreen`` draws
/// the live viewfinder there, behind this view, so it stays the same view in every mode. The view
/// keeps its state (the open dial, the quick menu, the timer delay) when the window changes
/// layout, as when an iPhone Duo folds or unfolds.
struct CameraReadyView: View {
    /// The model to render and send intents to.
    let model: CameraModel

    /// The person's settings.
    let settings: NopeSettings

    /// The lenses, in display order.
    let lenses: [Lens]

    /// Opens Settings.
    let openSettings: () -> Void

    /// The saved settings presets (issue #72), or `nil` for no Presets item.
    let presets: SettingsPresets?

    /// The current text size; accessibility sizes switch to the scrolling layout.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The horizontal size class; regular with a regular vertical class is a full-size iPad
    /// window.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The vertical size class.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Which way up the person holds the iPhone.
    @Environment(\.cameraUprightRotation) private var rotation

    /// Whether Reduce Motion is on: the thumbnail and the quick menu fade instead of moving.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tells the app that a sheet opened or closed, so it can rotate.
    @Environment(\.cameraPresentsSheet) private var presentsSheet

    /// Whether night mode is on, so the sheets opened here are red too.
    private var isNightMode: Bool { settings.isNightModeOn }

    /// The space the screen has.
    @State private var size = CGSize.zero

    /// The height of the lens row and drive strip, measured.
    @State private var bandsHeight: CGFloat = 0

    /// The manual control whose dial is open, or `nil`.
    @State private var openControl: ManualControl?

    /// Whether Pro Tools is shown.
    @State private var showsProTools = false

    /// Whether the format sheet is shown.
    @State private var showsFormats = false

    /// Whether the quick menu (Q) is open.
    @State private var showsQuickMenu = false

    /// Whether VoiceOver focus is on Q, to return it there when the quick menu closes.
    @AccessibilityFocusState private var isQuickButtonFocused: Bool

    /// Whether the last photo's details are shown (issue #53).
    @State private var showsPhotoDetails = false

    /// Whether VoiceOver focus is on Last Photo, to return it there when the viewer closes.
    @AccessibilityFocusState private var isLastPhotoFocused: Bool

    /// Opens Photos, or `nil` when the app can't.
    @Environment(\.openPhotosApp) private var openPhotosApp

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

    /// Whether the full-auto exposure dial is open (the Exposure item).
    @State private var showsExposureDial = false

    /// Whether the astro helper's settings are shown (issue #60).
    @State private var showsAstroSettings = false

    /// Whether the presets sheet is shown (issue #72).
    @State private var showsPresets = false

    /// Whether the Interval sheet is shown (the selected Interval word, or the interval card).
    @State private var showsIntervalSettings = false

    /// The self-timer delay the Timer word chooses: the last one chosen in this session, 3
    /// seconds at first (BUILD-SPEC.md, 3.5; not stored, section 6, item 8).
    @State private var timerDelay = SelfTimerDelay.threeSeconds

    /// The viewfinder's size, to turn a touch into a point in the picture.
    @State private var viewfinderSize = CGSize.zero

    /// Creates the ready view.
    ///
    /// - Parameters:
    ///   - model: The model to render.
    ///   - settings: The person's settings.
    ///   - lenses: The lenses, in display order.
    ///   - openSettings: Opens Settings.
    ///   - presets: The saved settings presets, or `nil` for no Presets item.
    init(
        model: CameraModel, settings: NopeSettings, lenses: [Lens], openSettings: @escaping () -> Void,
        presets: SettingsPresets? = nil
    ) {
        self.model = model
        self.settings = settings
        self.lenses = lenses
        self.openSettings = openSettings
        self.presets = presets
    }

    /// The registries' context.
    private var context: CameraControlContext {
        var context = CameraControlContext(model: model, settings: settings)
        context.showsExposureDial = $showsExposureDial
        context.presets = presets
        context.showsPresets = $showsPresets
        context.showsIntervalSettings = $showsIntervalSettings
        return context
    }

    /// The arrangement for the current space.
    private var layout: CameraLayout {
        CameraLayout.arrangement(
            for: size, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            isRegularSize: CameraLayout.isRegularSize(horizontal: horizontalSizeClass, vertical: verticalSizeClass))
    }

    /// Whether the controls are shown: not in clean view.
    private var showsControls: Bool { !model.isCleanView }

    /// Whether a countdown, burst, interval series or astro run is going: the shutter stops it,
    /// and the readout row and dials give the picture to the running mode's card.
    private var isSeriesRunning: Bool {
        model.drive.isBusy || model.astro.isRunning || model.manual.intervalProgress != nil
    }

    /// What the shutter's disc shows: a stop square while a series runs, the self-timer's delay
    /// while Timer is chosen, otherwise the plain disc.
    private var shutterFace: ShutterButton.Face {
        if isSeriesRunning { return .stop }
        if !model.astro.isOn, case .timer(let delay) = model.drive.mode { return .timer(seconds: delay.seconds) }
        return .photo
    }

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
        // While Pro Tools or the Last Photo viewer covers the screen, the camera controls under
        // it are hidden from assistive technologies, so VoiceOver reads only what covers them.
        .accessibilityHidden(showsProTools || model.isViewerOpen)
        .fullScreenCover(isPresented: $showsProTools) {
            ProToolsSheet(model: model, settings: settings)
                .nightModeStyle(isNightMode)
        }
        .comparisonCover(model, isNightMode: isNightMode)
        .photoViewerCover(model, isNightMode: isNightMode) { isLastPhotoFocused = true }
        .adaptivePresentation(isPresented: $showsFormats, prefersSheet: isNightMode) {
            if let format = model.captureFormat {
                FormatDetailsSheet(
                    settings: settings, format: format,
                    deviceSupportsBayerRAW: model.capabilities?.supportsBayerRAW ?? true,
                    distortionCorrection: model.selectedLens?.distortionCorrection ?? .notSwitchable)
                    .nightModeStyle(isNightMode)
                    .frame(idealWidth: 420, idealHeight: 560)
                    // Opaque: a translucent sheet or popover lets the live picture through and
                    // fails the contrast audit.
                    .presentationBackground(.background)
                    // Full height: at half height the explanation is cut off at large text sizes.
                    .presentationDetents([.large])
            }
        }
        // A sheet on iPad too, as the astro settings below: in the iPad popover, translucent
        // glass, the audit reported the list's rows as low contrast and as not following Dynamic
        // Type at the largest size, and a swipe outside the small popover didn't scroll it.
        .sheet(isPresented: $showsPhotoDetails) {
            PhotoDetailsSheet(photos: sessionPhotos ?? [], openPhoto: openPhotosApp.map { open in { open() } })
                // Red on black in night mode, as every other sheet of the camera.
                .nightModeStyle(isNightMode)
                .presentationBackground(.background)
                // Page sized on iPad: in the shorter form sheet the list's last rows sat at the
                // sheet's lower edge, where the audit measured them against the dimmed camera.
                .presentationSizing(.page)
                // Full height, as for the format sheet: at half height (issue #68 suggests medium
                // and large) the accessibility audit reports the rows at the sheet's lower edge as
                // clipped text.
                .presentationDetents([.large])
        }
        // A sheet on iPad too, not a popover: the iPad popover is translucent glass whatever its
        // presentation background, so the picture showed through the red-on-black settings and
        // their text failed the contrast audit. Page sized on iPad, so the estimates show
        // without scrolling, as on iPhone.
        .sheet(isPresented: $showsAstroSettings) {
            AstroSheet(model: model)
                .nightModeStyle(isNightMode)
                .presentationBackground(.background)
                .presentationDetents([.large])
                .presentationSizing(.page)
        }
        .onChange(of: model.astro.isOn) { _, isOn in if !isOn { showsAstroSettings = false } }
        // A sheet with an opaque background on iPad too, as the astro settings above, and page
        // sized there for the same reason as What's in This Photo: in the shorter form sheet the
        // explanation under Start ("Each photo is separate…") ran to the sheet's lower edge, where
        // the audit measured it against the dimmed camera.
        .sheet(isPresented: $showsIntervalSettings) {
            IntervalSheet(model: model)
                .nightModeStyle(isNightMode)
                .presentationBackground(.background)
                .presentationDetents([.large])
                .presentationSizing(.page)
        }
        // The same presets list as in Settings (issue #72), a sheet for the reasons above.
        .sheet(isPresented: $showsPresets) {
            if let presets {
                PresetsSheet(presets: presets, settings: settings, camera: model)
                    .nightModeStyle(isNightMode)
                    // Presets follows the system's light or dark setting, as in Settings.
                    .screenAppearance(.system, isNightMode: isNightMode)
                    .presentationBackground(.background)
                    .presentationDetents([.large])
                    .presentationSizing(.page)
            }
        }
        .onChange(of: showsProTools || showsFormats || showsPhotoDetails || showsAstroSettings || showsIntervalSettings || showsPresets || model.comparison.isPresented || model.isViewerOpen) { _, isPresenting in presentsSheet(isPresenting) }
        .task { await recordCaptureResults() }
        .onChange(of: model.selectedLensID, initial: true) { _, id in
            openControl = nil
            showsExposureDial = false
            if let id, let lens = model.capabilities?.lens(withID: id), lens.kind != .front { lastRearLensID = id }
        }
        .onChange(of: model.manual.isEnabled) {
            openControl = nil
            showsExposureDial = false
        }
        // VoiceOver focus goes back to Q when the quick menu closes (BUILD-SPEC.md, 3.6).
        .onChange(of: showsQuickMenu) { _, isOpen in
            if !isOpen, showsControls { isQuickButtonFocused = true }
        }
        .onChange(of: model.isCleanView) {
            showsQuickMenu = false
            showsExposureDial = false
        }
        // A delay chosen elsewhere (Siri, a preset) becomes the one Timer chooses next.
        .onChange(of: model.drive.mode, initial: true) { _, mode in
            if case .timer(let delay) = mode { timerDelay = delay }
        }
        .onChange(of: model.manual.focusTarget?.isLocked) { wasLocked, isLocked in
            // Announced only when the lock itself changes, not on every tap.
            guard wasLocked == true || isLocked == true else { return }
            AccessibilityNotification.Announcement(FocusText.announcement(isLocked: isLocked == true)).post()
        }
        .sensoryFeedback(NopeHaptic.saved, trigger: saveCount)
        .sensoryFeedback(NopeHaptic.notSaved, trigger: failureCount)
        .driveFeedback(model.drive)
        .astroFeedback(model.astro, isNightModeOn: isNightMode)
        .announcesResourceWarnings(model)
    }

    // MARK: - Arrangements

    /// Status line, picture with the rows, shutter row (iPhone).
    private var stacked: some View {
        VStack(spacing: 0) {
            statusLine
                .frame(minHeight: CameraLayout.topBarHeight)
                .padding(.horizontal, NopeSpace.m)
            StackedMiddle(
                bandsHeight: bandsHeight,
                picture: { pictureArea(isColumn: false) },
                dial: {
                    // Sideways, the bottom stack sits on the picture's lower edge as seen
                    // sideways instead (pictureArea).
                    if !rotation.isSideways, !isQuickMenuOpen { pictureBottomStack }
                },
                bands: {
                    if isQuickMenuOpen {
                        // Covered by Q's panel: their space is kept, and they leave the
                        // accessibility tree, which hiding them alone didn't do for the audit.
                        Color.clear.frame(height: bandsHeight)
                    } else {
                        rows
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bandsHeight = $0 }
                    }
                })
                // Q's panel covers the lens row and the drive strip, never the shutter row.
                .overlay(alignment: .bottom) { quickMenu(rotation.isSideways ? .sideways : .stacked) }
            shutterRow(quickSize: NopeSize.quick)
                .frame(minHeight: CameraLayout.shutterRowHeight)
                .padding(.horizontal, NopeSpace.xl)
        }
    }

    /// The rows in a scroll view, with a shorter picture (accessibility text sizes).
    private var scrolling: some View {
        // The shutter row stays pinned below the scroll view, so the shutter is always in reach.
        VStack(spacing: 0) {
            // Q's list takes the scrolling content's place while it is open (BUILD-SPEC.md, 3.6).
            if showsControls, showsQuickMenu {
                QuickMenuList(context: context, isPresented: $showsQuickMenu, openSettings: openSettings)
            } else {
                scrollingContent
            }
            shutterRow(quickSize: NopeSize.scrollingRowButton)
                .padding(.horizontal, NopeSpace.m)
                .padding(.vertical, NopeSpace.xs)
        }
    }

    /// Everything but the shutter row, scrolling.
    private var scrollingContent: some View {
        ScrollView {
            scrollingStack
        }
        .hardScrollEdges()
        // The viewfinder is drawn outside the scroll view (CameraScreen); this keeps it inside.
        .transformAnchorPreference(key: ViewfinderFrame.self, value: .bounds) { $0.clip = $1 }
    }

    /// The scrolling layout's parts, top to bottom (BUILD-SPEC.md, 3.12): format status, pills,
    /// warnings, the picture, the mode card, then Manual Controls, one row per lens, one row per
    /// drive mode, and the manual controls list when manual controls are on.
    private var scrollingStack: some View {
        VStack(alignment: .leading, spacing: NopeSpace.s) {
            formatChip
            StatePillRow(pills: showsControls ? StatePills.current(context) : StatePills.cleanView(context))
            warningsAndBanner
            // The session's message goes above the short picture here, not over it: at these
            // text sizes it is taller than the picture and overlapped the banner and the lens
            // buttons.
            SessionStatusView(status: model.sessionStatus)
            // Landscape in a wide window, where the preview turns with the interface.
            picture(showsStatus: false)
                .aspectRatio(CameraLayout.pictureAspectRatio(in: size), contentMode: .fit)
                .frame(height: CameraLayout.scrollingPictureHeight)
                .frame(maxWidth: .infinity)
            if LiveAidsPanel.isShown(model) {
                LiveAidsPanel(model: model, settings: settings)
            }
            modeCards
            CameraHints(model: model)
            if showsControls, showsExposureDial {
                AutoExposureDial(model: model) { showsExposureDial = false }
            }
            if showsControls {
                manualControlsButton(.row)
                LensRows(lenses: lenses, selectedID: model.selectedLensID) { select($0) }
                driveStrip(.rows)
                if model.manual.isEnabled {
                    ManualControlsList(model: model)
                    ManualOptionsMenu(model: model, openControl: $openControl, showsProTools: $showsProTools)
                }
            }
        }
        .padding(NopeSpace.m)
    }

    /// The picture beside a trailing control column (iPad, the iPhone Duo's inner display,
    /// wide windows).
    private var column: some View {
        HStack(spacing: 0) {
            ZStack {
                pictureArea(isColumn: true)
                    .aspectRatio(CameraLayout.pictureAspectRatio(in: size), contentMode: .fit)
                    .overlay(alignment: .bottom) {
                        VStack(spacing: NopeSpace.xs) {
                            // Q's panel may cover them; they return when it closes.
                            if !isQuickMenuOpen {
                                pictureBottomStack
                                if showsControls {
                                    driveStrip(.backedWords)
                                }
                            }
                        }
                        .frame(maxWidth: NopeSize.pictureStackMaxWidth)
                        .padding(NopeSpace.xs)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Q's panel opens beside the column, its bottom level with Q's.
            .overlay(alignment: .bottomTrailing) { quickMenu(.column) }
            controlColumn
        }
    }

    /// The trailing column (BUILD-SPEC.md, 3.11): Settings, the lenses and Manual Controls at the
    /// top; Q, the shutter and the last photo centered on the shutter; Switch Camera at the
    /// bottom. The top part scrolls if the text is too large to fit, and stops above Q: the two
    /// halves around the shutter share the height equally, so the shutter stays centered and
    /// nothing scrolls under it, even in a short window such as the unfolded inner display of an
    /// iPhone Duo held like a book.
    private var controlColumn: some View {
        VStack(spacing: NopeSpace.xs) {
            VStack(spacing: NopeSpace.xs) {
                if showsControls {
                    SettingsButton(action: openSettings)
                    ScrollView {
                        VStack(spacing: NopeSpace.xs) {
                            LensButtons(lenses: LensButtons.rear(lenses), selectedID: model.selectedLensID, isVertical: true) { select($0) }
                            manualControlsButton(.compactCapsule)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    Spacer(minLength: 0)
                    quickButton(size: NopeSize.quick)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            shutter
            VStack(spacing: NopeSpace.xs) {
                thumbnailOrShowControls
                Spacer(minLength: 0)
                if showsControls, let flip = flipTarget {
                    CameraFlipButton { select(flip) }
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(minWidth: NopeSize.column)
        .padding(.vertical, NopeSpace.m)
        .padding(.horizontal, NopeSpace.xs)
        // The column takes the width its controls need at the current text size, at least
        // NopeSize.column; the picture gets the rest.
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Rows

    /// The status line of the stacked layout: format status leading, pills trailing. While the
    /// iPhone is on its side its content moves onto the picture's upper edge, and the line
    /// stays as a margin so the picture doesn't move.
    @ViewBuilder private var statusLine: some View {
        if rotation.isSideways {
            Color.clear
        } else {
            HStack(spacing: NopeSpace.xs) {
                formatChip
                Spacer(minLength: 0)
                StatePillRow(pills: showsControls ? StatePills.current(context) : StatePills.cleanView(context))
            }
        }
    }

    /// The format status; in clean view only its warning, the "Processed" marker, stays. When the
    /// person turns the marker off in Settings (issue #80) it names the processed file instead,
    /// and VoiceOver still says it is processed (``FormatChip``).
    @ViewBuilder private var formatChip: some View {
        if let format = model.captureFormat,
            FormatChip.isShown(for: format, showsControls: showsControls, showsProcessedMarker: settings.showsProcessedMarker)
        {
            FormatChip(
                format: format, savedFormats: settings.selectedFormats(deviceSupportsBayerRAW: format.isBayerRAW),
                showsProcessedMarker: settings.showsProcessedMarker
            ) {
                showsFormats = true
            }
        }
    }

    /// The lens row and the drive strip of the stacked layout; nothing in clean view.
    @ViewBuilder private var rows: some View {
        if showsControls {
            VStack(spacing: 0) {
                lensRow
                    .frame(minHeight: NopeSize.lensRow)
                    .padding(.horizontal, NopeSpace.m)
                driveStrip(rotation.isSideways ? .symbols : .words)
                    .frame(maxWidth: .infinity, minHeight: NopeSize.driveRow)
                    .padding(.horizontal, NopeSpace.m)
            }
        }
    }

    /// Manual Controls at the leading end, the lens group centered over the shutter, Switch
    /// Camera at the trailing end. When the words don't fit, as with larger text, Manual Controls
    /// shows its letter instead (A or M), as it does sideways.
    private var lensRow: some View {
        ViewThatFits(in: .horizontal) {
            if !rotation.isSideways {
                lensRow(manualPresentation: .capsule)
            }
            lensRow(manualPresentation: .letter)
        }
    }

    /// The lens row with Manual Controls drawn one way.
    ///
    /// - Parameter manualPresentation: How Manual Controls is drawn.
    private func lensRow(manualPresentation: ManualControlsButton.Presentation) -> some View {
        CenteredRowLayout(spacing: NopeSpace.xs) {
            manualControlsButton(manualPresentation)
            LensButtons(lenses: LensButtons.rear(lenses), selectedID: model.selectedLensID) { select($0) }
            if let flip = flipTarget {
                CameraFlipButton { select(flip) }
                    .uprightUnit()
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    /// The Manual Controls button (issue #77): one tap turns manual controls on or off through
    /// `CameraModel.setManualControls(_:settings:)`.
    ///
    /// - Parameter presentation: How it is drawn for its place.
    private func manualControlsButton(_ presentation: ManualControlsButton.Presentation) -> some View {
        ManualControlsButton(isOn: model.manual.isEnabled, presentation: presentation) {
            let model = model
            let settings = settings
            let isOn = !model.manual.isEnabled
            Task { await model.setManualControls(isOn, settings: settings) }
        }
    }

    /// The drive strip.
    ///
    /// - Parameter presentation: How it is drawn for its place.
    private func driveStrip(_ presentation: DriveStrip.Presentation) -> some View {
        DriveStrip(
            model: model, settings: settings, presentation: presentation, timerDelay: $timerDelay,
            openIntervalSettings: { showsIntervalSettings = true },
            openAstroSettings: { showsAstroSettings = true })
    }

    /// The shutter row: the last photo (or Show Controls) on the leading side, the shutter in
    /// the middle, Q on the trailing side, each side the same width so the shutter is centered
    /// and the two are the same distance from it.
    ///
    /// - Parameter quickSize: Q's diameter.
    private func shutterRow(quickSize: CGFloat) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Color.clear.frame(width: 1, height: 1)
                thumbnailOrShowControls
            }
            .frame(maxWidth: .infinity)
            shutter
            ZStack {
                Color.clear.frame(width: 1, height: 1)
                if showsControls {
                    quickButton(size: quickSize)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Q: opens and closes the quick menu.
    ///
    /// - Parameter size: Its diameter.
    private func quickButton(size: CGFloat) -> some View {
        QuickButton(isOpen: showsQuickMenu, size: size) { showsQuickMenu.toggle() }
            // Escape (or Command-Period) on a hardware keyboard closes the open menu.
            .keyboardShortcut(showsQuickMenu ? .cancelAction : nil)
            .accessibilityFocused($isQuickButtonFocused)
    }

    /// Whether Q's panel is open over the camera (not the scrolling layout's list).
    private var isQuickMenuOpen: Bool {
        showsControls && showsQuickMenu && layout != .scrolling
    }

    /// The shutter. Pressing it closes the quick menu and takes a photo (or stops a series).
    private var shutter: some View {
        ShutterButton(isEnabled: model.canPressShutter, face: shutterFace) {
            showsQuickMenu = false
            Task { await model.send(.capture) }
        }
        .shutterDriveValue(model)
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
                image: sessionPhotos?.last?.thumbnail.flatMap(Image.photo),
                isBusy: model.captureStatus == .capturing || model.captureStatus == .saving,
                openViewer: { Task { await model.send(.setViewerOpen(true)) } },
                openPhoto: openPhotosApp.map { open in { open() } },
                showDetails: { showsPhotoDetails = true }
            )
            .accessibilityFocused($isLastPhotoFocused)
            .uprightUnit()
            .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            .animation(reduceMotion ? nil : NopeMotion.panel, value: sessionPhotos)
        }
    }

    // MARK: - Quick menu

    /// Where Q's panel opens.
    private enum QuickMenuPlacement {
        /// Over the lens row and drive strip, the width of the screen less a margin.
        case stacked

        /// Upright, over the picture's part beside the controls, while the iPhone is sideways.
        case sideways

        /// Over the picture beside the control column, near Q.
        case column
    }

    /// Q's panel in its place, while it is open.
    ///
    /// The panel (``QuickPanel``) closes itself through the binding; what it covers is taken out
    /// of the layout while it is open.
    ///
    /// - Parameter placement: Where it opens.
    @ViewBuilder private func quickMenu(_ placement: QuickMenuPlacement) -> some View {
        if isQuickMenuOpen {
            let panel = QuickPanel(context: context, isPresented: $showsQuickMenu, openSettings: openSettings)
            switch placement {
            case .stacked:
                panel
                    // At least as tall as the lens row and drive strip, which it covers.
                    .frame(minHeight: bandsHeight, alignment: .bottom)
                    .padding(.horizontal, NopeSpace.xs)
                    .padding(.bottom, NopeSpace.xs)
                    .transition(NopeMotion.panelTransition(reduceMotion: reduceMotion))
            case .sideways:
                panel
                    .uprightUnit(sidewaysWidth: min(NopeSize.panelMaxWidth, sidewaysBannerWidth ?? NopeSize.panelMaxWidth))
                    .padding(NopeSpace.xs)
            case .column:
                panel
                    .frame(maxWidth: NopeSize.panelMaxWidth)
                    .padding(.trailing, NopeSpace.xs)
                    .padding(.top, NopeSpace.xs)
                    // The shutter is centered in the column with Q just above it, so Q's bottom
                    // is half the height less half the shutter and the gap above it.
                    .padding(.bottom, max(size.height / 2 + NopeSize.shutter / 2 + NopeSpace.xs, NopeSpace.xs))
                    .transition(NopeMotion.panelTransition(reduceMotion: reduceMotion))
            }
        }
    }

    // MARK: - Picture

    /// The picture with everything drawn over it: the session's pause message and the countdown
    /// in the middle; the status, warnings and failure banner on the upper edge; the bottom
    /// stack on the lower edge where the layout puts it there.
    ///
    /// - Parameter isColumn: Whether this is the column layout, where the format status and
    ///   warnings sit on the top leading corner and the pills on the top trailing corner. Sideways
    ///   on an iPhone, the status turns upright on the edge that is up, as one unit.
    private func pictureArea(isColumn: Bool) -> some View {
        picture
            .overlay(alignment: overlayTopAlignment) {
                VStack(alignment: .leading, spacing: NopeSpace.xs) {
                    if isColumn {
                        formatChip
                    } else if rotation.isSideways {
                        sidewaysStatus
                    }
                    warningsAndBanner
                }
                .uprightUnit(sidewaysWidth: rotation.isSideways ? sidewaysBannerWidth : nil)
                .padding(NopeSpace.xs)
                // The status is on the picture here, so it gets the dark backing.
                .environment(\.isStatusOnPicture, true)
            }
            .overlay(alignment: .topTrailing) {
                if isColumn {
                    StatePillRow(pills: showsControls ? StatePills.current(context) : StatePills.cleanView(context))
                        // At its natural width: in the iPad column layout the row was laid out
                        // narrower than the picture's room and cut a pill short.
                        .fixedSize()
                        .padding(NopeSpace.xs)
                        .environment(\.isStatusOnPicture, true)
                }
            }
            .overlay(alignment: overlayBottomAlignment) {
                if !isColumn, rotation.isSideways {
                    pictureBottomStack
                        .uprightUnit(sidewaysWidth: sidewaysBannerWidth)
                        .padding(NopeSpace.xs)
                }
            }
    }

    /// The status on the picture while the iPhone is on its side: the format status leading;
    /// the pills and the drive mode's name trailing.
    private var sidewaysStatus: some View {
        HStack(spacing: NopeSpace.xs) {
            formatChip
            Spacer(minLength: 0)
            StatePillRow(pills: showsControls ? StatePills.current(context) : StatePills.cleanView(context))
            if showsControls {
                DriveModePill(word: DriveWord.selected(mode: model.drive.mode, isAstroOn: model.astro.isOn))
            }
        }
    }

    /// The bottom stack on the picture's lower edge, from the top: hints, the open dial, the
    /// running mode's card, the manual readouts (BUILD-SPEC.md, 3.1, `PictureBottomStack`). While
    /// a series runs, the readouts and dials are hidden.
    private var pictureBottomStack: some View {
        VStack(spacing: NopeSpace.xs) {
            CameraHints(model: model)
            if showsControls, !isSeriesRunning, !dynamicTypeSize.isAccessibilitySize {
                if let openControl, model.manual.isEnabled {
                    ControlDial(model: model, control: openControl)
                } else if showsExposureDial {
                    AutoExposureDial(model: model) { showsExposureDial = false }
                }
            }
            modeCards
            if showsControls, model.manual.isEnabled, !isSeriesRunning {
                // Each readout is a tile with its own backing (docs/design/screens/camera-manual).
                ManualReadoutRow(model: model, openControl: $openControl, showsProTools: $showsProTools)
            }
        }
        .padding(rotation.isSideways ? 0 : NopeSpace.xs)
    }

    /// The running or chosen mode's card (BUILD-SPEC.md, 3.5, ``ModeCards``).
    private var modeCards: some View {
        ModeCards(
            model: model, showsControls: showsControls, openIntervalSettings: { showsIntervalSettings = true },
            openAstroSettings: { showsAstroSettings = true })
    }

    /// The width text blocks wrap at while the iPhone is on its side: the picture's height,
    /// less margins, so a turned block fits across the picture.
    private var sidewaysBannerWidth: CGFloat? {
        guard rotation.isSideways else { return nil }
        let pictureHeight = min(CameraLayout.pictureHeight(forWidth: size.width), size.height)
        return max(pictureHeight - 4 * NopeSpace.xs, NopeSize.minTarget * 4)
    }

    /// Where the top-of-picture overlay sits: the top leading corner in portrait, or the edge
    /// that is up while the iPhone is on its side (the physical right edge when the device's top
    /// points left).
    private var overlayTopAlignment: Alignment {
        switch rotation {
        case .portrait: .topLeading
        case .landscapeLeft: layoutDirection == .rightToLeft ? .leading : .trailing
        case .landscapeRight: layoutDirection == .rightToLeft ? .trailing : .leading
        }
    }

    /// Where the bottom stack sits while the iPhone is on its side: the edge that is down, the
    /// opposite of ``overlayTopAlignment``.
    private var overlayBottomAlignment: Alignment {
        switch rotation {
        case .portrait: .bottom
        case .landscapeLeft: layoutDirection == .rightToLeft ? .trailing : .leading
        case .landscapeRight: layoutDirection == .rightToLeft ? .leading : .trailing
        }
    }

    /// The layout direction, to place overlays on physical edges.
    @Environment(\.layoutDirection) private var layoutDirection

    /// Warning chips and the failure banner.
    @ViewBuilder private var warningsAndBanner: some View {
        let warnings = CameraWarnings.current(context, lastSignature: sessionPhotos?.first(where: { $0.signature != .signed })?.signature)
        if !warnings.isEmpty {
            HStack(spacing: NopeSpace.xs) {
                ForEach(warnings) { WarningChip(warning: $0) }
            }
        }
        if let bannerError {
            FailureBanner(
                error: bannerError, canCapture: model.canCapture,
                tryAgain: { Task { await model.send(.capture) } },
                dismiss: { self.bannerError = nil })
        }
    }

    /// The viewfinder with the focus square and the session's pause message over it.
    ///
    /// VoiceOver reads it as one element that names the lens and the format (AGENTS.md,
    /// "VoiceOver"), with the actions Focus on Center and Lock (or Unlock) Focus and Exposure.
    /// Smart Invert leaves it alone. A tap focuses and exposes there (or closes the quick menu
    /// when it is open), a press and hold locks, and a vertical swipe is a shortcut for clean
    /// view.
    private var picture: some View {
        picture(showsStatus: true)
    }

    /// The viewfinder, with or without the session's message over it (see ``picture``).
    ///
    /// - Parameter showsStatus: Whether the session's message is drawn over the picture; the
    ///   scrolling layout shows it above the picture instead.
    private func picture(showsStatus: Bool) -> some View {
        ZStack {
            viewfinderLayer
            ViewfinderOverlays(model: model, settings: settings)
            if showsStatus {
                SessionStatusView(status: model.sessionStatus)
                    .uprightUnit(sidewaysWidth: sidewaysBannerWidth)
            }
            CountdownNumber(drive: model.drive)
                .uprightUnit()
        }
        .clipped()
        .contentShape(.rect)
    }

    /// The live picture, magnified when the focus magnifier is on, with the focus square. It
    /// is laid out left to right in every language: it is a picture, and a tapped point must
    /// mean the same place in the camera.
    private var viewfinderLayer: some View {
        // Clear: CameraScreen draws the live viewfinder behind it.
        Color.clear
            // Focus peaking is drawn on the picture itself, so the magnifier enlarges it too.
            .overlay { FocusPeakingLayer(model: model) }
            .focusMagnified(model)
            // Reported outside the enlargement, so CameraScreen gets the picture's own frame and
            // enlarges the viewfinder the same way (FocusMagnifier).
            .background { Color.clear.anchorPreference(key: ViewfinderFrame.self, value: .bounds) { ViewfinderAnchors(frame: $0) } }
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
                        guard !showsQuickMenu else {
                            showsQuickMenu = false
                            return
                        }
                        sendFocus(at: location, locks: false)
                    },
                    hold: { sendFocus(at: $0, locks: true) },
                    swipe: { height in Task { await model.send(.setCleanView(height > 0)) } }))
            .environment(\.layoutDirection, .leftToRight)
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

    /// The lens Switch Camera switches to: the front camera from a rear lens, or the rear lens
    /// last used from the front camera. `nil` when the device has no front or no rear camera.
    private var flipTarget: Lens.ID? {
        guard let front = lenses.first(where: { $0.kind == .front }) else { return nil }
        let rear = LensButtons.rear(lenses)
        guard let firstRear = rear.first else { return nil }
        guard model.selectedLens?.kind == .front else { return front.id }
        let defaultRear = rear.first(where: { $0.kind == .wide }) ?? firstRear
        return lastRearLensID ?? defaultRear.id
    }

    /// Switches to a lens and closes the quick menu.
    ///
    /// - Parameter id: The lens.
    private func select(_ id: Lens.ID) {
        showsQuickMenu = false
        Task { await model.send(.selectLens(id)) }
    }

    // MARK: - Feedback

    /// Records each new capture status for as long as the view is shown (``record(_:)``).
    ///
    /// It waits for the model's status to change and then reads it, instead of using
    /// `onChange(of:)` or `task(id:)`: when a photo is taken and fails (or is saved) within one
    /// frame, the status changes several times in that frame, and SwiftUI then runs those
    /// actions once and drops the rest ("onChange(of: CaptureStatus) action tried to update
    /// multiple times per frame"), so the failure banner never came, although the view was
    /// drawn again. Read after each change, the last status of a burst of changes is never
    /// missed; statuses in between may be, as before.
    private func recordCaptureResults() async {
        var last = model.captureStatus
        while !Task.isCancelled {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = model.captureStatus
                } onChange: {
                    continuation.resume()
                }
            }
            let status = model.captureStatus
            guard !Task.isCancelled, status != last else { continue }
            last = status
            record(status)
        }
    }

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

/// The middle of the stacked layout: the whole picture with the rows below it when they fit,
/// otherwise the rows over the bottom of the picture on ``NopeMaterial/rowOverlay`` (4.7-inch
/// iPhones, the iPhone Duo's outer display). The bottom stack sits over the bottom of the
/// picture, above the rows.
struct StackedMiddle<Picture: View, Dial: View, Bands: View>: View {
    /// The measured height of the bands.
    let bandsHeight: CGFloat

    /// The picture with its overlays.
    let picture: Picture

    /// The bottom stack (hints, dial, mode card, readouts), or nothing.
    let dial: Dial

    /// The lens row and the drive strip.
    let bands: Bands

    /// The space between the status line and the shutter row.
    @State private var space = CGSize.zero

    /// Creates the middle.
    ///
    /// - Parameters:
    ///   - bandsHeight: The measured height of the bands.
    ///   - picture: The picture with its overlays.
    ///   - dial: The bottom stack, or nothing.
    ///   - bands: The lens row and the drive strip.
    init(
        bandsHeight: CGFloat, @ViewBuilder picture: () -> Picture, @ViewBuilder dial: () -> Dial,
        @ViewBuilder bands: () -> Bands
    ) {
        self.bandsHeight = bandsHeight
        self.picture = picture()
        self.dial = dial()
        self.bands = bands()
    }

    /// The picture and the rows.
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
                            .nopeBackground(.rowOverlay, in: Rectangle())
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

/// Opens Settings: at the top of the column layout, and above the screens shown before the camera
/// is ready. In the stacked and scrolling layouts Settings opens from Q instead. Its name,
/// "Settings", is what VoiceOver reads and what Voice Control users say; the Large Content Viewer
/// shows it at accessibility text sizes.
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
        }
        .buttonStyle(NopeIconButtonStyle())
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
        }
        .buttonStyle(NopeIconButtonStyle(size: NopeSize.thumbnail))
    }
}

/// Where the ready camera reserves room for the live viewfinder, for ``CameraScreen`` to draw it
/// behind the interface: so night mode's red stays off the picture (issue #61), and so switching
/// night mode or Red Viewfinder never replaces the viewfinder (on a device, its preview layer).
/// Empty outside the ready camera.
struct ViewfinderFrame: PreferenceKey {
    /// Creates the key. It holds no state.
    init() {}

    /// No frame: there is no picture to fill.
    static var defaultValue: ViewfinderAnchors { ViewfinderAnchors() }

    /// Keeps the first frame and the first clip reported.
    ///
    /// - Parameters:
    ///   - value: The anchors so far.
    ///   - nextValue: The next anchors reported.
    static func reduce(value: inout ViewfinderAnchors, nextValue: () -> ViewfinderAnchors) {
        let next = nextValue()
        value.frame = value.frame ?? next.frame
        value.clip = value.clip ?? next.clip
    }
}

/// The picture's frame and, when the picture scrolls, the scroll view's frame, which the
/// viewfinder must stay inside: ``CameraScreen`` draws it behind the interface, outside the
/// scroll view, so without the clip it would run past the scroll view's edges into the pinned
/// shutter row or the top of the screen (the scrolling layout at accessibility text sizes).
struct ViewfinderAnchors {
    /// The picture's frame, or `nil` when there is no picture.
    var frame: Anchor<CGRect>?

    /// The frame the picture is seen through, or `nil` when it isn't clipped.
    var clip: Anchor<CGRect>?

    /// Creates the anchors.
    ///
    /// - Parameters:
    ///   - frame: The picture's frame.
    ///   - clip: The frame the picture is seen through.
    init(frame: Anchor<CGRect>? = nil, clip: Anchor<CGRect>? = nil) {
        self.frame = frame
        self.clip = clip
    }

    /// The part of the picture to show: all of it, or the part inside the clip; empty when the
    /// picture has scrolled out of view.
    ///
    /// - Parameters:
    ///   - frame: The picture's frame.
    ///   - clip: The frame the picture is seen through, or `nil`.
    /// - Returns: The visible frame, in the same coordinates.
    static func visibleFrame(of frame: CGRect, in clip: CGRect?) -> CGRect {
        guard let clip else { return frame }
        let visible = frame.intersection(clip)
        return visible.isNull ? .zero : visible
    }
}
