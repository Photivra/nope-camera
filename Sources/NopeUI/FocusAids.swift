import NopeCore
import SwiftUI

/// The focus magnifier's settings (issue #51): the viewfinder drawn larger around the focus
/// point, for checking focus. Preview only: the photo and the camera's zoom stay unchanged.
enum FocusMagnifier {
    /// How much larger the magnifier draws the viewfinder.
    static var scale: Double { 3 }

    /// The point the magnifier is centered on: the tapped point, or the center.
    ///
    /// - Parameter target: The focus target, or `nil`.
    static func anchor(for target: FocusTarget?) -> FramePoint {
        target?.viewfinderPoint ?? .center
    }
}

extension View {
    /// Draws the view enlarged around the magnifier's point while the focus magnifier is on.
    /// The ready camera applies it to the picture and focus peaking, and ``CameraScreen`` to the
    /// live viewfinder it draws behind the interface, so all three stay aligned. The layout frame doesn't change, so the caller clips it.
    ///
    /// - Parameter model: The camera model.
    func focusMagnified(_ model: CameraModel) -> some View {
        let anchor = FocusMagnifier.anchor(for: model.manual.focusTarget)
        return scaleEffect(
            model.isMagnifying ? FocusMagnifier.scale : 1, anchor: UnitPoint(x: anchor.x, y: anchor.y))
    }
}

/// When the focus square and Lock show (docs/design/device-feedback-1.0.md, section 5): from a
/// tap for ``NopeMotion/focusAidLinger``, then they fade together. Where the camera focuses and
/// exposes doesn't change; only the drawing leaves. A locked square never fades, and nothing
/// fades while it is held: VoiceOver or Switch Control on, a finger on Lock, Lock with the
/// keyboard's focus, or the scrolling layout, where touch and hold isn't available.
struct FocusAidLinger: Equatable {
    /// When the clock started: at the last tap, the last change of the target, or when what
    /// held the aids ended. `nil` before any.
    private(set) var start: ContinuousClock.Instant?

    /// Creates a clock that hasn't started.
    init() {}

    /// Starts the clock again.
    ///
    /// - Parameter time: The time now.
    mutating func restart(at time: ContinuousClock.Instant) {
        start = time
    }

    /// Whether the square and Lock show.
    ///
    /// - Parameters:
    ///   - target: The focus target, or `nil` (nothing to show).
    ///   - time: The time now.
    ///   - isHeld: Whether something holds them: VoiceOver or Switch Control on, Lock pressed or
    ///     focused, or the scrolling layout.
    /// - Returns: `true` while locked or held, and for ``NopeMotion/focusAidLinger`` after the
    ///   clock started; `false` without a target.
    func isShown(target: FocusTarget?, at time: ContinuousClock.Instant, isHeld: Bool) -> Bool {
        guard let target else { return false }
        if target.isLocked || isHeld { return true }
        guard let start else { return true }
        return time - start < NopeMotion.focusAidLinger
    }

    /// How long until the aids fade, or `nil` when the clock hasn't started or has run out.
    ///
    /// - Parameter time: The time now.
    /// - Returns: The time left.
    func remaining(at time: ContinuousClock.Instant) -> Duration? {
        guard let start else { return nil }
        let remaining = NopeMotion.focusAidLinger - (time - start)
        return remaining > .zero ? remaining : nil
    }
}

/// The focus square at the tapped point, with the lock button under it (issue #68: "AE/AF lock
/// (lock pill after tap to focus)"). The square is 2 points white with a dark outline, so it
/// shows on any scene. It isn't drawn while the magnifier is on, where the whole picture is the
/// focus point.
struct FocusSquareLayer: View {
    /// The side of the square, in points.
    static var side: CGFloat { NopeSize.focusSquare }

    /// The camera model.
    let model: CameraModel

    /// Whether the square and Lock show now (``FocusAidLinger``); they fade when it turns
    /// `false`, and Lock takes no press from then.
    let isShown: Bool

    /// Called with `true` while Lock is pressed or has the keyboard's focus, which holds the
    /// fade, and `false` when that ends.
    let holdChanged: (Bool) -> Void

    /// Creates the layer.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - part: The square or the lock button.
    ///   - isShown: Whether the square and Lock show now. Defaults to `true`.
    ///   - holdChanged: Called when Lock starts or stops holding the fade.
    init(model: CameraModel, part: Part, isShown: Bool = true, holdChanged: @escaping (Bool) -> Void = { _ in }) {
        self.model = model
        self.part = part
        self.isShown = isShown
        self.holdChanged = holdChanged
    }

    /// Whether this layer draws the square, which the viewfinder element contains (so VoiceOver
    /// reads it as part of the picture), or the lock button, which is its own element.
    let part: Part

    /// The two parts of the layer.
    enum Part {
        /// The square, drawn inside the viewfinder's accessibility element.
        case square
        /// The lock button.
        case lockButton
    }

    /// The square or the button, or nothing.
    var body: some View {
        switch part {
        case .square:
            GeometryReader { proxy in
                if let target = model.manual.focusTarget, !model.isMagnifying, isShown {
                    square
                        .position(x: target.viewfinderPoint.x * proxy.size.width, y: target.viewfinderPoint.y * proxy.size.height)
                        .transition(.opacity)
                }
            }
            .animation(NopeMotion.fade, value: isShown)
            .allowsHitTesting(false)
        case .lockButton:
            lockButton
        }
    }

    /// The lock button under the square, kept inside the picture.
    private var lockButton: some View {
        GeometryReader { proxy in
            // Faded, Lock leaves the view: gone for VoiceOver and the tests, with no press from
            // the start of the fade (the viewfinder keeps its Lock Focus and Exposure action).
            if let target = model.manual.focusTarget, !model.isMagnifying, isShown {
                let x = target.viewfinderPoint.x * proxy.size.width
                let y = target.viewfinderPoint.y * proxy.size.height
                FocusLockButton(isLocked: target.isLocked, holdChanged: holdChanged) {
                    let model = model
                    Task {
                        await model.send(.auto(target.isLocked ? .unlockFocusAndExposure : .lockFocusAndExposure(at: nil)))
                    }
                }
                // Kept inside the picture, below the square, or above it near the bottom edge.
                .position(
                    x: min(max(x, Self.side), max(proxy.size.width - Self.side, Self.side)),
                    y: y + Self.side < proxy.size.height - NopeSize.minTarget
                        ? y + Self.side : max(y - Self.side, NopeSize.minTarget / 2))
                .transition(.opacity)
            }
        }
        .animation(NopeMotion.fade, value: isShown)
    }

    /// The square: white with a dark edge on both sides.
    private var square: some View {
        Rectangle()
            .strokeBorder(Color.black.opacity(0.7), lineWidth: 4)
            .overlay(Rectangle().inset(by: 1).strokeBorder(Color.white, lineWidth: 2))
            .frame(width: Self.side, height: Self.side)
    }
}

/// The lock button under the focus square: "Lock" after a tap, "AE/AF" with a closed lock once
/// focus and exposure are locked; pressing it locks or unlocks.
struct FocusLockButton: View {
    /// Whether focus and exposure are locked.
    let isLocked: Bool

    /// Called with `true` while the button is pressed or has the keyboard's focus, and `false`
    /// when neither holds: the fade waits meanwhile.
    let holdChanged: (Bool) -> Void

    /// Locks or unlocks.
    let action: () -> Void

    /// Whether a finger is on the button.
    @State private var isPressed = false

    /// Whether the button has the keyboard's focus (Full Keyboard Access).
    @FocusState private var isFocused: Bool

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - isLocked: Whether focus and exposure are locked.
    ///   - holdChanged: Called when the button starts or stops holding the fade.
    ///   - action: Locks or unlocks.
    init(isLocked: Bool, holdChanged: @escaping (Bool) -> Void = { _ in }, action: @escaping () -> Void) {
        self.isLocked = isLocked
        self.holdChanged = holdChanged
        self.action = action
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            Label {
                if isLocked {
                    Text(verbatim: "AE/AF")
                } else {
                    Text("Lock", bundle: .module, comment: "Button under the focus square on the camera: locks focus and exposure at the tapped point.")
                }
            } icon: {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
            }
        }
        .buttonStyle(PressReportingStyle(base: NopePillStyle(isOnPicture: true), isPressed: $isPressed))
        .focused($isFocused)
        .onChange(of: isPressed || isFocused) { _, holds in holdChanged(holds) }
        // Gone (the scene changed, the lock was released): it holds nothing any more.
        .onDisappear { holdChanged(false) }
        .accessibilityLabel(isLocked ? FocusText.unlock : FocusText.lock)
        .accessibilityInputLabels(isLocked ? [FocusText.unlock, Text(verbatim: "AE/AF")] : [FocusText.lock])
        .accessibilityShowsLargeContentViewer()
    }
}

/// A button style that draws another style and reports whether the button is pressed, for
/// Lock, whose fade waits while a finger is on it.
struct PressReportingStyle<Base: ButtonStyle>: ButtonStyle {
    /// The style that draws the button.
    let base: Base

    /// Set while the button is pressed.
    @Binding var isPressed: Bool

    /// Creates the style.
    ///
    /// - Parameters:
    ///   - base: The style that draws the button.
    ///   - isPressed: Set while the button is pressed.
    init(base: Base, isPressed: Binding<Bool>) {
        self.base = base
        _isPressed = isPressed
    }

    /// The base style's button, reporting its pressed state.
    ///
    /// - Parameter configuration: The button's label and press state.
    func makeBody(configuration: Configuration) -> some View {
        base.makeBody(configuration: configuration)
            .onChange(of: configuration.isPressed, initial: true) { _, pressed in isPressed = pressed }
    }
}

/// The words of the focus aids, shared by buttons and VoiceOver actions.
enum FocusText {
    /// "Lock Focus and Exposure".
    static var lock: Text {
        Text("Lock Focus and Exposure", bundle: .module, comment: "Button and VoiceOver action on the camera: locks focus and exposure (AE/AF lock).")
    }

    /// "Unlock Focus and Exposure".
    static var unlock: Text {
        Text("Unlock Focus and Exposure", bundle: .module, comment: "Button and VoiceOver action on the camera: returns focus and exposure to automatic.")
    }

    /// "Focus on Center".
    static var focusOnCenter: Text {
        Text("Focus on Center", bundle: .module, comment: "VoiceOver action on the viewfinder: focuses and exposes at the middle of the picture, as a tap there does.")
    }

    /// The announcement when the lock changes.
    ///
    /// - Parameter isLocked: Whether focus and exposure are now locked.
    static func announcement(isLocked: Bool) -> String {
        isLocked
            ? String(localized: "Focus and exposure locked", bundle: .module, comment: "VoiceOver announcement after focus and exposure are locked.")
            : String(localized: "Focus and exposure unlocked", bundle: .module, comment: "VoiceOver announcement after the focus and exposure lock is released.")
    }
}

/// The touches on the viewfinder: tap to focus and expose, press and hold to lock, a long
/// vertical swipe for clean view, and a pinch to switch lenses (issue #95). One gesture tells the
/// first three apart, so a tap never also counts as a swipe; the pinch runs beside it, and a touch
/// that pinched is never also a tap, a lock or a swipe. Every one of them also has a button: the
/// lock button, Hide Controls in the quick menu and Show Controls, and the lens buttons (issue
/// #68, "Gestures always have a button").
struct ViewfinderTouches: ViewModifier {
    /// How long a press must last to lock, in seconds: the system's usual long press.
    static var holdDuration: Double { 0.5 }

    /// How far a finger may move and still tap or hold, in points.
    static var tapSlop: CGFloat { 10 }

    /// The shortest vertical swipe that toggles clean view, in points.
    static var swipeDistance: CGFloat { 60 }

    /// Whether the swipe and hold are on. In the scrolling layout they would block scrolling,
    /// so only the tap remains there.
    let allowsDrags: Bool

    /// Called with the tapped location, in the view's points.
    let tap: (CGPoint) -> Void

    /// Called with the held location, in the view's points.
    let hold: (CGPoint) -> Void

    /// Called with the swipe's vertical distance: positive downward.
    let swipe: (CGFloat) -> Void

    /// Whether a pinch switches lenses now (`CameraModel.pinchSwitchesLenses(setting:)` and
    /// nothing open over the picture). Off, a pinch is ignored completely: it reports nothing,
    /// and is still no tap, hold or swipe.
    let allowsPinch: Bool

    /// Called with a pinch's scale as the fingers move: 1 when they landed.
    let pinchChanged: (Double) -> Void

    /// Called when the fingers of a pinch lift.
    let pinchEnded: () -> Void

    /// The pending hold, cancelled when the finger moves or lifts.
    @State private var holdTask: Task<Void, Never>?

    /// Whether the current touch already locked.
    @State private var didHold = false

    /// Whether the current touch pinched, so it starts no hold and its end is no tap and no
    /// swipe. Cleared once both the touch and the pinch are over, however each of them ended
    /// (the touch gesture may fail when the second finger lands, and then reports no end).
    @State private var didPinch = false

    /// Whether the touch gesture is under way; reset by SwiftUI when it ends, fails or is
    /// cancelled.
    @GestureState private var isTouching = false

    /// Whether the pinch gesture is under way; reset by SwiftUI as ``isTouching`` is.
    @GestureState private var isPinching = false

    /// The lens controls' busy state (issue #96): no pinch while the lens can't be changed.
    @Environment(\.lensBusy) private var lensBusy

    /// Creates the touch handling.
    ///
    /// - Parameters:
    ///   - allowsDrags: Whether the swipe and hold are on.
    ///   - tap: Called with the tapped location.
    ///   - hold: Called with the held location.
    ///   - swipe: Called with the swipe's vertical distance.
    ///   - allowsPinch: Whether a pinch switches lenses now. Only with `allowsDrags`.
    ///   - pinchChanged: Called with a pinch's scale as the fingers move.
    ///   - pinchEnded: Called when a pinch's fingers lift.
    init(
        allowsDrags: Bool, tap: @escaping (CGPoint) -> Void, hold: @escaping (CGPoint) -> Void,
        swipe: @escaping (CGFloat) -> Void, allowsPinch: Bool = false, pinchChanged: @escaping (Double) -> Void = { _ in },
        pinchEnded: @escaping () -> Void = {}
    ) {
        self.allowsDrags = allowsDrags
        self.tap = tap
        self.hold = hold
        self.swipe = swipe
        self.allowsPinch = allowsPinch
        self.pinchChanged = pinchChanged
        self.pinchEnded = pinchEnded
    }

    /// The content with its gestures.
    ///
    /// - Parameter content: The viewfinder.
    func body(content: Content) -> some View {
        if allowsDrags {
            content
                .gesture(touch)
                // Beside the touch gesture, so a pinch doesn't replace tap, hold and swipe. It is
                // there even while a pinch can't switch lenses, so two moving fingers are never
                // taken for a clean-view swipe (docs/design/pinch-lens.md, 6.1).
                .simultaneousGesture(pinch)
                .onChange(of: isTouching || isPinching) { _, isActive in
                    if !isActive { didPinch = false }
                }
        } else {
            content.gesture(SpatialTapGesture().onEnded { tap($0.location) })
        }
    }

    /// The one gesture for tap, hold and swipe.
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, isTouching, _ in isTouching = true }
            .onChanged { value in
                if didPinch || distance(value.translation) > Self.tapSlop {
                    holdTask?.cancel()
                    holdTask = nil
                } else if holdTask == nil, !didHold {
                    let location = value.startLocation
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(Self.holdDuration))
                        guard !Task.isCancelled else { return }
                        didHold = true
                        hold(location)
                    }
                }
            }
            .onEnded { value in
                holdTask?.cancel()
                holdTask = nil
                defer { didHold = false }
                guard !didHold, !didPinch else { return }
                let translation = value.translation
                if abs(translation.height) >= Self.swipeDistance, abs(translation.height) > abs(translation.width) {
                    swipe(translation.height)
                } else if distance(translation) <= Self.tapSlop {
                    tap(value.location)
                }
            }
    }

    /// The pinch: its scale as the fingers move apart or together. It reports from the first
    /// movement (no minimum), so the pending hold is cancelled as soon as two fingers move. It
    /// never scales the picture.
    private var pinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .updating($isPinching) { _, isPinching, _ in isPinching = true }
            .onChanged { value in
                if !didPinch {
                    didPinch = true
                    holdTask?.cancel()
                    holdTask = nil
                }
                // While the lens can't be changed (issue #96) or a pinch isn't used, nothing.
                guard allowsPinch, !lensBusy.isDisabled else { return }
                pinchChanged(value.magnification)
            }
            .onEnded { _ in
                pinchEnded()
            }
    }

    /// The length of a movement.
    ///
    /// - Parameter translation: The movement.
    private func distance(_ translation: CGSize) -> CGFloat {
        (translation.width * translation.width + translation.height * translation.height).squareRoot()
    }
}

/// Exposure compensation in full auto (issue #41): − and + steppers around a native slider over
/// thirds of a stop, within the lens's range, and Reset. The slider is adjustable with VoiceOver
/// (swipe up or down), and every step has a button for Voice Control and Switch Control.
///
/// It looks like the manual dial (``ControlDial``): on the backing with the large radius, on the
/// picture's lower edge (docs/design/BUILD-SPEC.md, 3.4).
struct AutoExposureDial: View {
    /// The camera model.
    let model: CameraModel

    /// Closes the dial.
    let close: () -> Void

    /// Creates the dial.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - close: Closes the dial.
    init(model: CameraModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
    }

    /// The compensation in use, in EV.
    private var compensation: Double { model.manual.settings.exposureCompensation }

    /// "+0.7", or "0.0".
    private var valueText: String {
        ControlText.value(compensation, of: .exposureCompensation)
    }

    /// The dial.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xs) {
            HStack(alignment: .center, spacing: NopeSpace.xs) {
                Text("Exposure", bundle: .module, comment: "Name of the exposure compensation control in full auto, in the quick-controls tray and on its dial.")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: valueText)
                    .font(NopeFont.dialValue)
                    .fixedSize()
                    .accessibilityHidden(true)
                Button(action: close) {
                    Label {
                        Text("Close Exposure", bundle: .module, comment: "Button that closes the exposure compensation dial on the camera.")
                    } icon: {
                        Image(systemName: "xmark")
                    }
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(NopeIconButtonStyle())
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(spacing: NopeSpace.xs) {
                stepButton(by: -1)
                slider
                stepButton(by: 1)
                Button {
                    send(.setExposureCompensation(0))
                } label: {
                    Text("Reset", bundle: .module, comment: "Button that returns one manual control to automatic.")
                }
                // Filled white at 0, as Auto is on the manual dial; not disabled, because a dimmed
                // button fails the contrast audit over the picture.
                .buttonStyle(NopeCapsuleStyle(isSelected: compensation == 0, isCompact: true, idleFill: .tile))
                .fixedSize()
                .accessibilityAddTraits(compensation == 0 ? .isSelected : [])
            }
        }
        .foregroundStyle(NopeColor.label)
        .padding(NopeSpace.s)
        .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.large))
        .accessibilityElement(children: .contain)
    }

    /// The slider over the lens's compensation steps.
    @ViewBuilder private var slider: some View {
        if let scale = model.manual.scale(for: .exposureCompensation), scale.values.count > 1 {
            let index = Binding<Double>(
                get: { Double(scale.nearestIndex(to: compensation)) },
                set: { position in send(.setExposureCompensation(scale.values[Int(position.rounded())])) })
            Slider(value: index, in: 0...Double(scale.values.count - 1), step: 1) {
                Text("Exposure", bundle: .module, comment: "Name of the exposure compensation control in full auto, in the quick-controls tray and on its dial.")
            }
            .accessibilityValue(Text(verbatim: valueText))
            .dialSliderTint()
        }
    }

    /// − or +: one third of a stop darker or brighter.
    ///
    /// - Parameter steps: −1 or 1.
    private func stepButton(by steps: Int) -> some View {
        Button {
            send(.stepExposureCompensation(by: steps))
        } label: {
            Label {
                steps < 0
                    ? Text("Darker", bundle: .module, comment: "Button on the exposure dial: one third of a stop darker.")
                    : Text("Brighter", bundle: .module, comment: "Button on the exposure dial: one third of a stop brighter.")
            } icon: {
                Image(systemName: steps < 0 ? "minus" : "plus")
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(NopeIconButtonStyle())
    }

    /// Sends an aid intent.
    ///
    /// - Parameter intent: The intent.
    private func send(_ intent: AutoControlIntent) {
        let model = model
        Task { await model.send(.auto(intent)) }
    }
}

/// Plain hints over the picture: "Hold it steady or use a tripod." when the shutter is slow
/// (issue #56), and the suggestion to switch to the ultra wide lens when the subject seems too
/// close to focus (issue #51). They aren't warnings about the photo, so they aren't amber. Each
/// is announced once when it appears, and stays while its cause lasts.
struct CameraHints: View {
    /// The camera model.
    let model: CameraModel

    /// Creates the hints.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The hints that apply, or nothing.
    var body: some View {
        SteadyHint(isWanted: model.showsSteadyHint)
        if let lens = model.closeUpLens {
            CloseUpSuggestion(model: model, lens: lens)
        }
        ComparisonHint(model: model)
        // What an assistant did (issue #82).
        AssistantHints(model: model)
    }
}

/// When "Hold it steady or use a tripod." shows and is announced (docs/design/device-feedback-1.0.md,
/// section 4): while its cause lasts, and at least ``minimumShown`` once shown, so it can be
/// read; VoiceOver hears it when it appears, and not again within ``announcementGap`` if it
/// returns. The minimum is the only timer, and it only keeps the hint longer.
struct SteadyHintTiming: Equatable {
    /// The shortest time the hint shows once it appears: 2 seconds.
    static let minimumShown = Duration.seconds(2)

    /// The shortest time between two announcements of the hint: 10 seconds.
    static let announcementGap = Duration.seconds(10)

    /// When the hint appeared, or `nil` while it isn't shown.
    private(set) var shownSince: ContinuousClock.Instant?

    /// When the hint was last announced, or `nil` before the first time.
    private(set) var lastAnnouncement: ContinuousClock.Instant?

    /// Creates the timing of a hint not shown yet.
    init() {}

    /// Records that the hint appears.
    ///
    /// - Parameter time: The time now.
    /// - Returns: Whether VoiceOver should announce it: the first time, and then only after
    ///   ``announcementGap`` since the last announcement.
    mutating func appear(at time: ContinuousClock.Instant) -> Bool {
        shownSince = time
        guard lastAnnouncement.map({ time - $0 >= Self.announcementGap }) ?? true else { return false }
        lastAnnouncement = time
        return true
    }

    /// How long the hint must still show once its cause has ended, or `nil` when it may go now.
    ///
    /// - Parameter time: The time now.
    /// - Returns: The time left of ``minimumShown``, or `nil`.
    func remainingMinimum(at time: ContinuousClock.Instant) -> Duration? {
        guard let shownSince else { return nil }
        let remaining = Self.minimumShown - (time - shownSince)
        return remaining > .zero ? remaining : nil
    }

    /// Records that the hint left.
    mutating func disappear() {
        shownSince = nil
    }
}

/// "Hold it steady or use a tripod.": shown while `CameraModel.showsSteadyHint` is `true`, and
/// at least ``SteadyHintTiming/minimumShown`` once shown; it leaves with ``NopeMotion/fade``.
struct SteadyHint: View {
    /// Whether the camera wants the hint now.
    let isWanted: Bool

    /// Whether the hint shows.
    @State private var isShown = false

    /// When it appeared and was announced.
    @State private var timing = SteadyHintTiming()

    /// Creates the hint.
    ///
    /// - Parameter isWanted: Whether the camera wants the hint now.
    init(isWanted: Bool) {
        self.isWanted = isWanted
    }

    /// The sentence.
    private var text: String {
        String(
            localized: "Hold it steady or use a tripod.", bundle: .module,
            comment: "Hint on the camera while Manual Controls are off and the shutter in use is slower than the lens can be held at by hand.")
    }

    /// The hint, or nothing.
    var body: some View {
        Group {
            if isShown {
                HintLabel(systemImage: "hand.raised", text: text, announces: false)
                    .transition(.opacity)
            }
        }
        .animation(NopeMotion.fade, value: isShown)
        .onChange(of: isWanted, initial: true) { _, wanted in
            guard wanted, !isShown else { return }
            isShown = true
            if timing.appear(at: .now) { AccessibilityNotification.Announcement(text).post() }
        }
        // Leaves once the cause has ended and the minimum has passed; nothing runs meanwhile.
        .task(id: isWanted) {
            guard !isWanted, isShown else { return }
            if let remaining = timing.remainingMinimum(at: .now) {
                try? await Task.sleep(for: remaining)
                guard !Task.isCancelled, !isWanted else { return }
            }
            isShown = false
            timing.disappear()
        }
    }
}

/// One hint: a symbol and a sentence on a dark backing, announced when it appears.
struct HintLabel: View {
    /// The SF Symbol.
    let systemImage: String

    /// The sentence.
    let text: String

    /// Whether the hint announces itself when it appears; `false` when its owner decides.
    let announces: Bool

    /// Creates a hint.
    ///
    /// - Parameters:
    ///   - systemImage: The SF Symbol.
    ///   - text: The sentence.
    ///   - announces: Whether it is announced when it appears. Defaults to `true`.
    init(systemImage: String, text: String, announces: Bool = true) {
        self.systemImage = systemImage
        self.text = text
        self.announces = announces
    }

    /// The hint.
    var body: some View {
        Label {
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(NopeFont.status)
        .foregroundStyle(NopeColor.label)
        .padding(.horizontal, NopeSpace.s)
        .padding(.vertical, NopeSpace.xs)
        .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.small))
        .accessibilityElement(children: .combine)
        .onAppear {
            if announces { AccessibilityNotification.Announcement(text).post() }
        }
    }
}

/// "The subject may be too close to focus." with About Close-Up Focus, which opens the Honesty
/// entry Lenses Never Switch on Their Own, a button that dismisses the suggestion and one that
/// switches to the ultra wide lens (docs/design/device-feedback-1.0.md, section 3). The app
/// never switches by itself. While the lens can't be changed (``LensBusyState``), only the switch
/// button is disabled. The buttons wrap under one another when they don't fit beside each other.
struct CloseUpSuggestion: View {
    /// The camera model.
    let model: CameraModel

    /// The lens to suggest.
    let lens: Lens

    /// Opens Settings at an item, or `nil` where Settings can't be opened.
    @Environment(\.openSettingsAt) private var openSettingsAt

    /// Creates the suggestion.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - lens: The lens to suggest.
    init(model: CameraModel, lens: Lens) {
        self.model = model
        self.lens = lens
    }

    /// The sentence.
    private var text: String {
        String(
            localized: "The subject may be too close to focus. Try \(LensName.string(for: lens.kind)).", bundle: .module,
            comment: "Hint on the camera when autofocus can't get close enough. The value is a lens name such as Ultra Wide.")
    }

    /// The name of About Close-Up Focus.
    static var aboutLabel: Text {
        Text("About Close-Up Focus", bundle: .module, comment: "Information button on the camera's close-up hint: opens the Honesty entry that explains why nope. never changes lenses for a close-up. Keep nope. unchanged if it appears. Draft for the Honesty review.")
    }

    /// The suggestion.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xs) {
            Label {
                Text(verbatim: text)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "camera.macro")
            }
            .font(NopeFont.status)
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NopeSpace.xs) {
                    aboutButton
                    Spacer(minLength: 0)
                    dismissButton
                    switchButton
                }
                VStack(alignment: .leading, spacing: NopeSpace.xs) {
                    aboutButton
                    dismissButton
                    switchButton
                }
            }
        }
        .foregroundStyle(NopeColor.label)
        .padding(NopeSpace.s)
        .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.small))
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement(text).post() }
    }

    /// Opens the Honesty entry, where Settings can be opened. Not disabled while the lens is busy.
    @ViewBuilder private var aboutButton: some View {
        if let openSettingsAt {
            Button {
                openSettingsAt(.honestyCloseUpFocus)
            } label: {
                Image(systemName: "info.circle")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(NopeIconButtonStyle(idleFill: .tile))
            .accessibilityLabel(Self.aboutLabel)
            .accessibilityShowsLargeContentViewer {
                Label {
                    Self.aboutLabel
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
            .accessibilityIdentifier("aboutCloseUpFocus")
        }
    }

    /// Hides the suggestion until the lens changes.
    private var dismissButton: some View {
        Button {
            let model = model
            Task { await model.send(.auto(.dismissCloseUpSuggestion)) }
        } label: {
            Text("Dismiss", bundle: .module, comment: "Button that closes the message about a photo that wasn't taken or saved.")
        }
        .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .tile))
    }

    /// Switches to the suggested lens: the person's choice, never the app's.
    private var switchButton: some View {
        Button {
            let model = model
            let id = lens.id
            Task { await model.send(.selectLens(id)) }
        } label: {
            Text("Switch to \(LensName.string(for: lens.kind))", bundle: .module, comment: "Button in the close-up hint: switches to the suggested lens. The value is a lens name such as Ultra Wide.")
        }
        .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .tile))
        // Disabled while the lens can't be changed; the hint itself stays (issue #96).
        .lensBusyControl()
    }
}

/// The names of the fast shutter choices.
enum FastShutterText {
    /// The name of a choice, such as "Freeze Motion (1/500 s)".
    ///
    /// - Parameter choice: The choice.
    static func name(_ choice: FastShutter) -> Text {
        switch choice {
        case .handheld:
            Text(String(localized: "Fast shutter: Standard", defaultValue: "Standard", bundle: .module, comment: "Fast shutter choice: full auto aims for a shutter fast enough to hold by hand. The default."))
        case .freezeMotion:
            Text("Freeze Motion (1/500 s)", bundle: .module, comment: "Fast shutter choice: full auto keeps the shutter at 1/500 second or faster. Keep the fraction.")
        case .freezeFastMotion:
            Text("Freeze Fast Motion (1/1000 s)", bundle: .module, comment: "Fast shutter choice: full auto keeps the shutter at 1/1000 second or faster. Keep the fraction.")
        }
    }

    /// The title of the setting and tray item: "Fast Shutter".
    static var title: Text {
        Text("Fast Shutter", bundle: .module, comment: "Setting and quick control: how fast a shutter full auto prefers, to avoid blur.")
    }

    /// Where the choice is used, the note under the Settings row and the start of the page:
    /// "Used only while Manual Controls are off." (`docs/design/SETTING-SCOPE.md`). With manual
    /// controls on, no shutter limit is sent (`ManualControlsModel.assist`), so the choice
    /// is stored but not used.
    static var scopeNote: Text {
        Text(
            "Used only while Manual Controls are off.", tableName: "Honesty", bundle: .module,
            comment: "Note under the Fast Shutter row in Settings: the choice is used only while nope.'s Manual Controls are off. Manual Controls is the name of nope.'s button; use its translation. Must not claim more than the English.")
    }
}

/// The name of the near focus limit.
enum CloseUpText {
    /// "Close-Up".
    static var title: Text {
        Text("Close-Up", bundle: .module, comment: "Quick control and pill on the camera: limits autofocus to near subjects, for small things close to the lens.")
    }
}

/// The name of the far focus limit (issue #57).
enum FarFocusText {
    /// "Far Focus".
    static var title: Text {
        Text("Far Focus", bundle: .module, comment: "Quick control and pill on the camera: limits autofocus to far subjects, such as a landscape seen past near branches.")
    }
}

/// The name of the focus magnifier.
enum MagnifierText {
    /// "Magnify".
    static var title: Text {
        Text("Magnify", bundle: .module, comment: "Quick control and pill on the camera: shows the viewfinder enlarged around the focus point, to check focus. The photo is not zoomed.")
    }
}

/// The Fast Shutter setting (issue #56): an inline picker of the choices with the explanation,
/// as the Look screen does, opened from the Camera section of Settings.
///
/// The choice is used only while Manual Controls are off (`docs/design/BUILD-SPEC.md`, 3.16).
/// While they are on, a line above the choices says the choice is not used now; the choices stay
/// enabled, because the choice is stored and used again once Manual Controls are off.
struct FastShutterSettingsView: View {
    /// The person's settings.
    let settings: NopeSettings

    /// Whether Manual Controls are on now, so the choice is not used: the camera's own state
    /// (`ManualControlsModel.isEnabled`, which Astro also turns on), or the stored option
    /// (`NopeSettings.showsManualControls`) where there is no camera.
    let manualControlsAreOn: Bool

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - settings: The person's settings.
    ///   - manualControlsAreOn: Whether Manual Controls are on now.
    init(settings: NopeSettings, manualControlsAreOn: Bool) {
        self.settings = settings
        self.manualControlsAreOn = manualControlsAreOn
    }

    /// The line while Manual Controls are on, the picker and the explanation.
    var body: some View {
        Form {
            if manualControlsAreOn {
                Section {
                    // A plain text row, as on HEIF and JPEG Copies: with the info symbol of the
                    // drawing (a Label), the audit reported the sentence as clipped, though it
                    // showed in full (iPhone 18 Pro Simulator, iOS 27.2).
                    Text(
                        "Manual Controls are on, so this choice is not used now.", tableName: "Honesty", bundle: .module,
                        comment: "First row of the Fast Shutter page in Settings while nope.'s Manual Controls are on: the choice is kept, but not used until Manual Controls are off. Manual Controls is the name of nope.'s button; use its translation. Must not claim more than the English.")
                        .accessibilityIdentifier("settings.fastShutter.notUsedNow")
                }
            }
            Section {
                Picker(selection: Binding(get: { settings.fastShutter }, set: { settings.setFastShutter($0) })) {
                    ForEach(FastShutter.allCases, id: \.self) { choice in
                        FastShutterText.name(choice).tag(choice)
                    }
                } label: {
                    FastShutterText.title
                }
                .pickerStyle(.inline)
            }
            // Rows rather than a section footer, as on the Look screen, so they follow Dynamic Type.
            Section {
                Text(
                    "Used only while Manual Controls are off. The camera keeps the shutter at least as fast as your choice while there is enough light, and uses a higher ISO to do it. In low light the shutter can be slower. Standard aims for a speed you can hold by hand.",
                    tableName: "Honesty", bundle: .module,
                    comment: "First paragraph of the Fast Shutter page in Settings. Manual Controls is the name of nope.'s button; use its translation. Standard is the name of the first choice. ISO is a standard name. Must not claim more than the English: nope. sets a limit for the camera's auto exposure, which is lifted when there isn't enough light.")
                    .font(.footnote)
                Text(
                    "With Manual Controls on, this choice is not used. A shutter you set is used as set. A shutter on Auto is chosen by the camera.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Second paragraph of the Fast Shutter page in Settings. Manual Controls is the name of nope.'s button; use its translation. \"Auto\" is the word on a manual readout; use its translation. Must not claim more than the English.")
                    .font(.footnote)
            }
        }
        .navigationTitle(FastShutterText.title)
    }

    /// A navigation row to the setting, showing the current choice.
    ///
    /// - Parameter settings: The settings.
    static func link(settings: NopeSettings) -> some View {
        NavigationLink {
            FastShutterSettingsView(settings: settings, manualControlsAreOn: settings.showsManualControls)
        } label: {
            LabeledContent {
                FastShutterText.name(settings.fastShutter)
            } label: {
                FastShutterText.title
            }
        }
    }
}
