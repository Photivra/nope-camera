import Foundation

/// Requests from Siri and Shortcuts (issue #62), performed with the same intents as the camera
/// screen's own controls.
extension CameraModel {
    /// Performs each request from the inbox in turn, until the calling task is cancelled. Run it
    /// for as long as the camera screen is shown, for example in a SwiftUI `.task`.
    ///
    /// Side effects: as ``CameraIntent/capture`` and ``CameraIntent/selectLens(_:)``; a request
    /// may switch the lens, start the self-timer, take a photo and add it to Photos.
    ///
    /// - Parameter inbox: Where the app's App Intents leave their requests.
    public func serveShortcuts(from inbox: ShortcutInbox) async {
        while let pending = await inbox.next() {
            pending.finish(await perform(pending.request, inbox: inbox))
        }
    }

    /// Performs one request.
    ///
    /// - Parameters:
    ///   - request: What was asked for.
    ///   - inbox: The inbox, for its waits and timeouts.
    /// - Returns: How it ended.
    func perform(_ request: ShortcutRequest, inbox: ShortcutInbox) async -> ShortcutOutcome {
        switch request {
        case .takePhoto(let photo): await takePhoto(photo, inbox: inbox)
        case .takeBracket(let bracket): await takeBracket(bracket, inbox: inbox)
        case .selectLens(let kind): await selectLens(kind, inbox: inbox)
        case .setLight(let isOn): await setLight(isOn, inbox: inbox)
        case .startInterval(let series): await startInterval(series, inbox: inbox)
        case .stopInterval: await stopInterval()
        }
    }

    /// Takes the photos for a request: waits for the camera, switches the lens if asked, then
    /// takes them at once or after the self-timer.
    ///
    /// The request's count decides what is taken, whatever the drive mode: one photo (a bracket
    /// that is on in the manual controls still applies, as it does to the shutter), or a burst
    /// of exactly that many frames through the burst's own loop (`takeBurst(frames:)`).
    ///
    /// - Parameters:
    ///   - photo: The request's delay, lens and count.
    ///   - inbox: The inbox, for its waits and timeouts.
    /// - Returns: How it ended.
    private func takePhoto(_ photo: PhotoShortcut, inbox: ShortcutInbox) async -> ShortcutOutcome {
        if let problem = await prepareCamera(lensKind: photo.lensKind, inbox: inbox) { return problem }
        guard canCapture, !isRunningSeries else { return .busy }
        let before = captureStatus
        if photo.delaySeconds == 0 {
            await takeShortcutPhotos(count: photo.count)
            return outcome(of: captureStatus)
        }
        startTimer(seconds: photo.delaySeconds) { [weak self] in await self?.takeShortcutPhotos(count: photo.count) }
        return await outcomeAfterCountdown(since: before, inbox: inbox)
    }

    /// Waits for the camera and switches to the lens a request asks for, if any.
    ///
    /// - Parameters:
    ///   - lensKind: The kind of lens, or `nil` to keep the lens in use.
    ///   - inbox: The inbox, for its waits and timeouts.
    /// - Returns: The outcome that ends the request when the camera can't be used or has no such
    ///   lens, otherwise `nil`.
    private func prepareCamera(lensKind: Lens.Kind?, inbox: ShortcutInbox) async -> ShortcutOutcome? {
        if let problem = await cameraProblem(inbox: inbox) { return .cameraUnavailable(problem) }
        guard let kind = lensKind, selectedLens?.kind != kind else { return nil }
        guard let lens = capabilities?.lenses.first(where: { $0.kind == kind }) else { return .lensUnavailable }
        await send(.selectLens(lens.id))
        if let problem = await cameraProblem(inbox: inbox) { return .cameraUnavailable(problem) }
        return nil
    }

    /// Waits for a self-timer a request started, then for its photos, and reports how it ended.
    ///
    /// - Parameters:
    ///   - before: The capture status before the countdown started.
    ///   - inbox: The inbox, for its waits.
    /// - Returns: How it ended: cancelled, the camera stopped, or the photos' outcome.
    private func outcomeAfterCountdown(since before: CaptureStatus, inbox: ShortcutInbox) async -> ShortcutOutcome {
        _ = await inbox.wait { !self.drive.countdown.isRunning }
        guard isTakingPhoto || captureStatus != before else {
            return sessionStatus.canCapture ? .cancelled : .cameraUnavailable(.notRunning)
        }
        _ = await inbox.wait { !self.isTakingPhoto }
        return outcome(of: captureStatus)
    }

    /// Takes one photo or a burst of `count` frames at once.
    ///
    /// - Parameter count: How many photos.
    private func takeShortcutPhotos(count: Int) async {
        if count == 1 {
            await capture()
        } else {
            await takeBurst(frames: count)
        }
    }

    /// How long a bracket request waits for the camera's first exposure reading, which the
    /// bracket's frames are planned around, in seconds. An assumption, to be confirmed on a
    /// device: the camera reports readings several times a second once it runs.
    static let bracketReadingTimeoutSeconds: Double = 2

    /// Takes one exposure bracket for a request: waits for the camera, switches the lens if
    /// asked, then takes the bracket at once or after the self-timer, through the same bracket
    /// path as the shutter (`capture(onceBracket:)`). The bracket chosen in Pro Tools, and every
    /// other setting, stays as it is.
    ///
    /// - Parameters:
    ///   - request: The request's frames, step, delay and lens.
    ///   - inbox: The inbox, for its waits and timeouts.
    /// - Returns: How it ended.
    private func takeBracket(_ request: BracketShortcut, inbox: ShortcutInbox) async -> ShortcutOutcome {
        if let problem = await prepareCamera(lensKind: request.lensKind, inbox: inbox) { return problem }
        let bracket = request.bracket
        guard manual.canBracket(bracket) else { return .bracketUnavailable }
        guard canCapture, !isRunningSeries else { return .busy }
        // The frames are planned around the camera's exposure, which arrives with its readings.
        guard await inbox.wait(timeoutSeconds: Self.bracketReadingTimeoutSeconds, until: { self.manual.bracketFrames(once: bracket) != nil })
        else { return .cameraUnavailable(.notRunning) }
        let before = captureStatus
        if request.delaySeconds == 0 {
            await capture(onceBracket: bracket)
            return outcome(of: captureStatus)
        }
        startTimer(seconds: request.delaySeconds) { [weak self] in await self?.capture(onceBracket: bracket) }
        return await outcomeAfterCountdown(since: before, inbox: inbox)
    }

    /// Switches to a lens of the kind asked for, as a lens button does.
    ///
    /// - Parameters:
    ///   - kind: The kind of lens.
    ///   - inbox: The inbox, for its waits and timeouts.
    /// - Returns: How it ended.
    private func selectLens(_ kind: Lens.Kind, inbox: ShortcutInbox) async -> ShortcutOutcome {
        if let problem = await cameraProblem(inbox: inbox) { return .cameraUnavailable(problem) }
        guard selectedLens?.kind != kind else { return .lensSelected(kind) }
        guard let lens = capabilities?.lenses.first(where: { $0.kind == kind }) else { return .lensUnavailable }
        // Switching restarts the camera, which would end a burst or a series part-way.
        guard !isTakingPhoto, !isRunningSeries else { return .busy }
        await send(.selectLens(lens.id))
        if let problem = await cameraProblem(inbox: inbox) { return .cameraUnavailable(problem) }
        return .lensSelected(kind)
    }

    /// Turns the light on or off with ``LightIntent/setTorch(_:)``, as the Light switch does.
    ///
    /// Turning it on waits for the camera, because the light works only while the camera runs;
    /// turning it off never needs to.
    ///
    /// - Parameters:
    ///   - isOn: Whether the light should be on.
    ///   - inbox: The inbox, for its waits and timeouts.
    /// - Returns: How it ended.
    private func setLight(_ isOn: Bool, inbox: ShortcutInbox) async -> ShortcutOutcome {
        guard isOn else {
            await send(.light(.setTorch(false)))
            return .lightOff
        }
        if let problem = await cameraProblem(inbox: inbox) { return .cameraUnavailable(problem) }
        guard light.supportsTorch else { return .noLight }
        await send(.light(.setTorch(true)))
        return light.isTorchOn ? .lightOn : .lightUnavailable
    }

    /// Starts an interval series with ``ManualControlIntent/startInterval``, as the shutter in
    /// the Interval drive mode and Start in Pro Tools do, after choosing the request's interval
    /// and count with ``ManualControlIntent/setInterval(_:)``. It runs in full auto, or with the
    /// manual settings while manual controls are on; it never turns them on.
    ///
    /// - Parameters:
    ///   - series: The request's interval and count.
    ///   - inbox: The inbox, for its waits and timeouts.
    /// - Returns: How it ended.
    private func startInterval(_ series: IntervalShortcut, inbox: ShortcutInbox) async -> ShortcutOutcome {
        if let problem = await cameraProblem(inbox: inbox) { return .cameraUnavailable(problem) }
        guard canCapture, !isRunningSeries else { return .busy }
        await send(.manual(.setInterval(series.settings(over: manual.interval))))
        await send(.manual(.startInterval))
        return .intervalStarted
    }

    /// Stops the running interval series with ``ManualControlIntent/stopInterval``.
    ///
    /// - Returns: How it ended.
    private func stopInterval() async -> ShortcutOutcome {
        guard manual.intervalProgress != nil else { return .noIntervalRunning }
        await send(.manual(.stopInterval))
        return .intervalStopped
    }

    /// Whether a countdown, a burst, an interval series or an astro run is in progress, so a
    /// request mustn't start another.
    private var isRunningSeries: Bool {
        drive.isBusy || manual.intervalProgress != nil || astro.isRunning
    }

    /// Whether a photo is being taken or saved.
    private var isTakingPhoto: Bool {
        captureStatus == .capturing || captureStatus == .saving
    }

    /// Waits for the camera to finish starting, at most ``ShortcutInbox/startTimeoutSeconds``,
    /// then says why it can't take a photo, if it can't.
    ///
    /// - Parameter inbox: The inbox, for its wait and timeout.
    /// - Returns: Why the camera can't take a photo, or `nil` when it can.
    private func cameraProblem(inbox: ShortcutInbox) async -> CameraUnavailability? {
        _ = await inbox.wait(timeoutSeconds: ShortcutInbox.startTimeoutSeconds) { !self.isStartingCamera }
        switch state {
        case .needsPermission: return .needsPermission
        case .permissionDenied: return .permissionDenied
        case .unavailable: return .noCamera
        case .starting: return .notRunning
        case .ready: return sessionStatus.canCapture ? nil : .notRunning
        }
    }

    /// Whether the camera is still checking access or starting a session.
    private var isStartingCamera: Bool {
        switch state {
        case .starting: true
        case .ready: sessionStatus == .stopped || sessionStatus == .starting
        default: false
        }
    }

    /// The outcome a capture status reports.
    ///
    /// - Parameter status: The status after the photo.
    /// - Returns: The outcome.
    func outcome(of status: CaptureStatus) -> ShortcutOutcome {
        switch status {
        case .saved(let photo): .saved(isSigned: photo.signature == .signed)
        case .savedBracket(let photos), .savedBurst(let photos):
            .savedSeveral(allSigned: photos.allSatisfy { $0.signature == .signed })
        case .failed(let error): .notSaved(error)
        case .idle, .capturing, .saving: .notSaved(.notRunning)
        }
    }
}
