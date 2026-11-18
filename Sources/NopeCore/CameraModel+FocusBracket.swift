import Foundation

/// Focus bracketing (issue #90; docs/design/BRACKETING.md, sections 5 and 8): a series of
/// separate single-frame photos, each at the next focus position, for stacking in other software.
///
/// For each frame the camera locks focus at the planned lens position and waits for the system
/// to report it applied (``ManualCaptureBackend/setFocus(lensPosition:)``), then takes one photo
/// through the ordinary single-photo path and saves it, so the metadata allowlist, the read-back
/// and signing apply as to any photo (AGENTS.md, "Honesty"). The app never stacks, aligns or
/// merges the frames, and no file gets a new tag: the positions are session values.
///
/// Exposure and white balance are locked at the first frame's values (or the values set by hand
/// are used), and are as they were afterwards. The series stops on request, before a frame that
/// storage can't hold, at a low battery, when the camera stops for good, or at a frame that can't
/// be taken or saved; it pauses and continues as an astro run does. Every photo taken is kept.
extension CameraModel {
    /// The wait after the system reports a focus move applied, before the photo: 0.1 seconds.
    /// An assumption until the device check D7 (docs/design/BRACKETING.md, section 9) measures
    /// whether a photo taken at once after the handler is sharp where expected.
    public static let focusSettleSeconds = 0.1

    /// Whether the selected lens can take a focus bracket: its focus can be locked at a lens
    /// position, and the camera has manual controls.
    public var canFocusBracket: Bool {
        backend is any ManualCaptureBackend && (selectedLens.map(FocusBracketSettings.isAvailable(on:)) ?? false)
    }

    /// Whether the selected lens can take an exposure bracket.
    public var canExposureBracket: Bool {
        !manual.bracketFrameCounts.isEmpty
    }

    /// Whether the drive strip offers Bracket: the lens can take either type, or a bracket is on.
    public var offersBracket: Bool {
        canExposureBracket || canFocusBracket || isBracketOn
    }

    /// Whether a press of the shutter takes the focus bracket (and the astro helper is off).
    public var isFocusBracketOn: Bool {
        bracketing.isFocusOn && !astro.isOn
    }

    /// The most bytes the focus bracket's files can take, for "Storage, at Most"
    /// (``PhotoSizeEstimate``, an upper bound), or `nil` before the camera is ready.
    public var focusBracketStorageBytes: Int64? {
        selectedLens.map { PhotoSizeEstimate.bytes(for: $0, settings: saveSettings) * Int64(bracketing.focus.frameCount) }
    }

    /// The value of the range end being set on the picture, or `nil` when none is: the value
    /// chosen with the slider, or after a tap on the picture the position the lens reports.
    public var focusRangeValue: Double? {
        guard let editing = bracketing.rangeEditing else { return nil }
        guard editing.followsLens, let position = manual.lastReading?.lensPosition else { return editing.value }
        return (position * 100).rounded() / 100
    }

    /// Handles one bracket intent.
    ///
    /// - Parameter intent: The intent.
    func handle(_ intent: BracketIntent) async {
        let isIdle = !bracketing.isRunning && !drive.isBusy
        switch intent {
        case .setOn(let isOn):
            guard isIdle else { return }
            if isOn { await turnOnBracket(preferring: bracketing.type) } else { await turnOffBracket() }
        case .setType(let type):
            guard isIdle else { return }
            await setBracketType(type)
        case .setFocus(let settings):
            if isIdle { bracketing.setFocus(settings) }
        case .setFocusStartDelay(let delay):
            if isIdle { bracketing.setFocusStartDelay(delay) }
        case .useWholeRange:
            if isIdle { bracketing.setFocus(bracketing.focus.with(nearest: 0, farthest: 1)) }
        case .beginSettingRange(let end):
            await beginSettingRange(end, isIdle: isIdle)
        case .setRangeValue(let value):
            await setRangeValue(value)
        case .focusRange(let point):
            await focusRange(at: point)
        case .finishSettingRange(let keeps):
            await finishSettingRange(keeps: keeps)
        case .stop:
            stopFocusBracket()
        }
    }

    /// Turns Bracket on with a type, or with the other type where the lens can't take it.
    ///
    /// - Parameter type: The type asked for.
    private func turnOnBracket(preferring type: BracketType) async {
        let usesFocus = type == .focus ? canFocusBracket : !canExposureBracket && canFocusBracket
        if usesFocus {
            if manual.bracket != nil { await send(.manual(.setBracket(nil))) }
            drive.setMode(.single)
            bracketing.setType(.focus)
            bracketing.setFocusOn(true)
            return
        }
        // The session's last exposure bracket, with its start delay (read before the bracket
        // changes the mode).
        guard let bracket = bracketToTurnOn else { return }
        let mode = bracketDriveMode
        await send(.manual(.setBracket(bracket)))
        await send(.drive(.setMode(mode)))
    }

    /// Turns both types of bracket off.
    private func turnOffBracket() async {
        bracketing.setFocusOn(false)
        if manual.bracket != nil { await send(.manual(.setBracket(nil))) }
    }

    /// Chooses the type; with Bracket on, turns that type on instead of the other.
    ///
    /// - Parameter type: The type.
    private func setBracketType(_ type: BracketType) async {
        let isAvailable = type == .focus ? canFocusBracket : canExposureBracket
        guard isAvailable else { return }
        guard isBracketOn else {
            bracketing.setType(type)
            return
        }
        await turnOnBracket(preferring: type)
    }

    // MARK: Setting the range on the picture

    /// Starts setting an end of the range: the lens moves to that end, and the camera's own
    /// controls hold until the setting ends.
    ///
    /// - Parameters:
    ///   - end: The end.
    ///   - isIdle: Whether nothing runs.
    private func beginSettingRange(_ end: FocusRangeEnd, isIdle: Bool) async {
        guard isIdle, canFocusBracket, bracketing.rangeEditing == nil else { return }
        let value = end == .nearest ? bracketing.focus.nearest : bracketing.focus.farthest
        bracketing.setRangeEditing(FocusRangeEditing(end: end, value: value))
        manual.holdsControls = true
        await moveLens(to: value)
    }

    /// Moves the lens while an end of the range is set.
    ///
    /// - Parameter value: The position, from 0 to 1.
    private func setRangeValue(_ value: Double) async {
        guard let editing = bracketing.rangeEditing else { return }
        let rounded = (value.limited(to: 0...1) * 100).rounded() / 100
        bracketing.setRangeEditing(FocusRangeEditing(end: editing.end, value: rounded))
        await moveLens(to: rounded)
    }

    /// Focuses once at a point of the picture while an end of the range is set, and lets the
    /// value follow the lens.
    ///
    /// - Parameter point: The point, in viewfinder coordinates.
    private func focusRange(at point: FramePoint) async {
        guard let editing = bracketing.rangeEditing, let lens = selectedLens,
            let focusBackend = backend as? any ManualCaptureBackend, lens.manualControls.supportsTapToFocus,
            let devicePoint = previewSource.map({ $0.devicePoint(forViewfinderPoint: point) }) ?? point
        else { return }
        let current = DeviceControls(settings: manual.settings, lens: lens)
        let once = DeviceControls(
            exposure: current.exposure, focus: .automatic, whiteBalance: current.whiteBalance,
            metering: current.metering,
            pointOfInterest: DeviceControls.PointOfInterest(point: devicePoint, focuses: true, exposes: false, locks: true))
        try? await focusBackend.applyControls(once)
        bracketing.setRangeEditing(FocusRangeEditing(end: editing.end, value: editing.value, followsLens: true))
    }

    /// Ends setting the range, keeping the value as that end or not, and gives the camera its
    /// own controls back.
    ///
    /// - Parameter keeps: Whether to keep the value (Set) or not (Cancel).
    private func finishSettingRange(keeps: Bool) async {
        guard let editing = bracketing.rangeEditing, let value = focusRangeValue else { return }
        if keeps {
            let focus = bracketing.focus
            bracketing.setFocus(
                editing.end == .nearest ? focus.with(nearest: value) : focus.with(farthest: value))
        }
        bracketing.setRangeEditing(nil)
        manual.holdsControls = false
        await manual.applyCurrentControls()
    }

    /// Ends setting an end of the range, as Cancel does, once the focus bracket it belongs to is
    /// off (another drive word, Astro, the exposure type, a preset, or a lens that can't take
    /// it), so the camera's own controls never stay held. Called after every intent.
    func endStaleRangeEditing() async {
        guard bracketing.rangeEditing != nil, !isFocusBracketOn else { return }
        await finishSettingRange(keeps: false)
    }

    /// Moves the lens to a position, ignoring a camera that refuses or isn't running.
    ///
    /// - Parameter position: The position, from 0 to 1.
    private func moveLens(to position: Double) async {
        // Only reached where the lens can take a focus bracket, so the backend is a manual one.
        _ = try? await (backend as? any ManualCaptureBackend)?.setFocus(lensPosition: position)
    }

    // MARK: Taking the bracket

    /// The shutter while the focus bracket is on or runs: stops a running bracket after its
    /// current frame, cancels the start delay, or starts the start delay and then the bracket.
    func pressFocusBracketShutter() async {
        if bracketing.isRunning || drive.countdown.isRunning {
            stopFocusBracket()
            return
        }
        guard canCapture else { return }
        // The shutter while an end of the range is set leaves the range as it was (as Cancel),
        // so the series never starts with the camera's controls held by the dial.
        if bracketing.rangeEditing != nil { await finishSettingRange(keeps: false) }
        let settings = bracketing.focus
        guard let delay = bracketing.focusStartDelay else {
            await takeFocusBracket(settings)
            return
        }
        drive.countdown.start(seconds: delay.seconds) { [weak self] in
            await self?.takeFocusBracket(settings)
        }
    }

    /// Stops a running focus bracket after the current frame, or the countdown before it or
    /// before a paused one continues.
    private func stopFocusBracket() {
        if bracketing.isRunning { bracketing.requestStop() }
        drive.countdown.cancel()
    }

    /// Takes a focus bracket now: for each position, lock focus there and wait for the system's
    /// handler, read back the position, take one photo, save it, go on.
    ///
    /// Side effects: may show the add-only Photos prompt; adds each photo to Photos; sets the
    /// camera's focus, exposure and white balance while it runs and restores them afterwards.
    ///
    /// - Parameter settings: The bracket.
    /// - Returns: Whether the bracket began: `false` when no photo can be taken, the lens's focus
    ///   can't be set or there is no save pipeline.
    @discardableResult
    func takeFocusBracket(_ settings: FocusBracketSettings) async -> Bool {
        guard canCapture, canFocusBracket, let lens = selectedLens, let focusBackend = backend as? any ManualCaptureBackend
        else { return false }
        guard let saver else {
            captureStatus = .failed(.savingUnavailable)
            return false
        }
        let save = saveSettings
        var plan = saver.plan(for: save.metadata)
        plan.location = location?.location(isOn: save.metadata.isOn(.location))
        // A focus bracket never fires the flash (docs/design/BRACKETING.md, section 5).
        let request = CaptureRequest(lens: lens, metadata: plan, flashMode: .off)
        let run = FocusBracketRun(
            settings: settings, lens: lens, request: request, save: save, saver: saver, backend: focusBackend,
            locked: lockedSettings(on: lens), bytesPerPhoto: PhotoSizeEstimate.bytes(for: lens, settings: save))
        manual.holdsControls = true
        bracketing.beginRun(settings)
        lastPressPhotos = []
        captureStatus = .capturing
        let outcome = await takeFrames(of: run)
        let focusAfter = await restoreControls(after: run, lastPosition: outcome.lastPosition)
        deviceStatus.refresh()
        bracketing.endRun(
            FocusBracketResult(
                end: outcome.failure == nil ? outcome.end : .failed, saved: outcome.saved.count,
                total: settings.frameCount, offPlan: outcome.offPlan, focusAfter: focusAfter))
        if let failure = outcome.failure {
            captureStatus = .failed(failure)
        } else {
            captureStatus = outcome.saved.isEmpty ? .idle : .savedBracket(outcome.saved)
        }
        return true
    }

    /// The frame loop of a focus bracket.
    ///
    /// - Parameter run: The bracket and what it is taken with.
    /// - Returns: The photos saved, why the loop ended, the error that ended it, if any, the
    ///   frames off their planned focus and the last reported position.
    private func takeFrames(of run: FocusBracketRun) async -> FocusBracketOutcome {
        let positions = run.settings.positions
        var outcome = FocusBracketOutcome()
        var needsLock = true
        while outcome.saved.count < positions.count {
            if seriesShouldPause {
                guard await pauseFocusBracket() else {
                    outcome.end = .stopped
                    break
                }
                // The camera may have restarted, which returns its controls to automatic.
                needsLock = true
                continue
            }
            if let reason = focusBracketStopReason(bytesPerPhoto: run.bytesPerPhoto) {
                outcome.end = reason
                break
            }
            let number = outcome.saved.count + 1
            do {
                if needsLock {
                    try await run.backend.applyControls(run.controls(at: positions[number - 1]))
                    needsLock = false
                }
                let (saved, preview, reported, takenAt) = try await takeFrame(number, of: run, positions: positions)
                keepInSession((saved: saved, preview: preview), lens: run.lens, takenAt: takenAt)
                bracketing.recordSaved()
                outcome.saved.append(saved)
                outcome.lastPosition = reported
                if saved.bracket?.focus?.isOffPlan == true { outcome.offPlan += 1 }
            } catch {
                // A frame cut short by leaving the app or a camera pause is taken again after it.
                if await failureWasAPause() { continue }
                outcome.failure = error
                break
            }
        }
        return outcome
    }

    /// Takes and saves one frame: moves the lens, waits for the system and a margin, takes one
    /// photo and saves it with its place in the bracket.
    ///
    /// - Parameters:
    ///   - number: The frame's number, from 1.
    ///   - run: The bracket.
    ///   - positions: Every frame's position, in the order taken.
    /// - Returns: The saved photo with its place, its preview, the reported position and when
    ///   the shutter took it.
    /// - Throws: The error of the move, the photo or the save.
    private func takeFrame(_ number: Int, of run: FocusBracketRun, positions: [Double]) async throws(CaptureError)
        -> (SavedPhoto, PhotoPreview?, Double, Date)
    {
        let planned = positions[number - 1]
        let reported = try await run.backend.setFocus(lensPosition: planned)
        bracketing.recordPosition(reported)
        try? await drive.sleep(Self.focusSettleSeconds)
        let start = now()
        let takenAt = wallClock()
        let photo = try await run.backend.capturePhoto(run.request)
        bracketing.recordTaken()
        let result = try await run.saver.saveWithPreview(
            photo, settings: run.save, captureDuration: now() - start, distortionCorrection: distortionCorrection(of: photo))
        // Privacy: the place is a session value; it is never written to the files.
        let place = FocusFramePlace(
            number: number, plannedPosition: planned, reportedPosition: reported, positions: positions,
            order: run.settings.order)
        return (result.saved.placed(in: BracketPlace(focus: place, count: positions.count)), result.preview, reported, takenAt)
    }

    /// Why the bracket should stop before the next frame, or `nil` to take it.
    ///
    /// - Parameter bytesPerPhoto: The estimated size of one frame's files.
    private func focusBracketStopReason(bytesPerPhoto: Int64) -> BurstEnd? {
        if bracketing.isStopRequested { return .stopped }
        guard sessionStatus.canCapture else { return .cameraStopped }
        deviceStatus.refresh()
        if deviceStatus.isBatteryBelow(AstroModel.stopBatteryLevel) { return .batteryLow }
        return deviceStatus.fits(bytes: bytesPerPhoto) ? nil : .storageFull
    }

    /// Pauses the bracket until the app is in the foreground and the camera can take photos,
    /// then counts the start delay down again so the phone is still. It waits for Observation's
    /// change notifications; nothing polls (AGENTS.md, "Battery").
    ///
    /// - Returns: `false` when the person stopped the bracket, `true` to continue.
    private func pauseFocusBracket() async -> Bool {
        bracketing.setPaused(true)
        while seriesShouldPause, !bracketing.isStopRequested {
            await nextChangeOfFocusBracketPause()
        }
        bracketing.setPaused(false)
        guard !bracketing.isStopRequested, sessionStatus.canCapture else { return !bracketing.isStopRequested }
        // A countdown cancelled by leaving the app again only pauses the bracket again.
        _ = await drive.countdown.run(seconds: bracketing.focusStartDelay?.seconds ?? 0)
        return !bracketing.isStopRequested
    }

    /// Waits until the foreground state, the camera's status or the stop request changes.
    private func nextChangeOfFocusBracketPause() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = isInForeground
                _ = sessionStatus
                _ = bracketing.isStopRequested
            } onChange: {
                continuation.resume()
            }
        }
    }

    /// The settings a focus bracket holds the camera to: exposure and white balance fixed at
    /// the values in use now (the camera's reading, or the values set by hand), so every frame
    /// matches (decision 13). Where the lens has no manual exposure, auto exposure is locked.
    ///
    /// - Parameter lens: The lens.
    /// - Returns: The settings; the focus is set for each frame.
    private func lockedSettings(on lens: Lens) -> ManualSettings {
        var settings = manual.settings
        let controls = lens.manualControls
        let reading = manual.lastReading
        if controls.supportsManualExposure, let reading {
            settings.iso = settings.iso ?? reading.iso
            settings.shutter = settings.shutter ?? reading.exposureDuration
        } else if controls.supportsExposureLock {
            settings.exposureLocked = true
        }
        if controls.supportsManualWhiteBalance, settings.whiteBalance == nil {
            settings.whiteBalance = reading?.whiteBalance
        }
        return settings
    }

    /// Gives the camera its own controls back after a bracket: exposure and white balance as they
    /// were, and focus as it was, or at the last frame's position with Return Focus When Done
    /// off.
    ///
    /// - Parameters:
    ///   - run: The bracket.
    ///   - lastPosition: The last frame's reported position, or `nil` when no frame was taken.
    /// - Returns: Where the focus is now.
    private func restoreControls(after run: FocusBracketRun, lastPosition: Double?) async -> FocusAfterBracket {
        manual.holdsControls = false
        guard !run.settings.returnsFocus, let lastPosition else {
            await manual.applyCurrentControls()
            return manual.settings.focus.map(FocusAfterBracket.returned) ?? .automatic
        }
        if manual.isEnabled {
            // With manual controls on, the position becomes the focus set by hand.
            manual.settings.focus = lastPosition
            manual.settings.focusLocked = false
            await manual.applyCurrentControls()
        } else {
            // In full auto the camera's own exposure and white balance return; the lens stays
            // where the last frame was until focus next changes (a tap or a lens change).
            let own = DeviceControls(settings: manual.settings, lens: run.lens, assist: manual.assist)
            try? await run.backend.applyControls(
                DeviceControls(
                    exposure: own.exposure, focus: .lensPosition(lastPosition), whiteBalance: own.whiteBalance,
                    metering: own.metering, longestAutoExposure: own.longestAutoExposure, followsFaces: own.followsFaces))
        }
        return .stays(lastPosition)
    }
}

/// A focus bracket being taken: its settings and what each frame is taken with.
struct FocusBracketRun {
    /// The bracket.
    let settings: FocusBracketSettings

    /// The lens.
    let lens: Lens

    /// Each frame's request: the lens, the metadata plan, no flash.
    let request: CaptureRequest

    /// The settings the frames are saved with.
    let save: SaveSettings

    /// The save pipeline.
    let saver: PhotoSaver

    /// The camera.
    let backend: any ManualCaptureBackend

    /// The exposure and white balance held for every frame.
    let locked: ManualSettings

    /// The estimated size of one frame's files.
    let bytesPerPhoto: Int64

    /// Creates a run.
    ///
    /// - Parameters:
    ///   - settings: The bracket.
    ///   - lens: The lens.
    ///   - request: Each frame's request.
    ///   - save: The settings the frames are saved with.
    ///   - saver: The save pipeline.
    ///   - backend: The camera.
    ///   - locked: The exposure and white balance held for every frame.
    ///   - bytesPerPhoto: The estimated size of one frame's files.
    init(
        settings: FocusBracketSettings, lens: Lens, request: CaptureRequest, save: SaveSettings, saver: PhotoSaver,
        backend: any ManualCaptureBackend, locked: ManualSettings, bytesPerPhoto: Int64
    ) {
        self.settings = settings
        self.lens = lens
        self.request = request
        self.save = save
        self.saver = saver
        self.backend = backend
        self.locked = locked
        self.bytesPerPhoto = bytesPerPhoto
    }

    /// The controls for a frame: the held exposure and white balance, focus at a position, no
    /// point of interest and no automatic aids.
    ///
    /// - Parameter position: The lens position.
    /// - Returns: The controls.
    func controls(at position: Double) -> DeviceControls {
        var settings = locked
        settings.focus = position
        settings.focusLocked = false
        return DeviceControls(settings: settings, lens: lens)
    }
}

/// What a focus bracket's frame loop returns.
struct FocusBracketOutcome {
    /// The photos saved, in the order taken.
    var saved: [SavedPhoto] = []

    /// Why the loop ended, when no frame failed.
    var end = BurstEnd.limitReached

    /// The error of the frame that failed, or `nil`.
    var failure: CaptureError?

    /// The frames whose reported focus was off their plan.
    var offPlan = 0

    /// The last frame's reported position, or `nil` when no frame was saved.
    var lastPosition: Double?

    /// Creates an outcome: nothing saved yet, ended at the limit, no failure.
    init() {}
}
