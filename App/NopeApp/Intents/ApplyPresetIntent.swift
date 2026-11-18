import AppIntents
import Foundation
import NopeCore

/// "Apply Preset" for the Shortcuts app (issue #72): applies Factory Defaults or a saved settings
/// preset, as tapping it in the Presets list does.
///
/// The intent holds no rules (AGENTS.md, "Siri and Shortcuts"): it hands
/// ``ShortcutRequest/applyPreset(_:)`` to the app's ``ShortcutInbox``, and the camera screen
/// applies it with ``SettingsPresets/apply(_:camera:location:)``: the same path, the same
/// permission prompt for Location, and the same Undo in the Presets list. A preset never turns
/// the light on. The lens and exposure apply to the running camera, so the app opens first. It
/// has no Siri phrase: every App Shortcut slot is used (`NopeShortcuts`).
struct ApplyPresetIntent: AppIntent {
    /// The action's name in the Shortcuts app.
    static let title = LocalizedStringResource(
        "Apply Preset", comment: "The name of nope.'s action that applies a settings preset (Factory Defaults or one the person saved), in the Shortcuts app.")

    /// What the action does, in the Shortcuts app.
    static let description = IntentDescription(
        LocalizedStringResource(
            "Opens nope. and applies a settings preset: Factory Defaults or one you saved. You can undo it in Presets.",
            comment: "Describes nope.'s Apply Preset action in the Shortcuts app. Presets is the name of the list in nope.'s Settings. Keep \"nope.\" unchanged."))

    /// The lens and exposure apply to the running camera, which runs only in the foreground.
    static let openAppWhenRun = true

    /// The preset.
    @Parameter(
        title: LocalizedStringResource(
            "Preset", comment: "A setting of nope.'s Apply Preset action: which settings preset to apply."))
    var preset: PresetEntity

    /// The app's inbox, which the camera screen serves.
    @Dependency private var inbox: ShortcutInbox

    /// How the action reads in the Shortcuts editor.
    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$preset)")
    }

    /// Hands the request to the camera screen and says how it ended.
    ///
    /// - Returns: The outcome, said by Siri or shown by Shortcuts.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let choice = PresetChoice(identifier: preset.id) else {
            return .result(dialog: IntentDialog(ShortcutDialog.message(for: .presetUnavailable)))
        }
        let outcome = await inbox.submit(.applyPreset(choice))
        return .result(dialog: IntentDialog(ShortcutDialog.message(for: outcome)))
    }
}

/// A settings preset as the Shortcuts app shows and picks it: Factory Defaults or a saved preset.
struct PresetEntity: AppEntity {
    /// The type's name in the Shortcuts app.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Preset", comment: "A setting of nope.'s Apply Preset action: which settings preset to apply."))

    /// Finds presets by identifier and lists them.
    static let defaultQuery = PresetQuery()

    /// ``PresetChoice/identifier``: Factory Defaults' fixed identifier or a saved preset's UUID.
    let id: String

    /// The name: "Factory Defaults", localized, or the name the person gave.
    let name: LocalizedStringResource

    /// How the preset is shown in Shortcuts.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: name)
    }

    /// Factory Defaults.
    static let factoryDefaults = PresetEntity(
        id: PresetChoice.factoryDefaultsIdentifier,
        name: LocalizedStringResource(
            "Factory Defaults", comment: "Built-in settings preset that returns every setting to what a fresh install has."))

    /// A saved preset.
    ///
    /// - Parameter preset: The preset.
    init(_ preset: SettingsPreset) {
        id = PresetChoice.saved(preset.id).identifier
        // The person's own text: shown as typed, never looked up in a string catalog.
        name = preset.verbatimName
    }

    /// A preset with an identifier and a name.
    ///
    /// - Parameters:
    ///   - id: The identifier.
    ///   - name: The name.
    init(id: String, name: LocalizedStringResource) {
        self.id = id
        self.name = name
    }
}

/// The presets Shortcuts can pick: Factory Defaults first, then the saved ones by name.
struct PresetQuery: EntityQuery {
    /// The person's presets, the same object the camera screen shows.
    @Dependency private var presets: SettingsPresets

    /// The presets with these identifiers that still exist.
    ///
    /// - Parameter identifiers: Identifiers from ``PresetEntity/id``.
    /// - Returns: The presets found.
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PresetEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    /// Every preset, for the picker.
    ///
    /// - Returns: Factory Defaults and the saved presets.
    @MainActor
    func suggestedEntities() async throws -> [PresetEntity] {
        all()
    }

    /// Factory Defaults and the saved presets.
    @MainActor
    private func all() -> [PresetEntity] {
        [.factoryDefaults] + presets.saved.map(PresetEntity.init)
    }
}
