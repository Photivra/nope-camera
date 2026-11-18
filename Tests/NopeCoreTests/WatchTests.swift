import Foundation
import Testing

@testable import NopeCore

/// A fake of the iPhone app's WatchConnectivity link: records what it sends, and can be made
/// unreachable or failing.
@MainActor
final class FakeWatchLink: WatchLink {
    var isWatchReachable = true
    var delivers = true
    private(set) var sent: [PhoneUpdate] = []
    /// Called with each message delivered, for example to hand it to a `WatchRemote`.
    var onDelivery: ((Data) -> Void)?

    /// Whether each send waits until ``releaseOldest()``.
    var holdsSends = false
    private var holds: [CheckedContinuation<Void, Never>] = []
    var held: Int { holds.count }

    func releaseOldest() {
        holds.removeFirst().resume()
    }

    func send(_ message: Data) async -> Bool {
        // A real send suspends; so does this one.
        if holdsSends {
            await withCheckedContinuation { holds.append($0) }
        } else {
            await Task.yield()
        }
        guard delivers else { return false }
        sent.append(try! WatchMessageCoding.decodeUpdate(message))
        onDelivery?(message)
        return true
    }
}

/// A fake of the watch app's WatchConnectivity link: replies with a closure, or fails.
@MainActor
final class FakePhoneLink: PhoneLink {
    struct NotDelivered: Error {}

    var isPhoneReachable = true
    private(set) var sent: [WatchCommand] = []
    var reply: (Data) async throws -> Data

    init(reply: @escaping (Data) async throws -> Data) {
        self.reply = reply
    }

    convenience init(update: PhoneUpdate) {
        self.init { _ in WatchMessageCoding.encode(update) }
    }

    func send(_ message: Data) async throws -> Data {
        sent.append(try WatchMessageCoding.decodeCommand(message))
        return try await reply(message)
    }
}

/// The Apple Watch app's messages, the phone's command server and the watch's model (issue #63).
@MainActor
struct WatchTests {
    func makeModel(
        _ backend: ScriptedBackend = ScriptedBackend(capabilities: CameraModelTests.oneLens),
        sleep: @escaping @Sendable (Double) async throws -> Void = { _ in }, start: Bool = true
    ) async -> CameraModel {
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), sleep: sleep)
        if start { await model.send(.start) }
        return model
    }

    func update(_ data: Data) -> PhoneUpdate? {
        try? WatchMessageCoding.decodeUpdate(data)
    }

    // MARK: - Messages

    @Test(arguments: [WatchCommand.requestStatus, .takePhoto(delay: .none), .takePhoto(delay: .tenSeconds), .cancelTimer])
    func commandsRoundTrip(command: WatchCommand) throws {
        #expect(try WatchMessageCoding.decodeCommand(WatchMessageCoding.encode(command)) == command)
    }

    @Test(arguments: [
        PhoneUpdate(status: .ready),
        PhoneUpdate(status: .countingDown(secondsLeft: 3), result: nil),
        PhoneUpdate(status: .busy, result: .saved(isSigned: true)),
        PhoneUpdate(status: .unavailable(.permissionDenied), result: .notTaken(.noCamera)),
        PhoneUpdate(status: .ready, result: .savedSeveral(allSigned: false)),
        PhoneUpdate(status: .ready, result: .saved(isSigned: false), unsignedReason: .turnedOff),
        PhoneUpdate(status: .ready, result: .savedSeveral(allSigned: false), unsignedReason: .failed),
        PhoneUpdate(status: .ready, result: .cancelled),
        PhoneUpdate(status: .ready, result: .notUnderstood),
    ])
    func updatesRoundTrip(update: PhoneUpdate) throws {
        #expect(try WatchMessageCoding.decodeUpdate(WatchMessageCoding.encode(update)) == update)
    }

    /// The unsigned reason is optional, so an update from a phone app without it still decodes,
    /// and the reasons keep stable names in the message.
    @Test func anUpdateWithoutTheUnsignedReasonDecodes() throws {
        let older = Data(#"{"version":1,"body":{"status":{"ready":{}},"result":{"saved":{"isSigned":false}}}}"#.utf8)
        #expect(try WatchMessageCoding.decodeUpdate(older) == PhoneUpdate(status: .ready, result: .saved(isSigned: false)))
        let update = PhoneUpdate(status: .ready, result: .saved(isSigned: false), unsignedReason: .signedFileFailedCheck)
        let json = try JSONSerialization.jsonObject(with: WatchMessageCoding.encode(update)) as? [String: Any]
        let body = json?["body"] as? [String: Any]
        #expect(body?["unsignedReason"] as? String == "signedFileFailedCheck")
        #expect(SignatureStatus.UnsignedReason.allCases.map(\.rawValue) == ["turnedOff", "unavailable", "failed", "signedFileFailedCheck"])
    }

    @Test func theUnsignedReasonComesFromTheSavedPhotos() {
        func photo(_ signature: SignatureStatus) -> SavedPhoto {
            SavedPhoto(formats: [.raw], isProcessedFallback: false, signature: signature, metadata: [:])
        }
        typealias Reason = SignatureStatus.UnsignedReason
        #expect(Reason(photosOf: .saved(photo(.unsigned(.turnedOff)))) == .turnedOff)
        #expect(Reason(photosOf: .saved(photo(.signed))) == nil)
        // A photo that couldn't be signed wins over signing turned off.
        #expect(Reason(photosOf: .savedBracket([photo(.unsigned(.turnedOff)), photo(.unsigned(.failed))])) == .failed)
        #expect(Reason(photosOf: .savedBurst([photo(.signed), photo(.unsigned(.turnedOff))])) == .turnedOff)
        #expect(Reason(photosOf: .savedBurst([photo(.signed)])) == nil)
        for status in [CaptureStatus.idle, .capturing, .saving, .failed(.notRunning)] {
            #expect(Reason(photosOf: status) == nil)
        }
        #expect(WatchResult.saved(isSigned: false).includesUnsignedPhotos)
        #expect(WatchResult.savedSeveral(allSigned: false).includesUnsignedPhotos)
        #expect(!WatchResult.saved(isSigned: true).includesUnsignedPhotos)
        #expect(!WatchResult.cancelled.includesUnsignedPhotos)
    }

    @Test func delaysAreTheSelfTimersOrNone() {
        #expect(WatchDelay.allCases.map(\.seconds) == [0, 3, 10])
        #expect(WatchDelay.threeSeconds.seconds == SelfTimerDelay.threeSeconds.seconds)
        #expect(WatchDelay.tenSeconds.seconds == SelfTimerDelay.tenSeconds.seconds)
    }

    @Test func messagesCarryTheProtocolVersion() throws {
        let json = try JSONSerialization.jsonObject(with: WatchMessageCoding.encode(.requestStatus)) as? [String: Any]
        #expect(json?["version"] as? Int == WatchMessageCoding.version)
    }

    @Test func otherVersionsAndUnreadableMessagesThrow() {
        let future = Data(#"{"version":2,"body":{"requestStatus":{}}}"#.utf8)
        #expect(throws: WatchMessageError.otherVersion(2)) { try WatchMessageCoding.decodeCommand(future) }
        #expect(throws: WatchMessageError.unreadable) { try WatchMessageCoding.decodeCommand(Data("photo".utf8)) }
        let unknown = Data(#"{"version":1,"body":{"zoom":{}}}"#.utf8)
        #expect(throws: WatchMessageError.unreadable) { try WatchMessageCoding.decodeCommand(unknown) }
        // A command isn't an update.
        #expect(throws: WatchMessageError.unreadable) {
            try WatchMessageCoding.decodeUpdate(WatchMessageCoding.encode(.cancelTimer))
        }
    }

    // MARK: - The camera's status

    @Test(arguments: [
        (CameraPermission.notDetermined, WatchCameraProblem.needsPermission),
        (.denied, .permissionDenied),
        (.restricted, .permissionDenied),
    ])
    func permissionProblemsAreReported(permission: CameraPermission, problem: WatchCameraProblem) async {
        let model = await makeModel(ScriptedBackend(permission: permission, capabilities: CameraModelTests.oneLens))
        #expect(model.watchStatus == .unavailable(problem))
    }

    @Test func aDeviceWithoutACameraIsReported() async {
        let model = await makeModel(ScriptedBackend(capabilities: DeviceCapabilities(lenses: [])))
        #expect(model.watchStatus == .unavailable(.noCamera))
    }

    @Test func aCameraThatIsStartingOrPausedIsNotRunning() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend, start: false)
        #expect(model.watchStatus == .unavailable(.notRunning))
        await model.send(.start)
        #expect(model.watchStatus == .ready)
        let events = Task { await model.observeEvents() }
        defer { events.cancel() }
        backend.emit(.interrupted(.inUseElsewhere))
        await waitUntil { model.sessionStatus == .interrupted(.inUseElsewhere) }
        #expect(model.watchStatus == .unavailable(.notRunning))
    }

    @Test func countdownsPhotosAndBurstsAreReported() async {
        let ticker = Ticker()
        let model = await makeModel(sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.startTimer(seconds: 3)))
        #expect(model.watchStatus == .countingDown(secondsLeft: 3))
        model.drive.countdown.cancel()
        model.captureStatus = .capturing
        #expect(model.watchStatus == .busy)
        model.captureStatus = .saving
        #expect(model.watchStatus == .busy)
        model.captureStatus = .idle
        model.drive.beginBurst()
        #expect(model.watchStatus == .busy)
        model.drive.endBurst(.stopped)
        #expect(model.watchStatus == .ready)
        model.astro.beginRun()
        #expect(model.watchStatus == .busy)
    }

    @Test func outcomesBecomeResults() {
        #expect(WatchResult(ShortcutOutcome.saved(isSigned: true)) == .saved(isSigned: true))
        #expect(WatchResult(ShortcutOutcome.savedSeveral(allSigned: false)) == .savedSeveral(allSigned: false))
        #expect(WatchResult(ShortcutOutcome.notSaved(.saveFailed)) == .notSaved)
        let otherRequests: [ShortcutOutcome] = [
            .lensUnavailable, .lensSelected(.wide), .lightOn, .lightOff, .noLight, .lightUnavailable,
            .intervalStarted, .intervalBlockedByAstro, .intervalNotShorterThanTime, .intervalStopped, .noIntervalRunning,
            .bracketUnavailable, .focusRangeSet(.closeUp),
            .focusRangeUnavailable, .photoSizeSet, .noPhotoSizeChoice, .presetUnavailable,
            .presetApplied(PresetApplyResult(choice: .factoryDefaults, name: nil, isApplied: true, notices: [])),
        ]
        for outcome in otherRequests { #expect(WatchResult(outcome) == .notSaved) }
        #expect(WatchResult(ShortcutOutcome.cancelled) == .cancelled)
        #expect(WatchResult(ShortcutOutcome.busy) == .busy)
        #expect(WatchResult(ShortcutOutcome.cameraUnavailable(.needsPermission)) == .notTaken(.needsPermission))
        #expect(WatchResult(ShortcutOutcome.cameraUnavailable(.permissionDenied)) == .notTaken(.permissionDenied))
        #expect(WatchResult(ShortcutOutcome.cameraUnavailable(.noCamera)) == .notTaken(.noCamera))
        #expect(WatchResult(ShortcutOutcome.cameraUnavailable(.notRunning)) == .notTaken(.notRunning))
    }

    @Test func onlyAReadyCameraTakesAPhoto() {
        #expect(WatchResult(refusing: .ready) == nil)
        #expect(WatchResult(refusing: .countingDown(secondsLeft: 2)) == .busy)
        #expect(WatchResult(refusing: .busy) == .busy)
        #expect(WatchResult(refusing: .unavailable(.noCamera)) == .notTaken(.noCamera))
    }

    // MARK: - The phone's server

    @Test func answersAStatusRequest() async {
        let model = await makeModel()
        let server = WatchCommandServer(model: model, inbox: ShortcutInbox(), link: FakeWatchLink())
        let reply = update(await server.reply(to: WatchMessageCoding.encode(.requestStatus)))
        #expect(reply == PhoneUpdate(status: .ready))
        #expect(server.lastSentStatus == .ready)
    }

    @Test func answersAMessageItCannotReadWithNotUnderstood() async {
        let model = await makeModel()
        let server = WatchCommandServer(model: model, inbox: ShortcutInbox(), link: FakeWatchLink())
        let reply = update(await server.reply(to: Data("shutter".utf8)))
        #expect(reply == PhoneUpdate(status: .ready, result: .notUnderstood))
    }

    @Test func theReplyWithoutACameraScreenSaysTheCameraIsNotRunning() {
        #expect(update(WatchCommandServer.notServingReply) == PhoneUpdate(status: .unavailable(.notRunning)))
    }

    @Test func takesNothingWhenTheCameraIsNotReady() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend, start: false)
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let shortcuts = Task { await model.serveShortcuts(from: inbox) }
        defer { shortcuts.cancel() }
        let server = WatchCommandServer(model: model, inbox: inbox, link: FakeWatchLink())
        let reply = update(await server.reply(to: WatchMessageCoding.encode(.takePhoto(delay: .none))))
        #expect(reply == PhoneUpdate(status: .unavailable(.notRunning), result: .notTaken(.notRunning)))
        // Starting the camera later takes nothing.
        await model.send(.start)
        await settle()
        #expect(await backend.captureRequests.isEmpty)
    }

    @Test func aRunningCountdownMakesTheRequestBusy() async {
        let ticker = Ticker()
        let model = await makeModel(sleep: { _ in await ticker.sleep() })
        await model.send(.drive(.startTimer(seconds: 5)))
        let server = WatchCommandServer(model: model, inbox: ShortcutInbox(), link: FakeWatchLink())
        let reply = update(await server.reply(to: WatchMessageCoding.encode(.takePhoto(delay: .none))))
        #expect(reply == PhoneUpdate(status: .countingDown(secondsLeft: 5), result: .busy))
        model.drive.countdown.cancel()
    }

    @Test func takesAPhotoThroughTheInboxAndSendsTheResult() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend)
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let shortcuts = Task { await model.serveShortcuts(from: inbox) }
        defer { shortcuts.cancel() }
        let link = FakeWatchLink()
        let server = WatchCommandServer(model: model, inbox: inbox, link: link)
        let reply = update(await server.reply(to: WatchMessageCoding.encode(.takePhoto(delay: .none))))
        #expect(reply?.result == nil)
        await waitUntil { !link.sent.isEmpty }
        // Signing is off by default (issue #80), so the watch hears it is off by choice.
        #expect(link.sent == [PhoneUpdate(status: .ready, result: .saved(isSigned: false), unsignedReason: .turnedOff)])
        #expect(await backend.captureRequests.count == 1)
    }

    @Test func aDelayRunsThePhonesSelfTimer() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend, sleep: { _ in await ticker.sleep() })
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let shortcuts = Task { await model.serveShortcuts(from: inbox) }
        defer { shortcuts.cancel() }
        let link = FakeWatchLink()
        let server = WatchCommandServer(model: model, inbox: inbox, link: link)
        _ = await server.reply(to: WatchMessageCoding.encode(.takePhoto(delay: .threeSeconds)))
        await waitUntil { model.drive.countdown.remainingSeconds == 3 }
        #expect(model.watchStatus == .countingDown(secondsLeft: 3))
        #expect(await backend.captureRequests.isEmpty)
        for _ in 0..<3 { await tick(ticker) }
        await waitUntil { !link.sent.isEmpty }
        #expect(link.sent.last?.result == .saved(isSigned: false))
        #expect(await backend.captureRequests.count == 1)
    }

    @Test func theWatchCancelsTheCountdown() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend, sleep: { _ in await ticker.sleep() })
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let shortcuts = Task { await model.serveShortcuts(from: inbox) }
        defer { shortcuts.cancel() }
        let link = FakeWatchLink()
        let server = WatchCommandServer(model: model, inbox: inbox, link: link)
        _ = await server.reply(to: WatchMessageCoding.encode(.takePhoto(delay: .tenSeconds)))
        await waitUntil { model.drive.countdown.isRunning }
        let reply = update(await server.reply(to: WatchMessageCoding.encode(.cancelTimer)))
        #expect(reply?.status == .ready)
        await waitUntil { !link.sent.isEmpty }
        #expect(link.sent.last?.result == .cancelled)
        #expect(await backend.captureRequests.isEmpty)
        // Cancelling again, with no countdown, changes nothing.
        #expect(update(await server.reply(to: WatchMessageCoding.encode(.cancelTimer))) == PhoneUpdate(status: .ready))
    }

    @Test func aResultTheWatchMissedComesWithTheNextReply() async {
        let model = await makeModel()
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let shortcuts = Task { await model.serveShortcuts(from: inbox) }
        defer { shortcuts.cancel() }
        let link = FakeWatchLink()
        link.isWatchReachable = false
        let server = WatchCommandServer(model: model, inbox: inbox, link: link)
        _ = await server.reply(to: WatchMessageCoding.encode(.takePhoto(delay: .none)))
        await waitUntil { server.undeliveredResult != nil }
        #expect(link.sent.isEmpty)
        let reply = update(await server.reply(to: WatchMessageCoding.encode(.requestStatus)))
        #expect(reply == PhoneUpdate(status: .ready, result: .saved(isSigned: false), unsignedReason: .turnedOff))
        // It is given once.
        #expect(update(await server.reply(to: WatchMessageCoding.encode(.requestStatus)))?.result == nil)
    }

    @Test func aResultThatFailsToSendIsKept() async {
        let model = await makeModel()
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let shortcuts = Task { await model.serveShortcuts(from: inbox) }
        defer { shortcuts.cancel() }
        let link = FakeWatchLink()
        link.delivers = false
        let server = WatchCommandServer(model: model, inbox: inbox, link: link)
        _ = await server.reply(to: WatchMessageCoding.encode(.takePhoto(delay: .none)))
        await waitUntil { server.undeliveredResult != nil }
        #expect(server.undeliveredResult == .saved(isSigned: false))
        #expect(server.undeliveredUnsignedReason == .turnedOff)
    }

    @Test func sendsEachStatusChangeWhileTheWatchIsReachable() async {
        let ticker = Ticker()
        let model = await makeModel(sleep: { _ in await ticker.sleep() })
        let link = FakeWatchLink()
        let server = WatchCommandServer(model: model, inbox: ShortcutInbox(), link: link)
        let updates = Task { await server.sendStatusChanges() }
        await waitUntil { link.sent.count == 1 }
        #expect(link.sent == [PhoneUpdate(status: .ready)])
        await model.send(.drive(.startTimer(seconds: 2)))
        await waitUntil { link.sent.count == 2 }
        await tick(ticker)
        await waitUntil { link.sent.count == 3 }
        #expect(link.sent.map(\.status) == [.ready, .countingDown(secondsLeft: 2), .countingDown(secondsLeft: 1)])
        // Not reachable: nothing is sent.
        link.isWatchReachable = false
        model.drive.countdown.cancel()
        await settle()
        #expect(link.sent.count == 3)
        updates.cancel()
        await updates.value
    }

    @Test func aStatusThatFailsToSendIsSentAgainWithTheNextChange() async {
        let ticker = Ticker()
        let model = await makeModel(sleep: { _ in await ticker.sleep() })
        let link = FakeWatchLink()
        link.delivers = false
        link.holdsSends = true
        let server = WatchCommandServer(model: model, inbox: ShortcutInbox(), link: link)
        let updates = Task { await server.sendStatusChanges() }
        await waitUntil { link.held == 1 }
        #expect(server.lastSentStatus == .ready)
        await model.send(.drive(.startTimer(seconds: 2)))
        await waitUntil { link.held == 2 }
        // The first send fails after a newer status was sent: the newer one stays.
        link.releaseOldest()
        await settle()
        #expect(server.lastSentStatus == .countingDown(secondsLeft: 2))
        // The newer one fails too: it is forgotten, so the next change is sent.
        link.releaseOldest()
        await settle()
        #expect(server.lastSentStatus == nil)
        link.holdsSends = false
        link.delivers = true
        model.drive.countdown.cancel()
        await waitUntil { link.sent.count == 1 }
        #expect(link.sent == [PhoneUpdate(status: .ready)])
        updates.cancel()
        await updates.value
    }

    @Test func anAlreadyCancelledTaskStopsSendingAtOnce() async {
        let model = await makeModel()
        let server = WatchCommandServer(model: model, inbox: ShortcutInbox(), link: FakeWatchLink())
        let updates = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await server.sendStatusChanges()
        }
        await updates.value
    }

    // MARK: - The watch's model

    @Test func startsConnectingAndShowsThePhonesStatus() async {
        let remote = WatchRemote(link: FakePhoneLink(update: PhoneUpdate(status: .ready)))
        #expect(remote.display == .connecting)
        #expect(!remote.canTakePhoto)
        await remote.refresh()
        #expect(remote.display == .ready)
        #expect(remote.status == .ready)
        #expect(remote.canTakePhoto)
        #expect(!remote.canCancelTimer)
    }

    @Test(arguments: [
        (WatchStatus.countingDown(secondsLeft: 4), WatchRemote.Display.countingDown(secondsLeft: 4)),
        (.busy, .waiting),
        (.unavailable(.permissionDenied), .unavailable(.permissionDenied)),
    ])
    func showsEachStatus(status: WatchStatus, display: WatchRemote.Display) async {
        let remote = WatchRemote(link: FakePhoneLink(update: PhoneUpdate(status: status)))
        await remote.refresh()
        #expect(remote.display == display)
        #expect(!remote.canTakePhoto)
    }

    @Test func aPhoneThatIsNotReachableIsShown() async {
        let link = FakePhoneLink(update: PhoneUpdate(status: .ready))
        link.isPhoneReachable = false
        let remote = WatchRemote(link: link)
        await remote.refresh()
        #expect(remote.display == .phoneNotReachable)
        #expect(link.sent.isEmpty)
    }

    @Test func aFailedSendMarksThePhoneNotReachable() async {
        let remote = WatchRemote(link: FakePhoneLink { _ in throw FakePhoneLink.NotDelivered() })
        await remote.refresh()
        #expect(remote.display == .phoneNotReachable)
    }

    @Test func followsReachability() async {
        let link = FakePhoneLink(update: PhoneUpdate(status: .ready))
        let remote = WatchRemote(link: link)
        await remote.reachabilityChanged(isReachable: true)
        #expect(remote.display == .ready)
        await remote.reachabilityChanged(isReachable: false)
        #expect(remote.display == .phoneNotReachable)
        #expect(link.sent == [.requestStatus])
    }

    @Test func takesAPhotoWithTheDelayAndWaitsForTheResult() async {
        let link = FakePhoneLink(update: PhoneUpdate(status: .ready))
        let remote = WatchRemote(link: link)
        await remote.refresh()
        remote.delay = .threeSeconds
        await remote.takePhoto()
        #expect(link.sent.last == .takePhoto(delay: .threeSeconds))
        #expect(remote.isAwaitingResult)
        #expect(remote.display == .waiting)
        // Asking again while waiting sends nothing.
        await remote.takePhoto()
        #expect(link.sent.count == 2)
        remote.receive(WatchMessageCoding.encode(PhoneUpdate(status: .countingDown(secondsLeft: 3))))
        #expect(remote.display == .countingDown(secondsLeft: 3))
        #expect(remote.canCancelTimer)
        remote.receive(WatchMessageCoding.encode(PhoneUpdate(status: .ready, result: .saved(isSigned: true))))
        #expect(remote.lastResult == .saved(isSigned: true))
        #expect(remote.lastUnsignedReason == nil)
        #expect(remote.display == .ready)
        // The next photo clears the last result.
        await remote.takePhoto()
        #expect(remote.lastResult == nil)
        remote.receive(
            WatchMessageCoding.encode(PhoneUpdate(status: .ready, result: .saved(isSigned: false), unsignedReason: .turnedOff)))
        #expect(remote.lastResult == .saved(isSigned: false))
        #expect(remote.lastUnsignedReason == .turnedOff)
        await remote.takePhoto()
        #expect(remote.lastUnsignedReason == nil)
    }

    @Test func aRefusalEndsTheWaitAtOnce() async {
        var replies = [PhoneUpdate(status: .ready), PhoneUpdate(status: .unavailable(.notRunning), result: .notTaken(.notRunning))]
        let link = FakePhoneLink { _ in WatchMessageCoding.encode(replies.removeFirst()) }
        let remote = WatchRemote(link: link)
        await remote.refresh()
        await remote.takePhoto()
        #expect(remote.lastResult == .notTaken(.notRunning))
        #expect(!remote.isAwaitingResult)
        #expect(remote.display == .unavailable(.notRunning))
    }

    @Test func cancelsOnlyARunningCountdown() async {
        let link = FakePhoneLink(update: PhoneUpdate(status: .ready))
        let remote = WatchRemote(link: link)
        await remote.cancelTimer()
        #expect(link.sent.isEmpty)
        remote.receive(WatchMessageCoding.encode(PhoneUpdate(status: .countingDown(secondsLeft: 9))))
        await remote.cancelTimer()
        #expect(link.sent == [.cancelTimer])
        #expect(remote.display == .ready)
    }

    @Test func anUpdateItCannotReadSaysToUpdateTheApps() async {
        let remote = WatchRemote(link: FakePhoneLink { _ in Data("{}".utf8) })
        await remote.refresh()
        #expect(remote.lastResult == .notUnderstood)
        #expect(remote.display == .ready)
    }

    @Test func aPhoneLostWhileWaitingEndsTheWait() async {
        let link = FakePhoneLink(update: PhoneUpdate(status: .ready))
        let remote = WatchRemote(link: link)
        await remote.refresh()
        await remote.takePhoto()
        await remote.reachabilityChanged(isReachable: false)
        #expect(!remote.isAwaitingResult)
        #expect(remote.display == .phoneNotReachable)
    }

    // MARK: - Both sides together

    @Test func theWatchTakesAPhotoOnThePhone() async {
        let ticker = Ticker()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await makeModel(backend, sleep: { _ in await ticker.sleep() })
        let inbox = ShortcutInbox(sleep: ShortcutTests.neverTimesOut)
        let shortcuts = Task { await model.serveShortcuts(from: inbox) }
        defer { shortcuts.cancel() }
        let watchLink = FakeWatchLink()
        let server = WatchCommandServer(model: model, inbox: inbox, link: watchLink)
        let remote = WatchRemote(link: FakePhoneLink { await server.reply(to: $0) })
        watchLink.onDelivery = { remote.receive($0) }
        let updates = Task { await server.sendStatusChanges() }
        defer { updates.cancel() }
        await remote.refresh()
        remote.delay = .threeSeconds
        await remote.takePhoto()
        await waitUntil { remote.display == .countingDown(secondsLeft: 3) }
        #expect(remote.display == .countingDown(secondsLeft: 3))
        for _ in 0..<3 { await tick(ticker) }
        await waitUntil { remote.lastResult != nil }
        #expect(remote.lastResult == .saved(isSigned: false))
        await waitUntil { remote.display == .ready }
        #expect(remote.display == .ready)
        #expect(await backend.captureRequests.count == 1)
    }
}
