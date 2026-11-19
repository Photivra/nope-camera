import NopeCore
import SwiftUI

/// The settings presets (issue #72): Factory Defaults and the saved presets, each applied with
/// one tap, the result of the last apply with an Undo button, and a link to save the current
/// settings. Each saved preset has a More menu (Rename, Delete), with the same two as swipe and
/// VoiceOver actions; Rename pushes the Rename Preset page and Delete asks first
/// (`docs/design/BUILD-SPEC.md`, 3.9). No page is more than two levels below Settings.
///
/// The same list opens from Settings (pushed) and from the Presets item of the quick-controls
/// tray (``PresetsSheet``), and applying works the same from both. A preset is applied only when
/// the person taps it, and Undo stays until the list closes, so a preset tapped by mistake costs
/// nothing: that is why there is no confirmation step. The screen renders a `SettingsPresets`
/// and changes it only through its methods, which hold the rules (AGENTS.md, "One direction of
/// flow").
struct PresetsScreen: View {
    /// The presets.
    let presets: SettingsPresets

    /// The settings, for night mode.
    let settings: NopeSettings

    /// The camera a preset saves and sets up, or `nil`.
    let camera: CameraModel?

    /// Whether the last Undo changed nothing, so the result says so.
    @State private var undoFailed = false

    /// The preset being renamed, whose Rename Preset page is pushed, or `nil`.
    @State private var renaming: UUID?

    /// Where Settings is, to scroll to a row search opened, or `nil` outside Settings.
    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    /// What assistants did since the app opened, or `nil` in the Lock Screen camera: told when
    /// Factory Defaults removed the tip's counter.
    @Environment(\.assistantSession) private var assistantSession

    /// Creates the list.
    ///
    /// - Parameters:
    ///   - presets: The presets.
    ///   - settings: The settings.
    ///   - camera: The camera, or `nil`.
    init(presets: SettingsPresets, settings: NopeSettings, camera: CameraModel?) {
        self.presets = presets
        self.settings = settings
        self.camera = camera
    }

    /// The list.
    var body: some View {
        List {
            if let result = presets.lastResult {
                resultSection(result)
            }
            Section {
                applyButton(.factoryDefaults) {
                    SettingLabel(title: PresetText.factoryDefaults, explanation: PresetText.factoryDefaultsExplanation)
                }
                .settingsRow(.factoryDefaults)
                ForEach(presets.saved) { preset in
                    PresetRow(
                        preset: preset,
                        apply: { apply(.saved(preset.id)) },
                        rename: { renaming = preset.id },
                        delete: { presets.delete(preset.id) })
                }
            } header: {
                Text("Apply a Preset", bundle: .module, comment: "Header of the list of settings presets: tapping one applies all of its settings.")
            } footer: {
                if presets.saved.isEmpty {
                    Text("No saved presets yet. Save your current settings to come back to them with one tap.", bundle: .module, comment: "Shown under the presets list before any preset is saved.")
                }
            }
            Section {
                NavigationLink {
                    PresetNameScreen(presets: presets, camera: camera, editing: nil)
                } label: {
                    Text(SettingsText.saveCurrentSettings)
                }
                .settingsRow(.saveCurrentSettings)
            } footer: {
                VStack(alignment: .leading, spacing: NopeSpace.xs) {
                    Text("A preset holds every setting: photos, privacy, camera, and the lens, exposure and drive mode. A preset that includes Location still asks for location access.", bundle: .module, comment: "Explains what a settings preset contains. Location is the name of the privacy switch.")
                    Text("Presets are kept on this device only.", tableName: "Honesty", bundle: .module, comment: "Privacy note under the settings presets. Must not claim more than the English.")
                }
            }
        }
        .navigationTitle(PresetText.title)
        .navigationDestination(item: $renaming) { id in
            if let preset = presets.saved.first(where: { $0.id == id }) {
                PresetNameScreen(presets: presets, camera: camera, editing: preset)
            }
        }
        .modifier(SettingsScrollTarget(navigation: navigation, page: .presets))
        .onChange(of: presets.lastResult) { _, result in
            guard let result else { return }
            AccessibilityNotification.Announcement(PresetText.summary(of: result)).post()
        }
    }

    /// What the last apply did, its notices and Undo.
    ///
    /// - Parameter result: The last result.
    private func resultSection(_ result: PresetApplyResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                Text(PresetText.summary(of: result))
                    .font(.headline)
                ForEach(result.notices, id: \.self) { notice in
                    Text(PresetText.notice(notice))
                    .font(.footnote)
                }
                if undoFailed {
                    Text(PresetText.undoFailed)
                        .font(.footnote)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            if presets.canUndo {
                Button {
                    Task {
                        undoFailed = !(await presets.undo(camera: camera, location: camera?.location))
                        guard !undoFailed else {
                            AccessibilityNotification.Announcement(PresetText.undoFailed).post()
                            return
                        }
                        AccessibilityNotification.Announcement(
                            String(localized: "Settings restored.", bundle: .module, comment: "VoiceOver announcement after Undo returned every setting to what it was before the preset.")
                        ).post()
                    }
                } label: {
                    Text("Undo", bundle: .module, comment: "Button that returns every setting to what it was before the preset was applied.")
                }
            }
        }
    }

    /// A row that applies a preset when tapped.
    ///
    /// - Parameters:
    ///   - choice: The preset.
    ///   - label: Its name.
    private func applyButton(_ choice: PresetChoice, @ViewBuilder label: () -> some View) -> some View {
        Button {
            apply(choice)
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityHint(Text("Applies every setting in the preset.", bundle: .module, comment: "VoiceOver hint of a settings preset in the list."))
    }

    /// Applies a preset.
    ///
    /// - Parameter choice: The preset.
    private func apply(_ choice: PresetChoice) {
        Task {
            undoFailed = false
            await presets.apply(choice, camera: camera, location: camera?.location)
            // Factory Defaults removed the Assistant Access tip's counter from the store.
            if choice == .factoryDefaults { assistantSession?.reloadTipCounter() }
        }
    }
}

/// A saved preset's row: its name, which applies it, and a More menu with Rename and Delete,
/// also offered as swipe actions and VoiceOver actions. Delete asks first, in a confirmation
/// anchored to the More button (a popover on iPad).
struct PresetRow: View {
    /// The preset.
    let preset: SettingsPreset

    /// Applies the preset.
    let apply: () -> Void

    /// Opens the Rename Preset page.
    let rename: () -> Void

    /// Deletes the preset, once confirmed.
    let delete: () -> Void

    /// Whether the delete confirmation is shown.
    @State private var confirmsDelete = false

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - preset: The preset.
    ///   - apply: Applies the preset.
    ///   - rename: Opens the Rename Preset page.
    ///   - delete: Deletes the preset, once confirmed.
    init(preset: SettingsPreset, apply: @escaping () -> Void, rename: @escaping () -> Void, delete: @escaping () -> Void) {
        self.preset = preset
        self.apply = apply
        self.rename = rename
        self.delete = delete
    }

    /// The name and the More menu.
    var body: some View {
        HStack(spacing: NopeSpace.xs) {
            Button(action: apply) {
                Text(verbatim: preset.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .foregroundStyle(.primary)
            .buttonStyle(.borderless)
            .accessibilityHint(Text("Applies every setting in the preset.", bundle: .module, comment: "VoiceOver hint of a settings preset in the list."))
            .accessibilityActions {
                Button(action: rename) { PresetText.rename }
                Button(action: { confirmsDelete = true }) { PresetText.delete }
            }
            Menu {
                Button(action: rename) {
                    Label { PresetText.rename } icon: { Image(systemName: "pencil") }
                }
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Label { PresetText.delete } icon: { Image(systemName: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(minWidth: NopeSize.minTarget, minHeight: NopeSize.minTarget)
                    .contentShape(.rect)
            }
            .foregroundStyle(CameraStyle.secondaryText)
            .accessibilityLabel(PresetText.more(preset.name))
            .accessibilityShowsLargeContentViewer()
            .confirmationDialog(
                Text(PresetText.deleteTitle(preset.name)), isPresented: $confirmsDelete, titleVisibility: .visible
            ) {
                // The system adds Cancel, in the system's words.
                Button(role: .destructive, action: delete) {
                    Text("Delete Preset", bundle: .module, comment: "Button that deletes a saved settings preset. The current settings don't change.")
                }
            } message: {
                Text("Deleting a preset doesn't change your current settings.", bundle: .module, comment: "Shown under the Delete Preset button.")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                confirmsDelete = true
            } label: {
                Label { PresetText.delete } icon: { Image(systemName: "trash") }
            }
            Button(action: rename) {
                Label { PresetText.rename } icon: { Image(systemName: "pencil") }
            }
        }
        .accessibilityIdentifier("settings.presets.saved.\(preset.name)")
    }
}

/// The presets list in its own sheet, opened from the quick-controls tray.
struct PresetsSheet: View {
    /// The presets.
    let presets: SettingsPresets

    /// The settings.
    let settings: NopeSettings

    /// The camera.
    let camera: CameraModel

    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet.
    ///
    /// - Parameters:
    ///   - presets: The presets.
    ///   - settings: The settings.
    ///   - camera: The camera.
    init(presets: SettingsPresets, settings: NopeSettings, camera: CameraModel) {
        self.presets = presets
        self.settings = settings
        self.camera = camera
    }

    /// The list in a navigation stack, with Done.
    var body: some View {
        NavigationStack {
            PresetsScreen(presets: presets, settings: settings, camera: camera)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        DoneButton { dismiss() }
                    }
                }
        }
    }
}

/// Names a new preset, or renames a saved one. Deleting is in the preset's More menu.
struct PresetNameScreen: View {
    /// The presets.
    let presets: SettingsPresets

    /// The camera whose state a new preset saves, or `nil`.
    let camera: CameraModel?

    /// The preset being renamed, or `nil` for a new one.
    let editing: SettingsPreset?

    /// The name as typed.
    @State private var name: String

    /// Whether the name field has focus.
    @FocusState private var isNameFocused: Bool

    /// Returns to the list.
    @Environment(\.dismiss) private var dismiss

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - presets: The presets.
    ///   - camera: The camera, or `nil`.
    ///   - editing: The preset to rename, or `nil` for a new one.
    init(presets: SettingsPresets, camera: CameraModel?, editing: SettingsPreset?) {
        self.presets = presets
        self.camera = camera
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
    }

    /// The problem with the name, or `nil` when it can be saved.
    private var problem: PresetNameProblem? {
        presets.problem(withName: name, renaming: editing?.id)
    }

    /// The form.
    var body: some View {
        Form {
            Section {
                // A field that grows with its text, so a long name or the largest text size is
                // never cut off (a one-line field's placeholder failed the clipped-text audit).
                // Return saves instead of adding a line.
                TextField(
                    text: Binding(
                        get: { name },
                        set: { typed in
                            name = typed.replacingOccurrences(of: "\n", with: "")
                            if typed.contains("\n") { save() }
                        }),
                    prompt: Text("For example, Astro", bundle: .module, comment: "Placeholder of the preset name field."),
                    axis: .vertical
                ) {
                    Text("Name", bundle: .module, comment: "Label of the field for a settings preset's name.")
                }
                .focused($isNameFocused)
                .submitLabel(.done)
            } footer: {
                // Shown only once something is typed: an empty new name isn't an error yet.
                if let problem, !(problem == .empty && name.isEmpty) {
                    Text(PresetText.problem(problem))
                }
            }
        }
        .navigationTitle(
            editing == nil
                ? Text("Save Preset", bundle: .module, comment: "Title of the screen that names a new settings preset.")
                : Text("Rename Preset", bundle: .module, comment: "Title of the screen that renames a saved settings preset."))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                // A Save button that does nothing until the name is valid, instead of a disabled
                // one: the footer says why (disabled buttons failed the contrast audit).
                // The system checkmark, as the Done button: a prominent text button in the bar
                // failed the contrast audit.
                Button(action: save) {
                    Label {
                        Text("Save", bundle: .module, comment: "Button that saves a settings preset under the typed name.")
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                    .labelStyle(.iconOnly)
                }
                .accessibilityShowsLargeContentViewer()
            }
        }
        .onAppear { isNameFocused = editing == nil }
    }

    /// Saves the preset, or the new name, and returns to the list. Does nothing while the name
    /// has a problem.
    private func save() {
        guard problem == nil else { return }
        if let editing {
            try? presets.rename(editing.id, to: name)
        } else {
            _ = try? presets.saveCurrent(named: name, camera: camera)
        }
        dismiss()
    }
}

/// The words of the presets screens.
enum PresetText {
    /// "Presets": the Settings row, the screen and the tray item.
    ///
    /// Its own key: "Presets" alone is the white balance presets menu.
    static let title = Text(String(localized: "Settings presets: title", defaultValue: "Presets", bundle: .module, comment: "Settings row, screen title and camera tray item: named sets of every setting that can be applied at once."))

    /// The built-in preset's name.
    static let factoryDefaults = Text("Factory Defaults", bundle: .module, comment: "Built-in settings preset that returns every setting to what a fresh install has.")

    /// What Factory Defaults does.
    static let factoryDefaultsExplanation = Text("Every setting as on a fresh install. Saved presets are kept.", bundle: .module, comment: "Explains the Factory Defaults preset.")

    /// "Rename", in a preset's More menu.
    static let rename = Text("Rename", bundle: .module, comment: "Action in a saved preset's More menu, swipe actions and VoiceOver actions: opens the page that renames the preset.")

    /// "Delete", in a preset's More menu.
    static let delete = Text("Delete", bundle: .module, comment: "Action in a saved preset's More menu, swipe actions and VoiceOver actions: deletes the preset after asking.")

    /// The More menu's name, "More for NAME".
    ///
    /// - Parameter name: The preset's name.
    /// - Returns: The localized name.
    static func more(_ name: String) -> Text {
        Text("More for \(name)", bundle: .module, comment: "VoiceOver and Voice Control name of the menu button beside a saved preset, which holds Rename and Delete. The placeholder is the preset's name.")
    }

    /// The delete confirmation's title, "Delete “NAME”?".
    ///
    /// - Parameter name: The preset's name.
    /// - Returns: The localized title.
    static func deleteTitle(_ name: String) -> String {
        String(localized: "Delete “\(name)”?", bundle: .module, comment: "Title of the confirmation before deleting a saved preset. The placeholder is the preset's name, in the language's quotation marks.")
    }

    /// The Presets row's value in Settings: "None Saved" or "2 Saved".
    ///
    /// - Parameter count: The number of saved presets.
    /// - Returns: The localized value.
    static func savedCount(_ count: Int) -> Text {
        count == 0
            ? Text("None Saved", bundle: .module, comment: "Value of the Presets row in Settings and of the Presets tile in Q: no preset is saved yet.")
            : Text("\(count) Saved", bundle: .module, comment: "Value of the Presets row in Settings and of the Presets tile in Q: how many presets are saved. Use plural rules.")
    }

    /// What a failed Undo tells the person: nothing changed, and why it can happen.
    static var undoFailed: String {
        String(localized: "Couldn't undo: the camera is busy, or the earlier settings can't be read. Nothing changed.", bundle: .module, comment: "Shown and spoken when Undo in the presets list changed nothing.")
    }

    /// What an apply did, in one sentence.
    ///
    /// - Parameter result: The result.
    /// - Returns: The sentence.
    static func summary(of result: PresetApplyResult) -> String {
        guard result.isApplied else {
            return String(localized: "Nothing changed.", bundle: .module, comment: "Shown above the reason when a settings preset couldn't be applied.")
        }
        guard let name = result.name else {
            return String(localized: "Factory Defaults applied.", bundle: .module, comment: "Shown after the Factory Defaults preset was applied.")
        }
        return String(localized: "“\(name)” applied.", bundle: .module, comment: "Shown after a saved settings preset was applied. The placeholder is the preset's name, in the language's quotation marks.")
    }

    /// What a notice tells the person.
    ///
    /// - Parameter notice: The notice.
    /// - Returns: The sentence.
    static func notice(_ notice: PresetNotice) -> String {
        switch notice {
        case .locationNotAllowed:
            String(localized: "Location stays off, because location access isn't allowed for nope. You can allow it in Settings.", table: "Honesty", bundle: .module, comment: "Shown after applying a settings preset that includes Location when location access is off. Keep \"nope.\" unchanged. Must not claim more than the English.")
        case .lensUnavailable:
            String(localized: "This device has no lens like the preset's, so the lens didn't change.", bundle: .module, comment: "Shown after applying a settings preset saved with a lens this device doesn't have.")
        case .cameraValuesAdjusted:
            String(localized: "Some camera values were changed to what this lens supports.", bundle: .module, comment: "Shown after applying a settings preset whose exposure values the lens can't use exactly.")
        case .cameraNotReady:
            String(localized: "The camera isn't on, so the lens and camera values didn't change.", bundle: .module, comment: "Shown after applying a settings preset before the camera is allowed or started.")
        case .cameraBusy:
            String(localized: "The camera is taking photos. Try again when it's done.", bundle: .module, comment: "Shown when a settings preset can't be applied, and VoiceOver hint of a dimmed lens button, during a countdown, burst, series or astro run.")
        case .unreadable:
            String(localized: "This preset can't be read.", bundle: .module, comment: "Shown when a saved settings preset is damaged and can't be applied.")
        }
    }

    /// Why a name can't be saved.
    ///
    /// - Parameter problem: The problem.
    /// - Returns: The sentence.
    static func problem(_ problem: PresetNameProblem) -> String {
        switch problem {
        case .empty:
            String(localized: "Enter a name.", bundle: .module, comment: "Shown under the preset name field when it is empty.")
        case .tooLong:
            String(localized: "Use \(SettingsPresets.maximumNameLength) characters or fewer.", bundle: .module, comment: "Shown under the preset name field when the name is too long. The placeholder is the most characters allowed.")
        case .duplicate:
            String(localized: "Another preset has this name.", bundle: .module, comment: "Shown under the preset name field when a saved preset already has the name.")
        }
    }
}

extension QuickControls {
    /// Presets: opens the list of presets, Factory Defaults and the saved ones (issue #72), the
    /// same list as in Settings. Shown wherever the app has presets (not in the Lock Screen
    /// camera).
    ///
    /// - Parameter context: The model and settings.
    static func presets(_ context: CameraControlContext) -> QuickControlItem? {
        guard context.presets != nil else { return nil }
        let isShown = context.showsPresets
        return QuickControlItem(
            id: "presets", title: PresetText.title, systemImage: "square.stack.3d.up",
            kind: .button { isShown.wrappedValue = true })
    }
}
