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

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - choice: The preset.
    ///   - name: Its name, or `nil` for Factory Defaults.
    ///   - isApplied: Whether the settings changed.
    ///   - notices: What the person should be told.
    public init(choice: PresetChoice, name: String?, isApplied: Bool, notices: [PresetNotice]) {
        self.choice = choice
        self.name = name
        self.isApplied = isApplied
        self.notices = notices
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
/// ``delete(_:)``, and applies with ``apply(_:camera:location:)``. The rules live here:
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
    /// restores, or `nil` when there is nothing to undo.
    private var beforeLastApply: SettingsPreset?

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
            name: Self.trimmed(name), settings: try settings.makeSnapshot(), camera: camera?.cameraSetup ?? .factory)
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
    /// Side effects: changes and saves every setting; may show the system location prompt when
    /// the preset includes Location; may switch the lens, which restarts the camera.
    ///
    /// - Parameters:
    ///   - choice: The preset.
    ///   - camera: The camera to set up, or `nil` when there is none (the camera part is then
    ///     skipped, with ``PresetNotice/cameraNotReady``).
    ///   - location: Location tagging, or `nil` when the app has no location service, in which
    ///     case Location stays off.
    /// - Returns: What happened, also kept in ``lastResult``.
    @discardableResult
    public func apply(_ choice: PresetChoice, camera: CameraModel?, location: LocationTagging?) async
        -> PresetApplyResult
    {
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
        guard let notices = await replaceSettings(with: preset, camera: camera, location: location) else {
            return finish(PresetApplyResult(choice: choice, name: name, isApplied: false, notices: [.unreadable]))
        }
        beforeLastApply = before
        return finish(PresetApplyResult(choice: choice, name: name, isApplied: true, notices: notices))
    }

    /// Returns every setting, and the camera, to what they were before the last apply.
    ///
    /// Side effects: as ``apply(_:camera:location:)``.
    ///
    /// - Parameters:
    ///   - camera: The camera to set up again, or `nil`.
    ///   - location: Location tagging, or `nil`.
    /// - Returns: `true` when there was an apply to undo and the camera wasn't busy.
    @discardableResult
    public func undo(camera: CameraModel?, location: LocationTagging?) async -> Bool {
        guard let before = beforeLastApply, camera?.isBusyForPresets != true, !isApplying else { return false }
        beforeLastApply = nil
        lastResult = nil
        await replaceSettings(with: before, camera: camera, location: location)
        return true
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
    /// - Returns: The notices, or `nil` when the preset's settings can't be read and nothing
    ///   changed.
    @discardableResult
    private func replaceSettings(with preset: SettingsPreset, camera: CameraModel?, location: LocationTagging?) async
        -> [PresetNotice]?
    {
        isApplying = true
        defer { isApplying = false }
        guard settings.apply(preset.settings) else { return nil }
        var notices: [PresetNotice] = []
        if settings.metadata.isOn(.location) {
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
