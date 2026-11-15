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
}
