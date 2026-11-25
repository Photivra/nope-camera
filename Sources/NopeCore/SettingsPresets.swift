import Foundation
import Observation

/// A named snapshot of every setting (issue #72): what ``NopeSettings`` stores (formats, file
/// options, pairing, privacy, signing, location, mirroring, overlays, flash, night mode and any
/// setting added later) and the camera's own state (``CameraSetup``: lens, manual exposure, drive
/// and timer, bracketing, the interval series and the astro helper).
///
/// The settings part is a ``NopeSettingsSnapshot``: every key ``NopeSettings`` stores, copied
/// as it is. A setting added in a later version is therefore part of every preset saved after it
/// exists, without changing this type, and a preset saved before it existed sets it to its
/// default when applied (``NopeSettings/apply(_:)``).
///
/// Privacy rule (AGENTS.md, "No network, no analytics"): a preset holds settings only (Booleans,
/// names of choices, numbers and the name the person typed), never a photo or a location. Presets
/// are stored on the device with the settings and never leave it.
public struct SettingsPreset: Codable, Identifiable, Equatable, Sendable {
    /// The encoding version this version of the app writes. A preset written by a later version
    /// is still read: unknown values are ignored, and missing ones get their defaults.
    public static let encodingVersion = 1

    /// A stable identifier.
    public let id: UUID

    /// The name the person gave it, such as "Astro".
    public internal(set) var name: String

    /// The name as a resource that shows it exactly as typed, for the Shortcuts app. The name
    /// itself is never a string catalog key, so a name that matches one of the app's strings
    /// (such as "Preset") isn't translated: the key is a placeholder that the name fills.
    public var verbatimName: LocalizedStringResource {
        var interpolation = String.LocalizationValue.StringInterpolation(literalCapacity: 0, interpolationCount: 1)
        interpolation.appendInterpolation(name)
        return LocalizedStringResource(String.LocalizationValue(stringInterpolation: interpolation))
    }

    /// The encoding version the preset was written with.
    public let version: Int

    /// Every stored setting.
    public let settings: NopeSettingsSnapshot

    /// The camera's lens, exposure, drive and astro values.
    public let camera: CameraSetup

    /// Creates a preset.
    ///
    /// - Parameters:
    ///   - id: A stable identifier.
    ///   - name: The preset's name.
    ///   - settings: Every stored setting.
    ///   - camera: The camera's state.
    public init(id: UUID = UUID(), name: String, settings: NopeSettingsSnapshot, camera: CameraSetup) {
        self.id = id
        self.name = name
        version = Self.encodingVersion
        self.settings = settings
        self.camera = camera
    }

    /// Reads a preset. Only the identifier, the name and the settings are required; the version
    /// defaults to 1 and the camera to ``CameraSetup/factory``.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: A `DecodingError` when a required value is missing or unreadable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        settings = try container.decode(NopeSettingsSnapshot.self, forKey: .settings)
        camera = (try? container.decodeIfPresent(CameraSetup.self, forKey: .camera)) ?? .factory
    }

    /// The stored names of the values.
    enum CodingKeys: String, CodingKey {
        /// ``SettingsPreset/id``.
        case id
        /// ``SettingsPreset/name``.
        case name
        /// ``SettingsPreset/version``.
        case version
        /// ``SettingsPreset/settings``.
        case settings
        /// ``SettingsPreset/camera``.
        case camera
    }

    /// The settings of a fresh install: no stored setting, so every one is its default.
    public static var factorySettings: NopeSettingsSnapshot {
        // A binary property list of an empty dictionary can always be written, so this can't
        // throw.
        NopeSettingsSnapshot(
            values: try! PropertyListSerialization.data(fromPropertyList: [String: Any](), format: .binary, options: 0))
    }
}

/// A preset to apply: the built-in Factory Defaults or one the person saved.
public enum PresetChoice: Hashable, Sendable {
    /// Every setting as a fresh install has it. Always available, and can't be changed or
    /// deleted.
    case factoryDefaults

    /// A saved preset, by identifier (``SettingsPreset/id``).
    case saved(UUID)
}

/// Something about applying a preset that the person should be told.
public enum PresetNotice: Equatable, Hashable, Sendable {
    /// The preset includes Location, but location access isn't allowed, so Location stays off.
    case locationNotAllowed

    /// The device has no lens like the preset's, so the lens didn't change.
    case lensUnavailable

    /// Some camera values were moved into what the lens supports, or left on Auto.
    case cameraValuesAdjusted

    /// The camera isn't on yet, so the lens and camera values didn't change; the other settings
    /// did.
    case cameraNotReady

    /// The camera is taking photos (a countdown, burst, series or astro run), so nothing changed.
    case cameraBusy

    /// The preset can't be read, so nothing changed.
    case unreadable
}

/// What happened when a preset was applied.
public struct PresetApplyResult: Equatable, Sendable {
    /// The preset that was applied.
    public let choice: PresetChoice

    /// The preset's name, or `nil` for Factory Defaults, whose name an interface localizes.
    public let name: String?

    /// Whether the settings changed. `false` only with ``PresetNotice/cameraBusy`` or
    /// ``PresetNotice/unreadable``.
    public let isApplied: Bool

    /// What the person should be told, in the order it happened. Empty when everything applied
    /// as saved.
    public let notices: [PresetNotice]

    /// Whether the Privacy settings were left as they were, because an assistant applied the
    /// preset (``SettingsPresets/apply(_:camera:location:keepsPrivacySettings:)``). The answer
    /// says so.
    public let keptPrivacySettings: Bool

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - choice: The preset.
    ///   - name: Its name, or `nil` for Factory Defaults.
    ///   - isApplied: Whether the settings changed.
    ///   - notices: What the person should be told.
    ///   - keptPrivacySettings: Whether the Privacy settings were left as they were.
    public init(
        choice: PresetChoice, name: String?, isApplied: Bool, notices: [PresetNotice], keptPrivacySettings: Bool = false
    ) {
        self.choice = choice
        self.name = name
        self.isApplied = isApplied
        self.notices = notices
        self.keptPrivacySettings = keptPrivacySettings
    }
}

/// Why a preset name can't be used.
public enum PresetNameProblem: Error, Equatable, Sendable {
    /// The name is empty or only spaces.
    case empty

    /// The name is longer than ``SettingsPresets/maximumNameLength`` characters.
    case tooLong

    /// Another saved preset already has this name (ignoring case).
    case duplicate
}

/// The person's saved settings presets, and the built-in Factory Defaults (issue #72).
///
/// Every interface uses the same object: it lists ``saved``, saves the current settings with
/// ``saveCurrent(named:camera:)``, renames and deletes with ``rename(_:to:)`` and
/// ``delete(_:)``, and applies with ``apply(_:camera:location:keepsPrivacySettings:)``. The rules live here:
///
/// - A preset changes settings only when the person applies it; nothing is ever applied on its
///   own (owner principle: the app never changes manual settings by itself).
/// - Applying replaces every setting at once. Factory Defaults returns every setting to a fresh
///   install's, without deleting saved presets.
/// - A preset never bypasses a permission: Location is turned on through
///   ``LocationTagging/turnOn(in:)``, which asks for access, and stays off with
///   ``PresetNotice/locationNotAllowed`` when access isn't allowed.
/// - The last apply can be undone (``undo(camera:location:)``), so a preset chosen by mistake
///   costs nothing.
///
/// Privacy rule (AGENTS.md, "No network, no analytics"): presets are stored in the same
/// on-device store as the settings, under their own key, and never leave the device. They aren't
/// part of the settings snapshot the Lock Screen camera gets.
///
/// ```swift
/// let presets = SettingsPresets(settings: settings)
/// try presets.saveCurrent(named: "Astro", camera: model)
/// let result = await presets.apply(.factoryDefaults, camera: model, location: model.location)
/// ```
@MainActor
@Observable
public final class SettingsPresets {
    /// The longest name a preset may have, in characters: enough for a few words, and short
    /// enough to read in one line in the lists at large text sizes.
    nonisolated public static let maximumNameLength = 40

    /// The saved presets, sorted by name.
    public private(set) var saved: [SettingsPreset]

    /// The result of the last apply, for an interface to show, or `nil` before any (and after an
    /// undo).
    public private(set) var lastResult: PresetApplyResult?

    /// Whether a preset is being applied now; another apply waits for it to finish.
    public private(set) var isApplying = false

    /// The settings and camera from before the last apply, which ``undo(camera:location:)``
    /// restores, or `nil` when there is nothing to undo. Internal so tests can give it one that
    /// can't be read.
    var beforeLastApply: SettingsPreset?

    /// The "Manual controls" option (``NopeSettings/showsManualControls``) the last apply or
    /// undo set up on the camera itself, until ``handlesManualControlsChange(to:)`` reports it.
    private var manualControlsSetUp: Bool?

    /// The settings the presets snapshot and replace.
    private let settings: NopeSettings

    /// Loads the saved presets from the settings' store.
    ///
    /// - Parameter settings: The person's settings. Presets are stored in the same store.
    public init(settings: NopeSettings) {
        self.settings = settings
        saved = Self.load(from: settings.defaults)
    }

    /// Whether ``undo(camera:location:)`` would restore anything.
    public var canUndo: Bool {
        beforeLastApply != nil
    }

    /// The saved preset with an identifier.
    ///
    /// - Parameter id: The identifier.
    /// - Returns: The preset, or `nil`.
    public func preset(withID id: UUID) -> SettingsPreset? {
        saved.first { $0.id == id }
    }

    /// Checks a name for a new or renamed preset.
    ///
    /// - Parameters:
    ///   - name: The name as typed. Spaces at either end are ignored.
    ///   - id: The preset being renamed, which may keep its own name, or `nil` for a new one.
    /// - Returns: Why the name can't be used, or `nil` when it can.
    public func problem(withName name: String, renaming id: UUID? = nil) -> PresetNameProblem? {
        let name = Self.trimmed(name)
        if name.isEmpty { return .empty }
        if name.count > Self.maximumNameLength { return .tooLong }
        let isTaken = saved.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return isTaken ? .duplicate : nil
    }

    /// Saves the current settings, and the camera's state, as a new preset.
    ///
    /// - Parameters:
    ///   - name: The name, which ``problem(withName:renaming:)`` must accept.
    ///   - camera: The camera, whose ``CameraModel/cameraSetup`` is saved, or `nil` to save
    ///     ``CameraSetup/factory``.
    /// - Returns: The new preset.
    /// - Throws: A ``PresetNameProblem`` for a name that can't be used, or an error from
    ///   ``NopeSettings/makeSnapshot()``.
    @discardableResult
    public func saveCurrent(named name: String, camera: CameraModel?) throws -> SettingsPreset {
        if let problem = problem(withName: name) { throw problem }
        let preset = SettingsPreset(
            name: Self.trimmed(name), settings: try settings.makePresetSnapshot(), camera: camera?.cameraSetup ?? .factory)
        saved.append(preset)
        store()
        return preset
    }

    /// Renames a saved preset.
    ///
    /// - Parameters:
    ///   - id: The preset.
    ///   - name: The new name, which ``problem(withName:renaming:)`` must accept.
    /// - Throws: A ``PresetNameProblem`` for a name that can't be used. A preset that doesn't
    ///   exist is ignored.
    public func rename(_ id: UUID, to name: String) throws {
        if let problem = problem(withName: name, renaming: id) { throw problem }
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[index].name = Self.trimmed(name)
        store()
    }

    /// Deletes a saved preset. The settings don't change.
    ///
    /// - Parameter id: The preset.
    public func delete(_ id: UUID) {
        saved.removeAll { $0.id == id }
        store()
    }

    /// Applies a preset: every setting, then the camera's state.
    ///
    /// Assistant Access is never stored in a preset and never changed by one; Factory Defaults
    /// applied in the app (`keepsPrivacySettings` false) returns it to its defaults, off and
    /// Every Action, and removes the tip's counter (``AssistantSession/tipCounter``). Applied through an assistant (`keepsPrivacySettings` true), the Privacy
    /// settings (``NopeSettings/metadata``: Details in Each Photo, Location, Sign Each Photo) and
    /// Assistant Access stay as they are, and everything else applies
    /// (`docs/design/assistant-access.md`, 7.4).
    ///
    /// Side effects: changes and saves every setting; may show the system location prompt when
    /// the preset includes Location; may switch the lens, which restarts the camera.
    ///
    /// - Parameters:
    ///   - choice: The preset.
    ///   - camera: The camera to set up, or `nil` when there is none (the camera part is then
    ///     skipped, with ``PresetNotice/cameraNotReady``).
    ///   - location: Location tagging, or `nil` when the app has no location service, in which
    ///     case Location stays off.
    ///   - keepsPrivacySettings: Whether the Privacy settings stay as they are: `true` when an
    ///     assistant applies the preset.
    /// - Returns: What happened, also kept in ``lastResult``.
    @discardableResult
    public func apply(
        _ choice: PresetChoice, camera: CameraModel?, location: LocationTagging?, keepsPrivacySettings: Bool = false
    ) async -> PresetApplyResult {
        let preset: SettingsPreset? =
            switch choice {
            case .factoryDefaults:
                SettingsPreset(name: "", settings: SettingsPreset.factorySettings, camera: .factory)
            case .saved(let id):
                self.preset(withID: id)
            }
        let name = choice == .factoryDefaults ? nil : preset?.name
        guard let preset else {
            return finish(PresetApplyResult(choice: choice, name: name, isApplied: false, notices: [.unreadable]))
        }
        guard camera?.isBusyForPresets != true, !isApplying else {
            return finish(PresetApplyResult(choice: choice, name: name, isApplied: false, notices: [.cameraBusy]))
        }
        let before = try? SettingsPreset(
            name: "", settings: settings.makeSnapshot(), camera: camera?.cameraSetup ?? .factory)
        let keepsAssistantAccess = keepsPrivacySettings || choice != .factoryDefaults
        guard
            let notices = await replaceSettings(
                with: preset, camera: camera, location: location, keepsPrivacySettings: keepsPrivacySettings,
                keepsAssistantAccess: keepsAssistantAccess)
        else {
            return finish(PresetApplyResult(choice: choice, name: name, isApplied: false, notices: [.unreadable]))
        }
        beforeLastApply = before
        return finish(
            PresetApplyResult(
                choice: choice, name: name, isApplied: true, notices: notices, keptPrivacySettings: keepsPrivacySettings))
    }

    /// Returns every setting, and the camera, to what they were before the last apply.
    ///
    /// Side effects: as ``apply(_:camera:location:keepsPrivacySettings:)``.
    ///
    /// - Parameters:
    ///   - camera: The camera to set up again, or `nil`.
    ///   - location: Location tagging, or `nil`.
    /// - Returns: `true` when the settings were restored; `false`, with nothing changed, when
    ///   there was no apply to undo, the camera was busy, or the earlier settings couldn't be
    ///   read (they can't be restored, so Undo is no longer offered). An interface says so.
    @discardableResult
    public func undo(camera: CameraModel?, location: LocationTagging?) async -> Bool {
        guard let before = beforeLastApply, camera?.isBusyForPresets != true, !isApplying else { return false }
        beforeLastApply = nil
        // Undo never changes Assistant Access: it changes on its own page only.
        guard
            await replaceSettings(
                with: before, camera: camera, location: location, keepsPrivacySettings: false, keepsAssistantAccess: true)
                != nil
        else { return false }
        lastResult = nil
        return true
    }

    /// Whether a change of the "Manual controls" option (``NopeSettings/showsManualControls``)
    /// was made by an apply or undo that already set the camera up for it, so an interface that
    /// follows the option must not send it to the camera again.
    ///
    /// ``CameraModel/applyCameraSetup(_:manualControlsOn:)`` turns manual controls on or off
    /// itself, before the astro helper, which turns them on again for its frames. An interface
    /// that sent the changed option afterwards (a SwiftUI `.task(id:)` runs later) would turn
    /// manual controls off under the helper, and so the helper too. Each apply's answer is given
    /// once: the next change is the person's again.
    ///
    /// - Parameter isOn: The option's new value.
    /// - Returns: `true` when the interface should skip sending it.
    public func handlesManualControlsChange(to isOn: Bool) -> Bool {
        defer { manualControlsSetUp = nil }
        return manualControlsSetUp == isOn
    }

    /// Replaces the settings and the camera's state with a preset's.
    ///
    /// Location is never turned on by the snapshot itself: it is turned off, then on again
    /// through ``LocationTagging/turnOn(in:)``, which asks for access first (AGENTS.md: a preset
    /// never bypasses a permission).
    ///
    /// - Parameters:
    ///   - preset: The preset.
    ///   - camera: The camera, or `nil`.
    ///   - location: Location tagging, or `nil`.
    ///   - keepsPrivacySettings: Whether the Privacy settings stay as they are.
    ///   - keepsAssistantAccess: Whether Assistant Access stays as it is.
    /// - Returns: The notices, or `nil` when the preset's settings can't be read and nothing
    ///   changed.
    @discardableResult
    private func replaceSettings(
        with preset: SettingsPreset, camera: CameraModel?, location: LocationTagging?, keepsPrivacySettings: Bool,
        keepsAssistantAccess: Bool
    ) async -> [PresetNotice]? {
        isApplying = true
        defer { isApplying = false }
        let metadata = settings.metadata
        let assistant = (isOn: settings.assistantAccess, ask: settings.assistantAsk)
        guard settings.apply(preset.settings) else { return nil }
        settings.restore(
            metadata: keepsPrivacySettings ? metadata : nil, assistant: keepsAssistantAccess ? assistant : nil)
        // Factory Defaults in the app also removes the Assistant Access tip's counter, the one
        // counter the app stores (docs/SECURITY_AUDIT.md, "Local data"); an interface tells its
        // ``AssistantSession`` (``AssistantSession/reloadTipCounter()``).
        if !keepsAssistantAccess { settings.defaults.removeObject(forKey: AssistantSession.tipCounterKey) }
        // Set before the first wait, so an interface that follows the option sees it at once.
        if camera != nil { manualControlsSetUp = settings.showsManualControls }
        var notices: [PresetNotice] = []
        // Kept privacy settings include Location as it already was, with its permission.
        if !keepsPrivacySettings, settings.metadata.isOn(.location) {
            settings.setMetadataItem(.location, isIncluded: false)
            let isOn = await location?.turnOn(in: settings) ?? false
            if !isOn { notices.append(.locationNotAllowed) }
        }
        guard let camera else { return notices + [.cameraNotReady] }
        return notices + (await camera.applyCameraSetup(preset.camera, manualControlsOn: settings.showsManualControls))
    }

    /// Keeps a result as ``lastResult`` and returns it.
    ///
    /// - Parameter result: The result.
    /// - Returns: The same result.
    private func finish(_ result: PresetApplyResult) -> PresetApplyResult {
        lastResult = result
        return result
    }

    /// Writes the saved presets to the store, sorted by name.
    private func store() {
        saved.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // Encoding presets of strings, numbers and data can't fail.
        settings.defaults.set(try? JSONEncoder().encode(Library(presets: saved)), forKey: Self.storageKey)
    }

    /// The saved presets in a store.
    ///
    /// Each preset is read on its own, so one that can't be read (damaged data) is skipped
    /// instead of hiding the others.
    ///
    /// - Parameter defaults: The store.
    /// - Returns: The presets that could be read, sorted by name.
    static func load(from defaults: UserDefaults) -> [SettingsPreset] {
        guard let data = defaults.data(forKey: storageKey),
            let library = try? JSONDecoder().decode(StoredLibrary.self, from: data)
        else { return [] }
        return library.presets.compactMap(\.preset)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Removes spaces and line breaks at either end of a name.
    ///
    /// - Parameter name: The name as typed.
    /// - Returns: The name without them.
    static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The store key of the saved presets. It doesn't start with ``SharedSettingsStore/keyPrefix``,
    /// so the presets aren't part of a settings snapshot (a preset never contains other presets,
    /// and the Lock Screen camera's 4 KB snapshot holds settings only).
    static let storageKey = "NopePresets.saved"

    /// The presets as written: a version and the list.
    struct Library: Encodable {
        /// The encoding version, ``SettingsPreset/encodingVersion``.
        let version = SettingsPreset.encodingVersion

        /// The presets.
        let presets: [SettingsPreset]

        /// Wraps the presets to write.
        ///
        /// - Parameter presets: The presets.
        init(presets: [SettingsPreset]) {
            self.presets = presets
        }
    }

    /// The presets as read: each one may fail on its own.
    struct StoredLibrary: Decodable {
        /// The presets, `nil` for each one that couldn't be read.
        let presets: [LossyPreset]

        /// Reads the list. The version isn't needed: each preset carries its own.
        ///
        /// - Parameter decoder: The decoder.
        /// - Throws: A `DecodingError` when there is no list of presets.
        init(from decoder: any Decoder) throws {
            presets = try decoder.container(keyedBy: CodingKeys.self).decode([LossyPreset].self, forKey: .presets)
        }

        /// The stored names of the values read.
        enum CodingKeys: String, CodingKey {
            /// ``StoredLibrary/presets``.
            case presets
        }
    }

    /// One stored preset, or `nil` when it can't be read.
    struct LossyPreset: Decodable {
        /// The preset, or `nil`.
        let preset: SettingsPreset?

        /// Reads a preset, keeping `nil` instead of failing.
        ///
        /// - Parameter decoder: The decoder.
        init(from decoder: any Decoder) {
            preset = try? SettingsPreset(from: decoder)
        }
    }
}
