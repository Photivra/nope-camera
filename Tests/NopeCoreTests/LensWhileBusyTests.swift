import Foundation
import Testing

@testable import NopeCore

/// A manual-capable backend that runs like `AVFoundationCaptureBackend`: a photo is refused
/// unless the session runs with the request's lens, and a photo or bracket can be held in
/// flight, so a test can act while it is taken.
actor GatedLensBackend: ManualCaptureBackend, ComparisonCaptureBackend {
    /// One photo: the lens asked for, and the lens the session ran with when the photo began and
    /// ended.
    struct Shot: Equatable, Sendable {
        let requested: Lens.ID
        let activeAtStart: Lens.ID?
        let activeAtEnd: Lens.ID?
    }

    nonisolated let events: AsyncStream<CaptureEvent>
    nonisolated let exposureReadings: AsyncStream<ExposureReading>
    nonisolated let previewSource: (any CameraPreviewSource)? = nil
    private nonisolated let eventContinuation: AsyncStream<CaptureEvent>.Continuation
    private nonisolated let readingContinuation: AsyncStream<ExposureReading>.Continuation
    let capabilities: DeviceCapabilities
    private let captureError: CaptureError?

    /// The lens the session runs with, cleared while it starts, as the real backend's
    /// `activeConfiguration`.
    private(set) var activeLensID: Lens.ID?
    private(set) var startRequests: [Lens.ID] = []
    private(set) var shots: [Shot] = []
    private(set) var brackets = 0
    private var holdsCapture = false
    private var heldCapture: CheckedContinuation<Void, Never>?
    private var onCapture: (@Sendable (Int) async -> Void)?
    private var captureCount = 0

    init(lenses: [Lens], captureError: CaptureError? = nil) {
        capabilities = DeviceCapabilities(lenses: lenses)
        self.captureError = captureError
        (events, eventContinuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        (exposureReadings, readingContinuation) = AsyncStream.makeStream(of: ExposureReading.self)
    }

    func setHoldsCapture(_ holds: Bool) { holdsCapture = holds }
    var isCaptureHeld: Bool { heldCapture != nil }
    func releaseCapture() {
        holdsCapture = false
        heldCapture?.resume()
        heldCapture = nil
    }

    func setOnCapture(_ hook: @escaping @Sendable (Int) async -> Void) { onCapture = hook }

    func currentPermission() async -> CameraPermission { .authorized }
    func requestPermission() async -> CameraPermission { .authorized }
    func deviceCapabilities() async -> DeviceCapabilities { capabilities }

    func startSession(_ request: CaptureRequest) async throws(CaptureError) {
        startRequests.append(request.lens.id)
        activeLensID = request.lens.id
    }

    func stopSession() async { activeLensID = nil }
    func applyControls(_ controls: DeviceControls) async throws(CaptureError) {}
    func setExposureReadingsEnabled(_ enabled: Bool) async {}

    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        captureCount += 1
        await onCapture?(captureCount)
        guard activeLensID == request.lens.id else { throw .notRunning }
        if let captureError { throw captureError }
        let atStart = activeLensID
        if holdsCapture { await withCheckedContinuation { heldCapture = $0 } }
        shots.append(Shot(requested: request.lens.id, activeAtStart: atStart, activeAtEnd: activeLensID))
        return ScriptedManualBackend.photo(for: request, exposureDuration: 0.01, iso: 100)
    }

    func captureBracket(_ request: CaptureRequest, frames: [BracketFrame]) async throws(CaptureError)
        -> [CapturedPhoto]
    {
        guard activeLensID == request.lens.id else { throw .notRunning }
        brackets += 1
        let atStart = activeLensID
        if holdsCapture { await withCheckedContinuation { heldCapture = $0 } }
        shots.append(Shot(requested: request.lens.id, activeAtStart: atStart, activeAtEnd: activeLensID))
        return frames.map { ScriptedManualBackend.photo(for: request, exposureDuration: $0.exposureDuration, iso: $0.iso) }
    }

    func captureComparison(_ request: CaptureRequest) async throws(CaptureError) -> PhoneProcessedPhoto {
        PhoneProcessedPhoto(
            data: ScriptedComparisonBackend.phoneData, format: .heif, dimensions: PhotoDimensions(width: 4, height: 3),
            metadata: MetadataInventory())
    }
}

/// A photo library whose adds can be held, so a test can act while a photo is saved.
actor HeldLibrary: PhotoLibrary {
    private var holds = true
    private var held: CheckedContinuation<Void, Never>?
    var isHeld: Bool { held != nil }

    func release() {
        holds = false
        held?.resume()
        held = nil
    }

    func add(_ assets: [PhotoLibraryAsset]) async throws(CaptureError) {
        if holds { await withCheckedContinuation { held = $0 } }
    }
}

/// Polls an actor's condition on the clock, for up to five seconds.
func waitForActor(_ condition: @Sendable () async -> Bool) async {
    for _ in 0..<500 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// The lens while the camera is busy (issue #96; docs/design/lens-while-busy.md, section 7):
/// the one rule (`CameraModel.canChangeLens`) in every busy state, a lens change in each of
/// them, and Siri and Shortcuts in each of them.
@MainActor
struct LensWhileBusyTests {
    /// Each state in which the lens can't be changed.
    enum Busy: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case capturing, saving, countdown, burst, heldBurst, bracket, bracketFullAuto, bracketSaving, bracketDelay
        case intervalFrame, intervalWait, astroRun, compareView

        var testDescription: String { rawValue }

        /// The reason the model gives in this state.
        var blocker: LensChangeBlocker {
            switch self {
            case .capturing, .saving, .bracket, .bracketFullAuto, .bracketSaving: .takingPhoto
            case .countdown, .burst, .heldBurst, .bracketDelay, .intervalFrame, .intervalWait, .astroRun: .runningSeries
            case .compareView: .comparing
            }
        }
    }

    /// A started camera on the wide lens, with the ultra wide lens to switch to.
    struct Camera {
        let model: CameraModel
        let backend: GatedLensBackend
        let library: HeldLibrary?
        let ticker: Ticker
    }

    static let lenses = [ManualFixtures.wide, ManualFixtures.basicLens]

    func makeCamera(
        _ backend: GatedLensBackend = GatedLensBackend(lenses: lenses), library: HeldLibrary? = nil,
        ticks: Bool = false
    ) async -> Camera {
        let ticker = Ticker()
        let saver =
            library.map {
                PhotoSaver(developer: FakeDeveloper(), signer: nil, reader: BytesReader(), library: $0, appVersion: "1.0.0")
            } ?? CameraModelTests.saver()
        let sleep: @Sendable (Double) async throws -> Void
        if ticks {
            sleep = { _ in await ticker.sleep() }
        } else {
            sleep = { _ in }
        }
        let model = CameraModel(
            backend: backend, saver: saver, sleep: sleep, deviceStatusReader: FakeStatusReader(bytes: nil))
        await model.send(.start)
        #expect(model.canChangeLens)
        #expect(model.lensChangeBlocker == nil)
        return Camera(model: model, backend: backend, library: library, ticker: ticker)
    }

    /// Brings a camera into a busy state, runs `action` there, then lets the state end normally:
    /// the photo is saved, the countdown's photo taken, the series completed, the compare view
    /// closed.
    ///
    /// - Returns: The camera, once the state has ended.
    @discardableResult
    func whileBusy(_ state: Busy, _ action: @escaping @MainActor @Sendable (CameraModel) async -> Void) async -> Camera {
        switch state {
        case .capturing:
            let camera = await makeCamera()
            await camera.backend.setHoldsCapture(true)
            let shot = Task { await camera.model.send(.capture) }
            await waitForActor { await camera.backend.isCaptureHeld }
            await action(camera.model)
            await camera.backend.releaseCapture()
            await shot.value
            return camera
        case .saving:
            let library = HeldLibrary()
            let camera = await makeCamera(library: library)
            let shot = Task { await camera.model.send(.capture) }
            await waitForActor { await library.isHeld }
            #expect(camera.model.captureStatus == .saving)
            await action(camera.model)
            await library.release()
            await shot.value
            return camera
        case .countdown:
            let camera = await makeCamera(ticks: true)
            await camera.model.send(.drive(.startTimer(seconds: 3)))
            #expect(camera.model.drive.countdown.isRunning)
            await action(camera.model)
            for _ in 0..<3 { await tick(camera.ticker) }
            await waitUntil { camera.model.captureStatus != .idle && !camera.model.isTakingPhoto }
            return camera
        case .burst:
            let camera = await makeCamera()
            await camera.backend.setOnCapture { count in
                guard count == 2 else { return }
                await action(camera.model)
            }
            await camera.model.takeBurst(frames: 3)
            return camera
        case .bracket:
            let camera = await makeCamera()
            await camera.model.send(.manual(.setEnabled(true)))
            await camera.model.manual.record(ManualFixtures.reading)
            await camera.model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1))))
            await camera.backend.setHoldsCapture(true)
            let shot = Task { await camera.model.send(.capture) }
            await waitForActor { await camera.backend.isCaptureHeld }
            await action(camera.model)
            await camera.backend.releaseCapture()
            await shot.value
            return camera
        case .heldBurst:
            // Burst held on the on-screen shutter (docs/design/BURST.md): busy from the first
            // photo, which is requested as the shutter goes down, until the release.
            let camera = await makeCamera()
            await camera.model.send(.drive(.setMode(.burst)))
            await camera.backend.setOnCapture { count in
                if count == 1 { await action(camera.model) }
                if count == 2 { await camera.model.send(.drive(.shutter(.released))) }
            }
            await camera.model.send(.drive(.shutter(.pressed)))
            return camera
        case .bracketFullAuto:
            // A bracket from the drive strip with Manual Controls off (docs/design/BRACKETING.md).
            let camera = await makeCamera()
            await camera.model.manual.record(ManualFixtures.reading)
            await camera.model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1))))
            #expect(!camera.model.manual.isEnabled)
            await camera.backend.setHoldsCapture(true)
            let shot = Task { await camera.model.send(.capture) }
            await waitForActor { await camera.backend.isCaptureHeld }
            #expect(camera.model.bracketProgress != nil)
            await action(camera.model)
            await camera.backend.releaseCapture()
            await shot.value
            return camera
        case .bracketSaving:
            let library = HeldLibrary()
            let camera = await makeCamera(library: library)
            await camera.model.manual.record(ManualFixtures.reading)
            await camera.model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1))))
            let shot = Task { await camera.model.send(.capture) }
            await waitForActor { await library.isHeld }
            #expect(camera.model.bracketProgress?.taken == 3)
            await action(camera.model)
            await library.release()
            await shot.value
            return camera
        case .bracketDelay:
            // A bracket with its start delay counts down as the self-timer does.
            let camera = await makeCamera(ticks: true)
            await camera.model.manual.record(ManualFixtures.reading)
            await camera.model.send(.drive(.setMode(.timer(.threeSeconds))))
            await camera.model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1))))
            #expect(camera.model.bracketStartDelay == .threeSeconds)
            await camera.model.send(.capture)
            #expect(camera.model.drive.countdown.isRunning)
            await action(camera.model)
            for _ in 0..<3 { await tick(camera.ticker) }
            await waitUntil { camera.model.captureStatus != .idle && !camera.model.isTakingPhoto }
            return camera
        case .intervalFrame, .intervalWait:
            let camera = await makeCamera(ticks: true)
            if state == .intervalFrame {
                await camera.backend.setOnCapture { count in
                    guard count == 2 else { return }
                    await action(camera.model)
                }
            }
            await camera.model.send(.manual(.setInterval(IntervalSettings(interval: 60, count: 3))))
            await camera.model.send(.manual(.startInterval))
            await waitUntil { camera.model.manual.intervalProgress?.taken == 1 }
            if state == .intervalWait { await action(camera.model) }
            await tick(camera.ticker)
            await waitUntil { camera.model.manual.intervalProgress?.taken == 2 }
            await tick(camera.ticker)
            await waitUntil { camera.model.manual.intervalProgress == nil }
            await waitUntil { !camera.model.isTakingPhoto }
            return camera
        case .astroRun:
            let camera = await makeCamera()
            await camera.model.send(.astro(.setOn(true)))
            await camera.model.send(.astro(.setFrameCount(5)))
            await camera.backend.setOnCapture { count in
                guard count == 2 else { return }
                await action(camera.model)
            }
            await camera.model.send(.capture)
            for _ in 0..<500 where camera.model.astro.lastRun == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return camera
        case .compareView:
            let camera = await makeCamera()
            camera.model.comparison.renderer = RecordingRenderer()
            await camera.model.send(.comparison(.setOn(true)))
            await camera.model.send(.capture)
            #expect(camera.model.comparison.isPresented)
            await action(camera.model)
            await camera.model.send(.comparison(.close))
            return camera
        }
    }

    /// The camera ran with the wide lens only: one start, and every photo with the wide lens
    /// from start to end.
    func expectOneLens(_ camera: Camera, photos: Int) async {
        #expect(camera.model.selectedLensID == "wide")
        #expect(await camera.backend.startRequests == ["wide"])
        let shots = await camera.backend.shots
        #expect(shots.count == photos)
        #expect(shots.allSatisfy { $0 == .init(requested: "wide", activeAtStart: "wide", activeAtEnd: "wide") })
    }

    /// The photos each state takes once it ends normally.
    func photos(in state: Busy) -> Int {
        switch state {
        case .capturing, .saving, .countdown, .bracket, .bracketFullAuto, .bracketSaving, .bracketDelay, .compareView: 1
        case .heldBurst: 2
        case .burst, .intervalFrame, .intervalWait: 3
        case .astroRun: 5
        }
    }

    // MARK: - 1. The rule

    @Test(arguments: Busy.allCases)
    func theLensCantBeChangedWhileBusy(_ state: Busy) async {
        let camera = await whileBusy(state) { model in
            #expect(!model.canChangeLens)
            #expect(model.lensChangeBlocker == state.blocker)
            #expect(model.isBusyForPresets)
        }
        #expect(camera.model.canChangeLens)
        #expect(!camera.model.isBusyForPresets)
    }

    @Test func theLensCanBeChangedAgainAfterAStop() async {
        // A countdown cancelled.
        let timer = await makeCamera(ticks: true)
        await timer.model.send(.drive(.startTimer(seconds: 3)))
        #expect(!timer.model.canChangeLens)
        await timer.model.send(.capture)
        #expect(timer.model.canChangeLens)

        // A burst stopped.
        let burst = await makeCamera()
        await burst.backend.setOnCapture { count in
            guard count == 2 else { return }
            await MainActor.run { burst.model.drive.requestBurstStop() }
        }
        await burst.model.takeBurst(frames: 6)
        #expect(burst.model.canChangeLens)

        // An interval series stopped during its wait.
        let interval = await makeCamera(ticks: true)
        await interval.model.send(.manual(.setInterval(IntervalSettings(interval: 60, count: 3))))
        await interval.model.send(.manual(.startInterval))
        await waitUntil { interval.model.manual.intervalProgress?.taken == 1 }
        #expect(interval.model.lensChangeBlocker == .runningSeries)
        await interval.model.send(.manual(.stopInterval))
        await waitUntil { interval.model.manual.intervalProgress == nil }
        #expect(interval.model.canChangeLens)

        // An astro run stopped.
        let astro = await makeCamera()
        await astro.model.send(.astro(.setOn(true)))
        await astro.model.send(.astro(.setFrameCount(10)))
        await astro.backend.setOnCapture { count in
            guard count == 2 else { return }
            await astro.model.send(.astro(.stop))
        }
        await astro.model.send(.capture)
        for _ in 0..<500 where astro.model.astro.lastRun == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(astro.model.canChangeLens)
    }

    @Test func theLensCanBeChangedAgainAfterAFailedPhoto() async {
        let camera = await makeCamera(GatedLensBackend(lenses: Self.lenses, captureError: .captureFailed))
        await camera.model.send(.capture)
        #expect(camera.model.captureStatus == .failed(.captureFailed))
        #expect(camera.model.canChangeLens)
        await camera.model.send(.selectLens("basic"))
        #expect(camera.model.selectedLensID == "basic")
    }

    @Test func aSeriesIsTheReasonForItsOwnPhotos() async {
        // During an interval photo the photo is being taken too; the series is the reason, so
        // an interface keeps the controls dimmed for the whole series.
        await whileBusy(.intervalFrame) { model in
            #expect(model.isTakingPhoto)
            #expect(model.lensChangeBlocker == .runningSeries)
        }
    }

    // MARK: - 2. A lens change while busy

    @Test(arguments: Busy.allCases)
    func aLensChangeWhileBusyChangesNothing(_ state: Busy) async {
        let camera = await whileBusy(state) { model in
            await model.send(.selectLens("basic"))
            #expect(model.selectedLensID == "wide")
        }
        await expectOneLens(camera, photos: photos(in: state))
        // Afterwards the lens changes again.
        await camera.model.send(.selectLens("basic"))
        #expect(camera.model.selectedLensID == "basic")
        #expect(await camera.backend.startRequests == ["wide", "basic"])
    }

    // MARK: - 3. Siri and Shortcuts while busy

    /// Submits a request and serves it, returning the outcome.
    func run(_ request: ShortcutRequest, on model: CameraModel, presets: SettingsPresets? = nil) async -> ShortcutOutcome {
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let server = Task { await model.serveShortcuts(from: inbox, presets: presets) }
        defer { server.cancel() }
        await waitUntil { inbox.isServed }
        return await inbox.submit(request)
    }

    @Test(arguments: Busy.allCases)
    func shortcutsDontChangeTheLensWhileBusy(_ state: Busy) async {
        let scratch = ScratchDefaults()
        let presets = SettingsPresets(settings: NopeSettings(defaults: scratch.defaults))
        let camera = await whileBusy(state) { model in
            #expect(await run(.selectLens(.ultraWide), on: model) == .lensBusy)
            #expect(await run(.takePhoto(PhotoShortcut(lensKind: .ultraWide)), on: model) == .busy)
            #expect(await run(.takeBracket(BracketShortcut(frameCount: 3, step: 1, lensKind: .ultraWide)), on: model) == .busy)
            #expect(await run(.applyPreset(.factoryDefaults), on: model, presets: presets) == .busy)
            #expect(model.selectedLensID == "wide")
        }
        await expectOneLens(camera, photos: photos(in: state))
    }

    @Test func switchLensToTheLensInUseSaysSoEvenWhileBusy() async {
        await whileBusy(.capturing) { model in
            #expect(await run(.selectLens(.wide), on: model) == .lensSelected(.wide))
        }
    }

    @Test func aBusyLensChangeIsBusyOnTheWatch() {
        #expect(WatchResult(ShortcutOutcome.lensBusy) == .busy)
    }
}
