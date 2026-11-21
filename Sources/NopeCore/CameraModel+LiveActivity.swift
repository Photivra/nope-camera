import Foundation

/// What the Live Activity shows (issue #64): see ``LiveActivityCoordinator``.
extension CameraModel {
    /// Whether photos are being taken or saved: a photo, a bracket, a burst or astro frames that
    /// aren't paused. When the app leaves the foreground then, it asks iOS for time to finish
    /// saving them (``BackgroundTimeRequesting``); a paused astro run has saved every frame taken.
    public var isFinishingPhotos: Bool {
        guard !astro.isPaused, bracketing.progress?.isPaused != true else { return false }
        return captureStatus == .capturing || captureStatus == .saving || drive.burstProgress != nil || astro.isRunning
    }

    /// The Live Activity's content for what runs now, or `nil` when nothing runs that it shows.
    ///
    /// An interval series, astro frames, a burst and the self-timer each have content while they
    /// run. Out of the foreground the camera stops, so a running interval series or astro run is
    /// ``LiveActivityContent/Phase/paused`` (it continues when the app is open again; both are
    /// paused in the foreground too while the camera is), and a running burst is
    /// ``LiveActivityContent/Phase/saving`` (the frames already taken are being saved). The self-timer's photo keeps the timer's content while it is
    /// taken and saved.
    ///
    /// - Parameters:
    ///   - kind: The kind of the activity already shown, or `nil`.
    ///   - isInForeground: Whether the app is in the foreground.
    ///   - now: The wall clock's date now, which the dates of a countdown's end and a timed
    ///     series' time are counted from; the time left is measured on ``clock``.
    /// - Returns: The content, without night mode (the coordinator adds it).
    public func liveActivityContent(
        continuing kind: LiveActivityContent.Kind?, isInForeground: Bool, now: Date
    ) -> LiveActivityContent? {
        if let progress = manual.intervalProgress {
            return LiveActivityContent(
                kind: .interval, phase: isInForeground && !progress.isPaused ? .running : .paused, taken: progress.taken,
                total: progress.total, seriesTime: progress.timeSpan(date: now, now: clock.now()))
        }
        if let progress = astro.progress {
            return LiveActivityContent(
                kind: .astro, phase: isInForeground && !astro.isPaused ? .running : .paused, taken: progress.taken,
                total: astro.frameCount, saved: progress.saved)
        }
        if let progress = bracketing.progress {
            return LiveActivityContent(
                kind: .focusBracket, phase: isInForeground && !progress.isPaused ? .running : .paused,
                taken: progress.taken, total: progress.total, saved: progress.saved)
        }
        if let progress = drive.burstProgress {
            return LiveActivityContent(
                kind: .burst, phase: isInForeground ? .running : .saving, taken: progress.taken, saved: progress.saved)
        }
        if let deadline = drive.countdown.deadline {
            // A focus bracket's start delay is the bracket's own, so its Stop is offered then too.
            let kind: LiveActivityContent.Kind = astro.isOn ? .astro : bracketing.isFocusOn ? .focusBracket : .timer
            let total = kind == .astro ? astro.frameCount : kind == .focusBracket ? bracketing.focus.frameCount : nil
            return LiveActivityContent(
                kind: kind, phase: .countingDown, total: total,
                countdownEnd: now.addingTimeInterval((deadline - clock.now()) / .seconds(1)))
        }
        if kind == .timer, captureStatus == .capturing || captureStatus == .saving {
            return LiveActivityContent(kind: .timer, phase: captureStatus == .capturing ? .running : .saving, taken: 1)
        }
        return nil
    }

    /// The final content of an activity whose run has ended: how it ended, how many photos were
    /// saved and whether they are signed.
    ///
    /// The model doesn't keep every run's result, so an ended interval series and a self-timer
    /// are judged from the last content shown. That content is current when the app is out of
    /// the foreground, the only time an activity is on screen: the camera has stopped, so nothing
    /// changes unseen.
    ///
    /// - Parameter last: The content shown last.
    /// - Returns: The final content.
    public func liveActivityOutcome(after last: LiveActivityContent) -> LiveActivityContent {
        var outcome = last
        outcome.countdownEnd = nil
        if last.phase == .countingDown {
            // The countdown was cancelled before the photo or the first frame.
            outcome.phase = .stopped
            return outcome
        }
        switch last.kind {
        case .interval where last.seriesTime != nil:
            // A series that stops after a time ends when its time is up, however many photos it took.
            outcome.phase = manual.lastIntervalEnd == .finished ? .finished : .stopped
        case .interval:
            outcome.phase = last.taken >= (last.total ?? 0) ? .finished : .stopped
        case .astro:
            apply(astro.lastRun, finishesWhenStopped: false, to: &outcome)
        case .burst:
            apply(drive.lastBurst, finishesWhenStopped: true, to: &outcome)
        case .timer:
            applyTimerResult(to: &outcome)
        case .focusBracket:
            applyFocusBracketResult(to: &outcome)
        }
        return outcome
    }

    /// Fills in how a burst or astro run ended.
    ///
    /// - Parameters:
    ///   - result: How the run ended, or `nil` if it never started.
    ///   - finishesWhenStopped: Whether the person stopping the run is its planned end, as it is
    ///     for a burst, which runs until the shutter is let go.
    ///   - outcome: The content to change.
    private func apply(_ result: BurstResult?, finishesWhenStopped: Bool, to outcome: inout LiveActivityContent) {
        guard let result else {
            outcome.phase = .stopped
            return
        }
        outcome.saved = result.saved
        outcome.signing = signingOfSavedPhotos
        switch result.end {
        case .failed: outcome.phase = .failed
        case .limitReached, .countReached: outcome.phase = .finished
        case .stopped: outcome.phase = finishesWhenStopped ? .finished : .stopped
        case .storageFull, .cameraStopped, .batteryLow: outcome.phase = .stopped
        }
    }

    /// Fills in how a focus bracket ended: finished when every frame was saved, failed when a
    /// frame couldn't be taken or saved, otherwise stopped.
    ///
    /// - Parameter outcome: The content to fill in.
    private func applyFocusBracketResult(to outcome: inout LiveActivityContent) {
        guard let result = bracketing.lastRun else {
            outcome.phase = .stopped
            return
        }
        outcome.saved = result.saved
        outcome.signing = signingOfSavedPhotos
        outcome.phase = result.end == .failed ? .failed : result.isFinished ? .finished : .stopped
    }

    /// Fills in how the self-timer's photo ended.
    ///
    /// - Parameter outcome: The content to change.
    private func applyTimerResult(to outcome: inout LiveActivityContent) {
        switch captureStatus {
        case .saved, .savedBracket, .savedBurst:
            outcome.phase = .finished
            outcome.saved = savedPhotos.count
            outcome.signing = signingOfSavedPhotos
        case .failed:
            outcome.phase = .failed
        case .idle, .capturing, .saving:
            outcome.phase = .stopped
            outcome.saved = 0
        }
    }

    /// The photos the last capture saved: one, a bracket, a burst or astro frames.
    private var savedPhotos: [SavedPhoto] {
        switch captureStatus {
        case .saved(let photo): [photo]
        case .savedBracket(let photos), .savedBurst(let photos): photos
        case .idle, .capturing, .saving, .failed: []
        }
    }

    /// Whether the photos the last capture saved are all signed, or `nil` when it saved none.
    /// Signing turned off by the person is reported as such only when it is why every photo is
    /// unsigned: a photo that couldn't be signed must not read as the person's choice.
    private var signingOfSavedPhotos: LiveActivityContent.Signing? {
        let photos = savedPhotos
        guard !photos.isEmpty else { return nil }
        if photos.allSatisfy({ $0.signature == .signed }) { return .allSigned }
        return photos.allSatisfy { $0.signature == .unsigned(.turnedOff) } ? .off : .notAllSigned
    }
}
