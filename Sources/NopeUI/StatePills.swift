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

    /// Creates a pill.
    ///
    /// - Parameters:
    ///   - id: A stable identifier.
    ///   - systemImage: The SF Symbol.
    ///   - text: The short visible text.
    ///   - label: The full name for VoiceOver and Voice Control.
    ///   - actions: What the pill can do; at least one.
    init(id: String, systemImage: String, text: Text, label: Text, actions: [Action]) {
        self.id = id
        self.systemImage = systemImage
        self.text = text
        self.label = label
        self.actions = actions
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
        manual,
        locks,
        drive,
    ]

    /// The pills for settings not at their defaults, in display order.
    ///
    /// - Parameter context: The model and settings.
    static func current(_ context: CameraControlContext) -> [StatePill] {
        builders.compactMap { $0(context) }
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

    /// A lock while auto exposure or autofocus is locked (AE-L, AF-L); its action unlocks both.
    ///
    /// Tap to focus (issue #35) can show the same pill after a lock from the viewfinder.
    ///
    /// - Parameter context: The model and settings.
    static func locks(_ context: CameraControlContext) -> StatePill? {
        let manual = context.model.manual
        guard manual.isEnabled, manual.settings.exposureLocked || manual.settings.focusLocked else { return nil }
        let text: String =
            switch (manual.settings.exposureLocked, manual.settings.focusLocked) {
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
