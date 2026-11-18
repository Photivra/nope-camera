import Foundation

/// Exposure bracketing as a drive choice (docs/design/BRACKETING.md, section 3): Bracket is the
/// bracket that ``ManualControlsModel/bracket`` holds, with the drive mode Single, or the
/// self-timer when a start delay is set. There is no bracket drive mode.
///
/// - A bracket works in full auto and with manual controls on.
/// - Choosing Burst or Interval turns the bracket off (decision 3); turning a bracket on while
///   either is chosen chooses Single.
/// - Switching to a lens that can't take the bracket turns it off and chooses Single.
/// - An interval series never takes a bracket, however it was started.
extension CameraModel {
    /// Whether a press of the shutter takes the bracket: a bracket is on and the astro helper,
    /// which takes over the shutter, is off. An interface shows the Bracket word selected.
    public var isBracketOn: Bool {
        manual.bracket != nil && !astro.isOn
    }

    /// The drive mode an interface chooses with the bracket: Single, or the self-timer with the
    /// bracket's start delay (``bracketStartDelay``).
    public var bracketDriveMode: DriveMode {
        bracketStartDelay.map(DriveMode.timer) ?? .single
    }

    /// The bracket an interface turns on when the person chooses Bracket: the session's
    /// ``ManualControlsModel/lastBracket``, with as many frames as the selected lens can take,
    /// or `nil` when the lens can't bracket.
    public var bracketToTurnOn: BracketSettings? {
        // The counts a lens offers are the first of 3, 5 and 7, so the smaller of the two is one.
        guard let most = manual.bracketFrameCounts.last else { return nil }
        let last = manual.lastBracket
        return last.with(frameCount: min(last.frameCount, most))
    }

    /// Keeps the bracket and the drive mode together after the drive mode changed: Burst and
    /// Interval turn the bracket off; with a bracket on, Single and the self-timer's delay become
    /// the bracket's start delay.
    func driveModeDidChange() async {
        guard manual.bracket != nil else { return }
        switch drive.mode {
        case .burst, .interval:
            await send(.manual(.setBracket(nil)))
        case .single:
            bracketStartDelay = nil
        case .timer(let delay):
            bracketStartDelay = delay
        }
    }

    /// Keeps the drive mode a bracket can use after a manual intent: turning a bracket on while
    /// Burst or Interval is chosen chooses Single, and the self-timer's delay, if chosen, becomes
    /// the bracket's start delay. An interface that turns Bracket on with the session's delay
    /// sends ``bracketDriveMode``, read before, as the drive mode next.
    ///
    /// - Parameter intent: The intent just handled.
    func bracketDidChange(after intent: ManualControlIntent) {
        guard case .setBracket(.some) = intent, manual.bracket != nil else { return }
        switch drive.mode {
        case .burst, .interval:
            drive.setMode(.single)
            bracketStartDelay = nil
        case .single:
            bracketStartDelay = nil
        case .timer(let delay):
            bracketStartDelay = delay
        }
    }

    /// Chooses Single when a lens change turned the bracket off, so the drive strip never shows
    /// a self-timer the person didn't choose.
    ///
    /// - Parameter hadBracket: Whether a bracket was on before the lens changed.
    func lensDidChange(hadBracket: Bool) {
        guard hadBracket, manual.bracket == nil else { return }
        drive.setMode(.single)
    }
}
