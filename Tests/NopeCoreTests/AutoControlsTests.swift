import Foundation
import Testing

@testable import NopeCore

/// The values and rules behind the automatic aids: points, the fast shutter rule, the close-up
/// detector and the device controls they add (issues #35, #41, #51 and #56).
struct AutoValueTests {
    typealias Fixtures = AutoFixtures

    // MARK: - Points

    @Test func framePointsStayInsideThePicture() {
        #expect(FramePoint(x: -0.2, y: 1.3) == FramePoint(x: 0, y: 1))
        #expect(FramePoint.center == FramePoint(x: 0.5, y: 0.5))
        #expect(FramePoint.normalized(locationX: 30, locationY: 120, width: 120, height: 160) == FramePoint(x: 0.25, y: 0.75))
        #expect(FramePoint.normalized(locationX: 1, locationY: 1, width: 0, height: 10) == nil)
        #expect(FramePoint.normalized(locationX: 1, locationY: 1, width: 10, height: 0) == nil)
    }

    @Test func aTapOnTheMagnifierLandsUnderTheFinger() {
        let anchor = FramePoint(x: 0.25, y: 0.5)
        #expect(anchor.unmagnified(scale: 3, anchor: anchor) == anchor)
        let corner = FramePoint(x: 1, y: 0.5).unmagnified(scale: 3, anchor: anchor)
        #expect(abs(corner.x - 0.5) < 1e-12)
        #expect(corner.y == 0.5)
    }

    // MARK: - Fast shutter rule

    @Test func fastShutterChoicesAndHandheldRule() {
        #expect(FastShutter.handheld.slowestShutter == nil)
        #expect(FastShutter.freezeMotion.slowestShutter == 1.0 / 500.0)
        #expect(FastShutter.freezeFastMotion.slowestShutter == 1.0 / 1000.0)
        // 24 mm: 1/48 s.
        #expect(AutoShutter.handheldLimit(for: Fixtures.handheld) == 1.0 / 48.0)
        #expect(AutoShutter.handheldLimit(for: Fixtures.lens(focalLength: nil)) == nil)
        #expect(AutoShutter.handheldLimit(for: Fixtures.lens(focalLength: 0)) == nil)
        #expect(AutoShutter.handheldLimit(for: Fixtures.lens(focalLength: 24, durations: nil)) == nil)
        // Kept inside the lens's range.
        #expect(AutoShutter.handheldLimit(for: Fixtures.lens(focalLength: 24, durations: 0.001...0.01)) == 0.01)
    }

    @Test func limitsAreShortestFirstWithoutDuplicates() {
        #expect(AutoShutter.limits(for: Fixtures.handheld, fastShutter: .handheld) == [1.0 / 48.0])
        #expect(AutoShutter.limits(for: Fixtures.handheld, fastShutter: .freezeMotion) == [1.0 / 500.0, 1.0 / 48.0])
        let narrow = Fixtures.lens(focalLength: 100, durations: 0.01...0.5)
        #expect(AutoShutter.limits(for: narrow, fastShutter: .freezeFastMotion) == [0.01])
        #expect(AutoShutter.limits(for: Fixtures.lens(focalLength: nil), fastShutter: .freezeMotion) == [1.0 / 500.0])
        #expect(AutoShutter.limits(for: Fixtures.lens(focalLength: 24, durations: nil), fastShutter: .freezeMotion).isEmpty)
    }

    @Test func theLimitIsLiftedOnlyWhenTheSceneIsTooDark() {
        let limit = 1.0 / 48.0
        let bright = Fixtures.reading(iso: 100, duration: 1.0 / 500.0)
        #expect(AutoShutter.longestShutter(for: bright, lens: Fixtures.handheld, fastShutter: .handheld, current: limit) == limit)
        // ISO 6400 at the limit, 1 EV under: needs twice the highest ISO.
        let dark = Fixtures.reading(iso: 6400, duration: limit, offset: -1)
        #expect(AutoShutter.longestShutter(for: dark, lens: Fixtures.handheld, fastShutter: .handheld, current: limit) == nil)
        // Exactly what the limit allows keeps it, but coming back from a lifted limit needs half a stop.
        let edge = Fixtures.reading(iso: 6400, duration: limit)
        #expect(AutoShutter.longestShutter(for: edge, lens: Fixtures.handheld, fastShutter: .handheld, current: limit) == limit)
        #expect(AutoShutter.longestShutter(for: edge, lens: Fixtures.handheld, fastShutter: .handheld, current: nil) == nil)
        let brighter = Fixtures.reading(iso: 3200, duration: limit)
        #expect(AutoShutter.longestShutter(for: brighter, lens: Fixtures.handheld, fastShutter: .handheld, current: nil) == limit)
        // Freeze motion steps back to the handheld limit before lifting it.
        let dim = Fixtures.reading(iso: 6400, duration: 1.0 / 500.0, offset: -2)
        #expect(
            AutoShutter.longestShutter(for: dim, lens: Fixtures.handheld, fastShutter: .freezeMotion, current: 1.0 / 500.0)
                == limit)
        // A lens without an ISO range has no rule.
        let noISO = Fixtures.lens(focalLength: 24, isos: nil)
        #expect(AutoShutter.longestShutter(for: bright, lens: noISO, fastShutter: .handheld, current: nil) == nil)
    }

    @Test func theSteadyLimitCountsStabilization() {
        // 24 mm without stabilization: the handheld rule, 1/48 s. With it, two stops slower, 1/12 s.
        #expect(AutoShutter.steadyLimit(for: Fixtures.handheld) == 1.0 / 48.0)
        #expect(AutoShutter.steadyLimit(for: Fixtures.lens(focalLength: 24, stabilized: true)) == 1.0 / 12.0)
        // 120 mm stabilized: 1/60 s; 13 mm unstabilized: 1/26 s.
        #expect(AutoShutter.steadyLimit(for: Fixtures.lens(focalLength: 120, stabilized: true)) == 1.0 / 60.0)
        #expect(AutoShutter.steadyLimit(for: Fixtures.lens(focalLength: 13)) == 1.0 / 26.0)
        // Kept inside the shutter range, at both ends.
        #expect(AutoShutter.steadyLimit(for: Fixtures.lens(focalLength: 24, durations: 0.0001...0.01, stabilized: true)) == 0.01)
        #expect(AutoShutter.steadyLimit(for: Fixtures.lens(focalLength: 24, durations: 0.1...1)) == 0.1)
        // No focal length, a focal length of 0 or no shutter range: no limit.
        #expect(AutoShutter.steadyLimit(for: Fixtures.lens(focalLength: nil, stabilized: true)) == nil)
        #expect(AutoShutter.steadyLimit(for: Fixtures.lens(focalLength: 0)) == nil)
        #expect(AutoShutter.steadyLimit(for: Fixtures.lens(focalLength: 24, durations: nil)) == nil)
        #expect(AutoShutter.stabilizationAllowance == 2)
    }

    @Test func theSteadyHintTurnsOnPastTheLimitAndOffHalfAStopFaster() {
        let limit = 1.0 / 48.0
        // Just slower than the limit: on, from off or on.
        #expect(AutoShutter.showsSteadyHint(shutter: limit * 1.01, limit: limit, isShown: false))
        #expect(AutoShutter.showsSteadyHint(shutter: limit * 1.01, limit: limit, isShown: true))
        // At the limit, or just faster: it keeps its state.
        #expect(!AutoShutter.showsSteadyHint(shutter: limit, limit: limit, isShown: false))
        #expect(AutoShutter.showsSteadyHint(shutter: limit, limit: limit, isShown: true))
        #expect(AutoShutter.showsSteadyHint(shutter: limit * 0.75, limit: limit, isShown: true))
        // Half a stop faster: off.
        #expect(!AutoShutter.showsSteadyHint(shutter: limit * AutoShutter.returnMargin, limit: limit, isShown: true))
    }

    // MARK: - Device controls

    @Test func theTappedPointAimsOnlyWhatIsAutomatic() {
        let target = FocusTarget(viewfinderPoint: .center, devicePoint: FramePoint(x: 0.2, y: 0.3), isLocked: true)
        let assist = AssistSettings(focusTarget: target)
        let both = DeviceControls(settings: .automatic, lens: Fixtures.wide, assist: assist)
        #expect(both.pointOfInterest == .init(point: FramePoint(x: 0.2, y: 0.3), focuses: true, exposes: true, locks: true))
        let manualFocus = DeviceControls(settings: ManualSettings(focus: 0.4), lens: Fixtures.wide, assist: assist)
        #expect(manualFocus.pointOfInterest?.focuses == false)
        #expect(manualFocus.pointOfInterest?.exposes == true)
        let manualAll = DeviceControls(settings: ManualSettings(iso: 100, shutter: 0.01, focus: 0.4), lens: Fixtures.wide, assist: assist)
        #expect(manualAll.pointOfInterest == nil)
        #expect(DeviceControls(settings: .automatic, lens: Fixtures.fixedFocus, assist: assist).pointOfInterest?.focuses == false)
        #expect(DeviceControls(settings: .automatic, lens: ManualFixtures.bare, assist: assist).pointOfInterest == nil)
    }

    @Test func nearLimitAndLongestShutterNeedAutoAndSupport() {
        let assist = AssistSettings(nearFocusLimit: true, longestShutter: 5)
        let auto = DeviceControls(settings: .automatic, lens: Fixtures.wide, assist: assist)
        #expect(auto.nearFocusLimit)
        #expect(auto.longestAutoExposure == 1)
        #expect(auto != .automatic)
        let manual = DeviceControls(settings: ManualSettings(iso: 100, shutter: 0.01, focus: 0.2), lens: Fixtures.wide, assist: assist)
        #expect(!manual.nearFocusLimit)
        #expect(manual.longestAutoExposure == nil)
        #expect(!DeviceControls(settings: .automatic, lens: ManualFixtures.wide, assist: assist).nearFocusLimit)
        let noRange = DeviceControls(settings: .automatic, lens: Fixtures.lens(focalLength: 24, durations: nil), assist: assist)
        #expect(noRange.longestAutoExposure == nil)
        #expect(DeviceControls(settings: .automatic, lens: Fixtures.wide, assist: .none) == .automatic)
    }

    @Test func capabilitiesSayWhetherATapDoesAnything() {
        #expect(Fixtures.aids.supportsTapToFocus)
        #expect(Fixtures.fixedFocus.manualControls.supportsTapToFocus)
        #expect(!ManualCapabilities.none.supportsTapToFocus)
        #expect(!ManualFixtures.full.supportsNearFocusLimit)
    }
}

/// The aids through `CameraModel`, against a scripted backend.
@MainActor
struct AutoControlsModelTests {
    typealias Fixtures = AutoFixtures

    /// A started camera on the first lens.
    func makeModel(
        lenses: [Lens] = [Fixtures.wide], enabled: Bool = false, applyErrors: [CaptureError?] = [],
        previewSource: (any CameraPreviewSource)? = nil, clock: ManualClock = ManualClock()
    ) async -> (CameraModel, ScriptedManualBackend) {
        let backend = ScriptedManualBackend(lenses: lenses, applyErrors: applyErrors, previewSource: previewSource)
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), now: { clock.now() })
        await model.send(.start)
        if enabled { await model.send(.manual(.setEnabled(true))) }
        return (model, backend)
    }

    func send(_ model: CameraModel, _ intents: AutoControlIntent...) async {
        for intent in intents { await model.send(.auto(intent)) }
    }

    func deliver(_ readings: ExposureReading..., to model: CameraModel, from backend: ScriptedManualBackend) async {
        for reading in readings { backend.emit(reading) }
        backend.finishReadings()
        await model.manual.observeReadings()
    }

    // MARK: - Tap to focus and the lock

    @Test func aTapAimsFocusAndExposureAndTheSceneChangeReturnsToCenter() async {
        let (model, backend) = await makeModel()
        #expect(await backend.readingSwitches == [true])
        let point = FramePoint(x: 0.3, y: 0.6)
        await send(model, .focusAndExpose(at: point))
        #expect(model.manual.focusTarget == FocusTarget(viewfinderPoint: point, devicePoint: point, isLocked: false))
        #expect(await backend.applied.last?.pointOfInterest == .init(point: point, focuses: true, exposes: true, locks: false))
        backend.emitEvent(.subjectAreaChanged)
        backend.finishEvents()
        await model.observeEvents()
        #expect(model.manual.focusTarget == nil)
        #expect(await backend.applied.last == .automatic)
    }

    @Test func aLockStaysWhenTheSceneChangesUntilUnlocked() async {
        let (model, backend) = await makeModel()
        await send(model, .lockFocusAndExposure(at: nil))
        #expect(model.manual.focusTarget?.viewfinderPoint == .center)
        #expect(model.manual.focusTarget?.isLocked == true)
        await send(model, .focusAndExpose(at: FramePoint(x: 0.1, y: 0.1)), .lockFocusAndExposure(at: nil))
        #expect(model.manual.focusTarget == FocusTarget(
            viewfinderPoint: FramePoint(x: 0.1, y: 0.1), devicePoint: FramePoint(x: 0.1, y: 0.1), isLocked: true))
        backend.emitEvent(.subjectAreaChanged)
        backend.finishEvents()
        await model.observeEvents()
        #expect(model.manual.focusTarget?.isLocked == true)
        await send(model, .unlockFocusAndExposure)
        #expect(model.manual.focusTarget == nil)
        let count = await backend.applied.count
        await send(model, .unlockFocusAndExposure)
        #expect(await backend.applied.count == count)
        await model.manual.subjectAreaDidChange()
        #expect(await backend.applied.count == count)
    }

    @Test func thePreviewConvertsThePoint() async {
        let preview = FixedPreviewSource(result: FramePoint(x: 0.9, y: 0.1))
        let (model, backend) = await makeModel(previewSource: preview)
        await send(model, .focusAndExpose(at: .center))
        #expect(model.manual.focusTarget?.viewfinderPoint == .center)
        #expect(await backend.applied.last?.pointOfInterest?.point == FramePoint(x: 0.9, y: 0.1))
        preview.result = nil
        await send(model, .focusAndExpose(at: FramePoint(x: 0.2, y: 0.2)))
        #expect(model.manual.focusTarget?.viewfinderPoint == .center)
    }

    @Test func aLensWithoutAPointIgnoresTapsAndALensChangeClearsTheTarget() async {
        let (model, _) = await makeModel(lenses: [ManualFixtures.bare, Fixtures.wide])
        await model.send(.selectLens(ManualFixtures.bare.id))
        await send(model, .focusAndExpose(at: .center))
        #expect(model.manual.focusTarget == nil)
        await model.send(.selectLens(Fixtures.wide.id))
        await send(model, .lockFocusAndExposure(at: .center), .setNearFocusLimit(true))
        await model.send(.selectLens(ManualFixtures.bare.id))
        #expect(model.manual.focusTarget == nil)
        #expect(model.manual.nearFocusLimit)
    }

    @Test func allAutoClearsTheAids() async {
        let (model, backend) = await makeModel(enabled: true)
        await send(model, .lockFocusAndExposure(at: .center), .setNearFocusLimit(true))
        await model.send(.manual(.allAuto))
        #expect(model.manual.focusTarget == nil)
        #expect(!model.manual.nearFocusLimit)
        #expect(await backend.applied.last == .automatic)
        // With manual settings too, one change returns everything.
        await send(model, .focusAndExpose(at: .center))
        await model.send(.manual(.setValue(.iso, 400)))
        await model.send(.manual(.allAuto))
        #expect(model.manual.focusTarget == nil)
        #expect(model.manual.settings == .automatic)
        // Nothing to reset: nothing is applied.
        let count = await backend.applied.count
        await model.send(.manual(.allAuto))
        #expect(await backend.applied.count == count)
    }

    // MARK: - Exposure compensation in full auto

    @Test func exposureCompensationWorksInFullAuto() async {
        let (model, backend) = await makeModel()
        #expect(model.manual.canAdjustExposureCompensation)
        await send(model, .setExposureCompensation(-0.7))
        #expect(model.manual.settings.exposureCompensation == -0.7)
        #expect(await backend.applied.last?.exposure == .automatic(compensation: -0.7))
        await send(model, .setExposureCompensation(20))
        #expect(model.manual.settings.exposureCompensation == 3)
        await send(model, .stepExposureCompensation(by: -1))
        #expect(abs(model.manual.settings.exposureCompensation - (3 - 1.0 / 3.0)) < 1e-9)
        let count = await backend.applied.count
        await send(model, .setExposureCompensation(model.manual.settings.exposureCompensation))
        #expect(await backend.applied.count == count)
        await send(model, .setExposureCompensation(0))
        #expect(await backend.applied.last == .automatic)
    }

    @Test func exposureCompensationNeedsTheLensAndRestoresOnRefusal() async {
        let (bare, bareBackend) = await makeModel(lenses: [ManualFixtures.bare])
        #expect(!bare.manual.canAdjustExposureCompensation)
        await send(bare, .setExposureCompensation(1), .stepExposureCompensation(by: 1))
        #expect(bare.manual.settings.exposureCompensation == 0)
        #expect(await bareBackend.applied.isEmpty)
        let (model, _) = await makeModel(applyErrors: [.configurationFailed])
        await send(model, .setExposureCompensation(1))
        #expect(model.manual.settings.exposureCompensation == 0)
    }

    @Test func aCompensationSetBeforeTheCameraRunsIsAppliedWhenItStarts() async {
        let (model, backend) = await makeModel(lenses: [Fixtures.wide, Fixtures.fixedFocus])
        await send(model, .setExposureCompensation(1))
        await model.send(.selectLens(Fixtures.fixedFocus.id))
        #expect(await backend.applied.last?.exposure == .automatic(compensation: 1))
    }

    // MARK: - Near focus limit

    @Test func theNearLimitNeedsALensThatSupportsIt() async {
        let (model, backend) = await makeModel(lenses: [ManualFixtures.wide, Fixtures.wide])
        await send(model, .setNearFocusLimit(true))
        #expect(!model.manual.nearFocusLimit)
        await model.send(.selectLens(Fixtures.wide.id))
        await send(model, .setNearFocusLimit(true))
        #expect(model.manual.nearFocusLimit)
        #expect(await backend.applied.last?.nearFocusLimit == true)
        await send(model, .setNearFocusLimit(false))
        #expect(await backend.applied.last == .automatic)
    }

    // MARK: - Fast shutter and the steady hint

    @Test func fullAutoLimitsTheShutterAndLiftsItInTheDark() async {
        let (model, backend) = await makeModel(lenses: [Fixtures.handheld])
        // Applied when the camera starts.
        #expect(await backend.applied.last?.longestAutoExposure == 1.0 / 48.0)
        #expect(model.manual.longestAutoShutter == 1.0 / 48.0)
        await deliver(Fixtures.reading(iso: 6400, duration: 1.0 / 48.0, offset: -2), to: model, from: backend)
        #expect(model.manual.longestAutoShutter == nil)
        // At the limit itself: not slower than the steady limit yet.
        #expect(!model.manual.showsSteadyHint)
        #expect(await backend.applied.last == .automatic)
        #expect(model.manual.reading == nil)
        // The camera then slows past it.
        await model.manual.record(Fixtures.reading(iso: 6400, duration: 1.0 / 24.0))
        #expect(model.manual.showsSteadyHint)
    }

    @Test func theLimitComesBackWhenTheLightDoes() async {
        let backend = ScriptedManualBackend(lenses: [Fixtures.handheld])
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.start)
        backend.emit(
            Fixtures.reading(iso: 6400, duration: 1.0 / 48.0, offset: -2),
            Fixtures.reading(iso: 100, duration: 1.0 / 500.0))
        backend.finishReadings()
        await model.manual.observeReadings()
        #expect(model.manual.longestAutoShutter == 1.0 / 48.0)
        #expect(!model.manual.showsSteadyHint)
    }

    @Test func choosingFreezeMotionUsesTheReading() async {
        let (model, backend) = await makeModel(lenses: [Fixtures.handheld])
        await send(model, .setFastShutter(.freezeMotion))
        #expect(model.manual.fastShutter == .freezeMotion)
        #expect(await backend.applied.last?.longestAutoExposure == 1.0 / 500.0)
        await send(model, .setFastShutter(.freezeMotion))
        await deliver(Fixtures.reading(iso: 100, duration: 1.0 / 2000.0), to: model, from: backend)
        await send(model, .setFastShutter(.freezeFastMotion))
        #expect(model.manual.longestAutoShutter == 1.0 / 1000.0)
    }

    @Test func theChoiceIsKeptBeforeTheCameraStarts() async {
        let model = CameraModel(backend: ScriptedManualBackend(lenses: [Fixtures.handheld]))
        await model.send(.auto(.setFastShutter(.freezeFastMotion)))
        #expect(model.manual.fastShutter == .freezeFastMotion)
        await model.send(.start)
        #expect(model.manual.longestAutoShutter == 1.0 / 1000.0)
    }

    @Test func manualControlsAreNeverLimitedAndGetNoHint() async {
        let (model, backend) = await makeModel(lenses: [Fixtures.handheld])
        await model.send(.manual(.setEnabled(true)))
        // The full-auto limit is taken off: P is the camera's own exposure.
        #expect(await backend.applied.last == .automatic)
        await deliver(Fixtures.reading(iso: 100, duration: 1.0 / 15.0), to: model, from: backend)
        #expect(model.manual.reading != nil)
        #expect(!model.manual.showsSteadyHint)
        #expect(model.manual.longestAutoShutter == 1.0 / 48.0)
        await model.send(.manual(.setValue(.shutter, 1.0 / 250.0)))
        #expect(!model.manual.showsSteadyHint)
        #expect(model.manual.settings.shutter == 1.0 / 250.0)
        // Back in full auto the limit returns.
        await model.send(.manual(.setEnabled(false)))
        #expect(await backend.applied.last?.longestAutoExposure == 1.0 / 48.0)
    }

    @Test func noHintWithoutAReadingOrALens() {
        let model = CameraModel(backend: ScriptedManualBackend(lenses: [Fixtures.handheld]))
        model.manual.updateSteadyHint()
        #expect(!model.manual.showsSteadyHint)
    }

    @Test func aReadingBeforeTheCameraStartsIsOnlyKept() async {
        let backend = ScriptedManualBackend(lenses: [Fixtures.handheld])
        let model = CameraModel(backend: backend)
        await deliver(Fixtures.reading(lensPosition: 0), to: model, from: backend)
        #expect(model.manual.lastReading != nil)
        #expect(!model.manual.suggestsCloseUpLens)
        #expect(await backend.applied.isEmpty)
    }

    // MARK: - Close-up suggestion

    /// Three seconds of readings, four a second, each moving the clock on a quarter second.
    func recordTooClose(_ model: CameraModel, clock: ManualClock) async {
        for _ in 0..<12 {
            clock.advance(by: .milliseconds(250))
            await model.manual.record(Fixtures.reading(lensPosition: 0, adjusting: true))
        }
    }

    @Test func theUltraWideIsSuggestedWhenTheSubjectIsTooClose() async {
        let clock = ManualClock()
        let (model, backend) = await makeModel(lenses: [Fixtures.wide, Fixtures.ultraWide], clock: clock)
        // Readings that arrive together prove nothing: no time passed at the nearest position.
        for _ in 0..<12 { backend.emit(Fixtures.reading(lensPosition: 0, adjusting: true)) }
        backend.finishReadings()
        await model.manual.observeReadings()
        #expect(!model.manual.suggestsCloseUpLens)
        await recordTooClose(model, clock: clock)
        #expect(model.manual.suggestsCloseUpLens)
        #expect(model.closeUpLens == Fixtures.ultraWide)
        await model.send(.auto(.dismissCloseUpSuggestion))
        #expect(model.closeUpLens == nil)
        await recordTooClose(model, clock: clock)
        #expect(!model.manual.suggestsCloseUpLens)
        // Switching lenses is the person's choice; on the ultra wide nothing is suggested.
        await model.send(.selectLens(Fixtures.ultraWide.id))
        await recordTooClose(model, clock: clock)
        #expect(model.manual.suggestsCloseUpLens)
        #expect(model.closeUpLens == nil)
    }

    @Test func noSuggestionWithManualFocusOrALockOrNoUltraWide() async {
        let clock = ManualClock()
        let (model, _) = await makeModel(lenses: [Fixtures.wide], enabled: true, clock: clock)
        await recordTooClose(model, clock: clock)
        #expect(model.manual.suggestsCloseUpLens)
        #expect(model.closeUpLens == nil)
        await model.send(.manual(.setValue(.focus, 0)))
        await recordTooClose(model, clock: clock)
        #expect(!model.manual.suggestsCloseUpLens)
        let (locked, _) = await makeModel(clock: clock)
        await locked.send(.auto(.lockFocusAndExposure(at: nil)))
        await recordTooClose(locked, clock: clock)
        #expect(!locked.manual.suggestsCloseUpLens)
        #expect(CameraModel(backend: ScriptedManualBackend(lenses: [Fixtures.wide])).closeUpLens == nil)
    }

    @Test func noSuggestionWhileTheAppHoldsTheLens() async {
        // Setting Nearest Focus at 0, or a focus bracket's first frames: the app holds the lens
        // near itself, so a near position and a search are no sign of a subject too close
        // (third review of 1.0.0, S4).
        let clock = ManualClock()
        let (model, _) = await makeModel(lenses: [Fixtures.wide, Fixtures.ultraWide], clock: clock)
        await recordTooClose(model, clock: clock)
        #expect(model.manual.suggestsCloseUpLens)
        model.manual.holdsControls = true
        await recordTooClose(model, clock: clock)
        #expect(!model.manual.suggestsCloseUpLens)
        #expect(model.closeUpLens == nil)
        // Given back, the detector starts again from nothing: one reading proves nothing.
        model.manual.holdsControls = false
        clock.advance(by: .milliseconds(250))
        await model.manual.record(Fixtures.reading(lensPosition: 0, adjusting: true))
        #expect(!model.manual.suggestsCloseUpLens)
        await recordTooClose(model, clock: clock)
        #expect(model.manual.suggestsCloseUpLens)
    }

    @Test func theUltraWideIsSuggestedOnlyWhereItCanHelp() async {
        // A fixed-focus ultra wide is never suggested.
        let fixedFocusUltraWide = Lens(
            id: "ultra-wide-fixed", kind: .ultraWide, bayerRAWFormat: "rgg4", manualControls: .none)
        let clock = ManualClock()
        let (fixed, _) = await makeModel(lenses: [Fixtures.wide, fixedFocusUltraWide], clock: clock)
        await recordTooClose(fixed, clock: clock)
        #expect(fixed.manual.suggestsCloseUpLens)
        #expect(fixed.closeUpLens == nil)
        #expect(fixed.capabilities?.closeUpFocusLens == nil)
        // Both report their closest focus: only an ultra wide that focuses closer is suggested.
        let wide = Fixtures.lens(focalLength: 24, closest: 200)
        for (closest, isSuggested) in [(20.0, true), (200.0, false), (300.0, false)] {
            let ultraWide = Lens(
                id: "ultra-wide-\(closest)", kind: .ultraWide, bayerRAWFormat: "rgg4", manualControls: Fixtures.aids,
                minimumFocusDistance: closest)
            let (model, _) = await makeModel(lenses: [wide, ultraWide], clock: clock)
            await recordTooClose(model, clock: clock)
            #expect((model.closeUpLens == ultraWide) == isSuggested, "\(closest)")
        }
        // Only one reports it: the ultra wide is still suggested (device check C2).
        let unknown = Lens(
            id: "ultra-wide-unknown", kind: .ultraWide, bayerRAWFormat: "rgg4", manualControls: Fixtures.aids)
        let (model, _) = await makeModel(lenses: [wide, unknown], clock: clock)
        await recordTooClose(model, clock: clock)
        #expect(model.closeUpLens == unknown)
    }

    // MARK: - Magnifier

    @Test func theMagnifierIsPreviewOnly() async {
        let (model, backend) = await makeModel()
        let count = await backend.applied.count
        await model.send(.auto(.setMagnifier(true)))
        #expect(model.isMagnifying)
        await model.send(.auto(.setMagnifier(false)))
        #expect(!model.isMagnifying)
        #expect(await backend.applied.count == count)
    }
}

/// A preview source that converts every point to a fixed one, or to `nil`.
final class FixedPreviewSource: CameraPreviewSource, @unchecked Sendable {
    /// The converted point, or `nil` as before a viewfinder is shown.
    @MainActor var result: FramePoint?

    @MainActor init(result: FramePoint?) {
        self.result = result
    }

    @MainActor func devicePoint(forViewfinderPoint point: FramePoint) -> FramePoint? {
        result
    }
}

/// Lenses and readings for the aid tests.
enum AutoFixtures {
    /// Every manual control and every aid.
    static let aids = ManualCapabilities(
        supportsManualExposure: true, supportsShutterPriority: true, supportsISOPriority: true,
        supportsAperturePriority: true, exposureCompensationRange: -8...8, supportsExposureLock: true,
        supportsAutoFocus: true, supportsFocusLock: true, supportsManualFocus: true, supportsManualWhiteBalance: true,
        meteringModes: [.center, .spot, .wholeFrame], supportsFocusPoint: true, supportsExposurePoint: true,
        supportsNearFocusLimit: true)

    /// A lens with the aids, ISO 50 to 6400, shutter up to 1 s and a 24 mm-equivalent focal
    /// length. Its id matches `ManualFixtures.wide`, so tests keep their lens.
    static let handheld = lens(focalLength: 24)

    /// The aids without a focal length, so full auto has no shutter limit.
    static let wide = Lens(
        id: "wide-aids", kind: .wide, bayerRAWFormat: "bgg4", isoRange: 50...6400, exposureDurationRange: 0.0001...1,
        aperture: .fixed(1.8), manualControls: aids, equivalentFocalLength: nil)

    /// An ultra wide with the aids.
    static let ultraWide = Lens(
        id: "ultra-wide-aids", kind: .ultraWide, bayerRAWFormat: "rgg4", isoRange: 50...3200,
        exposureDurationRange: 0.0001...1, aperture: .fixed(2.2), manualControls: aids, equivalentFocalLength: 13)

    /// A front camera with a fixed focus: it meters a point but can't focus on one.
    static let fixedFocus = Lens(
        id: "fixed-focus", kind: .front, bayerRAWFormat: nil, isoRange: 20...2000, exposureDurationRange: 0.0001...0.5,
        manualControls: ManualCapabilities(
            supportsManualExposure: false, supportsShutterPriority: false, supportsISOPriority: false,
            supportsAperturePriority: false, exposureCompensationRange: -8...8, supportsExposureLock: true,
            supportsAutoFocus: false, supportsFocusLock: false, supportsManualFocus: false,
            supportsManualWhiteBalance: false, meteringModes: [.center], supportsFocusPoint: false,
            supportsExposurePoint: true))

    /// A wide lens with the aids and optional ranges.
    static func lens(
        focalLength: Double?, isos: ClosedRange<Double>? = 50...6400, durations: ClosedRange<Double>? = 0.0001...1,
        stabilized: Bool = false, closest: Double? = nil
    ) -> Lens {
        Lens(
            id: "handheld", kind: .wide, bayerRAWFormat: "bgg4", isoRange: isos, exposureDurationRange: durations,
            aperture: .fixed(1.8), manualControls: aids, equivalentFocalLength: focalLength,
            minimumFocusDistance: closest, reportsStabilization: stabilized)
    }

    /// A reading.
    static func reading(
        iso: Double = 100, duration: Double = 0.01, offset: Double = 0, lensPosition: Double = 0.5, adjusting: Bool = false
    ) -> ExposureReading {
        ExposureReading(
            iso: iso, exposureDuration: duration, exposureOffset: offset, lensPosition: lensPosition, aperture: 1.8,
            whiteBalance: nil, isAdjustingFocus: adjusting)
    }
}
