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
    public private(set) var settings = ManualSettings.automatic

    /// What the camera is using now, or `nil` before the first reading or while manual controls
    /// are off.
    public private(set) var reading: ExposureReading?

    /// The exposure bracket for the next photo, or `nil` when bracketing is off.
    public private(set) var bracket: BracketSettings?

    /// The interval and photo count of the next interval series.
    public private(set) var interval = IntervalSettings.standard

    /// The running interval series, or `nil` when none is running.
    public private(set) var intervalProgress: IntervalProgress?

    /// The selected lens, or `nil` before the camera is ready.
    public private(set) var lens: Lens?

    /// The hardware, or `nil` when the backend has no manual controls.
    private let backend: (any ManualCaptureBackend)?

    /// Waits between interval photos; the time is in seconds.
    private let sleep: @Sendable (Double) async throws -> Void

    /// The running interval series.
    private var intervalTask: Task<Void, Never>?

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
        if let bracket, !BracketSettings.frameCounts(for: lens).contains(bracket.frameCount) {
            self.bracket = nil
        }
    }

    /// Applies the settings again after the camera started, because starting it returns every
    /// control to automatic. Does nothing in full auto.
    func sessionDidStart() async {
        guard isEnabled, !settings.isAutomatic else { return }
        await apply(restoringOnFailure: settings)
    }

    /// The frames of the next photo's exposure bracket, or `nil` for a single photo: bracketing
    /// is off, the lens reports no ISO or shutter range, or there is no exposure to start from
    /// yet. The bracket always fits the lens: ``lensWillStart(_:)`` drops one that doesn't.
    ///
    /// The base exposure is the person's ISO and shutter where set, otherwise the camera's
    /// reading, which already includes exposure compensation.
    func bracketFrames() -> [BracketFrame]? {
        guard isEnabled, let bracket, let lens, let isoRange = lens.isoRange, let durationRange = lens.exposureDurationRange,
            let iso = value(of: .iso), let duration = value(of: .shutter)
        else { return nil }
        return BracketFrame.plan(
            offsets: bracket.offsets, base: BracketFrame(iso: iso, exposureDuration: duration),
            shutterFirst: settings.shutter == nil || settings.iso != nil, isoRange: isoRange,
            durationRange: durationRange)
    }

    /// Applies the backend's readings until its stream ends. Interfaces
    /// run it in a `.task` while the camera is visible. Returns at once without manual controls.
    public func observeReadings() async {
        guard let backend else { return }
        for await reading in backend.exposureReadings where isEnabled {
            self.reading = reading
        }
    }

    /// Handles one intent. ``CameraModel/send(_:)`` calls it.
    ///
    /// Settings intents and starting a series have no effect while manual controls are off.
    ///
    /// - Parameters:
    ///   - intent: The intent.
    ///   - capture: Takes one photo the way the shutter does; used by interval shooting.
    func handle(_ intent: ManualControlIntent, capture: @escaping @MainActor () async -> Void) async {
        var next = settings
        switch intent {
        case .setEnabled(let enabled):
            await setEnabled(enabled)
            return
        case .setBracket(let bracket):
            if isEnabled { setBracket(bracket) }
            return
        case .setInterval(let interval):
            self.interval = interval
            return
        case .startInterval:
            if isEnabled { startInterval(capture: capture) }
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
        }
        guard isEnabled, next != settings else { return }
        let previous = settings
        settings = next
        await apply(restoringOnFailure: previous)
    }

    // MARK: - Rules

    /// Turns manual controls on or off. Off returns everything to automatic and stops a series.
    ///
    /// - Parameter enabled: Whether manual controls are on.
    private func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        await backend?.setExposureReadingsEnabled(enabled)
        guard !enabled else { return }
        stopInterval()
        bracket = nil
        reading = nil
        let previous = settings
        settings = .automatic
        if previous != settings { await apply(restoringOnFailure: previous) }
    }

    /// Turns bracketing on with settings the lens supports, or off.
    ///
    /// - Parameter bracket: The bracket, or `nil` to turn it off.
    private func setBracket(_ bracket: BracketSettings?) {
        guard let bracket else {
            self.bracket = nil
            return
        }
        if bracketFrameCounts.contains(bracket.frameCount), BracketSettings.steps.contains(bracket.step) {
            self.bracket = bracket
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
    private func apply(restoringOnFailure previous: ManualSettings) async {
        guard let backend, let lens else { return }
        do {
            try await backend.applyControls(DeviceControls(settings: settings, lens: lens))
        } catch .configurationFailed {
            settings = previous
        } catch {
            // Not running: sessionDidStart() applies the settings when the camera starts.
        }
    }

    // MARK: - Interval shooting

    /// Starts an interval series: takes a photo, waits ``interval``, and repeats until
    /// ``IntervalSettings/count`` photos are taken or the series is stopped. A photo the camera
    /// can't take, for example during a pause, is skipped and still counted.
    ///
    /// - Parameter capture: Takes one photo.
    private func startInterval(capture: @escaping @MainActor () async -> Void) {
        guard intervalProgress == nil else { return }
        let series = interval
        intervalProgress = IntervalProgress(taken: 0, total: series.count)
        intervalTask = Task {
            for taken in 1...series.count {
                await capture()
                guard !Task.isCancelled else { return }
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

    /// Stops the running interval series, if any.
    private func stopInterval() {
        intervalTask?.cancel()
        intervalTask = nil
        intervalProgress = nil
    }
}
