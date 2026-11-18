import NopeCore
import SwiftUI

/// The camera screen: renders a `CameraModel` and sends it intents.
///
/// The screen holds no rules: it shows the model's state and sends `CameraIntent` values
/// (AGENTS.md, "One direction of flow"). The camera and its own sheets use the dark appearance,
/// because a camera is used in every light and a dark frame doesn't change how a scene looks;
/// Settings, first run and the other screens that aren't the camera follow the system's light or
/// dark setting, read from ``SwiftUICore/EnvironmentValues/systemColorScheme``
/// (`ScreenAppearance`). Night mode is red on black on every screen.
///
/// The live viewfinder comes from the app target: `NopeUI` can't show camera video, so the app
/// passes a closure that turns the model's `CameraPreviewSource` into a view (for example one
/// backed by `AVCaptureVideoPreviewLayer`).
///
/// Settings (``SettingsScreen``, a popover in a regular-width window, a sheet otherwise) is
/// reachable in every state, so settings and the Honesty screen are reachable before the camera
/// is allowed: from a Settings button above the screens shown before the camera is ready, from
/// the column layout's Settings button, and from Q in the stacked and scrolling layouts. Before
/// camera access is asked, ``FirstRunView`` says what the app does, then asks.
///
/// The app target can set ``SwiftUICore/EnvironmentValues/openAppSettings`` (Open Settings buttons),
/// ``SwiftUICore/EnvironmentValues/cameraUprightRotation`` (upright icons on a turned iPhone),
/// ``SwiftUICore/EnvironmentValues/cameraPresentsSheet`` (rotation while a sheet is open),
/// ``SwiftUICore/EnvironmentValues/systemColorScheme`` (the appearance Settings follows) and
/// ``SwiftUICore/EnvironmentValues/windowAppearance`` (the window's appearance).
///
/// ```swift
/// CameraScreen(model: model, settings: settings) { source in
///     MyPreviewView(source: source)
/// }
/// ```
public struct CameraScreen<Viewfinder: View>: View {
    /// The model the screen renders.
    private let model: CameraModel

    /// The person's settings, shown and changed in the settings sheet.
    private let settings: NopeSettings

    /// The saved settings presets (issue #72), or `nil` to offer none.
    private let presets: SettingsPresets?

    /// Whether the settings sheet is open.
    @State private var showsSettings = false

    /// Where Settings is, kept outside its presentation so it stays on its page when the
    /// presentation changes (night mode on iPad, a fold on the iPhone Duo).
    @State private var settingsNavigation = SettingsNavigation()

    /// Makes the live viewfinder for the model's preview source.
    private let viewfinder: (any CameraPreviewSource) -> Viewfinder

    /// Creates the camera screen.
    ///
    /// - Parameters:
    ///   - model: The model to render. The screen sends `CameraIntent.start` when it appears
    ///     and runs `CameraModel.observeEvents()` while it is visible.
    ///   - settings: The person's settings, opened from the Settings button.
    ///   - presets: The saved settings presets, shown in Settings and the quick menu, or
    ///     `nil` to offer none (the Lock Screen camera, which can't read them).
    ///   - viewfinder: Makes the live viewfinder from the model's preview source.
    public init(
        model: CameraModel, settings: NopeSettings, presets: SettingsPresets? = nil,
        @ViewBuilder viewfinder: @escaping (any CameraPreviewSource) -> Viewfinder
    ) {
        self.model = model
        self.settings = settings
        self.presets = presets
        self.viewfinder = viewfinder
    }

    /// Opens the app's page in the Settings app, or `nil` when the app can't.
    @Environment(\.openAppSettings) private var openAppSettings

    /// Tells the app that a sheet opened or closed, so it can rotate.
    @Environment(\.cameraPresentsSheet) private var presentsSheet

    /// Whether the app is in the foreground, to turn the light off when it leaves.
    @Environment(\.scenePhase) private var scenePhase

    /// What assistants did since the app opened; its Open Assistant Access request opens
    /// Settings at that page (issue #82).
    @Environment(\.assistantSession) private var assistantSession

    /// The screen's content for the current state.
    public var body: some View {
        // Outside the ready camera, the Settings button sits above the content, not over it, so
        // scrolling content at large text sizes never passes under it. The ready camera opens
        // Settings from Q, or from its control column.
        VStack(spacing: 0) {
            if showsSettingsButton {
                HStack {
                    Spacer()
                    SettingsButton { showsSettings = true }
                }
                .padding(.horizontal, NopeSpace.m)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The camera's first start: the launch screen's mark at the same point until the picture
        // arrives, then a fade (docs/design/LAUNCH-SCREEN.md, 6.3). Inside night mode's style, so
        // it is red from the first frame.
        .overlay {
            if model.isFirstStart {
                StartIndicator(showsWords: isReady)
                    .transition(.opacity)
            }
        }
        .animation(NopeMotion.fade, value: model.isFirstStart)
        .environment(\.showsStartIndicator, model.isFirstStart)
        .nightModeStyle(settings.isNightModeOn)
        // Nothing turns upright in a window that rotates with the device (iPad, or the inner
        // display of a foldable iPhone).
        .modifier(WindowUprightRotation())
        // The live viewfinder is always drawn here, behind the interface, in the frame the ready
        // camera reserves for it (``ViewfinderFrame``), so night mode's red multiply reaches only
        // nope.'s own interface. It is the same view in every mode: on a device a new viewfinder
        // is a new preview layer, which attaches to the running capture session on the main
        // thread and made switching night mode freeze the camera. Red Viewfinder tints it here.
        // The focus magnifier enlarges it here, as it enlarges the picture and focus peaking there.
        // In the scrolling layout it is clipped to the scroll view, so it never runs into the
        // pinned shutter row or past the top of the screen.
        .backgroundPreferenceValue(ViewfinderFrame.self) { anchors in
            if let anchor = anchors.frame, let source = model.previewSource {
                GeometryReader { proxy in
                    let frame = proxy[anchor]
                    let visible = ViewfinderAnchors.visibleFrame(of: frame, in: anchors.clip.map { proxy[$0] })
                    viewfinder(source)
                        .frame(width: frame.width, height: frame.height)
                        .focusMagnified(model)
                        .clipped()
                        .colorMultiply(tintsViewfinder ? NightStyle.red : .white)
                        .offset(x: frame.minX, y: frame.minY)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .mask(alignment: .topLeading) {
                            Rectangle()
                                .frame(width: visible.width, height: visible.height)
                                .offset(x: visible.minX, y: visible.minY)
                        }
                }
                // Left to right in every language, placement included: the picture is laid out
                // left to right (CameraReadyView), and its frame is read here from the left
                // edge. With only the viewfinder left to right, a right-to-left layout offset it
                // from the right edge instead, so beside a control column (iPad, wide windows)
                // it was drawn a column's width from the picture's frame, under the column.
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityIgnoresInvertColors()
                .accessibilityHidden(true)
            }
        }
        // Black whenever the camera's appearance applies, without waiting for the window's dark
        // style, so the first frame is the launch screen's black in the light appearance too
        // (docs/design/LAUNCH-SCREEN.md, 6.1). The screens that follow the system keep its
        // background.
        .background(usesLaunchBackground ? AnyShapeStyle(NopeColor.launchBackground) : AnyShapeStyle(.background))
        // A popover on iPad (a sheet in night mode, see AdaptivePresentation); a sheet on iPhone.
        // Night mode turned on in the popover moves Settings to the sheet at once, on the same page.
        .adaptivePresentation(isPresented: $showsSettings, prefersSheet: settings.isNightModeOn, switchesToSheet: true) {
            SettingsScreen(
                settings: settings, deviceSupportsBayerRAW: model.capabilities?.supportsBayerRAW ?? true,
                deviceHasFrontCamera: model.capabilities?.hasFrontCamera ?? true, location: model.location,
                lenses: model.capabilities?.lenses ?? [], presets: presets, camera: model, navigation: settingsNavigation)
                .nightModeStyle(settings.isNightModeOn)
                // The system's light or dark setting, not the camera's dark appearance.
                .screenAppearance(.system, isNightMode: settings.isNightModeOn)
                .frame(idealWidth: 480, idealHeight: 720)
                // Opaque: a translucent popover lets the camera through and fails the contrast
                // audit.
                .presentationBackground(.background)
        }
        .onChange(of: showsSettings) { _, isPresenting in
            presentsSheet(isPresenting)
            // Settings opens at its list again next time.
            if !isPresenting { settingsNavigation.reset() }
        }
        // Opens Settings at a page or row (the Photo Format sheet's All Photo Settings and Look).
        .environment(
            \.openSettingsAt,
            OpenSettingsAction { id in
                settingsNavigation.open(id)
                showsSettings = true
            })
        // Open Assistant Access, from Shortcuts or the off answer, opens Settings at the page.
        .onChange(of: assistantSession?.opensSettingsPage, initial: true) { _, opens in
            guard opens == true, let assistantSession else { return }
            assistantSession.settingsPageOpened()
            settingsNavigation.open(.assistantAccess)
            showsSettings = true
        }
        // The light turns off when nope. leaves the foreground (AGENTS.md, "Battery"). The model
        // hears of leaving and coming back: the self-timer is cancelled, and astro frames pause
        // and continue (issue #64).
        .onChange(of: scenePhase) { _, phase in
            Task {
                if phase == .background { await model.send(.light(.setTorch(false))) }
                await model.send(.setInForeground(phase != .background))
            }
        }
        // Dark for the camera; first run, camera access declined and no camera follow the system.
        .windowAppearance(ScreenAppearance.of(model.state), isNightMode: settings.isNightModeOn)
        // Night mode: the home indicator, a white system bar, fades away until the screen is
        // touched.
        .persistentSystemOverlays(settings.isNightModeOn ? .hidden : .automatic)
        // After a relaunch during Astro (off at every launch), night mode stays as it was, so the
        // screen opens red in the dark; it becomes the person's (owner decision, 2026-11-18).
        .task { model.forgetNightModeFromAstroAtLaunch(settings: settings) }
        .task { await model.send(.start) }
        .task { await model.observeEvents() }
        .task { await model.manual.observeReadings() }
        .task { await model.live.observeAnalyses() }
        .task { await model.live.observeStats() }
        // An interval series runs only while the camera screen is shown (AGENTS.md, "Battery").
        .onDisappear { Task { await model.send(.manual(.stopInterval)) } }
        // The screen stays awake and dimmed during a series; a countdown or burst stops here.
        .seriesScreen(model, isNightMode: settings.isNightModeOn)
    }

    /// Whether the viewfinder is drawn in night mode's red: night mode with Red Viewfinder on.
    private var tintsViewfinder: Bool {
        settings.isNightModeOn && settings.tintsViewfinderInNightMode
    }

    /// Whether the camera is ready, so Settings opens from the camera layout.
    private var isReady: Bool {
        if case .ready = model.state { true } else { false }
    }

    /// Whether the Settings button sits above the content: on first run, camera access declined
    /// and no camera. Not while the camera state isn't known yet, a frame or two that is the
    /// launch screen again (docs/design/LAUNCH-SCREEN.md, 6.1), nor on the ready camera, which
    /// opens Settings from its own layout.
    private var showsSettingsButton: Bool {
        switch model.state {
        case .starting, .ready: false
        case .needsPermission, .permissionDenied, .unavailable: true
        }
    }

    /// Whether the screen's background is the launch screen's black: whenever the camera's
    /// appearance applies, or night mode is on.
    private var usesLaunchBackground: Bool {
        ScreenAppearance.of(model.state) == .camera || settings.isNightModeOn
    }

    /// The view for the model's current state.
    @ViewBuilder private var content: some View {
        switch model.state {
        case .starting:
            // Only the background: the state lasts as long as reading the camera permission, and
            // a spinner would be drawn and gone within a frame or two. ``StartIndicator`` is shown
            // over it, with the one VoiceOver element, "Starting the camera…".
            Color.clear
                .accessibilityHidden(true)
        case .needsPermission:
            FirstRunView { Task { await model.send(.requestPermission) } }
        case .permissionDenied:
            StatusMessageView(
                title: Text("Camera Access Is Off", bundle: .module, comment: "Title when camera access was declined."),
                systemImage: "camera.badge.ellipsis",
                message: Text(
                    "To take photos, turn on camera access for nope. in the Settings app.",
                    bundle: .module,
                    comment: "Explains how to allow camera access after it was declined. Keep \"nope.\" unchanged: it is the app's name."
                )
            ) {
                if let openAppSettings {
                    Button {
                        openAppSettings()
                    } label: {
                        Text("Open Settings", bundle: .module, comment: "Button that opens nope.'s page in the system Settings app, where camera or photo library access can be allowed. Keep \"nope.\" unchanged.")
                    }
                }
            }
        case .unavailable:
            StatusMessageView(
                title: Text("No Camera Available", bundle: .module, comment: "Title when the device has no usable camera."),
                systemImage: "camera",
                message: Text(
                    "This device has no camera that nope. can use.",
                    bundle: .module,
                    comment: "Explains that the device has no usable camera. Keep \"nope.\" unchanged: it is the app's name."
                )
            )
        case .ready(let capabilities):
            // The ready camera leaves the picture's frame clear; the viewfinder is drawn behind
            // it (see body).
            CameraReadyView(
                model: model, settings: settings, lenses: capabilities.lenses, openSettings: { showsSettings = true },
                presets: presets)
            // Settings over the camera holds the level's tap back.
            .environment(\.cameraIsCovered, showsSettings)
        }
    }
}

extension CameraScreen where Viewfinder == Color {
    /// Creates the camera screen with a plain black viewfinder, for tests and previews.
    ///
    /// - Parameters:
    ///   - model: The model to render.
    ///   - settings: The person's settings.
    public init(model: CameraModel, settings: NopeSettings) {
        self.init(model: model, settings: settings) { _ in Color.black }
    }
}
