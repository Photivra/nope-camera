import Foundation

/// What the Live Activity shows on the Lock Screen and in the Dynamic Island while a series or
/// its saving runs (issue #64): counts and status only, never image data, location or metadata
/// (docs/PRIVACY.md, "Live Activity").
///
/// ``LiveActivityCoordinator`` makes one from the camera model and hands it to the app's
/// ``LiveActivityPresenting``, which shows it with ActivityKit. The app and its widget extension
/// use it as the activity's content state, so it is `Codable`. An interface renders
/// ``kind``, ``statusLine``, ``signingLine`` and ``progress``; it holds no rules of its own.
///
/// iOS shows an app's Live Activity only while the app isn't on screen, and the camera stops when
/// the app leaves the foreground, so what people see is mostly a paused series, frames still being
/// saved, or how the run ended.
public struct LiveActivityContent: Codable, Hashable, Sendable {
    /// What runs.
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// An interval series (issue #48).
        case interval
        /// The astro helper's frames, and the countdown before them (issue #60).
        case astro
        /// A burst (issue #46).
        case burst
        /// The self-timer and its photo (issue #39).
        case timer
        /// A focus bracket's frames (issue #90). Its start delay shows as the self-timer's.
        case focusBracket
    }

    /// How far the run has got.
    public enum Phase: String, Codable, Hashable, Sendable, CaseIterable {
        /// The countdown before the photo or the first frame runs; ``countdownEnd`` says when it
        /// ends.
        case countingDown
        /// Photos are being taken, which happens only while the app is open.
        case running
        /// The app left during an interval series or astro run, or the camera paused one: it
        /// continues when the app is open and the camera runs again.
        case paused
        /// The app left, so no more photos are taken; the ones taken are being saved.
        case saving
        /// The app left and iOS gave it no more time before every photo was saved; opening the
        /// app lets the save continue.
        case savingPaused
        /// The run ended as planned.
        case finished
        /// The run ended early: stopped, or the camera stopped, or the countdown was cancelled.
        case stopped
        /// A photo couldn't be taken or saved; the app says what went wrong.
        case failed
    }

    /// Whether the saved photos are signed (Content Credentials).
    public enum Signing: String, Codable, Hashable, Sendable, CaseIterable {
        /// Every saved photo is signed.
        case allSigned
        /// At least one saved photo isn't signed, although signing was on or couldn't be offered.
        case notAllSigned
        /// No saved photo is signed, because the person has signing turned off
        /// (``SignatureStatus/UnsignedReason/turnedOff``): the person's choice, not a problem.
        case off
    }

    /// What runs.
    public var kind: Kind

    /// How far it has got.
    public var phase: Phase

    /// The photos taken so far. For an interval series, only photos taken and saved are
    /// counted, as on the camera screen (``IntervalProgress/taken``).
    public var taken: Int

    /// The photos the run takes, or `nil` when it has no set number (a burst, the self-timer, or
    /// an interval series that stops after a time).
    public var total: Int?

    /// When an interval series that stops after a time started and when it ends, or `nil`. The
    /// system counts down to the end and fills the progress bar by time on screen, so the content
    /// isn't updated for it. The time keeps running while the series is paused
    /// (``IntervalProgress/timeSpan(date:now:)``).
    public var seriesTime: ClosedRange<Date>?

    /// The photos saved so far.
    public var saved: Int

    /// When the countdown ends, while ``phase`` is ``Phase/countingDown``; otherwise `nil`. The
    /// system counts down to it on screen, so the content isn't updated every second.
    public var countdownEnd: Date?

    /// Whether the saved photos are signed, once the run has ended with photos saved; otherwise
    /// `nil`.
    public var signing: Signing?

    /// Whether night mode is on (issue #61), so the activity is red on black too.
    public var isNightMode: Bool

    /// Creates content.
    ///
    /// - Parameters:
    ///   - kind: What runs.
    ///   - phase: How far it has got.
    ///   - taken: The photos taken so far.
    ///   - total: The photos the run takes, or `nil`.
    ///   - saved: The photos saved so far.
    ///   - countdownEnd: When the countdown ends, or `nil`.
    ///   - signing: Whether the saved photos are signed, or `nil`.
    ///   - isNightMode: Whether night mode is on.
    ///   - seriesTime: When an interval series that stops after a time started and ends, or
    ///     `nil`.
    public init(
        kind: Kind, phase: Phase, taken: Int = 0, total: Int? = nil, saved: Int = 0, countdownEnd: Date? = nil,
        signing: Signing? = nil, isNightMode: Bool = false, seriesTime: ClosedRange<Date>? = nil
    ) {
        self.kind = kind
        self.phase = phase
        self.taken = taken
        self.total = total
        self.seriesTime = seriesTime
        self.saved = saved
        self.countdownEnd = countdownEnd
        self.signing = signing
        self.isNightMode = isNightMode
    }

    /// Whether the activity offers Stop: for an interval series, astro run or focus bracket that
    /// runs or is paused, because they have photos still to take that Stop would prevent, and
    /// for a focus bracket's start delay (docs/design/device-feedback-1.0.md, section 6). Every
    /// photo already taken is saved either way.
    public var canStop: Bool {
        switch kind {
        case .interval, .astro: phase == .running || phase == .paused
        case .focusBracket: phase == .countingDown || phase == .running || phase == .paused
        case .burst, .timer: false
        }
    }

    /// Whether the run has ended, so the activity shows its final state.
    public var hasEnded: Bool {
        phase == .finished || phase == .stopped || phase == .failed
    }

    /// Whether this content can start an activity: a countdown or a run that has just begun. An
    /// activity can only be started while the app is in the foreground (ActivityKit,
    /// `Activity.request`), so it starts when the run starts.
    var startsActivity: Bool {
        phase == .countingDown || phase == .running
    }

    /// How far a run with a set number of photos has got, from 0 to 1, or `nil` for a run without
    /// one or a countdown.
    public var progress: Double? {
        guard let total, total > 0, phase != .countingDown else { return nil }
        return min(Double(taken) / Double(total), 1)
    }

    /// The one number beside the Dynamic Island: the photos taken while they are being taken (and
    /// for an interval series, always), the photos saved once saving has begun, or `nil` during a
    /// countdown (the countdown is shown instead) and after a failure (a warning symbol is shown).
    public var compactCount: Int? {
        switch phase {
        case .countingDown, .failed: nil
        case .running, .paused: taken
        case .saving, .savingPaused, .finished, .stopped: kind == .interval ? taken : saved
        }
    }

    /// Whether the activity shows the time left of an interval series that stops after a time,
    /// with a progress bar by time (``seriesTime``): while the series runs or is paused.
    public var showsTimeLeft: Bool {
        seriesTime != nil && (phase == .running || phase == .paused)
    }

    /// The main line of text: what is happening, with the counts.
    public var statusLine: LiveActivityStatusLine {
        if seriesTime != nil, let line = timedSeriesLine { return line }
        let total = total ?? taken
        switch phase {
        case .countingDown:
            return kind == .astro ? .astroStartsIn : .photoIn
        case .running:
            switch kind {
            case .interval: return .photosTaken(taken: taken, total: total)
            case .astro, .focusBracket: return .frame(number: min(taken + 1, total), total: total)
            case .burst: return .burstPhotosTaken(taken)
            case .timer: return .takingPhoto
            }
        case .paused:
            return kind == .astro || kind == .focusBracket
                ? .framesPaused(taken: taken, total: total) : .paused(taken: taken, total: total)
        case .saving:
            return kind == .timer ? .savingPhoto : .saving(saved: saved, taken: taken)
        case .savingPaused:
            return .savingPaused
        case .finished:
            return kind == .interval ? .seriesDone(taken: taken, total: total) : .photosSaved(saved)
        case .stopped:
            return stoppedLine(total: total)
        case .failed:
            return .failed
        }
    }

    /// The status line of an interval series that stops after a time, or `nil` for a phase it
    /// shares with other runs.
    private var timedSeriesLine: LiveActivityStatusLine? {
        switch phase {
        case .running: .photosTakenTimeLeft(taken)
        case .paused: .pausedTimeLeft(taken)
        case .finished: .seriesDoneAfterTime(taken)
        case .stopped: .seriesStoppedBeforeTime(taken)
        case .countingDown, .saving, .savingPaused, .failed: nil
        }
    }

    /// The status line of a run that ended early.
    ///
    /// - Parameter total: The photos the run was to take.
    /// - Returns: The line.
    private func stoppedLine(total: Int) -> LiveActivityStatusLine {
        switch kind {
        case .interval: .seriesStopped(taken: taken, total: total)
        case .timer: saved > 0 ? .photosSaved(saved) : .noPhotoTaken
        case .astro, .burst: .stoppedPhotosSaved(saved)
        case .focusBracket: .bracketStopped(saved: saved, total: total)
        }
    }

    /// The line about signatures, once the run has ended with photos saved, or `nil`. A missing
    /// signature is never hidden (AGENTS.md, "Honesty").
    public var signingLine: LiveActivitySigningLine? {
        guard hasEnded, let signing else { return nil }
        switch signing {
        case .allSigned: return .signed
        case .notAllSigned: return saved > 1 ? .notAllSigned : .notSigned
        case .off: return .signingOff
        }
    }
}

/// The main line of a Live Activity's text (``LiveActivityContent/statusLine``). Each case says
/// what an interface shows; counts are numbers of photos.
public enum LiveActivityStatusLine: Equatable, Sendable {
    /// "Photo in" followed by the system's countdown to ``LiveActivityContent/countdownEnd``.
    case photoIn
    /// "Astro starts in" followed by the system's countdown.
    case astroStartsIn
    /// "Taking the photo…": the self-timer's photo is being taken.
    case takingPhoto
    /// "12 of 120 photos taken": an interval series runs.
    case photosTaken(taken: Int, total: Int)
    /// "12 photos taken · 1:12:00 left", the time counted down by the system to the end of
    /// ``LiveActivityContent/seriesTime``: an interval series that stops after a time runs.
    case photosTakenTimeLeft(Int)
    /// "Paused: 12 photos taken · 1:12:00 left. Open nope. to continue.": an interval series that
    /// stops after a time is paused, and its time keeps running.
    case pausedTimeLeft(Int)
    /// "Done: 120 photos taken.": an interval series that stops after a time reached its time.
    case seriesDoneAfterTime(Int)
    /// "Stopped: 42 photos taken.": an interval series that stops after a time ended before it.
    case seriesStoppedBeforeTime(Int)
    /// "Frame 5 of 20": the astro helper takes this frame.
    case frame(number: Int, total: Int)
    /// "Photos taken: 12": a burst runs.
    case burstPhotosTaken(Int)
    /// "Paused: 42 of 120 photos taken. Open nope. to continue."
    case paused(taken: Int, total: Int)
    /// "Paused: 4 of 20 frames. Open nope. to continue.": an astro run.
    case framesPaused(taken: Int, total: Int)
    /// "Saving: 4 of 7 photos saved."
    case saving(saved: Int, taken: Int)
    /// "Saving the photo…"
    case savingPhoto
    /// "Saving paused. Open nope. to finish."
    case savingPaused
    /// "Done: 120 of 120 photos taken."
    case seriesDone(taken: Int, total: Int)
    /// "Stopped: 42 of 120 photos taken."
    case seriesStopped(taken: Int, total: Int)
    /// "Photos saved: 7."
    case photosSaved(Int)
    /// "Stopped. Photos saved: 5."
    case stoppedPhotosSaved(Int)
    /// "Bracket stopped: 4 of 12 photos saved", as the focus bracket's card says it: a focus
    /// bracket ended before its last frame.
    case bracketStopped(saved: Int, total: Int)
    /// "Stopped. No photo taken."
    case noPhotoTaken
    /// "A photo wasn't saved. Open nope. for details."
    case failed
}

/// The line about signatures (``LiveActivityContent/signingLine``). Honesty wording: it never
/// implies a photo is signed when it isn't.
public enum LiveActivitySigningLine: Equatable, Sendable, CaseIterable {
    /// "Signed.": every saved photo is signed.
    case signed
    /// "Not signed. Open nope. for details.": the one saved photo isn't signed.
    case notSigned
    /// "Not every photo is signed. Open nope. for details."
    case notAllSigned
    /// "Not signed: signing is off in Settings.": signing is off by the person's choice, so the
    /// line states it without pointing to a problem.
    case signingOff
}

/// How long an ended Live Activity stays on the Lock Screen.
public enum LiveActivityDismissal: Equatable, Sendable {
    /// It goes away now.
    case immediate
    /// It stays until this time, unless the person removes it first.
    case after(Date)
}

/// Shows the Live Activity. The app implements it with ActivityKit, updated from the device only:
/// no push token is ever requested and nothing is sent anywhere (AGENTS.md, "No network");
/// tests pass a fake.
///
/// One activity is shown at a time; ``LiveActivityCoordinator`` decides when it starts, changes
/// and ends.
@MainActor
public protocol LiveActivityPresenting: AnyObject {
    /// Whether the person allows Live Activities for the app, in the Settings app
    /// (ActivityKit, `ActivityAuthorizationInfo.areActivitiesEnabled`).
    var areActivitiesEnabled: Bool { get }

    /// Starts the activity with this content. Called only while the app is in the foreground.
    ///
    /// - Parameter content: What it shows.
    /// - Returns: Whether the system started it.
    func start(_ content: LiveActivityContent) -> Bool

    /// Changes what the running activity shows.
    ///
    /// - Parameter content: What it shows now.
    func update(_ content: LiveActivityContent)

    /// Ends the running activity, showing its final content until it is dismissed.
    ///
    /// - Parameters:
    ///   - content: What it shows last.
    ///   - dismissal: When it goes away.
    func end(_ content: LiveActivityContent, dismissal: LiveActivityDismissal)
}

/// Asks iOS for a little time to finish saving photos after the app leaves the foreground. The app
/// implements it with `UIApplication.beginBackgroundTask(withName:expirationHandler:)`, which is
/// a limited extension of the app's run time, not a background mode (AGENTS.md, "Battery"); tests
/// pass a fake.
@MainActor
public protocol BackgroundTimeRequesting: AnyObject {
    /// Asks for time to finish. At most one request is open at a time.
    ///
    /// - Parameter onExpiration: Runs on the main actor when the time is about to run out. The
    ///   request is then over; don't call ``endBackgroundTime()`` for it.
    /// - Returns: Whether the system gave the time.
    func beginBackgroundTime(onExpiration: @escaping @MainActor () -> Void) -> Bool

    /// Says the work is done, so the app can be suspended.
    func endBackgroundTime()
}
