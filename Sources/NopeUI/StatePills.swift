import NopeCore
import SwiftUI

/// What the camera screen's registries read: the camera model and the person's settings.
///
/// The quick-controls tray (``QuickControls``), the state pills (``StatePills``) and the warning
/// chips (``CameraWarnings``) build their items from it, so a new feature adds its item in one
/// place without touching the layout.
@MainActor
struct CameraControlContext {
    /// The camera model.
    let model: CameraModel

    /// The person's settings.
    let settings: NopeSettings

    /// Whether the full-auto exposure dial is open, for the Exposure tray item. The camera
    /// screen sets it; a constant `false` elsewhere.
    var showsExposureDial: Binding<Bool> = .constant(false)

    /// Creates a context.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - settings: The person's settings.
    init(model: CameraModel, settings: NopeSettings) {
        self.model = model
        self.settings = settings
    }

    /// Sends an intent to the camera model.
    ///
    /// - Parameter intent: The intent.
    func send(_ intent: CameraIntent) {
        let model = model
        Task { await model.send(intent) }
    }
}

/// One small pill at the top of the camera for a setting that isn't at its default, such as
/// "M" for manual controls or a lock (issue #68, "Non-default state"). Defaults are invisible.
///
/// A pill has a symbol and short text, so it never relies on color, and one or more actions
/// to change or reset it: one action makes the pill a button, more make it a menu.
struct StatePill: Identifiable {
    /// One thing a pill can do, such as "Unlock".
    struct Action: Identifiable {
        /// A stable identifier within the pill.
        let id: String

        /// The action's name.
        let title: Text

        /// Whether the action is destructive.
        let role: ButtonRole?

        /// Does it.
        let perform: @MainActor () -> Void

        /// Creates an action.
        ///
        /// - Parameters:
        ///   - id: A stable identifier within the pill.
        ///   - title: The action's name.
        ///   - role: Whether the action is destructive.
        ///   - perform: Does it.
        init(id: String, title: Text, role: ButtonRole? = nil, perform: @escaping @MainActor () -> Void) {
            self.id = id
            self.title = title
            self.role = role
            self.perform = perform
        }
    }

    /// A stable identifier, such as "manual".
    let id: String

    /// The SF Symbol.
    let systemImage: String

    /// The short visible text, such as "M" or "AE/AF".
    let text: Text

    /// The full name for VoiceOver and Voice Control, such as "Manual Controls".
    let label: Text

    /// What the pill can do. The first is the pill's own action when there is only one.
    let actions: [Action]

    /// The state VoiceOver reads after the name, such as "25%" for the light, or `nil`.
    let value: Text?

    /// Creates a pill.
    ///
    /// - Parameters:
    ///   - id: A stable identifier.
    ///   - systemImage: The SF Symbol.
    ///   - text: The short visible text.
    ///   - label: The full name for VoiceOver and Voice Control.
    ///   - actions: What the pill can do; at least one.
    ///   - value: The state VoiceOver reads after the name, or `nil`.
    init(id: String, systemImage: String, text: Text, label: Text, actions: [Action], value: Text? = nil) {
        self.id = id
        self.systemImage = systemImage
        self.text = text
        self.label = label
        self.actions = actions
        self.value = value
    }
}

/// The registry of state pills: each feature with a non-default state adds one function here
/// that returns its pill, or `nil` at the default.
///
/// The order of ``builders`` is the order on screen; ``StatePillRow`` shows the first
/// ``StatePillRow/maximumVisible`` and folds the rest into "+n".
@MainActor
enum StatePills {
    /// Every pill builder, in display order. Add a feature's builder here.
    static let builders: [@MainActor (CameraControlContext) -> StatePill?] = [
        light,
        flash,
        manual,
        locks,
        exposure,
        fastShutter,
        closeUp,
        magnifier,
    ]

    /// The builders whose pills stay in clean view: the light, so it can always be turned off
    /// in one tap (issue #38).
    static let cleanViewBuilders: [@MainActor (CameraControlContext) -> StatePill?] = [
        light,
    ]

    /// The pills for settings not at their defaults, in display order.
    ///
    /// - Parameter context: The model and settings.
    static func current(_ context: CameraControlContext) -> [StatePill] {
        builders.compactMap { $0(context) }
    }

    /// The pills shown in clean view, in display order.
    ///
    /// - Parameter context: The model and settings.
    static func cleanView(_ context: CameraControlContext) -> [StatePill] {
        cleanViewBuilders.compactMap { $0(context) }
    }

    /// The light's brightness while the torch is on, such as "25%"; its menu turns the light
    /// off or picks another brightness, which is remembered.
    ///
    /// - Parameter context: The model and settings.
    static func light(_ context: CameraControlContext) -> StatePill? {
        let light = context.model.light
        guard case .on(let level) = light.torch else { return nil }
        let settings = context.settings
        let percent = Text(level, format: .percent.precision(.fractionLength(0)))
        let levels = LightModel.torchLevels.map { choice in
            StatePill.Action(
                id: "level-\(choice)",
                title: Text(
                    "Brightness \(Text(choice, format: .percent.precision(.fractionLength(0))))", bundle: .module,
                    comment: "Action of the Light pill on the camera: sets the light's brightness. The value is a percentage such as 25%.")
            ) {
                settings.setTorchLevel(choice)
            }
        }
        return StatePill(
            id: "light", systemImage: "flashlight.on.fill", text: percent,
            label: Text("Light", bundle: .module, comment: "Camera switch and its Voice Control name: turns on the phone's light (torch) and keeps it on while taking photos."),
            actions: [
                StatePill.Action(
                    id: "off", title: Text("Turn Off Light", bundle: .module, comment: "Action of the Light pill on the camera: turns the light (torch) off.")
                ) {
                    context.send(.light(.setTorch(false)))
                }
            ] + levels,
            value: percent)
    }

    /// The flash mode while it is Auto or On and applies to the next photo; its action turns
    /// the flash off.
    ///
    /// - Parameter context: The model and settings.
    static func flash(_ context: CameraControlContext) -> StatePill? {
        let mode = context.model.light.flashModeForCapture
        guard mode != .off else { return nil }
        let settings = context.settings
        return StatePill(
            id: "flash", systemImage: FlashText.systemImage(for: mode),
            // Their own keys: "Auto" alone is the manual controls' Auto.
            text: mode == .auto
                ? Text(String(localized: "Flash pill: Auto", defaultValue: "Auto", bundle: .module, comment: "Short text of the flash pill on the camera: the camera decides whether the flash fires."))
                : Text(String(localized: "Flash pill: On", defaultValue: "On", bundle: .module, comment: "Short text of the flash pill on the camera: the flash fires for every photo.")),
            label: FlashText.name(of: mode),
            actions: [
                StatePill.Action(
                    id: "off", title: Text("Turn Off Flash", bundle: .module, comment: "Action of the flash pill on the camera: the flash no longer fires.")
                ) {
                    settings.setFlashMode(.off)
                }
            ])
    }

    /// "M" while manual controls are on; its action turns them off.
    ///
    /// - Parameter context: The model and settings.
    static func manual(_ context: CameraControlContext) -> StatePill? {
        guard context.model.manual.isEnabled else { return nil }
        let settings = context.settings
        return StatePill(
            id: "manual", systemImage: "slider.horizontal.3", text: Text(verbatim: ControlText.mark(.manual)),
            label: Text("Manual Controls", bundle: .module, comment: "Switch that shows manual exposure controls on the camera screen."),
            actions: [
                StatePill.Action(
                    id: "off",
                    title: Text("Turn Off Manual Controls", bundle: .module, comment: "Action of the M pill on the camera: hides the manual controls, as the Manual Controls switch in Settings does.")
                ) {
                    settings.setShowsManualControls(false)
                }
            ])
    }

    /// A lock while auto exposure or autofocus is locked (AE-L, AF-L), or both are locked at a
    /// tapped point (issue #35); its action unlocks everything.
    ///
    /// - Parameter context: The model and settings.
    static func locks(_ context: CameraControlContext) -> StatePill? {
        let manual = context.model.manual
        let locksAtPoint = manual.focusTarget?.isLocked == true
        guard locksAtPoint || (manual.isEnabled && (manual.settings.exposureLocked || manual.settings.focusLocked))
        else { return nil }
        let text: String =
            switch (manual.settings.exposureLocked || locksAtPoint, manual.settings.focusLocked || locksAtPoint) {
            case (true, true): "AE/AF"
            case (true, false): "AE-L"
            default: "AF-L"
            }
        return StatePill(
            id: "locks", systemImage: "lock.fill", text: Text(verbatim: text),
            label: Text("Exposure and Focus Lock", bundle: .module, comment: "VoiceOver and Voice Control name of the lock pill on the camera, shown while exposure or focus is locked."),
            actions: [
                StatePill.Action(
                    id: "unlock", title: Text("Unlock", bundle: .module, comment: "Action of the lock pill on the camera: unlocks exposure and focus.")
                ) {
                    context.send(.manual(.setExposureLock(false)))
                    context.send(.manual(.setFocusLock(false)))
                    context.send(.auto(.unlockFocusAndExposure))
                }
            ])
    }

    /// The exposure compensation in full auto, such as "−0.7", while it isn't 0 (issue #41);
    /// its action resets it. With manual controls on, the readout row shows it instead.
    ///
    /// - Parameter context: The model and settings.
    static func exposure(_ context: CameraControlContext) -> StatePill? {
        let manual = context.model.manual
        let compensation = manual.settings.exposureCompensation
        guard !manual.isEnabled, compensation != 0 else { return nil }
        return StatePill(
            id: "exposure", systemImage: "plusminus.circle",
            text: Text(verbatim: ControlText.value(compensation, of: .exposureCompensation)),
            label: Text("Exposure", bundle: .module, comment: "Name of the exposure compensation control in full auto, in the quick-controls tray and on its dial."),
            actions: [
                StatePill.Action(
                    id: "reset", title: Text("Reset Exposure", bundle: .module, comment: "Action of the exposure pill on the camera: returns exposure compensation to 0.")
                ) {
                    context.send(.auto(.setExposureCompensation(0)))
                }
            ])
    }

    /// The fast shutter choice in full auto while it isn't Standard (issue #56); its action
    /// returns it to Standard.
    ///
    /// - Parameter context: The model and settings.
    static func fastShutter(_ context: CameraControlContext) -> StatePill? {
        let choice = context.settings.fastShutter
        guard !context.model.manual.isEnabled, let shutter = choice.slowestShutter else { return nil }
        let settings = context.settings
        return StatePill(
            id: "fastShutter", systemImage: "hare", text: Text(verbatim: ControlText.shutter(shutter)),
            label: FastShutterText.title,
            actions: [
                StatePill.Action(
                    id: "standard", title: Text("Use Standard Shutter", bundle: .module, comment: "Action of the fast shutter pill on the camera: returns the fast shutter choice to Standard.")
                ) {
                    settings.setFastShutter(.handheld)
                }
            ])
    }

    /// "Close-Up" while autofocus is limited to near subjects (issue #51); its action turns
    /// the limit off.
    ///
    /// - Parameter context: The model and settings.
    static func closeUp(_ context: CameraControlContext) -> StatePill? {
        guard context.model.manual.nearFocusLimit else { return nil }
        return StatePill(
            id: "closeUp", systemImage: "camera.macro", text: CloseUpText.title, label: CloseUpText.title,
            actions: [
                StatePill.Action(
                    id: "off", title: Text("Turn Off Close-Up", bundle: .module, comment: "Action of the Close-Up pill on the camera: lets autofocus focus at any distance again.")
                ) {
                    context.send(.auto(.setNearFocusLimit(false)))
                }
            ])
    }

    /// "3×" while the focus magnifier is on (issue #51); its action turns it off.
    ///
    /// - Parameter context: The model and settings.
    static func magnifier(_ context: CameraControlContext) -> StatePill? {
        guard context.model.isMagnifying else { return nil }
        return StatePill(
            id: "magnifier", systemImage: "plus.magnifyingglass",
            text: Text(verbatim: FocusMagnifier.scale.formatted(.number.precision(.fractionLength(0))) + "×"),
            label: MagnifierText.title,
            actions: [
                StatePill.Action(
                    id: "off", title: Text("Turn Off Magnifier", bundle: .module, comment: "Action of the magnifier pill on the camera: shows the whole viewfinder again.")
                ) {
                    context.send(.auto(.setMagnifier(false)))
                }
            ])
    }
}

/// The state pills at the top of the camera: at most three, then "+n" for the rest, each with a
/// symbol and short text. Each pill is a button, or a menu when it has more than one action.
struct StatePillRow: View {
    /// The most pills shown before the rest fold into "+n".
    static var maximumVisible: Int { 3 }

    /// The pills, in display order.
    let pills: [StatePill]

    /// Creates the row.
    ///
    /// - Parameter pills: The pills, in display order.
    init(pills: [StatePill]) {
        self.pills = pills
    }

    /// The row.
    var body: some View {
        HStack(spacing: CameraStyle.targetSpacing) {
            ForEach(pills.prefix(Self.maximumVisible)) { pill in
                StatePillButton(pill: pill)
            }
            if pills.count > Self.maximumVisible {
                overflow(Array(pills.dropFirst(Self.maximumVisible)))
            }
        }
    }

    /// "+n": a menu with a section for each pill that doesn't fit.
    ///
    /// - Parameter hidden: The pills that don't fit.
    private func overflow(_ hidden: [StatePill]) -> some View {
        Menu {
            ForEach(hidden) { pill in
                Section {
                    ForEach(pill.actions) { action in
                        Button(role: action.role) { action.perform() } label: { action.title }
                    }
                } header: {
                    pill.label
                }
            }
        } label: {
            Text(verbatim: "+" + hidden.count.formatted())
                .pillShape()
        }
        .accessibilityLabel(
            Text("\(hidden.count) More Settings Changed", bundle: .module, comment: "VoiceOver name of the +n pill on the camera: how many more settings are not at their defaults. The number is a count of settings."))
    }
}

/// One state pill: a button for one action, a menu for more.
struct StatePillButton: View {
    /// The pill.
    let pill: StatePill

    /// Creates the pill.
    ///
    /// - Parameter pill: The pill.
    init(pill: StatePill) {
        self.pill = pill
    }

    /// The pill.
    var body: some View {
        Group {
            if pill.actions.count == 1, let action = pill.actions.first {
                Button(role: action.role) { action.perform() } label: { label }
                    .buttonStyle(.plain)
                    .accessibilityHint(action.title)
            } else {
                Menu {
                    ForEach(pill.actions) { action in
                        Button(role: action.role) { action.perform() } label: { action.title }
                    }
                } label: {
                    label
                }
            }
        }
        .accessibilityLabel(pill.label)
        .accessibilityValue(pill.value ?? Text(verbatim: ""))
        .accessibilityInputLabels([pill.label, pill.text])
        .accessibilityShowsLargeContentViewer()
    }

    /// The symbol and short text in a capsule.
    private var label: some View {
        Label {
            pill.text
        } icon: {
            Image(systemName: pill.systemImage)
        }
        .pillShape()
    }
}

extension View {
    /// The look of a state pill: small bold text on a dark capsule, inside a touch target at
    /// least 44 points on each side.
    func pillShape() -> some View {
        font(.footnote.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(white: 0.2), in: .capsule)
            .frame(minWidth: CameraStyle.minimumTarget, minHeight: CameraStyle.minimumTarget)
            .contentShape(.rect)
    }
}
