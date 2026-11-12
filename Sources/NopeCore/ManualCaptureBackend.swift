import Foundation

/// A ``CaptureBackend`` that can also set the camera's exposure, focus and white balance, report
/// what the camera is using, and take exposure brackets.
///
/// `NopeCapture`'s AVFoundation backend and ``SimulatedCaptureBackend`` implement it. A backend
/// that doesn't simply has no manual controls: ``ManualControlsModel`` then offers none.
public protocol ManualCaptureBackend: CaptureBackend {
    /// What the camera is using now, sent while readings are on
    /// (``setExposureReadingsEnabled(_:)``), at a reduced rate. ``ManualControlsModel/observeReadings()``
    /// is its only consumer. The stream ends when the backend is released.
    var exposureReadings: AsyncStream<ExposureReading> { get }

    /// Sets exposure, focus, white balance and metering on the running camera.
    ///
    /// Starting the camera or switching lenses returns every control to automatic, so
    /// ``ManualControlsModel`` applies its controls again after each start.
    ///
    /// - Parameter controls: The controls, already checked against the lens.
    /// - Throws: ``CaptureError/notRunning`` if the camera isn't running, or
    ///   ``CaptureError/configurationFailed`` if the camera refused the change.
    func applyControls(_ controls: DeviceControls) async throws(CaptureError)

    /// Turns the readings on or off. They are off by default and are on only while manual
    /// controls are shown, so nothing is measured ahead of need (AGENTS.md, "Battery").
    ///
    /// - Parameter enabled: Whether to send readings.
    func setExposureReadingsEnabled(_ enabled: Bool) async

    /// Takes an exposure bracket: one separate single-frame photo per frame, nothing merged.
    ///
    /// - Parameters:
    ///   - request: The lens and format; the same as the last ``CaptureBackend/startSession(_:)``.
    ///   - frames: Each frame's exact ISO and exposure duration, no more than the lens's
    ///     ``Lens/maxBracketedPhotoCount``.
    /// - Returns: The photos, in the order of `frames`.
    /// - Throws: ``CaptureError/notRunning`` if the camera isn't running,
    ///   ``CaptureError/blankPicture`` if any frame is blank (every frame is dropped), or
    ///   ``CaptureError/captureFailed`` if the system reports an error or too few photos.
    func captureBracket(_ request: CaptureRequest, frames: [BracketFrame]) async throws(CaptureError)
        -> [CapturedPhoto]
}

/// A request an interface sends to change manual controls, wrapped in
/// ``CameraIntent/manual(_:)``.
///
/// None of these has an effect while manual controls are off (``ManualControlsModel/isEnabled``),
/// except ``setEnabled(_:)``.
public enum ManualControlIntent: Equatable, Sendable {
    /// Turn manual controls on or off: the "Manual controls" option in Settings. Turning them
    /// off returns everything to automatic and stops an interval series.
    case setEnabled(Bool)

    /// Set a control to a value, switching it to Manual. Units: EV for exposure compensation,
    /// ISO, seconds for the shutter, an f-number for the aperture, 0 (closest) to 1 (far) for
    /// focus, and kelvin for white balance (the tint is kept). The value is moved inside the
    /// lens's range.
    case setValue(ManualControl, Double)

    /// Set the white balance tint, switching white balance to Manual.
    case setTint(Double)

    /// Set the white balance from a preset.
    case setWhiteBalancePreset(WhiteBalancePreset)

    /// Move a control a number of steps along its ``ControlScale``, switching it to Manual.
    /// VoiceOver's adjustable action sends ±1.
    case step(ManualControl, by: Int)

    /// Return one control to Auto. Exposure compensation returns to 0.
    case setAuto(ManualControl)

    /// Switch to an exposure mode: Program sets ISO and shutter to Auto; S, I and M keep or take
    /// the values in use.
    case setExposureMode(ExposureMode)

    /// Choose how auto exposure measures the scene.
    case setMetering(MeteringMode)

    /// Lock or unlock auto exposure (AE-L).
    case setExposureLock(Bool)

    /// Lock or unlock autofocus (AF-L).
    case setFocusLock(Bool)

    /// Return every control to automatic in one step ("All Auto").
    case allAuto

    /// Turn exposure bracketing on with settings, or off with `nil`.
    case setBracket(BracketSettings?)

    /// Choose the interval and photo count of the next interval series.
    case setInterval(IntervalSettings)

    /// Start an interval series with the chosen settings.
    case startInterval

    /// Stop a running interval series.
    case stopInterval
}
