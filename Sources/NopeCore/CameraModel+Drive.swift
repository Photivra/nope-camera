import Foundation

/// The shutter's drive modes: single, the self-timer and bursts (issues #37, #39 and #46).
extension CameraModel {
    /// Whether the shutter should be enabled: a photo can be taken now, or a countdown, burst,
    /// interval series or astro run runs, which pressing the shutter stops. Not while a burst's
    /// last photos are being saved: a new burst waits for them (docs/design/BURST.md, decision 9).
    /// In the Interval drive mode, not while the interval is as long as the series' time or
    /// longer (``IntervalBlocker/intervalNotShorterThanTime``): the shutter would start nothing.
    public var canPressShutter: Bool {
        if drive.burstProgress?.isSaving == true { return false }
        if drive.isBusy || astro.isRunning || manual.intervalProgress != nil || bracketing.isRunning { return true }
        let startsNoSeries = drive.mode == .interval && intervalBlocker == .intervalNotShorterThanTime
        return canCapture && !startsNoSeries
    }

    /// Whether the shutter's photos can fire the flash. Not in Burst (docs/design/BURST.md,
    /// 3.1: "No flash in Burst, for one photo or many"), not with a bracket on
    /// (`AVCapturePhotoBracketSettings` takes no flash; ``CaptureRequest/flashMode``), and not
    /// with the astro helper on, whose frames are taken without it as a burst's are
    /// (`takeFrames`).
    ///
    /// An interface shows the flash control and its state only while this is `true` (issue #92,
    /// docs/design/SETTING-SCOPE.md, 6). The person's choice (``LightModel/flashMode``) is kept
    /// and is used again in the other modes.
    public var shutterUsesFlash: Bool {
        drive.mode != .burst && manual.bracket == nil && !bracketing.isFocusOn && !astro.isOn
    }

    /// The flash mode the shutter's next photo uses: ``LightModel/flashModeForCapture`` while
    /// the shutter can fire the flash (``shutterUsesFlash``), otherwise ``FlashMode/off``. What
    /// an interface shows as the flash in use, such as the Flash pill.
    public var flashModeForShutter: FlashMode {
        shutterUsesFlash ? light.flashModeForCapture : .off
    }

    /// Whether holding the shutter takes a burst (docs/design/BURST.md, 3.1): in Burst mode
    /// with the astro helper off, while no interval series or focus bracket runs. An interface
    /// reports the shutter's phases (``DriveIntent/shutter(_:)``) only while this is `true`, and
    /// sends ``CameraIntent/capture`` otherwise. While a series runs the shutter stops it, in
    /// every drive mode; that includes a focus bracket that Take Bracket started in Burst mode.
    public var isBurstShutter: Bool {
        drive.mode == .burst && !astro.isOn && manual.intervalProgress == nil && !bracketing.isRunning
    }

    /// The burst speeds offered on the selected lens: Fast, and Slow unless Fast measured under
    /// ``DriveModel/slowBurstMinimumFastRate`` on it in this session.
    public var burstSpeeds: [BurstSpeed] {
        drive.offersSlowBurst(on: selectedLensID) ? BurstSpeed.allCases : [.fast]
    }

    /// The speed a burst on the selected lens uses: the session's choice
    /// (``DriveModel/burstSpeed``) when the lens offers it, otherwise Fast.
    public var burstSpeed: BurstSpeed {
        burstSpeeds.contains(drive.burstSpeed) ? drive.burstSpeed : .fast
    }

    /// Whether the app should take the hardware shutter buttons (the volume buttons and the
    /// Camera Control): while the camera runs. At other times they keep their system behavior,
    /// as Apple asks of apps that can't respond to them (AVKit, `AVCaptureEventInteraction`,
    /// "isEnabled"). Not while the compare view is open (issue #55). While the Last Photo viewer
    /// is open (``isViewerOpen``) a press closes it and takes no photo.
    public var handlesHardwareButtons: Bool {
        sessionStatus.canCapture && !comparison.isPresented
    }

    /// The storage warning for the next photo with the selected lens and formats, or `nil`
    /// (issue #44). The photo's size is estimated with ``PhotoSizeEstimate``.
    public var storageWarning: StorageWarning? {
        guard let lens = selectedLens else { return nil }
        return deviceStatus.storageWarning(bytesPerPhoto: PhotoSizeEstimate.bytes(for: lens, settings: saveSettings))
    }

    /// What the shutter does: stops a running countdown, burst, focus bracket or interval
    /// series, or else applies the drive mode: one photo, the self-timer, a burst, a focus
    /// bracket or an interval series. While the astro helper is on, it starts or stops an astro
    /// run instead (``AstroModel``). While any series runs, the shutter stops it, in every drive
    /// mode and with either type of bracket on.
    func pressShutter() async {
        // A running focus bracket first, also one a Siri or Shortcuts request started: the
        // shutter stops it after the current frame, also while it is paused or counts down to
        // continue, whatever else is on (third review of 1.0.0, S3).
        if bracketing.isRunning {
            await pressFocusBracketShutter()
            return
        }
        if astro.isOn {
            pressAstroShutter()
            return
        }
        // A series started from Interval Settings, Siri or this mode: the shutter stops it, as
        // it stops a burst, also with a focus bracket on, which would otherwise start beside it
        // (third review of 1.0.0, S1).
        if manual.intervalProgress != nil {
            await send(.manual(.stopInterval))
            return
        }
        // The focus bracket: the shutter starts it, or cancels its start delay.
        if isFocusBracketOn {
            await pressFocusBracketShutter()
            return
        }
        if drive.countdown.isRunning {
            drive.countdown.cancel()
            return
        }
        if drive.burstProgress != nil {
            drive.requestBurstStop()
            return
        }
        switch drive.mode {
        case .single: await capture()
        case .timer(let delay): startTimer(seconds: delay.seconds)
        // A press that reports no phases (assistive activation, Space, an interface without a
        // held shutter) takes one photo; holding the shutter takes a burst (`.shutter`).
        case .burst:
            if let limit = drive.burstLimit.frameCount {
                // With a Burst Limit, a press takes the count (issue #121).
                await takeBurst(frames: limit, start: .limited)
            } else {
                await takeBurst(frames: 1)
            }
        case .interval: await send(.manual(.startInterval))
        }
    }

    /// Handles one drive intent.
    ///
    /// - Parameter intent: The intent.
    func handle(_ intent: DriveIntent) async {
        switch intent {
        case .setMode(let mode):
            drive.setMode(mode)
            await driveModeDidChange()
        case .startTimer(let seconds): startTimer(seconds: seconds)
        case .cancelTimer: drive.countdown.cancel()
        case .stopBurst: drive.requestBurstStop()
        case .hardwareButton(let phase): await handleShutter(phase, from: .hardware, press: nil)?.value
        case .shutter(let phase): await handleShutter(phase, from: .onScreen, press: nil)?.value
        case .startBurst: await startBurst()
        case .setBurstSpeed(let speed): drive.setBurstSpeed(speed)
        case .setBurstLimit(let limit): drive.setBurstLimit(limit)
        }
    }

    /// Starts a burst that needs no holding (docs/design/BURST.md, 3.1), in burst mode with the
    /// astro helper off, when a photo can be taken and nothing runs. With a Burst Limit it is the
    /// same as a press: the limit's count (issue #121).
    private func startBurst() async {
        guard drive.mode == .burst, !astro.isOn, canCapture, !drive.isBusy, !drive.isBurstPrepared else { return }
        if let limit = drive.burstLimit.frameCount {
            await takeBurst(frames: limit, start: .limited)
        } else {
            await takeBurst(start: .started)
        }
    }

    /// A shutter moved: the on-screen shutter in burst mode, or a hardware shutter button. Call
    /// it straight from the touch or the button's event, with no task in between, so presses and
    /// releases are handled in the order they happened (issue #100). The hold changes at once;
    /// the work (a photo, or a burst) starts in a task, which is returned.
    ///
    /// In burst mode a burst runs while the shutter is held: its first photo is requested when
    /// it goes down, and it ends when no shutter is down any more (each source has its own
    /// hold). In the other modes a hardware button acts as the shutter when it comes up, as the
    /// system Camera app does (AVKit, `AVCaptureEventInteraction`, "Capture a photo on press
    /// up"), and the on-screen shutter's phases are ignored: it sends ``CameraIntent/capture``
    /// instead. ``DriveIntent/shutter(_:)`` and ``DriveIntent/hardwareButton(_:)`` come here too.
    ///
    /// A press is numbered by its source, and its release carries the same number. A press or
    /// release that arrives late is dropped by its number, and a release that arrives before its
    /// press makes that press a tap (``ShutterHolds``), so a tap can never leave a burst running.
    ///
    /// Counts as the person's action (``activityCount``), as an intent does.
    ///
    /// Side effects: may take photos and add them to Photos.
    ///
    /// - Parameters:
    ///   - phase: How the shutter moved.
    ///   - source: Which shutter.
    ///   - press: The number of the press, counted by its source from 1, which the release of
    ///     that press repeats; `nil` for a caller that delivers in order and doesn't count: its
    ///     press is the next one and its release ends the latest.
    /// - Returns: The work the event started, or `nil` for none.
    @discardableResult
    public func shutter(_ phase: ShutterPhase, from source: ShutterSource, press: Int? = nil) -> Task<Void, Never>? {
        countAction()
        return handleShutter(phase, from: source, press: press)
    }

    /// Ends every shutter press that is down, as if each came up, so a held burst stops after the
    /// photo being taken (issue #101). Call it when the app leaves the active state: a press that
    /// is down then may never report coming up. Sending ``CameraIntent/setInForeground(_:)`` with
    /// `false` does it too. A burst that needs no holding is not stopped by it.
    public func cancelShutterHolds() {
        drive.holds.releaseAll()
    }

    /// Handles a shutter event without counting it as an action (see ``shutter(_:from:press:)``).
    ///
    /// - Parameters:
    ///   - phase: How the shutter moved.
    ///   - source: Which shutter.
    ///   - press: The press's number, or `nil`.
    /// - Returns: The work the event started, or `nil`.
    func handleShutter(_ phase: ShutterPhase, from source: ShutterSource, press: Int?) -> Task<Void, Never>? {
        guard phase == .pressed else {
            guard drive.holds.release(press, from: source) == .current else { return nil }
            return shutterCameUp(phase, from: source)
        }
        guard case .new(_, let isReleased) = drive.holds.press(press, from: source) else { return nil }
        let work = shutterWentDown(from: source)
        // Its release came first: the press is a tap.
        guard isReleased, let release = shutterCameUp(.released, from: source) else { return work }
        return Task {
            await work?.value
            await release.value
        }
    }

    /// A shutter went down; its hold is recorded.
    ///
    /// - Parameter source: Which shutter.
    /// - Returns: The burst it starts, or `nil`.
    private func shutterWentDown(from source: ShutterSource) -> Task<Void, Never>? {
        // With the Last Photo viewer open, a hardware button's press closes it and takes no
        // photo, from its first phase to its last (BUILD-SPEC.md, decision V1): the framing is
        // hidden.
        if source == .hardware, isViewerOpen || hardwarePressClosedViewer {
            isViewerOpen = false
            hardwarePressClosedViewer = true
            return nil
        }
        // Outside a held burst a shutter acts when it comes up.
        guard isBurstShutter else { return nil }
        if let limit = drive.burstLimit.frameCount {
            // With a Burst Limit a press takes the count, and a second press stops it after the
            // photo being taken, as a press stops the self-timer (issue #121).
            guard !drive.isBusy, !drive.isBurstPrepared else {
                if drive.countdown.isRunning { drive.countdown.cancel() } else { drive.requestBurstStop() }
                return nil
            }
            drive.prepareBurst(start: .limited, limit: limit)
            return Task { await takeBurst(frames: limit, start: .limited, isPrepared: true) }
        }
        guard !drive.isBusy, !drive.isBurstPrepared else { return nil }
        drive.prepareBurst(start: .held)
        return Task { await takeBurst(start: .held, isPrepared: true) }
    }

    /// A shutter came up, or its press was cancelled; its hold has ended.
    ///
    /// - Parameters:
    ///   - phase: How it moved: ``ShutterPhase/released`` or ``ShutterPhase/cancelled``.
    ///   - source: Which shutter.
    /// - Returns: The photo it takes, or `nil`.
    private func shutterCameUp(_ phase: ShutterPhase, from source: ShutterSource) -> Task<Void, Never>? {
        if source == .hardware, isViewerOpen || hardwarePressClosedViewer {
            isViewerOpen = false
            hardwarePressClosedViewer = false
            return nil
        }
        // Outside a held burst, a hardware button acts when it comes up, as a tap on the
        // on-screen shutter does. That includes a running interval series or astro run in Burst
        // mode, which the press stops and takes no burst. The on-screen shutter reports no phases
        // then (``isBurstShutter``), but a press it reported just before the series began must
        // still stop it when it comes up.
        guard isBurstShutter else {
            let stopsASeries = manual.intervalProgress != nil || astro.isRunning || bracketing.isRunning
            guard source == .hardware || stopsASeries, phase == .released else { return nil }
            return Task { await pressShutter() }
        }
        // Coming up, or cancelled, ends what the press started. A held burst ends by itself once
        // no shutter is down (``DriveModel/isBurstStopRequested``), so a second button's release
        // doesn't end it; a limited one runs on to its count (issue #121); any other burst stops.
        // A countdown started another way (such as by Siri) is cancelled as the shutter would,
        // unless a limit is set, where the press already did.
        if let burst = drive.burstProgress {
            if burst.start != .held, burst.start != .limited { drive.requestBurstStop() }
        } else if !drive.isBurstPrepared, drive.burstLimit.frameCount == nil {
            drive.countdown.cancel()
        }
        return nil
    }

    /// Starts the self-timer, which takes one photo when it reaches zero, or what `shot` takes.
    /// Ignored while a photo can't be taken or a countdown or burst runs.
    ///
    /// - Parameters:
    ///   - seconds: The delay, in seconds.
    ///   - shot: What to take at zero instead of one photo, such as the burst or bracket a Siri
    ///     or Shortcuts request asked for (issue #62), or `nil` for one photo.
    func startTimer(seconds: Int, shot: (@MainActor () async -> Void)? = nil) {
        guard canCapture, !drive.isBusy else { return }
        drive.countdown.start(seconds: seconds) { [weak self] in
            if let shot {
                await shot()
            } else {
                await self?.capture()
            }
        }
    }

    /// Takes a burst: single frames as fast as the camera is ready for them, each saved as its
    /// own photo through the same pipeline as any photo (metadata allowlist, read-back and
    /// signing per file). No frame is merged with another (AGENTS.md, "Honesty").
    ///
    /// Each frame is saved while the next is taken, so at most two frames are in memory at once
    /// (issue #46, "memory stays bounded"). The burst stops when the person stops it, at
    /// ``DriveModel/maximumBurstFrames``, when the next frame wouldn't fit in storage, when the
    /// camera stops, or at the first frame that can't be taken or saved. Every frame taken
    /// before that is still saved; nothing is dropped.
    ///
    /// A burst never fires the flash, as brackets don't: the flash can't recharge between rapid
    /// frames.
    ///
    /// A held or started burst runs at the session's speed (``burstSpeed``); a counted one
    /// always at Fast, so "as fast as the camera allows" in the Siri action stays true. A burst
    /// at Fast of three photos or more records its rate for the lens, which decides whether Slow
    /// is offered on it (``DriveModel/offersSlowBurst(on:)``).
    ///
    /// Side effects: may show the add-only Photos prompt; adds each photo to Photos.
    ///
    /// - Parameters:
    ///   - frames: The most frames to take: ``DriveModel/maximumBurstFrames`` for a held or
    ///     started burst, 1 for a press that reports no phases, the count a Siri or Shortcuts
    ///     request asked for (issue #62), or the Burst Limit's count (issue #121).
    ///   - start: Who begins the burst.
    ///   - isPrepared: Whether a shutter press already asked for it (`DriveModel.prepareBurst`),
    ///     so a stop asked for since then still applies.
    func takeBurst(frames: Int = DriveModel.maximumBurstFrames, start: BurstStart = .counted, isPrepared: Bool = false) async {
        // A Burst Limit of 50 ends by its count, not as the cap (docs/design/finish-1.0.md, 5.2).
        let end: BurstEnd = start == .limited || frames < DriveModel.maximumBurstFrames ? .countReached : .limitReached
        let speed: BurstSpeed = start == .counted ? .fast : burstSpeed
        let lensID = selectedLensID
        if !isPrepared { drive.prepareBurst(start: start, limit: start == .limited ? frames : nil) }
        let began = await takeFrames(
            limit: frames, tracker: drive, stopsOnLowBattery: false, endAtLimit: end,
            minimumInterval: speed.minimumFrameInterval)
        if !began { drive.abandonPreparedBurst() }
        // A press that could not begin a burst (the camera restarting after a lens change, a
        // photo still saving) leaves the previous burst in `lastBurst`; its rate belongs to the
        // lens that burst ran on, not to the one selected now.
        if began, speed == .fast, let lensID, let rate = drive.lastBurst?.rate {
            drive.recordFastRate(rate, on: lensID)
        }
    }

    /// Takes up to `limit` single frames back to back, each saved as its own photo while the
    /// next is taken: the loop behind a burst and an astro run (``AstroModel``). See
    /// `takeBurst()` for how frames are saved and when the run stops. Each frame carries the
    /// location when the Location switch is on, as a single photo does.
    ///
    /// - Parameters:
    ///   - limit: The most frames to take.
    ///   - tracker: What the run reports its progress to.
    ///   - stopsOnLowBattery: Whether the run also stops when the battery is at or below
    ///     ``AstroModel/stopBatteryLevel`` and not charging.
    ///   - endAtLimit: What the run reports when it takes all `limit` frames.
    ///   - pausesWithCamera: Whether the run pauses instead of stopping when the app leaves the
    ///     foreground or the camera pauses, and continues afterwards (the astro helper, issue
    ///     #64; see `pauseAstroRun()`). A frame cut short by the pause is taken again, also
    ///     when its error arrives before the pause does (`failureWasAPause()`).
    ///   - minimumInterval: The least time between the starts of two frames (a Slow burst), or
    ///     `nil` to take each as soon as the camera is ready. The run waits with the drive's
    ///     sleep and checks again whether to stop after the wait.
    /// - Returns: Whether the run began: `false` when no photo could be taken, the camera has no
    ///   lens or there is no save pipeline, and the tracker was not told of a run.
    ///
    /// Side effects: may show the add-only Photos prompt; adds each photo to Photos.
    @discardableResult
    func takeFrames(
        limit: Int, tracker: any FrameRunTracking, stopsOnLowBattery: Bool, endAtLimit: BurstEnd = .limitReached,
        pausesWithCamera: Bool = false, minimumInterval: Duration? = nil
    ) async -> Bool {
        guard canCapture || (pausesWithCamera && seriesShouldPause), let lens = selectedLens else { return false }
        guard let saver else {
            captureStatus = .failed(.savingUnavailable)
            return false
        }
        let settings = saveSettings
        var plan = saver.plan(for: settings.metadata)
        plan.location = location?.location(isOn: settings.metadata.isOn(.location))
        let request = CaptureRequest(lens: lens, metadata: plan)
        let bytesPerPhoto = PhotoSizeEstimate.bytes(for: lens, settings: settings)
        tracker.beginRun()
        lastPressPhotos = []
        captureStatus = .capturing
        var saved: [SavedPhoto] = []
        var failure: CaptureError?
        var end = endAtLimit
        var pending: PendingFrame?
        var taken = 0
        var lastStart: ContinuousClock.Instant?
        while taken < limit {
            if pausesWithCamera, seriesShouldPause {
                // Every frame taken is saved before the pause, so nothing waits in memory.
                if let previous = pending {
                    pending = nil
                    if let error = await collect(previous, into: &saved, tracker: tracker) {
                        failure = error
                        break
                    }
                }
                guard await pauseAstroRun() else {
                    end = .stopped
                    break
                }
                continue
            }
            if let reason = stopReason(tracker, bytesPerPhoto: bytesPerPhoto, stopsOnLowBattery: stopsOnLowBattery) {
                end = reason
                break
            }
            // A Slow burst waits, then asks again whether to stop: a stop during the wait takes
            // no further photo.
            if let minimumInterval, let lastStart, await waitUntil(lastStart + minimumInterval),
                let reason = stopReason(tracker, bytesPerPhoto: bytesPerPhoto, stopsOnLowBattery: stopsOnLowBattery)
            {
                end = reason
                break
            }
            let photo: CapturedPhoto
            let start = now()
            lastStart = start
            let takenAt = wallClock()
            do {
                photo = try await backend.capturePhoto(request)
            } catch {
                // A frame cut short by leaving the app or a camera pause is taken again after it.
                if pausesWithCamera, await failureWasAPause() { continue }
                failure = error
                break
            }
            taken += 1
            tracker.recordTaken()
            let previous = pending
            let captureDuration = now() - start
            let distortionCorrection = distortionCorrection(of: photo)
            pending = PendingFrame(
                save: Task {
                    await Self.saveResult(
                        photo, saver: saver, settings: settings, captureDuration: captureDuration,
                        distortionCorrection: distortionCorrection)
                }, lens: lens, takenAt: takenAt)
            if let previous, let error = await collect(previous, into: &saved, tracker: tracker) {
                failure = error
                break
            }
        }
        if let pending {
            // No more photos are taken; a new burst waits until the last one is saved.
            (tracker as? DriveModel)?.beginSaving()
            if let error = await collect(pending, into: &saved, tracker: tracker) {
                failure = failure ?? error
            }
        }
        deviceStatus.refresh()
        finishRun(saved: saved, end: end, failure: failure, tracker: tracker)
        return true
    }

    /// Waits until a time on the model's clock, with the drive's sleep: before the next frame of
    /// a Slow burst. Returns at once when the time has passed; a sleep that throws ends the wait.
    ///
    /// - Parameter time: When the next frame may start.
    /// - Returns: Whether it waited.
    private func waitUntil(_ time: ContinuousClock.Instant) async -> Bool {
        let left = (time - now()) / .seconds(1)
        guard left > 0 else { return false }
        try? await drive.sleep(left)
        return true
    }

    /// Why the run should stop before the next frame, or `nil` to take it.
    ///
    /// - Parameters:
    ///   - tracker: The run's progress.
    ///   - bytesPerPhoto: The estimated size of one frame's files.
    ///   - stopsOnLowBattery: Whether a low battery stops the run.
    private func stopReason(_ tracker: any FrameRunTracking, bytesPerPhoto: Int64, stopsOnLowBattery: Bool) -> BurstEnd? {
        if tracker.isStopRequested { return .stopped }
        guard sessionStatus.canCapture else { return .cameraStopped }
        deviceStatus.refresh()
        if stopsOnLowBattery, deviceStatus.isBatteryBelow(AstroModel.stopBatteryLevel) { return .batteryLow }
        return deviceStatus.fits(bytes: bytesPerPhoto) ? nil : .storageFull
    }

    /// Waits for a frame's save and adds it to the saved frames and ``sessionPhotos``.
    ///
    /// - Parameters:
    ///   - frame: The frame's save, lens and time.
    ///   - saved: The frames saved so far.
    ///   - tracker: The run's progress.
    /// - Returns: The error when the save failed, otherwise `nil`.
    private func collect(
        _ frame: PendingFrame, into saved: inout [SavedPhoto], tracker: any FrameRunTracking
    ) async -> CaptureError? {
        switch await frame.save.value {
        case .success(let result):
            keepInSession(result, lens: frame.lens, takenAt: frame.takenAt)
            saved.append(result.saved)
            tracker.recordSaved()
            return nil
        case .failure(let error):
            return error
        }
    }

    /// Records how the run ended: the error of a failed frame, or the frames saved.
    ///
    /// - Parameters:
    ///   - saved: The frames saved.
    ///   - end: Why the run ended, when no frame failed.
    ///   - failure: The error of the frame that failed, or `nil`.
    ///   - tracker: The run's progress.
    private func finishRun(saved: [SavedPhoto], end: BurstEnd, failure: CaptureError?, tracker: any FrameRunTracking) {
        if let failure {
            tracker.endRun(.failed)
            captureStatus = .failed(failure)
        } else {
            tracker.endRun(end)
            captureStatus = saved.isEmpty ? .idle : .savedBurst(saved)
        }
    }

    /// Saves one frame, off the main actor.
    ///
    /// - Parameters:
    ///   - photo: The frame.
    ///   - saver: The save pipeline.
    ///   - settings: The settings the burst is taken with.
    ///   - captureDuration: How long the camera took to return the frame.
    ///   - distortionCorrection: The lens's distortion correction, for the details.
    /// - Returns: The saved photo and its preview, or the error.
    private nonisolated static func saveResult(
        _ photo: CapturedPhoto, saver: PhotoSaver, settings: SaveSettings, captureDuration: Duration,
        distortionCorrection: DistortionCorrection?
    ) async -> Result<(saved: SavedPhoto, preview: PhotoPreview?), CaptureError> {
        do {
            return .success(
                try await saver.saveWithPreview(
                    photo, settings: settings, captureDuration: captureDuration,
                    distortionCorrection: distortionCorrection))
        } catch {
            return .failure(error)
        }
    }
}

/// A burst or series frame whose save is running, with what ``CameraModel/sessionPhotos`` keeps
/// about it.
struct PendingFrame {
    /// The save, which returns the saved photo and its preview, or the error.
    let save: Task<Result<(saved: SavedPhoto, preview: PhotoPreview?), CaptureError>, Never>
    /// The lens the frame was taken with.
    let lens: Lens
    /// When the shutter took the frame.
    let takenAt: Date

    /// Creates a pending frame.
    ///
    /// - Parameters:
    ///   - save: The running save.
    ///   - lens: The lens the frame was taken with.
    ///   - takenAt: When the shutter took the frame.
    init(save: Task<Result<(saved: SavedPhoto, preview: PhotoPreview?), CaptureError>, Never>, lens: Lens, takenAt: Date) {
        self.save = save
        self.lens = lens
        self.takenAt = takenAt
    }
}
