import Foundation
import Observation

/// Starts, updates and ends the Live Activity that shows a series and its saving on the Lock
/// Screen and in the Dynamic Island (issue #64), and asks for time to finish saving when the app
/// leaves the foreground.
///
/// The app owns one for its lifetime, runs ``observe(_:)`` while the camera screen is shown, and
/// keeps ``isEnabled`` (the Settings switch, off by default), ``isInForeground`` and
/// ``isNightMode`` current. The coordinator follows the camera model; it holds no camera rules.
///
/// - **Start:** an activity can only be started while the app is in the foreground (ActivityKit,
///   `Activity.request`), so it starts when an interval series, astro run, burst or self-timer
///   starts, if the switch is on and the person allows Live Activities.
/// - **Updates:** local only, no push and no network. While the app is in the foreground the
///   activity isn't on screen, so a change of the counts alone is sent at most every
///   ``minimumUpdateInterval``; a change of phase, and the content when the app leaves the
///   foreground, are sent at once. A countdown is drawn by the system from its end time, with no
///   updates (AGENTS.md, "Battery": no timers that keep running).
/// - **End:** when the run ends, at once if the app is in the foreground, where the camera screen
///   says how it went; otherwise its final content stays on the Lock Screen for
///   ``endedActivityDuration``. Stop on the activity ends it at once (``stopSeries(_:)``).
/// - **Time to finish saving:** when the app leaves the foreground while photos are being taken or
///   saved (``CameraModel/isFinishingPhotos``), the coordinator asks iOS for time to finish, and
///   gives it back as soon as they are saved, whether or not the switch is on. If the time runs
///   out first, the activity says saving is paused until the app is opened again.
@MainActor
@Observable
public final class LiveActivityCoordinator {
    /// The shortest time between two updates that change only the counts, in seconds, while the
    /// app is in the foreground and the activity isn't on screen. An assumption to be checked on a
    /// device: rare enough to cost no noticeable battery, often enough to stay roughly current if
    /// the system shows the activity.
    public static let minimumUpdateInterval: Double = 30

    /// How long an activity that ended while the app was out of the foreground stays on the Lock
    /// Screen, in seconds: two minutes, "a short time after saving finishes" (issue #64).
    public static let endedActivityDuration: Double = 120

    /// Whether Live Activities are on: the Settings switch (``NopeSettings/showsLiveActivity``).
    /// Turning it off ends the shown activity at once.
    public var isEnabled = false

    /// Whether the app is in the foreground. The app sets it whenever its scene phase changes.
    public var isInForeground = true

    /// Whether night mode is on, so the activity is red on black too.
    public var isNightMode = false

    /// The content of the activity shown now, or `nil` when none is shown.
    @ObservationIgnored public private(set) var shown: LiveActivityContent?

    /// When the shown activity was last started or updated.
    @ObservationIgnored private var lastSent = Date.distantPast

    /// Whether the system refused to start an activity for the run that runs now, so it isn't
    /// asked again until that run ends.
    @ObservationIgnored private var wasRefused = false

    /// Whether the coordinator holds time from ``BackgroundTimeRequesting``.
    @ObservationIgnored private var holdsBackgroundTime = false

    /// Whether the time to finish saving ran out since the app last left the foreground.
    @ObservationIgnored private var backgroundTimeRanOut = false

    /// Shows the activity.
    @ObservationIgnored private let presenter: any LiveActivityPresenting

    /// Asks for time to finish saving.
    @ObservationIgnored private let backgroundTime: any BackgroundTimeRequesting

    /// Reads the current time.
    @ObservationIgnored private let now: () -> Date

    /// Creates a coordinator with no activity shown.
    ///
    /// - Parameters:
    ///   - presenter: Shows the activity.
    ///   - backgroundTime: Asks for time to finish saving.
    ///   - now: Reads the current time. Tests pass their own.
    public init(
        presenter: any LiveActivityPresenting, backgroundTime: any BackgroundTimeRequesting,
        now: @escaping () -> Date = Date.init
    ) {
        self.presenter = presenter
        self.backgroundTime = backgroundTime
        self.now = now
    }

    /// Follows the model until the calling task is cancelled: applies every change of the model
    /// or of ``isEnabled``, ``isInForeground`` and ``isNightMode`` as it happens. Nothing polls;
    /// it waits for Observation's change notifications.
    ///
    /// - Parameter model: The camera model.
    public func observe(_ model: CameraModel) async {
        let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        track(model, continuation: continuation)
        for await _ in changes {
            track(model, continuation: continuation)
        }
    }

    /// Applies the model's state once, and asks to hear of the next change.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - continuation: Told when anything read here changes.
    private func track(_ model: CameraModel, continuation: AsyncStream<Void>.Continuation) {
        withObservationTracking {
            apply(model)
        } onChange: {
            continuation.yield()
        }
    }

    /// Stops the interval series or astro run from the activity's Stop button, and ends the
    /// activity at once, with every photo already taken saved.
    ///
    /// - Parameter model: The camera model.
    public func stopSeries(_ model: CameraModel) async {
        await model.send(.manual(.stopInterval))
        await model.send(.astro(.stop))
        guard let shown else { return }
        presenter.end(model.liveActivityOutcome(after: shown), dismissal: .immediate)
        self.shown = nil
    }

    /// Brings the background time and the activity in line with the model's state.
    ///
    /// - Parameter model: The camera model.
    func apply(_ model: CameraModel) {
        applyBackgroundTime(model)
        var content = model.liveActivityContent(continuing: shown?.kind, isInForeground: isInForeground, now: now())
        content?.isNightMode = isNightMode
        if content?.phase == .saving, backgroundTimeRanOut { content?.phase = .savingPaused }
        if content == nil { wasRefused = false }
        guard let shown else {
            start(content)
            return
        }
        guard isEnabled else {
            presenter.end(shown, dismissal: .immediate)
            self.shown = nil
            return
        }
        guard let content, content.kind == shown.kind else {
            end(shown, model: model)
            start(content)
            return
        }
        update(shown, to: content)
    }

    /// Starts an activity for the content, if it starts one and Live Activities are on and
    /// allowed.
    ///
    /// - Parameter content: The content for what runs now, or `nil`.
    private func start(_ content: LiveActivityContent?) {
        guard let content, content.startsActivity, isEnabled, isInForeground, !wasRefused,
            presenter.areActivitiesEnabled
        else { return }
        guard presenter.start(content) else {
            wasRefused = true
            return
        }
        shown = content
        lastSent = now()
    }

    /// Ends the shown activity with its run's final content.
    ///
    /// - Parameters:
    ///   - shown: The content shown now.
    ///   - model: The camera model, which says how the run ended.
    private func end(_ shown: LiveActivityContent, model: CameraModel) {
        var outcome = model.liveActivityOutcome(after: shown)
        outcome.isNightMode = isNightMode
        let dismissal: LiveActivityDismissal =
            isInForeground ? .immediate : .after(now().addingTimeInterval(Self.endedActivityDuration))
        presenter.end(outcome, dismissal: dismissal)
        self.shown = nil
    }

    /// Updates the shown activity when its content changed enough to be worth it.
    ///
    /// - Parameters:
    ///   - shown: The content shown now.
    ///   - content: The new content, of the same kind.
    private func update(_ shown: LiveActivityContent, to content: LiveActivityContent) {
        let changesOnlyCounts =
            content.phase == shown.phase && content.total == shown.total && content.isNightMode == shown.isNightMode
        if changesOnlyCounts {
            guard content.taken != shown.taken || content.saved != shown.saved else { return }
            guard !isInForeground || now().timeIntervalSince(lastSent) >= Self.minimumUpdateInterval else { return }
        }
        presenter.update(content)
        self.shown = content
        lastSent = now()
    }

    /// Holds time to finish saving while the app is out of the foreground with photos still being
    /// taken or saved, and gives it back otherwise.
    ///
    /// - Parameter model: The camera model.
    private func applyBackgroundTime(_ model: CameraModel) {
        if isInForeground { backgroundTimeRanOut = false }
        let needsTime = !isInForeground && model.isFinishingPhotos && !backgroundTimeRanOut
        if needsTime, !holdsBackgroundTime {
            holdsBackgroundTime = backgroundTime.beginBackgroundTime { [weak self, weak model] in
                guard let self, let model else { return }
                self.backgroundTimeDidRunOut(model)
            }
        } else if !needsTime, holdsBackgroundTime {
            holdsBackgroundTime = false
            backgroundTime.endBackgroundTime()
        }
    }

    /// Notes that the time to finish saving ran out, and says so on the activity before the app
    /// is suspended.
    ///
    /// - Parameter model: The camera model.
    private func backgroundTimeDidRunOut(_ model: CameraModel) {
        holdsBackgroundTime = false
        backgroundTimeRanOut = true
        apply(model)
    }
}
