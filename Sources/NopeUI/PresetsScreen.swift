import NopeCore
import SwiftUI

/// The settings presets (issue #72): Factory Defaults and the saved presets, each applied with
/// one tap, the result of the last apply with an Undo button, and links to save the current
/// settings and to rename or delete saved presets.
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
                ForEach(presets.saved) { preset in
                    applyButton(.saved(preset.id)) { Text(verbatim: preset.name) }
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
                    Text("Save Current Settings", bundle: .module, comment: "Link that saves every current setting as a new named preset.")
                }
                if !presets.saved.isEmpty {
                    NavigationLink {
                        EditPresetsScreen(presets: presets, camera: camera)
                    } label: {
                        Text("Rename or Delete", bundle: .module, comment: "Link to the list of saved presets, where each can be renamed or deleted.")
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A preset holds every setting: photos, privacy, camera, and the lens, exposure and drive mode. A preset that includes Location still asks for location access.", bundle: .module, comment: "Explains what a settings preset contains. Location is the name of the privacy switch.")
                    Text("Presets are kept on this device only.", tableName: "Honesty", bundle: .module, comment: "Privacy note under the settings presets. Must not claim more than the English.")
                }
            }
        }
        .navigationTitle(PresetText.title)
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
            VStack(alignment: .leading, spacing: 4) {
                Text(PresetText.summary(of: result))
                    .font(.headline)
                ForEach(result.notices, id: \.self) { notice in
                    Text(PresetText.notice(notice))
                    .font(.footnote)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            if presets.canUndo {
                Button {
                    Task {
                        guard await presets.undo(camera: camera, location: camera?.location) else { return }
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
            Task { await presets.apply(choice, camera: camera, location: camera?.location) }
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityHint(Text("Applies every setting in the preset.", bundle: .module, comment: "VoiceOver hint of a settings preset in the list."))
    }

    /// The Presets row in Settings, with the number of saved presets.
    ///
    /// - Parameters:
    ///   - presets: The presets.
    ///   - settings: The settings.
    ///   - camera: The camera, or `nil`.
    /// - Returns: The link.
    static func link(presets: SettingsPresets, settings: NopeSettings, camera: CameraModel?) -> some View {
        NavigationLink {
            PresetsScreen(presets: presets, settings: settings, camera: camera)
        } label: {
            LabeledContent {
                Text(presets.saved.count, format: .number)
            } label: {
                PresetText.title
            }
        }
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

/// The saved presets, each opening its rename and delete screen; swiping a row deletes it.
struct EditPresetsScreen: View {
    /// The presets.
    let presets: SettingsPresets

    /// The camera, or `nil`.
    let camera: CameraModel?

    /// Creates the list.
    ///
    /// - Parameters:
    ///   - presets: The presets.
    ///   - camera: The camera, or `nil`.
    init(presets: SettingsPresets, camera: CameraModel?) {
        self.presets = presets
        self.camera = camera
    }

    /// The list.
    var body: some View {
        List {
            ForEach(presets.saved) { preset in
                NavigationLink {
                    PresetNameScreen(presets: presets, camera: camera, editing: preset)
                } label: {
                    Text(verbatim: preset.name)
                }
            }
            .onDelete { offsets in
                for id in offsets.map({ presets.saved[$0].id }) { presets.delete(id) }
            }
        }
        .navigationTitle(Text("Rename or Delete", bundle: .module, comment: "Link to the list of saved presets, where each can be renamed or deleted."))
    }
}

/// Names a new preset, or renames or deletes a saved one.
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
            if let editing {
                Section {
                    Button(role: .destructive) {
                        presets.delete(editing.id)
                        dismiss()
                    } label: {
                        Text("Delete Preset", bundle: .module, comment: "Button that deletes a saved settings preset. The current settings don't change.")
                    }
                } footer: {
                    Text("Deleting a preset doesn't change your current settings.", bundle: .module, comment: "Shown under the Delete Preset button.")
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
            String(localized: "The camera is taking photos. Try again when it's done.", bundle: .module, comment: "Shown when a settings preset can't be applied during a countdown, burst, series or astro run.")
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
