import Foundation
import Observation

/// The manual and pro controls: the state behind the control grid, the exposure modes, the
/// locks, bracketing and interval shooting.
///
/// ``CameraModel`` owns one as ``CameraModel/manual``. An interface reads its properties and
/// sends ``ManualControlIntent`` values through ``CameraModel/send(_:)`` as
/// ``CameraIntent/manual(_:)``. Every rule lives here: which controls a lens offers
/// (``availability(of:)``), the steps of each control (``scale(for:)``), and how the exposure
/// modes combine. Full auto is the default, and manual controls stay hidden until the "Manual
/// controls" option turns them on (``isEnabled``).
@MainActor
@Observable
public final class ManualControlsModel {
    /// ISO to start from when a control is first set before the camera has reported a reading.
    static let fallbackISO = 100.0

    /// Shutter to start from before the first reading, in seconds: 1/60 s.
    static let fallbackShutter = 1.0 / 60.0

    /// Focus to start from before the first reading: the middle of the relative scale.
    static let fallbackFocus = 0.5

    /// Whether manual controls are on (the "Manual controls" option). Off by default.
    public private(set) var isEnabled = false

    /// The person's settings. ``ManualSettings/automatic`` (full auto) by default.
    public internal(set) var settings = ManualSettings.automatic

    /// What the camera is using now, or `nil` before the first reading or while manual controls
    /// are off.
    public private(set) var reading: ExposureReading?

    /// The exposure bracket for the next press of the shutter, or `nil` when bracketing is off.
    /// It works in full auto and with manual controls on (docs/design/BRACKETING.md, decision
    /// 2). An interface shows it as the drive strip's Bracket word.
    public private(set) var bracket: BracketSettings?

    /// The bracket chosen last in this session: the one an interface turns on again when the
    /// person chooses Bracket. ``BracketSettings/standard`` at first. Not stored between launches,
    /// as the drive mode isn't (AGENTS.md, "Cognitive": no surprise modes).
    public private(set) var lastBracket = BracketSettings.standard

    /// The interval and photo count of the next interval series.
    public private(set) var interval = IntervalSettings.standard

    /// The running interval series, or `nil` when none is running.
    public private(set) var intervalProgress: IntervalProgress?

    /// The selected lens, or `nil` before the camera is ready.
    public private(set) var lens: Lens?

    /// The hardware, or `nil` when the backend has no manual controls.
    let backend: (any ManualCaptureBackend)?

    /// Waits between interval photos; the time is in seconds.
    private let sleep: @Sendable (Double) async throws -> Void

    /// The running interval series.
    private var intervalTask: Task<Void, Never>?

    // MARK: Automatic aids (ManualControlsModel+Auto.swift)

    /// Where autofocus and auto exposure are aimed after a tap, and whether they are locked
    /// there, or `nil` for continuous auto at the center. Cleared when the scene changes (unless
    /// locked), on a lens change and by All Auto.
    public internal(set) var focusTarget: FocusTarget?

    /// Whether autofocus is limited to near subjects (Close-Up). Off by default; reset by All
    /// Auto.
    public internal(set) var nearFocusLimit = false

    /// Whether autofocus is limited to far subjects (Far Focus, issue #57). Off by default; never
    /// on with ``nearFocusLimit``; reset by All Auto.
    public internal(set) var farFocusLimit = false

    /// Whether faces the camera detects steer autofocus and auto exposure. On by default, the
    /// system's behavior; the app sets it from the person's Face Detection setting
    /// (``AutoControlIntent/setFollowsFaces(_:)``). All Auto doesn't change it.
    public internal(set) var followsFaces = true

    /// How fast a shutter full auto prefers. ``FastShutter/handheld`` by default.
    public internal(set) var fastShutter = FastShutter.handheld

    /// Whether the camera should say "Hold it steady or use a tripod": in full auto when the
    /// light is too low for a handheld-safe shutter, and with manual controls when the shutter
    /// chosen or in use is slower than that.
    public internal(set) var showsSteadyHint = false

    /// Whether the subject seems closer than the lens can focus, so an interface may suggest
    /// the ultra wide lens (``CameraModel/closeUpLens``).
    public internal(set) var suggestsCloseUpLens = false

    /// The longest shutter full auto allows now, in seconds, or `nil` when the limit is lifted
    /// or the lens has none (``AutoShutter``).
    var longestAutoShutter: Double?

    /// The camera's last reading, in full auto too, for the fast shutter rule and the hints.
    var lastReading: ExposureReading?

    /// Watches for a subject that is too close to focus.
    var closeUpDetector = CloseUpDetector()

    /// Whether the person dismissed the close-up suggestion on this lens.
    var closeUpDismissed = false

    /// Whether the readings were turned on.
    var readingsStarted = false

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - backend: The hardware, or `nil` when it has no manual controls.
    ///   - sleep: Waits a number of seconds between interval photos, throwing when cancelled.
    public init(
        backend: (any ManualCaptureBackend)?,
        sleep: @escaping @Sendable (Double) async throws -> Void
    ) {
        self.backend = backend
        self.sleep = sleep
    }

    // MARK: - What an interface reads

    /// Whether the backend offers manual controls at all. When it's `false`, an interface
    /// shouldn't offer the "Manual controls" option.
    public var isSupported: Bool {
        backend != nil
    }

    /// The selected lens's manual capabilities.
    public var capabilities: ManualCapabilities {
        lens?.manualControls ?? .none
    }

    /// Whether a control can be used on the selected lens now, and if not, why.
    ///
    /// - Parameter control: A control.
    /// - Returns: The control's availability.
    public func availability(of control: ManualControl) -> ControlAvailability {
        guard let lens else { return .unavailable }
        let capabilities = lens.manualControls
        switch control {
        case .exposureCompensation:
            guard scale(for: control) != nil else { return .unavailable }
            return settings.iso != nil && settings.shutter != nil ? .blockedByManualExposure : .adjustable
        case .iso:
            let settable = capabilities.supportsManualExposure || capabilities.supportsISOPriority
            return settable && lens.isoRange != nil ? .adjustable : .unavailable
        case .shutter:
            let settable = capabilities.supportsManualExposure || capabilities.supportsShutterPriority
            return settable && lens.exposureDurationRange != nil ? .adjustable : .unavailable
        case .aperture:
            guard let aperture = lens.aperture else { return .unavailable }
            guard aperture.isVariable else { return .fixed(aperture.minimumFNumber) }
            return capabilities.supportsAperturePriority ? .adjustable : .unavailable
        case .focus:
            return capabilities.supportsManualFocus ? .adjustable : .unavailable
        case .whiteBalance:
            return capabilities.supportsManualWhiteBalance ? .adjustable : .unavailable
        }
    }

    /// The steps of a control on the selected lens (``ControlScale/scale(for:on:)``), or `nil`.
    ///
    /// - Parameter control: A control.
    public func scale(for control: ManualControl) -> ControlScale? {
        lens.flatMap { ControlScale.scale(for: control, on: $0) }
    }

    /// The value a control has now: the person's value when it is Manual, otherwise the
    /// camera's reading. In the control's unit (see ``ManualControlIntent/setValue(_:_:)``).
    ///
    /// - Parameter control: A control.
    /// - Returns: The value, or `nil` before the first reading.
    public func value(of control: ManualControl) -> Double? {
        switch control {
        case .exposureCompensation: settings.exposureCompensation
        case .iso: settings.iso ?? reading?.iso
        case .shutter: settings.shutter ?? reading?.exposureDuration
        case .aperture: settings.aperture ?? reading?.aperture ?? lens?.aperture?.minimumFNumber
        case .focus: settings.focus ?? reading?.lensPosition
        case .whiteBalance: settings.whiteBalance?.temperature ?? reading?.whiteBalance?.temperature
        }
    }

    /// The white balance tint in use: the person's when white balance is Manual, otherwise the
    /// camera's reading, otherwise 0.
    public var tint: Double {
        settings.whiteBalance?.tint ?? reading?.whiteBalance?.tint ?? 0
    }

    /// The exposure modes the selected lens offers, in the order P, S, I, M.
    public var exposureModes: [ExposureMode] {
        capabilities.exposureModes
    }

    /// Whether AE-L can be turned on: the lens supports it and ISO, shutter and aperture are Auto.
    public var canLockExposure: Bool {
        capabilities.supportsExposureLock && settings.iso == nil && settings.shutter == nil && settings.aperture == nil
    }

    /// Whether AF-L can be turned on: the lens supports it and focus is Auto.
    public var canLockFocus: Bool {
        capabilities.supportsFocusLock && settings.focus == nil
    }

    /// The bracket frame counts the selected lens offers; empty when it can't bracket.
    public var bracketFrameCounts: [Int] {
        lens.map(BracketSettings.frameCounts(for:)) ?? []
    }

    // MARK: - Calls from CameraModel

    /// Records the lens the camera is about to use. Switching to another lens drops the last
    /// reading, which belonged to the old lens, and a bracket longer than the new lens allows.
    ///
    /// - Parameter lens: The selected lens.
    func lensWillStart(_ lens: Lens) {
        guard lens != self.lens else { return }
        if self.lens != nil { reading = nil }
        self.lens = lens
        resetAidsForNewLens()
        if let bracket, !BracketSettings.frameCounts(for: lens).contains(bracket.frameCount) {
            self.bracket = nil
        }
    }

    /// Applies the settings again after the camera started, because starting it returns every
    /// control to automatic. Does nothing in full auto.
    func sessionDidStart() async {
        await startReadings()
        guard let lens, DeviceControls(settings: settings, lens: lens, assist: assist) != .automatic else { return }
        await apply(restoringOnFailure: settings)
    }

    /// The frames the next press of the shutter takes, as an interface lists them in Bracket
    /// Settings, or `nil` for a single photo: bracketing is off, the lens reports no ISO or
    /// shutter range, or there is nothing to plan from yet (see ``bracketFrames(once:)``). The
    /// bracket always fits the lens: ``lensWillStart(_:)`` drops one that doesn't. It follows the camera's readings, so it changes as the light
    /// does; the bracket is planned again from the reading when the shutter is pressed.
    public var bracketPlan: [BracketFramePlan]? {
        bracket.flatMap(bracketPlan(once:))
    }

    /// Whether the selected lens can take this bracket: it reports ISO and shutter ranges, the
    /// frame count is one ``bracketFrameCounts`` offers, and the step is one of
    /// ``BracketSettings/steps``. The same limits as the bracket the drive strip turns on.
    ///
    /// - Parameter bracket: The bracket.
    func canBracket(_ bracket: BracketSettings) -> Bool {
        lens?.isoRange != nil && lens?.exposureDurationRange != nil
            && bracketFrameCounts.contains(bracket.frameCount) && BracketSettings.steps.contains(bracket.step)
    }

    /// The frames of a bracket taken once, for a Siri or Shortcuts request (issue #62), whether
    /// or not manual controls are on. It leaves ``bracket`` and every setting as they are.
    ///
    /// The base exposure is the person's ISO and shutter where set (only while manual controls
    /// are on; otherwise the settings are automatic), otherwise the camera's last reading.
    ///
    /// - Parameter bracket: The bracket.
    /// - Returns: The frames, or `nil` when the lens can't take it (``canBracket(_:)``) or the
    ///   camera hasn't reported an exposure yet.
    func bracketFrames(once bracket: BracketSettings) -> [BracketFrame]? {
        bracketPlan(once: bracket)?.map(\.frame)
    }

    /// Plans a bracket's frames around the base exposure, within the lens's ranges: the
    /// person's ISO and shutter where set (only while manual controls are on), otherwise the
    /// camera's last reading, which already includes exposure compensation. The parameter the
    /// person didn't set changes first, the shutter when neither is set.
    ///
    /// - Parameter bracket: The bracket.
    /// - Returns: One plan per frame, in the order taken, or `nil` when the lens can't take the
    ///   bracket or there is no base exposure yet.
    func bracketPlan(once bracket: BracketSettings) -> [BracketFramePlan]? {
        guard canBracket(bracket), let lens, let isoRange = lens.isoRange,
            let durationRange = lens.exposureDurationRange, let iso = settings.iso ?? lastReading?.iso,
            let duration = settings.shutter ?? lastReading?.exposureDuration
        else { return nil }
        return BracketFramePlan.plan(
            offsets: bracket.offsets, base: BracketFrame(iso: iso, exposureDuration: duration),
            shutterFirst: settings.shutter == nil || settings.iso != nil, isoRange: isoRange,
            durationRange: durationRange)
    }

    /// Whether the person set the shutter but not ISO, so a bracket changes ISO first; an
    /// interface says which value changes from frame to frame.
    public var bracketChangesISOFirst: Bool {
        settings.shutter != nil && settings.iso == nil
    }

    /// Applies the backend's readings until its stream ends. Interfaces
    /// run it in a `.task` while the camera is visible. Returns at once without manual controls.
    ///
    /// ``reading`` shows a reading only while manual controls are on; in full auto the readings
    /// drive the fast shutter rule and the hints (``record(_:)``).
    public func observeReadings() async {
        guard let backend else { return }
        for await reading in backend.exposureReadings {
            if isEnabled { self.reading = reading }
            await record(reading)
        }
    }

    /// Handles one intent. ``CameraModel/send(_:)`` calls it.
    ///
    /// Settings intents have no effect while manual controls are off. Interval shooting and
    /// bracketing work in full auto too (each photo is then a full-auto photo, and a bracket is
    /// planned around the camera's reading), so they always apply.
    ///
    /// - Parameters:
    ///   - intent: The intent.
    ///   - capture: Takes one photo of an interval series the way the shutter does, waiting
    ///     while the series is paused, and returns whether the photo was taken and saved.
    func handle(_ intent: ManualControlIntent, capture: @escaping @MainActor () async -> Bool) async {
        var next = settings
        switch intent {
        case .setEnabled(let enabled):
            await setEnabled(enabled)
            return
        case .setBracket(let bracket):
            setBracket(bracket)
            return
        case .setInterval(let interval):
            self.interval = interval
            return
        case .startInterval:
            startInterval(capture: capture)
            return
        case .stopInterval:
            stopInterval()
            return
        case .setValue(let control, let value):
            set(control, to: value, in: &next)
        case .step(let control, let steps):
            if let scale = scale(for: control), let current = startingValue(of: control) {
                set(control, to: scale.value(from: current, steppedBy: steps), in: &next)
            }
        case .setTint(let tint):
            if availability(of: .whiteBalance).isAdjustable {
                let temperature = value(of: .whiteBalance) ?? WhiteBalancePreset.daylight.whiteBalance.temperature
                next.whiteBalance = WhiteBalance(temperature: temperature, tint: tint).limited
            }
        case .setWhiteBalancePreset(let preset):
            if availability(of: .whiteBalance).isAdjustable { next.whiteBalance = preset.whiteBalance }
        case .setAuto(let control):
            setAuto(control, in: &next)
        case .setExposureMode(let mode):
            if exposureModes.contains(mode) { setExposureMode(mode, in: &next) }
        case .setMetering(let mode):
            if capabilities.meteringModes.contains(mode) { next.metering = mode }
        case .setExposureLock(let locked):
            if !locked || canLockExposure { next.exposureLocked = locked }
        case .setFocusLock(let locked):
            if !locked || canLockFocus { next.focusLocked = locked }
        case .allAuto:
            next = .automatic
            if isEnabled, resetAids(), next == settings {
                await applyCurrentControls()
                return
            }
        }
        guard isEnabled, next != settings else { return }
        let previous = settings
        settings = next
        await apply(restoringOnFailure: previous)
        updateSteadyHint()
    }

    // MARK: - Rules

    /// Turns manual controls on or off. Off returns everything to automatic; a running interval
    /// series continues, with full-auto photos from then on, and a bracket stays on, planned
    /// around the camera's reading from then on.
    ///
    /// - Parameter enabled: Whether manual controls are on.
    private func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defer { updateSteadyHint() }
        guard !enabled else {
            // Full auto's limit doesn't apply to manual controls; P is the camera's own exposure.
            if longestAutoShutter != nil { await applyCurrentControls() }
            return
        }
        reading = nil
        let previous = settings
        settings = .automatic
        if previous != settings || longestAutoShutter != nil { await apply(restoringOnFailure: previous) }
    }

    /// Turns bracketing on with settings the lens supports, or off. A bracket turned on becomes
    /// the session's ``lastBracket``.
    ///
    /// - Parameter bracket: The bracket, or `nil` to turn it off.
    private func setBracket(_ bracket: BracketSettings?) {
        guard let bracket else {
            self.bracket = nil
            return
        }
        if bracketFrameCounts.contains(bracket.frameCount), BracketSettings.steps.contains(bracket.step) {
            self.bracket = bracket
            lastBracket = bracket
        }
    }

    /// Sets one control to a value, moved inside the lens's range, and keeps the exposure mode
    /// possible on the lens: before iOS 27 there is no shutter or ISO priority, so setting one
    /// also fixes the other at the value in use (manual mode).
    ///
    /// - Parameters:
    ///   - control: The control.
    ///   - value: The new value, in the control's unit.
    ///   - next: The settings to change.
    private func set(_ control: ManualControl, to value: Double, in next: inout ManualSettings) {
        guard availability(of: control).isAdjustable, let scale = scale(for: control) else { return }
        let value = value.limited(to: scale.range)
        switch control {
        case .exposureCompensation:
            next.exposureCompensation = value
        case .iso:
            next.iso = value
            next.exposureLocked = false
            if next.shutter == nil, !capabilities.supportsISOPriority { next.shutter = snapped(.shutter) }
        case .shutter:
            next.shutter = value
            next.exposureLocked = false
            if next.iso == nil, !capabilities.supportsShutterPriority { next.iso = snapped(.iso) }
        case .aperture:
            next.aperture = value
            next.exposureLocked = false
        case .focus:
            next.focus = value
            next.focusLocked = false
        case .whiteBalance:
            next.whiteBalance = WhiteBalance(temperature: value, tint: tint).limited
        }
    }

    /// Returns one control to Auto, and keeps the exposure mode possible on the lens.
    ///
    /// - Parameters:
    ///   - control: The control.
    ///   - next: The settings to change.
    private func setAuto(_ control: ManualControl, in next: inout ManualSettings) {
        switch control {
        case .exposureCompensation:
            next.exposureCompensation = 0
        case .iso:
            next.iso = nil
            if !capabilities.supportsShutterPriority { next.shutter = nil }
        case .shutter:
            next.shutter = nil
            if !capabilities.supportsISOPriority { next.iso = nil }
        case .aperture:
            next.aperture = nil
        case .focus:
            next.focus = nil
        case .whiteBalance:
            next.whiteBalance = nil
        }
    }

    /// Switches to an exposure mode the lens supports.
    ///
    /// - Parameters:
    ///   - mode: The mode.
    ///   - next: The settings to change.
    private func setExposureMode(_ mode: ExposureMode, in next: inout ManualSettings) {
        switch mode {
        case .program:
            next.iso = nil
            next.shutter = nil
        case .shutterPriority:
            next.shutter = next.shutter ?? snapped(.shutter)
            next.iso = nil
        case .isoPriority:
            next.iso = next.iso ?? snapped(.iso)
            next.shutter = nil
        case .manual:
            next.iso = next.iso ?? snapped(.iso)
            next.shutter = next.shutter ?? snapped(.shutter)
        }
        if mode != .program { next.exposureLocked = false }
    }

    /// The scale value nearest to what ISO or the shutter is now, so a newly fixed value is a
    /// marked one.
    ///
    /// - Parameter control: ``ManualControl/iso`` or ``ManualControl/shutter``.
    /// - Returns: The value, or `nil` when the lens has no range for it.
    private func snapped(_ control: ManualControl) -> Double? {
        guard let scale = scale(for: control), let current = startingValue(of: control) else {
            return nil
        }
        return scale.values[scale.nearestIndex(to: current)]
    }

    /// The value a control starts from when it is changed: its current value, or before the
    /// camera has reported one, a common starting point.
    ///
    /// - Parameter control: A control.
    /// - Returns: The value, or `nil` for an aperture the lens doesn't report.
    private func startingValue(of control: ManualControl) -> Double? {
        switch control {
        case .exposureCompensation: settings.exposureCompensation
        case .iso: value(of: .iso) ?? Self.fallbackISO
        case .shutter: value(of: .shutter) ?? Self.fallbackShutter
        case .aperture: value(of: .aperture)
        case .focus: value(of: .focus) ?? Self.fallbackFocus
        case .whiteBalance: value(of: .whiteBalance) ?? WhiteBalancePreset.daylight.whiteBalance.temperature
        }
    }

    /// Sends the settings to the camera. If the camera refuses them, the settings go back to
    /// what they were; if it isn't running, they are applied when it starts.
    ///
    /// - Parameter previous: The settings to restore when the camera refuses.
    func apply(restoringOnFailure previous: ManualSettings) async {
        guard let backend, let lens else { return }
        do {
            try await backend.applyControls(DeviceControls(settings: settings, lens: lens, assist: assist))
        } catch .configurationFailed {
            settings = previous
        } catch {
            // Not running: sessionDidStart() applies the settings when the camera starts.
        }
    }

    // MARK: - Interval shooting

    /// Starts an interval series: takes a photo, waits ``interval``, and repeats until
    /// ``IntervalSettings/count`` photos are taken or the series is stopped. Only photos taken and
    /// saved are counted: `capture` waits while the series is paused (``setIntervalPaused(_:)``)
    /// instead of skipping a photo. A photo that can't be taken for another reason (the camera
    /// stopped for good, or the photo failed) ends the series, and the camera says why.
    ///
    /// - Parameter capture: Takes one photo and returns whether it was taken and saved.
    private func startInterval(capture: @escaping @MainActor () async -> Bool) {
        guard intervalProgress == nil else { return }
        let series = interval
        intervalProgress = IntervalProgress(taken: 0, total: series.count)
        intervalTask = Task {
            for taken in 1...series.count {
                let wasTaken = await capture()
                guard !Task.isCancelled else { return }
                guard wasTaken else { break }
                intervalProgress = IntervalProgress(taken: taken, total: series.count)
                guard taken < series.count else { break }
                do {
                    try await sleep(series.interval)
                } catch {
                    return
                }
            }
            intervalProgress = nil
            intervalTask = nil
        }
    }

    /// Marks the running series as paused or running again, for the camera screen and the Live
    /// Activity. Does nothing while no series runs.
    ///
    /// - Parameter isPaused: Whether the series is paused.
    func setIntervalPaused(_ isPaused: Bool) {
        guard let progress = intervalProgress, progress.isPaused != isPaused else { return }
        intervalProgress = IntervalProgress(taken: progress.taken, total: progress.total, isPaused: isPaused)
    }

    /// Stops the running interval series, if any.
    private func stopInterval() {
        intervalTask?.cancel()
        intervalTask = nil
        intervalProgress = nil
    }
}
