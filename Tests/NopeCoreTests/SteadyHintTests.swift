import Foundation
import Testing

@testable import NopeCore

/// "Hold it steady or use a tripod." (docs/design/device-feedback-1.0.md, section 4): never with
/// Manual Controls on; in full auto only while the shutter in use is slower than the lens's
/// steady limit, which counts its stabilization, with half a stop of margin. It follows only
/// readings taken in the current mode and lens, so it doesn't stay on after Manual, Astro or a
/// lens change.
@MainActor
struct SteadyHintTests {
    typealias Fixtures = AutoFixtures

    /// The handheld lens's limit: 1/(2 × 24 mm). It reports no stabilization, so this is also
    /// its steady limit.
    static let handheldLimit = 1.0 / 48.0

    /// Dark enough at the handheld limit and the highest ISO to lift it: two stops under. Its
    /// shutter is the limit itself, so it doesn't show the hint.
    static let dim = Fixtures.reading(iso: 6400, duration: handheldLimit, offset: -2)

    /// What the camera uses once the limit is lifted in that scene: twice as long as the limit.
    static let dimSlow = Fixtures.reading(iso: 6400, duration: 2 * handheldLimit)

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

    /// A reading in a scene dark enough to keep the limit lifted, with a shutter.
    ///
    /// - Parameter duration: The shutter in seconds.
    static func dark(_ duration: Double) -> ExposureReading {
        Fixtures.reading(iso: 6400, duration: duration, offset: -2)
    }

    @Test func fullAutoShowsItOnlyForAShutterSlowerThanTheLimit() async {
        let (model, _) = await makeModel()
        // The limit is lifted, but the camera's shutter is still the limit: no hint.
        await record(Self.dim, in: model)
        #expect(model.manual.longestAutoShutter == nil)
        #expect(!model.showsSteadyHint)
        // Just faster than the limit: no hint; just slower: the hint.
        await record(Self.dark(Self.handheldLimit * 0.99), in: model)
        #expect(!model.showsSteadyHint)
        await record(Self.dark(Self.handheldLimit * 1.01), in: model)
        #expect(model.showsSteadyHint)
    }

    @Test func aStabilizedLensHoldsTwoStopsSlower() async {
        let stabilized = Fixtures.lens(focalLength: 24, stabilized: true)
        let (model, _) = await makeModel(lenses: [stabilized])
        // The limit lifts at 1/48 s; at 1/24 s the stabilized lens's steady limit (1/12 s) isn't
        // passed.
        await record(Self.dim, Self.dimSlow, in: model)
        #expect(model.manual.longestAutoShutter == nil)
        #expect(!model.showsSteadyHint)
        await record(Self.dark(1.0 / 8.0), in: model)
        #expect(model.showsSteadyHint)
    }

    @Test func aLensWithoutAFocalLengthHasNoHint() async {
        // No handheld rule, so no limit to lift and no steady limit.
        let (model, _) = await makeModel(lenses: [Fixtures.wide])
        await record(Self.slowManual, in: model)
        #expect(model.manual.longestAutoShutter == nil)
        #expect(!model.showsSteadyHint)
    }

    @Test func theHintDoesNotFlickerNearTheLimit() async {
        let (model, _) = await makeModel()
        await record(Self.dim, Self.dark(Self.handheldLimit * 1.01), in: model)
        #expect(model.showsSteadyHint)
        // Faster than the limit but less than half a stop: it stays.
        for duration in [0.9, 0.75, 1.0, 0.72] {
            await record(Self.dark(Self.handheldLimit * duration), in: model)
            #expect(model.showsSteadyHint, "\(duration)")
        }
        // Half a stop faster: it goes, and stays away until the shutter is slower than the limit.
        for duration in [0.7, 0.9, 1.0] {
            await record(Self.dark(Self.handheldLimit * duration), in: model)
            #expect(!model.showsSteadyHint, "\(duration)")
        }
        await record(Self.dark(Self.handheldLimit * 1.01), in: model)
        #expect(model.showsSteadyHint)
    }

    @Test func manualControlsNeverShowIt() async {
        let (model, _) = await makeModel()
        await record(Self.dim, Self.dimSlow, in: model)
        #expect(model.showsSteadyHint)
        await model.send(.manual(.setEnabled(true)))
        #expect(!model.showsSteadyHint)
        // Shutter on Auto with a slow reading, and a set shutter of 1 s.
        await record(Fixtures.reading(iso: 6400, duration: 1.0 / 4.0), in: model)
        #expect(!model.showsSteadyHint)
        await model.send(.manual(.setValue(.shutter, 1)))
        #expect(model.manual.settings.shutter == 1)
        #expect(!model.showsSteadyHint)
        await record(Fixtures.reading(iso: 6400, duration: 1), in: model)
        #expect(!model.showsSteadyHint)
    }

    @Test func leavingManualStartsAgainFromTheHandheldLimit() async {
        let (model, backend) = await makeModel()
        await record(Self.dim, Self.dimSlow, in: model)
        #expect(model.manual.longestAutoShutter == nil)
        #expect(model.showsSteadyHint)
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setValue(.shutter, 1.0 / 4.0)))
        #expect(!model.showsSteadyHint)
        await model.send(.manual(.setEnabled(false)))
        // Full auto starts again from its first limit, as on a new lens; the lifted limit and the
        // reading from before Manual are gone.
        #expect(model.manual.longestAutoShutter == Self.handheldLimit)
        #expect(model.manual.lastReading == nil)
        #expect(!model.showsSteadyHint)
        #expect(await backend.applied.last?.longestAutoExposure == Self.handheldLimit)
        // Fresh readings in the same dark scene show it again.
        await record(Self.dim, Self.dimSlow, in: model)
        #expect(model.showsSteadyHint)
    }

    @Test func aSlowReadingLeftOverFromManualChangesNothing() async {
        let (model, _) = await makeModel()
        await record(Self.bright, in: model)
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setValue(.shutter, 1.0 / 4.0)))
        await record(Self.slowManual, in: model)
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

    @Test func astroGivesItsOwnTripodAdviceAndLeavesNoHintBehind() async {
        let (model, _) = await makeModel()
        await record(Self.dim, Self.dimSlow, in: model)
        #expect(model.showsSteadyHint)
        await model.send(.astro(.setOn(true)))
        #expect(model.astro.isOn)
        #expect(!model.showsSteadyHint)
        await record(Fixtures.reading(iso: 6400, duration: 1), in: model)
        #expect(!model.showsSteadyHint)
        await model.send(.astro(.setOn(false)))
        #expect(!model.manual.isEnabled)
        #expect(!model.showsSteadyHint)
        // Astro's long frames, still reported for a moment: from before, so nothing.
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
        // The new lens's own readings in the same dark scene: lifted at its limit, then slower.
        await record(Fixtures.reading(iso: 3200, duration: 1.0 / 26.0, offset: -2), in: model)
        #expect(model.manual.longestAutoShutter == nil)
        #expect(!model.showsSteadyHint)
        await record(Fixtures.reading(iso: 3200, duration: 1.0 / 13.0), in: model)
        #expect(model.showsSteadyHint)
    }

    @Test func driveModesNeitherKeepNorDropTheHint() async {
        let (model, _) = await makeModel()
        await record(Self.dim, Self.dimSlow, in: model)
        for mode in [DriveMode.timer(.threeSeconds), .burst, .interval, .single] {
            await model.send(.drive(.setMode(mode)))
            #expect(model.showsSteadyHint, "\(mode)")
        }
        // The light comes back: so does the limit, and the hint goes.
        await record(Fixtures.reading(iso: 100, duration: Self.handheldLimit), in: model)
        #expect(model.manual.longestAutoShutter == Self.handheldLimit)
        #expect(!model.showsSteadyHint)
        await model.send(.drive(.setMode(.burst)))
        #expect(!model.showsSteadyHint)
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
