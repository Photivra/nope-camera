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

    /// Whether ``CameraScreen`` shows the camera's first start indicator: the scrolling layout
    /// then waits to draw its scrolling content (docs/design/LAUNCH-SCREEN.md, 13.2).
    @Environment(\.showsStartIndicator) private var showsStartIndicator

    /// Tells the app that a sheet opened or closed, so it can rotate.
    @Environment(\.cameraPresentsSheet) private var presentsSheet

    /// Whether the app offers Keep Screen On, for the Battery Low warning's explanation.
    @Environment(\.offersKeepScreenOn) private var offersKeepScreenOn

    /// Whether a sheet, popover or full-screen cover opened here is over the camera.
    private var presentsOwnSheet: Bool {
        showsProTools || showsFormats || showsPhotoDetails || showsAstroSettings || showsIntervalSettings
            || showsBracketSettings || showsPresets || model.comparison.isPresented || model.isViewerOpen
    }

    /// Whether night mode is on, so the sheets opened here are red too.
    private var isNightMode: Bool { settings.isNightModeOn }

    /// The space the screen has.
    @State private var size = CGSize.zero

    /// The height of the lens row and drive strip, measured with the gap between them: what Q's
    /// panel covers.
    @State private var bandsHeight: CGFloat = 0

    /// The height of the lens row's controls, measured without the row's insets.
    @State private var lensControlsHeight: CGFloat = NopeSize.minTarget

    /// The height of the drive strip, measured.
    @State private var driveStripHeight: CGFloat = NopeSize.driveRow

    /// The height of the stacked layout's status line, measured.
    @State private var statusLineHeight: CGFloat = CameraLayout.topBarHeight

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

    /// When the focus square and Lock fade (docs/design/device-feedback-1.0.md, section 5).
    @State private var focusAidLinger = FocusAidLinger()

    /// The time the focus aids were last judged at: set when their clock starts and when it runs
    /// out, so nothing runs in between.
    @State private var focusAidTime = ContinuousClock.now

    /// Whether Lock is pressed or has the keyboard's focus, which holds the fade.
    @State private var isLockHeld = false

    /// Whether VoiceOver is on: the focus aids don't fade.
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverOn

    /// Whether Switch Control is on: the focus aids don't fade.
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlOn

    /// Whether the UI tests simulate VoiceOver or Switch Control, which the Simulator can't run.
    @Environment(\.simulatesAssistiveTechnology) private var simulatesAssistiveTechnology

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

    /// Whether Bracket Settings is shown (the selected Bracket word, or the bracket's card).
    @State private var showsBracketSettings = false

    /// The self-timer delay the Timer word chooses: the last one chosen in this session, 3
    /// seconds at first (BUILD-SPEC.md, 3.5; not stored, section 6, item 8).
    @State private var timerDelay = SelfTimerDelay.threeSeconds

    /// The viewfinder's size, to turn a touch into a point in the picture.
    @State private var viewfinderSize = CGSize.zero

    /// A pinch on the viewfinder that switches lenses (issue #95).
    @State private var pinch = ViewfinderPinch()

    /// How long the lens label of a pinch stays after the fingers lift.
    @Environment(\.lensPinchLabelSeconds) private var pinchLabelSeconds

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
        context.offersKeepScreenOn = offersKeepScreenOn
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

    /// Whether a pinch on the viewfinder switches lenses now (docs/design/pinch-lens.md,
    /// section 5): the camera's rule, and nothing of the screen's own open over the picture (Q,
    /// a dial, a sheet), outside the scrolling layout.
    private var pinchSwitchesLenses: Bool {
        model.pinchSwitchesLenses(setting: settings.pinch) && layout != .scrolling && !showsQuickMenu
            && openControl == nil && !showsExposureDial && !presentsOwnSheet
    }

    /// The lens the lens buttons show selected: the lens a pinch has reached while it is shown,
    /// otherwise the lens in use.
    private var shownLensID: Lens.ID? {
        pinch.shownLens?.id ?? model.selectedLensID
    }

    /// Whether a countdown, burst, interval series or astro run is going: the shutter stops it,
    /// and the readout row and dials give the picture to the running mode's card.
    private var isSeriesRunning: Bool {
        model.drive.isBusy || model.astro.isRunning || model.manual.intervalProgress != nil || model.bracketing.isRunning
    }

    /// Whether a countdown or series runs or is paused, so leaving for Photos would interrupt
    /// it and Open Photos isn't offered (docs/design/device-feedback-1.0.md, decision 4).
    private var isSeriesUnderWay: Bool {
        isSeriesRunning || model.drive.countdown.isRunning || model.astro.progress != nil
            || model.bracketing.progress != nil || model.bracketProgress != nil
    }

    /// What the shutter's disc shows: a stop square while a series runs (not a burst the
    /// shutter holds, which ends when it comes up), the self-timer's delay while Timer is
    /// chosen, otherwise the plain disc.
    private var shutterFace: ShutterButton.Face {
        if isSeriesRunning, model.drive.burstProgress?.start != .held { return .stop }
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
        // The lens controls follow the model's one rule for a lens change (issue #96).
        .tracksLensBusy(model.lensChangeBlocker)
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
            PhotoDetailsSheet(
                photos: sessionPhotos ?? [], openPhoto: openPhotosApp.map { open in { open() } },
                lenses: model.capabilities?.lenses ?? [], session: model.sessionPhotos.photos)
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
        // Bracket Settings, as Interval Settings above: full height and page sized, so the audit
        // measures every row against the sheet (docs/design/BRACKETING.md, section 7).
        .sheet(isPresented: $showsBracketSettings) {
            BracketSheet(model: model)
                .nightModeStyle(isNightMode)
                .presentationBackground(.background)
                .presentationDetents([.large])
                .presentationSizing(.page)
        }
        .onChange(of: model.isBracketOn) { _, isOn in if !isOn { showsBracketSettings = false } }
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
        .onChange(of: presentsOwnSheet) { _, isPresenting in presentsSheet(isPresenting) }
        // Keep Screen On is used only while no sheet is over the camera (SeriesScreen).
        .preference(key: CameraCoveredPreference.self, value: presentsOwnSheet)
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
        // A delay chosen elsewhere (Siri, a preset) becomes the one Timer chooses next; a
        // bracket's start delay is the bracket's own.
        .onChange(of: model.drive.mode, initial: true) { _, mode in
            if !model.isBracketOn, case .timer(let delay) = mode { timerDelay = delay }
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
    ///
    /// When the picture and the rows fit one above the other, the spare height is shared between
    /// the gap under the lens row (``CameraLayout/rowGap(spareHeight:)``) and the shutter row,
    /// which takes the rest with the shutter centered in it (issue #116;
    /// docs/design/finish-1.0.md, 1.2: 94 points on a 402 × 874 point screen); otherwise the
    /// shutter row keeps its smallest height and the rows overlay the picture. The picture keeps
    /// its size either way.
    private var stacked: some View {
        VStack(spacing: 0) {
            statusLine
                .frame(minHeight: CameraLayout.topBarHeight)
                .padding(.horizontal, NopeSpace.m)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { statusLineHeight = $0 }
            StackedMiddle(
                width: size.width, bandsOverlayPicture: bandsOverlayPicture,
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
                // Keeps the shutter 8 points below the drive strip's targets where the row is too
                // short to center it with that gap (a 4.7-inch iPhone).
                .padding(.top, showsControls ? CameraLayout.shutterRowTopPadding(shutterRowHeight: stackedShutterRowHeight) : 0)
                .frame(minHeight: CameraLayout.shutterRowHeight, maxHeight: bandsOverlayPicture ? nil : .infinity)
                .padding(.horizontal, NopeSpace.xl)
        }
    }

    /// The height of the lens row and the drive strip without the gap between them, in points:
    /// zero in clean view, where they are hidden. Worked out from the measured controls and
    /// strip rather than from the stack that holds the gap, so the gap doesn't feed back into
    /// the spare height it comes from (docs/design/finish-1.0.md, 1.5).
    private var stackedRowsHeight: CGFloat {
        guard showsControls else { return 0 }
        let lensRow = max(lensControlsHeight + 2 * CameraLayout.lensRowInset, NopeSize.lensRow)
        return lensRow + max(driveStripHeight, NopeSize.driveRow)
    }

    /// The spare height of the stacked layout (``CameraLayout/spareHeight(in:bandsHeight:)``).
    private var stackedSpareHeight: CGFloat {
        CameraLayout.spareHeight(in: stackedMiddleSpace, bandsHeight: stackedRowsHeight)
    }

    /// The gap between the lens row and the drive strip (``CameraLayout/rowGap(spareHeight:)``):
    /// zero in clean view.
    private var stackedRowGap: CGFloat {
        showsControls ? CameraLayout.rowGap(spareHeight: stackedSpareHeight) : 0
    }

    /// The shutter row's height in the stacked layout, in points: its smallest height and the
    /// spare height the row gap leaves.
    private var stackedShutterRowHeight: CGFloat {
        CameraLayout.shutterRowHeight + max(stackedSpareHeight - stackedRowGap, 0)
    }

    /// The space between the status line and the shutter row at its smallest height, in the
    /// stacked layout.
    private var stackedMiddleSpace: CGSize {
        CGSize(width: size.width, height: max(size.height - statusLineHeight - CameraLayout.shutterRowHeight, 0))
    }

    /// Whether the lens row and drive strip overlay the bottom of the picture in the stacked
    /// layout (``CameraLayout/bandsOverlayPicture(in:bandsHeight:)``).
    private var bandsOverlayPicture: Bool {
        CameraLayout.bandsOverlayPicture(in: stackedMiddleSpace, bandsHeight: stackedRowsHeight)
    }

    /// How far the lens row and drive strip reach up over the picture in the stacked layout, in
    /// points: zero when they are below it. While the iPhone is sideways, the turned status and
    /// bottom stack run along the picture's side edges and stop this far above its lower edge, so
    /// they never run under the rows (a 4.7-inch iPhone).
    private var rowsOverPicture: CGFloat {
        guard layout == .stacked else { return 0 }
        return CameraLayout.rowsOverPicture(in: stackedMiddleSpace, bandsHeight: stackedRowsHeight)
    }

    /// The rows in a scroll view, with a shorter picture (accessibility text sizes).
    private var scrolling: some View {
        // The shutter row stays pinned below the scroll view, so the shutter is always in reach.
        VStack(spacing: 0) {
            // Q's list takes the scrolling content's place while it is open (BUILD-SPEC.md, 3.6).
            if showsControls, showsQuickMenu {
                QuickMenuList(context: context, isPresented: $showsQuickMenu, openSettings: openSettings)
                    // Q opened during a slow first start: the indicator shows the mark alone, so
                    // its words and plate never lie over Q's rows (LAUNCH-SCREEN.md, 13.2, part 3).
                    .preference(key: QuickMenuListIsOpen.self, value: true)
            } else {
                scrollingContent
                    // During the camera's first start everything that scrolls waits: laid out,
                    // not drawn, no touches, hidden from VoiceOver, so nothing is under the
                    // start indicator's plate. It fades in with the indicator's fade
                    // (docs/design/LAUNCH-SCREEN.md, 13.2, decision 9).
                    .opacity(showsStartIndicator ? 0 : 1)
                    .allowsHitTesting(!showsStartIndicator)
                    .accessibilityHidden(showsStartIndicator)
            }
            // The pinned row is drawn from the start, so the shutter and Q are in reach during a
            // slow start; its top edge tells the indicator how much room it has (13.2, decision 10).
            shutterRow(quickSize: NopeSize.scrollingRowButton)
                .padding(.horizontal, NopeSpace.m)
                .padding(.vertical, NopeSpace.xs)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: PinnedRowTop.self, value: proxy.frame(in: .global).minY)
                    }
                }
        }
    }

    /// Everything but the shutter row, scrolling.
    private var scrollingContent: some View {
        ScrollView {
            scrollingStack
                // Hidden here too, inside the scroll view: hidden only outside it, the rows were
                // still found by UI tests during the first start (LAUNCH-SCREEN.md, 13.2).
                .accessibilityHidden(showsStartIndicator)
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
    ///
    /// Q and Last Photo are 16 points from the shutter in a column at least 600 points tall, 8 in
    /// a shorter one (``CameraLayout/columnShutterGap(columnHeight:)``, issue #116).
    private var controlColumn: some View {
        VStack(spacing: CameraLayout.columnShutterGap(columnHeight: size.height)) {
            VStack(spacing: NopeSpace.xs) {
                if showsControls {
                    SettingsButton(action: openSettings)
                    ScrollView {
                        VStack(spacing: NopeSpace.xs) {
                            LensButtons(lenses: LensButtons.rear(lenses), selectedID: shownLensID, isVertical: true) { select($0) }
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
    /// stays as a margin of the same height, hidden, so the picture doesn't move. (An empty
    /// `Color.clear` there took a share of the free height: the picture moved down 41 points on
    /// a 440 × 956 point iPhone, leaving the shutter 6 points below the drive strip, and on a
    /// 4.7-inch iPhone the picture shrank to 210 × 279 points.)
    @ViewBuilder private var statusLine: some View {
        if rotation.isSideways {
            statusLineContent
                .hidden()
                .accessibilityHidden(true)
        } else {
            statusLineContent
        }
    }

    /// The status line's content: format status leading, pills trailing.
    private var statusLineContent: some View {
        HStack(spacing: NopeSpace.xs) {
            formatChip
            Spacer(minLength: 0)
            StatePillRow(pills: showsControls ? StatePills.current(context) : StatePills.cleanView(context))
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

    /// The lens row and the drive strip of the stacked layout, with the gap the spare height
    /// gives between them (``CameraLayout/rowGap(spareHeight:)``); nothing in clean view.
    ///
    /// The lens controls are always at least 8 points from the drive strip's targets
    /// (``NopeSize/targetGap``): where the spare height gives less than 2 points, as where the
    /// rows overlay the picture, the controls move up by what is missing
    /// (``CameraLayout/lensRowLift(rowGap:)``) and the rows keep their height.
    @ViewBuilder private var rows: some View {
        if showsControls {
            let lift = CameraLayout.lensRowLift(rowGap: stackedRowGap)
            VStack(spacing: 0) {
                lensRow
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lensControlsHeight = $0 }
                    // The lens row's controls keep the design's gap from the picture above and the
                    // drive strip below (CameraLayout.lensRowInset) even when they grow taller
                    // than the row, rather than reaching its edges.
                    .padding(.top, CameraLayout.lensRowInset - lift)
                    .padding(.bottom, CameraLayout.lensRowInset)
                    .frame(minHeight: NopeSize.lensRow - lift)
                    .padding(.horizontal, NopeSpace.m)
                    // The gap from the spare height, and the 2 points the lift took from above.
                    .padding(.bottom, stackedRowGap + lift)
                driveStrip(rotation.isSideways ? .symbols : .words)
                    .frame(maxWidth: .infinity, minHeight: NopeSize.driveRow)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { driveStripHeight = $0 }
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
            LensButtons(lenses: LensButtons.rear(lenses), selectedID: shownLensID) { select($0) }
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
            openAstroSettings: { showsAstroSettings = true },
            openBracketSettings: { showsBracketSettings = true })
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

    /// Whether holding the shutter takes a burst (docs/design/BURST.md, 3.1): not while a
    /// series runs, which the shutter stops in every drive mode (`CameraModel.isBurstShutter`).
    private var isBurstShutter: Bool {
        model.isBurstShutter
    }

    /// The shutter. Pressing it closes the quick menu and takes a photo (or stops a series). In
    /// burst mode it reports going down and coming up, so holding it takes a burst, and it has
    /// the action Start Burst while nothing runs.
    private var shutter: some View {
        ShutterButton(
            isEnabled: model.canPressShutter, face: shutterFace,
            onPressChange: isBurstShutter ? { isPressed in
                if isPressed { showsQuickMenu = false }
                Task { await model.send(.drive(.shutter(isPressed ? .pressed : .released))) }
            } : nil
        ) {
            showsQuickMenu = false
            Task { await model.send(.capture) }
        }
        .shutterDriveValue(model)
        .accessibilityActions {
            if isBurstShutter, !isSeriesRunning {
                Button {
                    Task { await model.send(.drive(.startBurst)) }
                } label: {
                    ModeCardText.startBurst
                }
            }
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
                showDetails: { showsPhotoDetails = true },
                isSeriesRunning: isSeriesUnderWay
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
                    .padding(
                        .bottom,
                        max(size.height / 2 + NopeSize.shutter / 2 + CameraLayout.columnShutterGap(columnHeight: size.height), NopeSpace.xs))
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
                .padding(.bottom, isColumn ? 0 : sidewaysRowsInset)
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
                        .padding(.bottom, sidewaysRowsInset)
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
                DriveModePill(word: DriveWord.selected(mode: model.drive.mode, isAstroOn: model.astro.isOn, isBracketOn: model.isBracketOn))
            }
        }
    }

    /// The bottom stack on the picture's lower edge, from the top: hints, the open dial, the
    /// running mode's card, the manual readouts (BUILD-SPEC.md, 3.1, `PictureBottomStack`). While
    /// a series runs, the readouts and dials are hidden.
    private var pictureBottomStack: some View {
        VStack(spacing: NopeSpace.xs) {
            CameraHints(model: model)
            if showsControls, !hidesReadouts, !dynamicTypeSize.isAccessibilitySize {
                if let openControl, model.manual.isEnabled {
                    ControlDial(model: model, control: openControl)
                } else if showsExposureDial {
                    AutoExposureDial(model: model) { showsExposureDial = false }
                }
            }
            modeCards
            if showsControls, model.manual.isEnabled, !hidesReadouts {
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
            openAstroSettings: { showsAstroSettings = true }, openBracketSettings: { showsBracketSettings = true })
    }

    /// Whether the readouts and dials step back for a running mode's card: a series, or a
    /// bracket being taken and saved (docs/design/BRACKETING.md, section 4).
    private var hidesReadouts: Bool {
        isSeriesRunning || model.bracketProgress != nil
    }

    /// The width text blocks wrap at while the iPhone is on its side: the picture's height,
    /// less margins, so a turned block fits across the picture.
    private var sidewaysBannerWidth: CGFloat? {
        guard rotation.isSideways else { return nil }
        let pictureHeight = min(CameraLayout.pictureHeight(forWidth: size.width), size.height) - sidewaysRowsInset
        return max(pictureHeight - 4 * NopeSpace.xs, NopeSize.minTarget * 4)
    }

    /// While the iPhone is sideways, how far above the picture's lower edge the turned status and
    /// bottom stack stop: the part of the picture under the rows (``rowsOverPicture``).
    private var sidewaysRowsInset: CGFloat {
        rotation.isSideways ? rowsOverPicture : 0
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
                dismiss: { self.bannerError = nil }, failedBracket: model.failedBracket)
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
                .transformEnvironment(\.cameraIsCovered) { $0 = $0 || presentsOwnSheet }
            if showsStatus {
                SessionStatusView(status: model.sessionStatus)
                    .uprightUnit(sidewaysWidth: sidewaysBannerWidth)
            }
            CountdownNumber(drive: model.drive)
                .uprightUnit()
            LensPinchLabel(lens: pinch.shownLens)
                // The lens row ticks for each step; in clean view, where it is hidden, the label
                // does (docs/design/pinch-lens.md, section 4).
                .sensoryFeedback(NopeHaptic.lensChanged, trigger: pinch.shownLens?.id) { _, new in
                    new != nil && model.isCleanView
                }
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
            .overlay { FocusSquareLayer(model: model, part: .square, isShown: showsFocusAids) }
            .accessibilityIgnoresInvertColors()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Viewfinder", bundle: .module, comment: "VoiceOver name of the live camera view."))
            .accessibilityValue(viewfinderDescription)
            .accessibilityActions { viewfinderActions }
            .overlay {
                FocusSquareLayer(model: model, part: .lockButton, isShown: showsFocusAids) { isLockHeld = $0 }
            }
            // The fade of the focus square and Lock: the clock starts at each tap and each new
            // target, and again when what held them ends; one wait until it runs out.
            .onChange(of: model.manual.focusTarget) { restartFocusAidClock() }
            .onChange(of: holdsFocusAids) { _, holds in
                if !holds { restartFocusAidClock() }
            }
            .task(id: focusAidLinger) {
                guard let remaining = focusAidLinger.remaining(at: .now) else { return }
                try? await Task.sleep(for: remaining)
                guard !Task.isCancelled else { return }
                focusAidTime = .now
            }
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
                    swipe: { height in Task { await model.send(.setCleanView(height > 0)) } },
                    allowsPinch: pinchSwitchesLenses,
                    pinchChanged: { pinch.change(scale: $0, model: model, isAvailable: pinchSwitchesLenses) },
                    pinchEnded: { pinch.end(model: model, labelSeconds: pinchLabelSeconds) }))
            // A pinch that can no longer switch lenses (a photo started, Q opened) stops at once.
            .onChange(of: pinchSwitchesLenses) { _, isAvailable in
                if !isAvailable { pinch.cancel() }
            }
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

    /// Whether something holds the focus square and Lock on screen: VoiceOver or Switch Control,
    /// a finger or the keyboard's focus on Lock, or the scrolling layout, where touch and hold
    /// isn't available on the picture.
    private var holdsFocusAids: Bool {
        isVoiceOverOn || isSwitchControlOn || simulatesAssistiveTechnology || isLockHeld || layout == .scrolling
    }

    /// Whether the focus square and Lock show now.
    private var showsFocusAids: Bool {
        focusAidLinger.isShown(target: model.manual.focusTarget, at: focusAidTime, isHeld: holdsFocusAids)
    }

    /// Starts the focus aids' clock again: they show for ``NopeMotion/focusAidLinger`` from now.
    private func restartFocusAidClock() {
        let now = ContinuousClock.now
        focusAidLinger.restart(at: now)
        focusAidTime = now
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
        // A tap at the same point sets the same target; the square and Lock show again anyway.
        restartFocusAidClock()
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
    /// banner until it is dismissed or the next good save. A bracket, burst or astro run that
    /// stopped on an error after saving some frames shows the newest of them as Last Photo,
    /// with their badges and Not Signed warning (`CameraModel.lastPressPhotos`).
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
            if !model.lastPressPhotos.isEmpty { sessionPhotos = model.lastPressPhotos }
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
    /// The width of the picture, in points: the screen's.
    let width: CGFloat

    /// Whether the bands overlay the bottom of the picture
    /// (``CameraLayout/bandsOverlayPicture(in:bandsHeight:)``).
    let bandsOverlayPicture: Bool

    /// The picture with its overlays.
    let picture: Picture

    /// The bottom stack (hints, dial, mode card, readouts), or nothing.
    let dial: Dial

    /// The lens row and the drive strip.
    let bands: Bands

    /// Creates the middle.
    ///
    /// - Parameters:
    ///   - width: The width of the picture, in points.
    ///   - bandsOverlayPicture: Whether the bands overlay the bottom of the picture.
    ///   - picture: The picture with its overlays.
    ///   - dial: The bottom stack, or nothing.
    ///   - bands: The lens row and the drive strip.
    init(
        width: CGFloat, bandsOverlayPicture: Bool, @ViewBuilder picture: () -> Picture,
        @ViewBuilder dial: () -> Dial, @ViewBuilder bands: () -> Bands
    ) {
        self.width = width
        self.bandsOverlayPicture = bandsOverlayPicture
        self.picture = picture()
        self.dial = dial()
        self.bands = bands()
    }

    /// The picture and the rows: over the picture, taking the height the shutter row leaves;
    /// or below it, at their own height, so the shutter row takes the rest.
    var body: some View {
        if bandsOverlayPicture {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                picture
                    .frame(width: width, height: CameraLayout.pictureHeight(forWidth: width))
                    .overlay(alignment: .bottom) { dial }
                bands
            }
            .frame(maxWidth: .infinity)
        }
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
