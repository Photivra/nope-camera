import Foundation
import Testing

@testable import NopeCore

/// A clock that moves only when told: by a sleep, or by a photo taking its time.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now
    private var sleeps: [Double] = []

    /// The time now.
    func now() -> ContinuousClock.Instant {
        lock.withLock { instant }
    }

    /// Moves the clock on.
    func advance(by duration: Duration) {
        lock.withLock { instant += duration }
    }

    /// A sleep that moves the clock on by its seconds and records them.
    func sleep(_ seconds: Double) {
        lock.withLock {
            sleeps.append(seconds)
            instant += .seconds(seconds)
        }
    }

    /// The sleeps so far, in seconds.
    var recordedSleeps: [Double] {
        lock.withLock { sleeps }
    }
}

/// A library that holds the add with this number (1-based) until ``release()``.
actor GatedLibrary: PhotoLibrary {
    let gatedAdd: Int
    private(set) var adds = 0
    private var waiting: CheckedContinuation<Void, Never>?
    private var isReleased = false

    init(gatedAdd: Int) {
        self.gatedAdd = gatedAdd
    }

    func add(_ assets: [PhotoLibraryAsset]) async throws(CaptureError) {
        adds += 1
        guard adds == gatedAdd, !isReleased else { return }
        await withCheckedContinuation { waiting = $0 }
    }

    /// Whether the gated add is waiting.
    var isHolding: Bool { waiting != nil }

    /// Lets the gated add finish.
    func release() {
        isReleased = true
        waiting?.resume()
        waiting = nil
    }
}

/// Burst as continuous shooting (docs/design/BURST.md): a tap takes one photo, holding the
/// shutter takes photos until it comes up, Start Burst, the Fast and Slow speeds, the measured
/// rate, and the saving state.
@MainActor
struct BurstTests {
    static let wide = CameraModelTests.wideRAW

    func makeModel(
        backend: any CaptureBackend = ScriptedBackend(capabilities: CameraModelTests.oneLens),
        saver: PhotoSaver? = CameraModelTests.saver(),
        clock: ManualClock = ManualClock(),
        reader: (any DeviceStatusReading)? = nil
    ) async -> CameraModel {
        let model = CameraModel(
            backend: backend, saver: saver, sleep: { clock.sleep($0) }, now: { clock.now() }, deviceStatusReader: reader)
        await model.send(.start)
        await model.send(.drive(.setMode(.burst)))
        return model
    }

    func savedCount(_ model: CameraModel) -> Int? {
        guard case .savedBurst(let photos) = model.captureStatus else { return nil }
        return photos.count
    }

    // MARK: - Values

    @Test func speedsAndStarts() {
        #expect(BurstSpeed.allCases == [.fast, .slow])
        #expect(BurstSpeed.fast.minimumFrameInterval == nil)
        #expect(BurstSpeed.slow.minimumFrameInterval == .milliseconds(500))
        #expect(BurstSpeed.fast.maximumPhotosPerSecond == nil)
        #expect(BurstSpeed.slow.maximumPhotosPerSecond == 2)
        let progress = BurstProgress(taken: 2, saved: 1)
        #expect(progress.start == .started && progress.rate == nil && !progress.isSaving)
        let result = BurstResult(end: .stopped, saved: 3)
        #expect(result.taken == 3 && result.start == .started && result.duration == .zero && result.rate == nil)
    }

    @Test func aSummaryIsForABurstOfTwoOrMoreThePersonEnded() {
        #expect(BurstResult(end: .stopped, saved: 2, start: .held).hasSummary)
        #expect(BurstResult(end: .stopped, saved: 12, start: .started).hasSummary)
        #expect(!BurstResult(end: .stopped, saved: 1, start: .held).hasSummary, "one photo is a photo")
        #expect(!BurstResult(end: .stopped, saved: 3, start: .counted).hasSummary, "Siri reports a count")
        #expect(!BurstResult(end: .failed, saved: 3, start: .held).hasSummary)
        #expect(!BurstResult(end: .limitReached, saved: 50, start: .held).hasSummary, "the limit has its own sentence")
    }

    @Test func theRateUsesTheLastFivePhotos() {
        let clock = ManualClock()
        let drive = DriveModel(sleep: { _ in }, now: { clock.now() })
        #expect(DriveModel.rateWindow == 5)
        drive.recordTaken()
        #expect(drive.burstProgress == nil, "nothing is counted outside a burst")
        drive.prepareBurst(start: .held)
        drive.beginBurst()
        // Two photos a second for five photos, then four a second.
        for gap in [0.0, 0.5, 0.5, 0.5, 0.5, 0.25, 0.25, 0.25, 0.25] {
            clock.advance(by: .seconds(gap))
            drive.recordTaken()
        }
        #expect(drive.burstProgress?.rate == 4)
        #expect(drive.burstProgress?.start == .held)
        drive.endBurst(.stopped)
        // Eight gaps over three seconds.
        #expect(drive.lastBurst?.taken == 9)
        #expect(drive.lastBurst?.duration == .seconds(3))
        #expect(drive.lastBurst?.rate == 8.0 / 3.0)
        #expect(drive.lastBurst?.start == .held)
    }

    @Test func theRateIsNilBeforeThreePhotos() {
        let clock = ManualClock()
        let drive = DriveModel(sleep: { _ in }, now: { clock.now() })
        drive.prepareBurst(start: .started)
        drive.beginBurst()
        drive.recordTaken()
        #expect(drive.burstProgress?.rate == nil)
        clock.advance(by: .seconds(1))
        drive.recordTaken()
        #expect(drive.burstProgress?.rate == nil)
        clock.advance(by: .seconds(1))
        drive.recordTaken()
        #expect(drive.burstProgress?.rate == 1)
        drive.endBurst(.stopped)
        #expect(drive.lastBurst?.duration == .seconds(2))
        #expect(drive.lastBurst?.rate == 1)
        // Photos with no time between them give no rate.
        #expect(DriveModel.rate(photos: 3, first: clock.now(), last: clock.now()) == nil)
        #expect(DriveModel.rate(photos: 3, first: nil, last: clock.now()) == nil)
    }

    @Test func aHeldBurstWhoseShutterCameUpEarlyTakesOnePhoto() {
        let drive = DriveModel(sleep: { _ in })
        #expect(!drive.isBurstStopRequested, "nothing runs")
        drive.setShutterHeld(false)
        drive.prepareBurst(start: .held)
        drive.beginBurst()
        #expect(!drive.isBurstStopRequested, "the first photo is always taken")
        drive.recordTaken()
        #expect(drive.isBurstStopRequested)
        drive.endBurst(.stopped)
        // A started burst doesn't depend on a held shutter.
        drive.prepareBurst(start: .started)
        drive.beginBurst()
        drive.recordTaken()
        #expect(!drive.isBurstStopRequested)
    }

    // MARK: - The shutter in burst mode

    @Test func captureInBurstTakesOnePhoto() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend: backend)
        await model.send(.capture)
        #expect(await backend.captureRequests.count == 1)
        #expect(model.drive.lastBurst?.end == .countReached)
        #expect(model.drive.lastBurst?.start == .counted)
        #expect(model.drive.lastBurst?.hasSummary == false)
        #expect(savedCount(model) == 1)
    }

    @Test func shutterPhasesRunABurstWhileHeld() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            if count == 1 {
                // The first photo is requested on touch down, with the shutter held.
                #expect(await model.drive.burstProgress?.start == .held)
                #expect(await model.drive.isShutterHeld)
            }
            guard count == 3 else { return }
            await model.send(.drive(.shutter(.released)))
        }
        await model.send(.drive(.shutter(.pressed)))
        #expect(savedCount(model) == 3)
        #expect(model.drive.lastBurst?.end == .stopped)
        #expect(model.drive.lastBurst?.start == .held)
        #expect(model.drive.lastBurst?.hasSummary == true)
        #expect(model.drive.burstProgress == nil)
    }

    @Test func shutterReleaseBeforeTheSecondFrameSavesOne() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let hooked = HookedBackend(backend)
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 1 else { return }
            await model.send(.drive(.shutter(.released)))
        }
        await model.send(.drive(.shutter(.pressed)))
        #expect(await backend.captureRequests.count == 1)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 1))
        #expect(model.drive.lastBurst?.hasSummary == false)
    }

    @Test func cancelledShutterStopsTheBurst() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 2 else { return }
            // A second touch while the burst runs is ignored; sliding off ends it.
            await model.send(.drive(.shutter(.pressed)))
            await model.send(.drive(.shutter(.cancelled)))
        }
        await model.send(.drive(.shutter(.pressed)))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 2))
    }

    @Test func shutterPhasesAreIgnoredOutsideBurstAndWithAstro() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend: backend)
        await model.send(.drive(.setMode(.single)))
        await model.send(.drive(.shutter(.pressed)))
        await model.send(.drive(.shutter(.released)))
        #expect(await backend.captureRequests.isEmpty, "outside burst the shutter sends capture instead")

        let manual = ScriptedManualBackend(lenses: [AstroTests.wide])
        let astroModel = await makeModel(backend: manual, reader: FakeStatusReader(bytes: nil))
        await astroModel.send(.astro(.setOn(true)))
        await astroModel.send(.drive(.setMode(.burst)))
        #expect(astroModel.astro.isOn && astroModel.drive.mode == .burst)
        await astroModel.send(.drive(.shutter(.pressed)))
        await astroModel.send(.drive(.startBurst))
        #expect(astroModel.drive.lastBurst == nil, "the astro helper has its own shutter")
        #expect(await manual.captureCount == 0)
    }

    @Test func hardwareButtonsAreUnchanged() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let hooked = HookedBackend(backend)
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 2 else { return }
            await model.send(.drive(.hardwareButton(.released)))
        }
        await model.send(.drive(.hardwareButton(.pressed)))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 2))
        #expect(model.drive.lastBurst?.start == .held)
        // Outside burst a hardware button takes a photo when it comes up, as before.
        await model.send(.drive(.setMode(.single)))
        await model.send(.drive(.hardwareButton(.pressed)))
        #expect(await backend.captureRequests.count == 2)
        await model.send(.drive(.hardwareButton(.released)))
        #expect(await backend.captureRequests.count == 3)
    }

    // MARK: - Start Burst

    @Test(arguments: [
        CameraIntent.capture, .drive(.stopBurst), .drive(.hardwareButton(.released)), .drive(.shutter(.released)),
    ])
    func startBurstRunsUntilStopped(stop: CameraIntent) async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 4 else { return }
            #expect(await model.drive.burstProgress?.start == .started)
            await model.send(stop)
        }
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 4))
        #expect(model.drive.lastBurst?.start == .started)
    }

    @Test func startBurstIsIgnoredOutsideBurstAndWhileBusy() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let hooked = HookedBackend(backend)
        let model = await makeModel(backend: hooked)
        await model.send(.drive(.setMode(.single)))
        await model.send(.drive(.startBurst))
        #expect(await backend.captureRequests.isEmpty)
        await model.send(.drive(.setMode(.burst)))
        await hooked.setOnCapture { [model] count in
            guard count == 1 else { return }
            await model.send(.drive(.startBurst))
            await model.send(.drive(.stopBurst))
        }
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 1))
        // The camera isn't running.
        let stopped = CameraModel(backend: ScriptedBackend(capabilities: CameraModelTests.oneLens), saver: CameraModelTests.saver())
        await stopped.send(.drive(.setMode(.burst)))
        await stopped.send(.drive(.startBurst))
        #expect(stopped.drive.lastBurst == nil)
    }

    @Test func burstStopsAtFiftyPhotos() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend: backend)
        await model.send(.drive(.startBurst))
        #expect(DriveModel.maximumBurstFrames == 50)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .limitReached, saved: 50))
        #expect(await backend.captureRequests.count == 50)
    }

    @Test func aHeldBurstStopsForStorage() async {
        let reader = FakeStatusReader(bytes: 0)
        let model = await makeModel(reader: reader)
        let perPhoto = PhotoSizeEstimate.bytes(for: Self.wide, settings: model.saveSettings)
        reader.bytes = perPhoto * 3
        reader.shrinkPerRead = perPhoto / 2
        await model.send(.drive(.shutter(.pressed)))
        #expect(model.drive.lastBurst?.end == .storageFull)
        #expect((model.drive.lastBurst?.saved ?? 0) > 0)
        #expect(savedCount(model) == model.drive.lastBurst?.saved)
    }

    // MARK: - Speed

    @Test func burstSpeedDefaultsToFastAndIsNotStored() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        #expect(model.drive.burstSpeed == .fast)
        #expect(model.burstSpeed == .fast)
        await model.send(.drive(.setBurstSpeed(.slow)))
        #expect(model.burstSpeed == .slow)
        await hooked.setOnCapture { [model] count in
            guard count == 1 else { return }
            await model.send(.drive(.setBurstSpeed(.fast)))
            #expect(await model.drive.burstSpeed == .slow, "the speed doesn't change while a burst runs")
            await model.send(.drive(.stopBurst))
        }
        await model.send(.drive(.startBurst))
        // A new model, as at the next launch, starts at Fast.
        let next = await makeModel()
        #expect(next.burstSpeed == .fast)
    }

    @Test func slowBurstSpacesFrameStarts() async {
        let clock = ManualClock()
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked, clock: clock)
        let starts = Starts()
        await hooked.setOnCapture { [model] count in
            await starts.append(clock.now())
            // Each photo takes a tenth of a second.
            clock.advance(by: .milliseconds(100))
            if count == 4 { await model.send(.drive(.shutter(.released))) }
        }
        await model.send(.drive(.setBurstSpeed(.slow)))
        await model.send(.drive(.shutter(.pressed)))
        let times = await starts.times
        #expect(times.count == 4)
        for (earlier, later) in zip(times, times.dropFirst()) {
            #expect(later - earlier >= .milliseconds(500))
        }
        #expect(clock.recordedSleeps.count == 3)
        #expect(model.drive.lastBurst?.saved == 4)
    }

    @Test func aStopDuringTheSlowWaitTakesNoFurtherPhoto() async {
        let clock = ManualClock()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let box = ModelBox()
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(),
            sleep: { seconds in
                clock.sleep(seconds)
                await box.model?.send(.drive(.stopBurst))
            }, now: { clock.now() })
        box.model = model
        await model.send(.start)
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.setBurstSpeed(.slow)))
        await model.send(.drive(.startBurst))
        #expect(await backend.captureRequests.count == 1)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 1))
    }

    @Test func slowWaitsNotWhenTheCameraIsSlowerThanHalfASecond() async {
        let clock = ManualClock()
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked, clock: clock)
        await hooked.setOnCapture { [model] count in
            clock.advance(by: .milliseconds(600))
            if count == 3 { await model.send(.drive(.stopBurst)) }
        }
        await model.send(.drive(.setBurstSpeed(.slow)))
        await model.send(.drive(.startBurst))
        #expect(clock.recordedSleeps.isEmpty)
        #expect(model.drive.lastBurst?.saved == 3)
    }

    @Test func countedBurstIgnoresSlow() async {
        let clock = ManualClock()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend: backend, clock: clock)
        await model.send(.drive(.setBurstSpeed(.slow)))
        await model.takeBurst(frames: 3)
        #expect(await backend.captureRequests.count == 3)
        #expect(clock.recordedSleeps.isEmpty, "a Siri count runs at Fast")
        #expect(model.drive.lastBurst?.start == .counted)
        #expect(model.drive.lastBurst?.end == .countReached)
    }

    @Test func slowIsHiddenOnALensWhereFastMeasuresUnderThreeASecond() async {
        let clock = ManualClock()
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked, clock: clock)
        #expect(model.burstSpeeds == [.fast, .slow], "offered until a measurement says otherwise")
        #expect(model.drive.offersSlowBurst(on: nil))
        await model.send(.drive(.setBurstSpeed(.slow)))
        // A Fast burst can't be taken while Slow is chosen; choose Fast, measure, choose Slow.
        await model.send(.drive(.setBurstSpeed(.fast)))
        let gap = Gap()
        await hooked.setOnCapture { [model] count in
            clock.advance(by: await gap.duration)
            if count == 4 { await model.send(.drive(.stopBurst)) }
        }
        // Half a second a photo: 2 a second.
        await gap.set(.milliseconds(500))
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst?.rate == 2)
        #expect(model.burstSpeeds == [.fast])
        await model.send(.drive(.setBurstSpeed(.slow)))
        #expect(model.drive.burstSpeed == .slow)
        #expect(model.burstSpeed == .fast, "Slow isn't offered on this lens, so a burst runs at Fast")
        // A quicker measurement offers it again.
        await model.send(.drive(.setBurstSpeed(.fast)))
        await gap.set(.milliseconds(250))
        await hooked.setOnCapture { [model] count in
            clock.advance(by: await gap.duration)
            if count == 8 { await model.send(.drive(.stopBurst)) }
        }
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst?.rate == 4)
        #expect(model.burstSpeeds == [.fast, .slow])
        // A Slow burst measures nothing for the lens.
        await model.send(.drive(.setBurstSpeed(.slow)))
        await gap.set(.seconds(1))
        await hooked.setOnCapture { [model] count in
            clock.advance(by: await gap.duration)
            if count == 4 { await model.send(.drive(.stopBurst)) }
        }
        await model.send(.drive(.startBurst))
        #expect(model.burstSpeeds == [.fast, .slow])
    }

    // MARK: - Saving

    @Test func burstIsSavingAfterItsLastPhotoUntilAllAreSaved() async {
        let library = GatedLibrary(gatedAdd: 3)
        let saver = PhotoSaver(developer: FakeDeveloper(), signer: nil, reader: BytesReader(), library: library, appVersion: "1.0.0")
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let hooked = HookedBackend(backend)
        let model = await makeModel(backend: hooked, saver: saver)
        await hooked.setOnCapture { [model] count in
            guard count == 3 else { return }
            await model.send(.drive(.shutter(.released)))
        }
        let burst = Task { await model.send(.drive(.shutter(.pressed))) }
        await waitUntil { model.drive.burstProgress?.isSaving == true }
        #expect(model.drive.burstProgress?.taken == 3)
        #expect(model.drive.burstProgress?.saved == 2)
        #expect(!model.canPressShutter, "the shutter is dimmed while the last photos are saved")
        // No new burst while the last one saves: neither a press, Start Burst nor a tap.
        await model.send(.drive(.shutter(.pressed)))
        await model.send(.drive(.startBurst))
        await model.send(.capture)
        await model.send(.drive(.shutter(.released)))
        #expect(await backend.captureRequests.count == 3)
        await library.release()
        await burst.value
        #expect(model.drive.burstProgress == nil)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 3))
        #expect(model.drive.lastBurst?.hasSummary == true)
        #expect(model.canPressShutter)
    }

    @Test func aFailedLastSaveKeepsTheEarlierPhotos() async {
        let library = FailingLibrary(failingAdd: 3)
        let saver = PhotoSaver(developer: FakeDeveloper(), signer: nil, reader: BytesReader(), library: library, appVersion: "1.0.0")
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked, saver: saver)
        await hooked.setOnCapture { [model] count in
            guard count == 3 else { return }
            await model.send(.drive(.shutter(.released)))
        }
        await model.send(.drive(.shutter(.pressed)))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .failed, saved: 2))
        #expect(model.captureStatus == .failed(.saveFailed))
    }

    // MARK: - The simulated camera

    @Test func theSimulatedCameraCanTakeItsTime() async throws {
        let backend = SimulatedCaptureBackend(permission: .authorized, captureSeconds: 0.01)
        #expect(backend.captureSeconds == 0.01)
        let start = ContinuousClock.now
        _ = try await backend.capturePhoto(CaptureRequest(lens: Self.wide))
        #expect(ContinuousClock.now - start >= .milliseconds(10))
        #expect(SimulatedCaptureBackend(permission: .authorized).captureSeconds == 0)
    }
}

/// The times photos started, in order.
actor Starts {
    private(set) var times: [ContinuousClock.Instant] = []

    func append(_ time: ContinuousClock.Instant) {
        times.append(time)
    }
}

/// How long each simulated photo takes, changed between bursts.
actor Gap {
    private(set) var duration: Duration = .zero

    func set(_ duration: Duration) {
        self.duration = duration
    }
}

/// Holds a model a sleep closure created before it can reach.
@MainActor
final class ModelBox: Sendable {
    nonisolated(unsafe) var model: CameraModel?
}
