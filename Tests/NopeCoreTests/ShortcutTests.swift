import Foundation
import Testing

@testable import NopeCore

/// Siri and Shortcuts requests through `ShortcutInbox` and `CameraModel` (issue #62).
@MainActor
struct ShortcutTests {
    /// A sleep that never ends unless cancelled, so timeouts don't pass during a test.
    static let neverTimesOut: @Sendable (Double) async throws -> Void = { _ in
        try await Task.sleep(for: .seconds(3600))
    }

    /// A model that has started, with the fake save pipeline (no signer, so photos are unsigned).
    func makeModel(
        _ backend: ScriptedBackend = ScriptedBackend(capabilities: CameraModelTests.oneLens),
        sleep: @escaping @Sendable (Double) async throws -> Void = { _ in }, start: Bool = true
    ) async -> CameraModel {
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), sleep: sleep)
        if start { await model.send(.start) }
        return model
    }

    /// Submits a request and serves it, returning the outcome.
    func run(
        _ request: ShortcutRequest, on model: CameraModel, inbox: ShortcutInbox = ShortcutInbox(sleep: neverTimesOut)
    ) async -> ShortcutOutcome {
        let server = Task { await model.serveShortcuts(from: inbox) }
        defer { server.cancel() }
        // As in the app, where the camera screen serves the inbox before Siri's request arrives.
        await waitUntil { inbox.isServed }
        return await inbox.submit(request)
    }

    static func photo(_ signature: SignatureStatus) -> SavedPhoto {
        SavedPhoto(formats: [.raw], isProcessedFallback: false, signature: signature, metadata: [:])
    }

    // MARK: - Values

    @Test func delaysAreCheckedAndCustomReplacesThePreset() {
        #expect(PhotoShortcut().delaySeconds == 0)
        #expect(PhotoShortcut().lensKind == nil)
        #expect(PhotoShortcut(delaySeconds: -4).delaySeconds == 0)
        #expect(PhotoShortcut(delaySeconds: 25, lensKind: .front).delaySeconds == 25)
        #expect(PhotoShortcut(delaySeconds: 25, lensKind: .front).lensKind == .front)
        #expect(PhotoShortcut(delaySeconds: 600).delaySeconds == PhotoShortcut.maximumDelaySeconds)
        #expect(PhotoShortcut(timer: nil, customDelaySeconds: nil).delaySeconds == 0)
        #expect(PhotoShortcut(timer: .threeSeconds, customDelaySeconds: nil).delaySeconds == 3)
        #expect(PhotoShortcut(timer: .tenSeconds, customDelaySeconds: 7, lensKind: .wide).delaySeconds == 7)
        #expect(PhotoShortcut(timer: .tenSeconds, customDelaySeconds: 0).delaySeconds == 0)
        #expect(PhotoShortcut(timer: .tenSeconds, customDelaySeconds: 7, lensKind: .wide).lensKind == .wide)
    }

    @Test func outcomesReportOnlyWhetherPhotosWereSavedAndSigned() async {
        let model = await makeModel(start: false)
        #expect(model.outcome(of: .saved(Self.photo(.signed))) == .saved(isSigned: true))
        #expect(model.outcome(of: .saved(Self.photo(.unsigned(.turnedOff)))) == .saved(isSigned: false))
        #expect(
            model.outcome(of: .savedBracket([Self.photo(.signed), Self.photo(.signed)])) == .savedSeveral(allSigned: true))
        #expect(
            model.outcome(of: .savedBurst([Self.photo(.signed), Self.photo(.unsigned(.failed))]))
                == .savedSeveral(allSigned: false))
        #expect(model.outcome(of: .failed(.saveFailed)) == .notSaved(.saveFailed))
        #expect(model.outcome(of: .idle) == .notSaved(.notRunning))
        #expect(model.outcome(of: .capturing) == .notSaved(.notRunning))
    }

    // MARK: - Taking photos

    @Test func takesOnePhotoAtOnceWhateverTheDriveMode() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend)
        await model.send(.drive(.setMode(.burst)))
        let outcome = await run(.takePhoto(PhotoShortcut()), on: model)
        #expect(outcome == .saved(isSigned: false))
        #expect(await backend.captureRequests.count == 1)
        #expect(model.drive.mode == .burst)
    }

    @Test func aDelayRunsTheSelfTimerThenTakesThePhoto() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend, sleep: { _ in await ticker.sleep() })
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        let server = Task { await model.serveShortcuts(from: inbox) }
        defer { server.cancel() }
        let request = Task { await inbox.submit(.takePhoto(PhotoShortcut(delaySeconds: 2))) }
        await waitUntil { model.drive.countdown.remainingSeconds == 2 }
        #expect(model.drive.countdown.remainingSeconds == 2)
        #expect(await backend.captureRequests.isEmpty)
        await tick(ticker)
        // The next tick only after the countdown has moved on, so it isn't lost on a busy Mac.
        await waitUntil { model.drive.countdown.remainingSeconds == 1 }
        await tick(ticker)
        #expect(await request.value == .saved(isSigned: false))
        #expect(await backend.captureRequests.count == 1)
    }

    @Test func aCancelledCountdownTakesNoPhoto() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend, sleep: { _ in await ticker.sleep() })
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        let server = Task { await model.serveShortcuts(from: inbox) }
        defer { server.cancel() }
        let request = Task { await inbox.submit(.takePhoto(PhotoShortcut(delaySeconds: 10))) }
        await waitUntil { model.drive.countdown.isRunning }
        await model.send(.drive(.cancelTimer))
        #expect(await request.value == .cancelled)
        #expect(await backend.captureRequests.isEmpty)
    }

    @Test func aCameraThatStopsDuringTheCountdownIsReported() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend, sleep: { _ in await ticker.sleep() })
        let events = Task { await model.observeEvents() }
        defer { events.cancel() }
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        let server = Task { await model.serveShortcuts(from: inbox) }
        defer { server.cancel() }
        let request = Task { await inbox.submit(.takePhoto(PhotoShortcut(delaySeconds: 1))) }
        await waitUntil { model.drive.countdown.isRunning }
        backend.emit(.interrupted(.inUseElsewhere))
        await waitUntil { model.sessionStatus == .interrupted(.inUseElsewhere) }
        await tick(ticker)
        #expect(await request.value == .cameraUnavailable(.notRunning))
        #expect(await backend.captureRequests.isEmpty)
    }

    @Test func aFailedPhotoIsReported() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens, captureError: .captureFailed)
        let model = await makeModel(backend)
        #expect(await run(.takePhoto(PhotoShortcut()), on: model) == .notSaved(.captureFailed))
    }

    @Test func aRunningCountdownMakesTheRequestBusy() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend, sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.startTimer(seconds: 5)))
        #expect(await run(.takePhoto(PhotoShortcut()), on: model) == .busy)
        model.drive.countdown.cancel()
    }

    // MARK: - Lenses

    @Test func switchesToTheLensAskedFor() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.twoLenses)
        let model = await makeModel(backend)
        #expect(model.selectedLens?.kind == .wide)
        let outcome = await run(.takePhoto(PhotoShortcut(lensKind: .telephoto)), on: model)
        #expect(outcome == .saved(isSigned: false))
        #expect(model.selectedLens?.kind == .telephoto)
        #expect(await backend.captureRequests.last?.lens.kind == .telephoto)
        // The lens already in use is kept.
        #expect(await run(.takePhoto(PhotoShortcut(lensKind: .telephoto)), on: model) == .saved(isSigned: false))
        #expect(await backend.startRequests.count == 2)
    }

    @Test func aMissingLensTakesNoPhoto() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.twoLenses)
        let model = await makeModel(backend)
        #expect(await run(.takePhoto(PhotoShortcut(lensKind: .front)), on: model) == .lensUnavailable)
        #expect(await backend.captureRequests.isEmpty)
    }

    @Test func aLensThatFailsToStartIsReported() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.twoLenses, startErrors: [nil, .configurationFailed])
        let model = await makeModel(backend)
        let outcome = await run(.takePhoto(PhotoShortcut(lensKind: .telephoto)), on: model)
        #expect(outcome == .cameraUnavailable(.notRunning))
        #expect(await backend.captureRequests.isEmpty)
    }

    // MARK: - Camera states

    @Test(arguments: [
        (CameraPermission.notDetermined, CameraUnavailability.needsPermission),
        (.denied, .permissionDenied),
        (.restricted, .permissionDenied),
    ])
    func permissionProblemsAreReported(permission: CameraPermission, reason: CameraUnavailability) async {
        let backend = ScriptedBackend(permission: permission, capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend)
        #expect(await run(.takePhoto(PhotoShortcut()), on: model) == .cameraUnavailable(reason))
    }

    @Test func aDeviceWithoutACameraIsReported() async {
        let model = await makeModel(ScriptedBackend(capabilities: DeviceCapabilities(lenses: [])))
        #expect(model.state == .unavailable)
        #expect(await run(.takePhoto(PhotoShortcut()), on: model) == .cameraUnavailable(.noCamera))
    }

    @Test func aPausedCameraIsReported() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend)
        let events = Task { await model.observeEvents() }
        defer { events.cancel() }
        backend.emit(.interrupted(.inUseElsewhere))
        await waitUntil { model.sessionStatus == .interrupted(.inUseElsewhere) }
        #expect(await run(.takePhoto(PhotoShortcut()), on: model) == .cameraUnavailable(.notRunning))
    }

    @Test func waitsForTheCameraToStart() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend, start: false)
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        let server = Task { await model.serveShortcuts(from: inbox) }
        defer { server.cancel() }
        let request = Task { await inbox.submit(.takePhoto(PhotoShortcut())) }
        await settle()
        #expect(await backend.captureRequests.isEmpty)
        await model.send(.start)
        #expect(await request.value == .saved(isSigned: false))
    }

    @Test func aCameraThatNeverStartsTimesOut() async {
        let model = await makeModel(start: false)
        let outcome = await run(.takePhoto(PhotoShortcut()), on: model, inbox: ShortcutInbox(sleep: { _ in }))
        #expect(outcome == .cameraUnavailable(.notRunning))
    }

    // MARK: - Inbox

    @Test func aRequestNoCameraScreenTakesTimesOut() async {
        let inbox = ShortcutInbox(sleep: { _ in })
        #expect(await inbox.submit(.takePhoto(PhotoShortcut())) == .cameraUnavailable(.notRunning))
    }

    @Test func requestsWaitForTheCameraScreenInOrder() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.twoLenses)
        let model = await makeModel(backend)
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        let first = Task { await inbox.submit(.takePhoto(PhotoShortcut(lensKind: .telephoto))) }
        await settle()
        let second = Task { await inbox.submit(.takePhoto(PhotoShortcut(lensKind: .front))) }
        await settle()
        let server = Task { await model.serveShortcuts(from: inbox) }
        defer { server.cancel() }
        #expect(await first.value == .saved(isSigned: false))
        #expect(await second.value == .lensUnavailable)
    }

    @Test func aCancelledServerStopsWaiting() async {
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        let server = Task { await inbox.next() }
        await settle()
        server.cancel()
        #expect(await server.value == nil)
        // A server whose task is already cancelled stops at once.
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await inbox.next()
        }
        #expect(await cancelled.value == nil)
    }

    @Test func aSecondServerReplacesTheFirst() async {
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        let first = Task { await inbox.next() }
        await settle()
        let second = Task { await inbox.next() }
        #expect(await first.value == nil)
        let request = Task { await inbox.submit(.takePhoto(PhotoShortcut(delaySeconds: 3))) }
        let pending = await second.value
        #expect(pending?.request == .takePhoto(PhotoShortcut(delaySeconds: 3)))
        pending?.finish(.busy)
        pending?.finish(.cancelled)
        #expect(await request.value == .busy)
    }

    @Test func aRequestTakenAtOnceDoesNotTimeOut() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend)
        // The timeouts pass at once, but the camera screen already waits for the request.
        let inbox = ShortcutInbox(sleep: { _ in })
        let server = Task { await model.serveShortcuts(from: inbox) }
        defer { server.cancel() }
        await settle()
        #expect(await inbox.submit(.takePhoto(PhotoShortcut())) == .saved(isSigned: false))
    }

    @Test func theDefaultTimeoutSleeps() async {
        let inbox = ShortcutInbox()
        #expect(await inbox.wait(timeoutSeconds: 0.01) { false } == false)
    }

    @Test func aWaitEndsAtItsTimeout() async {
        let inbox = ShortcutInbox(sleep: { _ in })
        let model = await makeModel(start: false)
        #expect(await inbox.wait(timeoutSeconds: 1) { model.state != .starting } == false)
        await model.send(.start)
        #expect(await inbox.wait(timeoutSeconds: 1) { model.state != .starting })
    }

    // MARK: - Count

    @Test func countsAreChecked() {
        #expect(PhotoShortcut().count == 1)
        #expect(PhotoShortcut(count: 0).count == 1)
        #expect(PhotoShortcut(count: 7).count == 7)
        #expect(PhotoShortcut(count: 500).count == DriveModel.maximumBurstFrames)
        #expect(PhotoShortcut(timer: nil, customDelaySeconds: nil).count == 1)
        #expect(PhotoShortcut(timer: .threeSeconds, customDelaySeconds: nil, count: 4).count == 4)
    }

    @Test func aCountTakesABurstOfThatManyFrames() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend)
        let outcome = await run(.takePhoto(PhotoShortcut(count: 3)), on: model)
        #expect(outcome == .savedSeveral(allSigned: false))
        #expect(await backend.captureRequests.count == 3)
        #expect(model.drive.lastBurst == BurstResult(end: .countReached, saved: 3))
        #expect(model.drive.mode == .single)
    }

    @Test func theLargestCountEndsAsTheBurstLimit() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend)
        let outcome = await run(.takePhoto(PhotoShortcut(count: DriveModel.maximumBurstFrames)), on: model)
        #expect(outcome == .savedSeveral(allSigned: false))
        #expect(model.drive.lastBurst == BurstResult(end: .limitReached, saved: DriveModel.maximumBurstFrames))
    }

    @Test func aDelayWithACountTakesTheBurstAfterTheCountdown() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend, sleep: { _ in await ticker.sleep() })
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        let server = Task { await model.serveShortcuts(from: inbox) }
        defer { server.cancel() }
        let request = Task { await inbox.submit(.takePhoto(PhotoShortcut(delaySeconds: 1, count: 2))) }
        await waitUntil { model.drive.countdown.isRunning }
        #expect(await backend.captureRequests.isEmpty)
        await tick(ticker)
        #expect(await request.value == .savedSeveral(allSigned: false))
        #expect(await backend.captureRequests.count == 2)
    }

    // MARK: - Switching lenses

    @Test func switchesLenses() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.twoLenses)
        let model = await makeModel(backend)
        #expect(await run(.selectLens(.telephoto), on: model) == .lensSelected(.telephoto))
        #expect(model.selectedLens?.kind == .telephoto)
        // The lens in use is kept, without restarting the camera.
        #expect(await run(.selectLens(.telephoto), on: model) == .lensSelected(.telephoto))
        #expect(await backend.startRequests.count == 2)
        #expect(await run(.selectLens(.front), on: model) == .lensUnavailable)
        #expect(await backend.captureRequests.isEmpty)
    }

    @Test func switchingLensesWaitsForACountdown() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.twoLenses)
        let model = await makeModel(backend, sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.startTimer(seconds: 5)))
        #expect(await run(.selectLens(.telephoto), on: model) == .busy)
        #expect(model.selectedLens?.kind == .wide)
        model.drive.countdown.cancel()
    }

    @Test func aLensSwitchTheCameraCanNotDoIsReported() async {
        let denied = ScriptedBackend(permission: .denied, capabilities: CameraModelTests.twoLenses)
        #expect(await run(.selectLens(.telephoto), on: await makeModel(denied)) == .cameraUnavailable(.permissionDenied))
        let failing = ScriptedBackend(capabilities: CameraModelTests.twoLenses, startErrors: [nil, .configurationFailed])
        #expect(await run(.selectLens(.telephoto), on: await makeModel(failing)) == .cameraUnavailable(.notRunning))
    }

    // MARK: - Light

    @Test func turnsTheLightOnAndOff() async {
        let (model, backend) = await LightModelTests.running()
        #expect(await run(.setLight(isOn: true), on: model) == .lightOn)
        #expect(model.light.isTorchOn)
        #expect(await run(.setLight(isOn: false), on: model) == .lightOff)
        #expect(!model.light.isTorchOn)
        #expect(await backend.torchRequests.count == 2)
    }

    @Test func aLightTheSystemRefusesIsReported() async {
        let (model, backend) = await LightModelTests.running()
        await backend.setAvailable(false)
        #expect(await run(.setLight(isOn: true), on: model) == .lightUnavailable)
    }

    @Test func aLensWithoutALightSaysSo() async {
        let model = await makeModel(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        #expect(await run(.setLight(isOn: true), on: model) == .noLight)
        let denied = await makeModel(ScriptedBackend(permission: .denied, capabilities: CameraModelTests.oneLens))
        #expect(await run(.setLight(isOn: true), on: denied) == .cameraUnavailable(.permissionDenied))
    }

    // MARK: - Interval shooting

    /// A started camera with manual controls, on or off, whose interval sleeps never end.
    func makeManualModel(enabled: Bool = true) async -> (CameraModel, ScriptedManualBackend) {
        let backend = ScriptedManualBackend(lenses: [ManualFixtures.wide])
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), sleep: Self.neverTimesOut)
        await model.send(.start)
        if enabled { await model.send(.manual(.setEnabled(true))) }
        return (model, backend)
    }

    @Test func intervalValuesKeepWhatIsNotGiven() {
        let chosen = IntervalSettings(interval: 30, count: 20)
        #expect(IntervalShortcut().settings(over: chosen) == chosen)
        #expect(IntervalShortcut(intervalSeconds: 5).settings(over: chosen) == IntervalSettings(interval: 5, count: 20))
        #expect(IntervalShortcut(count: 4).settings(over: chosen) == IntervalSettings(interval: 30, count: 4))
        #expect(IntervalShortcut(intervalSeconds: 0, count: 5000).settings(over: chosen) == IntervalSettings(interval: 1, count: 999))
    }

    @Test func startsAndStopsAnIntervalSeries() async {
        let (model, backend) = await makeManualModel()
        let outcome = await run(.startInterval(IntervalShortcut(intervalSeconds: 5, count: 3)), on: model)
        #expect(outcome == .intervalStarted)
        #expect(model.manual.interval == IntervalSettings(interval: 5, count: 3))
        #expect(model.manual.intervalProgress != nil)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        #expect(await backend.captureCount == 1)
        // A running series makes other requests busy.
        #expect(await run(.startInterval(IntervalShortcut()), on: model) == .busy)
        #expect(await run(.takePhoto(PhotoShortcut()), on: model) == .busy)
        #expect(await run(.stopInterval, on: model) == .intervalStopped)
        #expect(model.manual.intervalProgress == nil)
        #expect(await run(.stopInterval, on: model) == .noIntervalRunning)
    }

    @Test func intervalShootingRunsInFullAutoWithoutTurningOnManualControls() async {
        let (model, backend) = await makeManualModel(enabled: false)
        #expect(await run(.startInterval(IntervalShortcut(count: 2)), on: model) == .intervalStarted)
        #expect(!model.manual.isEnabled)
        await waitUntil { model.manual.intervalProgress?.taken == 1 }
        #expect(await backend.captureCount == 1)
        #expect(await backend.applied.isEmpty)
        #expect(await run(.stopInterval, on: model) == .intervalStopped)
        let denied = await makeModel(ScriptedBackend(permission: .denied, capabilities: CameraModelTests.oneLens))
        #expect(await run(.startInterval(IntervalShortcut()), on: denied) == .cameraUnavailable(.permissionDenied))
    }

    // MARK: - Brackets

    @Test func bracketValuesMoveToTheNearestOffered() {
        #expect(BracketShortcut(frameCount: 5, step: 1).bracket == BracketSettings(frameCount: 5, step: 1))
        #expect(BracketShortcut(frameCount: 1, step: 0).bracket == BracketSettings(frameCount: 3, step: 1.0 / 3.0))
        #expect(BracketShortcut(frameCount: 4, step: 1.6).bracket == BracketSettings(frameCount: 3, step: 2))
        #expect(BracketShortcut(frameCount: 99, step: 9).bracket == BracketSettings(frameCount: 7, step: 2))
        #expect(BracketShortcut(frameCount: 3, step: 0.7).bracket.step == 2.0 / 3.0)
        let delayed = BracketShortcut(frameCount: 3, step: 1, delaySeconds: 500, lensKind: .wide)
        #expect(delayed.delaySeconds == PhotoShortcut.maximumDelaySeconds)
        #expect(delayed.lensKind == .wide)
        #expect(BracketShortcut(frameCount: 3, step: 1, delaySeconds: -1).delaySeconds == 0)
        #expect(ShortcutRequest.takeBracket(delayed).outcomeWithoutCameraScreen == nil)
    }

    /// A started manual-capable camera that has reported an exposure.
    func makeBracketModel(
        enabled: Bool = false, lenses: [Lens] = [ManualFixtures.wide],
        sleep: @escaping @Sendable (Double) async throws -> Void = { _ in }
    ) async -> (CameraModel, ScriptedManualBackend) {
        let backend = ScriptedManualBackend(lenses: lenses)
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), sleep: sleep)
        await model.send(.start)
        if enabled { await model.send(.manual(.setEnabled(true))) }
        await model.manual.record(ManualFixtures.reading)
        return (model, backend)
    }

    @Test func takesABracketOnceInFullAutoWithoutChangingSettings() async {
        let (model, backend) = await makeBracketModel()
        let outcome = await run(.takeBracket(BracketShortcut(frameCount: 3, step: 1)), on: model)
        #expect(outcome == .savedSeveral(allSigned: false))
        let frames = await backend.brackets
        #expect(frames.count == 1)
        #expect(frames.first?.count == 3)
        #expect(model.manual.bracket == nil)
        #expect(!model.manual.isEnabled)
        // The next shutter press takes one photo again.
        await model.send(.capture)
        #expect(await backend.brackets.count == 1)
        #expect(await backend.captureCount == 1)
    }

    @Test func aBracketRequestLeavesThePersonsBracketAsItIs() async {
        let (model, backend) = await makeBracketModel(enabled: true)
        let chosen = BracketSettings(frameCount: 5, step: 2.0 / 3.0)
        await model.send(.manual(.setBracket(chosen)))
        #expect(await run(.takeBracket(BracketShortcut(frameCount: 3, step: 1)), on: model) == .savedSeveral(allSigned: false))
        #expect(await backend.brackets.last?.count == 3)
        #expect(model.manual.bracket == chosen)
    }

    @Test func aBracketTheLensCanNotTakeIsReported() async {
        // The wide fixture takes at most 5 frames; the bare lens has no manual exposure.
        let (model, backend) = await makeBracketModel()
        #expect(await run(.takeBracket(BracketShortcut(frameCount: 7, step: 1)), on: model) == .bracketUnavailable)
        #expect(model.manual.bracketFrames(once: BracketSettings(frameCount: 7, step: 1)) == nil)
        #expect(model.manual.bracketFrames(once: BracketSettings(frameCount: 3, step: 1))?.count == 3)
        let (bare, _) = await makeBracketModel(lenses: [ManualFixtures.bare])
        #expect(await run(.takeBracket(BracketShortcut(frameCount: 3, step: 1)), on: bare) == .bracketUnavailable)
        #expect(await backend.brackets.isEmpty)
        #expect(await backend.captureCount == 0)
    }

    @Test func aBracketWaitsForAnExposureReading() async {
        let backend = ScriptedManualBackend(lenses: [ManualFixtures.wide])
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.start)
        // The reading never comes, and the timeout passes at once.
        let outcome = await run(
            .takeBracket(BracketShortcut(frameCount: 3, step: 1)), on: model, inbox: ShortcutInbox(sleep: { _ in }))
        #expect(outcome == .cameraUnavailable(.notRunning))
        #expect(await backend.brackets.isEmpty)
        #expect(model.manual.bracketFrames(once: BracketSettings(frameCount: 3, step: 1)) == nil)
    }

    @Test func aBracketAfterADelayAndOnAnotherLens() async {
        let ticker = Ticker()
        let (model, backend) = await makeBracketModel(
            lenses: [ManualFixtures.wide, ManualFixtures.basicLens], sleep: { _ in await ticker.sleep() })
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        let server = Task { await model.serveShortcuts(from: inbox) }
        defer { server.cancel() }
        await waitUntil { inbox.isServed }
        let request = Task {
            await inbox.submit(.takeBracket(BracketShortcut(frameCount: 3, step: 1, delaySeconds: 1, lensKind: .ultraWide)))
        }
        // Switching lenses clears the last reading; the new lens reports its own.
        await waitUntil { model.selectedLens?.kind == .ultraWide && model.sessionStatus == .running }
        await model.manual.record(ManualFixtures.reading)
        await waitUntil { model.drive.countdown.isRunning }
        #expect(model.selectedLens?.kind == .ultraWide)
        await tick(ticker)
        #expect(await request.value == .savedSeveral(allSigned: false))
        #expect(await backend.brackets.count == 1)
    }

    @Test func aBracketRequestIsBusyDuringACountdownAndChecksTheLens() async {
        let ticker = Ticker()
        let (model, _) = await makeBracketModel(sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.startTimer(seconds: 5)))
        #expect(await run(.takeBracket(BracketShortcut(frameCount: 3, step: 1)), on: model) == .busy)
        model.drive.countdown.cancel()
        #expect(await run(.takeBracket(BracketShortcut(frameCount: 3, step: 1, lensKind: .front)), on: model) == .lensUnavailable)
        let denied = await makeModel(ScriptedBackend(permission: .denied, capabilities: CameraModelTests.oneLens))
        #expect(await run(.takeBracket(BracketShortcut(frameCount: 3, step: 1)), on: denied) == .cameraUnavailable(.permissionDenied))
    }

    // MARK: - Without a camera screen

    @Test func requestsThatNeedNoCameraEndAtOnceWithoutACameraScreen() async {
        // The timeouts never pass: a request that waited would never end.
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        #expect(!inbox.isServed)
        #expect(await inbox.submit(.setLight(isOn: false)) == .lightOff)
        #expect(await inbox.submit(.stopInterval) == .noIntervalRunning)
        let waiting: [ShortcutRequest] = [
            .takePhoto(PhotoShortcut()), .selectLens(.wide), .setLight(isOn: true), .startInterval(IntervalShortcut()),
        ]
        #expect(waiting.allSatisfy { $0.outcomeWithoutCameraScreen == nil })
    }

    @Test func theInboxKnowsWhenACameraScreenServesIt() async {
        let model = await makeModel()
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        let server = Task { await model.serveShortcuts(from: inbox) }
        await waitUntil { inbox.isServed }
        #expect(inbox.isServed)
        // With a camera screen, turning the light off is performed by it.
        #expect(await inbox.submit(.setLight(isOn: false)) == .lightOff)
        #expect(inbox.isServed)
        server.cancel()
        await waitUntil { !inbox.isServed }
        #expect(!inbox.isServed)
    }

    // MARK: - Focus range

    @Test func setsTheFocusRange() async {
        let backend = ScriptedManualBackend(lenses: [AutoFixtures.handheld])
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.start)
        #expect(await run(.setFocusRange(.closeUp), on: model) == .focusRangeSet(.closeUp))
        #expect(model.manual.nearFocusLimit && !model.manual.farFocusLimit)
        #expect(await run(.setFocusRange(.far), on: model) == .focusRangeSet(.far))
        #expect(model.manual.farFocusLimit && !model.manual.nearFocusLimit)
        #expect(await run(.setFocusRange(.unlimited), on: model) == .focusRangeSet(.unlimited))
        #expect(!model.manual.farFocusLimit && !model.manual.nearFocusLimit)
        // Manual values stay as they were.
        #expect(model.manual.settings == .automatic)
        #expect(!model.manual.isEnabled)
    }

    @Test func aLensThatCanNotLimitItsFocusSaysSo() async {
        let (model, _) = await makeManualModel(enabled: false)
        #expect(await run(.setFocusRange(.closeUp), on: model) == .focusRangeUnavailable)
        #expect(await run(.setFocusRange(.far), on: model) == .focusRangeUnavailable)
        #expect(!model.manual.nearFocusLimit && !model.manual.farFocusLimit)
        let denied = await makeModel(ScriptedBackend(permission: .denied, capabilities: CameraModelTests.oneLens))
        #expect(await run(.setFocusRange(.closeUp), on: denied) == .cameraUnavailable(.permissionDenied))
        #expect(ShortcutRequest.setFocusRange(.far).outcomeWithoutCameraScreen == nil)
    }

    // MARK: - Photo size

    /// A camera with a RAW wide lens and a front lens without RAW that offers two sizes.
    func makeSizeModel(
        sleep: @escaping @Sendable (Double) async throws -> Void = { _ in }
    ) async -> (CameraModel, NopeSettings) {
        let front = CaptureSettingValueTests.fallbackLens
        let capabilities = DeviceCapabilities(lenses: [CameraModelTests.wideRAW, front])
        let model = CameraModel(backend: ScriptedBackend(capabilities: capabilities), saver: CameraModelTests.saver(), sleep: sleep)
        await model.send(.start)
        let store = UserDefaults(suiteName: "ShortcutTests.photoSize.\(UUID().uuidString)")!
        return (model, NopeSettings(defaults: store))
    }

    /// Submits a request to a camera screen that serves the inbox with the settings.
    func run(_ request: ShortcutRequest, on model: CameraModel, settings: NopeSettings?) async -> ShortcutOutcome {
        let inbox = ShortcutInbox(sleep: Self.neverTimesOut)
        let server = Task { await model.serveShortcuts(from: inbox, settings: settings) }
        defer { server.cancel() }
        await waitUntil { inbox.isServed }
        return await inbox.submit(request)
    }

    @Test func choosesALensPhotoSize() async {
        let (model, settings) = await makeSizeModel()
        let front = CaptureSettingValueTests.fallbackLens
        let largest = PhotoSizeShortcut(lensKind: .front, size: .largest)
        #expect(largest.dimensions(on: front) == CaptureSettingValueTests.large)
        #expect(await run(.setPhotoSize(largest), on: model, settings: settings) == .photoSizeSet)
        #expect(settings.photoSize(for: front) == CaptureSettingValueTests.large)
        let standard = PhotoSizeShortcut(lensKind: .front, size: .standard)
        #expect(await run(.setPhotoSize(standard), on: model, settings: settings) == .photoSizeSet)
        #expect(settings.photoSizes.isEmpty)
        #expect(ShortcutRequest.setPhotoSize(standard).outcomeWithoutCameraScreen == nil)
    }

    @Test func aLensWithOneSizeOrNoSettingsSaysThereIsNoChoice() async {
        let (model, settings) = await makeSizeModel()
        // The lens in use, the wide lens with Bayer RAW, always takes its full-size RAW.
        let inUse = PhotoSizeShortcut(size: .largest)
        #expect(inUse.dimensions(on: CameraModelTests.wideRAW) == nil)
        #expect(await run(.setPhotoSize(inUse), on: model, settings: settings) == .noPhotoSizeChoice)
        let front = PhotoSizeShortcut(lensKind: .front, size: .largest)
        #expect(await run(.setPhotoSize(front), on: model, settings: nil) == .noPhotoSizeChoice)
        #expect(await run(.setPhotoSize(PhotoSizeShortcut(lensKind: .telephoto, size: .largest)), on: model, settings: settings)
            == .lensUnavailable)
        #expect(settings.photoSizes.isEmpty)
    }

    @Test func aPhotoSizeWaitsForARunningCountdownAndNeedsTheCamera() async {
        let ticker = Ticker()
        let (model, settings) = await makeSizeModel(sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.startTimer(seconds: 5)))
        let front = PhotoSizeShortcut(lensKind: .front, size: .largest)
        #expect(await run(.setPhotoSize(front), on: model, settings: settings) == .busy)
        model.drive.countdown.cancel()
        #expect(settings.photoSizes.isEmpty)
        let denied = await makeModel(ScriptedBackend(permission: .denied, capabilities: CameraModelTests.oneLens))
        #expect(await run(.setPhotoSize(front), on: denied, settings: settings) == .cameraUnavailable(.permissionDenied))
    }
}
