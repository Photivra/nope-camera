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
        #expect(!drive.isShutterHeld)
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

    @Test(arguments: [true, false])
    func theShutterStopsAnIntervalSeriesInBurstMode(onScreen: Bool) async {
        let backend = ScriptedManualBackend(lenses: [ManualFixtures.wide])
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        await model.send(.start)
        await model.send(.drive(.setMode(.burst)))
        #expect(model.isBurstShutter)
        // A series started by Siri or Shortcuts leaves the drive mode at Burst.
        await model.send(.manual(.setInterval(IntervalSettings(interval: 60, count: 3))))
        await model.send(.manual(.startInterval))
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        #expect(!model.isBurstShutter, "the on-screen shutter sends Capture while a series runs")
        // A running focus bracket does the same (CameraModelFocusBracketTests, fourth review S1).
        let phase: (ShutterPhase) -> CameraIntent = onScreen ? { .drive(.shutter($0)) } : { .drive(.hardwareButton($0)) }
        await model.send(phase(.pressed))
        #expect(model.manual.intervalProgress != nil, "the press stops the series when it comes up")
        await model.send(phase(.released))
        #expect(model.manual.intervalProgress == nil)
        #expect(model.drive.lastBurst == nil, "no burst was taken")
        #expect(await backend.captureCount == 1)
        #expect(model.isBurstShutter)
    }

    @Test func aHardwareButtonStartsAndStopsAnAstroRunInBurstMode() async {
        let backend = HookedManualBackend(ScriptedManualBackend(lenses: [AstroTests.wide]))
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), sleep: { _ in }, deviceStatusReader: FakeStatusReader(bytes: nil))
        await model.send(.start)
        await model.send(.astro(.setOn(true)))
        await model.send(.drive(.setMode(.burst)))
        await model.send(.astro(.setFrameCount(10)))
        #expect(!model.isBurstShutter)
        await backend.setOnCapture { count in
            guard count == 3 else { return }
            await model.send(.drive(.hardwareButton(.pressed)))
            await model.send(.drive(.hardwareButton(.released)))
        }
        await model.send(.drive(.hardwareButton(.pressed)))
        #expect(await backend.requests.isEmpty, "a hardware button acts when it comes up, as a tap does")
        await model.send(.drive(.hardwareButton(.released)))
        for _ in 0..<500 where model.astro.lastRun == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.astro.lastRun == BurstResult(end: .stopped, saved: 3))
        #expect(model.drive.lastBurst == nil, "no burst was taken")
    }

    // MARK: - One ordered path for press and release (issue #100)

    @Test func pressesAndReleasesAreNumberedBySource() {
        var holds = ShutterHolds()
        #expect(!holds.isAnyHeld)
        #expect(holds.press(nil, from: .onScreen) == .new(number: 1, isReleased: false))
        #expect(holds.isHeld(.onScreen) && !holds.isHeld(.hardware))
        // Each source counts its own presses.
        #expect(holds.press(nil, from: .hardware) == .new(number: 1, isReleased: false))
        #expect(holds.release(nil, from: .hardware) == .current)
        #expect(holds.isAnyHeld, "the on-screen shutter is still down")
        #expect(holds.press(1, from: .onScreen) == .stale, "a press is never counted twice")
        #expect(holds.release(1, from: .onScreen) == .current)
        #expect(!holds.isAnyHeld)
        // A release that comes before its press.
        #expect(holds.release(3, from: .onScreen) == .early)
        #expect(!holds.isAnyHeld)
        #expect(holds.press(3, from: .onScreen) == .new(number: 3, isReleased: true))
        #expect(!holds.isAnyHeld)
        #expect(holds.press(4, from: .onScreen) == .new(number: 4, isReleased: false))
        #expect(holds.release(3, from: .onScreen) == .stale, "an old release can't end a newer press")
        #expect(holds.isHeld(.onScreen))
        // Without numbers, a release ends the latest press, also one that already ended.
        #expect(holds.release(nil, from: .onScreen) == .current)
        #expect(holds.release(nil, from: .onScreen) == .current)
    }

    @Test func aReleaseDeliveredBeforeItsPressLeavesNoHold() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend: backend)
        #expect(model.shutter(.released, from: .onScreen, press: 1) == nil)
        await model.shutter(.pressed, from: .onScreen, press: 1)?.value
        #expect(!model.drive.isShutterHeld)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 1), "a tap: one photo")
        #expect(await backend.captureRequests.count == 1)
    }

    @Test func aPressAndReleaseBeforeTheFirstPhotoTakeOnePhoto() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend: backend)
        let actions = model.actionCount
        // Both arrive before the burst's task runs, as from one quick tap.
        let work = model.shutter(.pressed, from: .onScreen)
        #expect(model.drive.isShutterHeld)
        #expect(model.shutter(.released, from: .onScreen) == nil)
        #expect(!model.drive.isShutterHeld)
        await work?.value
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 1))
        #expect(await backend.captureRequests.count == 1)
        #expect(model.actionCount == actions + 2, "each event is the person's action")
    }

    @Test func aSecondPressBeforeTheBurstBeginsStartsNoSecondBurst() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend: backend)
        let work = model.shutter(.pressed, from: .onScreen)
        #expect(model.drive.isBurstPrepared)
        #expect(model.shutter(.pressed, from: .hardware) == nil)
        await model.send(.drive(.startBurst))
        model.shutter(.released, from: .hardware)
        model.shutter(.released, from: .onScreen)
        await work?.value
        #expect(!model.drive.isBurstPrepared)
        #expect(await backend.captureRequests.count == 1)
    }

    @Test func aStaleReleaseFromAnEarlierPressDoesNotStopANewHold() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        model.shutter(.released, from: .onScreen, press: 1)
        await model.shutter(.pressed, from: .onScreen, press: 1)?.value
        #expect(model.drive.lastBurst?.saved == 1)
        await hooked.setOnCapture { [model] count in
            // The first burst took photo 1; this one starts at photo 2.
            if count == 3 { await model.shutter(.released, from: .onScreen, press: 1) }
            if count == 5 { await model.shutter(.released, from: .onScreen, press: 2) }
        }
        await model.shutter(.pressed, from: .onScreen, press: 2)?.value
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 4))
    }

    @Test func anOnScreenHoldOutlastsAHardwarePressAndRelease() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            if count == 2 {
                let work = await model.shutter(.pressed, from: .hardware)
                #expect(work == nil, "the burst runs already")
                await model.shutter(.released, from: .hardware)
            }
            if count == 4 { await model.shutter(.released, from: .onScreen) }
        }
        await model.shutter(.pressed, from: .onScreen)?.value
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 4))
        #expect(model.drive.lastBurst?.start == .held)
    }

    @Test func aPressThatCannotBeginABurstLeavesNothingPrepared() async {
        let model = await makeModel()
        model.captureStatus = .saving
        await model.shutter(.pressed, from: .onScreen)?.value
        #expect(!model.drive.isBurstPrepared)
        #expect(model.drive.lastBurst == nil)
        model.shutter(.released, from: .onScreen)
        model.captureStatus = .idle
        let work = model.shutter(.pressed, from: .onScreen)
        model.shutter(.released, from: .onScreen)
        await work?.value
        #expect(model.drive.lastBurst?.saved == 1)
    }

    // MARK: - A held burst ends when its shutter goes away (issue #101)

    /// How a held burst loses its shutter.
    enum LostShutter: CaseIterable, Sendable {
        /// The shutter view went away, or stopped reporting, with the finger down: it sends
        /// `.cancelled` with the touch's number.
        case viewCancelled
        /// The app stopped being active.
        case appInactive
        /// The app went to the background.
        case appInBackground
    }

    @Test(arguments: LostShutter.allCases)
    func aHeldBurstStopsWhenItsShutterGoesAway(_ lost: LostShutter) async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 2 else { return }
            switch lost {
            case .viewCancelled: await model.shutter(.cancelled, from: .onScreen, press: 7)
            case .appInactive: await model.cancelShutterHolds()
            case .appInBackground: await model.send(.setInForeground(false))
            }
        }
        await model.shutter(.pressed, from: .onScreen, press: 7)?.value
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 2))
        #expect(!model.drive.isShutterHeld)
        // The next press starts a burst as usual, and its release ends it.
        await hooked.setOnCapture { [model] count in
            if count == 4 { await model.shutter(.released, from: .hardware) }
        }
        await model.send(.setInForeground(true))
        await model.shutter(.pressed, from: .hardware)?.value
        #expect(model.drive.lastBurst?.saved == 2)
    }

    @Test func endingTheHoldsLeavesABurstThatNeedsNoHolding() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            if count == 2 { await model.cancelShutterHolds() }
            if count == 3 { await model.send(.drive(.stopBurst)) }
        }
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 3))
    }

    @Test func holdsOfEverySourceEndTogether() {
        var holds = ShutterHolds()
        _ = holds.press(nil, from: .onScreen)
        _ = holds.press(5, from: .hardware)
        holds.releaseAll()
        #expect(!holds.isAnyHeld)
        #expect(holds.release(5, from: .hardware) == .current, "the late release is still its press's")
        #expect(holds.press(6, from: .hardware) == .new(number: 6, isReleased: false))
    }

    // MARK: - Burst Limit (issue #121)

    /// A model in burst mode with a Burst Limit.
    func limitedModel(
        _ limit: BurstLimit, backend: any CaptureBackend = ScriptedBackend(capabilities: CameraModelTests.oneLens),
        reader: (any DeviceStatusReading)? = nil
    ) async -> CameraModel {
        let model = await makeModel(backend: backend, reader: reader)
        await model.send(.drive(.setBurstLimit(limit)))
        #expect(model.drive.burstLimit == limit)
        return model
    }

    @Test func limitedValuesAndSummaries() {
        let progress = BurstProgress(taken: 3, saved: 2, start: .limited, limit: 10)
        #expect(progress.limit == 10)
        #expect(BurstProgress(taken: 1, saved: 0).limit == nil)
        #expect(BurstResult(end: .countReached, saved: 10, start: .limited, limit: 10).hasSummary, "10 of 10")
        #expect(BurstResult(end: .stopped, saved: 1, start: .limited, limit: 10).hasSummary, "1 of 10")
        #expect(!BurstResult(end: .stopped, saved: 0, start: .limited, limit: 10).hasSummary)
        #expect(!BurstResult(end: .storageFull, saved: 4, start: .limited, limit: 10).hasSummary, "storage has its sentence")
        #expect(!BurstResult(end: .failed, saved: 4, start: .limited, limit: 10).hasSummary)
        #expect(BurstResult(end: .stopped, saved: 3).limit == nil)
    }

    @Test(arguments: ShutterSource.allCases)
    func aTapWithALimitRunsToTheCount(_ source: ShutterSource) async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await limitedModel(.ten, backend: hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 1 else { return }
            let progress = await model.drive.burstProgress
            #expect(progress?.start == .limited && progress?.limit == 10)
        }
        let work = model.shutter(.pressed, from: source)
        model.shutter(.released, from: source)
        await work?.value
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .countReached, saved: 10))
        #expect(model.drive.lastBurst?.start == .limited)
        #expect(model.drive.lastBurst?.limit == 10)
        #expect(model.drive.lastBurst?.hasSummary == true)
        #expect(savedCount(model) == 10)
    }

    @Test func aHoldWithALimitRunsToTheCountAfterTheRelease() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await limitedModel(.five, backend: hooked)
        await hooked.setOnCapture { [model] count in
            if count == 2 { await model.shutter(.released, from: .onScreen) }
        }
        await model.shutter(.pressed, from: .onScreen)?.value
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .countReached, saved: 5))
    }

    /// What stops a limited burst early.
    enum SecondPress: CaseIterable, Sendable {
        case onScreen, hardware, assistiveTap, stopBurst
    }

    @Test(arguments: SecondPress.allCases)
    func aSecondPressStopsALimitedBurstAfterThePhotoBeingTaken(_ second: SecondPress) async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await limitedModel(.ten, backend: hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 4 else { return }
            switch second {
            case .onScreen:
                await model.shutter(.pressed, from: .onScreen)
                await model.shutter(.released, from: .onScreen)
            case .hardware:
                await model.shutter(.pressed, from: .hardware)
                await model.shutter(.released, from: .hardware)
            case .assistiveTap: await model.send(.capture)
            case .stopBurst: await model.send(.drive(.stopBurst))
            }
        }
        let work = model.shutter(.pressed, from: .hardware)
        model.shutter(.released, from: .hardware)
        await work?.value
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 4), "every photo taken is saved")
        #expect(model.drive.lastBurst?.limit == 10)
        #expect(model.drive.lastBurst?.hasSummary == true, "4 of 10")
    }

    @Test func aPressBeforeTheLimitedBurstBeginsStopsIt() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await limitedModel(.three, backend: backend)
        let work = model.shutter(.pressed, from: .onScreen)
        model.shutter(.released, from: .onScreen)
        #expect(model.shutter(.pressed, from: .hardware) == nil)
        await work?.value
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 0))
        #expect(await backend.captureRequests.isEmpty)
    }

    @Test func assistiveActivationAndStartBurstTakeTheCount() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await limitedModel(.three, backend: backend)
        await model.send(.capture)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .countReached, saved: 3))
        #expect(model.drive.lastBurst?.start == .limited)
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .countReached, saved: 3))
        #expect(await backend.captureRequests.count == 6)
    }

    @Test func withTheLimitOffATapTakesOnePhotoAsBefore() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await limitedModel(.off, backend: backend)
        let work = model.shutter(.pressed, from: .onScreen)
        model.shutter(.released, from: .onScreen)
        await work?.value
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 1))
        #expect(model.drive.lastBurst?.start == .held && model.drive.lastBurst?.limit == nil)
        await model.send(.capture)
        #expect(model.drive.lastBurst?.start == .counted)
        #expect(await backend.captureRequests.count == 2)
    }

    @Test func aLimitOfFiftyEndsByItsCountNotTheCap() async {
        let model = await limitedModel(.fifty)
        await model.send(.capture)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .countReached, saved: 50))
        #expect(model.drive.lastBurst?.limit == 50)
        #expect(model.drive.lastBurst?.hasSummary == true)
    }

    @Test func aLimitAboveWhatStorageAllowsStopsForStorage() async {
        let reader = FakeStatusReader(bytes: 0)
        let model = await limitedModel(.twenty, reader: reader)
        let perPhoto = PhotoSizeEstimate.bytes(for: Self.wide, settings: model.saveSettings)
        reader.bytes = perPhoto * 3
        reader.shrinkPerRead = perPhoto / 2
        await model.send(.capture)
        #expect(model.drive.lastBurst?.end == .storageFull)
        #expect(model.drive.lastBurst?.limit == 20)
        #expect((model.drive.lastBurst?.saved ?? 0) > 0)
    }

    @Test func aRunningBurstKeepsItsCountWhenTheLimitChanges() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await limitedModel(.five, backend: hooked)
        await hooked.setOnCapture { [model] count in
            // A preset or Settings changes the limit while Burst is selected.
            if count == 2 { await model.send(.drive(.setBurstLimit(.three))) }
        }
        await model.send(.capture)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .countReached, saved: 5))
        await model.send(.capture)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .countReached, saved: 3))
    }

    @Test func aPressWithALimitCancelsATimerFromElsewhere() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), sleep: { _ in await ticker.sleep() })
        await model.send(.start)
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.setBurstLimit(.ten)))
        await model.send(.drive(.startTimer(seconds: 3)))
        #expect(model.shutter(.pressed, from: .hardware) == nil)
        #expect(!model.drive.countdown.isRunning)
        model.shutter(.released, from: .hardware)
        #expect(model.drive.lastBurst == nil)
        #expect(await backend.captureRequests.isEmpty)
        await tick(ticker)
    }

    @Test func siriAndShortcutsKeepTheirOwnCount() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await limitedModel(.ten, backend: backend)
        await model.takeBurst(frames: 3)
        #expect(model.drive.lastBurst?.start == .counted)
        #expect(model.drive.lastBurst?.limit == nil)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .countReached, saved: 3))
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

    @Test func aRefusedPressRecordsNoRateOnTheLensSelectedNow() async {
        let clock = ManualClock()
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.twoLenses))
        let model = await makeModel(backend: hooked, clock: clock)
        await hooked.setOnCapture { [model] count in
            clock.advance(by: .milliseconds(500))
            if count == 4 { await model.send(.drive(.stopBurst)) }
        }
        // Two a second on the wide lens: Slow is not offered there.
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst?.rate == 2)
        #expect(model.drive.measuredFastRates == ["wide": 2])
        await model.send(.selectLens("tele"))
        #expect(model.burstSpeeds == [.fast, .slow])
        // A press that can't begin a burst, such as while a photo is still saving.
        model.captureStatus = .saving
        await model.send(.drive(.shutter(.pressed)))
        await model.send(.drive(.shutter(.released)))
        #expect(model.drive.measuredFastRates == ["wide": 2], "the old burst's rate isn't recorded for this lens")
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
