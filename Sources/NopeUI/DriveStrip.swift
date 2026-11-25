import NopeCore
import SwiftUI

/// One word of the drive strip: what the shutter does (docs/design/BUILD-SPEC.md, 3.5).
///
/// Four words are drive modes of `NopeCore` (`DriveMode`); Bracket is the exposure bracket
/// (`ManualControlsModel.bracket`) with the mode Single, or the self-timer for its start delay
/// (docs/design/BRACKETING.md, section 3); Astro is the astro helper, which has its own shutter.
/// The words are an interface's names for existing intents; they hold no rules.
enum DriveWord: CaseIterable, Identifiable, Hashable, Sendable {
    /// One photo per press: `DriveMode/single`.
    case single

    /// The self-timer: `DriveMode/timer(_:)` with the last delay chosen.
    case timer

    /// A rapid run of separate photos: `DriveMode/burst`.
    case burst

    /// An exposure bracket: `ManualControlsModel.bracket`, with Single or the self-timer.
    case bracket

    /// An interval series: `DriveMode/interval`.
    case interval

    /// The astro helper (issue #60).
    case astro

    /// The word itself, so the cases can be listed with `ForEach`.
    var id: Self { self }

    /// The word that shows what the shutter does now.
    ///
    /// - Parameters:
    ///   - mode: The drive mode.
    ///   - isAstroOn: Whether the astro helper is on; it takes over the shutter whatever the
    ///     mode.
    ///   - isBracketOn: Whether a bracket is on (`CameraModel.isBracketOn`); Single and Timer
    ///     are then the bracket's start delay, so Bracket is selected.
    /// - Returns: The selected word.
    static func selected(mode: DriveMode, isAstroOn: Bool, isBracketOn: Bool = false) -> DriveWord {
        if isAstroOn { return .astro }
        switch mode {
        case .single: return isBracketOn ? .bracket : .single
        case .timer: return isBracketOn ? .bracket : .timer
        case .burst: return .burst
        case .interval: return .interval
        }
    }

    /// The words the strip offers: the four drive modes, Bracket where the lens can take a
    /// bracket or one is on, and Astro where the astro helper can be used or is on.
    ///
    /// - Parameters:
    ///   - offersAstro: Whether Astro is offered.
    ///   - offersBracket: Whether Bracket is offered.
    /// - Returns: The words, in display order.
    static func offered(offersAstro: Bool, offersBracket: Bool = false) -> [DriveWord] {
        allCases.filter { word in
            switch word {
            case .astro: offersAstro
            case .bracket: offersBracket
            case .single, .timer, .burst, .interval: true
            }
        }
    }

    /// The drive mode the word chooses, or `nil` for Bracket and Astro, which are turned on with
    /// their own intents.
    ///
    /// - Parameter timerDelay: The self-timer's delay for ``timer``.
    /// - Returns: The mode, or `nil`.
    func mode(timerDelay: SelfTimerDelay) -> DriveMode? {
        switch self {
        case .single: .single
        case .timer: .timer(timerDelay)
        case .burst: .burst
        case .interval: .interval
        case .bracket, .astro: nil
        }
    }

    /// The SF Symbol shown in place of the word while the iPhone is held sideways.
    var systemImage: String {
        switch self {
        case .single: "square"
        case .timer: "clock"
        case .burst: "square.stack.3d.down.right"
        case .bracket: "square.3.layers.3d"
        case .interval: "timer"
        case .astro: "moon.stars"
        }
    }

    /// The word, as the strip shows it.
    @MainActor var title: Text {
        switch self {
        case .single:
            Text(String(localized: "Drive strip: Single", defaultValue: "Single", bundle: .module, comment: "Drive mode word in the strip above the shutter: each press takes one photo. A short word; the strip holds five."))
        case .timer:
            Text(String(localized: "Drive strip: Timer", defaultValue: "Timer", bundle: .module, comment: "Drive mode word in the strip above the shutter: a self-timer of 3 or 10 seconds. A short word; the strip holds five."))
        case .burst:
            Text("Burst", bundle: .module, comment: "Drive menu option on the camera: holding the shutter takes a rapid run of separate photos.")
        case .bracket:
            Text(verbatim: BracketText.word)
        case .interval:
            Text(String(localized: "Drive strip: Interval", defaultValue: "Interval", bundle: .module, comment: "Drive mode word in the strip above the shutter: a series of photos at a fixed interval. A short word; the strip holds five."))
        case .astro:
            AstroText.title
        }
    }

    /// The VoiceOver hint of the selected Interval or Astro word: choosing it again opens its
    /// settings.
    @MainActor static var opensSettingsHint: Text {
        Text("Opens its settings.", bundle: .module, comment: "VoiceOver hint on the selected Interval or Astro word of the drive strip above the shutter: activating the word again opens that mode's settings.")
    }

    /// The word as a string, for the VoiceOver announcement of a new mode.
    @MainActor var string: String {
        switch self {
        case .single:
            String(localized: "Drive strip: Single", defaultValue: "Single", bundle: .module, comment: "Drive mode word in the strip above the shutter: each press takes one photo. A short word; the strip holds five.")
        case .timer:
            String(localized: "Drive strip: Timer", defaultValue: "Timer", bundle: .module, comment: "Drive mode word in the strip above the shutter: a self-timer of 3 or 10 seconds. A short word; the strip holds five.")
        case .burst:
            String(localized: "Burst", bundle: .module, comment: "Drive menu option on the camera: holding the shutter takes a rapid run of separate photos.")
        case .bracket:
            BracketText.word
        case .interval:
            String(localized: "Drive strip: Interval", defaultValue: "Interval", bundle: .module, comment: "Drive mode word in the strip above the shutter: a series of photos at a fixed interval. A short word; the strip holds five.")
        case .astro:
            String(localized: "Astro", bundle: .module, comment: "Quick control, pill and its Voice Control name on the camera: the helper for night sky photos, which takes a series of single RAW frames for stacking in other software.")
        }
    }
}

/// The drive strip above the shutter: Single, Timer, Burst, Bracket, Interval and Astro, exactly
/// one selected (docs/design/BUILD-SPEC.md, 3.5). It replaces the Drive menu of the quick-controls
/// tray and the Astro switch, and with them the Drive and Astro pills.
///
/// - Choosing a word sets that mode; choosing another word while Astro is on turns Astro off
///   first, and while Bracket is on turns the bracket off first. Choosing Interval only selects
///   it: the shutter starts the series. Choosing Bracket turns on the session's last bracket
///   with its start delay; it doesn't open Bracket Settings by itself.
/// - Tapping the selected word again: Timer opens a menu of 3 and 10 seconds; Burst a menu of
///   its speeds, Fast and Slow (docs/design/BURST.md, 3.2), where the lens offers both;
///   Bracket, Interval and Astro open their settings; Single does nothing.
/// - While a countdown, burst, interval series or astro run is going, the other words are
///   disabled.
/// - It never truncates a word: the words get less padding, then scroll sideways, keeping the
///   selected word in view.
///
/// A selection haptic confirms each change, and VoiceOver announces the new mode.
struct DriveStrip: View {
    /// How the strip is drawn for its place on the camera.
    enum Presentation: Equatable {
        /// Words on the black row above the shutter (stacked layout).
        case words

        /// Words in a capsule with the backing, on the lower edge of the picture (column layout).
        case backedWords

        /// Symbols only, each turned upright: the stacked layout with the iPhone held sideways,
        /// where the selected mode's name is a pill on the picture (``DriveModePill``).
        case symbols

        /// One full-width row per word: the scrolling layout at accessibility text sizes.
        case rows
    }

    /// The camera model.
    let model: CameraModel

    /// The person's settings: choosing Astro turns night mode on, as the astro switch did.
    let settings: NopeSettings

    /// How the strip is drawn.
    let presentation: Presentation

    /// The self-timer delay Timer chooses: the last one chosen in this session, 3 seconds at
    /// first. It isn't stored (BUILD-SPEC.md, section 6, item 8).
    @Binding var timerDelay: SelfTimerDelay

    /// Opens the interval settings.
    let openIntervalSettings: () -> Void

    /// Opens the astro settings.
    let openAstroSettings: () -> Void

    /// Opens Bracket Settings.
    let openBracketSettings: () -> Void

    /// Creates the strip.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - settings: The person's settings.
    ///   - presentation: How the strip is drawn.
    ///   - timerDelay: The self-timer delay Timer chooses, kept for the session by the camera.
    ///   - openIntervalSettings: Opens the interval settings.
    ///   - openAstroSettings: Opens the astro settings.
    ///   - openBracketSettings: Opens Bracket Settings.
    init(
        model: CameraModel, settings: NopeSettings, presentation: Presentation, timerDelay: Binding<SelfTimerDelay>,
        openIntervalSettings: @escaping () -> Void, openAstroSettings: @escaping () -> Void,
        openBracketSettings: @escaping () -> Void = {}
    ) {
        self.model = model
        self.settings = settings
        self.presentation = presentation
        self._timerDelay = timerDelay
        self.openIntervalSettings = openIntervalSettings
        self.openAstroSettings = openAstroSettings
        self.openBracketSettings = openBracketSettings
    }

    /// The selected word.
    private var selected: DriveWord {
        DriveWord.selected(mode: model.drive.mode, isAstroOn: model.astro.isOn, isBracketOn: model.isBracketOn)
    }

    /// The words offered.
    private var words: [DriveWord] {
        DriveWord.offered(
            offersAstro: model.canUseAstro || model.astro.isOn,
            offersBracket: model.offersBracket)
    }

    /// Whether a countdown, burst, bracket, interval series or astro run is going, so only the
    /// selected word stays enabled.
    private var isBusy: Bool {
        model.drive.isBusy || model.astro.isRunning || model.manual.intervalProgress != nil || model.bracketProgress != nil
            || model.bracketing.isRunning
    }

    /// The strip.
    var body: some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Drive", bundle: .module, comment: "Quick control on the camera: a menu that chooses what the shutter does: one photo, a self-timer, or a burst."))
            .sensoryFeedback(NopeHaptic.driveModeChanged, trigger: selected)
            .onChange(of: selected) { _, word in
                AccessibilityNotification.Announcement(word.string).post()
            }
    }

    /// The words in the presentation's arrangement.
    @ViewBuilder private var content: some View {
        switch presentation {
        case .words:
            fittedWords
        case .backedWords:
            fittedWords
                .padding(.horizontal, NopeSpace.xxs)
                .nopeBackground(.backing, in: Capsule())
        case .symbols:
            HStack(spacing: NopeSpace.xxs) {
                ForEach(words) { word in control(for: word, padding: NopeSpace.xs) }
            }
        case .rows:
            // 12 points apart, as every row of the scrolling layout (docs/design/screens/ax-camera).
            VStack(spacing: NopeSpace.s) {
                ForEach(words) { word in control(for: word, padding: NopeSpace.s) }
            }
        }
    }

    /// The words at their roomiest padding that fits, then tighter, then scrolling sideways
    /// with the selected word kept in view.
    private var fittedWords: some View {
        ViewThatFits(in: .horizontal) {
            wordRow(padding: NopeSpace.s)
            wordRow(padding: NopeSpace.xs)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    wordRow(padding: NopeSpace.xs)
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(selected, anchor: .center) }
                .onChange(of: selected) { _, word in proxy.scrollTo(word, anchor: .center) }
            }
        }
    }

    /// The words in one row.
    ///
    /// - Parameter padding: The space on each side of a word, inside its capsule.
    private func wordRow(padding: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(words) { word in
                control(for: word, padding: padding)
                    .id(word)
            }
        }
    }

    /// One word's control: a button, or for the selected Timer, the menu of delays, and for the
    /// selected Burst, the menu of speeds.
    ///
    /// - Parameters:
    ///   - word: The word.
    ///   - padding: The space on each side of the word, inside its capsule.
    @ViewBuilder private func control(for word: DriveWord, padding: CGFloat) -> some View {
        let isSelected = word == selected
        Group {
            if word == .timer, isSelected {
                Menu {
                    Picker(selection: Binding(get: { timerDelay }, set: { chooseTimerDelay($0) })) {
                        ForEach(SelfTimerDelay.allCases, id: \.self) { delay in
                            Text(verbatim: DriveText.spokenSeconds(delay.seconds)).tag(delay)
                        }
                    } label: {
                        word.title
                    }
                } label: {
                    label(for: word)
                }
                .accessibilityValue(Text(verbatim: DriveText.spokenSeconds(timerDelay.seconds)))
            } else if word == .burst, isSelected, model.burstSpeeds.count > 1 {
                Menu {
                    Section {
                        ForEach(model.burstSpeeds, id: \.self) { speed in
                            // A toggle shows the check on the speed in use; a menu row's second
                            // text is its subtitle.
                            Toggle(isOn: Binding(get: { model.burstSpeed == speed }, set: { if $0 { chooseBurstSpeed(speed) } })) {
                                BurstSpeedText.name(speed)
                                BurstSpeedText.detail(speed)
                            }
                        }
                    } header: {
                        BurstSpeedText.menuTitle
                    }
                } label: {
                    label(for: word)
                }
                .accessibilityValue(BurstSpeedText.name(model.burstSpeed))
            } else {
                Button {
                    choose(word)
                } label: {
                    label(for: word)
                }
            }
        }
        .modifier(DriveWordStyling(isSelected: isSelected, padding: padding, isRow: presentation == .rows))
        .disabled(isBusy && !isSelected)
        .accessibilityLabel(word.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // The selected Interval or Astro opens its settings on a second tap, which nothing on
        // the word shows (docs/design/ACCESSIBILITY.md, the drive strip).
        .accessibilityHint(hint(for: word, isSelected: isSelected))
        .accessibilityShowsLargeContentViewer {
            Label { word.title } icon: { Image(systemName: word.systemImage) }
        }
    }

    /// The VoiceOver hint of a word: the selected Bracket, Interval or Astro opens its settings.
    ///
    /// - Parameters:
    ///   - word: The word.
    ///   - isSelected: Whether it is selected.
    private func hint(for word: DriveWord, isSelected: Bool) -> Text {
        guard isSelected else { return Text(verbatim: "") }
        switch word {
        case .bracket: return BracketText.opensSettingsHint
        case .interval, .astro: return DriveWord.opensSettingsHint
        case .single, .timer, .burst: return Text(verbatim: "")
        }
    }

    /// A word's visible label for the presentation.
    ///
    /// - Parameter word: The word.
    @ViewBuilder private func label(for word: DriveWord) -> some View {
        switch presentation {
        case .words, .backedWords:
            word.title
                .lineLimit(1)
                .fixedSize()
        case .symbols:
            Image(systemName: word.systemImage)
                .uprightUnit()
        case .rows:
            CameraRowLabel(name: word.title, value: rowValue(for: word), systemImage: word.systemImage)
        }
    }

    /// The value under a word in the scrolling layout: the delay under Timer, the speed under
    /// the selected Burst, nothing otherwise.
    ///
    /// - Parameter word: The word.
    private func rowValue(for word: DriveWord) -> Text? {
        switch word {
        case .timer: Text(verbatim: DriveText.shortSeconds(timerDelay.seconds))
        case .burst where word == selected: BurstSpeedText.name(model.burstSpeed)
        default: nil
        }
    }

    /// Chooses a word: sets its mode, or for the selected word, opens what it opens.
    ///
    /// - Parameter word: The word chosen.
    private func choose(_ word: DriveWord) {
        guard word != selected else {
            switch word {
            case .interval: openIntervalSettings()
            case .astro: openAstroSettings()
            case .bracket: openBracketSettings()
            case .single, .timer, .burst: break
            }
            return
        }
        let model = model
        let settings = settings
        let delay = timerDelay
        Task {
            if word == .astro {
                // Turns night mode on too (issue #60), and leaving Astro turns it off again if
                // Astro turned it on; the helper turns manual controls on itself. It turns a
                // bracket off.
                await model.setAstro(true, settings: settings)
                return
            }
            if model.astro.isOn { await model.setAstro(false, settings: settings) }
            if word == .bracket {
                // The session's type: the last exposure bracket with its start delay, or the
                // focus bracket.
                await model.send(.bracket(.setOn(true)))
                return
            }
            // Another word turns the bracket off first (docs/design/BRACKETING.md, section 3).
            if model.isBracketOn { await model.send(.bracket(.setOn(false))) }
            if let mode = word.mode(timerDelay: delay) { await model.send(.drive(.setMode(mode))) }
        }
    }

    /// Chooses the burst speed from the Burst menu, for this session.
    ///
    /// - Parameter speed: The speed.
    private func chooseBurstSpeed(_ speed: BurstSpeed) {
        guard !isBusy else { return }
        let model = model
        Task { await model.send(.drive(.setBurstSpeed(speed))) }
    }

    /// Chooses the self-timer's delay from the Timer menu.
    ///
    /// - Parameter delay: The delay.
    private func chooseTimerDelay(_ delay: SelfTimerDelay) {
        // The camera keeps its mode while a countdown or a photo is going, so the delay shown
        // must not change then either.
        guard !isBusy else { return }
        timerDelay = delay
        let model = model
        Task { await model.send(.drive(.setMode(.timer(delay)))) }
    }
}

/// Applies a drive word's style: ``DriveWordStyle`` in the strip, a tile row in the scrolling
/// layout.
struct DriveWordStyling: ViewModifier {
    /// Whether the word is selected.
    let isSelected: Bool

    /// The space on each side of the label, in points, in the strip.
    let padding: CGFloat

    /// Whether the word is a full-width row (scrolling layout).
    let isRow: Bool

    /// Creates the styling.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the word is selected.
    ///   - padding: The space on each side of the label, in points, in the strip.
    ///   - isRow: Whether the word is a full-width row.
    init(isSelected: Bool, padding: CGFloat, isRow: Bool) {
        self.isSelected = isSelected
        self.padding = padding
        self.isRow = isRow
    }

    /// The control with its style.
    ///
    /// - Parameter content: The word's button or menu.
    @ViewBuilder func body(content: Content) -> some View {
        if isRow {
            content.buttonStyle(NopeTileStyle(isOn: isSelected, minHeight: NopeSize.scrollingRowButton))
        } else {
            content.buttonStyle(DriveWordStyle(isSelected: isSelected, padding: padding))
        }
    }
}

/// A drive word: a capsule ``NopeSize/driveWord`` high with a 44-point target, filled white
/// when selected and with no fill otherwise (docs/design/tokens.md, "Capsule"). It is
/// `NopeCapsuleStyle` with the padding the strip chooses, which tightens before the strip
/// scrolls (BUILD-SPEC.md, 3.5, "Fit"); `NopeCapsuleStyle` has a fixed padding.
struct DriveWordStyle: ButtonStyle {
    /// Whether the word is selected.
    let isSelected: Bool

    /// The space on each side of the label, in points.
    let padding: CGFloat

    /// Whether night mode is on.
    @Environment(\.isNightMode) private var isNightMode

    /// Whether Increase Contrast is on.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the style.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the word is selected.
    ///   - padding: The space on each side of the label, in points.
    init(isSelected: Bool, padding: CGFloat) {
        self.isSelected = isSelected
        self.padding = padding
    }

    /// The styled word.
    ///
    /// - Parameter configuration: The word's label and press state.
    func makeBody(configuration: Configuration) -> some View {
        let appearance = NopeControlAppearance.resolve(
            isSelected: isSelected, idleFill: .none, isNightMode: isNightMode, increaseContrast: contrast == .increased)
        configuration.label
            .font(NopeFont.status)
            .foregroundStyle(appearance.label)
            .padding(.horizontal, padding)
            .frame(minHeight: NopeSize.driveWord)
            .modifier(NopeControlBackground(appearance: appearance, shape: Capsule()))
            .nopeHitTarget()
            .contentShape(.hoverEffect, .capsule)
            .hoverEffect(.highlight)
            .modifier(NopePressEffect(isPressed: configuration.isPressed))
    }
}

/// The selected drive mode's name as a pill on the picture, while the iPhone is held sideways
/// and the strip shows only symbols (BUILD-SPEC.md, 3.1). It is a label, not a control: the
/// strip changes the mode.
struct DriveModePill: View {
    /// The selected word.
    let word: DriveWord

    /// Creates the pill.
    ///
    /// - Parameter word: The selected word.
    init(word: DriveWord) {
        self.word = word
    }

    /// The pill.
    var body: some View {
        Label {
            word.title
        } icon: {
            Image(systemName: word.systemImage)
        }
        .labelStyle(NopePillLabelStyle())
        .font(NopeFont.pill)
        .foregroundStyle(NopeColor.label)
        .padding(.horizontal, NopeSpace.s)
        .frame(minHeight: NopeSize.pill)
        .nopeBackground(.backing, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// The words for the burst speeds in the Burst menu (docs/design/BURST.md, 6). No rate is
/// promised: Fast is "as fast as the camera is ready", and Slow is "up to" its figure.
@MainActor
enum BurstSpeedText {
    /// The menu's title, "Burst Speed".
    static var menuTitle: Text {
        Text("Burst Speed", bundle: .module, comment: "Title of the menu of the selected Burst word on the camera: how fast a burst takes its photos.")
    }

    /// The speed's name: "Fast" or "Slow".
    ///
    /// - Parameter speed: The speed.
    static func name(_ speed: BurstSpeed) -> Text {
        switch speed {
        case .fast:
            Text(String(localized: "Burst speed: Fast", defaultValue: "Fast", bundle: .module, comment: "Burst speed in the menu of the selected Burst word: photos are taken as fast as the camera is ready."))
        case .slow:
            Text(String(localized: "Burst speed: Slow", defaultValue: "Slow", bundle: .module, comment: "Burst speed in the menu of the selected Burst word: up to 2 photos a second."))
        }
    }

    /// The line under the speed's name in the menu.
    ///
    /// - Parameter speed: The speed.
    static func detail(_ speed: BurstSpeed) -> Text {
        switch speed {
        case .fast:
            Text("As fast as the camera is ready", bundle: .module, comment: "Detail of the Fast burst speed in the Burst menu. It makes no claim about a rate.")
        case .slow:
            Text("Up to \(speed.maximumPhotosPerSecond ?? 2) photos a second", bundle: .module, comment: "Detail of the Slow burst speed in the Burst menu. The number is the most photos a second, 2; \"up to\": it can be fewer.")
        }
    }
}
