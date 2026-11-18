import NopeCore
import SwiftUI

/// The words of exposure bracketing (docs/design/BRACKETING.md, section 7, "Strings"). Keys the
/// string catalog doesn't have yet carry their English as the default value.
@MainActor
enum BracketText {
    /// "Bracket": the drive strip's word.
    static var word: String {
        String(
            localized: "Drive strip: Bracket", defaultValue: "Bracket", bundle: .module,
            comment: "Drive mode word in the strip above the shutter: one press takes an exposure bracket, several separate photos at different exposures. A short word; the strip holds six.")
    }

    /// "Bracket Settings": the sheet's title, and the idle card's VoiceOver name.
    static var settings: Text {
        Text("Bracket Settings", bundle: .module, comment: "Title of the sheet with the exposure bracket's frames, step, order and start delay, and the name of the card on the camera that opens it.")
    }

    /// "Opens Bracket Settings.": the hint of the selected Bracket word.
    static var opensSettingsHint: Text {
        Text("Opens Bracket Settings.", bundle: .module, comment: "VoiceOver hint on the selected Bracket word of the drive strip above the shutter: activating it again opens Bracket Settings.")
    }

    /// An exposure offset with its sign and no unit, such as "−1", "0" or "+⅔".
    ///
    /// - Parameter offset: The offset, in EV.
    static func signed(_ offset: Double) -> String {
        offset.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)))
    }

    /// An offset with its unit, such as "−1 EV" or "0 EV".
    ///
    /// - Parameter offset: The offset, in EV.
    static func offset(_ offset: Double) -> String {
        String(localized: "\(signed(offset)) EV", bundle: .module, comment: "An exposure value in EV units, such as -0.7 EV. EV means exposure value.")
    }

    /// The offsets in the order they are taken, with one unit: "−1, 0, +1 EV".
    ///
    /// - Parameter offsets: The offsets, in EV.
    static func offsets(_ offsets: [Double]) -> String {
        let list = offsets.map(signed).joined(separator: ", ")
        return String(localized: "\(list) EV", bundle: .module, comment: "An exposure value in EV units, such as -0.7 EV. EV means exposure value.")
    }

    /// "Exposure bracket: 3 frames, 1 EV apart": the idle card's title.
    ///
    /// - Parameter bracket: The bracket.
    static func summary(_ bracket: BracketSettings) -> String {
        String(
            localized: "Exposure bracket: \(bracket.frameCount) frames, \(ControlText.step(bracket.step)) apart", bundle: .module,
            comment: "Bracket card on the camera: what one press of the shutter takes. The number is the count of frames (3, 5 or 7); the second value is the step between them, such as \"1 EV\".")
    }

    /// The idle card's detail: the offsets, and with a start delay "· after 3 seconds".
    ///
    /// - Parameters:
    ///   - bracket: The bracket.
    ///   - startDelay: The start delay, or `nil` for none.
    static func idleDetail(_ bracket: BracketSettings, startDelay: SelfTimerDelay?) -> String {
        let offsets = offsets(bracket.offsets)
        guard let startDelay else { return offsets }
        return String(
            localized: "\(offsets) · after \(DriveText.spokenSeconds(startDelay.seconds))", bundle: .module,
            comment: "Bracket card on the camera, second line, with a start delay: the frames' exposure offsets, such as \"−1, 0, +1 EV\", then the delay, such as \"3 seconds\", formatted by the system.")
    }

    /// "Bracket in 3s": the countdown card's title.
    ///
    /// - Parameter seconds: The seconds left.
    static func bracketIn(_ seconds: Int) -> Text {
        Text(
            String(
                localized: "Bracket in %@", defaultValue: "Bracket in \(DriveText.shortSeconds(seconds))", bundle: .module,
                comment: "Bracket card on the camera while the start delay counts down: the bracket is taken after this many seconds. The value is a short number of seconds, such as 3s, formatted by the system."))
    }

    /// "3 frames, −1, 0, +1 EV": the countdown card's detail.
    ///
    /// - Parameter bracket: The bracket.
    static func framesAndOffsets(_ bracket: BracketSettings) -> String {
        String(
            localized: "\(bracket.frameCount) frames, \(offsets(bracket.offsets))", bundle: .module,
            comment: "Bracket card on the camera while the start delay counts down, second line: the number of frames, then their exposure offsets, such as \"−1, 0, +1 EV\".")
    }

    /// "Taking 3 frames".
    ///
    /// - Parameter count: The frames in the bracket.
    static func taking(_ count: Int) -> String {
        String(localized: "Taking \(count) frames", bundle: .module, comment: "Bracket card on the camera, and announced to VoiceOver, while the camera takes the frames of an exposure bracket. The number is the count of frames, 3, 5 or 7.")
    }

    /// "Saving: 2 of 3 photos saved".
    ///
    /// - Parameter progress: The bracket's progress.
    static func saving(_ progress: BracketProgress) -> Text {
        Text("Saving: \(progress.saved) of \(progress.total) photos saved", bundle: .module, comment: "Bracket card on the camera while the frames of an exposure bracket are saved to the photo library: how many are saved so far, of how many.")
    }

    /// "3 photos saved": the card after a bracket, shared with Burst.
    ///
    /// - Parameter count: The photos saved.
    static func saved(_ count: Int) -> Text {
        Text("\(count) photos saved", bundle: .module, comment: "Card on the camera after an exposure bracket or a burst: how many separate photos were saved to the photo library.")
    }

    /// "Bracket stopped: 2 of 3 photos saved.": the start of the failure banner.
    ///
    /// - Parameter progress: How far the bracket got.
    static func stopped(_ progress: BracketProgress) -> String {
        String(
            localized: "Bracket stopped: \(progress.saved) of \(progress.total) photos saved.", bundle: .module,
            comment: "Banner on the camera when a frame of an exposure bracket couldn't be saved; the reason follows in another sentence. The first number is the photos saved, the second the frames in the bracket.")
    }

    /// "Bracket, exposure, 3 frames": the shutter's VoiceOver value.
    ///
    /// - Parameter bracket: The bracket.
    static func shutterValue(_ bracket: BracketSettings) -> Text {
        Text("Bracket, exposure, \(bracket.frameCount) frames", bundle: .module, comment: "VoiceOver value of the shutter when one press takes an exposure bracket. The number is the count of frames.")
    }

    /// "Cancel": the countdown card's button.
    static var cancel: Text {
        Text(String(localized: "Bracket card: Cancel", defaultValue: "Cancel", bundle: .module, comment: "Button on the bracket card while the start delay counts down: stops the countdown; no photo is taken."))
    }

    /// A bracket order's name.
    ///
    /// - Parameter order: The order.
    static func name(_ order: BracketOrder) -> String {
        switch order {
        case .darkestFirst:
            String(localized: "Darkest First", bundle: .module, comment: "Choice of the bracket's Order: the darkest frame first, then brighter ones.")
        case .meteredFirst:
            String(localized: "Metered First", bundle: .module, comment: "Choice of the bracket's Order: the frame at the metered exposure first, then darker and brighter ones, outward.")
        case .brightestFirst:
            String(localized: "Brightest First", bundle: .module, comment: "Choice of the bracket's Order: the brightest frame first, then darker ones.")
        }
    }

    /// "Exposure bracket · frame 2 of 3 · 0 EV": the viewer's chip.
    ///
    /// - Parameter place: The photo's place in its bracket.
    static func chip(_ place: BracketPlace) -> String {
        if let focus = place.focus { return FocusBracketText.chip(focus, count: place.count) }
        return String(
            localized: "Exposure bracket · frame \(place.number) of \(place.count) · \(offset(place.frame?.offset ?? 0))", bundle: .module,
            comment: "Chip on a photo in the Last Photo viewer: the photo is one frame of an exposure bracket. The numbers are the frame and the count of frames; the last value is the frame's exposure offset, such as \"0 EV\".")
    }

    /// "Exposure bracket, frame 2 of 3, 0 EV.": the chip as part of a page's VoiceOver label.
    ///
    /// - Parameter place: The photo's place in its bracket.
    static func chipSpoken(_ place: BracketPlace) -> String {
        if let focus = place.focus { return FocusBracketText.chipSpoken(focus, count: place.count) }
        return String(
            localized: "Exposure bracket, frame \(place.number) of \(place.count), \(offset(place.frame?.offset ?? 0)).", bundle: .module,
            comment: "VoiceOver, part of a photo's label in the Last Photo viewer: the photo is one frame of an exposure bracket. The numbers are the frame and the count of frames; the last value is its exposure offset, such as \"0 EV\".")
    }

    /// The Honesty sentences of Bracket Settings, one under the other.
    static var honesty: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
            Text("Each frame is a separate single-frame photo. Nothing is merged.", tableName: "Honesty", bundle: .module, comment: "Explains exposure bracketing. Must not claim more than the English: the photos are never combined.")
            Text("A bracket never fires the flash.", tableName: "Honesty", bundle: .module, comment: "In Bracket Settings: the flash doesn't fire for any frame of an exposure bracket. Must not claim more than the English.")
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the bracket's card on the picture's lower edge shows (docs/design/BRACKETING.md,
/// section 4, "The card and the shutter"). Plain data from the camera's state, so which card
/// shows is tested without drawing.
enum BracketCardState: Equatable {
    /// A bracket is on and nothing runs: "Exposure bracket: 3 frames, 1 EV apart". The whole
    /// card is the button Bracket Settings.
    case idle(BracketSettings, startDelay: SelfTimerDelay?)

    /// The start delay counts down: "Bracket in 3s" and Cancel.
    case countdown(remaining: Int, BracketSettings)

    /// The camera takes the frames: "Taking 3 frames".
    case taking(total: Int)

    /// The frames are saved: "Saving: 2 of 3 photos saved", with a progress bar.
    case saving(BracketProgress)

    /// The bracket was saved: "3 photos saved", until the next action.
    case saved(count: Int, offsets: [Double])

    /// A focus bracket is on and nothing runs: "Focus bracket: 12 frames", the track, Nearest
    /// and Farthest.
    case focusIdle(FocusBracketSettings)

    /// An end of the focus range is being set on the picture: the dial, with the value shown.
    case focusRange(FocusRangeEditing, value: Double)

    /// The focus bracket's start delay counts down: "Bracket in 3s" and Cancel.
    case focusCountdown(remaining: Int, FocusBracketSettings)

    /// A focus bracket runs: "Frame 4 of 12", the focus reported, the track and Stop Bracket.
    case focusRunning(FocusBracketProgress, positions: [Double])

    /// A focus bracket is paused: "Paused: 4 of 12 frames" and Stop Bracket.
    case focusPaused(FocusBracketProgress)

    /// A focus bracket ended: the photos saved, why it stopped, and where the focus is.
    case focusEnded(FocusBracketResult)

    /// Whether the card shows something that runs, and so stays in clean view.
    var isRunning: Bool {
        switch self {
        case .countdown, .taking, .saving, .focusCountdown, .focusRunning, .focusPaused, .focusRange: true
        case .idle, .saved, .focusIdle, .focusEnded: false
        }
    }

    /// Whether the card is one of a focus bracket's.
    var isFocus: Bool {
        switch self {
        case .focusIdle, .focusRange, .focusCountdown, .focusRunning, .focusPaused, .focusEnded: true
        case .idle, .countdown, .taking, .saving, .saved: false
        }
    }

    /// The focus bracket's card, or `nil` when no focus bracket is on, runs or is being set up.
    ///
    /// - Parameters:
    ///   - bracketing: The focus bracket's state.
    ///   - isOn: Whether the focus bracket is on (``CameraModel/isFocusBracketOn``).
    ///   - rangeValue: The value of the range end being set, or `nil`.
    ///   - countdownRemaining: The countdown's seconds left, or `nil`.
    ///   - ended: The end card of the last focus bracket, until the next action, or `nil`.
    ///   - showsControls: Whether the controls are shown (not clean view).
    /// - Returns: The card, or `nil`.
    @MainActor
    static func focus(
        _ bracketing: BracketModel, isOn: Bool, rangeValue: Double?, countdownRemaining: Int?,
        ended: BracketCardState?, showsControls: Bool
    ) -> BracketCardState? {
        if let progress = bracketing.progress {
            guard !progress.isPaused else { return .focusPaused(progress) }
            return .focusRunning(progress, positions: bracketing.running?.positions ?? [])
        }
        guard isOn else { return nil }
        if let editing = bracketing.rangeEditing { return .focusRange(editing, value: rangeValue ?? editing.value) }
        if let countdownRemaining { return .focusCountdown(remaining: countdownRemaining, bracketing.focus) }
        guard showsControls else { return nil }
        return ended ?? .focusIdle(bracketing.focus)
    }

    /// The card for the camera's state, or `nil` for none.
    ///
    /// - Parameters:
    ///   - bracket: The bracket that is on, or `nil` (also while the astro helper is on).
    ///   - startDelay: The bracket's start delay.
    ///   - countdownRemaining: The self-timer's seconds left, or `nil`.
    ///   - progress: The bracket being taken and saved, or `nil`.
    ///   - saved: The last bracket saved, whose card shows until the next action, or `nil`.
    ///   - showsControls: Whether the controls are shown (not clean view).
    /// - Returns: The card, or `nil`.
    static func resolve(
        bracket: BracketSettings?, startDelay: SelfTimerDelay?, countdownRemaining: Int?, progress: BracketProgress?,
        saved: BracketCardState?, showsControls: Bool
    ) -> BracketCardState? {
        if let progress { return progress.isTaking ? .taking(total: progress.total) : .saving(progress) }
        guard let bracket else { return nil }
        if let countdownRemaining { return .countdown(remaining: countdownRemaining, bracket) }
        guard showsControls else { return nil }
        return saved ?? .idle(bracket, startDelay: startDelay)
    }

    /// The card for the camera model's state, or `nil`.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - saved: The last bracket saved, whose card shows until the next action, or `nil`.
    ///   - showsControls: Whether the controls are shown.
    /// - Returns: The card, or `nil`.
    @MainActor
    static func current(_ model: CameraModel, saved: BracketCardState?, showsControls: Bool) -> BracketCardState? {
        if model.bracketing.isRunning || model.isFocusBracketOn {
            return focus(
                model.bracketing, isOn: model.isFocusBracketOn, rangeValue: model.focusRangeValue,
                countdownRemaining: model.drive.countdown.remainingSeconds, ended: saved?.isFocus == true ? saved : nil,
                showsControls: showsControls)
        }
        return resolve(
            bracket: model.isBracketOn ? model.manual.bracket : nil, startDelay: model.bracketStartDelay,
            countdownRemaining: model.drive.countdown.remainingSeconds, progress: model.bracketProgress, saved: saved,
            showsControls: showsControls)
    }

    /// The saved card for a capture result, or `nil` when it isn't a bracket's.
    ///
    /// - Parameters:
    ///   - status: A capture status.
    ///   - focusRun: How the last focus bracket ended, for a focus bracket's photos.
    static func saved(from status: CaptureStatus, focusRun: FocusBracketResult? = nil) -> BracketCardState? {
        guard case .savedBracket(let photos) = status, let place = photos.first?.bracket else { return nil }
        guard place.type == .exposure else { return focusRun.map(BracketCardState.focusEnded) }
        return .saved(count: photos.count, offsets: place.offsets)
    }
}

/// The bracket's card, one state of ``BracketCardState``. The idle card is one button that opens
/// Bracket Settings; the countdown has Cancel; taking and saving have no button, because the
/// system can't stop a bracket request once it is made (docs/design/BRACKETING.md, section 2).
struct BracketCard: View {
    /// The card's state.
    let state: BracketCardState

    /// Opens Bracket Settings.
    let openSettings: () -> Void

    /// Cancels the start delay.
    let cancel: () -> Void

    /// Sends an intent to the camera, for the focus bracket's buttons.
    let send: (CameraIntent) -> Void

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - state: The card's state.
    ///   - openSettings: Opens Bracket Settings.
    ///   - send: Sends an intent, for the focus bracket's buttons.
    ///   - cancel: Cancels the start delay.
    init(
        state: BracketCardState, openSettings: @escaping () -> Void, send: @escaping (CameraIntent) -> Void = { _ in },
        cancel: @escaping () -> Void
    ) {
        self.state = state
        self.openSettings = openSettings
        self.send = send
        self.cancel = cancel
    }

    /// The card.
    var body: some View {
        switch state {
        case .idle(let bracket, let startDelay):
            SettingsCard(
                title: BracketText.summary(bracket), detail: BracketText.idleDetail(bracket, startDelay: startDelay),
                name: BracketText.settings, action: openSettings)
        case .countdown(let remaining, let bracket):
            ModeCard(title: BracketText.bracketIn(remaining), detail: Text(verbatim: BracketText.framesAndOffsets(bracket))) {
                Button(action: cancel) {
                    BracketText.cancel
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .tile))
            }
        case .taking(let total):
            ModeCard(title: Text(verbatim: BracketText.taking(total))) { EmptyView() }
        case .saving(let progress):
            ModeCard(
                title: BracketText.saving(progress), detail: Text?.none,
                fractionDone: Double(progress.saved) / Double(max(progress.total, 1))
            ) { EmptyView() }
        case .saved(let count, let offsets):
            ModeCard(title: BracketText.saved(count), detail: Text(verbatim: BracketText.offsets(offsets))) { EmptyView() }
        case .focusCountdown(let remaining, let settings):
            ModeCard(title: BracketText.bracketIn(remaining), detail: Text(verbatim: FocusBracketText.countdownDetail(settings))) {
                Button(action: cancel) {
                    BracketText.cancel
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .tile))
            }
        case .focusIdle, .focusRange, .focusRunning, .focusPaused, .focusEnded:
            FocusBracketCard(state: state, send: send, openSettings: openSettings)
        }
    }
}

/// Announcements for a bracket without looking at the screen: "Taking 3 frames" when the
/// request starts. The countdown's numbers are the self-timer's (``DriveFeedback``), and the
/// saved photos are announced by the camera's save feedback.
struct BracketFeedback: ViewModifier {
    /// The camera model.
    let model: CameraModel

    /// Creates the feedback.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The content with the feedback attached.
    ///
    /// - Parameter content: The camera.
    func body(content: Content) -> some View {
        content
            .onChange(of: model.bracketProgress?.isTaking == true) { _, isTaking in
                if isTaking, let total = model.bracketProgress?.total {
                    AccessibilityNotification.Announcement(BracketText.taking(total)).post()
                }
            }
            // A focus bracket: "Frame 4 of 12" at each frame, at low priority so it doesn't
            // interrupt VoiceOver, and the end sentence.
            .onChange(of: model.bracketing.progress?.taken) {
                guard let progress = model.bracketing.progress, !progress.isPaused else { return }
                var frame = AttributedString(FocusBracketText.frame(progress.frameNumber, of: progress.total))
                frame.accessibilitySpeechAnnouncementPriority = .low
                AccessibilityNotification.Announcement(frame).post()
            }
            .onChange(of: model.bracketing.lastRun) { _, result in
                guard let result else { return }
                let sentence = [FocusBracketText.endTitle(result), FocusBracketText.endDetail(result)].joined(separator: ". ")
                AccessibilityNotification.Announcement(sentence).post()
            }
    }
}

extension View {
    /// Adds the bracket's announcements (``BracketFeedback``).
    ///
    /// - Parameter model: The camera model.
    func bracketFeedback(_ model: CameraModel) -> some View {
        modifier(BracketFeedback(model: model))
    }
}

/// Bracket Settings (docs/design/BRACKETING.md, section 7; figures `bracket-settings` and
/// `bracket-settings-limited`): Frames, Step and Order; the Start Delay; The Frames, each
/// frame's exposure with the limited ones marked; and the Honesty sentence. Opened from the
/// selected Bracket word and from the bracket's card.
///
/// Every value is sent to `NopeCore` as an intent: the bracket as
/// `ManualControlIntent.setBracket(_:)`, the start delay as the drive mode (Single, or the
/// self-timer with the delay). Nothing is stored between launches.
struct BracketSheet: View {
    /// The camera model.
    let model: CameraModel

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The manual controls model, which holds the bracket.
    private var manual: ManualControlsModel { model.manual }

    /// The bracket shown: the one that is on, or the session's last one.
    private var bracket: BracketSettings {
        manual.bracket ?? manual.lastBracket
    }

    /// The form.
    var body: some View {
        NavigationStack {
            Form {
                typeSection
                if model.bracketing.type == .focus {
                    FocusBracketSections(model: model) { end in
                        // The sheet closes, and the end is set on the picture.
                        dismiss()
                        let model = model
                        Task { await model.send(.bracket(.beginSettingRange(end))) }
                    }
                } else {
                    exposureSections
                }
                // Done is a row of the form, not a bar button, as in Pro Tools: the audit can't
                // measure the contrast of the glass bar button.
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module, comment: "Button that closes a sheet, such as Settings or Pro Tools.")
                    }
                }
            }
            .navigationTitle(BracketText.settings)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The text size: the Type control becomes a two-row picker at accessibility sizes.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Type: Exposure or Focus. Dimmed, with its sentence, where the lens can take only one.
    private var typeSection: some View {
        Section {
            let selection = Binding(
                get: { model.bracketing.type },
                set: { type in
                    let model = model
                    Task { await model.send(.bracket(.setType(type))) }
                })
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Picker(selection: selection) { typeChoices } label: { typeLabel }
                        .pickerStyle(.inline)
                } else {
                    Picker(selection: selection) { typeChoices } label: { typeLabel }
                        .pickerStyle(.segmented)
                }
            }
            .disabled(!(model.canFocusBracket && model.canExposureBracket))
        } footer: {
            if !model.canFocusBracket {
                Text("Focus bracketing needs a lens whose focus can be set. This lens’s focus can’t.", bundle: .module, comment: "Under the Type control in Bracket Settings, on a lens whose focus can't be set by the app.")
            }
        }
    }

    /// The Type control's label.
    private var typeLabel: Text {
        Text("Type", bundle: .module, comment: "Control in Bracket Settings, and a setting of the Take Bracket action: the kind of bracket, exposure or focus.")
    }

    /// The Type control's choices.
    private var typeChoices: some View {
        ForEach(BracketType.allCases, id: \.self) { type in
            Text(verbatim: FocusBracketText.name(type)).tag(type)
        }
    }

    /// The exposure bracket's sections (release 1.0.0's sheet).
    @ViewBuilder
    private var exposureSections: some View {
                Section {
                    framesPicker
                    stepPicker
                    orderPicker
                }
                Section {
                    startDelayPicker
                } footer: {
                    Text("Waits before the first frame, so touching the phone doesn't shake it.", bundle: .module, comment: "Footer under Start Delay in Bracket Settings.")
                }
                if let plan = manual.bracketPlan {
                    Section {
                        ForEach(plan, id: \.number) { frame in
                            BracketFrameRow(frame: frame)
                        }
                    } header: {
                        Text("The Frames", bundle: .module, comment: "Section header in Bracket Settings: the frames one press takes, each with its exposure.")
                    } footer: {
                        framesFooter
                    }
                }
                Section {
                    BracketText.honesty
                }
    }

    /// Frames: 3, 5 or 7, as the lens allows.
    private var framesPicker: some View {
        Picker(selection: Binding(get: { bracket.frameCount }, set: { setBracket(bracket.with(frameCount: $0)) })) {
            ForEach(manual.bracketFrameCounts, id: \.self) { count in
                Text(verbatim: count.formatted()).tag(count)
            }
        } label: {
            Text("Frames", bundle: .module, comment: "Picker for how many photos one bracket takes.")
        }
        .pickerStyle(.navigationLink)
    }

    /// Step: 1/3, 2/3, 1 or 2 EV.
    private var stepPicker: some View {
        Picker(selection: Binding(get: { bracket.step }, set: { setBracket(bracket.with(step: $0)) })) {
            ForEach(BracketSettings.steps, id: \.self) { step in
                Text(verbatim: ControlText.step(step)).tag(step)
            }
        } label: {
            Text("Step", bundle: .module, comment: "Picker for the exposure difference between bracketed photos.")
        }
        .pickerStyle(.navigationLink)
    }

    /// Order: darkest, metered or brightest first.
    private var orderPicker: some View {
        Picker(selection: Binding(get: { bracket.order }, set: { setBracket(bracket.with(order: $0)) })) {
            ForEach(BracketOrder.allCases, id: \.self) { order in
                Text(verbatim: BracketText.name(order)).tag(order)
            }
        } label: {
            Text("Order", bundle: .module, comment: "Picker in Bracket Settings, and a setting of the Take Bracket action: the order in which the frames are taken.")
        }
        .pickerStyle(.navigationLink)
    }

    /// Start Delay: off, 3 or 10 seconds, the self-timer's delays.
    private var startDelayPicker: some View {
        Picker(selection: Binding(get: { model.bracketStartDelay }, set: { setStartDelay($0) })) {
            Text(String(localized: "Start Delay: Off", defaultValue: "Off", bundle: .module, comment: "Choice of Start Delay in Bracket Settings: the bracket is taken at once."))
                .tag(SelfTimerDelay?.none)
            ForEach(SelfTimerDelay.allCases, id: \.self) { delay in
                Text(verbatim: DriveText.spokenSeconds(delay.seconds)).tag(SelfTimerDelay?.some(delay))
            }
        } label: {
            Text("Start Delay", bundle: .module, comment: "Picker in the night sky helper's settings: how long the self-timer waits before the first frame, so touching the phone doesn't shake it.")
        }
        .pickerStyle(.navigationLink)
    }

    /// What the frames are planned from, and which value changes from frame to frame.
    private var framesFooter: Text {
        if manual.bracketChangesISOFirst {
            Text("From the exposure the camera reads now; it is read again when you press the shutter. ISO changes from frame to frame. The shutter speed changes only where ISO can't go further.", bundle: .module, comment: "Footer under The Frames in Bracket Settings when the shutter speed is set by hand: the frames are planned from the camera's current reading, and ISO changes first.")
        } else {
            Text("From the exposure the camera reads now; it is read again when you press the shutter. The shutter speed changes from frame to frame. ISO changes only where the shutter can't go further.", bundle: .module, comment: "Footer under The Frames in Bracket Settings: the frames are planned from the camera's current reading, and the shutter speed changes first.")
        }
    }

    /// Sends a new bracket, which stays on.
    ///
    /// - Parameter bracket: The bracket.
    private func setBracket(_ bracket: BracketSettings) {
        let model = model
        Task { await model.send(.manual(.setBracket(bracket))) }
    }

    /// Sends the start delay as the drive mode: Single, or the self-timer with the delay.
    ///
    /// - Parameter delay: The delay, or `nil` for none.
    private func setStartDelay(_ delay: SelfTimerDelay?) {
        let model = model
        Task { await model.send(.drive(.setMode(delay.map(DriveMode.timer) ?? .single))) }
    }
}

/// One frame of The Frames: its number, its offset (and, when the lens can't give it, the offset
/// asked for and why), its shutter speed and ISO. VoiceOver reads it as one sentence.
struct BracketFrameRow: View {
    /// The frame.
    let frame: BracketFramePlan

    /// Creates the row.
    ///
    /// - Parameter frame: The frame.
    init(frame: BracketFramePlan) {
        self.frame = frame
    }

    /// The offset reached, and the one asked for when they differ: "+2 EV, not +4".
    private var offsetText: String {
        guard frame.isLimited else { return BracketText.offset(frame.offset) }
        return String(
            localized: "\(BracketText.offset(frame.offset)), not \(BracketText.signed(frame.requestedOffset))", bundle: .module,
            comment: "A frame in Bracket Settings that the lens can't give: the exposure offset it will have, such as \"+2 EV\", then the one asked for, such as \"+4\".")
    }

    /// "1/250 s · ISO 200".
    private var exposureText: String {
        "\(ControlText.shutter(frame.frame.exposureDuration)) · ISO \(ControlText.value(frame.frame.iso, of: .iso))"
    }

    /// Why the frame is limited, or `nil`.
    private var limitText: String? {
        guard let limit = frame.limit, let number = frame.limitingFrameNumber else { return nil }
        switch limit {
        case .brightest:
            return String(localized: "This lens can't go brighter than frame \(number).", bundle: .module, comment: "Under a frame in Bracket Settings that the lens can't make as bright as asked. The number is the first frame with the brightest exposure the lens can give.")
        case .darkest:
            return String(localized: "This lens can't go darker than frame \(number).", bundle: .module, comment: "Under a frame in Bracket Settings that the lens can't make as dark as asked. The number is the first frame with the darkest exposure the lens can give.")
        }
    }

    /// The row.
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NopeSpace.s) {
            Text(verbatim: frame.number.formatted())
                .font(.footnote.monospacedDigit())
                .foregroundStyle(CameraStyle.secondaryText)
            VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                Text(verbatim: offsetText)
                if let limitText {
                    Text(verbatim: limitText)
                        .font(.footnote)
                        .foregroundStyle(CameraStyle.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if frame.isLimited {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CameraStyle.warning)
                    .accessibilityHidden(true)
            }
            Text(verbatim: exposureText)
                .monospacedDigit()
                .foregroundStyle(CameraStyle.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    /// "Frame 1, −1 EV, 1/250 s, ISO 200", and the limit's sentence for a limited frame.
    private var spoken: String {
        let sentence = String(
            localized: "Frame \(frame.number), \(offsetText), \(ControlText.shutter(frame.frame.exposureDuration)), ISO \(ControlText.value(frame.frame.iso, of: .iso))",
            bundle: .module,
            comment: "VoiceOver label of a frame in Bracket Settings: the frame's number, its exposure offset such as \"-1 EV\", its shutter speed such as \"1/250\", and its ISO.")
        return [sentence, limitText].compactMap(\.self).joined(separator: ". ")
    }
}

/// The chip on a bracket's frame in the Last Photo viewer: "Exposure bracket · frame 2 of 3 ·
/// 0 EV" (docs/design/BRACKETING.md, section 4; figure `bracket-viewer`). From the session's
/// values only (`SavedPhoto.bracket`); nothing is read from or written to the file.
///
/// Integration: the viewer shows it on the picture's lower edge for a page whose photo has a
/// `bracket`, hides it with the other controls, and adds ``BracketText/chipSpoken(_:)`` to the
/// page's VoiceOver label (so the chip itself is hidden from VoiceOver).
struct BracketChip: View {
    /// The photo's place in its bracket.
    let place: BracketPlace

    /// Creates the chip.
    ///
    /// - Parameter place: The photo's place in its bracket.
    init(place: BracketPlace) {
        self.place = place
    }

    /// The chip.
    var body: some View {
        Text(verbatim: BracketText.chip(place))
            .font(NopeFont.pill)
            .foregroundStyle(NopeColor.label)
            .padding(.horizontal, NopeSpace.s)
            .frame(minHeight: NopeSize.pill)
            .nopeBackground(.backing, in: Capsule())
            .accessibilityHidden(true)
            .accessibilityIdentifier("BracketChip")
    }
}

/// The Bracket group of What's in This Photo (docs/design/BRACKETING.md, section 4; figure
/// `bracket-details`): Type, This Frame, Planned Exposure and The Bracket, with a footer that
/// says these are session values that no file holds.
struct BracketDetailsSection: View {
    /// The photo's place in its bracket.
    let place: BracketPlace

    /// Creates the section.
    ///
    /// - Parameter place: The photo's place in its bracket.
    init(place: BracketPlace) {
        self.place = place
    }

    /// The section.
    var body: some View {
        Section {
            DetailRow(
                title: Text(String(localized: "Bracket details: Type", defaultValue: "Type", bundle: .module, comment: "Row in the photo details of a bracket's frame: the kind of bracket.")),
                value: place.focus == nil
                    ? Text(String(localized: "Bracket details: Exposure", defaultValue: "Exposure", bundle: .module, comment: "Value of the Type row in the photo details: an exposure bracket, frames at different exposures."))
                    : Text(verbatim: FocusBracketText.name(.focus)))
            DetailRow(
                title: Text("This Frame", bundle: .module, comment: "Row in the photo details of a bracket's frame: which frame of the bracket this photo is."),
                value: Text("\(place.number) of \(place.count)", bundle: .module, comment: "Value of This Frame in the photo details: the frame's number, of how many frames."))
            if let focus = place.focus {
                FocusBracketDetailRows(place: focus)
            }
            if let frame = place.frame, let order = place.order {
                DetailRow(
                    title: Text("Planned Exposure", bundle: .module, comment: "Row in the photo details of a bracket's frame: the exposure the app asked the camera for."),
                    value: Text(verbatim: "\(BracketText.offset(frame.offset))\n\(ControlText.shutter(frame.frame.exposureDuration)) · ISO \(ControlText.value(frame.frame.iso, of: .iso))"))
                DetailRow(
                    title: Text("The Bracket", bundle: .module, comment: "Row in the photo details of a bracket's frame: every frame's exposure offset, and their order."),
                    value: Text(verbatim: "\(BracketText.offsets(place.offsets))\n\(BracketText.name(order))"))
            }
        } header: {
            Text(verbatim: BracketText.word)
        } footer: {
            if place.focus != nil {
                Text(
                    "Focus is a position on this lens’s own scale from 0 to 1, not a distance. Kept by nope. until it closes; not written to the files.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Footer of the Bracket group in the photo details of a focus bracket's frame. Keep \"nope.\" unchanged: it is the app's name. Must not claim more than the English: no distance is known, and the values are in memory only.")
            } else {
                Text(
                    "Kept by nope. until it closes, to group the frames here. Not written to the files; in Photos each frame is a separate photo.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Footer of the Bracket group in the photo details. Keep \"nope.\" unchanged: it is the app's name. Must not claim more than the English: the values are in memory only.")
            }
        }
    }
}
