import Foundation
import Testing

@testable import NopeCore

/// Pinch to switch lenses (issue #95; docs/design/pinch-lens.md, section 11): the steps, the
/// ends, the return margin, the order, where a pinch is used, the settling of targets, the
/// setting and Magnify.
@MainActor
struct LensPinchTests {
    static let ultraWide = Lens(id: "ultra", kind: .ultraWide, bayerRAWFormat: "rgg4", magnification: 0.5)
    static let wide = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4", magnification: 1)
    static let tele = Lens(id: "tele", kind: .telephoto, bayerRAWFormat: nil, magnification: 5)
    static let front = Lens(id: "front", kind: .front, bayerRAWFormat: "bgg4")
    static let threeRear = [ultraWide, wide, tele, front]

    /// A pinch started on a lens of the three rear lenses.
    func started(from id: Lens.ID, lenses: [Lens] = threeRear) throws -> LensPinch {
        try #require(LensPinch(lenses: lenses, startingAt: id))
    }

    // MARK: - 1. Steps

    @Test func belowTheFirstThresholdNothingChanges() throws {
        var pinch = try started(from: "wide")
        for scale in [1.0, 1.1, 1.24, 0.9, 0.81] {
            #expect(pinch.update(scale: scale).id == "wide", "\(scale)")
            #expect(pinch.step == 0)
        }
    }

    @Test func theFirstStepsSpreadingAndPinching() throws {
        var spread = try started(from: "wide")
        #expect(spread.update(scale: 1.25).id == "tele")
        #expect(spread.step == 1)
        var pinched = try started(from: "wide")
        #expect(pinched.update(scale: 0.80).id == "ultra")
        #expect(pinched.step == -1)
    }

    @Test func aLongerPinchPassesFurtherLenses() throws {
        var spread = try started(from: "ultra")
        #expect(spread.update(scale: 1.69).id == "tele")
        #expect(spread.step == 2)
        var pinched = try started(from: "tele")
        // 0.80 / 1.35 = 0.593: the second wider lens.
        #expect(pinched.update(scale: 0.80).id == "wide")
        #expect(pinched.update(scale: 0.59).id == "ultra")
        #expect(pinched.step == -2)
        #expect(LensPinch.threshold(2) == LensPinch.firstSpreadStep * LensPinch.furtherStep)
        #expect(abs(LensPinch.threshold(3) - 2.278) < 0.001)
        #expect(abs(LensPinch.threshold(-1) - 0.80 / 1.35) < 1e-12)
    }

    @Test func oneStepAtATimeOnTheWay() throws {
        var pinch = try started(from: "ultra")
        #expect(pinch.update(scale: 1.3).id == "wide")
        #expect(pinch.update(scale: 1.6).id == "wide")
        #expect(pinch.update(scale: 1.7).id == "tele")
    }

    // MARK: - 2. Ends

    @Test func theLastAndFirstLensStayAndNothingWraps() throws {
        var longest = try started(from: "tele")
        #expect(longest.update(scale: 1.5).id == "tele")
        #expect(longest.update(scale: 4).id == "tele")
        #expect(longest.step == 0)
        var widest = try started(from: "ultra")
        #expect(widest.update(scale: 0.5).id == "ultra")
        #expect(widest.update(scale: 0.1).id == "ultra")
        #expect(widest.step == 0)
        // Pushing past the end doesn't store steps: the first return goes back at once.
        var far = try started(from: "wide")
        #expect(far.update(scale: 5).id == "tele")
        #expect(far.update(scale: 1.12).id == "wide")
    }

    // MARK: - 3. Return margin

    @Test func hoveringAtAThresholdDoesNotAlternate() throws {
        var pinch = try started(from: "wide")
        for scale in [1.25, 1.2, 1.26, 1.13, 1.25, 1.14] {
            #expect(pinch.update(scale: scale).id == "tele", "\(scale)")
        }
        // 10% inside 1.25 is 1.125.
        #expect(pinch.update(scale: 1.12).id == "wide")
        var pinched = try started(from: "wide")
        for scale in [0.80, 0.85, 0.79, 0.88] {
            #expect(pinched.update(scale: scale).id == "ultra", "\(scale)")
        }
        // 10% inside 0.80, pinching, is 0.80 / 0.9 = 0.889.
        #expect(pinched.update(scale: 0.9).id == "wide")
    }

    @Test func goingBackPastTheStartReachesTheOtherSide() throws {
        var pinch = try started(from: "wide")
        #expect(pinch.update(scale: 1.3).id == "tele")
        #expect(pinch.update(scale: 0.7).id == "ultra")
        #expect(pinch.update(scale: 1.3).id == "tele")
    }

    // MARK: - 4. Order

    @Test func theFrontCameraIsNeverATargetAndNoRAWLensesAre() throws {
        #expect(LensPinch.rearLenses(Self.threeRear).map(\.id) == ["ultra", "wide", "tele"])
        var pinch = try started(from: "wide")
        #expect(pinch.update(scale: 1.3).supportsBayerRAW == false, "a lens without RAW is a target")
        #expect(pinch.update(scale: 10).id == "tele")
        #expect(!pinch.lenses.contains { $0.kind == .front })
    }

    @Test func oneRearLensGivesNoPinch() {
        #expect(LensPinch(lenses: [Self.wide, Self.front], startingAt: "wide") == nil)
        #expect(LensPinch(lenses: [Self.wide], startingAt: "wide") == nil)
        #expect(!LensPinch.isOffered(on: [Self.wide, Self.front]))
        #expect(LensPinch.isOffered(on: [Self.ultraWide, Self.wide]))
        #expect(LensPinch.isOffered(on: Self.threeRear))
        #expect(!LensPinch.isOffered(on: []))
    }

    @Test func aLensWithoutAMagnificationKeepsItsPlace() throws {
        let unnamed = Lens(id: "unnamed", kind: .telephoto, bayerRAWFormat: "bgg4")
        var pinch = try started(from: "wide", lenses: [Self.ultraWide, Self.wide, unnamed, Self.front])
        #expect(pinch.update(scale: 1.3).id == "unnamed")
    }

    // MARK: - 5. Starting

    @Test func startingOnTheFrontCameraOrNoLensGivesNoPinch() {
        #expect(LensPinch(lenses: Self.threeRear, startingAt: "front") == nil)
        #expect(LensPinch(lenses: Self.threeRear, startingAt: nil) == nil)
        #expect(LensPinch(lenses: Self.threeRear, startingAt: "gone") == nil)
    }

    @Test func thePinchStartsOnTheLensInUse() throws {
        let pinch = try started(from: "tele")
        #expect(pinch.startIndex == 2)
        #expect(pinch.target.id == "tele")
    }

    // MARK: - 6. Availability

    static let capabilities = DeviceCapabilities(lenses: threeRear)

    func runningModel(
        _ capabilities: DeviceCapabilities = capabilities, backend: ScriptedBackend? = nil
    ) async -> CameraModel {
        await CameraModelTests.runningModel(backend ?? ScriptedBackend(capabilities: capabilities))
    }

    @Test func aRunningRearLensIsAvailable() async {
        let model = await runningModel()
        #expect(model.selectedLensID == "wide")
        #expect(model.pinchSwitchesLenses(setting: .switchLenses))
        #expect(!model.pinchSwitchesLenses(setting: .off))
    }

    @Test func notOnTheFrontCameraOrWithOneRearLens() async {
        let model = await runningModel()
        await model.send(.selectLens("front"))
        #expect(!model.pinchSwitchesLenses(setting: .switchLenses))
        let one = await runningModel(DeviceCapabilities(lenses: [Self.wide, Self.front]))
        #expect(!one.pinchSwitchesLenses(setting: .switchLenses))
    }

    @Test func notBeforeTheCameraIsReady() async {
        let model = CameraModel(backend: ScriptedBackend(capabilities: Self.capabilities))
        #expect(model.sessionStatus == .stopped)
        #expect(!model.pinchSwitchesLenses(setting: .switchLenses))
    }

    @Test(arguments: LensWhileBusyTests.Busy.allCases)
    func notWhileTheLensCantBeChanged(_ state: LensWhileBusyTests.Busy) async {
        let camera = await LensWhileBusyTests().whileBusy(state) { model in
            #expect(!model.canChangeLens)
            #expect(!model.pinchSwitchesLenses(setting: .switchLenses), "\(state)")
        }
        // After an astro run Astro is still on, where a pinch does nothing (decision 6).
        #expect(camera.model.pinchSwitchesLenses(setting: .switchLenses) == (state != .astroRun), "after \(state)")
    }

    @Test func notWithAstroOnIdle() async {
        let camera = await LensWhileBusyTests().makeCamera()
        await camera.model.send(.astro(.setOn(true)))
        #expect(camera.model.astro.isOn)
        #expect(!camera.model.astro.isRunning)
        #expect(!camera.model.pinchSwitchesLenses(setting: .switchLenses))
        await camera.model.send(.astro(.setOn(false)))
        #expect(camera.model.pinchSwitchesLenses(setting: .switchLenses))
    }

    @Test func notDuringTheFirstStart() async {
        let backend = ScriptedBackend(capabilities: Self.capabilities)
        let model = CameraModel(backend: backend)
        let during = PinchRecorder()
        await backend.setOnStart { @MainActor in during.record(model) }
        await model.send(.start)
        #expect(during.status == .starting)
        #expect(during.isAvailable == false)
        #expect(model.pinchSwitchesLenses(setting: .switchLenses))
    }

    @Test func duringARestartForALensChange() async {
        let backend = ScriptedBackend(capabilities: Self.capabilities)
        let model = await runningModel(backend: backend)
        let during = PinchRecorder()
        await backend.setOnStart { @MainActor in during.record(model) }
        await model.send(.selectLens("tele"))
        #expect(during.status == .starting)
        #expect(during.isAvailable == true, "a pinch goes on while the camera switches")
    }

    @Test func notWhileInterruptedTooHotFailedOrWithoutAPicture() async {
        let interrupted = ScriptedBackend(capabilities: Self.capabilities)
        let interruptedModel = await runningModel(backend: interrupted)
        interrupted.emit(.interrupted(.inUseElsewhere))
        interrupted.finish()
        await interruptedModel.observeEvents()
        #expect(interruptedModel.sessionStatus == .interrupted(.inUseElsewhere))
        #expect(!interruptedModel.pinchSwitchesLenses(setting: .switchLenses))

        let hot = ScriptedBackend(capabilities: Self.capabilities)
        let hotModel = await runningModel(backend: hot)
        hot.emit(.heat(.critical))
        hot.finish()
        await hotModel.observeEvents()
        #expect(hotModel.sessionStatus == .pausedForHeat)
        #expect(!hotModel.pinchSwitchesLenses(setting: .switchLenses))

        let failed = await runningModel(
            backend: ScriptedBackend(capabilities: Self.capabilities, startErrors: [.configurationFailed]))
        #expect(failed.sessionStatus == .failed(.configurationFailed))
        #expect(!failed.pinchSwitchesLenses(setting: .switchLenses))

        let blank = await runningModel(backend: ScriptedBackend(capabilities: Self.capabilities, captureError: .blankPicture))
        await blank.send(.capture)
        #expect(blank.sessionStatus == .noPicture)
        #expect(!blank.pinchSwitchesLenses(setting: .switchLenses))
    }

    @Test func inNightModeManualControlsCleanViewMagnifyAndIdleDriveModes() async {
        let camera = await LensWhileBusyTests().makeCamera()
        let model = camera.model
        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        settings.setNightMode(true)
        await model.send(.manual(.setEnabled(true)))
        #expect(model.manual.isEnabled)
        #expect(model.pinchSwitchesLenses(setting: settings.pinch), "Night Mode and Manual Controls")
        await model.send(.setCleanView(true))
        #expect(model.pinchSwitchesLenses(setting: .switchLenses), "clean view")
        await model.send(.auto(.setMagnifier(true)))
        #expect(model.pinchSwitchesLenses(setting: .switchLenses), "Magnify")
        for mode in [DriveMode.burst, .timer(.threeSeconds)] {
            await model.send(.drive(.setMode(mode)))
            #expect(model.pinchSwitchesLenses(setting: .switchLenses), "\(mode) chosen and idle")
        }
        await model.send(.drive(.setMode(.single)))
        await model.send(.manual(.setInterval(IntervalSettings(interval: 5, count: 3))))
        await model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1))))
        #expect(model.pinchSwitchesLenses(setting: .switchLenses), "interval and bracket chosen and idle")
    }

    // MARK: - 7. Settling

    @Test func severalTargetsInOnePinchSendOneSwitch() async {
        let camera = await runningModel()
        let sent = SentLenses()
        let switcher = LensPinchSwitcher(lensInUse: { camera.selectedLensID }) { id in
            sent.ids.append(id)
            await camera.send(.selectLens(id))
        }
        // The interface settles only on the last target of a pinch that moved on quickly.
        guard var pinch = LensPinch(lenses: Self.threeRear, startingAt: "ultra") else {
            Issue.record("no pinch")
            return
        }
        pinch.update(scale: 1.3)
        pinch.update(scale: 1.7)
        await switcher.settle(on: pinch.target.id)
        #expect(sent.ids == ["tele"])
        #expect(camera.selectedLensID == "tele")
    }

    @Test func returningToTheStartingLensSendsNothing() async {
        let sent = SentLenses()
        let switcher = LensPinchSwitcher(lensInUse: { "wide" }) { sent.ids.append($0) }
        await switcher.settle(on: "wide")
        #expect(sent.ids.isEmpty)
        #expect(!switcher.isSwitching)
    }

    @Test func aTargetReachedWhileASwitchRunsIsSentAfterIt() async {
        let gate = SwitchGate()
        var inUse: Lens.ID = "wide"
        let switcher = LensPinchSwitcher(lensInUse: { inUse }) { id in
            gate.started.append(id)
            await gate.wait()
            inUse = id
        }
        let first = Task { await switcher.settle(on: "tele") }
        await waitUntil { gate.isWaiting }
        #expect(switcher.isSwitching)
        // Two more targets while the first switch runs: only the latest is sent, after it.
        await switcher.settle(on: "ultra")
        await switcher.settle(on: "wide")
        #expect(gate.started == ["tele"])
        gate.open()
        await first.value
        #expect(gate.started == ["tele", "wide"])
        #expect(inUse == "wide")
        #expect(!switcher.isSwitching)
    }

    @Test func theSwitcherSendsThroughTheCamerasRule() async {
        let camera = await runningModel()
        let switcher = LensPinchSwitcher(model: camera)
        await switcher.settle(on: "tele")
        #expect(camera.selectedLensID == "tele")
        // While the lens can't be changed the camera itself refuses the switch (issue #96).
        let busy = await LensWhileBusyTests().whileBusy(.capturing) { model in
            await LensPinchSwitcher(model: model).settle(on: "basic")
            #expect(model.selectedLensID == "wide")
        }
        #expect(busy.model.selectedLensID == "wide")
    }

    @Test func theTimingsAreTheDesignsStartingValues() {
        #expect(LensPinch.firstSpreadStep == 1.25)
        #expect(LensPinch.firstPinchStep == 0.80)
        #expect(LensPinch.furtherStep == 1.35)
        #expect(LensPinch.returnMargin == 0.10)
        #expect(LensPinchSwitcher.settleSeconds == 0.25)
        #expect(LensPinchSwitcher.labelSeconds == 0.8)
    }

    // MARK: - 8. Settings

    @Test func theDefaultIsSwitchLenses() {
        #expect(NopeSettings(defaults: ScratchDefaults().defaults).pinch == .switchLenses)
    }

    @Test func theValueIsStoredAndReadBack() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        settings.setPinch(.off)
        #expect(settings.pinch == .off)
        #expect(NopeSettings(defaults: scratch.defaults).pinch == .off)
        #expect(scratch.defaults.string(forKey: "NopeSettings.pinch") == "off")
        // Another process (a preset applied elsewhere) changes it; reload reads it.
        scratch.defaults.set("switchLenses", forKey: "NopeSettings.pinch")
        #expect(settings.reload())
        #expect(settings.pinch == .switchLenses)
    }

    @Test func anEarlierOrUnknownValueReadsAsTheDefault() {
        let scratch = ScratchDefaults()
        scratch.defaults.set("magnify", forKey: "NopeSettings.pinch")
        #expect(NopeSettings(defaults: scratch.defaults).pinch == .switchLenses)
    }

    @Test func aPresetStoresAndAppliesItAndFactoryDefaultsRestoresIt() async throws {
        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        settings.setPinch(.off)
        let presets = SettingsPresets(settings: settings)
        let preset = try presets.saveCurrent(named: "No Pinch", camera: nil)
        await presets.apply(.factoryDefaults, camera: nil, location: nil)
        #expect(settings.pinch == .switchLenses)
        await presets.apply(.saved(preset.id), camera: nil, location: nil)
        #expect(settings.pinch == .off)
    }

    @Test func aPresetFromBeforeThePinchSettingGivesTheDefault() throws {
        let settings = NopeSettings(defaults: ScratchDefaults().defaults)
        settings.setPinch(.off)
        let snapshot = try settings.makeSnapshot()
        var values = try #require(
            PropertyListSerialization.propertyList(from: snapshot.values, format: nil) as? [String: Any])
        #expect(values["NopeSettings.pinch"] as? String == "off")
        values.removeValue(forKey: "NopeSettings.pinch")
        let older = NopeSettingsSnapshot(
            values: try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0))
        #expect(settings.apply(older))
        #expect(settings.pinch == .switchLenses)
    }

    // MARK: - 10. Magnify

    @Test func aLensChangeByPinchLeavesMagnifyAsItWas() async {
        for isOn in [true, false] {
            let camera = await runningModel()
            await camera.send(.auto(.setMagnifier(isOn)))
            await LensPinchSwitcher(model: camera).settle(on: "tele")
            #expect(camera.selectedLensID == "tele")
            #expect(camera.isMagnifying == isOn)
        }
    }
}

/// What a camera reported during a start.
@MainActor
final class PinchRecorder {
    var status: SessionStatus?
    var isAvailable: Bool?

    func record(_ model: CameraModel) {
        status = model.sessionStatus
        isAvailable = model.pinchSwitchesLenses(setting: .switchLenses)
    }
}

/// The lenses a switcher sent.
@MainActor
final class SentLenses {
    var ids: [Lens.ID] = []
}

/// A lens switch held until the test opens it.
@MainActor
final class SwitchGate {
    var started: [Lens.ID] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    var isWaiting: Bool { continuation != nil }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
