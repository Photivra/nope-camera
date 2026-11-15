import Foundation

/// The automatic aids: tap to focus and expose, the focus and exposure lock, exposure
/// compensation in full auto, the near focus limit, the fast shutter rule and the hints (issues
/// #35, #41, #51 and #56).
///
/// They work with manual controls off as well as on, and never change a manual setting: each
/// aid is added to the person's settings by ``DeviceControls/init(settings:lens:assist:)`` only
/// where that part of the camera is still automatic. ``CameraModel`` calls these methods for
/// ``AutoControlIntent`` values.
extension ManualControlsModel {
    /// The aids to send with the person's settings. The fast shutter limit is full auto's alone:
    /// with manual controls on, the person decides.
    var assist: AssistSettings {
        AssistSettings(
            focusTarget: focusTarget, nearFocusLimit: nearFocusLimit, longestShutter: isEnabled ? nil : longestAutoShutter)
    }

    /// Whether the selected lens can set exposure compensation now.
    public var canAdjustExposureCompensation: Bool {
        availability(of: .exposureCompensation) == .adjustable
    }

    // MARK: - Intents

    /// Aims autofocus and auto exposure at a point.
    ///
    /// - Parameters:
    ///   - viewfinderPoint: The point in the viewfinder, as drawn.
    ///   - devicePoint: The same point in the camera's coordinates.
    ///   - locks: Whether to lock focus and exposure there once they have adjusted.
    ///
    /// Does nothing on a lens without a focus or exposure point (some front cameras).
    func focus(at viewfinderPoint: FramePoint, devicePoint: FramePoint, locks: Bool) async {
        guard capabilities.supportsTapToFocus else { return }
        focusTarget = FocusTarget(viewfinderPoint: viewfinderPoint, devicePoint: devicePoint, isLocked: locks)
        await applyCurrentControls()
    }

    /// Returns focus and exposure to continuous auto at the center.
    func unlockFocus() async {
        guard focusTarget != nil else { return }
        focusTarget = nil
        await applyCurrentControls()
    }

    /// Sets exposure compensation, in EV, inside the lens's range. Works in full auto (issue
    /// #41) as well as with manual controls.
    ///
    /// - Parameter value: The compensation, in EV.
    func setExposureCompensation(_ value: Double) async {
        guard canAdjustExposureCompensation, let scale = scale(for: .exposureCompensation) else { return }
        let limited = value.limited(to: scale.range)
        guard limited != settings.exposureCompensation else { return }
        let previous = settings
        settings.exposureCompensation = limited
        await apply(restoringOnFailure: previous)
    }

    /// Moves exposure compensation a number of steps along its scale.
    ///
    /// - Parameter steps: How many steps, negative for darker.
    func stepExposureCompensation(by steps: Int) async {
        guard let scale = scale(for: .exposureCompensation) else { return }
        await setExposureCompensation(scale.value(from: settings.exposureCompensation, steppedBy: steps))
    }

    /// Turns the near focus limit on or off.
    ///
    /// - Parameter isOn: Whether autofocus is limited to near subjects. Turning it on does
    ///   nothing on a lens that can't limit its range.
    func setNearFocusLimit(_ isOn: Bool) async {
        guard isOn != nearFocusLimit, !isOn || capabilities.supportsNearFocusLimit else { return }
        nearFocusLimit = isOn
        await applyCurrentControls()
    }

    /// Chooses how fast a shutter full auto prefers, and applies the new limit.
    ///
    /// - Parameter choice: The choice.
    func setFastShutter(_ choice: FastShutter) async {
        guard choice != fastShutter else { return }
        fastShutter = choice
        guard let lens else { return }
        let limit = lastReading.map {
            AutoShutter.longestShutter(for: $0, lens: lens, fastShutter: choice, current: nil)
        } ?? AutoShutter.limits(for: lens, fastShutter: choice).first
        await setLongestAutoShutter(limit)
    }

    /// Hides the close-up suggestion until the lens changes.
    func dismissCloseUpSuggestion() {
        closeUpDismissed = true
        suggestsCloseUpLens = false
    }

    // MARK: - Camera events

    /// Returns autofocus and exposure to the center when the scene changed, unless they are
    /// locked (`AVCaptureDevice.subjectAreaDidChangeNotification`, issue #35).
    func subjectAreaDidChange() async {
        guard let focusTarget, !focusTarget.isLocked else { return }
        await unlockFocus()
    }

    /// Applies one reading to the aids: the fast shutter limit in full auto, the steady hint and
    /// the close-up suggestion.
    ///
    /// - Parameter reading: What the camera is using now.
    func record(_ reading: ExposureReading) async {
        lastReading = reading
        guard let lens else { return }
        if closeUpDismissed || settings.focus != nil || focusTarget?.isLocked == true {
            // Manual focus or a lock is the person's choice; nothing to suggest.
            closeUpDetector = CloseUpDetector()
            suggestsCloseUpLens = false
        } else {
            suggestsCloseUpLens = closeUpDetector.record(reading)
        }
        if !isEnabled {
            await setLongestAutoShutter(
                AutoShutter.longestShutter(
                    for: reading, lens: lens, fastShutter: fastShutter, current: longestAutoShutter))
        }
        updateSteadyHint()
    }

    // MARK: - Helpers

    /// Turns the camera's readings on, once.
    func startReadings() async {
        guard let backend, !readingsStarted else { return }
        readingsStarted = true
        await backend.setExposureReadingsEnabled(true)
    }

    /// Clears what belonged to the previous lens: the tapped point, the close-up state and the
    /// hint, and starts the new lens at its fastest fast-shutter limit until it reports a
    /// reading.
    func resetAidsForNewLens() {
        focusTarget = nil
        closeUpDetector = CloseUpDetector()
        closeUpDismissed = false
        suggestsCloseUpLens = false
        showsSteadyHint = false
        lastReading = nil
        longestAutoShutter = lens.flatMap { AutoShutter.limits(for: $0, fastShutter: fastShutter).first }
    }

    /// Clears the tapped point and the near focus limit, for All Auto.
    ///
    /// - Returns: Whether anything changed.
    func resetAids() -> Bool {
        let changed = focusTarget != nil || nearFocusLimit
        focusTarget = nil
        nearFocusLimit = false
        return changed
    }

    /// Sets the full-auto limit and applies it when it changed.
    ///
    /// - Parameter limit: The longest shutter in seconds, or `nil` to lift the limit.
    func setLongestAutoShutter(_ limit: Double?) async {
        guard limit != longestAutoShutter else { return }
        longestAutoShutter = limit
        if !isEnabled { await applyCurrentControls() }
        updateSteadyHint()
    }

    /// Decides whether to show "Hold it steady or use a tripod".
    ///
    /// - Full auto: when the fast shutter limit had to be lifted past the handheld rule.
    /// - Manual controls: when the person's shutter, or the camera's while it is Auto, is slower
    ///   than the handheld rule. The app changes nothing; it only says so.
    func updateSteadyHint() {
        guard let lens, let lastReading else {
            showsSteadyHint = false
            return
        }
        if isEnabled {
            showsSteadyHint = AutoShutter.risksBlur(settings.shutter ?? lastReading.exposureDuration, on: lens)
        } else {
            showsSteadyHint =
                longestAutoShutter == nil && lens.isoRange != nil && AutoShutter.handheldLimit(for: lens) != nil
        }
    }

    /// Sends the settings and aids to the camera. If it refuses, nothing is kept from the
    /// change except what the interface shows; if it isn't running, the controls are applied
    /// when it starts.
    func applyCurrentControls() async {
        await apply(restoringOnFailure: settings)
    }
}
