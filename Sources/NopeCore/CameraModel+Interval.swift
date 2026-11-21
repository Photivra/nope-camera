import Foundation

/// Why an interval series can't start now (``CameraModel/intervalBlocker``).
public enum IntervalBlocker: Equatable, Sendable {
    /// The astro helper is on. Its frames and an interval series both take the camera for a long
    /// time, and the helper sets the exposure for the night sky, so one runs at a time: turn the
    /// helper off first.
    case astroIsOn

    /// The self-timer counts down or a burst runs. Wait until it ends.
    case driveIsBusy

    /// The series stops after a time, and the interval is as long as the time or longer, so it
    /// would take only one photo. Choose a shorter interval or a longer time
    /// (``IntervalSettings/isIntervalShorterThanTime``).
    case intervalNotShorterThanTime
}

/// The photos of an interval series (issue #48). ``ManualControlsModel`` holds the series; the
/// camera model takes each photo, and pauses the series as it pauses an astro run.
extension CameraModel {
    /// How long a photo of an astro run or an interval series that failed waits for a pause, in
    /// seconds, before the failure ends the run (`failureWasAPause()`).
    ///
    /// The camera reports a photo cut short by an interruption, and the interruption itself, on
    /// separate paths, and the app hears that it left the foreground from the interface, so the
    /// photo's error can arrive first. One second is an assumption to be checked on a device:
    /// long enough for those events, short enough that a real failure is reported at once.
    public static let pauseAfterErrorSeconds: Double = 1

    /// Why an interval series can't start now, or `nil` when it can as far as these rules go
    /// (the camera must also be able to take a photo, ``canCapture``). An interface disables
    /// Start and says why; ``CameraIntent/manual(_:)`` with
    /// ``ManualControlIntent/startInterval`` is ignored while it isn't `nil`.
    public var intervalBlocker: IntervalBlocker? {
        if astro.isOn { return .astroIsOn }
        if drive.isBusy { return .driveIsBusy }
        if !manual.interval.isIntervalShorterThanTime { return .intervalNotShorterThanTime }
        return nil
    }

    /// Takes one photo of the running interval series, the way the shutter does. While the
    /// series should pause (``seriesShouldPause``) it waits, marked as paused, instead of
    /// skipping the photo; it also waits while another photo is being taken or saved (such as
    /// the photo the shutter took just before the series started) or the compare view is open.
    /// A photo cut short by a pause is taken again after it.
    ///
    /// - Returns: ``IntervalPhotoOutcome/taken`` when the photo was taken and saved;
    ///   ``IntervalPhotoOutcome/timeUp`` when the series' time was up while it waited; otherwise
    ///   ``IntervalPhotoOutcome/failed``: the camera stopped for good, or the photo failed for
    ///   another reason (the camera says why). A stopped series is cancelled and ignores it.
    func takeIntervalPhoto() async -> IntervalPhotoOutcome {
        while await waitForIntervalPhoto() {
            guard canCapture else { return .failed }
            await capture()
            guard case .failed = captureStatus else { return .taken }
            guard await failureWasAPause() else { return .failed }
        }
        return manual.isIntervalTimeUp ? .timeUp : .failed
    }

    /// Whether the next interval photo has to wait: the series should pause, a photo is being
    /// taken or saved, or the compare view is open.
    private var intervalPhotoMustWait: Bool {
        seriesShouldPause || captureStatus == .capturing || captureStatus == .saving || comparison.isPresented
    }

    /// Waits until the next interval photo can be taken, with the series marked as paused while
    /// it should pause. It waits for Observation's change notifications; nothing polls
    /// (AGENTS.md, "Battery"). For a series that stops after a time, it also wakes when the time
    /// is up, so a series paused in the foreground (by a call, say) ends at its time.
    ///
    /// - Returns: `false` when the series was stopped while it waited, or its time is up.
    private func waitForIntervalPhoto() async -> Bool {
        while !Task.isCancelled, !manual.isIntervalTimeUp, intervalPhotoMustWait {
            let waiter = ChangeWaiter()
            let timeUp = wakeAtIntervalEnd(waiter)
            await withTaskCancellationHandler {
                while intervalPhotoMustWait, !waiter.isExpired {
                    manual.setIntervalPaused(seriesShouldPause)
                    await waiter.waitForChange { self.intervalPhotoMustWait }
                }
            } onCancel: {
                Task { @MainActor in waiter.expire() }
            }
            timeUp?.cancel()
        }
        // A stopped series is already gone.
        guard !Task.isCancelled, !manual.isIntervalTimeUp else { return false }
        // Only a running series is marked as running again.
        manual.setIntervalPaused(false)
        return true
    }

    /// Wakes a wait for the next interval photo when the running series' time is up.
    ///
    /// - Parameter waiter: The wait to wake.
    /// - Returns: The task that wakes it, to cancel when the wait ends, or `nil` for a series that
    ///   stops after a number of photos.
    private func wakeAtIntervalEnd(_ waiter: ChangeWaiter) -> Task<Void, Never>? {
        guard let deadline = manual.intervalProgress?.deadline else { return nil }
        return Task { [clock] in
            guard (try? await clock.sleep(deadline)) != nil else { return }
            waiter.expire()
        }
    }

    /// Whether a photo of an astro run or an interval series that failed was cut short by a
    /// pause: the run should pause now, or starts to within ``pauseAfterErrorSeconds``.
    ///
    /// - Returns: `true` when the run should pause, so the photo is taken again after the pause.
    func failureWasAPause() async -> Bool {
        let waiter = ChangeWaiter()
        let timeout = Task { [pauseAfterErrorSleep] in
            try? await pauseAfterErrorSleep()
            waiter.expire()
        }
        defer { timeout.cancel() }
        while !seriesShouldPause, !waiter.isExpired {
            await waiter.waitForChange { self.seriesShouldPause }
        }
        return seriesShouldPause
    }
}
