import Foundation
import Observation

/// The person's settings, stored on the device: what each photo saves (``SaveSettings``: formats,
/// metadata and signing) and the camera screen options.
///
/// Every interface reads the same object and changes it only through its methods, which apply
/// the rules of ``SaveSettings`` and ``MetadataSettings`` (at least one format, the metadata
/// master switch). Each change is saved at once. The app passes ``save`` to
/// ``CameraModel/saveSettings`` whenever it changes, so the next photo uses it.
///
/// Privacy rule (AGENTS.md, "No network, no analytics"): settings are stored in the app's own
/// `UserDefaults` on the device only. They are never synced through iCloud or sent anywhere.
///
/// The model is isolated to the main actor, so an interface can read its properties directly.
///
/// ```swift
/// let settings = NopeSettings(defaults: .standard)
/// settings.setFormat(.jpeg, isSelected: true)
/// settings.setSignsPhotos(false)
/// model.saveSettings = settings.save
/// ```
@MainActor
@Observable
public final class NopeSettings {
    /// What each photo saves: formats, the HEIF and JPEG look, metadata and the signature switch.
    public private(set) var save: SaveSettings

    /// Whether the camera screen shows the manual controls. Off by default, so the camera stays
    /// simple unless the person asks (AGENTS.md, "Cognitive").
    public private(set) var showsManualControls: Bool

    /// Whether the camera screen starts in clean view, with only the viewfinder, the shutter
    /// and honesty warnings. Off by default.
    public private(set) var startsInCleanView: Bool

    /// Where the settings are stored.
    private let defaults: UserDefaults

    /// Loads the settings, using the default for any value not stored yet or not readable.
    ///
    /// Unreadable save settings fall back to ``SaveSettings/init()``, which removes every
    /// optional detail and signs: the most private choice (AGENTS.md, "Fail closed").
    ///
    /// - Parameter defaults: The store to read and write, normally `UserDefaults.standard`.
    ///   Tests pass a store of their own.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        save = defaults.data(forKey: Key.save).flatMap { try? JSONDecoder().decode(SaveSettings.self, from: $0) }
            ?? SaveSettings()
        // A value from a launch argument (`-NopeSettings.showsManualControls YES`) arrives as a
        // string, which `bool(forKey:)` reads; a missing value is the default, off.
        showsManualControls = defaults.bool(forKey: Key.showsManualControls)
        startsInCleanView = defaults.bool(forKey: Key.startsInCleanView)
        migrateManualControlsOption()
    }

    /// The formats each photo is saved in. Never empty; RAW and HEIF by default.
    public var formats: Set<PhotoFormat> {
        save.formats
    }

    /// Which optional metadata items each file carries. The default removes them all.
    public var metadata: MetadataSettings {
        save.metadata
    }

    /// Whether each photo is signed with Content Credentials. On by default, and separate from
    /// the metadata master switch (`docs/PRIVACY.md`, "Metadata plan").
    public var signsPhotos: Bool {
        save.metadata.signsPhotos
    }

    /// How the HEIF and JPEG copies are developed from the RAW. ``DevelopedLook/standard`` by
    /// default. The RAW is never changed by it.
    public var developedLook: DevelopedLook {
        save.developedLook
    }

    /// The selected formats in display order: RAW, HEIF, JPEG.
    public var orderedFormats: [PhotoFormat] {
        PhotoFormat.allCases.filter(formats.contains)
    }

    /// Whether a format can be chosen on a device.
    ///
    /// - Parameters:
    ///   - format: A format.
    ///   - deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW
    ///     (``DeviceCapabilities/supportsBayerRAW``).
    /// - Returns: `false` only for RAW on a device without Bayer RAW.
    public static func isAvailable(_ format: PhotoFormat, deviceSupportsBayerRAW: Bool) -> Bool {
        format != .raw || deviceSupportsBayerRAW
    }

    /// The selected formats the device can save, in display order.
    ///
    /// - Parameter deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW.
    /// - Returns: ``orderedFormats`` without RAW on a device that has none.
    public func selectedFormats(deviceSupportsBayerRAW: Bool) -> [PhotoFormat] {
        orderedFormats.filter { Self.isAvailable($0, deviceSupportsBayerRAW: deviceSupportsBayerRAW) }
    }

    /// Whether the person can turn a selected format off.
    ///
    /// Every photo needs at least one format the device can save, so the last one can't be
    /// turned off.
    ///
    /// - Parameters:
    ///   - format: A selected format.
    ///   - deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW.
    /// - Returns: `false` when the format is the only one left that the device can save.
    public func canTurnOff(_ format: PhotoFormat, deviceSupportsBayerRAW: Bool) -> Bool {
        selectedFormats(deviceSupportsBayerRAW: deviceSupportsBayerRAW) != [format]
    }

    /// Whether any selected format is developed by nope. from the RAW (HEIF or JPEG).
    public var savesDevelopedFormat: Bool {
        formats.contains(where: \.isDevelopedFromRAW)
    }

    /// Turns a format on or off, and saves the change.
    ///
    /// - Parameters:
    ///   - format: The format to change.
    ///   - isSelected: Whether photos should be saved in the format.
    /// - Returns: `false`, changing nothing, when the change would leave no format selected.
    ///   Interfaces also check ``canTurnOff(_:deviceSupportsBayerRAW:)`` first.
    @discardableResult
    public func setFormat(_ format: PhotoFormat, isSelected: Bool) -> Bool {
        let changed = save.setFormat(format, isSelected: isSelected)
        store()
        return changed
    }

    /// Turns the metadata master switch on or off, and saves the change.
    ///
    /// - Parameter isOn: See ``MetadataSettings/setRemovesAllOptionalDetails(_:)``.
    public func setRemovesAllOptionalDetails(_ isOn: Bool) {
        save.metadata.setRemovesAllOptionalDetails(isOn)
        store()
    }

    /// Turns one metadata item on or off, and saves the change.
    ///
    /// - Parameters:
    ///   - item: The item. See ``MetadataSettings/set(_:isOn:)``.
    ///   - isIncluded: Whether files should carry the item.
    public func setMetadataItem(_ item: MetadataItem, isIncluded: Bool) {
        save.metadata.set(item, isOn: isIncluded)
        store()
    }

    /// Turns signing on or off, and saves the change.
    ///
    /// - Parameter isOn: Whether each photo is signed.
    public func setSignsPhotos(_ isOn: Bool) {
        save.metadata.signsPhotos = isOn
        store()
    }

    /// Sets how the HEIF and JPEG copies are developed, and saves the change.
    ///
    /// - Parameter look: The look.
    public func setDevelopedLook(_ look: DevelopedLook) {
        save.developedLook = look
        store()
    }

    /// Shows or hides the manual controls on the camera screen, and saves the change.
    ///
    /// - Parameter isOn: Whether the manual controls are shown.
    public func setShowsManualControls(_ isOn: Bool) {
        showsManualControls = isOn
        defaults.set(isOn, forKey: Key.showsManualControls)
    }

    /// Sets whether the camera screen starts in clean view, and saves the change.
    ///
    /// - Parameter isOn: Whether the camera starts in clean view.
    public func setStartsInCleanView(_ isOn: Bool) {
        startsInCleanView = isOn
        defaults.set(isOn, forKey: Key.startsInCleanView)
    }

    /// Moves the "Manual controls" option from the key used before `NopeSettings` existed,
    /// once: a stored value is kept unless this model already has one, and the old key is
    /// removed.
    private func migrateManualControlsOption() {
        guard defaults.object(forKey: Key.legacyManualControls) != nil else { return }
        if defaults.object(forKey: Key.showsManualControls) == nil {
            setShowsManualControls(defaults.bool(forKey: Key.legacyManualControls))
        }
        defaults.removeObject(forKey: Key.legacyManualControls)
    }

    /// Writes the save settings to the store.
    private func store() {
        // Encoding a struct of Booleans, strings and sets of string-backed cases can't fail.
        defaults.set(try? JSONEncoder().encode(save), forKey: Key.save)
    }

    /// The `UserDefaults` keys.
    enum Key {
        /// The save settings, as JSON-encoded ``SaveSettings``.
        static let save = "NopeSettings.save"
        /// Whether the manual controls are shown, a Boolean.
        static let showsManualControls = "NopeSettings.showsManualControls"
        /// The key the "Manual controls" option used before `NopeSettings`, migrated once.
        static let legacyManualControls = "manualControlsEnabled"
        /// Whether the camera starts in clean view, a Boolean.
        static let startsInCleanView = "NopeSettings.startsInCleanView"
    }
}
