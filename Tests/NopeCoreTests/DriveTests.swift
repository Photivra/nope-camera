import Foundation
import Testing

@testable import NopeCore

/// A sleep that waits until the test lets it go, so a test can see each countdown tick.
actor Ticker {
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Waits until ``tick()``.
    func sleep() async {
        await withCheckedContinuation { waiting.append($0) }
    }

    /// The number of sleeps waiting.
    var pending: Int { waiting.count }

    /// Lets the oldest sleep return.
    func tick() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }
}

/// A backend that wraps ``ScriptedBackend`` and runs a hook before each photo, so a test can act
/// in the middle of a burst.
actor HookedBackend: CaptureBackend {
    nonisolated let inner: ScriptedBackend
    nonisolated var events: AsyncStream<CaptureEvent> { inner.events }
    nonisolated var previewSource: (any CameraPreviewSource)? { nil }
    private var onCapture: (@Sendable (Int) async -> Void)?
    private(set) var captures = 0

    init(_ inner: ScriptedBackend) {
        self.inner = inner
    }

    func setOnCapture(_ hook: @escaping @Sendable (Int) async -> Void) {
        onCapture = hook
    }

    func currentPermission() async -> CameraPermission { await inner.currentPermission() }
    func requestPermission() async -> CameraPermission { await inner.requestPermission() }
    func deviceCapabilities() async -> DeviceCapabilities { await inner.deviceCapabilities() }
    func startSession(_ request: CaptureRequest) async throws(CaptureError) { try await inner.startSession(request) }
    func stopSession() async { await inner.stopSession() }

    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        captures += 1
        await onCapture?(captures)
        return try await inner.capturePhoto(request)
    }
}

/// A library that refuses the add with this number (1-based) and accepts the others.
actor FailingLibrary: PhotoLibrary {
    let failingAdd: Int
    private(set) var adds = 0

    init(failingAdd: Int) {
        self.failingAdd = failingAdd
    }

    func add(_ assets: [PhotoLibraryAsset]) async throws(CaptureError) {
        adds += 1
        if adds == failingAdd { throw .saveFailed }
    }
}

/// Fixed storage and battery values; the storage can shrink with each read.
@MainActor
final class FakeStatusReader: DeviceStatusReading {
    var bytes: Int64?
    var shrinkPerRead: Int64 = 0
    var batteryReading: BatteryReading?

    init(bytes: Int64?, battery: BatteryReading? = nil) {
        self.bytes = bytes
        batteryReading = battery
    }

    func availableStorageBytes() -> Int64? {
        defer { bytes = bytes.map { $0 - shrinkPerRead } }
        return bytes
    }

    func battery() -> BatteryReading? { batteryReading }
}

/// A screen that records its brightness and idle timer.
@MainActor
final class FakeScreen: ScreenControlling {
    var brightness: Double
    var isIdleTimerDisabled = false

    init(brightness: Double) {
        self.brightness = brightness
    }
}

/// Waits, yielding, until the condition holds: at most 10,000 yields, then on the clock for up
/// to five seconds more, so a busy test runner doesn't end the wait too early.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() {
        await Task.yield()
    }
    for _ in 0..<500 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Lets other tasks run for a moment.
func settle() async {
    for _ in 0..<200 { await Task.yield() }
}

/// Waits until a sleep is waiting on the ticker (at least `count`), then lets the oldest go. It
/// yields first, then waits on the clock for up to five seconds, so a busy test runner can't
/// make it tick before the sleep is waiting and lose the tick.
func tick(_ ticker: Ticker, whenWaiting count: Int = 1) async {
    for _ in 0..<10_000 {
        if await ticker.pending >= count { break }
        await Task.yield()
    }
    for _ in 0..<500 {
        if await ticker.pending >= count { break }
        try? await Task.sleep(for: .milliseconds(10))
    }
    await ticker.tick()
}

/// A burst's end and saved count, for tests that don't look at its timing.
struct BurstOutcome: Equatable {
    let end: BurstEnd
    let saved: Int
}

extension Optional where Wrapped == BurstResult {
    /// The end and the saved count.
    var outcome: BurstOutcome? { map { BurstOutcome(end: $0.end, saved: $0.saved) } }
}

/// The self-timer, burst and hardware buttons through `CameraModel` (issues #37, #39, #46).
@MainActor
struct DriveTests {
    static let wide = CameraModelTests.wideRAW

    func makeModel(
        backend: any CaptureBackend = ScriptedBackend(capabilities: CameraModelTests.oneLens),
        saver: PhotoSaver? = CameraModelTests.saver(),
        sleep: @escaping @Sendable (Double) async throws -> Void = { _ in },
        reader: (any DeviceStatusReading)? = nil
    ) async -> CameraModel {
        let model = CameraModel(backend: backend, saver: saver, sleep: sleep, deviceStatusReader: reader)
        await model.send(.start)
        return model
    }

    func savedCount(_ model: CameraModel) -> Int? {
        switch model.captureStatus {
        case .saved: 1
        case .savedBurst(let photos): photos.count
        default: nil
        }
    }

    // MARK: - Values

    @Test func delaysAndModes() {
        #expect(SelfTimerDelay.threeSeconds.seconds == 3)
        #expect(SelfTimerDelay.tenSeconds.seconds == 10)
        #expect(SelfTimerDelay.allCases == [.threeSeconds, .tenSeconds])
        #expect(DriveMode.allCases == [.single, .timer(.threeSeconds), .timer(.tenSeconds), .burst, .interval])
        #expect(BurstProgress(taken: 2, saved: 1) == BurstProgress(taken: 2, saved: 1))
        #expect(BurstResult(end: .stopped, saved: 3).saved == 3)
        let drive = DriveModel(sleep: { _ in })
        drive.endBurst(.stopped)
        #expect(drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 0))
    }

    // MARK: - Countdown

    @Test func countdownTicksThenFires() async {
        let ticker = Ticker()
        let countdown = Countdown(sleep: { _ in await ticker.sleep() })
        var fired = 0
        countdown.start(seconds: 3) { fired += 1 }
        #expect(countdown.remainingSeconds == 3)
        #expect(countdown.isRunning)
        countdown.start(seconds: 10) { fired += 10 }
        #expect(countdown.remainingSeconds == 3)
        for expected in [2, 1] {
            await tick(ticker)
            await waitUntil { countdown.remainingSeconds == expected }
            #expect(countdown.remainingSeconds == expected)
        }
        await tick(ticker)
        await waitUntil { fired > 0 }
        #expect(fired == 1)
        #expect(!countdown.isRunning)
    }

    @Test func cancellingStopsWithoutFiring() async {
        let ticker = Ticker()
        let countdown = Countdown(sleep: { _ in await ticker.sleep() })
        var fired = false
        countdown.start(seconds: 3) { fired = true }
        await settle()
        countdown.cancel()
        #expect(countdown.remainingSeconds == nil)
        // A new countdown isn't overwritten by the cancelled one's late tick.
        countdown.start(seconds: 5) { fired = true }
        await tick(ticker, whenWaiting: 2)
        await settle()
        #expect(countdown.remainingSeconds == 5)
        countdown.cancel()
        await tick(ticker)
        await settle()
        #expect(!fired)
        countdown.cancel()
    }

    @Test func zeroSecondsDoesNothing() {
        let countdown = Countdown(sleep: { _ in })
        countdown.start(seconds: 0) {}
        #expect(!countdown.isRunning)
    }

    // MARK: - Shutter and timer

    @Test func singleModeTakesOnePhoto() async {
        let model = await makeModel()
        #expect(model.drive.mode == .single)
        #expect(model.canPressShutter)
        #expect(model.handlesHardwareButtons)
        await model.send(.capture)
        #expect(savedCount(model) == 1)
    }

    @Test func timerModeCountsDownThenTakesAPhoto() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend: backend, sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.setMode(.timer(.threeSeconds))))
        #expect(model.drive.mode == .timer(.threeSeconds))
        await model.send(.capture)
        #expect(model.drive.countdown.remainingSeconds == 3)
        #expect(model.drive.isBusy)
        // The mode can't change while counting down.
        await model.send(.drive(.setMode(.burst)))
        #expect(model.drive.mode == .timer(.threeSeconds))
        for _ in 0..<3 {
            await tick(ticker)
        }
        await waitUntil { savedCount(model) != nil }
        #expect(savedCount(model) == 1)
        #expect(await backend.captureRequests.count == 1)
    }

    @Test func pressingTheShutterAgainCancelsTheTimer() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend: backend, sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.setMode(.timer(.tenSeconds))))
        await model.send(.capture)
        #expect(model.drive.countdown.remainingSeconds == 10)
        await model.send(.capture)
        #expect(!model.drive.countdown.isRunning)
        await tick(ticker)
        await settle()
        #expect(await backend.captureRequests.isEmpty)
    }

    @Test func startTimerTakesAnyDelayAndCanBeCancelled() async {
        let ticker = Ticker()
        let model = await makeModel(sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.startTimer(seconds: 7)))
        #expect(model.drive.countdown.remainingSeconds == 7)
        // A second request while counting down is ignored.
        await model.send(.drive(.startTimer(seconds: 2)))
        #expect(model.drive.countdown.remainingSeconds == 7)
        await model.send(.drive(.cancelTimer))
        #expect(!model.drive.countdown.isRunning)
        await tick(ticker)
    }

    @Test func timerNeedsARunningCamera() async {
        let model = CameraModel(backend: ScriptedBackend(capabilities: CameraModelTests.oneLens), saver: CameraModelTests.saver())
        await model.send(.drive(.startTimer(seconds: 3)))
        #expect(!model.drive.countdown.isRunning)
        #expect(!model.canPressShutter)
        #expect(!model.handlesHardwareButtons)
    }

    // MARK: - Hardware buttons

    @Test func hardwareButtonTakesAPhotoWhenReleased() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend: backend)
        await model.send(.drive(.hardwareButton(.pressed)))
        #expect(await backend.captureRequests.isEmpty)
        await model.send(.drive(.hardwareButton(.cancelled)))
        #expect(await backend.captureRequests.isEmpty)
        await model.send(.drive(.hardwareButton(.released)))
        #expect(await backend.captureRequests.count == 1)
        #expect(savedCount(model) == 1)
    }

    @Test func hardwareButtonIsIgnoredWhileTheCameraIsntRunning() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.drive(.hardwareButton(.released)))
        #expect(await backend.captureRequests.isEmpty)
    }

    @Test func hardwareButtonStartsTheTimerInTimerMode() async {
        let ticker = Ticker()
        let model = await makeModel(sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.setMode(.timer(.threeSeconds))))
        await model.send(.drive(.hardwareButton(.released)))
        #expect(model.drive.countdown.remainingSeconds == 3)
        await model.send(.drive(.hardwareButton(.released)))
        #expect(!model.drive.countdown.isRunning)
        await tick(ticker)
    }

    @Test func holdingAHardwareButtonTakesABurstUntilReleased() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 3 else { return }
            await model.send(.drive(.hardwareButton(.released)))
        }
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.hardwareButton(.pressed)))
        #expect(savedCount(model) == 3)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 3))
        #expect(model.drive.burstProgress == nil)
    }

    @Test func cancelledHardwarePressStopsTheBurst() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 1 else { return }
            // A second press while the burst runs is ignored.
            await model.send(.drive(.hardwareButton(.pressed)))
            await model.send(.drive(.hardwareButton(.cancelled)))
        }
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.hardwareButton(.pressed)))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 1))
    }

    @Test func hardwareReleaseInBurstModeCancelsATimerFromElsewhere() async {
        let ticker = Ticker()
        let model = await makeModel(sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startTimer(seconds: 3)))
        await model.send(.drive(.hardwareButton(.pressed)))
        #expect(model.drive.burstProgress == nil)
        await model.send(.drive(.hardwareButton(.released)))
        #expect(!model.drive.countdown.isRunning)
        await tick(ticker)
    }

    // MARK: - Burst

    @Test func burstStopsAtTheLimit() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let library = FakeLibrary()
        let model = await makeModel(backend: backend, saver: CameraModelTests.saver(library: library))
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        #expect(savedCount(model) == DriveModel.maximumBurstFrames)
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .limitReached, saved: DriveModel.maximumBurstFrames))
        #expect(await backend.captureRequests.count == DriveModel.maximumBurstFrames)
        #expect(await library.added.count == DriveModel.maximumBurstFrames)
    }

    @Test func pressingTheShutterAgainStopsTheBurst() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 2 else { return }
            let progress = await model.drive.burstProgress
            #expect(progress?.taken == 1)
            #expect(await model.canPressShutter)
            await model.send(.capture)
        }
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 2))
    }

    @Test func stopBurstIntentStopsTheBurst() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 4 else { return }
            await model.send(.drive(.stopBurst))
        }
        await model.send(.drive(.stopBurst))
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .stopped, saved: 4))
    }

    @Test func burstStopsBeforeStorageRunsOut() async {
        let reader = FakeStatusReader(bytes: 0)
        let model = await makeModel(reader: reader)
        let perPhoto = PhotoSizeEstimate.bytes(for: Self.wide, settings: model.saveSettings)
        reader.bytes = perPhoto * 3
        reader.shrinkPerRead = perPhoto / 2
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst?.end == .storageFull)
        #expect((model.drive.lastBurst?.saved ?? 0) > 0)
        #expect(savedCount(model) == model.drive.lastBurst?.saved)
    }

    @Test func burstWithNoRoomSavesNothing() async {
        let model = await makeModel(reader: FakeStatusReader(bytes: 10))
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .storageFull, saved: 0))
        #expect(model.captureStatus == .idle)
    }

    @Test func burstStopsWhenTheCameraStops() async {
        let inner = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let hooked = HookedBackend(inner)
        let model = await makeModel(backend: hooked)
        let events = Task { await model.observeEvents() }
        await hooked.setOnCapture { [model] count in
            guard count == 2 else { return }
            inner.emit(.interrupted(.inUseElsewhere))
            for _ in 0..<1000 {
                if await model.sessionStatus != .running { break }
                await Task.yield()
            }
        }
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .cameraStopped, saved: 2))
        inner.finish()
        await events.value
    }

    @Test func aFrameThatCantBeTakenEndsTheBurstAndKeepsTheOthers() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens, captureErrors: [nil, nil, .captureFailed])
        let library = FakeLibrary()
        let model = await makeModel(backend: backend, saver: CameraModelTests.saver(library: library))
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        #expect(model.captureStatus == .failed(.captureFailed))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .failed, saved: 2))
        #expect(await library.added.count == 2)
    }

    @Test(arguments: [1, 3])
    func aFrameThatCantBeSavedEndsTheBurst(failingAdd: Int) async {
        let library = FailingLibrary(failingAdd: failingAdd)
        let saver = PhotoSaver(developer: FakeDeveloper(), signer: nil, reader: BytesReader(), library: library, appVersion: "0.2.0")
        let model = await makeModel(saver: saver)
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        #expect(model.captureStatus == .failed(.saveFailed))
        #expect(model.drive.lastBurst?.end == .failed)
        // The frame taken while the failing one was saving is still saved: nothing is dropped.
        #expect(model.drive.lastBurst?.saved == failingAdd)
    }

    @Test func lastFrameThatCantBeSavedEndsTheBurst() async {
        // The add that fails is the burst's last frame, saved after the loop.
        let library = FailingLibrary(failingAdd: DriveModel.maximumBurstFrames)
        let saver = PhotoSaver(developer: FakeDeveloper(), signer: nil, reader: BytesReader(), library: library, appVersion: "0.2.0")
        let model = await makeModel(saver: saver)
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        #expect(model.captureStatus == .failed(.saveFailed))
        #expect(model.drive.lastBurst.outcome == BurstOutcome(end: .failed, saved: DriveModel.maximumBurstFrames - 1))
    }

    @Test func aFailedCaptureAndAFailedSaveKeepTheFirstError() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens, captureErrors: [nil, .captureFailed])
        let saver = PhotoSaver(
            developer: FakeDeveloper(), signer: nil, reader: BytesReader(), library: FailingLibrary(failingAdd: 1),
            appVersion: "0.2.0")
        let model = await makeModel(backend: backend, saver: saver)
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        #expect(model.captureStatus == .failed(.captureFailed))
    }

    @Test func burstWithoutASaverSaysSo() async {
        let model = await makeModel(saver: nil)
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        #expect(model.captureStatus == .failed(.savingUnavailable))
        #expect(model.drive.burstProgress == nil)
    }

    @Test func burstNeedsARunningCamera() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        await model.send(.capture)
        #expect(model.drive.lastBurst == nil)
        #expect(await backend.captureRequests.isEmpty)
    }

    @Test func burstFramesAreSinglePhotosWithTheSamePlan() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let hooked = HookedBackend(backend)
        let model = await makeModel(backend: hooked)
        await hooked.setOnCapture { [model] count in
            if count == 2 { await model.send(.drive(.stopBurst)) }
        }
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.startBurst))
        let requests = await backend.captureRequests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0 == requests[0] })
        #expect(requests.first?.lens == Self.wide)
    }

    // MARK: - Device status

    @Test func storageWarnings() async {
        let reader = FakeStatusReader(bytes: nil)
        let status = DeviceStatus(reader: reader)
        #expect(status.fits(bytes: 1))
        #expect(status.storageWarning(bytesPerPhoto: 10) == nil)
        status.refresh()
        #expect(status.availableStorageBytes == nil)
        reader.bytes = 1000
        status.refresh()
        #expect(status.availableStorageBytes == 1000)
        #expect(status.fits(bytes: 1000))
        #expect(!status.fits(bytes: 1001))
        #expect(status.storageWarning(bytesPerPhoto: 0) == nil)
        #expect(status.storageWarning(bytesPerPhoto: 2000) == .full)
        #expect(status.storageWarning(bytesPerPhoto: 100) == .low(photosThatFit: 10))
        #expect(status.storageWarning(bytesPerPhoto: 1000 / 24) == .low(photosThatFit: 24))
        #expect(status.storageWarning(bytesPerPhoto: 1000 / 25) == nil)
    }

    @Test func batteryWarnings() {
        let reader = FakeStatusReader(bytes: nil)
        let status = DeviceStatus(reader: reader)
        #expect(status.batteryWarning == nil)
        #expect(DeviceStatus.lowBatteryLevel == 0.03)
        for battery in [
            BatteryReading(level: nil, isCharging: false, isLowPowerMode: false),
            // Charging never warns, however low.
            BatteryReading(level: 0.03, isCharging: true, isLowPowerMode: false),
            BatteryReading(level: 0.01, isCharging: true, isLowPowerMode: true),
            // Just above the threshold, and the old 20% threshold.
            BatteryReading(level: 0.031, isCharging: false, isLowPowerMode: false),
            BatteryReading(level: 0.2, isCharging: false, isLowPowerMode: true),
        ] {
            reader.batteryReading = battery
            status.refresh()
            #expect(status.battery == battery)
            #expect(status.batteryWarning == nil)
        }
        reader.batteryReading = BatteryReading(level: 0.03, isCharging: false, isLowPowerMode: true)
        status.refresh()
        #expect(status.batteryWarning == BatteryWarning(percent: 3, isLowPowerMode: true))
        reader.batteryReading = BatteryReading(level: 0.02, isCharging: false, isLowPowerMode: false)
        status.refresh()
        #expect(status.batteryWarning == BatteryWarning(percent: 2, isLowPowerMode: false))
        #expect(DeviceStatus(reader: nil).batteryWarning == nil)
    }

    @Test func modelReadsStatusWhenItStartsAndAfterEachPhoto() async {
        let reader = FakeStatusReader(bytes: 1_000_000_000_000)
        let model = CameraModel(backend: ScriptedBackend(capabilities: CameraModelTests.oneLens), deviceStatusReader: reader)
        #expect(model.storageWarning == nil)
        await model.send(.start)
        #expect(model.deviceStatus.availableStorageBytes == 1_000_000_000_000)
        #expect(model.storageWarning == nil)
        reader.bytes = 1
        await model.send(.capture)
        #expect(model.storageWarning == .full)
    }

    @Test func photoSizeEstimates() {
        let pixels = 4032.0 * 3024
        var settings = SaveSettings.rawPlusHEIFSigned
        let rawAndHEIF = Int64(pixels * 2 + 1_000_000 + pixels * 1 + 1_000_000)
        #expect(PhotoSizeEstimate.bytes(for: Self.wide, settings: settings) == rawAndHEIF)
        _ = settings.setFormat(.jpeg, isSelected: true)
        let withJPEG = rawAndHEIF + Int64(pixels * 2.5 + 1_000_000)
        #expect(PhotoSizeEstimate.bytes(for: Self.wide, settings: settings) == withJPEG)
        let sized = Lens(
            id: "sized", kind: .telephoto, bayerRAWFormat: nil, photoDimensions: [PhotoDimensions(width: 100, height: 10)])
        let fallback = sized.processedFallback == .heif ? 1.0 : 2.5
        #expect(PhotoSizeEstimate.bytes(for: sized, settings: settings) == Int64(1000 * fallback + 1_000_000))
        #expect(ProcessedFallback.heif.format == .heif)
        #expect(ProcessedFallback.jpeg.format == .jpeg)
    }

    // MARK: - Screen during a series

    @Test func seriesKeepsTheScreenAwakeAndDimmed() {
        let screen = FakeScreen(brightness: 0.8)
        let keeper = SeriesScreenKeeper(screen: screen)
        keeper.update(isSeriesRunning: false, isInForeground: true)
        #expect(!screen.isIdleTimerDisabled)
        keeper.update(isSeriesRunning: true, isInForeground: true)
        #expect(screen.isIdleTimerDisabled)
        #expect(screen.brightness == SeriesScreenKeeper.dimmedBrightness)
        #expect(keeper.isDimmed)
        #expect(keeper.isKeepingAwake)
        // A repeated update changes nothing.
        keeper.update(isSeriesRunning: true, isInForeground: true)
        #expect(screen.brightness == SeriesScreenKeeper.dimmedBrightness)
        keeper.brighten()
        #expect(screen.brightness == 0.8)
        #expect(!keeper.isDimmed)
        #expect(screen.isIdleTimerDisabled)
        keeper.brighten()
        #expect(screen.brightness == 0.8)
        keeper.update(isSeriesRunning: false, isInForeground: true)
        #expect(!screen.isIdleTimerDisabled)
        #expect(!keeper.isKeepingAwake)
    }

    @Test func leavingTheForegroundRestoresTheScreen() {
        let screen = FakeScreen(brightness: 0.05)
        let keeper = SeriesScreenKeeper(screen: screen)
        keeper.update(isSeriesRunning: true, isInForeground: true)
        // A screen darker than the dimmed level stays as it is.
        #expect(screen.brightness == 0.05)
        screen.brightness = 0.02
        keeper.update(isSeriesRunning: true, isInForeground: false)
        #expect(screen.brightness == 0.05)
        #expect(!screen.isIdleTimerDisabled)
        #expect(!keeper.isDimmed)
    }

    @Test func endingTheSeriesWhileDimmedRestoresBoth() async {
        let screen = FakeScreen(brightness: 0.6)
        let keeper = SeriesScreenKeeper(screen: screen)
        keeper.update(isSeriesRunning: true, isInForeground: true)
        keeper.update(isSeriesRunning: false, isInForeground: true)
        #expect(screen.brightness == 0.6)
        #expect(!screen.isIdleTimerDisabled)
    }

    // MARK: - Interval mode

    @Test func theIntervalModeStartsAndStopsASeriesWithTheShutter() async {
        let backend = ScriptedManualBackend(lenses: [ManualFixtures.wide])
        let model = CameraModel(
            backend: backend, saver: CameraModelTests.saver(), sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        await model.send(.start)
        await model.send(.drive(.setMode(.interval)))
        #expect(model.drive.mode == .interval)
        await model.send(.manual(.setInterval(IntervalSettings(interval: 60, count: 3))))
        await model.send(.capture)
        #expect(model.manual.intervalProgress != nil)
        #expect(model.canPressShutter)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        #expect(await backend.captureCount == 1)
        // The shutter stops the series, whatever the drive mode.
        await model.send(.drive(.setMode(.single)))
        await model.send(.capture)
        #expect(model.manual.intervalProgress == nil)
        #expect(await backend.captureCount == 1)
    }
}
