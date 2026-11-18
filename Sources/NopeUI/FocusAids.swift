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

/// The focus square at the tapped point, with the lock button under it (issue #68: "AE/AF lock
/// (lock pill after tap to focus)"). The square is 2 points white with a dark outline, so it
/// shows on any scene. It isn't drawn while the magnifier is on, where the whole picture is the
/// focus point.
struct FocusSquareLayer: View {
    /// The side of the square, in points.
    static var side: CGFloat { NopeSize.focusSquare }

    /// The camera model.
    let model: CameraModel

    /// Creates the layer.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - part: The square or the lock button.
    init(model: CameraModel, part: Part) {
        self.model = model
        self.part = part
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
                if let target = model.manual.focusTarget, !model.isMagnifying {
                    square
                        .position(x: target.viewfinderPoint.x * proxy.size.width, y: target.viewfinderPoint.y * proxy.size.height)
                }
            }
            .allowsHitTesting(false)
        case .lockButton:
            lockButton
        }
    }

    /// The lock button under the square, kept inside the picture.
    private var lockButton: some View {
        GeometryReader { proxy in
            if let target = model.manual.focusTarget, !model.isMagnifying {
                let x = target.viewfinderPoint.x * proxy.size.width
                let y = target.viewfinderPoint.y * proxy.size.height
                FocusLockButton(isLocked: target.isLocked) {
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
            }
        }
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

    /// Locks or unlocks.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - isLocked: Whether focus and exposure are locked.
    ///   - action: Locks or unlocks.
    init(isLocked: Bool, action: @escaping () -> Void) {
        self.isLocked = isLocked
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
        .buttonStyle(NopePillStyle(isOnPicture: true))
        .accessibilityLabel(isLocked ? FocusText.unlock : FocusText.lock)
        .accessibilityInputLabels(isLocked ? [FocusText.unlock, Text(verbatim: "AE/AF")] : [FocusText.lock])
        .accessibilityShowsLargeContentViewer()
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

/// The touches on the viewfinder: tap to focus and expose, press and hold to lock, and a long
/// vertical swipe for clean view. One gesture tells them apart, so a tap never also counts as a
/// swipe. Every one of them also has a button: the lock button, the Hide Controls tray item and
/// Show Controls (issue #68, "Gestures always have a button").
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

    /// The pending hold, cancelled when the finger moves or lifts.
    @State private var holdTask: Task<Void, Never>?

    /// Whether the current touch already locked.
    @State private var didHold = false

    /// Creates the touch handling.
    ///
    /// - Parameters:
    ///   - allowsDrags: Whether the swipe and hold are on.
    ///   - tap: Called with the tapped location.
    ///   - hold: Called with the held location.
    ///   - swipe: Called with the swipe's vertical distance.
    init(
        allowsDrags: Bool, tap: @escaping (CGPoint) -> Void, hold: @escaping (CGPoint) -> Void,
        swipe: @escaping (CGFloat) -> Void
    ) {
        self.allowsDrags = allowsDrags
        self.tap = tap
        self.hold = hold
        self.swipe = swipe
    }

    /// The content with its gestures.
    ///
    /// - Parameter content: The viewfinder.
    func body(content: Content) -> some View {
        if allowsDrags {
            content.gesture(touch)
        } else {
            content.gesture(SpatialTapGesture().onEnded { tap($0.location) })
        }
    }

    /// The one gesture for tap, hold and swipe.
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if distance(value.translation) > Self.tapSlop {
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
                guard !didHold else { return }
                let translation = value.translation
                if abs(translation.height) >= Self.swipeDistance, abs(translation.height) > abs(translation.width) {
                    swipe(translation.height)
                } else if distance(translation) <= Self.tapSlop {
                    tap(value.location)
                }
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
        if model.manual.showsSteadyHint {
            HintLabel(
                systemImage: "hand.raised",
                text: String(
                    localized: "Hold it steady or use a tripod.", bundle: .module,
                    comment: "Hint on the camera when the light is too low for a shutter that is safe to hold by hand, or the manual shutter is that slow."))
        }
        if let lens = model.closeUpLens {
            CloseUpSuggestion(model: model, lens: lens)
        }
        ComparisonHint(model: model)
    }
}

/// One hint: a symbol and a sentence on a dark backing, announced when it appears.
struct HintLabel: View {
    /// The SF Symbol.
    let systemImage: String

    /// The sentence.
    let text: String

    /// Creates a hint.
    ///
    /// - Parameters:
    ///   - systemImage: The SF Symbol.
    ///   - text: The sentence.
    init(systemImage: String, text: String) {
        self.systemImage = systemImage
        self.text = text
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
        .onAppear { AccessibilityNotification.Announcement(text).post() }
    }
}

/// "The subject may be too close to focus." with a button that switches to the ultra wide lens
/// and one that dismisses the suggestion. The app never switches by itself.
struct CloseUpSuggestion: View {
    /// The camera model.
    let model: CameraModel

    /// The lens to suggest.
    let lens: Lens

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
            HStack(spacing: NopeSpace.xs) {
                Button {
                    let model = model
                    let id = lens.id
                    Task { await model.send(.selectLens(id)) }
                } label: {
                    Text("Switch to \(LensName.string(for: lens.kind))", bundle: .module, comment: "Button in the close-up hint: switches to the suggested lens. The value is a lens name such as Ultra Wide.")
                }
                .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .tile))
                Button {
                    let model = model
                    Task { await model.send(.auto(.dismissCloseUpSuggestion)) }
                } label: {
                    Text("Dismiss", bundle: .module, comment: "Button that closes the message about a photo that wasn't taken or saved.")
                }
                .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .tile))
            }
        }
        .foregroundStyle(NopeColor.label)
        .padding(NopeSpace.s)
        .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.small))
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement(text).post() }
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
struct FastShutterSettingsView: View {
    /// The person's settings.
    let settings: NopeSettings

    /// Creates the screen.
    ///
    /// - Parameter settings: The person's settings.
    init(settings: NopeSettings) {
        self.settings = settings
    }

    /// The picker and the explanation.
    var body: some View {
        Form {
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
            // A row rather than a section footer, as on the Look screen, so it follows Dynamic Type.
            Section {
                Text(
                    "In full auto, the camera prefers the fastest shutter that still exposes well, so photos blur less. Standard aims for a speed you can hold by hand. Manual controls are never changed.",
                    bundle: .module, comment: "Explains the Fast Shutter setting.")
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
            FastShutterSettingsView(settings: settings)
        } label: {
            LabeledContent {
                FastShutterText.name(settings.fastShutter)
            } label: {
                FastShutterText.title
            }
        }
    }
}
