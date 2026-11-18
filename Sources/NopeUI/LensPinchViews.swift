import NopeCore
import SwiftUI

extension EnvironmentValues {
    /// How long, in seconds, the lens label of a pinch stays on the picture after the fingers
    /// lift: `LensPinchSwitcher.labelSeconds` (0.8 s). The app's UI tests lengthen it, so the
    /// accessibility audit can run with the label showing.
    @Entry public var lensPinchLabelSeconds = LensPinchSwitcher.labelSeconds
}

/// A pinch on the viewfinder that switches lenses (issue #95; docs/design/pinch-lens.md): what the
/// camera screen keeps while the fingers move, and the lens it shows.
///
/// Each step sets the target lens at once: the label on the picture, the lens row and the tick
/// follow the fingers. The camera is asked to switch when the fingers lift, or when the target
/// hasn't changed for `LensPinchSwitcher.settleSeconds`, through `LensPinchSwitcher`, so only
/// the latest target is sent and the camera's own rule for a lens change applies (issue #96).
/// The picture itself is never scaled, cropped or animated: the app has no digital zoom.
@MainActor
@Observable
final class ViewfinderPinch {
    /// The lens the pinch shows: on the label and in the lens row. `nil` before the first step
    /// and once the label has gone.
    private(set) var shownLens: Lens?

    /// The pinch in progress, or `nil` between pinches and after one was ignored.
    private var pinch: LensPinch?

    /// Whether the current touch was ignored at its start, so it stays ignored to its end.
    private var isIgnoringTouch = false

    /// Sends settled targets to the camera; made for the first pinch.
    private var switcher: LensPinchSwitcher?

    /// The wait before the latest target is sent during a pinch.
    private var settleTask: Task<Void, Never>?

    /// The wait before the label goes after the fingers lift.
    private var hideTask: Task<Void, Never>?

    /// Creates an idle pinch.
    init() {}

    /// Follows the fingers.
    ///
    /// The first change of a touch starts the pinch on the lens in use, if a pinch switches
    /// lenses now (`isAvailable`); otherwise the whole touch is ignored. A pinch that becomes
    /// unavailable while the fingers move, such as when a photo starts, is cancelled.
    ///
    /// - Parameters:
    ///   - scale: The pinch's scale, 1 when the fingers landed.
    ///   - model: The camera.
    ///   - isAvailable: Whether a pinch switches lenses now: the camera's rule
    ///     (`CameraModel.pinchSwitchesLenses(setting:)`) and nothing open over the picture.
    func change(scale: Double, model: CameraModel, isAvailable: Bool) {
        guard !isIgnoringTouch else { return }
        guard isAvailable else {
            cancel()
            isIgnoringTouch = true
            return
        }
        if pinch == nil {
            guard let started = LensPinch(lenses: model.capabilities?.lenses ?? [], startingAt: model.selectedLensID) else {
                isIgnoringTouch = true
                return
            }
            pinch = started
            hideTask?.cancel()
        }
        guard var pinch else { return }
        let before = pinch.target
        let target = pinch.update(scale: scale)
        self.pinch = pinch
        // Nothing is shown before the first step; after it, the label stays to the end.
        guard shownLens != nil || pinch.step != 0 else { return }
        shownLens = target
        guard target != before else { return }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LensPinchSwitcher.settleSeconds))
            guard !Task.isCancelled else { return }
            await self?.send(target, model: model)
        }
    }

    /// Ends the pinch when the fingers lift: the lens shown is sent at once, and the label goes
    /// after `labelSeconds`.
    ///
    /// - Parameters:
    ///   - model: The camera.
    ///   - labelSeconds: How long the label stays, `LensPinchSwitcher.labelSeconds` in the app.
    func end(model: CameraModel, labelSeconds: Double = LensPinchSwitcher.labelSeconds) {
        defer { isIgnoringTouch = false }
        guard pinch != nil else { return }
        pinch = nil
        settleTask?.cancel()
        settleTask = nil
        guard let target = shownLens else { return }
        Task { await send(target, model: model) }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(labelSeconds))
            guard !Task.isCancelled else { return }
            self?.shownLens = nil
        }
    }

    /// Stops a pinch at once without sending anything more, and removes the label: the camera
    /// became busy, or something opened over the picture.
    func cancel() {
        pinch = nil
        settleTask?.cancel()
        settleTask = nil
        hideTask?.cancel()
        hideTask = nil
        shownLens = nil
    }

    /// Sends a target to the camera through the switcher.
    ///
    /// - Parameters:
    ///   - lens: The target.
    ///   - model: The camera.
    private func send(_ lens: Lens, model: CameraModel) async {
        let switcher = switcher ?? LensPinchSwitcher(model: model)
        self.switcher = switcher
        await switcher.settle(on: lens.id)
    }
}

/// The lens a pinch has reached, in the middle of the picture (docs/design/pinch-lens.md,
/// section 4): the lens button's own text ("0.5×", "1×", "5×") with the lens's name under it, and
/// "No RAW" where the lens button says so. White on the dark backing with the large radius,
/// upright when the iPhone is held sideways, red on black in night mode through the camera's
/// night mode filter. It fades in at the first step and out after the fingers lift; nothing else
/// moves.
struct LensPinchLabel: View {
    /// The lens to show, or `nil` for none.
    let lens: Lens?

    /// Creates the label.
    ///
    /// - Parameter lens: The lens a pinch has reached, or `nil`.
    init(lens: Lens?) {
        self.lens = lens
    }

    /// The label, or nothing.
    var body: some View {
        ZStack {
            if let lens {
                VStack(spacing: NopeSpace.xxs) {
                    if let magnification = LensPinchLabel.magnification(of: lens) {
                        Text(verbatim: magnification)
                            .font(NopeFont.dialValue)
                    }
                    Text(verbatim: LensName.string(for: lens.kind))
                        .font(NopeFont.status)
                    if !lens.supportsBayerRAW {
                        Text("No RAW", tableName: "Honesty", bundle: .module, comment: "Under a lens button: this lens can't save RAW. RAW is a file format name.")
                            .font(NopeFont.readoutMode)
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize()
                .foregroundStyle(NopeColor.label)
                .padding(.horizontal, NopeSpace.m)
                .padding(.vertical, NopeSpace.xs)
                .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.large))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("lensPinchLabel")
                .uprightUnit()
                .transition(.opacity)
            }
        }
        .animation(NopeMotion.fade, value: lens?.id)
        .allowsHitTesting(false)
    }

    /// "0.5×", "1×", "5×", as the lens button shows it, or `nil` for a lens without a
    /// magnification, whose name is enough.
    ///
    /// - Parameter lens: The lens.
    static func magnification(of lens: Lens) -> String? {
        lens.magnification.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "×" }
    }
}

/// The words of the Pinch setting (docs/design/pinch-lens.md, 7.2). Visible text never says
/// "zoom": the app has no digital zoom, and a pinch only chooses between the cameras.
enum PinchText {
    /// A value's name: "Switch Lenses" or "Off".
    ///
    /// - Parameter action: The value.
    static func name(_ action: PinchAction) -> Text {
        switch action {
        case .switchLenses:
            Text("Switch Lenses", bundle: .module, comment: "Value of the Pinch setting: a pinch on the camera picture moves to the next longer or wider rear lens. Not a zoom.")
        case .off:
            Text(String(localized: "Pinch: Off", defaultValue: "Off", bundle: .module, comment: "Value of the Pinch setting: a pinch on the camera picture does nothing."))
        }
    }

    /// What the setting does.
    static var explanation: Text {
        Text(
            "Spread two fingers on the picture for the next longer lens, or pinch for the next wider one. nope. never enlarges or crops the picture.",
            tableName: "Honesty", bundle: .module,
            comment: "Explains the Pinch setting. Longer and wider describe the phone's separate rear lenses, not a zoom range; never translate as zoom. Keep \"nope.\" unchanged. Must not claim more than the English: the photo and the picture on screen are never enlarged or cropped by a pinch.")
    }

    /// Where the setting is used, a line of its own under the explanation.
    static var scopeNote: Text {
        Text(
            "Used only on the rear cameras. Not used in Astro, while photos are being taken, or at the largest text sizes.",
            tableName: "Honesty", bundle: .module,
            comment: "Note under the Pinch setting: when a pinch switches lenses. Astro is the name of nope.'s night sky mode; use its translation. Must not claim more than the English.")
    }
}

/// The Pinch row of Settings › Camera: a menu on its row with Switch Lenses and Off, its
/// explanation and its scope note under its name (docs/design/pinch-lens.md, 7.1). Shown only on a
/// device with two or more rear lenses.
struct PinchSettingRow: View {
    /// The settings.
    let settings: NopeSettings

    /// Creates the row.
    ///
    /// - Parameter settings: The settings.
    init(settings: NopeSettings) {
        self.settings = settings
    }

    /// The menu with its label.
    var body: some View {
        Picker(selection: Binding(get: { settings.pinch }, set: { settings.setPinch($0) })) {
            ForEach(PinchAction.allCases, id: \.self) { action in
                PinchText.name(action).tag(action)
            }
        } label: {
            VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                Text(SettingsText.pinch)
                Group {
                    PinchText.explanation
                    PinchText.scopeNote
                }
                .font(.footnote)
                .foregroundStyle(CameraStyle.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .pickerStyle(.menu)
        .settingsContainerRow(.pinch)
    }
}
