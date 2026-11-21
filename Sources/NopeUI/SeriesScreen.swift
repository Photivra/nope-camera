import NopeCore
import SwiftUI

extension EnvironmentValues {
    /// Keeps the screen awake and dimmed during an interval series (issue #48) and for Keep
    /// Screen On (issue #97), or `nil` when the app gives none, as in the Lock Screen camera and
    /// previews: then the screen is left alone.
    @Entry public var seriesScreenKeeper: SeriesScreenKeeper?

    /// Whether Settings offers Keep Screen On (issue #97): `true` where the app gives a
    /// `SeriesScreenKeeper`. `false` by default, as in the Lock Screen camera, which leaves the
    /// screen to iOS, and in previews.
    @Entry public var offersKeepScreenOn = false
}

/// Whether a sheet, popover or full-screen cover opened by the ready camera is over it, passed up
/// to ``SeriesScreen``: Keep Screen On is used only while the camera screen is in front.
struct CameraCoveredPreference: PreferenceKey {
    /// No cover.
    static let defaultValue = false

    /// Creates the key. It holds no state.
    init() {}

    /// Any cover.
    ///
    /// - Parameters:
    ///   - value: The value so far.
    ///   - nextValue: The next view's value.
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// The camera screen's ties to its own lifetime: the screen stays awake and dimmed while an
/// interval series runs, and while Keep Screen On is used (`SeriesScreenKeeper`), and a
/// countdown or burst stops when the camera screen goes away (AGENTS.md, "Battery").
///
/// While the screen is dimmed, a "Brighten Screen" button covers it: any tap brightens the
/// screen and does nothing else, and VoiceOver hears the change. The modifier tells the keeper
/// the conditions of Keep Screen On (`docs/design/keep-screen-on.md`, section 3) and each change
/// the person makes or photo taken (`CameraModel.activityCount`); the app reports touches and
/// VoiceOver focus changes itself.
struct SeriesScreen: ViewModifier {
    /// The camera model.
    let model: CameraModel

    /// The person's settings: night mode, so the Brighten Screen button is red on black too,
    /// and Keep Screen On.
    let settings: NopeSettings

    /// Whether the camera screen opened Settings over the camera.
    let showsSettings: Bool

    /// The keeper the app gives, or `nil`.
    @Environment(\.seriesScreenKeeper) private var keeper

    /// Whether the app is in the foreground, and active.
    @Environment(\.scenePhase) private var scenePhase

    /// Whether the ready camera has a sheet of its own open.
    @State private var isCoveredByCamera = false

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - settings: The person's settings.
    ///   - showsSettings: Whether Settings is open over the camera.
    init(model: CameraModel, settings: NopeSettings, showsSettings: Bool) {
        self.model = model
        self.settings = settings
        self.showsSettings = showsSettings
    }

    /// Whether an interval series, the astro helper's frames (issue #60) or a focus bracket run
    /// (`CameraModel.keepsScreenForSeries`): a run of long or many frames outlasts the auto-lock.
    private var isSeriesRunning: Bool {
        model.keepsScreenForSeries
    }

    /// Keep Screen On's conditions now.
    private var keepScreenOn: KeepScreenOnConditions {
        KeepScreenOnConditions(
            isSwitchOn: settings.keepsScreenOn, isActive: scenePhase == .active,
            isCameraInFront: !showsSettings && !isCoveredByCamera, isCameraRunning: model.sessionStatus == .running,
            isBatteryLow: model.deviceStatus.batteryWarning != nil,
            isLowPowerMode: model.deviceStatus.battery?.isLowPowerMode == true, dimAfter: settings.dimAfter,
            heatLevel: model.heatLevel)
    }

    /// The content with the dimming button over it.
    ///
    /// - Parameter content: The camera screen.
    func body(content: Content) -> some View {
        content
            .onPreferenceChange(CameraCoveredPreference.self) { isCoveredByCamera = $0 }
            .overlay {
                if let keeper, keeper.isDimmed {
                    BrightenScreenButton { keeper.brighten() }
                        .nightModeStyle(settings.isNightModeOn)
                        .transition(.opacity)
                }
            }
            .animation(NopeMotion.fade, value: keeper?.isDimmed)
            .onChange(of: isSeriesRunning, initial: true) { update() }
            .onChange(of: scenePhase) { update() }
            .onChange(of: keepScreenOn) { update() }
            .onChange(of: model.activityCount) { keeper?.noteActivity() }
            .onChange(of: keeper?.isDimmed) { _, isDimmed in
                guard let isDimmed else { return }
                Self.announce(
                    isDimmed
                        ? String(localized: "Screen dimmed to save battery. Tap to brighten it.", bundle: .module, comment: "Shown over the dimmed screen, and announced to VoiceOver, when interval shooting starts, or after a while without a touch with Keep Screen On, and the app dims the screen to save battery.")
                        : String(localized: "Screen brightness restored.", bundle: .module, comment: "Announced to VoiceOver when the app puts the screen's brightness back, after interval shooting, Keep Screen On's dimming or a tap."))
            }
            .onDisappear {
                keeper?.update(isSeriesRunning: false, isInForeground: false)
                Task {
                    await model.send(.drive(.cancelTimer))
                    await model.send(.drive(.stopBurst))
                    await model.send(.astro(.stop))
                }
            }
    }

    /// Tells the keeper whether a series runs in the foreground, and Keep Screen On's
    /// conditions.
    private func update() {
        keeper?.update(
            isSeriesRunning: isSeriesRunning, isInForeground: scenePhase != .background, keepScreenOn: keepScreenOn)
    }

    /// Posts a VoiceOver announcement.
    ///
    /// - Parameter message: What to say.
    private static func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}

/// Covers the dimmed screen: a tap anywhere brightens it, and a visible Brighten Screen button in
/// the middle says what happened and does the same, so the dimming never depends on a gesture.
struct BrightenScreenButton: View {
    /// Brightens the screen.
    let action: () -> Void

    /// Creates the cover.
    ///
    /// - Parameter action: Brightens the screen.
    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// The tap area and the button.
    var body: some View {
        ZStack {
            // Nearly clear, so the series' progress stays visible, but hit-testable. The button
            // below is the accessible way to do the same.
            Color.black.opacity(0.01)
                .contentShape(.rect)
                .onTapGesture(perform: action)
                .accessibilityHidden(true)
                .ignoresSafeArea()
            Button(action: action) {
                // The sentence, as the design shows it (docs/design/drive.html, "Interval, screen
                // dimmed"), and the button's name under it, so the name Voice Control and
                // VoiceOver use is on screen too (WCAG 2.5.3, label in name).
                VStack(spacing: NopeSpace.xxs) {
                    Text("Screen dimmed to save battery. Tap to brighten it.", bundle: .module, comment: "Shown over the dimmed screen, and announced to VoiceOver, when interval shooting starts, or after a while without a touch with Keep Screen On, and the app dims the screen to save battery.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Brighten Screen", bundle: .module, comment: "VoiceOver and Voice Control name of the button that covers the dimmed screen during interval shooting or with Keep Screen On; it restores the brightness.")
                        .font(NopeFont.status)
                }
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(NopeColor.label)
                .padding(NopeSpace.m)
                .frame(minHeight: NopeSize.minTarget)
                .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.large))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(NopeSpace.m)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Brighten Screen", bundle: .module, comment: "VoiceOver and Voice Control name of the button that covers the dimmed screen during interval shooting or with Keep Screen On; it restores the brightness."))
            .accessibilityValue(Text("Screen dimmed to save battery. Tap to brighten it.", bundle: .module, comment: "Shown over the dimmed screen, and announced to VoiceOver, when interval shooting starts, or after a while without a touch with Keep Screen On, and the app dims the screen to save battery."))
            .accessibilityAddTraits(.isButton)
        }
    }
}

extension View {
    /// Keeps the screen awake and dimmed during an interval series and for Keep Screen On, and
    /// stops a countdown or burst when the camera screen goes away (``SeriesScreen``).
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - settings: The person's settings.
    ///   - showsSettings: Whether Settings is open over the camera.
    func seriesScreen(_ model: CameraModel, settings: NopeSettings, showsSettings: Bool) -> some View {
        modifier(SeriesScreen(model: model, settings: settings, showsSettings: showsSettings))
    }
}
