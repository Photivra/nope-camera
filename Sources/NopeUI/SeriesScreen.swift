import NopeCore
import SwiftUI

extension EnvironmentValues {
    /// Keeps the screen awake and dimmed during an interval series (issue #48), or `nil` when
    /// the app gives none, as in previews: then the screen is left alone.
    @Entry public var seriesScreenKeeper: SeriesScreenKeeper?
}

/// The camera screen's ties to its own lifetime: the screen stays awake and dimmed while an
/// interval series runs (`SeriesScreenKeeper`), and a countdown or burst stops when the camera
/// screen goes away (AGENTS.md, "Battery").
///
/// While the screen is dimmed, a "Brighten Screen" button covers it: any tap brightens the
/// screen while the series continues, and VoiceOver hears the change.
struct SeriesScreen: ViewModifier {
    /// The camera model.
    let model: CameraModel

    /// Whether night mode is on, so the Brighten Screen button is red on black too.
    let isNightMode: Bool

    /// The keeper the app gives, or `nil`.
    @Environment(\.seriesScreenKeeper) private var keeper

    /// Whether the app is in the foreground.
    @Environment(\.scenePhase) private var scenePhase

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - isNightMode: Whether night mode is on.
    init(model: CameraModel, isNightMode: Bool) {
        self.model = model
        self.isNightMode = isNightMode
    }

    /// Whether an interval series or the astro helper's frames run (issue #60): a run of long
    /// frames outlasts the auto-lock.
    private var isSeriesRunning: Bool {
        model.manual.intervalProgress != nil || model.astro.isRunning
    }

    /// The content with the dimming button over it.
    ///
    /// - Parameter content: The camera screen.
    func body(content: Content) -> some View {
        content
            .overlay {
                if let keeper, keeper.isDimmed {
                    BrightenScreenButton { keeper.brighten() }
                        .nightModeStyle(isNightMode)
                }
            }
            .onChange(of: isSeriesRunning, initial: true) { update() }
            .onChange(of: scenePhase) { update() }
            .onChange(of: keeper?.isDimmed) { _, isDimmed in
                guard let isDimmed else { return }
                Self.announce(
                    isDimmed
                        ? String(localized: "Screen dimmed to save battery. Tap to brighten it.", bundle: .module, comment: "Shown over the dimmed screen, and announced to VoiceOver, when interval shooting starts and the app dims the screen to save battery.")
                        : String(localized: "Screen brightness restored.", bundle: .module, comment: "Announced to VoiceOver when the app puts the screen's brightness back, after interval shooting or a tap."))
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

    /// Tells the keeper whether a series runs in the foreground.
    private func update() {
        keeper?.update(isSeriesRunning: isSeriesRunning, isInForeground: scenePhase != .background)
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
                    Text("Screen dimmed to save battery. Tap to brighten it.", bundle: .module, comment: "Shown over the dimmed screen, and announced to VoiceOver, when interval shooting starts and the app dims the screen to save battery.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Brighten Screen", bundle: .module, comment: "VoiceOver and Voice Control name of the button that covers the dimmed screen during interval shooting; it restores the brightness.")
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
            .accessibilityLabel(Text("Brighten Screen", bundle: .module, comment: "VoiceOver and Voice Control name of the button that covers the dimmed screen during interval shooting; it restores the brightness."))
            .accessibilityValue(Text("Screen dimmed to save battery. Tap to brighten it.", bundle: .module, comment: "Shown over the dimmed screen, and announced to VoiceOver, when interval shooting starts and the app dims the screen to save battery."))
            .accessibilityAddTraits(.isButton)
        }
    }
}

extension View {
    /// Keeps the screen awake and dimmed during an interval series, and stops a countdown or
    /// burst when the camera screen goes away (``SeriesScreen``).
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - isNightMode: Whether night mode is on.
    func seriesScreen(_ model: CameraModel, isNightMode: Bool) -> some View {
        modifier(SeriesScreen(model: model, isNightMode: isNightMode))
    }
}
