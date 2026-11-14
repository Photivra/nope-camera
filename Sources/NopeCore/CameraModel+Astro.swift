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

    /// Whether the helper can be turned on with the selected lens.
    public var canUseAstro: Bool {
        selectedLens.map(AstroModel.isAvailable(on:)) ?? false
    }

    /// Handles one astro intent.
    ///
    /// - Parameter intent: The intent.
    ///
    /// Side effects: turning the helper on may turn manual controls on, sets focus, shutter and
    /// ISO, and turns the light off; turning it off may turn manual controls off.
    func handle(_ intent: AstroIntent) async {
        let isIdle = !drive.isBusy && !astro.isRunning
        switch intent {
        case .setOn(true):
            guard !astro.isOn, isIdle, canCapture, manual.intervalProgress == nil else { return }
            await turnOnAstro()
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

    /// Turns the helper on and sets up the camera for it.
    private func turnOnAstro() async {
        guard let lens = selectedLens, let exposure = AstroModel.startingExposure(for: lens) else { return }
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

    /// Turns the helper off, stopping a run, and turns manual controls off again if the helper
    /// turned them on.
    private func turnOffAstro() async {
        guard astro.isOn else { return }
        stopAstroRun()
        astro.setOn(false)
        if astro.turnedOnManualControls {
            astro.turnedOnManualControls = false
            await send(.manual(.setEnabled(false)))
        }
    }

    /// Stops the countdown before the first frame or the running frames.
    private func stopAstroRun() {
        guard astro.isOn else { return }
        if astro.isRunning {
            astro.requestStop()
        } else {
            drive.countdown.cancel()
        }
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
        await takeFrames(limit: astro.frameCount, tracker: astro, stopsOnLowBattery: true)
    }
}
