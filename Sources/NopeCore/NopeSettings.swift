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
    /// Other features read it to work in the dark. The astro helper turns it on, and turns it off
    /// again when the helper ends if it turned it on (``CameraModel/setAstro(_:settings:)``).
    public private(set) var isNightModeOn: Bool

    /// Whether night mode stays on after the astro helper ends, when the helper turned it on.
    /// Off by default: leaving Astro returns night mode to what it was before (owner decision for
    /// 1.0.0). A night mode the person turned on, or changed while the helper was on, is never
    /// turned off by the helper either way.
    public private(set) var keepsNightModeAfterAstro: Bool

    /// Whether night mode is on because the astro helper turned it on, and the person hasn't
    /// changed it since. Leaving the helper turns night mode off again while this is `true`
    /// (unless ``keepsNightModeAfterAstro``).
    ///
    /// It is stored in the shared store, so a change from another process (a Control Center
    /// control) clears it; a relaunch clears it too, keeping night mode as it was
    /// (``CameraModel/forgetNightModeFromAstroAtLaunch(settings:)``). It is
    /// kept under a key outside ``SharedSettingsStore/keyPrefix``: it is the app's state, not a
    /// setting, so presets and the Lock Screen camera's snapshot don't carry it.
    public private(set) var isNightModeFromAstro: Bool

    /// Whether night mode also tints the live viewfinder red. Off by default: the viewfinder
    /// keeps its natural colors. Only the preview on screen is tinted; photos never change.
    public private(set) var tintsViewfinderInNightMode: Bool

    /// Whether the screen stays on while the camera is showing (Keep Screen On, issue #97). Off
    /// by default. ``SeriesScreenKeeper`` applies it with ``KeepScreenOnRule``: the screen dims
    /// after a while without a touch or a photo, and the phone's Auto-Lock applies again after
    /// ``KeepScreenOnRule/limit``. The Lock Screen camera doesn't use it.
    public private(set) var keepsScreenOn: Bool

    /// How long Keep Screen On waits without a touch or photo before it dims the screen (Dim
    /// After, issue #119). ``DimAfter/standard`` (2 minutes) by default, so nothing changes for
    /// anyone who doesn't choose. ``SeriesScreenKeeper`` applies it through
    /// ``KeepScreenOnConditions/dimAfter``; Low Power Mode and heat still dim sooner, and a
    /// series still dims at once.
    public private(set) var dimAfter: DimAfter

    /// Whether a Live Activity shows a series and its saving on the Lock Screen and in the
    /// Dynamic Island (issue #64). Off by default.
    public private(set) var showsLiveActivity: Bool

    /// Whether faces the camera detects steer autofocus and auto exposure (Face Detection, issue
    /// #57). Off by default (owner decision, issue #80); on gives the system's own behavior. The
    /// app passes it to ``CameraModel/manual`` with ``AutoControlIntent/setFollowsFaces(_:)``.
    public private(set) var followsFaces: Bool

    /// What a pinch on the viewfinder does (issue #95): ``PinchAction/switchLenses`` by default.
    /// The camera screen reads it with ``CameraModel/pinchSwitchesLenses(setting:)``.
    public private(set) var pinch: PinchAction

    /// How many photos one press takes in Burst (Burst Limit, issue #121). ``BurstLimit/off`` by
    /// default. Stored, in presets and in the Lock Screen camera's snapshot; not yet read by the
    /// burst itself (see ``BurstLimit``).
    public private(set) var burstLimit: BurstLimit

    /// Whether the camera shows the "Processed" marker before a photo is taken with a lens
    /// without Bayer RAW (issue #80). On by default. Off hides the marker only: the photo is
    /// still the labeled processed fallback, VoiceOver still names its format, and the photo's
    /// details still say the phone processed it.
    public private(set) var showsProcessedMarker: Bool

    /// The photo size chosen for each lens that offers a choice (``Lens/photoSizeChoices``,
    /// issue #57). Empty by default: every lens at its default size. The app passes it to the
    /// camera with ``CameraIntent/setPhotoSizes(_:)``. Lens identifiers are the app's own and
    /// stay on the device.
    public private(set) var photoSizes: [Lens.ID: PhotoDimensions]

    /// Whether Siri, Shortcuts and other assistants may use the app's actions (Assistant Access,
    /// issue #82). Off by default, for fresh installs and updates. It changes only on its
    /// Settings page (``setAssistantAccess(_:)``) and with Factory Defaults applied in the app:
    /// never through an assistant, a control or a preset (`docs/design/assistant-access.md`,
    /// 3.5). The check is ``assistantAccess(deviceIsLocked:)``.
    public private(set) var assistantAccess: Bool

    /// When the app asks before an assistant action runs. ``AssistantAskLevel/everyAction`` by
    /// default; kept while ``assistantAccess`` is off and used when it is turned on. Changed
    /// only as ``assistantAccess`` is.
    public private(set) var assistantAsk: AssistantAskLevel

    /// Where the settings are stored. ``SharedSettingsSync`` watches it and
    /// ``makeSnapshot()`` copies it.
    let defaults: UserDefaults

    /// Loads the settings, using the default for any value not stored yet or not readable.
    ///
    /// Unreadable save settings fall back to ``SaveSettings/init()``, which removes every
    /// optional detail and doesn't sign: the most private choice (AGENTS.md, "Fail closed").
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
        // A missing value is the default, off; so is a preset saved before the setting existed.
        keepsScreenOn = defaults.bool(forKey: Key.keepsScreenOn)
        // A missing value (settings or a preset from before the choice) or an unknown one is
        // the default, 2 Minutes.
        dimAfter = defaults.string(forKey: Key.dimAfter).flatMap(DimAfter.init(rawValue:)) ?? .standard
        // A missing value is the default, off: leaving Astro restores night mode.
        keepsNightModeAfterAstro = defaults.bool(forKey: Key.keepsNightModeAfterAstro)
        isNightModeFromAstro = defaults.bool(forKey: Key.isNightModeFromAstro)
        showsLiveActivity = defaults.bool(forKey: Key.showsLiveActivity)
        // A missing value is the default, off.
        followsFaces = defaults.bool(forKey: Key.followsFaces)
        // A missing value (settings or a preset from before 1.0.0) or an unknown one is the
        // default, Switch Lenses.
        pinch = defaults.string(forKey: Key.pinch).flatMap(PinchAction.init(rawValue:)) ?? .switchLenses
        // A missing value (settings or a preset from before the setting) or an unknown one is
        // the default, Off.
        burstLimit = defaults.string(forKey: Key.burstLimit).flatMap(BurstLimit.init(rawValue:)) ?? .standard
        showsProcessedMarker =
            defaults.object(forKey: Key.showsProcessedMarker) == nil || defaults.bool(forKey: Key.showsProcessedMarker)
        // Unreadable sizes fall back to the defaults: every lens at its default size.
        photoSizes = defaults.data(forKey: Key.photoSizes).flatMap {
            try? JSONDecoder().decode([Lens.ID: PhotoDimensions].self, from: $0)
        } ?? [:]
        // A missing value is the default, off; an unknown choice falls back to Every Action.
        assistantAccess = defaults.bool(forKey: Key.assistantAccess)
        assistantAsk = defaults.string(forKey: Key.assistantAsk).flatMap(AssistantAskLevel.init(rawValue:)) ?? .everyAction
        migrateManualControlsOption()
    }

    /// The formats each photo is saved in. Never empty; RAW only by default.
    public var formats: Set<PhotoFormat> {
        save.formats
    }

    /// Which optional metadata items each file carries. The default removes them all.
    public var metadata: MetadataSettings {
        save.metadata
    }

    /// Whether each photo is signed with Content Credentials. Off by default, and separate from
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
    /// On a device without Bayer RAW, a selection of RAW alone (the default) leaves nothing the
    /// device can save; HEIF then stands in, the processed fallback a lens gives by default
    /// (``Lens/processedFallback``), so the list is never empty.
    ///
    /// - Parameter deviceSupportsBayerRAW: Whether any camera on the device gives Bayer RAW.
    /// - Returns: ``orderedFormats`` without RAW on a device that has none, or HEIF when nothing
    ///   else is left.
    public func selectedFormats(deviceSupportsBayerRAW: Bool) -> [PhotoFormat] {
        let available = orderedFormats.filter { Self.isAvailable($0, deviceSupportsBayerRAW: deviceSupportsBayerRAW) }
        return available.isEmpty ? [.heif] : available
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

    /// Turns the standard file tags on or off, and saves the change.
    ///
    /// - Parameter isOn: See ``MetadataSettings/writesStandardFileTags``.
    public func setWritesStandardFileTags(_ isOn: Bool) {
        save.metadata.writesStandardFileTags = isOn
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

    /// Turns night mode on or off as the person's choice, and saves the change. Use it for every
    /// control the person uses: the Night Mode switch, the Control Center and Lock Screen control,
    /// and Siri and Shortcuts.
    ///
    /// The choice is the person's from then on: if the astro helper had turned night mode on,
    /// leaving the helper no longer turns it off (``isNightModeFromAstro`` becomes `false`).
    ///
    /// - Parameter isOn: Whether the app's screens are red on black.
    public func setNightMode(_ isOn: Bool) {
        storeNightMode(isOn)
        setNightModeFromAstro(false)
    }

    /// Sets whether night mode stays on after the astro helper ends, and saves the change.
    ///
    /// - Parameter isOn: Whether night mode stays on when the helper that turned it on ends.
    public func setKeepsNightModeAfterAstro(_ isOn: Bool) {
        keepsNightModeAfterAstro = isOn
        defaults.set(isOn, forKey: Key.keepsNightModeAfterAstro)
    }

    /// Turns night mode on for the astro helper, if it is off, and records that the helper did,
    /// so ``nightModeAstroDidEnd()`` can turn it off again. A night mode already on is left as
    /// it is: it is the person's.
    func turnOnNightModeForAstro() {
        guard !isNightModeOn else { return }
        storeNightMode(true)
        setNightModeFromAstro(true)
    }

    /// Returns night mode to what it was before the astro helper turned it on: off, when the
    /// helper turned it on, the person hasn't changed it since, and
    /// ``keepsNightModeAfterAstro`` is off. Otherwise night mode stays as it is. Either way, the
    /// helper no longer owns it.
    func nightModeAstroDidEnd() {
        guard isNightModeFromAstro else { return }
        setNightModeFromAstro(false)
        if !keepsNightModeAfterAstro { storeNightMode(false) }
    }

    /// Records night mode and saves it.
    ///
    /// - Parameter isOn: Whether night mode is on.
    private func storeNightMode(_ isOn: Bool) {
        isNightModeOn = isOn
        defaults.set(isOn, forKey: Key.isNightModeOn)
    }

    /// Records whether the astro helper turned night mode on, and saves it.
    ///
    /// - Parameter isOn: The new ``isNightModeFromAstro``.
    func setNightModeFromAstro(_ isOn: Bool) {
        isNightModeFromAstro = isOn
        defaults.set(isOn, forKey: Key.isNightModeFromAstro)
    }

    /// Sets whether night mode tints the live viewfinder red, and saves the change.
    ///
    /// - Parameter isOn: Whether the viewfinder is tinted in night mode.
    public func setTintsViewfinderInNightMode(_ isOn: Bool) {
        tintsViewfinderInNightMode = isOn
        defaults.set(isOn, forKey: Key.tintsViewfinderInNightMode)
    }

    /// Turns Keep Screen On on or off, and saves the change.
    ///
    /// - Parameter isOn: Whether the screen stays on while the camera is showing.
    public func setKeepsScreenOn(_ isOn: Bool) {
        keepsScreenOn = isOn
        defaults.set(isOn, forKey: Key.keepsScreenOn)
    }

    /// Sets how long Keep Screen On waits before it dims the screen, and saves the change.
    ///
    /// - Parameter choice: The Dim After choice.
    public func setDimAfter(_ choice: DimAfter) {
        dimAfter = choice
        defaults.set(choice.rawValue, forKey: Key.dimAfter)
    }

    /// Turns the Live Activity on or off, and saves the change.
    ///
    /// - Parameter isOn: Whether a Live Activity shows a series and its saving.
    public func setShowsLiveActivity(_ isOn: Bool) {
        showsLiveActivity = isOn
        defaults.set(isOn, forKey: Key.showsLiveActivity)
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
            update(\.keepsScreenOn, from: stored),
            update(\.dimAfter, from: stored),
            update(\.keepsNightModeAfterAstro, from: stored),
            update(\.isNightModeFromAstro, from: stored),
            update(\.showsLiveActivity, from: stored),
            update(\.followsFaces, from: stored),
            update(\.pinch, from: stored),
            update(\.burstLimit, from: stored),
            update(\.showsProcessedMarker, from: stored),
            update(\.photoSizes, from: stored),
            update(\.assistantAccess, from: stored),
            update(\.assistantAsk, from: stored),
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

    /// Turns Face Detection on or off, and saves the change.
    ///
    /// - Parameter isOn: Whether detected faces steer autofocus and auto exposure.
    public func setFollowsFaces(_ isOn: Bool) {
        followsFaces = isOn
        defaults.set(isOn, forKey: Key.followsFaces)
    }

    /// Sets what a pinch on the viewfinder does, and saves the change.
    ///
    /// - Parameter action: Switch Lenses or Off.
    public func setPinch(_ action: PinchAction) {
        pinch = action
        defaults.set(action.rawValue, forKey: Key.pinch)
    }

    /// Sets how many photos one press takes in Burst, and saves the change.
    ///
    /// - Parameter limit: Off, or the number of photos.
    public func setBurstLimit(_ limit: BurstLimit) {
        burstLimit = limit
        defaults.set(limit.rawValue, forKey: Key.burstLimit)
    }

    /// Shows or hides the "Processed" marker, and saves the change.
    ///
    /// - Parameter isOn: Whether the camera shows the marker before a photo is taken with a lens
    ///   without Bayer RAW.
    public func setShowsProcessedMarker(_ isOn: Bool) {
        showsProcessedMarker = isOn
        defaults.set(isOn, forKey: Key.showsProcessedMarker)
    }

    /// The photo size chosen for a lens, as the camera will use it: the choice when the lens
    /// offers it, otherwise the lens's default.
    ///
    /// - Parameter lens: A lens.
    /// - Returns: The size, or `nil` when the lens reported none.
    public func photoSize(for lens: Lens) -> PhotoDimensions? {
        lens.photoSize(for: photoSizes[lens.id])
    }

    /// Chooses a lens's photo size, and saves the change. Choosing the lens's default removes
    /// the stored choice.
    ///
    /// - Parameters:
    ///   - size: One of the lens's ``Lens/photoSizeChoices``; any other size does nothing.
    ///   - lens: The lens.
    public func setPhotoSize(_ size: PhotoDimensions, for lens: Lens) {
        guard lens.photoSizeChoices.contains(size) else { return }
        photoSizes[lens.id] = size == lens.defaultPhotoSize ? nil : size
        // Encoding a dictionary of strings to pairs of integers can't fail.
        defaults.set(try? JSONEncoder().encode(photoSizes), forKey: Key.photoSizes)
    }

    /// Turns Assistant Access on or off, and saves the change. Only the Assistant Access page
    /// calls it.
    ///
    /// - Parameter isOn: Whether assistants may use the app's actions.
    public func setAssistantAccess(_ isOn: Bool) {
        assistantAccess = isOn
        defaults.set(isOn, forKey: Key.assistantAccess)
    }

    /// Sets when the app asks before an assistant action runs, and saves the change. Only the
    /// Assistant Access page calls it.
    ///
    /// - Parameter level: The choice.
    public func setAssistantAsk(_ level: AssistantAskLevel) {
        assistantAsk = level
        defaults.set(level.rawValue, forKey: Key.assistantAsk)
    }

    /// Puts back the Privacy group's photo settings (Details in Each Photo, Location and Sign
    /// Each Photo, all held in ``metadata``) and Assistant Access, after a preset replaced the
    /// other settings. Privacy rule (`docs/design/assistant-access.md`, 7.4): a preset applied
    /// through an assistant never changes a Privacy setting, and no preset changes Assistant
    /// Access.
    ///
    /// - Parameters:
    ///   - metadata: The metadata settings to keep, or `nil` to keep the preset's.
    ///   - assistant: The Assistant Access values to keep, or `nil` to keep the preset's.
    func restore(metadata: MetadataSettings?, assistant: (isOn: Bool, ask: AssistantAskLevel)?) {
        if let metadata {
            save.metadata = metadata
            store()
        }
        if let assistant {
            setAssistantAccess(assistant.isOn)
            setAssistantAsk(assistant.ask)
        }
    }

    /// The Assistant Access check with the stored choices.
    ///
    /// - Parameter deviceIsLocked: Whether the device is locked now.
    /// - Returns: The check.
    public func assistantAccess(deviceIsLocked: Bool) -> AssistantAccess {
        AssistantAccess(isOn: assistantAccess, ask: assistantAsk, deviceIsLocked: deviceIsLocked)
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
        /// Whether the screen stays on while the camera is showing, a Boolean.
        static let keepsScreenOn = "NopeSettings.keepsScreenOn"
        /// How long Keep Screen On waits before it dims, a ``DimAfter`` raw value.
        static let dimAfter = "NopeSettings.dimAfter"
        /// Whether night mode stays on after the astro helper ends, a Boolean.
        static let keepsNightModeAfterAstro = "NopeSettings.keepsNightModeAfterAstro"
        /// Whether the astro helper turned night mode on, a Boolean. Not a setting, so outside
        /// ``SharedSettingsStore/keyPrefix``: presets and snapshots don't carry it.
        static let isNightModeFromAstro = "NopeAstro.isNightModeFromAstro"
        /// Whether the Live Activity is on, a Boolean.
        static let showsLiveActivity = "NopeSettings.showsLiveActivity"
        /// Whether detected faces steer autofocus and auto exposure, a Boolean.
        static let followsFaces = "NopeSettings.followsFaces"
        /// What a pinch on the viewfinder does, a ``PinchAction`` raw value.
        static let pinch = "NopeSettings.pinch"
        /// How many photos one press takes in Burst, a ``BurstLimit`` raw value.
        static let burstLimit = "NopeSettings.burstLimit"
        /// Whether the "Processed" marker is shown, a Boolean.
        static let showsProcessedMarker = "NopeSettings.showsProcessedMarker"
        /// The photo size chosen for each lens, as JSON-encoded `[Lens.ID: PhotoDimensions]`.
        static let photoSizes = "NopeSettings.photoSizes"
        /// Whether Assistant Access is on, a Boolean. Inside ``SharedSettingsStore/keyPrefix``,
        /// so the Lock Screen camera's snapshot shows it; presets leave it out
        /// (``assistantKeys``).
        static let assistantAccess = "NopeSettings.assistantAccess"
        /// When to ask first, an ``AssistantAskLevel`` raw value.
        static let assistantAsk = "NopeSettings.assistantAsk"
        /// The Assistant Access keys, which no preset stores or applies.
        static let assistantKeys: Set<String> = [assistantAccess, assistantAsk]
    }
}
