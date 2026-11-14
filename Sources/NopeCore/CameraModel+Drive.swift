import Foundation

/// The shutter's drive modes: single, the self-timer and bursts (issues #37, #39 and #46).
extension CameraModel {
    /// Whether the shutter should be enabled: a photo can be taken now, or a countdown or burst
    /// runs, which pressing the shutter stops.
    public var canPressShutter: Bool {
        canCapture || drive.isBusy
    }

    /// Whether the app should take the hardware shutter buttons (the volume buttons and the
    /// Camera Control): while the camera runs. At other times they keep their system behavior,
    /// as Apple asks of apps that can't respond to them (AVKit, `AVCaptureEventInteraction`,
    /// "isEnabled").
    public var handlesHardwareButtons: Bool {
        sessionStatus.canCapture
    }

    /// The storage warning for the next photo with the selected lens and formats, or `nil`
    /// (issue #44). The photo's size is estimated with ``PhotoSizeEstimate``.
    public var storageWarning: StorageWarning? {
        guard let lens = selectedLens else { return nil }
        return deviceStatus.storageWarning(bytesPerPhoto: PhotoSizeEstimate.bytes(for: lens, settings: saveSettings))
    }

    /// What the shutter does: stops a running countdown or burst, or else applies the drive mode:
    /// one photo, the self-timer, or a burst.
    func pressShutter() async {
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
        case .burst: await takeBurst()
        }
    }

    /// Handles one drive intent.
    ///
    /// - Parameter intent: The intent.
    func handle(_ intent: DriveIntent) async {
        switch intent {
        case .setMode(let mode): drive.setMode(mode)
        case .startTimer(let seconds): startTimer(seconds: seconds)
        case .cancelTimer: drive.countdown.cancel()
        case .stopBurst: drive.requestBurstStop()
        case .hardwareButton(let phase): await handleHardwareButton(phase)
        }
    }

    /// A hardware shutter button: in burst mode, a burst runs while it is held; in the other
    /// modes, it acts as the shutter when it comes up, as the system Camera app does (AVKit,
    /// `AVCaptureEventInteraction`, "Capture a photo on press up").
    ///
    /// - Parameter phase: How the button moved.
    private func handleHardwareButton(_ phase: HardwareButtonPhase) async {
        guard drive.mode == .burst else {
            if phase == .released { await pressShutter() }
            return
        }
        guard phase != .pressed else {
            if !drive.isBusy { await takeBurst() }
            return
        }
        // Coming up, or cancelled, ends what the press started; a countdown started another way
        // (such as by Siri) is cancelled as the shutter would.
        if drive.burstProgress != nil {
            drive.requestBurstStop()
        } else {
            drive.countdown.cancel()
        }
    }

    /// Starts the self-timer, which takes one photo when it reaches zero. Ignored while a photo
    /// can't be taken or a countdown or burst runs.
    ///
    /// - Parameter seconds: The delay, in seconds.
    private func startTimer(seconds: Int) {
        guard canCapture, !drive.isBusy else { return }
        drive.countdown.start(seconds: seconds) { [weak self] in
            await self?.capture()
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
    /// Side effects: may show the add-only Photos prompt; adds each photo to Photos.
    private func takeBurst() async {
        guard canCapture, let lens = selectedLens else { return }
        guard let saver else {
            captureStatus = .failed(.savingUnavailable)
            return
        }
        let settings = saveSettings
        let request = CaptureRequest(lens: lens, metadata: saver.plan(for: settings.metadata))
        let bytesPerPhoto = PhotoSizeEstimate.bytes(for: lens, settings: settings)
        drive.beginBurst()
        captureStatus = .capturing
        var saved: [SavedPhoto] = []
        var failure: CaptureError?
        var end = BurstEnd.limitReached
        var pending: Task<Result<SavedPhoto, CaptureError>, Never>?
        for _ in 0..<DriveModel.maximumBurstFrames {
            if let reason = burstStopReason(bytesPerPhoto: bytesPerPhoto) {
                end = reason
                break
            }
            let photo: CapturedPhoto
            do {
                photo = try await backend.capturePhoto(request)
            } catch {
                failure = error
                break
            }
            drive.recordTaken()
            let previous = pending
            pending = Task { await Self.saveResult(photo, saver: saver, settings: settings) }
            if let previous, let error = await collect(previous, into: &saved) {
                failure = error
                break
            }
        }
        if let pending, let error = await collect(pending, into: &saved) {
            failure = failure ?? error
        }
        deviceStatus.refresh()
        finishBurst(saved: saved, end: end, failure: failure)
    }

    /// Why the burst should stop before the next frame, or `nil` to take it.
    ///
    /// - Parameter bytesPerPhoto: The estimated size of one frame's files.
    private func burstStopReason(bytesPerPhoto: Int64) -> BurstEnd? {
        if drive.isBurstStopRequested { return .stopped }
        guard sessionStatus.canCapture else { return .cameraStopped }
        deviceStatus.refresh()
        return deviceStatus.fits(bytes: bytesPerPhoto) ? nil : .storageFull
    }

    /// Waits for a frame's save and adds it to the saved frames.
    ///
    /// - Parameters:
    ///   - save: The frame's save.
    ///   - saved: The frames saved so far.
    /// - Returns: The error when the save failed, otherwise `nil`.
    private func collect(
        _ save: Task<Result<SavedPhoto, CaptureError>, Never>, into saved: inout [SavedPhoto]
    ) async -> CaptureError? {
        switch await save.value {
        case .success(let photo):
            saved.append(photo)
            drive.recordSaved()
            return nil
        case .failure(let error):
            return error
        }
    }

    /// Records how the burst ended: the error of a failed frame, or the frames saved.
    ///
    /// - Parameters:
    ///   - saved: The frames saved.
    ///   - end: Why the burst ended, when no frame failed.
    ///   - failure: The error of the frame that failed, or `nil`.
    private func finishBurst(saved: [SavedPhoto], end: BurstEnd, failure: CaptureError?) {
        if let failure {
            drive.endBurst(.failed)
            captureStatus = .failed(failure)
        } else {
            drive.endBurst(end)
            captureStatus = saved.isEmpty ? .idle : .savedBurst(saved)
        }
    }

    /// Saves one frame, off the main actor.
    ///
    /// - Parameters:
    ///   - photo: The frame.
    ///   - saver: The save pipeline.
    ///   - settings: The settings the burst is taken with.
    /// - Returns: The saved photo, or the error.
    private nonisolated static func saveResult(
        _ photo: CapturedPhoto, saver: PhotoSaver, settings: SaveSettings
    ) async -> Result<SavedPhoto, CaptureError> {
        do {
            return .success(try await saver.save(photo, settings: settings))
        } catch {
            return .failure(error)
        }
    }
}
