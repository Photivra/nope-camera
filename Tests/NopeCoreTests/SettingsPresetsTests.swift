import Foundation
import Testing

@testable import NopeCore

/// Settings presets (issue #72): what a preset covers, its encoding, the saved list, applying,
/// permissions and undo.
@MainActor
struct SettingsPresetsTests {
    /// One change per stored `NopeSettings` property, each away from its default.
    ///
    /// When this test fails with "no change for", a setting was added to `NopeSettings`: add a
    /// line here that changes it, and the test checks that presets save and restore it.
    static let settingChanges: [String: @MainActor (NopeSettings) -> Void] = [
        "save": { $0.setFormat(.jpeg, isSelected: true) },
        "showsManualControls": { $0.setShowsManualControls(true) },
        "startsInCleanView": { $0.setStartsInCleanView(true) },
        "overlays": {
            var overlays = $0.overlays
            overlays.showsGrid = true
            $0.setOverlays(overlays)
        },
        "fastShutter": { $0.setFastShutter(.freezeMotion) },
        "flashMode": { $0.setFlashMode(.auto) },
        "torchLevel": { $0.setTorchLevel(0.75) },
        "isNightModeOn": { $0.setNightMode(true) },
        "tintsViewfinderInNightMode": { $0.setTintsViewfinderInNightMode(true) },
        "keepsNightModeAfterAstro": { $0.setKeepsNightModeAfterAstro(true) },
        "followsFaces": { $0.setFollowsFaces(true) },
        "pinch": { $0.setPinch(.off) },
        "showsProcessedMarker": { $0.setShowsProcessedMarker(false) },
        "showsLiveActivity": { $0.setShowsLiveActivity(true) },
        "photoSizes": {
            // A lens without Bayer RAW that offers two sizes; the larger isn't the default.
            let lens = Lens(
                id: "sizes", kind: .wide, bayerRAWFormat: nil,
                photoDimensions: [PhotoDimensions(width: 4032, height: 3024), PhotoDimensions(width: 8064, height: 6048)])
            $0.setPhotoSize(PhotoDimensions(width: 8064, height: 6048), for: lens)
        },
    ]

    /// `NopeSettings` properties that aren't settings: where they are stored, Observation's
    /// bookkeeping, and whether the astro helper turned night mode on (the app's state, which a
    /// preset never carries; `AstroNightModeTests`).
    static let notSettings: Set<String> = ["defaults", "$observationRegistrar", "isNightModeFromAstro"]

    /// The names of the stored properties of a value, without Observation's `_` prefix.
    static func storedProperties(of value: Any) -> [String] {
        Mirror(reflecting: value).children.compactMap(\.label).map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
    }

    /// A property's value, compared with `==` (text would list a set's members in any order).
    struct Value: Equatable {
        /// The value.
        let value: Any?

        static func == (lhs: Value, rhs: Value) -> Bool {
            guard let left = lhs.value as? any Equatable else { return false }
            return left.isEqual(to: rhs.value)
        }
    }

    /// A property's value, for comparing values of any type.
    static func value(_ name: String, of settings: NopeSettings) -> Value {
        Value(value: Mirror(reflecting: settings).children.first { $0.label == name || $0.label == "_" + name }?.value)
    }

    @Test func everySettingIsSavedAndRestored() throws {
        let properties = Self.storedProperties(of: NopeSettings(defaults: ScratchDefaults().defaults))
            .filter { !Self.notSettings.contains($0) }
        #expect(!properties.isEmpty)
        for name in properties {
            let change = try #require(Self.settingChanges[name], "no change for NopeSettings.\(name): add one to settingChanges")
            let source = ScratchDefaults()
            let changed = NopeSettings(defaults: source.defaults)
            change(changed)
            let fresh = NopeSettings(defaults: ScratchDefaults().defaults)
            #expect(Self.value(name, of: changed) != Self.value(name, of: fresh), "the change to \(name) must leave its default")

            let presets = SettingsPresets(settings: changed)
            let preset = try presets.saveCurrent(named: "All", camera: nil)
            let target = ScratchDefaults()
            let other = NopeSettings(defaults: target.defaults)
            #expect(other.apply(preset.settings))
            #expect(Self.value(name, of: other) == Self.value(name, of: changed), "\(name) isn't restored by a preset")
        }
    }

    @Test func factoryDefaultsRestoresEverySettingAndKeepsPresets() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        for change in Self.settingChanges.values { change(settings) }
        let presets = SettingsPresets(settings: settings)
        try presets.saveCurrent(named: "Night", camera: nil)

        let result = await presets.apply(.factoryDefaults, camera: nil, location: nil)

        let fresh = NopeSettings(defaults: ScratchDefaults().defaults)
        for name in Self.settingChanges.keys {
            #expect(Self.value(name, of: settings) == Self.value(name, of: fresh), "\(name) isn't reset")
        }
        #expect(result == PresetApplyResult(choice: .factoryDefaults, name: nil, isApplied: true, notices: [.cameraNotReady]))
        #expect(presets.lastResult == result)
        #expect(presets.saved.map(\.name) == ["Night"])
        #expect(SettingsPresets(settings: settings).saved.map(\.name) == ["Night"])
    }

    @Test func anOlderPresetGivesALaterSettingItsDefault() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let preset = try presets.saveCurrent(named: "Old", camera: nil)
        // As if the preset was saved before "Night Mode" existed: its key isn't in the snapshot.
        var values = try #require(
            PropertyListSerialization.propertyList(from: preset.settings.values, format: nil) as? [String: Any])
        values.removeValue(forKey: NopeSettings.Key.isNightModeOn)
        let older = SettingsPreset(
            id: preset.id, name: "Old",
            settings: NopeSettingsSnapshot(
                values: try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)),
            camera: .factory)
        settings.setNightMode(true)

        #expect(settings.apply(older.settings))
        #expect(!settings.isNightModeOn)
    }

    @Test func aPresetWithARemovedGoldenGridAppliesThirds() throws {
        // Saved before issue #76 removed the golden ratio and golden spiral grids.
        for removed in ["goldenRatio", "goldenSpiral"] {
            let values: [String: Any] = [
                OverlayOptions.Key.showsGrid: true, OverlayOptions.Key.gridStyle: removed,
                OverlayOptions.Key.removedSpiralPlacement: 3,
            ]
            let plist = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            let preset = SettingsPreset(name: "Golden", settings: NopeSettingsSnapshot(values: plist), camera: .factory)
            let decoded = try JSONDecoder().decode(SettingsPreset.self, from: JSONEncoder().encode(preset))
            let settings = NopeSettings(defaults: ScratchDefaults().defaults)
            settings.setGridStyle(.square)
            #expect(settings.apply(decoded.settings))
            #expect(settings.overlays.showsGrid)
            #expect(settings.overlays.gridStyle == .thirds)
        }
    }

    @Test func factoryDefaultsGiveTheIssue80Defaults() async {
        // RAW only, signing off, Face Detection off and the Processed marker on (issue #80).
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        settings.setFormat(.heif, isSelected: true)
        settings.setSignsPhotos(true)
        settings.setFollowsFaces(true)
        settings.setShowsProcessedMarker(false)
        _ = await SettingsPresets(settings: settings).apply(.factoryDefaults, camera: nil, location: nil)
        #expect(settings.formats == [.raw])
        #expect(!settings.signsPhotos)
        #expect(!settings.followsFaces)
        #expect(settings.showsProcessedMarker)
    }

    @Test func aPresetSavedBeforeTheNewDefaultsDecodesAndKeepsItsChoices() throws {
        // Saved by 0.x before issue #80: RAW plus HEIF and signing stored as the person left
        // them; Face Detection and the Processed marker never stored.
        let save = #"{"formats":["raw","heif"],"metadata":{"removesAllOptionalDetails":true,"enabledItems":[],"signsPhotos":true,"ownerName":"","copyrightNotice":""},"developedLook":"standard"}"#
        let values: [String: Any] = [NopeSettings.Key.save: Data(save.utf8), NopeSettings.Key.isNightModeOn: true]
        let plist = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        let json = #"{"id":"7A3F4B2E-0C1D-4E5F-8A9B-112233445566","name":"Before","version":1,"settings":{"values":""#
            + plist.base64EncodedString() + #""},"camera":{}}"#
        let preset = try JSONDecoder().decode(SettingsPreset.self, from: Data(json.utf8))
        #expect(preset.name == "Before")
        #expect(preset.camera == .factory)

        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        #expect(settings.apply(preset.settings))
        // What the preset stored is kept.
        #expect(settings.formats == [.raw, .heif])
        #expect(settings.signsPhotos)
        #expect(settings.isNightModeOn)
        // What it never stored takes today's defaults.
        #expect(!settings.followsFaces)
        #expect(settings.showsProcessedMarker)
    }

    @Test func aMinimalPresetDecodesWithDefaults() throws {
        let snapshot = SettingsPreset.factorySettings
        let json = """
            {"id":"\(UUID().uuidString)","name":"Plain","settings":\(String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self))}
            """
        let preset = try JSONDecoder().decode(SettingsPreset.self, from: Data(json.utf8))
        #expect(preset.version == 1)
        #expect(preset.camera == .factory)
        #expect(preset.settings == snapshot)
    }

    @Test func aLaterVersionsPresetStillDecodes() throws {
        let snapshot = String(decoding: try JSONEncoder().encode(SettingsPreset.factorySettings), as: UTF8.self)
        let json = """
            {"id":"\(UUID().uuidString)","name":"Later","version":7,"settings":\(snapshot),"future":true,
             "camera":{"drive":"hyperlapse","metering":"matrix","iso":400,"newThing":1}}
            """
        let preset = try JSONDecoder().decode(SettingsPreset.self, from: Data(json.utf8))
        #expect(preset.version == 7)
        #expect(preset.camera.iso == 400)
        #expect(CameraSetup.driveMode(named: preset.camera.drive) == .single)
        #expect(preset.camera.manualSettings.metering == ManualSettings.automatic.metering)
    }

    @Test func aDamagedPresetIsSkippedAndTheOthersLoad() throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        try SettingsPresets(settings: settings).saveCurrent(named: "Good", camera: nil)
        let stored = try #require(scratch.defaults.data(forKey: SettingsPresets.storageKey))
        var library = try #require(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        var list = try #require(library["presets"] as? [Any])
        list.append(["name": "No identifier"])
        library["presets"] = list
        scratch.defaults.set(try JSONSerialization.data(withJSONObject: library), forKey: SettingsPresets.storageKey)

        #expect(SettingsPresets(settings: settings).saved.map(\.name) == ["Good"])

        scratch.defaults.set(Data("not json".utf8), forKey: SettingsPresets.storageKey)
        #expect(SettingsPresets(settings: settings).saved.isEmpty)
    }

    @Test func namesAreCheckedTrimmedAndSorted() throws {
        let scratch = ScratchDefaults()
        let presets = SettingsPresets(settings: NopeSettings(defaults: scratch.defaults))
        #expect(presets.problem(withName: "  ") == .empty)
        #expect(presets.problem(withName: String(repeating: "a", count: SettingsPresets.maximumNameLength + 1)) == .tooLong)
        #expect(presets.problem(withName: String(repeating: "a", count: SettingsPresets.maximumNameLength)) == nil)
        #expect(throws: PresetNameProblem.empty) { try presets.saveCurrent(named: "", camera: nil) }

        let astro = try presets.saveCurrent(named: "  Astro ", camera: nil)
        try presets.saveCurrent(named: "Bugs at night", camera: nil)
        try presets.saveCurrent(named: "acorns", camera: nil)
        #expect(astro.name == "Astro")
        #expect(presets.saved.map(\.name) == ["acorns", "Astro", "Bugs at night"])
        #expect(presets.problem(withName: "ASTRO") == .duplicate)
        #expect(presets.problem(withName: "astro", renaming: astro.id) == nil)
        #expect(presets.preset(withID: astro.id) == astro)

        try presets.rename(astro.id, to: "Zodiac")
        #expect(presets.saved.map(\.name) == ["acorns", "Bugs at night", "Zodiac"])
        #expect(throws: PresetNameProblem.duplicate) { try presets.rename(astro.id, to: "acorns") }
        try presets.rename(UUID(), to: "Nobody")
        #expect(presets.saved.count == 3)

        presets.delete(astro.id)
        #expect(presets.saved.map(\.name) == ["acorns", "Bugs at night"])
        #expect(SettingsPresets(settings: NopeSettings(defaults: scratch.defaults)).saved.map(\.name) == ["acorns", "Bugs at night"])
    }

    @Test func presetsAreNotPartOfTheSettingsSnapshot() throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        try SettingsPresets(settings: settings).saveCurrent(named: "One", camera: nil)
        #expect(!SharedSettingsStore.isSettingsKey(SettingsPresets.storageKey))
        let values = try #require(
            PropertyListSerialization.propertyList(from: try settings.makeSnapshot().values, format: nil) as? [String: Any])
        #expect(values[SettingsPresets.storageKey] == nil)
    }

    @Test func applyingAMissingOrDamagedPresetChangesNothing() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let missing = UUID()
        let result = await presets.apply(.saved(missing), camera: nil, location: nil)
        #expect(result == PresetApplyResult(choice: .saved(missing), name: nil, isApplied: false, notices: [.unreadable]))

        let damaged = SettingsPreset(name: "Damaged", settings: NopeSettingsSnapshot(values: Data("x".utf8)), camera: .factory)
        let library = try JSONEncoder().encode(SettingsPresets.Library(presets: [damaged]))
        scratch.defaults.set(library, forKey: SettingsPresets.storageKey)
        let reloaded = SettingsPresets(settings: settings)
        settings.setNightMode(true)
        let second = await reloaded.apply(.saved(damaged.id), camera: nil, location: nil)
        #expect(second == PresetApplyResult(choice: .saved(damaged.id), name: "Damaged", isApplied: false, notices: [.unreadable]))
        #expect(settings.isNightModeOn)
        #expect(!reloaded.canUndo)
    }

    /// Saves a preset with Location on, then turns Location off again.
    func presetWithLocation(_ settings: NopeSettings, _ presets: SettingsPresets) throws -> SettingsPreset {
        settings.setMetadataItem(.location, isIncluded: true)
        let preset = try presets.saveCurrent(named: "Places", camera: nil)
        settings.setMetadataItem(.location, isIncluded: false)
        return preset
    }

    @Test func locationTurnsOnOnlyWithAccess() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let preset = try presetWithLocation(settings, presets)
        let provider = FakeLocationProvider(access: .notDetermined, afterRequest: .allowed)

        let result = await presets.apply(.saved(preset.id), camera: nil, location: LocationTagging(provider: provider))

        #expect(settings.metadata.isOn(.location))
        #expect(result.notices == [.cameraNotReady])
        #expect(await provider.requests == 1)
    }

    @Test func locationStaysOffWhenAccessIsDenied() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let preset = try presetWithLocation(settings, presets)
        let provider = FakeLocationProvider(access: .notDetermined, afterRequest: .denied)

        let denied = await presets.apply(.saved(preset.id), camera: nil, location: LocationTagging(provider: provider))
        #expect(!settings.metadata.isOn(.location))
        #expect(denied.notices == [.locationNotAllowed, .cameraNotReady])
        #expect(denied.isApplied)

        let noService = await presets.apply(.saved(preset.id), camera: nil, location: nil)
        #expect(!settings.metadata.isOn(.location))
        #expect(noService.notices == [.locationNotAllowed, .cameraNotReady])
    }

    @Test func undoRestoresTheSettingsAndCamera() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        #expect(await presets.undo(camera: nil, location: nil) == false)
        let model = await CameraSetupTests.makeModel()
        settings.setNightMode(true)
        settings.setShowsManualControls(true)
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setValue(.iso, 800)))

        await presets.apply(.factoryDefaults, camera: model, location: nil)
        #expect(!settings.isNightModeOn)
        #expect(model.manual.settings.iso == nil)
        #expect(presets.canUndo)

        #expect(await presets.undo(camera: model, location: nil))
        #expect(settings.isNightModeOn)
        #expect(model.manual.settings.iso == 800)
        #expect(!presets.canUndo)
        #expect(presets.lastResult == nil)
    }

    /// A name is never used as a catalog key, so it shows as typed in Shortcuts, even when it
    /// matches one of the app's strings or holds format characters.
    @Test func theNameForShortcutsIsShownAsTyped() {
        for name in ["Preset", "Factory Defaults", "100% %@ %lld", "Astro"] {
            let preset = SettingsPreset(name: name, settings: NopeSettingsSnapshot(values: Data()), camera: .factory)
            #expect(preset.verbatimName.key == "%@", "\(name)")
            #expect(String(localized: preset.verbatimName) == name)
            #expect(LocalizedStringResource(stringLiteral: name).key == name, "a literal resource looks the name up")
        }
    }

    @Test func anUndoThatCanNotReadTheEarlierSettingsSaysSo() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let model = await CameraSetupTests.makeModel()
        let result = await presets.apply(.factoryDefaults, camera: model, location: nil)
        settings.setNightMode(true)
        presets.beforeLastApply = SettingsPreset(
            name: "", settings: NopeSettingsSnapshot(values: Data("damaged".utf8)), camera: .factory)

        #expect(await presets.undo(camera: model, location: nil) == false)
        #expect(settings.isNightModeOn, "nothing changed")
        #expect(!presets.canUndo, "settings that can't be read are no longer offered")
        #expect(presets.lastResult == result)
    }

    /// A preset with the astro helper on and "Manual controls" off: the helper turns manual
    /// controls on for its frames. The app follows the option with a task that runs after the
    /// apply; the apply already set the camera up, so the option isn't sent again.
    @Test func aPresetsManualControlsChangeIsNotSentAgain() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let model = await CameraSetupTests.makeModel()
        await model.send(.astro(.setOn(true)))
        #expect(model.astro.isOn && model.manual.isEnabled && !settings.showsManualControls)
        let astro = try presets.saveCurrent(named: "Astro", camera: model)
        await model.send(.astro(.setOn(false)))
        settings.setShowsManualControls(true)
        await model.send(.manual(.setEnabled(true)))

        await presets.apply(.saved(astro.id), camera: model, location: nil)
        #expect(!settings.showsManualControls)
        #expect(model.astro.isOn)
        // What the app's task does when the option changed.
        #expect(presets.handlesManualControlsChange(to: settings.showsManualControls))
        #expect(model.astro.isOn, "the helper stays on")
        // Sending it anyway would have turned the helper off with manual controls.
        let copy = await CameraSetupTests.makeModel()
        await copy.send(.astro(.setOn(true)))
        await copy.send(.manual(.setEnabled(false)))
        #expect(!copy.astro.isOn)

        // The answer is given once: the person's next change is sent.
        settings.setShowsManualControls(true)
        #expect(!presets.handlesManualControlsChange(to: settings.showsManualControls))
        // Without a camera, nothing was set up, so the change is sent.
        await presets.apply(.factoryDefaults, camera: nil, location: nil)
        #expect(!presets.handlesManualControlsChange(to: settings.showsManualControls))
    }

    @Test func aBusyCameraChangesNothing() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let model = await CameraSetupTests.makeModel()
        await presets.apply(.factoryDefaults, camera: model, location: nil)
        model.drive.beginBurst()
        settings.setNightMode(true)

        let result = await presets.apply(.factoryDefaults, camera: model, location: nil)

        #expect(result == PresetApplyResult(choice: .factoryDefaults, name: nil, isApplied: false, notices: [.cameraBusy]))
        #expect(settings.isNightModeOn)
        #expect(await presets.undo(camera: model, location: nil) == false)
        #expect(presets.canUndo)
    }

    /// While an apply waits (here for location access, held by the test), a second apply and an
    /// undo are refused as busy; once it finishes, one undo restores the earlier settings and a
    /// second has nothing left to undo. The wait is held open on purpose, so the test doesn't
    /// depend on which of two concurrent tasks the executor runs first.
    @Test func oneApplyAtATime() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let preset = try presetWithLocation(settings, presets)
        let provider = GatedLocationProvider()
        let location = LocationTagging(provider: provider)

        let first = Task { await presets.apply(.saved(preset.id), camera: nil, location: location) }
        await waitUntil { presets.isApplying }
        #expect(presets.isApplying)

        let second = await presets.apply(.factoryDefaults, camera: nil, location: nil)
        #expect(!second.isApplied)
        #expect(second.notices == [.cameraBusy])
        #expect(await presets.undo(camera: nil, location: location) == false)

        await provider.open()
        #expect(await first.value.isApplied)
        #expect(!presets.isApplying)

        #expect(await presets.undo(camera: nil, location: location))
        #expect(await presets.undo(camera: nil, location: location) == false)
    }
}

/// A location provider whose access request waits until the test opens it, so a preset apply
/// stays in progress for as long as a test needs.
actor GatedLocationProvider: LocationProviding {
    /// Whether requests answer at once.
    private var isOpen = false

    /// The requests waiting for ``open()``.
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Answers every waiting request, and every later one at once.
    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }

    func currentAccess() async -> LocationAccess {
        .allowed
    }

    func requestAccess() async -> LocationAccess {
        if !isOpen { await withCheckedContinuation { waiting.append($0) } }
        return .allowed
    }

    nonisolated func locations() -> AsyncStream<PhotoLocation> {
        AsyncStream { $0.finish() }
    }
}

/// A preset's camera part (``CameraSetup``): reading, applying and encoding it.
@MainActor
struct CameraSetupTests {
    /// A telephoto with manual exposure, for lens matching.
    static let telephoto = Lens(
        id: "tele", kind: .telephoto, bayerRAWFormat: "bgg4", magnification: 3, isoRange: 50...3200,
        exposureDurationRange: 0.0001...1, manualControls: ManualFixtures.full)

    /// A started model with the wide, ultra wide and telephoto lenses, a storage reader (for the
    /// astro helper) and instant waits.
    static func makeModel(lenses: [Lens] = [ManualFixtures.wide, ManualFixtures.basicLens, telephoto]) async -> CameraModel {
        let model = CameraModel(
            backend: ScriptedManualBackend(lenses: lenses), saver: CameraModelTests.saver(), sleep: { _ in },
            deviceStatusReader: FakeStatusReader(bytes: nil))
        await model.send(.start)
        return model
    }

    /// One change per ``CameraSetup`` value, each away from ``CameraSetup/factory`` and possible
    /// on the wide lens. When this test fails with "no change for", a value was added to
    /// `CameraSetup`: add a line here, and make `cameraSetup` and `applyCameraSetup` handle it.
    static let setupChanges: [String: (inout CameraSetup) -> Void] = [
        "lens": { $0.lens = CameraSetup.LensChoice(CameraSetupTests.telephoto) },
        "iso": { $0.iso = 400 },
        "shutter": { $0.shutter = 0.5 },
        "aperture": { $0.aperture = 2.8 },
        "focus": { $0.focus = 0.25 },
        "whiteBalance": { $0.whiteBalance = CameraSetup.WhiteBalanceValue(WhiteBalance(temperature: 3200, tint: 5)) },
        "exposureCompensation": { $0.exposureCompensation = 1 },
        "metering": { $0.metering = MeteringMode.spot.rawValue },
        "nearFocusLimit": { $0.nearFocusLimit = true },
        "drive": { $0.drive = CameraSetup.driveName(.timer(.threeSeconds)) },
        "bracket": { $0.bracket = CameraSetup.BracketValue(BracketSettings(frameCount: 3, step: 1)) },
        "intervalSeconds": { $0.intervalSeconds = 30 },
        "intervalCount": { $0.intervalCount = 50 },
        "intervalStopAfter": { $0.intervalStopAfter = IntervalSettings.StopAfter.time.rawValue },
        "intervalDuration": { $0.intervalDuration = 5400 },
        "astroIsOn": { $0.astroIsOn = true },
        "astroFrameCount": { $0.astroFrameCount = 50 },
        "astroStartDelay": { $0.astroStartDelay = 3 },
    ]

    /// The manual settings that a preset leaves out on purpose: locks belong to one scene.
    static let manualSettingsLeftOut: Set<String> = ["exposureLocked", "focusLocked"]

    @Test func everyCameraValueIsAppliedAndReadBack() async throws {
        let properties = SettingsPresetsTests.storedProperties(of: CameraSetup.factory)
        #expect(properties.count == Self.setupChanges.count)
        for name in properties {
            let change = try #require(Self.setupChanges[name], "no change for CameraSetup.\(name): add one to setupChanges")
            var setup = CameraSetup.factory
            change(&setup)
            #expect(setup != .factory)
            // The wide lens has every control except Close-Up; the astro helper sets its own values.
            if name != "lens" { setup.lens = CameraSetup.LensChoice(ManualFixtures.wide) }
            let model = await Self.makeModel(lenses: [ManualFixtures.wide.withNearFocusLimit, Self.telephoto])
            if name == "lens" || name == "nearFocusLimit" {
                setup.lens = setup.lens.map { $0.id == "wide" ? CameraSetup.LensChoice(ManualFixtures.wide.withNearFocusLimit) : $0 }
            }
            let manualOn = name != "nearFocusLimit" && name != "exposureCompensation" && name != "drive"
            let notices = await model.applyCameraSetup(setup, manualControlsOn: manualOn)
            if name == "astroIsOn" {
                #expect(model.astro.isOn)
            } else {
                #expect(notices == [], "\(name) wasn't applied")
                #expect(model.cameraSetup == setup, "\(name) isn't read back")
            }
        }
    }

    @Test func everyManualSettingIsInThePresetOrLeftOutOnPurpose() {
        let manual = Set(SettingsPresetsTests.storedProperties(of: ManualSettings.automatic))
        let covered: Set<String> = ["iso", "shutter", "aperture", "exposureCompensation", "focus", "whiteBalance", "metering"]
        #expect(manual == covered.union(Self.manualSettingsLeftOut), "a manual setting isn't in CameraSetup")
        #expect(Set(SettingsPresetsTests.storedProperties(of: CameraSetup.factory)).isSuperset(of: covered))
    }

    @Test func aPresetSavesAndAppliesTheCamera() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let model = await Self.makeModel()
        settings.setShowsManualControls(true)
        await model.send(.manual(.setEnabled(true)))
        await model.send(.selectLens("tele"))
        await model.send(.manual(.setValue(.iso, 1600)))
        await model.send(.drive(.setMode(.burst)))
        let saved = try presets.saveCurrent(named: "Tele", camera: model)
        #expect(saved.camera.lens?.id == "tele")

        let reset = await presets.apply(.factoryDefaults, camera: model, location: nil)
        #expect(reset.notices == [])
        #expect(model.selectedLensID == "wide")
        #expect(model.drive.mode == .single)
        #expect(!model.manual.isEnabled)

        let result = await presets.apply(.saved(saved.id), camera: model, location: nil)
        #expect(result == PresetApplyResult(choice: .saved(saved.id), name: "Tele", isApplied: true, notices: []))
        #expect(model.selectedLensID == "tele")
        #expect(model.manual.settings.iso == 1600)
        #expect(model.drive.mode == .burst)
    }

    @Test func valuesTheLensCantUseAreReported() async {
        let model = await Self.makeModel()
        var setup = CameraSetup.factory
        setup.lens = CameraSetup.LensChoice(ManualFixtures.basicLens)
        // The ultra wide has no ISO priority: setting ISO alone fixes the shutter too.
        setup.iso = 400
        // A start delay this version doesn't offer becomes the default, 10 seconds.
        setup.astroStartDelay = 7
        let notices = await model.applyCameraSetup(setup, manualControlsOn: true)
        #expect(notices == [.cameraValuesAdjusted])
        #expect(model.manual.settings.shutter != nil)
        #expect(model.astro.startDelay == .tenSeconds)
    }

    @Test func aMissingLensIsReportedAndTheRestApplies() async {
        let model = await Self.makeModel(lenses: [ManualFixtures.wide])
        var setup = CameraSetup.factory
        setup.lens = CameraSetup.LensChoice(Self.telephoto)
        setup.drive = CameraSetup.driveName(.burst)
        let notices = await model.applyCameraSetup(setup, manualControlsOn: false)
        #expect(notices == [.lensUnavailable])
        #expect(model.selectedLensID == "wide")
        #expect(model.drive.mode == .burst)
    }

    @Test func aCameraThatIsntOnIsReported() async {
        let model = CameraModel(backend: ScriptedManualBackend(lenses: [ManualFixtures.wide]))
        #expect(await model.applyCameraSetup(.factory, manualControlsOn: false) == [.cameraNotReady])
    }

    @Test func lensesMatchByIdentifierThenKindAndMagnification() {
        let tele3 = Self.telephoto
        let tele5 = Lens(id: "tele5", kind: .telephoto, bayerRAWFormat: nil, magnification: 5)
        let frontA = Lens(id: "frontA", kind: .front, bayerRAWFormat: nil)
        let frontB = Lens(id: "frontB", kind: .front, bayerRAWFormat: nil)
        let device = DeviceCapabilities(lenses: [ManualFixtures.wide, tele3, tele5, frontA, frontB])
        let other = Lens(id: "other-tele", kind: .telephoto, bayerRAWFormat: nil, magnification: 4.5)
        #expect(CameraSetup.LensChoice(tele3).match(in: device)?.id == "tele")
        #expect(CameraSetup.LensChoice(other).match(in: device)?.id == "tele5")
        #expect(CameraSetup.LensChoice(Lens(id: "front-elsewhere", kind: .front, bayerRAWFormat: nil)).match(in: device)?.id == "frontA")
        #expect(CameraSetup.LensChoice(ManualFixtures.basicLens).match(in: device) == nil)
    }

    @Test func namesOfKindsAndDriveModes() {
        #expect(Lens.Kind.allCases.map(CameraSetup.kindName) == ["ultraWide", "wide", "telephoto", "front"])
        #expect(DriveMode.allCases.map(CameraSetup.driveName) == ["single", "timer3", "timer10", "burst", "interval"])
        for mode in DriveMode.allCases {
            #expect(CameraSetup.driveMode(named: CameraSetup.driveName(mode)) == mode)
        }
    }

    @Test func theEncodingRoundTripsAndFillsInMissingValues() throws {
        var setup = CameraSetup.factory
        for change in Self.setupChanges.values { change(&setup) }
        let decoded = try JSONDecoder().decode(CameraSetup.self, from: try JSONEncoder().encode(setup))
        #expect(decoded == setup)
        #expect(try JSONDecoder().decode(CameraSetup.self, from: Data("{}".utf8)) == .factory)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(CameraSetup.self, from: Data("[]".utf8)) }
    }
}

extension Equatable {
    /// Whether another value of any type is equal to this one.
    func isEqual(to other: Any?) -> Bool {
        (other as? Self) == self
    }
}

extension Lens {
    /// The same lens with every manual control (`ManualFixtures.full`) and Close-Up (the near
    /// focus limit).
    var withNearFocusLimit: Lens {
        let full = ManualFixtures.full
        let controls = ManualCapabilities(
            supportsManualExposure: full.supportsManualExposure, supportsShutterPriority: full.supportsShutterPriority,
            supportsISOPriority: full.supportsISOPriority, supportsAperturePriority: full.supportsAperturePriority,
            exposureCompensationRange: full.exposureCompensationRange, supportsExposureLock: full.supportsExposureLock,
            supportsAutoFocus: full.supportsAutoFocus, supportsFocusLock: full.supportsFocusLock,
            supportsManualFocus: full.supportsManualFocus, supportsManualWhiteBalance: full.supportsManualWhiteBalance,
            meteringModes: full.meteringModes, supportsNearFocusLimit: true)
        return Lens(
            id: id, kind: kind, bayerRAWFormat: bayerRAWFormat, magnification: magnification, isoRange: isoRange,
            exposureDurationRange: exposureDurationRange, aperture: aperture,
            maxBracketedPhotoCount: maxBracketedPhotoCount, manualControls: controls)
    }
}
