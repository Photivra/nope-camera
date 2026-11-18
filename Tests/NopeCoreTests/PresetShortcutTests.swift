import Foundation
import Testing

@testable import NopeCore

/// "Apply Preset" from Siri and Shortcuts (issues #62 and #72): the request goes through
/// `ShortcutInbox` and `SettingsPresets.apply(_:camera:location:)`, the same path as the Presets
/// list.
@MainActor
struct PresetShortcutTests {
    /// Submits a request and serves it with presets, returning the outcome.
    func run(_ request: ShortcutRequest, on model: CameraModel, presets: SettingsPresets?) async -> ShortcutOutcome {
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let server = Task { await model.serveShortcuts(from: inbox, presets: presets) }
        defer { server.cancel() }
        await waitUntil { inbox.isServed }
        return await inbox.submit(request)
    }

    /// A started model with the wide lens (which has a torch) and the telephoto.
    func makeModel(permission: CameraPermission = .authorized) async -> CameraModel {
        let wide = Lens(
            id: "wide", kind: .wide, bayerRAWFormat: "bgg4", magnification: 1, flashModes: FlashMode.allCases,
            hasTorch: true)
        // The simulated backend has a torch that comes on when asked.
        let backend = SimulatedCaptureBackend(
            permission: permission, capabilities: DeviceCapabilities(lenses: [wide, CameraSetupTests.telephoto]))
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), sleep: { _ in })
        await model.send(.start)
        return model
    }

    @Test func identifiersRoundTrip() {
        let id = UUID()
        #expect(PresetChoice(identifier: PresetChoice.factoryDefaults.identifier) == .factoryDefaults)
        #expect(PresetChoice(identifier: PresetChoice.saved(id).identifier) == .saved(id))
        #expect(PresetChoice(identifier: "not a preset") == nil)
        #expect(ShortcutRequest.applyPreset(.factoryDefaults).outcomeWithoutCameraScreen == nil)
    }

    @Test func aSavedPresetAppliesTheSettingsAndTheCamera() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let model = await makeModel()
        settings.setNightMode(true)
        await model.send(.selectLens("tele"))
        let saved = try presets.saveCurrent(named: "Night tele", camera: model)
        settings.setNightMode(false)
        await model.send(.selectLens("wide"))

        let outcome = await run(.applyPreset(.saved(saved.id)), on: model, presets: presets)

        let result = PresetApplyResult(choice: .saved(saved.id), name: "Night tele", isApplied: true, notices: [])
        #expect(outcome == .presetApplied(result))
        #expect(settings.isNightModeOn)
        #expect(model.selectedLensID == "tele")
        // As from the Presets list, the apply can be undone there.
        #expect(presets.canUndo)
        #expect(presets.lastResult == result)
    }

    @Test func aPresetNeverTurnsTheLightOn() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let model = await makeModel()
        await model.send(.light(.setTorch(true)))
        #expect(model.light.isTorchOn)
        let saved = try presets.saveCurrent(named: "Light on", camera: model)
        await model.send(.light(.setTorch(false)))

        #expect(await run(.applyPreset(.saved(saved.id)), on: model, presets: presets) != .presetUnavailable)
        #expect(!model.light.isTorchOn)
        #expect(await run(.applyPreset(.factoryDefaults), on: model, presets: presets) != .presetUnavailable)
        #expect(!model.light.isTorchOn)
    }

    @Test func aMissingPresetOrNoPresetsChangesNothing() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let model = await makeModel()
        settings.setNightMode(true)

        #expect(await run(.applyPreset(.saved(UUID())), on: model, presets: presets) == .presetUnavailable)
        #expect(await run(.applyPreset(.factoryDefaults), on: model, presets: nil) == .presetUnavailable)
        #expect(settings.isNightModeOn)
    }

    @Test func aBusyCameraSaysSo() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let model = await makeModel()
        model.drive.beginBurst()
        settings.setNightMode(true)

        #expect(await run(.applyPreset(.factoryDefaults), on: model, presets: presets) == .busy)
        #expect(settings.isNightModeOn)
    }

    @Test func withoutTheCameraTheSettingsStillApply() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let presets = SettingsPresets(settings: settings)
        let model = await makeModel(permission: .denied)
        settings.setNightMode(true)

        let outcome = await run(.applyPreset(.factoryDefaults), on: model, presets: presets)

        #expect(outcome == .presetApplied(
            PresetApplyResult(choice: .factoryDefaults, name: nil, isApplied: true, notices: [.cameraNotReady])))
        #expect(!settings.isNightModeOn)
    }
}
