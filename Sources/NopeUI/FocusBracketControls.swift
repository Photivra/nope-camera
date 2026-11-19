import NopeCore
import SwiftUI

/// The words of focus bracketing (docs/design/BRACKETING.md, section 8, "Strings"). Focus is
/// always a position on the lens's own scale from 0 to 1, shown to two decimals; never a
/// distance, a depth of field, a time or a rate.
@MainActor
enum FocusBracketText {
    /// A lens position to two decimals, such as "0.31".
    ///
    /// - Parameter position: The position, from 0 to 1.
    static func position(_ position: Double) -> String {
        position.formatted(.number.precision(.fractionLength(2)))
    }

    /// A type's name: "Exposure" or "Focus".
    ///
    /// - Parameter type: The type.
    static func name(_ type: BracketType) -> String {
        switch type {
        case .exposure:
            String(localized: "Bracket type: Exposure", defaultValue: "Exposure", bundle: .module, comment: "Choice of the Type control in Bracket Settings, and of the Take Bracket action: frames at different exposures.")
        case .focus:
            String(localized: "Bracket type: Focus", defaultValue: "Focus", bundle: .module, comment: "Choice of the Type control in Bracket Settings, and of the Take Bracket action: frames at different focus positions.")
        }
    }

    /// An end of the range's name: "Nearest Focus" or "Farthest Focus".
    ///
    /// - Parameter end: The end.
    static func title(_ end: FocusRangeEnd) -> Text {
        switch end {
        case .nearest: Text("Nearest Focus", bundle: .module, comment: "Row in Bracket Settings, button on the focus bracket card and title of the dial: the nearest focus position of a focus bracket.")
        case .farthest: Text("Farthest Focus", bundle: .module, comment: "Row in Bracket Settings, button on the focus bracket card and title of the dial: the farthest focus position of a focus bracket.")
        }
    }

    /// "Focus bracket: 12 frames": the idle card's title.
    ///
    /// - Parameter settings: The bracket.
    static func summary(_ settings: FocusBracketSettings) -> String {
        String(localized: "Focus bracket: \(settings.frameCount) frames", bundle: .module, comment: "Focus bracket card on the camera: what one press of the shutter takes. The number is the count of frames.")
    }

    /// "Focus 0.12 to 0.80, nearest first": the idle card's detail.
    ///
    /// - Parameter settings: The bracket.
    static func range(_ settings: FocusBracketSettings) -> String {
        let nearest = position(settings.nearest)
        let farthest = position(settings.farthest)
        switch settings.order {
        case .nearestFirst:
            return String(localized: "Focus \(nearest) to \(farthest), nearest first", bundle: .module, comment: "Focus bracket card, second line: the focus positions on the lens's own scale from 0 to 1, not distances, and the order.")
        case .farthestFirst:
            return String(localized: "Focus \(nearest) to \(farthest), farthest first", bundle: .module, comment: "Focus bracket card, second line: the focus positions on the lens's own scale from 0 to 1, not distances, and the order.")
        }
    }

    /// "12 frames, focus 0.12 to 0.80": the countdown card's detail.
    ///
    /// - Parameter settings: The bracket.
    static func countdownDetail(_ settings: FocusBracketSettings) -> String {
        String(localized: "\(settings.frameCount) frames, focus \(position(settings.nearest)) to \(position(settings.farthest))", bundle: .module, comment: "Focus bracket card while the start delay counts down, second line: the number of frames and the focus positions, on the lens's own scale from 0 to 1.")
    }

    /// "Nearest: 0.12" or "Farthest: 0.80": a card button's visible text.
    ///
    /// - Parameters:
    ///   - end: The end.
    ///   - value: Its position.
    static func button(_ end: FocusRangeEnd, value: Double) -> Text {
        switch end {
        case .nearest: Text("Nearest: \(position(value))", bundle: .module, comment: "Button on the focus bracket card: sets the nearest focus position on the picture. The value is a position from 0 to 1.")
        case .farthest: Text("Farthest: \(position(value))", bundle: .module, comment: "Button on the focus bracket card: sets the farthest focus position on the picture. The value is a position from 0 to 1.")
        }
    }

    /// The dial's hint.
    ///
    /// - Parameter end: The end being set.
    static func hint(_ end: FocusRangeEnd) -> Text {
        switch end {
        case .nearest: Text("Tap the nearest thing you want sharp, or move the slider.", bundle: .module, comment: "Hint on the focus dial when setting the nearest focus of a focus bracket.")
        case .farthest: Text("Tap the farthest thing you want sharp, or move the slider.", bundle: .module, comment: "Hint on the focus dial when setting the farthest focus of a focus bracket.")
        }
    }

    /// The dial's Set button.
    ///
    /// - Parameter end: The end being set.
    static func set(_ end: FocusRangeEnd) -> Text {
        switch end {
        case .nearest: Text("Set Nearest Focus", bundle: .module, comment: "Button on the focus dial: keeps the position as the focus bracket's nearest focus.")
        case .farthest: Text("Set Farthest Focus", bundle: .module, comment: "Button on the focus dial: keeps the position as the focus bracket's farthest focus.")
        }
    }

    /// "Frame 4 of 12": the running card's title, and the announcement at each frame.
    ///
    /// - Parameters:
    ///   - number: The frame being taken.
    ///   - total: The frames in the bracket.
    static func frame(_ number: Int, of total: Int) -> String {
        String(localized: "Frame \(number) of \(total)", bundle: .module, comment: "Focus bracket card while it runs, and announced to VoiceOver: the frame being taken, of how many.")
    }

    /// "Focus 0.31": the focus the lens reports.
    ///
    /// - Parameter position: The position.
    static func focus(_ position: Double) -> String {
        String(localized: "Focus \(FocusBracketText.position(position))", bundle: .module, comment: "Focus bracket card while it runs: the focus position the lens reports, on its own scale from 0 to 1, not a distance.")
    }

    /// "Stop Bracket".
    static var stop: Text {
        Text("Stop Bracket", bundle: .module, comment: "Button on the focus bracket card while it runs: stops after the current frame; every photo taken is kept.")
    }

    /// "Paused: 4 of 12 frames".
    ///
    /// - Parameter progress: The bracket's progress.
    static func paused(_ progress: FocusBracketProgress) -> String {
        String(localized: "Paused: \(progress.taken) of \(progress.total) frames", bundle: .module, comment: "Focus bracket card while the series is paused: the frames taken, of how many.")
    }

    /// "Continues when the camera is back".
    static var continues: Text {
        Text("Continues when the camera is back", bundle: .module, comment: "Focus bracket card while the series is paused: it goes on when the app is open and the camera runs again.")
    }

    /// Where the focus is after a bracket.
    ///
    /// - Parameter focus: Where it is.
    static func after(_ focus: FocusAfterBracket) -> String {
        switch focus {
        case .automatic:
            String(localized: "Focus is back to Auto", bundle: .module, comment: "Focus bracket card after the series: focus is automatic again.")
        case .returned(let value):
            String(localized: "Focus is back to \(position(value))", bundle: .module, comment: "Focus bracket card after the series: focus is back at the position set by hand before, from 0 to 1.")
        case .stays(let value):
            String(localized: "Focus stays at \(position(value))", bundle: .module, comment: "Focus bracket card after the series: focus stays at the last frame's position, from 0 to 1.")
        }
    }

    /// The end card's title: "12 photos saved", or "Bracket stopped: 4 of 12 photos saved".
    ///
    /// - Parameter result: How it ended.
    static func endTitle(_ result: FocusBracketResult) -> String {
        guard result.isFinished else {
            return String(
                localized: "Focus bracket stopped: %lld of %lld photos saved",
                defaultValue: "Bracket stopped: \(result.saved) of \(result.total) photos saved", bundle: .module,
                comment: "Focus bracket card when the series ended before its last frame. The first number is the photos saved, the second the frames in the bracket.")
        }
        return String(localized: "\(result.saved) photos saved", bundle: .module, comment: "Card on the camera after an exposure bracket or a burst: how many separate photos were saved to the photo library.")
    }

    /// Why the app stopped the bracket, or `nil` when the person did or it finished.
    ///
    /// - Parameter end: Why it ended.
    static func reason(_ end: BurstEnd) -> String? {
        switch end {
        case .storageFull:
            String(localized: "Storage is full.", bundle: .module, comment: "Focus bracket card: the series stopped because the next photo wouldn't fit in the device's free storage.")
        case .batteryLow:
            String(localized: "The battery is low.", bundle: .module, comment: "Focus bracket card: the series stopped because the battery is nearly empty and not charging.")
        case .cameraStopped:
            String(localized: "The camera stopped.", bundle: .module, comment: "Focus bracket card: the series stopped because the camera stopped.")
        case .stopped, .limitReached, .countReached, .failed:
            nil
        }
    }

    /// The end card's detail: the reason, where the focus is, and the frames off their plan.
    ///
    /// - Parameter result: How it ended.
    static func endDetail(_ result: FocusBracketResult) -> String {
        var lines = [reason(result.end), after(result.focusAfter)].compactMap(\.self)
        if result.offPlan > 0 {
            lines.append(String(localized: "\(result.offPlan) frames were not at their planned focus", bundle: .module, comment: "Focus bracket card after the series: how many frames the lens reported at a focus position other than the one planned. The frames are saved."))
        }
        return lines.joined(separator: "\n")
    }

    /// "Bracket, focus, 12 frames": the shutter's VoiceOver value.
    ///
    /// - Parameter settings: The bracket.
    static func shutterValue(_ settings: FocusBracketSettings) -> Text {
        Text("Bracket, focus, \(settings.frameCount) frames", bundle: .module, comment: "VoiceOver value of the shutter when one press takes a focus bracket. The number is the count of frames.")
    }

    /// The shutter's VoiceOver value while a focus bracket runs.
    static var shutterRunning: Text {
        Text("Taking a focus bracket. Press to stop.", bundle: .module, comment: "VoiceOver value of the shutter while a focus bracket runs: pressing the shutter stops it after the current frame.")
    }

    /// "Focus bracket · frame 4 of 12 · focus 0.31": the viewer's chip.
    ///
    /// - Parameters:
    ///   - place: The photo's place in its bracket.
    ///   - count: The frames in the bracket.
    static func chip(_ place: FocusFramePlace, count: Int) -> String {
        String(localized: "Focus bracket · frame \(place.number) of \(count) · focus \(position(place.reportedPosition))", bundle: .module, comment: "Chip on a photo in the Last Photo viewer: the photo is one frame of a focus bracket. The numbers are the frame and the count of frames; the last value is the focus position the lens reported, from 0 to 1.")
    }

    /// "Focus bracket, frame 4 of 12, focus 0.31.": the chip as part of a page's VoiceOver label.
    ///
    /// - Parameters:
    ///   - place: The photo's place in its bracket.
    ///   - count: The frames in the bracket.
    static func chipSpoken(_ place: FocusFramePlace, count: Int) -> String {
        String(localized: "Focus bracket, frame \(place.number) of \(count), focus \(position(place.reportedPosition)).", bundle: .module, comment: "VoiceOver, part of a photo's label in the Last Photo viewer: the photo is one frame of a focus bracket. The numbers are the frame and the count of frames; the last value is the focus position the lens reported, from 0 to 1.")
    }
}

/// The focus track: a line from the lens's closest focus (leading) to far (trailing), with a mark
/// for each frame. Marks taken are filled and marks to come are outlined, so the count never
/// depends on color; the frame being taken has a ring. Custom drawing, hidden from VoiceOver:
/// the card's words carry it (docs/design/BRACKETING.md, section 6).
struct FocusTrack: View {
    /// Each frame's position, in the order taken.
    let positions: [Double]

    /// The frames taken, or `nil` before the bracket runs (every mark is then drawn plain).
    let taken: Int?

    /// Whether Reduce Motion is on: the marks change without animation.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the track.
    ///
    /// - Parameters:
    ///   - positions: Each frame's position.
    ///   - taken: The frames taken, or `nil`.
    init(positions: [Double], taken: Int? = nil) {
        self.positions = positions
        self.taken = taken
    }

    /// The track and its two end labels.
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let middle = geometry.size.height / 2
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CameraColor(NopeColor.labelSecondary))
                        .frame(height: 2)
                    ForEach(Array(positions.enumerated()), id: \.offset) { index, position in
                        mark(index: index)
                            .position(x: position * width, y: middle)
                    }
                }
            }
            .frame(height: NopeSpace.m)
            // Positions run from the closest focus on the leading edge (section 6).
            .flipsForRightToLeftLayoutDirection(true)
            HStack {
                Text("Closest", bundle: .module, comment: "Label under the leading end of the focus bracket's track: the closest the lens focuses (position 0).")
                Spacer()
                Text("Far", bundle: .module, comment: "Label under the trailing end of the focus bracket's track: the farthest the lens focuses (position 1).")
            }
            .font(NopeFont.pill)
            .foregroundStyle(CameraColor(NopeColor.labelSecondary))
        }
        .animation(reduceMotion ? nil : .default, value: taken)
        .accessibilityHidden(true)
    }

    /// One frame's mark.
    ///
    /// - Parameter index: The frame's index in the order taken.
    @ViewBuilder
    private func mark(index: Int) -> some View {
        let isCurrent = taken == index
        let isTaken = taken.map { index < $0 } ?? true
        if isCurrent {
            Circle()
                .strokeBorder(NopeColor.label, lineWidth: 2)
                .frame(width: NopeSpace.s, height: NopeSpace.s)
        } else if isTaken {
            RoundedRectangle(cornerRadius: 1)
                .fill(NopeColor.label)
                .frame(width: 3, height: NopeSpace.s)
        } else {
            RoundedRectangle(cornerRadius: 1)
                .strokeBorder(NopeColor.label, lineWidth: 1)
                .frame(width: 5, height: NopeSpace.s)
        }
    }
}

/// The focus bracket's cards on the picture's lower edge (docs/design/BRACKETING.md, section 5,
/// "Running"; figures `bracket-focus-*`): idle, the range dial, running, paused and the end. The
/// countdown uses the exposure bracket's countdown card with the focus detail.
struct FocusBracketCard: View {
    /// The card's state: one of the focus cases of ``BracketCardState``.
    let state: BracketCardState

    /// Sends an intent to the camera.
    let send: (CameraIntent) -> Void

    /// Opens Bracket Settings.
    let openSettings: () -> Void

    /// The text size: at accessibility sizes the track is left out and the buttons are stacked.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - state: The card's state.
    ///   - send: Sends an intent.
    ///   - openSettings: Opens Bracket Settings.
    init(state: BracketCardState, send: @escaping (CameraIntent) -> Void, openSettings: @escaping () -> Void) {
        self.state = state
        self.send = send
        self.openSettings = openSettings
    }

    /// Whether the track is drawn.
    private var showsTrack: Bool {
        !dynamicTypeSize.isAccessibilitySize
    }

    /// The card.
    var body: some View {
        // The idle card covers no more than 30% of the picture on a 402 × 874 pt screen
        // (docs/design/BRACKETING.md, section 8, criterion 10), so its rows sit close.
        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
            content
        }
        .padding(.leading, NopeSpace.m)
        .padding(.trailing, NopeSpace.xs)
        .padding(.vertical, NopeSpace.xs)
        .modifier(ModeCardBackground())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ModeCard")
    }

    /// The card's rows for its state.
    @ViewBuilder
    private var content: some View {
        switch state {
        case .focusIdle(let settings):
            idle(settings)
        case .focusRange(let editing, let value):
            FocusRangeDial(editing: editing, value: value, send: send)
        case .focusRunning(let progress, let positions):
            row(title: FocusBracketText.frame(progress.frameNumber, of: progress.total), detail: progress.position.map(FocusBracketText.focus)) {
                stopButton
            }
            if showsTrack { FocusTrack(positions: positions, taken: progress.taken) }
        case .focusPaused(let progress):
            row(title: FocusBracketText.paused(progress), detail: nil, detailText: FocusBracketText.continues) {
                stopButton
            }
        case .focusEnded(let result):
            row(title: FocusBracketText.endTitle(result), detail: FocusBracketText.endDetail(result)) { EmptyView() }
        case .idle, .countdown, .taking, .saving, .saved, .focusCountdown:
            EmptyView()
        }
    }

    /// The idle card: the settings button, the track, and Nearest and Farthest.
    ///
    /// - Parameter settings: The bracket.
    @ViewBuilder
    private func idle(_ settings: FocusBracketSettings) -> some View {
        let title = FocusBracketText.summary(settings)
        let detail = FocusBracketText.range(settings)
        Button(action: openSettings) {
            HStack(spacing: NopeSpace.s) {
                ModeCardLines(title: Text(verbatim: title), detail: Text(verbatim: detail))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(NopeFont.status)
                    .foregroundStyle(CameraColor(NopeColor.labelSecondary))
                    .frame(minWidth: NopeSize.minTarget, minHeight: NopeSize.minTarget)
            }
            .contentShape(.rect)
        }
        .buttonStyle(ModeCardButtonStyle())
        .accessibilityLabel(BracketText.settings)
        .accessibilityValue(Text(verbatim: [title, detail].formatted(.list(type: .and, width: .narrow))))
        .accessibilityInputLabels([BracketText.settings, Text(verbatim: title)])
        .accessibilityIdentifier("BracketSettingsCard")
        if showsTrack { FocusTrack(positions: settings.positions.sorted()) }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NopeSpace.xs) { endButtons(settings) }
            VStack(spacing: NopeSpace.xs) { endButtons(settings) }
        }
        .padding(.trailing, NopeSpace.xxs)
    }

    /// Nearest and Farthest: each opens the dial on the picture.
    ///
    /// - Parameter settings: The bracket.
    @ViewBuilder
    private func endButtons(_ settings: FocusBracketSettings) -> some View {
        endButton(.nearest, value: settings.nearest)
        endButton(.farthest, value: settings.farthest)
    }

    /// One end's button. VoiceOver reads its name and its value.
    ///
    /// - Parameters:
    ///   - end: The end.
    ///   - value: Its position.
    private func endButton(_ end: FocusRangeEnd, value: Double) -> some View {
        Button {
            send(.bracket(.beginSettingRange(end)))
        } label: {
            FocusBracketText.button(end, value: value)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .tile))
        .accessibilityLabel(FocusBracketText.title(end))
        .accessibilityValue(Text(verbatim: FocusBracketText.position(value)))
        .accessibilityInputLabels([FocusBracketText.title(end)])
    }

    /// Stop Bracket.
    private var stopButton: some View {
        Button {
            send(.bracket(.stop))
        } label: {
            FocusBracketText.stop
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .buttonStyle(NopeCapsuleStyle(role: .destructive, isCompact: true, idleFill: .tile))
    }

    /// A title, a detail and an accessory, side by side, or stacked at accessibility sizes.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - detail: The detail, or `nil`.
    ///   - detailText: A detail as text, used when `detail` is `nil`.
    ///   - accessory: The button.
    @ViewBuilder
    private func row<Accessory: View>(
        title: String, detail: String?, detailText: Text? = nil, @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        let lines = ModeCardLines(title: Text(verbatim: title), detail: detail.map { Text(verbatim: $0) } ?? detailText)
        if dynamicTypeSize.isAccessibilitySize {
            lines
            accessory()
        } else {
            HStack(spacing: NopeSpace.s) {
                lines.frame(maxWidth: .infinity, alignment: .leading)
                accessory()
            }
        }
    }
}

/// The dial for an end of the range (figure `bracket-focus-set-nearest`): the title and value,
/// Decrease, a slider, Increase, the hint, Cancel and Set. A tap on the picture focuses there
/// once and the value follows the lens; Focus Peaking shows meanwhile. Escape cancels.
struct FocusRangeDial: View {
    /// The end being set.
    let editing: FocusRangeEditing

    /// The value shown (`CameraModel.focusRangeValue`).
    let value: Double

    /// Sends an intent.
    let send: (CameraIntent) -> Void

    /// The step of the buttons and of VoiceOver's adjustable action: 0.01.
    static let step = 0.01

    /// Creates the dial.
    ///
    /// - Parameters:
    ///   - editing: The end being set.
    ///   - value: The value shown.
    ///   - send: Sends an intent.
    init(editing: FocusRangeEditing, value: Double, send: @escaping (CameraIntent) -> Void) {
        self.editing = editing
        self.value = value
        self.send = send
    }

    /// The dial.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xs) {
            HStack {
                FocusBracketText.title(editing.end)
                    .font(NopeFont.status)
                    .foregroundStyle(NopeColor.label)
                Spacer()
                Text(verbatim: FocusBracketText.position(value))
                    .font(NopeFont.status.monospacedDigit())
                    .foregroundStyle(NopeColor.label)
            }
            .padding(.trailing, NopeSpace.xs)
            .accessibilityElement(children: .combine)
            HStack(spacing: NopeSpace.xs) {
                stepButton(by: -Self.step, systemImage: "minus", name: Text("Decrease", bundle: .module, comment: "Button on the focus dial: moves the focus position 0.01 nearer."))
                Slider(value: Binding(get: { value }, set: { send(.bracket(.setRangeValue($0))) }), in: 0...1, step: Self.step) {
                    FocusBracketText.title(editing.end)
                }
                .accessibilityValue(Text(verbatim: FocusBracketText.position(value)))
                .tint(NopeColor.label)
                stepButton(by: Self.step, systemImage: "plus", name: Text("Increase", bundle: .module, comment: "Button on the focus dial: moves the focus position 0.01 farther."))
            }
            FocusBracketText.hint(editing.end)
                .font(NopeFont.pill)
                .foregroundStyle(CameraColor(NopeColor.labelSecondary))
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NopeSpace.xs) { actions }
                VStack(spacing: NopeSpace.xs) { actions }
            }
            .padding(.trailing, NopeSpace.xxs)
        }
        .accessibilityIdentifier("FocusRangeDial")
    }

    /// Cancel and Set.
    @ViewBuilder
    private var actions: some View {
        Button {
            send(.bracket(.finishSettingRange(keeps: false)))
        } label: {
            Text(String(localized: "Focus dial: Cancel", defaultValue: "Cancel", bundle: .module, comment: "Button on the focus dial: leaves the focus bracket's range as it was."))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .tile))
        .keyboardShortcut(.cancelAction)
        Button {
            send(.bracket(.finishSettingRange(keeps: true)))
        } label: {
            FocusBracketText.set(editing.end)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NopeCapsuleStyle(isSelected: true, isCompact: true, idleFill: .tile))
    }

    /// Decrease or Increase.
    ///
    /// - Parameters:
    ///   - step: The change.
    ///   - systemImage: The symbol.
    ///   - name: The button's name.
    private func stepButton(by step: Double, systemImage: String, name: Text) -> some View {
        Button {
            send(.bracket(.setRangeValue(value + step)))
        } label: {
            Image(systemName: systemImage)
                .frame(minWidth: NopeSize.minTarget, minHeight: NopeSize.minTarget)
        }
        .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .tile))
        .accessibilityLabel(name)
    }
}

/// The focus sections of Bracket Settings (figure `bracket-focus-settings`): the range, Frames,
/// Focus Step and Order, Start Delay and Return Focus When Done, Storage, at Most, and the
/// advice and Honesty sentences. Closest Focus of This Lens is not shown: it appears only for a
/// lens confirmed by device check D5, and none is yet (docs/design/BRACKETING.md, decision 11).
struct FocusBracketSections: View {
    /// The camera model.
    let model: CameraModel

    /// Closes the sheet and starts setting an end of the range on the picture.
    let setOnThePicture: (FocusRangeEnd) -> Void

    /// Creates the sections.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - setOnThePicture: Closes the sheet and opens the dial for an end.
    init(model: CameraModel, setOnThePicture: @escaping (FocusRangeEnd) -> Void) {
        self.model = model
        self.setOnThePicture = setOnThePicture
    }

    /// The bracket shown.
    private var settings: FocusBracketSettings {
        model.bracketing.focus
    }

    /// The sections.
    var body: some View {
        Section {
            endRow(.nearest, value: settings.nearest)
            endRow(.farthest, value: settings.farthest)
            // Never disabled or dimmed: with the whole range already in use it shows a check mark
            // and is selected, as the selected choice of a picker is, and pressing it changes
            // nothing (docs/design/device-feedback-1.0.md, section 2; tokens.md, "Button types").
            Button {
                send(.bracket(.useWholeRange))
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Use the Whole Range", bundle: .module, comment: "Button in Bracket Settings: sets the focus bracket's range back to 0 to 1.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if settings.isWholeRange {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityAddTraits(settings.isWholeRange ? .isSelected : [])
            .accessibilityValue(
                settings.isWholeRange
                    ? Text("In use", bundle: .module, comment: "VoiceOver value of Use the Whole Range in Bracket Settings while the focus bracket already covers the whole range, 0 to 1.")
                    : Text(verbatim: ""))
            .accessibilityIdentifier("useWholeRange")
        } header: {
            Text("Focus Range", bundle: .module, comment: "Section header in Bracket Settings: the nearest and farthest focus of a focus bracket.")
        }
        Section {
            Picker(selection: Binding(get: { settings.frameCount }, set: { send(.bracket(.setFocus(settings.with(frameCount: $0)))) })) {
                ForEach(FocusBracketSettings.frameCounts, id: \.self) { count in
                    Text(verbatim: count.formatted()).tag(count)
                }
            } label: {
                Text("Frames", bundle: .module, comment: "Picker for how many photos one bracket takes.")
            }
            .pickerStyle(.navigationLink)
            LabeledContent {
                Text(verbatim: FocusBracketText.position(settings.step))
            } label: {
                Text("Focus Step", bundle: .module, comment: "Row in Bracket Settings: the difference between neighboring frames of a focus bracket, on the lens's own scale from 0 to 1.")
            }
            Picker(selection: Binding(get: { settings.order }, set: { send(.bracket(.setFocus(settings.with(order: $0)))) })) {
                Text("Nearest First", bundle: .module, comment: "Choice of the focus bracket's Order: the nearest focus first.").tag(FocusBracketOrder.nearestFirst)
                Text("Farthest First", bundle: .module, comment: "Choice of the focus bracket's Order: the farthest focus first.").tag(FocusBracketOrder.farthestFirst)
            } label: {
                Text("Order", bundle: .module, comment: "Picker in Bracket Settings, and a setting of the Take Bracket action: the order in which the frames are taken.")
            }
            .pickerStyle(.navigationLink)
        } footer: {
            Text("Even steps on this lens’s own focus scale, from 0 (its closest focus) to 1 (far). iPhone doesn’t report focus as a distance, so nope. shows none.", tableName: "Honesty", bundle: .module, comment: "Footer under Focus Step in Bracket Settings. Keep \"nope.\" unchanged: it is the app's name. Must not claim more than the English: no distance is shown or known.")
        }
        Section {
            Picker(selection: Binding(get: { model.bracketing.focusStartDelay }, set: { send(.bracket(.setFocusStartDelay($0))) })) {
                Text(String(localized: "Start Delay: Off", defaultValue: "Off", bundle: .module, comment: "Choice of Start Delay in Bracket Settings: the bracket is taken at once."))
                    .tag(SelfTimerDelay?.none)
                ForEach(SelfTimerDelay.allCases, id: \.self) { delay in
                    Text(verbatim: DriveText.spokenSeconds(delay.seconds)).tag(SelfTimerDelay?.some(delay))
                }
            } label: {
                Text("Start Delay", bundle: .module, comment: "Picker in the night sky helper's settings: how long the self-timer waits before the first frame, so touching the phone doesn't shake it.")
            }
            .pickerStyle(.navigationLink)
            Toggle(isOn: Binding(get: { settings.returnsFocus }, set: { send(.bracket(.setFocus(settings.with(returnsFocus: $0)))) })) {
                Text("Return Focus When Done", bundle: .module, comment: "Switch in Bracket Settings: after a focus bracket, focus goes back to automatic or to the position set by hand before.")
            }
        } footer: {
            Text("Exposure and white balance are locked at the first frame, so every frame matches.", bundle: .module, comment: "Footer in Bracket Settings for a focus bracket.")
        }
        if let bytes = model.focusBracketStorageBytes {
            Section {
                LabeledContent {
                    Text(verbatim: bytes.formatted(.byteCount(style: .file)))
                } label: {
                    Text("Storage, at Most", bundle: .module, comment: "Row in the night sky helper's settings: the most storage all frames can take, an upper estimate.")
                }
            }
        }
        Section {
            Text("Use a tripod. Nothing in the picture should move between frames.", bundle: .module, comment: "Advice in Bracket Settings for a focus bracket.")
            Text("Each frame is a separate single-frame photo. Nothing is merged. Stack them in other software.", tableName: "Honesty", bundle: .module, comment: "Explains focus bracketing in Bracket Settings. Must not claim more than the English: the photos are never combined by the app.")
        }
    }

    /// A row for an end of the range: its name, "Set on the picture", its value; it closes the
    /// sheet and opens the dial.
    ///
    /// - Parameters:
    ///   - end: The end.
    ///   - value: Its position.
    private func endRow(_ end: FocusRangeEnd, value: Double) -> some View {
        Button {
            setOnThePicture(end)
        } label: {
            LabeledContent {
                Text(verbatim: FocusBracketText.position(value))
            } label: {
                FocusBracketText.title(end)
                Text("Set on the picture", bundle: .module, comment: "Under Nearest Focus and Farthest Focus in Bracket Settings: the row closes the sheet and the end is set on the camera's picture.")
            }
        }
        .foregroundStyle(.primary)
        .accessibilityInputLabels([FocusBracketText.title(end)])
    }

    /// Sends an intent to the camera.
    ///
    /// - Parameter intent: The intent.
    private func send(_ intent: CameraIntent) {
        let model = model
        Task { await model.send(intent) }
    }
}

/// The focus rows of the Bracket group of What's in This Photo (figure `bracket-focus-details`):
/// Focus as the lens reported it, Planned Focus and The Bracket.
struct FocusBracketDetailRows: View {
    /// The photo's place in its focus bracket.
    let place: FocusFramePlace

    /// Creates the rows.
    ///
    /// - Parameter place: The place.
    init(place: FocusFramePlace) {
        self.place = place
    }

    /// The rows.
    var body: some View {
        DetailRow(
            title: Text(String(localized: "Bracket details: Focus", defaultValue: "Focus", bundle: .module, comment: "Row in the photo details of a focus bracket's frame: the focus position the lens reported, from 0 to 1.")),
            value: Text(verbatim: FocusBracketText.position(place.reportedPosition)),
            note: Text("Reported by the lens", bundle: .module, comment: "Note under the Focus row in the photo details of a focus bracket's frame."))
        DetailRow(
            title: Text("Planned Focus", bundle: .module, comment: "Row in the photo details of a focus bracket's frame: the focus position the app asked the lens for, from 0 to 1."),
            value: Text(verbatim: FocusBracketText.position(place.plannedPosition)))
        DetailRow(
            title: Text("The Bracket", bundle: .module, comment: "Row in the photo details of a bracket's frame: every frame's exposure offset, and their order."),
            value: Text(verbatim: FocusBracketText.range(
                FocusBracketSettings(
                    nearest: place.positions.min() ?? 0, farthest: place.positions.max() ?? 1,
                    frameCount: place.positions.count, order: place.order))))
    }
}
