import Foundation

/// The astro helper (issue #60): see ``AstroModel``.
extension CameraModel {
    /// What the next astro run will take, or `nil` while the helper is off or before the camera
    /// is ready. Each frame's size is estimated with ``PhotoSizeEstimate`` for the selected
    /// formats.
    public var astroEstimate: AstroEstimate? {
        guard astro.isOn, let lens = selectedLens else { return nil }
        let bytesPerFrame = PhotoSizeEstimate.bytes(for: lens, settings: saveSettings)
        let framesThatFit = deviceStatus.availableStorageBytes.map { Int($0 / max(bytesPerFrame, 1)) }
        return AstroEstimate(
            frameCount: astro.frameCount, shutter: manual.value(of: .shutter),
            bytes: bytesPerFrame * Int64(astro.frameCount), framesThatFit: framesThatFit)
    }

    /// Whether the camera should say "Hold it steady or use a tripod.":
    /// ``ManualControlsModel/showsSteadyHint``, except while the astro helper is on. Its long exposures are meant for a tripod, and its
    /// own guidance already says "Use a tripod.", so the hint would only repeat it (the Astro
    /// screens in docs/design draw no hint). Interfaces show the hint from this property.
    public var showsSteadyHint: Bool {
        manual.showsSteadyHint && !astro.isOn
    }

    /// Whether the helper can be turned on: the selected lens suits it, and the storage and
    /// battery can be read, so a run can stop before either runs out (not in the Lock Screen
    /// capture extension, which has no reader).
    public var canUseAstro: Bool {
        deviceStatus.canRead && (selectedLens.map(AstroModel.isAvailable(on:)) ?? false)
    }

    /// Whether the device offers the helper at all: a lens suits it, and storage and battery can
    /// be read (not in the Lock Screen capture extension). `false` before the camera is ready.
    /// An interface shows settings about the helper only then (AGENTS.md, "Progressive
    /// enhancement"), such as Keep Night Mode After Astro (``NopeSettings/keepsNightModeAfterAstro``).
    public var deviceOffersAstro: Bool {
        deviceStatus.canRead && (capabilities?.lenses.contains(where: AstroModel.isAvailable(on:)) ?? false)
    }

    /// Handles one astro intent.
    ///
    /// - Parameter intent: The intent.
    ///
    /// Side effects: turning the helper on may turn manual controls on, sets focus, shutter and
    /// ISO, and turns the light off; turning it off may turn manual controls off, and night mode
    /// if ``setAstro(_:settings:)`` turned it on.
    func handle(_ intent: AstroIntent) async {
        let isIdle = !drive.isBusy && !astro.isRunning
        switch intent {
        case .setOn(true):
            guard let exposure = astroExposureIfItCanTurnOn() else { return }
            await turnOnAstro(exposure)
        case .setOn(false):
            await turnOffAstro()
        case .setFrameCount(let count):
            if isIdle { astro.setFrameCount(count) }
        case .setStartDelay(let delay):
            if isIdle { astro.setStartDelay(delay) }
        case .stop:
            stopAstroRun()
        }
    }

    /// Turns the helper on or off from an interface's Astro control, with night mode: turning it
    /// on turns night mode on too (issue #60), and turning it off, in any way, returns night mode
    /// to what it was before.
    ///
    /// The night mode rule mirrors the one for manual controls:
    /// - Night mode that was off is turned on, and turned off again when the helper ends: Astro
    ///   off, another drive mode, a lens without the helper, manual controls off, or a preset. A
    ///   relaunch keeps night mode as it was (``forgetNightModeFromAstroAtLaunch(settings:)``).
    /// - Night mode that was already on stays on.
    /// - A change the person makes to night mode while the helper is on
    ///   (``NopeSettings/setNightMode(_:)``) is theirs, and is kept.
    /// - With ``NopeSettings/keepsNightModeAfterAstro`` on, night mode stays on.
    ///
    /// The helper alone (``CameraIntent/astro(_:)``, as a preset sends it) never changes night
    /// mode: night mode is a setting of the screens, and a preset brings its own.
    ///
    /// Side effects: as ``AstroIntent/setOn(_:)``; may turn night mode on and store it. Turning on
    /// is ignored, and night mode left alone, where the helper can't turn on.
    ///
    /// - Parameters:
    ///   - isOn: Whether the helper is on.
    ///   - settings: The person's settings, where night mode is stored.
    public func setAstro(_ isOn: Bool, settings: NopeSettings) async {
        guard isOn else {
            await turnOffAstro()
            return
        }
        guard let exposure = astroExposureIfItCanTurnOn() else { return }
        // Night mode first, so the screen is already red when the helper's announcement names it.
        settings.turnOnNightModeForAstro()
        astro.nightModeSettings = settings
        await turnOnAstro(exposure)
    }

    /// Forgets that the astro helper turned night mode on, without changing night mode, when the
    /// helper ended without leaving it: the app was quit or closed by the system while the helper
    /// was on, and the helper is off at every launch. Night mode stays as it was, so a relaunch in
    /// the dark opens red (owner decision, 2026-11-18); it is the person's from then on. Call it
    /// once the camera screen shows. It does nothing while the helper is on.
    ///
    /// Side effects: may store that night mode is no longer the helper's.
    ///
    /// - Parameter settings: The person's settings, where the record is stored.
    public func forgetNightModeFromAstroAtLaunch(settings: NopeSettings) {
        guard !astro.isOn, settings.isNightModeFromAstro else { return }
        settings.setNightModeFromAstro(false)
    }

    /// The helper's starting values for the selected lens, when it can turn on now: it is off,
    /// nothing is being taken, the camera can take photos, storage and battery can be read, no
    /// interval series runs, and the lens suits it.
    ///
    /// - Returns: The values, or `nil` when the helper can't turn on.
    private func astroExposureIfItCanTurnOn() -> AstroExposure? {
        guard !astro.isOn, !drive.isBusy, !astro.isRunning, canCapture, deviceStatus.canRead,
            manual.intervalProgress == nil, let lens = selectedLens
        else { return nil }
        return AstroModel.startingExposure(for: lens)
    }

    /// Turns the helper on and sets up the camera for it.
    ///
    /// - Parameter exposure: The helper's starting values for the selected lens.
    private func turnOnAstro(_ exposure: AstroExposure) async {
        drive.setMode(.single)
        await light.handle(.setTorch(false))
        if !manual.isEnabled {
            await send(.manual(.setEnabled(true)))
            astro.turnedOnManualControls = true
        }
        astro.setOn(true)
        await send(.manual(.setBracket(nil)))
        await applyAstroExposure(exposure)
    }

    /// Sets focus, shutter and ISO to the helper's starting values. The shutter is set before
    /// ISO, so on a lens without shutter priority the second value replaces the ISO the first
    /// one fixed.
    ///
    /// - Parameter exposure: The values for the selected lens.
    private func applyAstroExposure(_ exposure: AstroExposure) async {
        await send(.manual(.setValue(.focus, exposure.focus)))
        await send(.manual(.setValue(.shutter, exposure.shutter)))
        await send(.manual(.setValue(.iso, exposure.iso)))
    }

    /// Turns the helper off, stopping a run, and turns manual controls and night mode off again
    /// if the helper turned them on (``setAstro(_:settings:)``).
    private func turnOffAstro() async {
        guard astro.isOn else { return }
        stopAstroRun()
        astro.setOn(false)
        if let settings = astro.nightModeSettings {
            astro.nightModeSettings = nil
            settings.nightModeAstroDidEnd()
        }
        if astro.turnedOnManualControls {
            astro.turnedOnManualControls = false
            await send(.manual(.setEnabled(false)))
        }
    }

    /// Stops the countdown before the first frame, the running or paused frames, or the
    /// countdown before a paused run continues.
    private func stopAstroRun() {
        guard astro.isOn else { return }
        if astro.isRunning { astro.requestStop() }
        drive.countdown.cancel()
    }

    /// Keeps the helper consistent after a manual control intent: turning manual controls off
    /// turns the helper off, because its frames need them; turning them on from elsewhere (the
    /// "Manual controls" option) makes them the person's, so the helper leaves them on.
    ///
    /// - Parameter intent: The manual control intent that was handled.
    func manualControlsDidChange(after intent: ManualControlIntent) async {
        guard astro.isOn, case .setEnabled(let isOn) = intent else { return }
        astro.turnedOnManualControls = false
        if !isOn { await turnOffAstro() }
    }

    /// Turns manual controls on or off and stores the choice as the "Manual controls" option
    /// (``NopeSettings/showsManualControls``). Use it for every control that turns manual
    /// controls on or off, such as a Manual Controls button.
    ///
    /// Storing the option alone isn't enough: the astro helper turns manual controls on without
    /// changing the option, so storing "off" while the helper had turned them on changes no
    /// stored value, and an interface that follows the option (a SwiftUI `.task(id:)`) sends
    /// nothing. This call stores the option and sends ``ManualControlIntent/setEnabled(_:)``
    /// itself, so turning manual controls off always turns them and the helper off. An interface
    /// that also follows the option may send the same intent again; it changes nothing then.
    ///
    /// Side effects: as ``ManualControlIntent/setEnabled(_:)``; off returns every control to
    /// automatic and turns the astro helper off.
    ///
    /// - Parameters:
    ///   - isOn: Whether manual controls are on.
    ///   - settings: The person's settings, where the option is stored.
    public func setManualControls(_ isOn: Bool, settings: NopeSettings) async {
        settings.setShowsManualControls(isOn)
        await send(.manual(.setEnabled(isOn)))
    }

    /// Applies the helper to a newly selected lens: its starting values for that lens, or the
    /// helper turns off on a lens it can't use.
    func astroLensDidChange() async {
        guard astro.isOn else { return }
        guard let lens = selectedLens, let exposure = AstroModel.startingExposure(for: lens) else {
            await turnOffAstro()
            return
        }
        await applyAstroExposure(exposure)
    }

    /// Whether a light intent is refused because the helper is on: the light must stay off for
    /// night sky frames, and it would ruin dark-adapted eyes.
    ///
    /// - Parameter intent: The light intent.
    func astroRefuses(_ intent: LightIntent) -> Bool {
        astro.isOn && intent == .setTorch(true)
    }

    /// The shutter while the helper is on: stops a countdown or a run, or starts the self-timer
    /// and then the run.
    func pressAstroShutter() {
        if drive.countdown.isRunning || astro.isRunning {
            stopAstroRun()
            return
        }
        guard canCapture else { return }
        drive.countdown.start(seconds: astro.startDelay.seconds) { [weak self] in
            await self?.takeAstroFrames()
        }
    }

    /// Takes the run's frames, after the countdown.
    private func takeAstroFrames() async {
        await takeFrames(limit: astro.frameCount, tracker: astro, stopsOnLowBattery: true, pausesWithCamera: true)
    }

    /// Records whether the app is in the foreground, and applies it to the self-timer and the
    /// astro helper (``CameraIntent/setInForeground(_:)``).
    ///
    /// - Parameter isInForeground: Whether the app is in the foreground now.
    func setInForeground(_ isInForeground: Bool) {
        self.isInForeground = isInForeground
        guard !isInForeground else { return }
        guard astro.isOn else {
            // The camera stops in the background, so the self-timer can't take its photo.
            drive.countdown.cancel()
            return
        }
        guard drive.countdown.isRunning, !astro.isRunning, saver != nil else { return }
        // Left during the start delay: the run starts now, paused, and counts the delay down
        // again when the app is back. It is marked as begun at once, so it reads as paused, not
        // ended, before its loop starts.
        drive.countdown.cancel()
        astro.beginRun()
        Task { [weak self] in await self?.takeAstroFrames() }
    }

    /// Whether an astro run or an interval series should pause: the app is out of the
    /// foreground, or the camera is paused for a while (an interruption, heat, or starting
    /// again).
    var seriesShouldPause: Bool {
        guard isInForeground else { return true }
        switch sessionStatus {
        case .starting, .interrupted, .pausedForHeat: return true
        case .stopped, .running, .failed, .noPicture: return false
        }
    }

    /// Pauses the astro run until the app is in the foreground and the camera can take photos
    /// again, then counts the start delay down so the phone is still before the next frame. It
    /// waits for Observation's change notifications; nothing polls (AGENTS.md, "Battery").
    ///
    /// - Returns: `false` when the person stopped the run, `true` to continue: the run then
    ///   checks the camera, storage and battery again before the next frame.
    func pauseAstroRun() async -> Bool {
        astro.setPaused(true)
        while seriesShouldPause, !astro.isStopRequested {
            await nextChangeOfPauseState()
        }
        astro.setPaused(false)
        guard !astro.isStopRequested else { return false }
        guard sessionStatus.canCapture else { return true }
        let counted = await drive.countdown.run(seconds: astro.startDelay.seconds)
        return counted && !astro.isStopRequested
    }

    /// Waits until the foreground state, the camera's status or the stop request changes.
    private func nextChangeOfPauseState() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = isInForeground
                _ = sessionStatus
                _ = astro.isStopRequested
            } onChange: {
                continuation.resume()
            }
        }
    }
}
