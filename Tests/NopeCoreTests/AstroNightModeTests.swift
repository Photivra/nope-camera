import Foundation
import Testing

@testable import NopeCore

/// Night mode and the astro helper (issue #60): Astro turns night mode on, and leaving Astro
/// returns it to what it was before, unless the person changed it while Astro was on or chose
/// Keep Night Mode After Astro. The rule mirrors the one for manual controls.
@MainActor
struct AstroNightModeTests {
    static let wide = ManualFixtures.wide
    static let basic = ManualFixtures.basicLens
    static let bare = ManualFixtures.bare

    /// A started camera with a storage and battery reader, so the helper can turn on.
    func makeModel(lenses: [Lens] = [AstroNightModeTests.wide]) async -> CameraModel {
        let backend = ScriptedManualBackend(lenses: lenses)
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), sleep: { _ in }, deviceStatusReader: FakeStatusReader(bytes: nil))
        await model.send(.start)
        return model
    }

    // MARK: - Leaving Astro

    @Test func nightModeOffBeforeAstroIsOffAgainAfterIt() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let model = await makeModel()
        await model.setAstro(true, settings: settings)
        #expect(model.astro.isOn)
        #expect(settings.isNightModeOn)
        #expect(settings.isNightModeFromAstro)
        await model.setAstro(false, settings: settings)
        #expect(!model.astro.isOn)
        #expect(!settings.isNightModeOn)
        #expect(!settings.isNightModeFromAstro)
        // Stored, so the next launch reads it off too.
        #expect(!NopeSettings(defaults: scratch.defaults).isNightModeOn)
    }

    @Test func nightModeOnBeforeAstroStaysOn() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        settings.setNightMode(true)
        let model = await makeModel()
        await model.setAstro(true, settings: settings)
        #expect(!settings.isNightModeFromAstro)
        await model.setAstro(false, settings: settings)
        #expect(settings.isNightModeOn)
    }

    @Test func aChangeDuringAstroIsThePersonsAndIsKept() async {
        // Turned off while Astro is on: leaving Astro leaves it off.
        let offScratch = ScratchDefaults()
        let off = NopeSettings(defaults: offScratch.defaults)
        let model = await makeModel()
        await model.setAstro(true, settings: off)
        off.setNightMode(false)
        await model.setAstro(false, settings: off)
        #expect(!off.isNightModeOn)

        // Turned off and on again while Astro is on: the person's on, kept.
        let onScratch = ScratchDefaults()
        let on = NopeSettings(defaults: onScratch.defaults)
        await model.setAstro(true, settings: on)
        on.setNightMode(false)
        on.setNightMode(true)
        #expect(!on.isNightModeFromAstro)
        await model.setAstro(false, settings: on)
        #expect(on.isNightModeOn)
    }

    @Test func aChangeFromAnotherProcessDuringAstroIsKept() async {
        // The Control Center or Lock Screen control writes the shared store from its own process,
        // and the app reads it again (`SharedSettingsSync`).
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let model = await makeModel()
        await model.setAstro(true, settings: settings)
        let control = NopeSettings(defaults: UserDefaults(suiteName: scratch.name)!)
        #expect(control.isNightModeFromAstro)
        control.setNightMode(false)
        control.setNightMode(true)
        #expect(settings.reload())
        #expect(!settings.isNightModeFromAstro)
        await model.setAstro(false, settings: settings)
        #expect(settings.isNightModeOn)
    }

    @Test func keepNightModeAfterAstroLeavesItOn() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(!settings.keepsNightModeAfterAstro)
        settings.setKeepsNightModeAfterAstro(true)
        #expect(NopeSettings(defaults: scratch.defaults).keepsNightModeAfterAstro)
        let model = await makeModel()
        await model.setAstro(true, settings: settings)
        await model.setAstro(false, settings: settings)
        #expect(settings.isNightModeOn)
        #expect(!settings.isNightModeFromAstro)

        // Chosen while Astro is on, the setting applies when Astro ends; and off again, the
        // restore applies.
        settings.setNightMode(false)
        settings.setKeepsNightModeAfterAstro(false)
        await model.setAstro(true, settings: settings)
        settings.setKeepsNightModeAfterAstro(true)
        await model.setAstro(false, settings: settings)
        #expect(settings.isNightModeOn)
        settings.setNightMode(false)
        await model.setAstro(true, settings: settings)
        settings.setKeepsNightModeAfterAstro(false)
        await model.setAstro(false, settings: settings)
        #expect(!settings.isNightModeOn)
    }

    // MARK: - Every way Astro ends

    @Test func anotherDriveModeEndsAstroAndRestoresNightMode() async {
        // The drive strip sends Astro off before the new mode.
        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        let model = await makeModel()
        await model.setAstro(true, settings: settings)
        await model.send(.astro(.setOn(false)))
        await model.send(.drive(.setMode(.burst)))
        #expect(!settings.isNightModeOn)
    }

    @Test func aLensWithoutAstroRestoresNightModeAndOneWithAstroKeepsIt() async {
        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        let model = await makeModel(lenses: [Self.wide, Self.basic, Self.bare])
        await model.setAstro(true, settings: settings)
        await model.send(.selectLens(Self.basic.id))
        #expect(model.astro.isOn)
        #expect(settings.isNightModeOn)
        await model.send(.selectLens(Self.bare.id))
        #expect(!model.astro.isOn)
        #expect(!settings.isNightModeOn)
    }

    @Test func manualControlsOffEndsAstroAndRestoresNightMode() async {
        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        let model = await makeModel()
        await model.setAstro(true, settings: settings)
        await model.setManualControls(false, settings: settings)
        #expect(!model.astro.isOn)
        #expect(!settings.isNightModeOn)
    }

    @Test func aRunStopDoesNotEndAstroOrNightMode() async {
        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        let model = await makeModel()
        await model.setAstro(true, settings: settings)
        await model.send(.astro(.setFrameCount(5)))
        await model.send(.capture)
        await waitUntil { model.astro.isRunning || model.astro.lastRun != nil }
        await model.send(.astro(.stop))
        for _ in 0..<500 where model.astro.lastRun == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.astro.lastRun != nil)
        #expect(model.astro.isOn)
        #expect(settings.isNightModeOn)
        #expect(settings.isNightModeFromAstro)
        await model.setAstro(false, settings: settings)
        #expect(!settings.isNightModeOn)
    }

    @Test func aPresetsNightModeIsKeptWhenItEndsAstro() async throws {
        // A preset applies its own night mode, the person's choice, then turns Astro off: night
        // mode stays as the preset has it.
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        settings.setNightMode(true)
        try presets.saveCurrent(named: "Night", camera: nil)
        settings.setNightMode(false)
        let model = await makeModel()
        await model.setAstro(true, settings: settings)
        let id = try #require(presets.saved.first?.id)
        await presets.apply(.saved(id), camera: model, location: nil)
        #expect(!model.astro.isOn)
        #expect(settings.isNightModeOn)
        #expect(!settings.isNightModeFromAstro)
    }

    @Test func aPresetThatTurnsAstroOnLeavesNightModeAlone() async throws {
        // The helper alone, as a preset turns it on, never changes night mode.
        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        let model = await makeModel()
        await model.send(.astro(.setOn(true)))
        #expect(model.astro.isOn)
        #expect(!settings.isNightModeOn)
        await model.send(.astro(.setOn(false)))
        #expect(!settings.isNightModeOn)
    }

    // MARK: - Relaunch

    @Test func aRelaunchWhileAstroWasOnKeepsNightModeAndClearsTheRecord() async {
        // Owner decision, 2026-11-18: a relaunch in the dark opens red.
        let scratch = ScratchDefaults()
        let before = NopeSettings(defaults: scratch.defaults)
        let first = await makeModel()
        await first.setAstro(true, settings: before)
        #expect(before.isNightModeOn)

        // The next launch: the helper is off, night mode and the record are read from the store.
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.isNightModeOn)
        #expect(settings.isNightModeFromAstro)
        let model = await makeModel()
        model.forgetNightModeFromAstroAtLaunch(settings: settings)
        #expect(settings.isNightModeOn)
        #expect(!settings.isNightModeFromAstro)
        #expect(!NopeSettings(defaults: scratch.defaults).isNightModeFromAstro)

        // Night mode is the person's now: Astro in this session finds it on and leaves it on.
        await model.setAstro(true, settings: settings)
        await model.setAstro(false, settings: settings)
        #expect(settings.isNightModeOn)
    }

    @Test func aRelaunchLeavesThePersonsNightModeAsItIs() async {
        for isOn in [true, false] {
            let settings = NopeSettings(defaults: ScratchDefaults().defaults)
            settings.setNightMode(isOn)
            let model = await makeModel()
            model.forgetNightModeFromAstroAtLaunch(settings: settings)
            #expect(settings.isNightModeOn == isOn)
            #expect(!settings.isNightModeFromAstro)
        }
    }

    @Test func forgettingWhileAstroIsOnDoesNothing() async {
        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        let model = await makeModel()
        await model.setAstro(true, settings: settings)
        model.forgetNightModeFromAstroAtLaunch(settings: settings)
        #expect(settings.isNightModeOn)
        #expect(settings.isNightModeFromAstro)
        // Leaving Astro still restores it.
        await model.setAstro(false, settings: settings)
        #expect(!settings.isNightModeOn)
    }

    // MARK: - When Astro can't turn on

    @Test func nightModeIsLeftAloneWhenAstroCannotTurnOn() async {
        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        let bare = await makeModel(lenses: [Self.bare])
        await bare.setAstro(true, settings: settings)
        #expect(!bare.astro.isOn)
        #expect(!settings.isNightModeOn)

        // Already on: a second turn-on changes nothing, and the first one's record stays.
        let model = await makeModel()
        await model.setAstro(true, settings: settings)
        settings.setNightMode(false)
        settings.setNightMode(true)
        await model.setAstro(true, settings: settings)
        #expect(!settings.isNightModeFromAstro)
        // Off while off: nothing.
        await bare.setAstro(false, settings: settings)
        #expect(settings.isNightModeOn)
    }

    // MARK: - Availability, presets and snapshots

    @Test func theDeviceOffersAstroOnlyWithASuitableLensAndReadings() async {
        #expect(await makeModel().deviceOffersAstro)
        #expect(!(await makeModel(lenses: [Self.bare]).deviceOffersAstro))
        let notStarted = CameraModel(backend: ScriptedManualBackend(lenses: [Self.wide]), deviceStatusReader: FakeStatusReader(bytes: nil))
        #expect(!notStarted.deviceOffersAstro)
        let noReader = CameraModel(backend: ScriptedManualBackend(lenses: [Self.wide]))
        await noReader.send(.start)
        #expect(!noReader.deviceOffersAstro)
    }

    @Test func presetsCarryTheSettingButNotTheRecord() throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        settings.setKeepsNightModeAfterAstro(true)
        settings.turnOnNightModeForAstro()
        let snapshot = try settings.makeSnapshot()
        let values = try #require(PropertyListSerialization.propertyList(from: snapshot.values, format: nil) as? [String: Any])
        #expect(values[NopeSettings.Key.keepsNightModeAfterAstro] as? Bool == true)
        #expect(values[NopeSettings.Key.isNightModeFromAstro] == nil)
        #expect(!SharedSettingsStore.isSettingsKey(NopeSettings.Key.isNightModeFromAstro))

        // With the key: on. A preset or snapshot from before the setting existed: the default, off.
        let other = NopeSettings(defaults: ScratchDefaults().defaults)
        #expect(other.apply(snapshot))
        #expect(other.keepsNightModeAfterAstro)
        var older = values
        older.removeValue(forKey: NopeSettings.Key.keepsNightModeAfterAstro)
        let olderSnapshot = NopeSettingsSnapshot(
            values: try PropertyListSerialization.data(fromPropertyList: older, format: .binary, options: 0))
        let preset = SettingsPreset(name: "Old", settings: olderSnapshot, camera: .factory)
        let decoded = try JSONDecoder().decode(SettingsPreset.self, from: JSONEncoder().encode(preset))
        #expect(other.apply(decoded.settings))
        #expect(!other.keepsNightModeAfterAstro)

        // Applying a snapshot makes night mode the person's.
        #expect(settings.isNightModeFromAstro)
        #expect(settings.apply(snapshot))
        #expect(!settings.isNightModeFromAstro)
        #expect(settings.isNightModeOn)
    }

    @Test func factoryDefaultsTurnTheSettingOff() async {
        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        settings.setKeepsNightModeAfterAstro(true)
        let presets = SettingsPresets(settings: settings)
        await presets.apply(.factoryDefaults, camera: nil, location: nil)
        #expect(!settings.keepsNightModeAfterAstro)
    }
}
