import Foundation
import Testing

@testable import NopeCore

/// "Hold it steady or use a tripod." across mode changes: the hint follows only readings taken
/// in the current mode, so it doesn't stay on after Manual, Astro or a lens change, and it still
/// doesn't flicker near the threshold.
@MainActor
struct SteadyHintTests {
    typealias Fixtures = AutoFixtures

    /// The handheld lens's limit: 1/(2 × 24 mm).
    static let handheldLimit = 1.0 / 48.0

    /// Dark enough at the handheld limit and the highest ISO to lift it: two stops under.
    static let dim = Fixtures.reading(iso: 6400, duration: handheldLimit, offset: -2)

    /// Bright: well inside the handheld limit.
    static let bright = Fixtures.reading(iso: 100, duration: 1.0 / 500.0)

    /// What the camera still reports for a moment after a slow manual or astro exposure: a long
    /// shutter at a high ISO, longer than the full-auto limit allows.
    static let slowManual = Fixtures.reading(iso: 6400, duration: 1.0 / 4.0)

    /// A started camera on the first lens, with the storage and battery readable for Astro.
    func makeModel(lenses: [Lens] = [Fixtures.handheld]) async -> (CameraModel, ScriptedManualBackend) {
        let backend = ScriptedManualBackend(lenses: lenses)
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), deviceStatusReader: FakeStatusReader(bytes: nil))
        await model.send(.start)
        return (model, backend)
    }

    /// Feeds readings the way ``ManualControlsModel/observeReadings()`` does, one at a time.
    func record(_ readings: ExposureReading..., in model: CameraModel) async {
        for reading in readings { await model.manual.record(reading) }
    }

    @Test func leavingManualStartsAgainFromTheHandheldLimit() async {
        let (model, backend) = await makeModel()
        await record(Self.dim, in: model)
        #expect(model.manual.longestAutoShutter == nil)
        #expect(model.showsSteadyHint)
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setValue(.shutter, 1.0 / 4.0)))
        #expect(model.showsSteadyHint)
        await model.send(.manual(.setEnabled(false)))
        // Full auto starts again from its first limit, as on a new lens; the lifted limit and the
        // reading from before Manual are gone.
        #expect(model.manual.longestAutoShutter == Self.handheldLimit)
        #expect(model.manual.lastReading == nil)
        #expect(!model.showsSteadyHint)
        #expect(await backend.applied.last?.longestAutoExposure == Self.handheldLimit)
        // A fresh reading in the same dark scene shows it again.
        await record(Self.dim, in: model)
        #expect(model.showsSteadyHint)
    }

    @Test func aSlowReadingLeftOverFromManualDoesNotLiftTheLimit() async {
        let (model, _) = await makeModel()
        await record(Self.bright, in: model)
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setValue(.shutter, 1.0 / 4.0)))
        await record(Self.slowManual, in: model)
        #expect(model.showsSteadyHint)
        await model.send(.manual(.setEnabled(false)))
        #expect(!model.showsSteadyHint)
        // The camera hasn't caught up with full auto yet: its shutter is longer than the limit
        // auto exposure is allowed, so the reading is from before.
        await record(Self.slowManual, Self.slowManual, in: model)
        #expect(model.manual.longestAutoShutter == Self.handheldLimit)
        #expect(model.manual.lastReading == nil)
        #expect(!model.showsSteadyHint)
        await record(Self.bright, in: model)
        #expect(!model.showsSteadyHint)
        #expect(model.manual.lastReading == Self.bright)
    }

    @Test func enteringManualUsesOnlyReadingsTakenInManual() async {
        let (model, _) = await makeModel()
        await record(Self.dim, in: model)
        #expect(model.showsSteadyHint)
        await model.send(.manual(.setEnabled(true)))
        // P mode: the camera's own exposure, not yet read.
        #expect(model.manual.lastReading == nil)
        #expect(!model.showsSteadyHint)
        await record(Fixtures.reading(iso: 6400, duration: 1.0 / 15.0), in: model)
        #expect(model.showsSteadyHint)
        await record(Fixtures.reading(iso: 400, duration: 1.0 / 120.0), in: model)
        #expect(!model.showsSteadyHint)
        // A slow shutter the person sets shows the hint at once, before the next reading.
        await model.send(.manual(.setValue(.shutter, 1.0 / 4.0)))
        #expect(model.showsSteadyHint)
    }

    @Test func astroGivesItsOwnTripodAdviceAndLeavesNoHintBehind() async {
        let (model, _) = await makeModel()
        await record(Self.bright, in: model)
        await model.send(.astro(.setOn(true)))
        #expect(model.astro.isOn)
        // Manual's rule still sees the slow shutter; the camera leaves the advice to Astro.
        #expect(model.manual.showsSteadyHint)
        #expect(!model.showsSteadyHint)
        await record(Fixtures.reading(iso: 6400, duration: 1), in: model)
        #expect(!model.showsSteadyHint)
        await model.send(.astro(.setOn(false)))
        #expect(!model.manual.isEnabled)
        #expect(!model.showsSteadyHint)
        await record(Fixtures.reading(iso: 6400, duration: 1), in: model)
        #expect(!model.showsSteadyHint)
        #expect(model.manual.longestAutoShutter == Self.handheldLimit)
    }

    @Test func aSlowReadingFromTheOldLensDoesNotLiftTheNewLensLimit() async {
        let (model, _) = await makeModel(lenses: [Fixtures.handheld, Fixtures.ultraWide])
        // Very dark on the first lens: the limit is lifted and auto exposure slows to 1/4 s.
        await record(Self.dim, Self.slowManual, in: model)
        #expect(model.showsSteadyHint)
        await model.send(.selectLens(Fixtures.ultraWide.id))
        #expect(!model.showsSteadyHint)
        #expect(model.manual.longestAutoShutter == 1.0 / 26.0)
        await record(Self.slowManual, in: model)
        #expect(!model.showsSteadyHint)
        #expect(model.manual.longestAutoShutter == 1.0 / 26.0)
        // The new lens's own reading in the same dark scene shows it.
        await record(Fixtures.reading(iso: 3200, duration: 1.0 / 26.0, offset: -2), in: model)
        #expect(model.showsSteadyHint)
    }

    @Test func driveModesNeitherKeepNorDropTheHint() async {
        let (model, _) = await makeModel()
        await record(Self.dim, in: model)
        for mode in [DriveMode.timer(.threeSeconds), .burst, .interval, .single] {
            await model.send(.drive(.setMode(mode)))
            #expect(model.showsSteadyHint, "\(mode)")
        }
        await record(Self.dim, Fixtures.reading(iso: 100, duration: Self.handheldLimit), in: model)
        #expect(!model.showsSteadyHint)
        await model.send(.drive(.setMode(.burst)))
        #expect(!model.showsSteadyHint)
    }

    @Test func theHintDoesNotFlickerNearTheThreshold() async {
        let (model, _) = await makeModel()
        await record(Self.dim, in: model)
        #expect(model.showsSteadyHint)
        // A quarter stop brighter than the limit needs, then a little darker, and back: inside
        // the half-stop margin, so the limit stays lifted and the hint stays.
        let needed = 6400 * Self.handheldLimit
        let justBrighter = Fixtures.reading(iso: needed * pow(2, -0.25) / Self.handheldLimit, duration: Self.handheldLimit)
        let justDarker = Fixtures.reading(iso: 6400, duration: Self.handheldLimit, offset: -0.1)
        for reading in [justBrighter, justDarker, justBrighter, justDarker, justBrighter] {
            await record(reading, in: model)
            #expect(model.showsSteadyHint)
        }
        // More than half a stop brighter: the limit comes back, then stays near the threshold.
        let brighter = Fixtures.reading(iso: needed * pow(2, -0.75) / Self.handheldLimit, duration: Self.handheldLimit)
        let atTheLimit = Fixtures.reading(iso: 6400, duration: Self.handheldLimit)
        for reading in [brighter, atTheLimit, justBrighter, atTheLimit] {
            await record(reading, in: model)
            #expect(!model.showsSteadyHint)
        }
    }

    @Test func aReadingJustOverTheLimitStillCounts() async {
        // The camera reports its shutter rounded to the sensor; a little over the limit is current.
        let (model, _) = await makeModel()
        await record(Fixtures.reading(iso: 6400, duration: Self.handheldLimit * 1.05, offset: -2), in: model)
        #expect(model.showsSteadyHint)
    }

    @Test func aLockedExposureIsNeverTakenAsLeftOver() async {
        let (model, _) = await makeModel()
        await model.send(.auto(.lockFocusAndExposure(at: nil)))
        await record(Fixtures.reading(iso: 6400, duration: 1.0 / 4.0), in: model)
        #expect(model.manual.lastReading != nil)
        #expect(model.showsSteadyHint)
    }
}
