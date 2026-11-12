import Foundation
import Testing

@testable import NopeCore

/// Manual controls through `CameraModel`, against a scripted backend: every mode, rule and limit.
@MainActor
struct ManualControlsModelTests {
    typealias Fixtures = ManualFixtures

    /// A started camera on the first lens, with manual controls on unless `enabled` is false.
    func makeModel(
        lenses: [Lens] = [Fixtures.wide], enabled: Bool = true, applyErrors: [CaptureError?] = [],
        bracketError: CaptureError? = nil, sleep: @escaping @Sendable (Double) async throws -> Void = { _ in }
    ) async -> (CameraModel, ScriptedManualBackend) {
        let backend = ScriptedManualBackend(lenses: lenses, applyErrors: applyErrors, bracketError: bracketError)
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), sleep: sleep)
        await model.send(.start)
        if enabled { await model.send(.manual(.setEnabled(true))) }
        return (model, backend)
    }

    /// Delivers readings to the model and ends the stream.
    func deliver(_ readings: ExposureReading..., to model: CameraModel, from backend: ScriptedManualBackend) async {
        for reading in readings { backend.emit(reading) }
        backend.finishReadings()
        await model.manual.observeReadings()
    }

    func send(_ model: CameraModel, _ intents: ManualControlIntent...) async {
        for intent in intents { await model.send(.manual(intent)) }
    }

    // MARK: - Defaults and the option

    @Test func defaultsAreFullAutoAndHidden() {
        let model = CameraModel(backend: ScriptedManualBackend(lenses: [Fixtures.wide]))
        let manual = model.manual
        #expect(manual.isSupported)
        #expect(!manual.isEnabled)
        #expect(manual.settings == .automatic)
        #expect(manual.reading == nil)
        #expect(manual.bracket == nil)
        #expect(manual.interval == .standard)
        #expect(manual.intervalProgress == nil)
        #expect(manual.lens == nil)
        #expect(manual.capabilities == .none)
        #expect(manual.bracketFrameCounts.isEmpty)
        #expect(manual.tint == 0)
        #expect(ManualControl.allCases.allSatisfy { manual.availability(of: $0) == .unavailable })
        #expect(ManualControl.allCases.allSatisfy { manual.scale(for: $0) == nil })
        #expect(manual.value(of: .exposureCompensation) == 0)
        for control in [ManualControl.iso, .shutter, .aperture, .focus, .whiteBalance] {
            #expect(manual.value(of: control) == nil)
        }
        #expect(!model.isCleanView)
    }

    @Test func aBackendWithoutManualControlsIsNotSupported() async {
        let model = CameraModel(backend: ScriptedBackend(capabilities: DeviceCapabilities(lenses: [Fixtures.wide])))
        #expect(!model.manual.isSupported)
        await model.manual.observeReadings()
        await model.send(.start)
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setValue(.iso, 400)))
        #expect(model.manual.settings.iso == 400)
    }

    @Test func intentsAreIgnoredWhileOff() async {
        let (model, backend) = await makeModel(enabled: false)
        await send(model, .setValue(.iso, 400), .setBracket(BracketSettings(frameCount: 3, step: 1)), .startInterval)
        #expect(model.manual.settings == .automatic)
        #expect(model.manual.bracket == nil)
        #expect(model.manual.intervalProgress == nil)
        await send(model, .setInterval(IntervalSettings(interval: 5, count: 3)))
        #expect(model.manual.interval == IntervalSettings(interval: 5, count: 3))
        #expect(await backend.applied.isEmpty)
    }

    @Test func turningOnStartsReadingsAndOffReturnsToFullAuto() async {
        let (model, backend) = await makeModel()
        await send(model, .setEnabled(true))
        #expect(await backend.readingSwitches == [true])
        await send(model, .setValue(.iso, 400), .setBracket(BracketSettings(frameCount: 3, step: 1)))
        await send(model, .setEnabled(false))
        #expect(!model.manual.isEnabled)
        #expect(model.manual.settings == .automatic)
        #expect(model.manual.bracket == nil)
        #expect(await backend.readingSwitches == [true, false])
        #expect(await backend.applied.last == .automatic)
        let count = await backend.applied.count
        await send(model, .setEnabled(true), .setEnabled(false))
        #expect(await backend.applied.count == count)
    }

    @Test func readingsShowInAutoSlotsAndAreIgnoredWhileOff() async {
        let (model, backend) = await makeModel(enabled: false)
        await deliver(Fixtures.reading, to: model, from: backend)
        #expect(model.manual.reading == nil)

        let (onModel, onBackend) = await makeModel()
        await deliver(Fixtures.reading, to: onModel, from: onBackend)
        let manual = onModel.manual
        #expect(manual.reading == Fixtures.reading)
        #expect(manual.value(of: .iso) == 200)
        #expect(manual.value(of: .shutter) == 0.01)
        #expect(manual.value(of: .aperture) == 1.5)
        #expect(manual.value(of: .focus) == 0.8)
        #expect(manual.value(of: .whiteBalance) == 4000)
        #expect(manual.tint == 10)
    }

    // MARK: - Availability

    @Test func availabilityFollowsTheLens() async {
        let (wide, _) = await makeModel()
        #expect(ManualControl.allCases.allSatisfy { wide.manual.availability(of: $0) == .adjustable })
        #expect(wide.manual.exposureModes == [.program, .shutterPriority, .isoPriority, .manual])
        #expect(wide.manual.bracketFrameCounts == [3, 5])

        let (basic, _) = await makeModel(lenses: [Fixtures.basicLens])
        #expect(basic.manual.availability(of: .aperture) == .fixed(2.2))
        #expect(basic.manual.value(of: .aperture) == 2.2)
        #expect(basic.manual.exposureModes == [.program, .manual])

        let (bare, _) = await makeModel(lenses: [Fixtures.bare])
        #expect(ManualControl.allCases.allSatisfy { bare.manual.availability(of: $0) == .unavailable })

        let variableWithoutPriority = Lens(
            id: "v", kind: .wide, bayerRAWFormat: nil, isoRange: 50...800,
            aperture: ApertureRange(minimumFNumber: 1.5, maximumFNumber: 4, recommendedStops: [1.5, 4]),
            manualControls: Fixtures.full.withoutAperturePriority)
        let (variable, _) = await makeModel(lenses: [variableWithoutPriority])
        #expect(variable.manual.availability(of: .aperture) == .unavailable)
        // ISO priority alone is enough for ISO; no shutter range means no shutter.
        #expect(variable.manual.availability(of: .iso) == .adjustable)
        #expect(variable.manual.availability(of: .shutter) == .unavailable)
    }

    @Test func compensationIsBlockedInManualExposure() async {
        let (model, _) = await makeModel()
        await send(model, .setExposureMode(.manual))
        #expect(model.manual.availability(of: .exposureCompensation) == .blockedByManualExposure)
        await send(model, .setValue(.exposureCompensation, 1))
        #expect(model.manual.settings.exposureCompensation == 0)
    }

    // MARK: - Setting values

    @Test func valuesAreLimitedToTheLens() async {
        let (model, backend) = await makeModel()
        await send(
            model, .setValue(.exposureCompensation, 9), .setValue(.iso, 1), .setValue(.shutter, 30),
            .setValue(.aperture, 1), .setValue(.focus, -1), .setValue(.whiteBalance, 50_000))
        let settings = model.manual.settings
        #expect(settings.exposureCompensation == 3)
        #expect(settings.iso == 50)
        #expect(settings.shutter == 1)
        #expect(settings.aperture == 1.5)
        #expect(settings.focus == 0)
        #expect(settings.whiteBalance == WhiteBalance(temperature: 10_000))
        #expect(await backend.applied.count == 6)
    }

    @Test func priorityModesKeepTheOtherOnAuto() async {
        let (model, _) = await makeModel()
        await send(model, .setValue(.iso, 400))
        #expect(model.manual.settings.exposureMode == .isoPriority)
        await send(model, .setAuto(.iso), .setValue(.shutter, 0.01))
        #expect(model.manual.settings.exposureMode == .shutterPriority)
        await send(model, .setAuto(.shutter))
        #expect(model.manual.settings.exposureMode == .program)
    }

    @Test func withoutPriorityModesTheOtherIsFixedToo() async {
        let (model, backend) = await makeModel(lenses: [Fixtures.basicLens])
        await deliver(Fixtures.reading, to: model, from: backend)
        await send(model, .setValue(.iso, 400))
        #expect(model.manual.settings.iso == 400)
        #expect(model.manual.settings.shutter == 0.01)
        await send(model, .setAuto(.shutter))
        #expect(model.manual.settings.exposureMode == .program)
        await send(model, .setValue(.shutter, 0.5))
        #expect(model.manual.settings.iso == 200)
        await send(model, .setAuto(.iso))
        #expect(model.manual.settings.exposureMode == .program)
    }

    @Test func fixingTheOtherWithoutAReadingUsesCommonStartingValues() async {
        let (model, _) = await makeModel(lenses: [Fixtures.basicLens])
        await send(model, .setValue(.iso, 400))
        #expect(model.manual.settings.shutter == 1.0 / 60)
        await send(model, .allAuto, .setValue(.shutter, 0.5))
        #expect(model.manual.settings.iso == 100)
    }

    @Test func fixingTheOtherWithoutARangeLeavesItAuto() async {
        let noShutterRange = Lens(
            id: "n", kind: .wide, bayerRAWFormat: nil, isoRange: 50...800, manualControls: Fixtures.basic)
        let (model, _) = await makeModel(lenses: [noShutterRange])
        await send(model, .setValue(.iso, 400))
        #expect(model.manual.settings.iso == 400)
        #expect(model.manual.settings.shutter == nil)
    }

    @Test func stepsMoveAlongTheScale() async {
        let (model, backend) = await makeModel()
        await deliver(Fixtures.reading, to: model, from: backend)
        await send(
            model, .step(.exposureCompensation, by: -2), .step(.iso, by: 1), .step(.shutter, by: -1),
            .step(.aperture, by: 1), .step(.focus, by: 1), .step(.whiteBalance, by: 1))
        let settings = model.manual.settings
        #expect(settings.iso == 250)
        #expect(settings.shutter == 1.0 / 125)
        #expect(abs(settings.exposureCompensation + 2.0 / 3) < 0.000_1)
        #expect(settings.aperture == 2)
        #expect(abs((settings.focus ?? 0) - 0.85) < 0.000_1)
        #expect(settings.whiteBalance == WhiteBalance(temperature: 4100, tint: 10))
    }

    @Test func stepsWithoutAReadingStartFromCommonValues() async {
        let (model, _) = await makeModel()
        await send(
            model, .step(.iso, by: 0), .step(.shutter, by: 0), .step(.focus, by: 0), .step(.whiteBalance, by: 0),
            .step(.aperture, by: 0))
        let settings = model.manual.settings
        #expect(settings.iso == 100)
        #expect(settings.shutter == 1.0 / 60)
        #expect(settings.focus == 0.5)
        #expect(settings.whiteBalance == WhiteBalance(temperature: 5500))
        #expect(settings.aperture == 1.5)
    }

    @Test func unavailableControlsDoNothing() async {
        let (model, backend) = await makeModel(lenses: [Fixtures.bare])
        await send(
            model, .setValue(.iso, 100), .step(.focus, by: 1), .setTint(10), .setWhiteBalancePreset(.shade),
            .setExposureMode(.manual), .setMetering(.spot), .setExposureLock(true), .setFocusLock(true))
        #expect(model.manual.settings == .automatic)
        #expect(await backend.applied.isEmpty)
        let (basic, _) = await makeModel(lenses: [Fixtures.basicLens])
        await send(basic, .step(.aperture, by: 1), .setExposureMode(.shutterPriority))
        #expect(basic.manual.settings == .automatic)
    }

    @Test func whiteBalanceTintAndPresets() async {
        let (model, backend) = await makeModel()
        await send(model, .setTint(-20))
        #expect(model.manual.settings.whiteBalance == WhiteBalance(temperature: 5500, tint: -20))
        await send(model, .setWhiteBalancePreset(.tungsten))
        #expect(model.manual.settings.whiteBalance == WhiteBalance(temperature: 3200))
        await send(model, .setAuto(.whiteBalance))
        await deliver(Fixtures.reading, to: model, from: backend)
        await send(model, .setTint(400))
        #expect(model.manual.settings.whiteBalance == WhiteBalance(temperature: 4000, tint: 150))
    }

    @Test func resetEachControl() async {
        let (model, _) = await makeModel()
        await send(
            model, .setValue(.exposureCompensation, 1), .setValue(.aperture, 2), .setValue(.focus, 0.2),
            .setValue(.whiteBalance, 3000))
        await send(model, .setAuto(.exposureCompensation), .setAuto(.aperture), .setAuto(.focus), .setAuto(.whiteBalance))
        #expect(model.manual.settings == .automatic)
    }

    // MARK: - Modes, metering and locks

    @Test func exposureModes() async {
        let (model, backend) = await makeModel()
        await deliver(Fixtures.reading, to: model, from: backend)
        await send(model, .setExposureLock(true), .setExposureMode(.shutterPriority))
        #expect(model.manual.settings.shutter == 0.01)
        #expect(model.manual.settings.iso == nil)
        #expect(!model.manual.settings.exposureLocked)
        await send(model, .setExposureMode(.isoPriority))
        #expect(model.manual.settings.iso == 200)
        #expect(model.manual.settings.shutter == nil)
        await send(model, .setExposureMode(.manual))
        #expect(model.manual.settings.iso == 200)
        #expect(model.manual.settings.shutter == 0.01)
        await send(model, .setExposureMode(.program))
        #expect(model.manual.settings.exposureMode == .program)
        await send(model, .setValue(.shutter, 0.5), .setExposureMode(.shutterPriority))
        #expect(model.manual.settings.shutter == 0.5)
    }

    @Test func meteringAndLocks() async {
        let (model, backend) = await makeModel()
        await send(model, .setMetering(.wholeFrame), .setExposureLock(true), .setFocusLock(true))
        #expect(model.manual.settings.metering == .wholeFrame)
        #expect(model.manual.settings.exposureLocked)
        #expect(model.manual.settings.focusLocked)
        #expect(await backend.applied.last?.exposure == .locked)
        #expect(await backend.applied.last?.focus == .locked)
        await send(model, .setExposureLock(false), .setFocusLock(false), .setValue(.iso, 100), .setValue(.focus, 0.5))
        #expect(!model.manual.canLockExposure)
        #expect(!model.manual.canLockFocus)
        await send(model, .setExposureLock(true), .setFocusLock(true))
        #expect(!model.manual.settings.exposureLocked)
        #expect(!model.manual.settings.focusLocked)
    }

    @Test func settingAValueClearsItsLock() async {
        let (model, _) = await makeModel()
        await send(model, .setExposureLock(true), .setFocusLock(true), .setValue(.aperture, 2), .setValue(.focus, 0.3))
        #expect(!model.manual.settings.exposureLocked)
        #expect(!model.manual.settings.focusLocked)
        await send(model, .allAuto, .setExposureLock(true), .setValue(.shutter, 0.1))
        #expect(!model.manual.settings.exposureLocked)
    }

    @Test func allAutoReturnsEverything() async {
        let (model, backend) = await makeModel()
        await send(model, .setValue(.iso, 100), .setMetering(.spot), .setValue(.focus, 0.5))
        await send(model, .allAuto)
        #expect(model.manual.settings.isAutomatic)
        #expect(await backend.applied.last == .automatic)
        let count = await backend.applied.count
        await send(model, .allAuto)
        #expect(await backend.applied.count == count)
    }

    // MARK: - Applying

    @Test func refusedSettingsAreRestoredAndPausedOnesKept() async {
        let (model, _) = await makeModel(applyErrors: [.configurationFailed, .notRunning])
        await send(model, .setValue(.iso, 400))
        #expect(model.manual.settings == .automatic)
        await send(model, .setValue(.iso, 400))
        #expect(model.manual.settings.iso == 400)
    }

    @Test func settingsAreAppliedAgainAfterEachStart() async {
        let (model, backend) = await makeModel(lenses: [Fixtures.wide, Fixtures.basicLens])
        #expect(await backend.applied.isEmpty)
        await send(model, .setValue(.focus, 0.5))
        await model.send(.selectLens("basic"))
        let applied = await backend.applied
        #expect(applied.count == 2)
        #expect(applied.last?.focus == .lensPosition(0.5))
        #expect(model.manual.lens == Fixtures.basicLens)
    }

    @Test func aNewLensDropsTheReadingAndABracketItCantTake() async {
        let five = BracketSettings(frameCount: 5, step: 1)
        let (model, backend) = await makeModel(lenses: [Fixtures.wide, Fixtures.basicLens])
        await deliver(Fixtures.reading, to: model, from: backend)
        await send(model, .setBracket(five))
        #expect(model.manual.bracket == five)
        await model.send(.selectLens("basic"))
        #expect(model.manual.reading == nil)
        #expect(model.manual.bracket == nil)

        let three = BracketSettings(frameCount: 3, step: 1)
        await send(model, .setBracket(three))
        await model.send(.selectLens("wide"))
        #expect(model.manual.bracket == three)
    }

    @Test func restartingTheSameLensKeepsTheReading() async {
        let (model, backend) = await makeModel()
        await deliver(Fixtures.reading, to: model, from: backend)
        await model.send(.start)
        #expect(model.manual.reading == Fixtures.reading)
    }

    // MARK: - Bracketing

    @Test func bracketSettingsMustFitTheLens() async {
        let (model, _) = await makeModel()
        await send(model, .setBracket(BracketSettings(frameCount: 7, step: 1)))
        #expect(model.manual.bracket == nil)
        await send(model, .setBracket(BracketSettings(frameCount: 3, step: 0.5)))
        #expect(model.manual.bracket == nil)
        await send(model, .setBracket(BracketSettings(frameCount: 3, step: 2)), .setBracket(nil))
        #expect(model.manual.bracket == nil)
    }

    @Test func bracketTakesSeparatePhotos() async throws {
        let (model, backend) = await makeModel()
        await model.send(.capture)
        #expect(await backend.captureCount == 1)
        await send(model, .setBracket(BracketSettings(frameCount: 3, step: 1)))
        // No reading yet: nothing to start from, so a single photo.
        await model.send(.capture)
        #expect(await backend.captureCount == 2)
        await deliver(Fixtures.reading, to: model, from: backend)
        await model.send(.capture)
        let frames = try #require(await backend.brackets.first)
        #expect(frames.map(\.exposureDuration) == [0.005, 0.01, 0.02])
        #expect(frames.map(\.iso) == [200, 200, 200])
        guard case .savedBracket(let photos) = model.captureStatus else {
            Issue.record("expected a saved bracket")
            return
        }
        #expect(photos.count == 3)
        #expect(photos.allSatisfy { $0.signature == .unsigned(.unavailable) })
    }

    @Test func bracketInShutterPriorityChangesISO() async throws {
        let (model, backend) = await makeModel()
        await deliver(Fixtures.reading, to: model, from: backend)
        await send(model, .setValue(.shutter, 0.01), .setBracket(BracketSettings(frameCount: 3, step: 1)))
        await model.send(.capture)
        let frames = try #require(await backend.brackets.first)
        #expect(frames.map(\.iso) == [100, 200, 400])
    }

    @Test func bracketNeedsRangesAndManualControlsOn() async {
        let noRanges = Lens(id: "n", kind: .wide, bayerRAWFormat: nil, maxBracketedPhotoCount: 3)
        let (model, backend) = await makeModel(lenses: [noRanges])
        await send(model, .setBracket(BracketSettings(frameCount: 3, step: 1)))
        await deliver(Fixtures.reading, to: model, from: backend)
        await model.send(.capture)
        #expect(await backend.brackets.isEmpty)
        #expect(await backend.captureCount == 1)
    }

    @Test func aFailedBracketIsReported() async {
        let (model, backend) = await makeModel(bracketError: .blankPicture)
        await deliver(Fixtures.reading, to: model, from: backend)
        await send(model, .setBracket(BracketSettings(frameCount: 3, step: 1)))
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.blankPicture))
        #expect(model.sessionStatus == .running)
    }

    @Test func aBracketWithoutASaverIsNotSaved() async {
        let backend = ScriptedManualBackend(lenses: [Fixtures.wide])
        let model = CameraModel(backend: backend)
        await model.send(.start)
        await send(model, .setEnabled(true), .setValue(.iso, 100), .setValue(.shutter, 0.01))
        await send(model, .setBracket(BracketSettings(frameCount: 3, step: 1)))
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.savingUnavailable))
    }

    @Test func aBracketStopsAtTheFirstFrameThatIsNotSaved() async {
        let backend = ScriptedManualBackend(lenses: [Fixtures.wide])
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(library: FakeLibrary(error: .saveFailed)))
        await model.send(.start)
        await send(model, .setEnabled(true), .setValue(.iso, 100), .setValue(.shutter, 0.01))
        await send(model, .setBracket(BracketSettings(frameCount: 3, step: 1)))
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.saveFailed))
    }

    @Test func aBackendWithoutBracketsTakesASinglePhoto() async {
        let backend = ScriptedBackend(capabilities: DeviceCapabilities(lenses: [Fixtures.wide]))
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.start)
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setValue(.iso, 100)))
        await model.send(.manual(.setValue(.shutter, 0.01)))
        await model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1))))
        await model.send(.capture)
        #expect(await backend.captureRequests.count == 1)
        guard case .saved = model.captureStatus else {
            Issue.record("expected one saved photo")
            return
        }
    }

    // MARK: - Interval shooting

    /// Waits until the running series has ended.
    func waitForSeries(_ model: CameraModel) async {
        while model.manual.intervalProgress != nil { await Task.yield() }
    }

    @Test func intervalTakesEveryPhoto() async {
        let (model, backend) = await makeModel()
        await send(model, .setInterval(IntervalSettings(interval: 5, count: 3)), .startInterval)
        #expect(model.manual.intervalProgress != nil)
        await send(model, .startInterval)
        await waitForSeries(model)
        #expect(await backend.captureCount == 3)
    }

    @Test func stoppingDuringASleepEndsTheSeries() async {
        let gate = AsyncStream<Void>.makeStream()
        let (model, backend) = await makeModel(sleep: { _ in
            gate.continuation.yield()
            try await Task.sleep(for: .seconds(60))
        })
        await send(model, .setInterval(IntervalSettings(interval: 60, count: 5)), .startInterval)
        var iterator = gate.stream.makeAsyncIterator()
        await iterator.next()
        #expect(model.manual.intervalProgress == IntervalProgress(taken: 1, total: 5))
        await send(model, .stopInterval)
        #expect(model.manual.intervalProgress == nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(await backend.captureCount == 1)
    }

    @Test func stoppingDuringACaptureEndsTheSeries() async {
        let (model, backend) = await makeModel()
        await send(model, .setInterval(IntervalSettings(interval: 1, count: 4)))
        await model.manual.handle(.startInterval) { [model] in
            await model.send(.manual(.stopInterval))
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(model.manual.intervalProgress == nil)
        #expect(await backend.captureCount == 0)
    }

    @Test func turningOffStopsASeries() async {
        let (model, _) = await makeModel(sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        await send(model, .setInterval(IntervalSettings(interval: 60, count: 3)), .startInterval)
        await send(model, .setEnabled(false))
        #expect(model.manual.intervalProgress == nil)
    }

    @Test func theDefaultSleepWaitsBetweenPhotos() async {
        let backend = ScriptedManualBackend(lenses: [Fixtures.wide])
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.start)
        await send(model, .setEnabled(true), .setInterval(IntervalSettings(interval: 1, count: 2)), .startInterval)
        let start = ContinuousClock.now
        await waitForSeries(model)
        #expect(ContinuousClock.now - start >= .seconds(0.9))
        #expect(await backend.captureCount == 2)
    }

    // MARK: - Clean view

    @Test func cleanViewChangesNoSetting() async {
        let (model, backend) = await makeModel()
        await model.send(.setCleanView(true))
        #expect(model.isCleanView)
        await model.send(.setCleanView(false))
        #expect(!model.isCleanView)
        #expect(await backend.applied.isEmpty)
    }
}

extension ManualCapabilities {
    /// The same capabilities without aperture priority.
    var withoutAperturePriority: ManualCapabilities {
        ManualCapabilities(
            supportsManualExposure: supportsManualExposure, supportsShutterPriority: supportsShutterPriority,
            supportsISOPriority: supportsISOPriority, supportsAperturePriority: false,
            exposureCompensationRange: exposureCompensationRange, supportsExposureLock: supportsExposureLock,
            supportsAutoFocus: supportsAutoFocus, supportsFocusLock: supportsFocusLock,
            supportsManualFocus: supportsManualFocus, supportsManualWhiteBalance: supportsManualWhiteBalance,
            meteringModes: meteringModes)
    }
}
