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
/// Privacy rule (AGENTS.md, "No network, no analytics"): settings are stored in `UserDefaults` on
/// the device only: the app's App Group store, shared with its extensions (``SharedSettingsStore``).
/// They are never synced through iCloud or sent anywhere.
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

    /// The viewfinder overlays: grid, level, focus peaking, histogram and live camera readout.
    /// Every overlay is off by default. Change them with the setters in `OverlayOptions.swift`
    /// or ``setOverlays(_:)``.
    public private(set) var overlays: OverlayOptions

    /// How fast a shutter full auto prefers. ``FastShutter/handheld`` by default; the camera
    /// screen applies it with ``AutoControlIntent/setFastShutter(_:)``.
    public private(set) var fastShutter: FastShutter

    /// When the flash fires, remembered between launches. ``FlashMode/off`` by default. The app
    /// passes it to ``CameraModel/light`` with ``LightIntent/setFlashMode(_:)``.
    public private(set) var flashMode: FlashMode

    /// The torch's brightness, remembered between launches (the torch itself always starts off).
    /// ``LightModel/defaultTorchLevel`` by default. The app passes it to ``CameraModel/light``
    /// with ``LightIntent/setTorchLevel(_:)``.
    public private(set) var torchLevel: Double

    /// Whether night mode is on: every screen of the app in red on black, to keep eyes used to the
    /// dark (issue #61). Off by default, remembered between launches, never switched on or off
    /// automatically. The app never changes the screen's brightness; people use the device's own
    /// brightness control.
    ///
    /// Other features read it to work in the dark, and may turn it on with ``setNightMode(_:)``.
    public private(set) var isNightModeOn: Bool

    /// Whether night mode also tints the live viewfinder red. Off by default: the viewfinder
    /// keeps its natural colors. Only the preview on screen is tinted; photos never change.
    public private(set) var tintsViewfinderInNightMode: Bool

    /// Where the settings are stored. ``SharedSettingsSync`` watches it and
    /// ``makeSnapshot()`` copies it.
    let defaults: UserDefaults

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
        overlays = OverlayOptions(defaults: defaults)
        // An unknown stored value, for example from a later version, falls back to the default.
        fastShutter = defaults.string(forKey: Key.fastShutter).flatMap(FastShutter.init(rawValue:)) ?? .handheld
        flashMode = defaults.string(forKey: Key.flashMode).flatMap(FlashMode.init(rawValue:)) ?? .off
        torchLevel = defaults.object(forKey: Key.torchLevel) == nil
            ? LightModel.defaultTorchLevel : LightModel.clampedTorchLevel(defaults.double(forKey: Key.torchLevel))
        isNightModeOn = defaults.bool(forKey: Key.isNightModeOn)
        tintsViewfinderInNightMode = defaults.bool(forKey: Key.tintsViewfinderInNightMode)
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

    /// Whether any selected format is developed by the app from the RAW (HEIF or JPEG).
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

    /// Which processed copy is paired with the RAW in Photos when RAW, HEIF and JPEG are all
    /// saved. ``RAWPairing/heif`` by default.
    public var rawPairing: RAWPairing {
        save.rawPairing
    }

    /// Whether the choice of ``rawPairing`` applies: RAW, HEIF and JPEG are all selected and
    /// the device has Bayer RAW.
    ///
    /// - Parameter deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW.
    /// - Returns: `true` when an interface should offer the choice.
    public func offersRAWPairingChoice(deviceSupportsBayerRAW: Bool) -> Bool {
        deviceSupportsBayerRAW && save.offersRAWPairingChoice
    }

    /// Sets which processed copy is paired with the RAW, and saves the change.
    ///
    /// - Parameter pairing: The copy to pair.
    public func setRAWPairing(_ pairing: RAWPairing) {
        save.rawPairing = pairing
        store()
    }

    /// Whether front camera photos are saved mirrored, as the viewfinder shows them. Off by
    /// default.
    public var mirrorsFrontCamera: Bool {
        save.mirrorsFrontCamera
    }

    /// Sets whether front camera photos are saved mirrored, and saves the change.
    ///
    /// - Parameter isOn: Whether they are mirrored.
    public func setMirrorsFrontCamera(_ isOn: Bool) {
        save.mirrorsFrontCamera = isOn
        store()
    }

    /// How the HEIF and JPEG copies are encoded. ``DevelopedFileOptions/init()`` by default.
    public var fileOptions: DevelopedFileOptions {
        save.fileOptions
    }

    /// Sets how the HEIF and JPEG copies are encoded, and saves the change.
    ///
    /// - Parameter options: The options.
    public func setFileOptions(_ options: DevelopedFileOptions) {
        save.fileOptions = options
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

    /// Replaces the viewfinder overlay options, and saves the change.
    ///
    /// - Parameter options: The new options.
    public func setOverlays(_ options: OverlayOptions) {
        overlays = options
        options.store(in: defaults)
    }

    /// Sets how fast a shutter full auto prefers, and saves the change.
    ///
    /// - Parameter choice: The choice.
    public func setFastShutter(_ choice: FastShutter) {
        fastShutter = choice
        defaults.set(choice.rawValue, forKey: Key.fastShutter)
    }

    /// Sets when the flash fires, and saves the change.
    ///
    /// - Parameter mode: The flash mode.
    public func setFlashMode(_ mode: FlashMode) {
        flashMode = mode
        defaults.set(mode.rawValue, forKey: Key.flashMode)
    }

    /// Sets the torch's brightness, and saves the change.
    ///
    /// - Parameter level: The brightness, moved inside ``LightModel/torchLevelRange``.
    public func setTorchLevel(_ level: Double) {
        torchLevel = LightModel.clampedTorchLevel(level)
        defaults.set(torchLevel, forKey: Key.torchLevel)
    }

    /// Turns night mode on or off, and saves the change.
    ///
    /// - Parameter isOn: Whether the app's screens are red on black.
    public func setNightMode(_ isOn: Bool) {
        isNightModeOn = isOn
        defaults.set(isOn, forKey: Key.isNightModeOn)
    }

    /// Sets whether night mode tints the live viewfinder red, and saves the change.
    ///
    /// - Parameter isOn: Whether the viewfinder is tinted in night mode.
    public func setTintsViewfinderInNightMode(_ isOn: Bool) {
        tintsViewfinderInNightMode = isOn
        defaults.set(isOn, forKey: Key.tintsViewfinderInNightMode)
    }

    /// Reads every setting from the store again, for a change made by another process (a
    /// Control Center control) or by ``apply(_:)``.
    ///
    /// Only values that differ are assigned, so the interface redraws only for what changed. A
    /// setting added to this type needs a line here.
    ///
    /// - Returns: `true` when any setting changed.
    @discardableResult
    public func reload() -> Bool {
        let stored = NopeSettings(defaults: defaults)
        let changes = [
            update(\.save, from: stored),
            update(\.showsManualControls, from: stored),
            update(\.startsInCleanView, from: stored),
            update(\.overlays, from: stored),
            update(\.fastShutter, from: stored),
            update(\.flashMode, from: stored),
            update(\.torchLevel, from: stored),
            update(\.isNightModeOn, from: stored),
            update(\.tintsViewfinderInNightMode, from: stored),
        ]
        return changes.contains(true)
    }

    /// Copies one setting from freshly loaded settings if it differs.
    ///
    /// - Parameters:
    ///   - keyPath: The setting.
    ///   - stored: Settings just loaded from the same store.
    /// - Returns: `true` when the value changed.
    private func update<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<NopeSettings, Value>, from stored: NopeSettings
    ) -> Bool {
        guard self[keyPath: keyPath] != stored[keyPath: keyPath] else { return false }
        self[keyPath: keyPath] = stored[keyPath: keyPath]
        return true
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
        /// How fast a shutter full auto prefers, a ``FastShutter`` raw value.
        static let fastShutter = "NopeSettings.fastShutter"
        /// When the flash fires, a ``FlashMode`` raw value.
        static let flashMode = "NopeSettings.flashMode"
        /// The torch's brightness, a number from 0.01 to 1.
        static let torchLevel = "NopeSettings.torchLevel"
        /// Whether night mode is on, a Boolean.
        static let isNightModeOn = "NopeSettings.isNightModeOn"
        /// Whether night mode tints the viewfinder, a Boolean.
        static let tintsViewfinderInNightMode = "NopeSettings.tintsViewfinderInNightMode"
    }
}
