import NopeCore
import SwiftUI

/// The words for the drive modes, the self-timer and bursts (issues #39 and #46). The modes' own
/// names are the drive strip's (`DriveWord`).
@MainActor
enum DriveText {
    /// A number of seconds in the system's short form, such as "3s" or "3 Sek.".
    ///
    /// - Parameter seconds: The seconds.
    static func shortSeconds(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .narrow))
    }

    /// A number of seconds in words, such as "3 seconds", for VoiceOver.
    ///
    /// - Parameter seconds: The seconds.
    static func spokenSeconds(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .wide))
    }

    /// What the shutter does now, for VoiceOver, or `nil` in single mode with nothing running.
    ///
    /// - Parameter model: The camera model.
    static func shutterValue(_ model: CameraModel) -> Text? {
        let drive = model.drive
        if model.manual.intervalProgress != nil {
            return Text("Interval series running. Press to stop.", bundle: .module, comment: "VoiceOver value of the shutter while an interval series runs: pressing the shutter stops it.")
        }
        if drive.countdown.isRunning {
            return Text("Counting down. Press to cancel.", bundle: .module, comment: "VoiceOver value of the shutter while the self-timer counts down: pressing the shutter cancels the photo.")
        }
        if drive.burstProgress != nil {
            return Text("Taking a burst. Press to stop.", bundle: .module, comment: "VoiceOver value of the shutter while a burst runs: pressing the shutter stops it.")
        }
        switch drive.mode {
        case .single: return nil
        case .timer(let delay):
            return Text("Self-timer: \(spokenSeconds(delay.seconds))", bundle: .module, comment: "VoiceOver value of the shutter when the self-timer is on. The value is a number of seconds in words, such as 3 seconds, formatted by the system.")
        case .burst:
            return burstValue(model.burstSpeed)
        case .interval:
            return Text("Interval shooting. Press to start the series.", bundle: .module, comment: "VoiceOver value of the shutter in the interval drive mode: one press starts a series of photos at a fixed interval.")
        }
    }

    /// The shutter's VoiceOver value in burst mode: "Burst, fast." or "Burst, slow."
    ///
    /// - Parameter speed: The burst speed.
    static func burstValue(_ speed: BurstSpeed) -> Text {
        switch speed {
        case .fast:
            Text("Burst, fast.", bundle: .module, comment: "VoiceOver value of the shutter in burst mode at the Fast speed: photos are taken as fast as the camera is ready while the shutter is held.")
        case .slow:
            Text("Burst, slow.", bundle: .module, comment: "VoiceOver value of the shutter in burst mode at the Slow speed: up to 2 photos a second while the shutter is held.")
        }
    }

    /// The shutter's VoiceOver hint in burst mode while nothing runs, or `nil` otherwise.
    ///
    /// - Parameter model: The camera model.
    static func shutterHint(_ model: CameraModel) -> Text? {
        guard model.drive.mode == .burst, !model.astro.isOn, !model.drive.isBusy else { return nil }
        return Text("Double tap for one photo. Double tap and hold for a burst.", bundle: .module, comment: "VoiceOver hint of the shutter in burst mode: a double tap takes one photo; a double tap and hold takes photos until the finger lifts.")
    }

    /// What to announce when a burst ends other than by the person, or `nil`.
    ///
    /// - Parameter result: How the burst ended.
    static func endMessage(_ result: BurstResult) -> String? {
        switch result.end {
        case .stopped, .failed, .countReached:
            // A burst of a chosen count is a Siri or Shortcuts request, which Siri reports.
            nil
        case .limitReached:
            String(localized: "Burst stopped at \(result.saved) photos, the most one burst takes.", bundle: .module, comment: "Announced and shown when a burst stops because it reached its maximum number of photos. The number is that count of photos, such as 50.")
        case .storageFull:
            String(localized: "Burst stopped: storage is full.", bundle: .module, comment: "Announced and shown when a burst stops because the next photo wouldn't fit in the device's free storage.")
        case .cameraStopped:
            String(localized: "Burst stopped: the camera stopped.", bundle: .module, comment: "Announced and shown when a burst stops because the camera was interrupted or switched lenses.")
        case .batteryLow:
            // Only astro runs stop for a low battery (AstroText.endMessage).
            nil
        }
    }
}

/// The large countdown number in the middle of the picture while the self-timer, or Astro's start
/// delay, runs: large enough to read from a distance (docs/design/drive.html, "Timer, counting
/// down"). VoiceOver hears each number through an announcement instead (``DriveFeedback``), so it
/// is hidden from assistive technologies. Its backing keeps it legible over a bright picture.
struct CountdownNumber: View {
    /// The drive model.
    let drive: DriveModel

    /// Creates the number.
    ///
    /// - Parameter drive: The drive model.
    init(drive: DriveModel) {
        self.drive = drive
    }

    /// The number, or nothing.
    var body: some View {
        if let remaining = drive.countdown.remainingSeconds {
            Text(remaining, format: .number)
                .nopeCountdownFont()
                .monospacedDigit()
                .foregroundStyle(NopeColor.label)
                .padding(.horizontal, NopeSpace.l)
                .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.large))
                .accessibilityHidden(true)
        }
    }
}

/// A run of Astro's frames, as its card shows it.
struct AstroRun: Equatable {
    /// The frames taken so far.
    let taken: Int

    /// The frames the run takes.
    let frameCount: Int

    /// Whether the run is paused (the camera is interrupted); it continues after the start delay.
    let isPaused: Bool

    /// Each frame's shutter, in seconds, or `nil` before the camera reports one.
    let shutter: Double?

    /// Creates a run.
    ///
    /// - Parameters:
    ///   - taken: The frames taken so far.
    ///   - frameCount: The frames the run takes.
    ///   - isPaused: Whether the run is paused.
    ///   - shutter: Each frame's shutter, in seconds, or `nil`.
    init(taken: Int, frameCount: Int, isPaused: Bool, shutter: Double?) {
        self.taken = taken
        self.frameCount = frameCount
        self.isPaused = isPaused
        self.shutter = shutter
    }

    /// The frame being taken now, counted from 1, never past the last.
    var frameNumber: Int { min(taken + 1, frameCount) }

    /// How much of the run is done, from 0 to 1.
    var fractionDone: Double { Double(taken) / Double(max(frameCount, 1)) }

    /// The exposure time of the frames still to take, in seconds, or `nil` without a shutter.
    /// Like Astro Settings' "Exposure Time in All", it leaves out the time each frame takes to
    /// save, which nothing reports (`AstroEstimate.totalExposureSeconds`).
    var exposureSecondsLeft: Double? {
        shutter.map { $0 * Double(max(frameCount - taken, 0)) }
    }
}

/// What the mode card on the picture's lower edge shows (docs/design/BUILD-SPEC.md, 3.5;
/// docs/design/BURST.md, 5.3): one case per state that has a card. Single has none, and Timer
/// has none while idle: the shutter shows the delay, and the strip names the mode.
///
/// It is plain data worked out from the camera's state (``resolve(mode:countdownRemaining:burst:endedBurst:burstSpeed:intervalProgress:intervalSettings:isAstroOn:astroRun:astroStartDelay:astroEstimate:showsControls:)``),
/// so which card shows is tested without drawing.
enum ModeCardState: Equatable {
    /// The self-timer counts down: "Photo in 3s" and Cancel Timer.
    case timerCountdown(remaining: Int)

    /// Astro's start delay counts down before the first frame: "First frame in 8s" and Stop
    /// Frames.
    case astroCountdown(remaining: Int)

    /// Burst is chosen and nothing runs: the speed, what the shutter does, and Start Burst.
    case burstIdle(BurstSpeed)

    /// A burst takes photos: "Photos taken: 12", the measured rate, and "Release to stop" while
    /// the shutter holds it, or Stop Burst.
    case burstRunning(BurstProgress)

    /// A burst took its last photo and the last ones are being saved: "Saving: 9 of 12 photos
    /// saved" and a bar. The shutter is dimmed until they are.
    case burstSaving(saved: Int, taken: Int)

    /// A burst ended: the summary ("12 photos saved", the time and the rate), or why it stopped
    /// by itself (``DriveText/endMessage(_:)``), until the next action.
    case burstEnded(BurstResult)

    /// Interval is chosen and no series runs: "Every 10 seconds, 10 photos", or "Every 10
    /// seconds, for 1 hour, 30 minutes". The whole card is the button Interval Settings.
    case intervalIdle(IntervalSettings)

    /// An interval series runs or is paused: the count, or for a series that stops after a time
    /// the count and the time left, a progress bar and Stop.
    case intervalRunning(IntervalProgress)

    /// Astro is on and ready: the frames and the estimate. The whole card is the button Astro
    /// Settings.
    case astroReady(frameCount: Int, startDelay: SelfTimerDelay, estimate: AstroEstimate?)

    /// Astro's frames run or are paused: the frame, a progress bar and Stop Frames.
    case astroRunning(AstroRun)

    /// Whether the card shows something that runs, and so stays in clean view: stopping never
    /// depends on bringing the controls back.
    var isRunning: Bool {
        switch self {
        case .timerCountdown, .astroCountdown, .burstRunning, .burstSaving, .intervalRunning, .astroRunning: true
        case .burstIdle, .burstEnded, .intervalIdle, .astroReady: false
        }
    }

    /// The card for the camera's state, or `nil` for none. A running series or countdown comes
    /// first; an idle card shows only while the controls are shown (not in clean view). In
    /// burst mode: running, saving, ended (until the next action), idle.
    ///
    /// - Parameters:
    ///   - mode: The drive mode.
    ///   - countdownRemaining: The self-timer's seconds left, or `nil` when it isn't counting.
    ///   - burst: The running burst, or `nil`.
    ///   - endedBurst: A burst whose summary or end message still shows, or `nil`.
    ///   - burstSpeed: The speed a burst on the selected lens uses, for the idle card.
    ///   - intervalProgress: The running interval series, or `nil`.
    ///   - intervalSettings: The next interval series.
    ///   - isAstroOn: Whether Astro is on.
    ///   - astroRun: Astro's running frames, or `nil`.
    ///   - astroStartDelay: Astro's start delay.
    ///   - astroEstimate: What Astro's next run will take, or `nil`.
    ///   - showsControls: Whether the controls are shown (not clean view).
    /// - Returns: The card, or `nil`.
    static func resolve(
        mode: DriveMode, countdownRemaining: Int?, burst: BurstProgress?, endedBurst: BurstResult?,
        burstSpeed: BurstSpeed = .fast, intervalProgress: IntervalProgress?, intervalSettings: IntervalSettings, isAstroOn: Bool, astroRun: AstroRun?,
        astroStartDelay: SelfTimerDelay, astroEstimate: AstroEstimate?, showsControls: Bool
    ) -> ModeCardState? {
        if let intervalProgress { return .intervalRunning(intervalProgress) }
        // After a pause, Astro runs its start delay again; the card keeps the run's progress.
        if let astroRun { return .astroRunning(astroRun) }
        if let countdownRemaining {
            return isAstroOn ? .astroCountdown(remaining: countdownRemaining) : .timerCountdown(remaining: countdownRemaining)
        }
        if let burst {
            return burst.isSaving ? .burstSaving(saved: burst.saved, taken: burst.taken) : .burstRunning(burst)
        }
        guard showsControls else { return nil }
        if isAstroOn {
            return .astroReady(frameCount: astroEstimate?.frameCount ?? 0, startDelay: astroStartDelay, estimate: astroEstimate)
        }
        switch mode {
        case .interval: return .intervalIdle(intervalSettings)
        case .burst: return endedBurst.map { .burstEnded($0) } ?? .burstIdle(burstSpeed)
        case .single, .timer: return nil
        }
    }

    /// Whether a burst's end keeps a card until the next action: a summary, or why it stopped
    /// by itself.
    ///
    /// - Parameter result: How the burst ended.
    @MainActor
    static func showsEnd(_ result: BurstResult) -> Bool {
        result.hasSummary || DriveText.endMessage(result) != nil
    }

    /// The card for the camera model's state, or `nil` (see ``resolve(mode:countdownRemaining:burst:endedBurst:burstSpeed:intervalProgress:intervalSettings:isAstroOn:astroRun:astroStartDelay:astroEstimate:showsControls:)``).
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - endedBurst: A burst whose summary or end message still shows, or `nil`.
    ///   - showsControls: Whether the controls are shown.
    /// - Returns: The card, or `nil`.
    @MainActor
    static func current(_ model: CameraModel, endedBurst: BurstResult?, showsControls: Bool) -> ModeCardState? {
        let astro = model.astro
        let estimate = model.astroEstimate
        let run = astro.progress.map {
            AstroRun(taken: $0.taken, frameCount: astro.frameCount, isPaused: astro.isPaused, shutter: estimate?.shutter)
        }
        let ready = resolve(
            mode: model.drive.mode, countdownRemaining: model.drive.countdown.remainingSeconds,
            burst: model.drive.burstProgress, endedBurst: endedBurst, burstSpeed: model.burstSpeed,
            intervalProgress: model.manual.intervalProgress,
            intervalSettings: model.manual.interval, isAstroOn: astro.isOn, astroRun: run,
            astroStartDelay: astro.startDelay, astroEstimate: estimate, showsControls: showsControls)
        // The frame count is Astro's own, whether or not the camera can estimate the run yet.
        if case .astroReady(_, let delay, let estimate) = ready {
            return .astroReady(frameCount: astro.frameCount, startDelay: delay, estimate: estimate)
        }
        return ready
    }
}

/// When an interval series' next photo is due, for the running card's "Next photo in 6s".
///
/// `NopeCore` doesn't publish the time of the next photo, so the card counts from the moment the
/// count of photos taken last changed, by the series' interval: the series waits that long after
/// each photo is saved (`ManualControlsModel`). The interval is the one set now, which is the
/// series' own unless it was changed in Interval Settings while the series runs (the change
/// applies to the next series). Until the card sees a photo counted, and while the series is
/// paused, it shows no time rather than a guessed one.
struct NextPhotoTiming: Equatable {
    /// When the last photo was counted.
    let lastPhoto: Date

    /// The series' interval, in seconds.
    let interval: Double

    /// Creates the timing.
    ///
    /// - Parameters:
    ///   - lastPhoto: When the last photo was counted.
    ///   - interval: The series' interval, in seconds.
    init(lastPhoto: Date, interval: Double) {
        self.lastPhoto = lastPhoto
        self.interval = interval
    }

    /// The whole seconds until the next photo, rounded up, or `nil` once it is due (it is being
    /// taken or waits for the camera).
    ///
    /// - Parameter now: The current time.
    /// - Returns: The seconds left, at least 1, or `nil`.
    func secondsLeft(at now: Date) -> Int? {
        let left = lastPhoto.addingTimeInterval(interval).timeIntervalSince(now)
        guard left > 0 else { return nil }
        return Int(left.rounded(.up))
    }
}

/// The mode card's words (docs/design/BUILD-SPEC.md, section 4). Keys the string catalog doesn't
/// have yet carry their English as the default value.
@MainActor
enum ModeCardText {
    /// A duration in the system's narrow form with up to two units, such as "13s" or "5m 20s".
    ///
    /// - Parameter seconds: The duration, in seconds.
    static func shortDuration(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2, fractionalPart: .hide(rounded: .up)))
    }

    /// A duration in words, such as "10 seconds", for the interval card.
    ///
    /// - Parameter seconds: The duration, in seconds.
    static func spokenDuration(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2, fractionalPart: .hide(rounded: .up)))
    }

    /// "Every 10 seconds, 10 photos", or for a series that stops after a time, "Every 10
    /// seconds, for 1 hour, 30 minutes".
    ///
    /// - Parameter settings: The series.
    static func intervalSummary(_ settings: IntervalSettings) -> String {
        switch settings.stopAfter {
        case .numberOfPhotos:
            String(
                localized: "Every \(spokenDuration(settings.interval)), \(settings.count) photos", bundle: .module,
                comment: "Interval card on the camera, before a series starts: the time between photos, then how many photos the series takes. The first placeholder is a duration formatted by the system, such as \"10 seconds\"; the number is at least 2.")
        case .time:
            String(
                localized: "Every \(spokenDuration(settings.interval)), for \(spokenDuration(settings.duration))", bundle: .module,
                comment: "Interval card on the camera, before a series that stops after a time starts: the time between photos, then how long the series runs. Both placeholders are durations formatted by the system, such as \"10 seconds\" and \"1 hour, 30 minutes\".")
        }
    }

    /// The idle card's second line: why the shutter can't start the series, or `nil`.
    ///
    /// - Parameter settings: The series.
    static func intervalIdleDetail(_ settings: IntervalSettings) -> String? {
        settings.isIntervalShorterThanTime ? nil : intervalNotShorterThanTimeString
    }

    /// "Choose an interval shorter than the time.": the interval isn't shorter than the series'
    /// time (`IntervalBlocker.intervalNotShorterThanTime`).
    static var intervalNotShorterThanTimeString: String {
        String(
            localized: "Choose an interval shorter than the time.", bundle: .module,
            comment: "Shown on the interval card and under the disabled Start button when the series stops after a time that is no longer than the time between photos, so it would take only one photo.")
    }

    /// ``intervalNotShorterThanTimeString`` as text.
    static var intervalNotShorterThanTime: Text {
        Text(verbatim: intervalNotShorterThanTimeString)
    }

    /// The time left of a series that stops after a time, in the system's abbreviated form with
    /// hours and minutes, the minutes rounded up: "1 hr, 12 min", or in words for VoiceOver.
    ///
    /// - Parameters:
    ///   - seconds: The time left, in seconds.
    ///   - width: How the units are written: abbreviated on screen, wide for VoiceOver.
    static func timeLeftDuration(_ seconds: Double, width: Duration.UnitsFormatStyle.UnitWidth = .abbreviated) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes], width: width, maximumUnitCount: 2, fractionalPart: .hide(rounded: .up)))
    }

    /// "12 photos taken · 1 hr, 12 min left", or "Paused: 12 photos taken · 1 hr, 12 min left",
    /// for a series that stops after a time. VoiceOver reads the units in full.
    ///
    /// - Parameters:
    ///   - progress: The series' progress.
    ///   - now: The current time.
    static func intervalTimeProgress(_ progress: IntervalProgress, at now: Date) -> Text {
        Text(verbatim: intervalTimeProgressString(progress, at: now))
            .accessibilityLabel(Text(verbatim: intervalTimeProgressString(progress, at: now, width: .wide)))
    }

    /// The words of ``intervalTimeProgress(_:at:)``.
    ///
    /// - Parameters:
    ///   - progress: The series' progress.
    ///   - now: The current time.
    ///   - width: How the units of the time left are written.
    static func intervalTimeProgressString(
        _ progress: IntervalProgress, at now: Date, width: Duration.UnitsFormatStyle.UnitWidth = .abbreviated
    ) -> String {
        let left = timeLeftDuration(progress.secondsLeft(at: now) ?? 0, width: width)
        if progress.isPaused {
            return String(
                localized: "Paused: \(progress.taken) photos taken · \(left) left", bundle: .module,
                comment: "Interval shooting that stops after a time, paused because the camera is paused (for example by a call) or nope. is in the background: it continues when the camera is back, and its time keeps running meanwhile. The number is a count of photos; the placeholder is the time left, such as \"1 hr, 12 min\", formatted by the system. Keep \"nope.\" unchanged.")
        }
        return String(
            localized: "\(progress.taken) photos taken · \(left) left", bundle: .module,
            comment: "Interval shooting progress for a series that stops after a time: how many photos are taken so far, and the time left. The number is a count of photos; the placeholder is the time left, such as \"1 hr, 12 min\", formatted by the system.")
    }

    /// "Ends at 9:41 PM", or with the day when the series ends on another day: "Ends at Tue 9:41
    /// PM".
    ///
    /// - Parameters:
    ///   - end: When the series ends.
    ///   - now: The current time.
    static func intervalEnds(at end: Date, now: Date) -> String {
        let format: Date.FormatStyle =
            Calendar.current.isDate(end, inSameDayAs: now)
            ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute()
        return String(
            localized: "Ends at \(end.formatted(format))", bundle: .module,
            comment: "Interval card on the camera while a series that stops after a time is paused: the time on the clock when it ends, such as 9:41 PM, with the day of the week when it is not today. Formatted by the system.")
    }

    /// "Interval Settings".
    static var intervalSettings: Text {
        Text("Interval Settings", bundle: .module, comment: "Action of the interval pill on the camera: opens the time between photos and the number of photos.")
    }

    /// "3 of 10 photos taken", or "Paused: 3 of 10 photos taken".
    ///
    /// - Parameter progress: The series' progress.
    static func intervalProgress(_ progress: IntervalProgress) -> Text {
        let total = progress.total ?? progress.taken
        return if progress.isPaused {
            Text("Paused: \(progress.taken) of \(total) photos taken", bundle: .module, comment: "Interval shooting progress while the series is paused because the camera is paused (for example by a call) or nope. is in the background: it continues when the camera is back. Both numbers are counts of photos; the second is at least 2. Keep \"nope.\" unchanged.")
        } else {
            Text("\(progress.taken) of \(total) photos taken", bundle: .module, comment: "Interval shooting progress: how many photos of the series are taken so far. Both numbers are counts of photos; the second is at least 2.")
        }
    }

    /// "Next photo in 6s" (BUILD-SPEC.md, figure drive-interval-running).
    ///
    /// - Parameter seconds: The seconds left.
    static func nextPhoto(in seconds: Int) -> Text {
        Text(
            String(
                localized: "Next photo in %@", defaultValue: "Next photo in \(DriveText.shortSeconds(seconds))",
                bundle: .module,
                comment: "Interval card on the camera while a series runs: the next photo is taken after this many seconds. The value is a short number of seconds, such as 6s, formatted by the system."))
    }

    /// "Astro frames: 20".
    ///
    /// - Parameter frameCount: The frames the run takes.
    static func astroFrames(_ frameCount: Int) -> String {
        String(localized: "Astro frames: \(frameCount)", bundle: .module, comment: "Shown on the camera while the night sky helper is on: how many frames the shutter will take.")
    }

    /// "After 10 seconds · 20 s in all · at most 486 MB", or `nil` before the camera reports a
    /// shutter for the estimate.
    ///
    /// - Parameters:
    ///   - startDelay: Astro's start delay.
    ///   - estimate: What the run will take.
    static func astroSummary(startDelay: SelfTimerDelay, estimate: AstroEstimate?) -> String? {
        guard let estimate, let total = estimate.totalExposureSeconds else { return nil }
        let delay = DriveText.spokenSeconds(startDelay.seconds)
        let inAll = Duration.seconds(total).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2, fractionalPart: .hide(rounded: .up)))
        let storage = estimate.bytes.formatted(.byteCount(style: .file))
        return String(
            localized: "After \(delay) · \(inAll) in all · at most \(storage)", bundle: .module,
            comment: "Astro card on the camera, before the frames start: the start delay (a duration such as \"10 seconds\"), the total time of all frames (such as \"20 s\"), and the most storage they can use (such as \"486 MB\"). All three values are formatted by the system.")
    }

    /// "First frame in 8s" (figure drive-astro-countdown).
    ///
    /// - Parameter seconds: The seconds left.
    static func firstFrame(in seconds: Int) -> Text {
        Text(
            String(
                localized: "First frame in %@", defaultValue: "First frame in \(DriveText.shortSeconds(seconds))",
                bundle: .module,
                comment: "Astro card on the camera while the start delay counts down: the first frame is taken after this many seconds. The value is a short number of seconds, such as 8s, formatted by the system."))
    }

    /// "Frame 7 of 20", or "Paused: 7 of 20 frames".
    ///
    /// - Parameter run: The run.
    static func astroProgress(_ run: AstroRun) -> Text {
        if run.isPaused {
            Text("Paused: \(run.taken) of \(run.frameCount) frames", bundle: .module, comment: "Shown on the camera while the night sky helper's frames are paused because the camera is paused (for example by a call): they continue, after the start delay, when the camera is back. Both numbers are counts of frames.")
        } else {
            Text("Frame \(run.frameNumber) of \(run.frameCount)", bundle: .module, comment: "Progress of the night sky helper on the camera: which frame is being taken, of how many. Both numbers are counts of frames.")
        }
    }

    /// "13 s left": the exposure time of the frames still to take (figure drive-astro-running).
    ///
    /// - Parameter seconds: The exposure time left, in seconds.
    static func exposureLeft(_ seconds: Double) -> Text {
        Text(
            String(
                localized: "%@ left", defaultValue: "\(shortDuration(seconds)) left", bundle: .module,
                comment: "Astro card on the camera while the frames run: the exposure time of the frames still to take, such as 13s or 5m 20s, formatted by the system. Saving each frame adds time, so this is the least time left."))
    }

    /// "Photo in 3s".
    ///
    /// - Parameter seconds: The seconds left.
    static func photoIn(_ seconds: Int) -> Text {
        Text("Photo in \(DriveText.shortSeconds(seconds))", bundle: .module, comment: "Self-timer progress on the camera: the photo is taken after this many seconds. The value is a short number of seconds, such as 3s, formatted by the system.")
    }

    /// "Photos taken: 12".
    ///
    /// - Parameter taken: The photos taken so far.
    static func burstTaken(_ taken: Int) -> Text {
        Text("Photos taken: \(taken)", bundle: .module, comment: "Burst progress on the camera: how many photos of the running burst are taken so far.")
    }

    /// A burst's measured rate, "2.6 a second", with one decimal place.
    ///
    /// - Parameter rate: Photos a second.
    static func burstRate(_ rate: Double) -> String {
        let number = rate.formatted(.number.precision(.fractionLength(1)))
        return String(
            localized: "%@ a second", defaultValue: "\(number) a second", bundle: .module,
            comment: "Burst card on the camera: the rate measured from the photos of this burst, in photos a second, such as 2.6. The value is a number with one decimal place, formatted by the system. It is a measurement, not a promise.")
    }

    /// A burst's time from its first photo to its last, "4.2 seconds".
    ///
    /// - Parameter duration: The time.
    static func burstDuration(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 2, fractionalPart: .show(length: 1)))
    }

    /// Two parts of a card's detail line, "4.2 seconds · 2.6 a second".
    ///
    /// - Parameters:
    ///   - first: The first part.
    ///   - second: The second part.
    static func joined(_ first: String, _ second: String) -> String {
        String(
            localized: "%@ · %@", defaultValue: "\(first) · \(second)", bundle: .module,
            comment: "Burst card on the camera: two details joined, such as a duration (\"4.2 seconds\") and a measured rate (\"2.6 a second\"), or a rate and \"Release to stop\".")
    }

    /// The idle card's title: "Fast burst", or "Slow burst: up to 2 a second".
    ///
    /// - Parameter speed: The burst speed.
    static func burstIdleTitle(_ speed: BurstSpeed) -> Text {
        switch speed {
        case .fast:
            Text("Fast burst", bundle: .module, comment: "Burst card on the camera, before a burst: the speed in use. Photos are taken as fast as the camera is ready.")
        case .slow:
            Text("Slow burst: up to \(speed.maximumPhotosPerSecond ?? 2) a second", bundle: .module, comment: "Burst card on the camera, before a burst: the speed in use. The number is the most photos a second, 2; it can be fewer.")
        }
    }

    /// "Hold the shutter. A tap takes one photo."
    static var burstIdleDetail: Text {
        Text("Hold the shutter. A tap takes one photo.", bundle: .module, comment: "Burst card on the camera, before a burst: what the shutter does in burst mode.")
    }

    /// "Start Burst".
    static var startBurst: Text {
        Text("Start Burst", bundle: .module, comment: "Button on the burst card, VoiceOver action on the shutter and Voice Control name: starts a burst that runs without holding the shutter.")
    }

    /// "Release to stop".
    static var releaseToStop: String {
        String(localized: "Release to stop", bundle: .module, comment: "Burst card on the camera while the shutter is held: letting go of it ends the burst.")
    }

    /// The running burst's detail: the rate and "Release to stop" while held, or the rate alone,
    /// or `nil` before a rate and without a hold.
    ///
    /// - Parameter progress: The burst's progress.
    static func burstRunningDetail(_ progress: BurstProgress) -> String? {
        let rate = progress.rate.map(burstRate)
        guard progress.start == .held else { return rate }
        return rate.map { joined($0, releaseToStop) } ?? releaseToStop
    }

    /// "Saving: 9 of 12 photos saved".
    ///
    /// - Parameters:
    ///   - saved: The photos saved so far.
    ///   - taken: The photos the burst took.
    static func burstSaving(saved: Int, taken: Int) -> Text {
        Text("Saving: \(saved) of \(taken) photos saved", bundle: .module, comment: "Burst card on the camera after the shutter is let go: the photos still waiting are being saved. Both numbers are counts of photos. The Live Activity has the same sentence.")
    }

    /// "12 photos saved".
    ///
    /// - Parameter saved: The photos saved, at least 2.
    static func photosSaved(_ saved: Int) -> String {
        String(localized: "\(saved) photos saved", bundle: .module, comment: "Burst card on the camera after a burst: how many photos it saved, at least 2.")
    }

    /// The ended card's detail: the time and the rate after a summary or the limit, the photos
    /// saved after the other stops, or `nil`.
    ///
    /// - Parameter result: How the burst ended.
    static func burstEndedDetail(_ result: BurstResult) -> String? {
        switch result.end {
        case .stopped, .limitReached:
            guard result.taken >= 2 else { return nil }
            let duration = burstDuration(result.duration)
            return result.rate.map { joined(duration, burstRate($0)) } ?? duration
        case .storageFull, .cameraStopped:
            return result.saved > 0 ? photosSaved(result.saved) : nil
        case .countReached, .batteryLow, .failed:
            return nil
        }
    }

    /// "Cancel Timer".
    static var cancelTimer: Text {
        Text("Cancel Timer", bundle: .module, comment: "Button that stops the self-timer without taking a photo.")
    }

    /// "Stop Burst".
    static var stopBurst: Text {
        Text("Stop Burst", bundle: .module, comment: "Button that stops a running burst. Every photo already taken is saved.")
    }

    /// "Stop", for an interval series.
    static var stopInterval: Text {
        Text("Stop", bundle: .module, comment: "Button that stops interval shooting.")
    }

    /// "Stop Frames".
    static var stopFrames: Text {
        Text("Stop Frames", bundle: .module, comment: "Button that stops the night sky helper's frames. Every frame already taken is saved.")
    }
}

/// The selected drive mode's card on the picture's lower edge (docs/design/BUILD-SPEC.md, 3.5;
/// docs/design/drive.html): idle, it names what the shutter will do; running, it shows progress
/// and a button that stops it. One card at a time, from ``ModeCardState``.
///
/// - Interval and Astro, idle: the whole card is one button that opens their settings.
/// - Running: the count, a progress bar where the end is known, and Stop. It stays in clean view
///   until the run ends, so stopping never depends on a gesture; the shutter stops it too.
/// - A burst that stopped by itself says why until the next action: another photo, a new mode,
///   lens or Astro.
struct ModeCards: View {
    /// The camera model.
    let model: CameraModel

    /// Whether the controls are shown (not clean view).
    let showsControls: Bool

    /// Opens Interval Settings.
    let openIntervalSettings: () -> Void

    /// Opens Astro Settings.
    let openAstroSettings: () -> Void

    /// A burst whose summary or end message the card shows until the next action.
    @State private var endedBurst: BurstResult?

    /// When the running series' last photo was counted, for "Next photo in".
    @State private var nextPhoto: NextPhotoTiming?

    /// Creates the cards.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - showsControls: Whether the controls are shown.
    ///   - openIntervalSettings: Opens Interval Settings.
    ///   - openAstroSettings: Opens Astro Settings.
    init(model: CameraModel, showsControls: Bool, openIntervalSettings: @escaping () -> Void, openAstroSettings: @escaping () -> Void) {
        self.model = model
        self.showsControls = showsControls
        self.openIntervalSettings = openIntervalSettings
        self.openAstroSettings = openAstroSettings
    }

    /// The card for now.
    private var state: ModeCardState? {
        ModeCardState.current(model, endedBurst: endedBurst, showsControls: showsControls)
    }

    /// The card, or nothing.
    var body: some View {
        // A stack, not a group: a group's modifiers go to each card, so its change handlers
        // would start again with each new card and miss the change that brought it.
        VStack(spacing: 0) {
            if let state { card(for: state) }
        }
        .onChange(of: model.drive.lastBurst) { _, result in
            endedBurst = result.flatMap { ModeCardState.showsEnd($0) ? $0 : nil }
        }
        // The next action clears a burst's end message.
        .onChange(of: model.drive.mode) { endedBurst = nil }
        .onChange(of: model.selectedLensID) { endedBurst = nil }
        .onChange(of: model.astro.isOn) { endedBurst = nil }
        .onChange(of: model.captureStatus == .capturing) { _, isCapturing in
            if isCapturing, model.drive.burstProgress == nil { endedBurst = nil }
        }
        .onChange(of: model.manual.intervalProgress?.taken) { _, taken in
            guard let taken, taken > 0 else {
                nextPhoto = nil
                return
            }
            nextPhoto = NextPhotoTiming(lastPhoto: .now, interval: model.manual.interval.interval)
        }
    }

    /// One state's card.
    ///
    /// - Parameter state: The state.
    @ViewBuilder private func card(for state: ModeCardState) -> some View {
        switch state {
        case .timerCountdown(let remaining):
            ModeCard(title: ModeCardText.photoIn(remaining)) {
                stopButton(ModeCardText.cancelTimer, isDestructive: false) { send(.drive(.cancelTimer)) }
            }
        case .astroCountdown(let remaining):
            ModeCard(title: ModeCardText.firstFrame(in: remaining)) {
                stopButton(ModeCardText.stopFrames) { send(.drive(.cancelTimer)) }
            }
        case .burstIdle(let speed):
            ModeCard(title: ModeCardText.burstIdleTitle(speed), detail: ModeCardText.burstIdleDetail) {
                stopButton(ModeCardText.startBurst, isDestructive: false) { send(.drive(.startBurst)) }
            }
        case .burstRunning(let progress):
            // One element for VoiceOver, updated politely: the count, then the rate.
            ModeCard(
                title: ModeCardText.burstTaken(progress.taken),
                detail: ModeCardText.burstRunningDetail(progress).map { Text(verbatim: $0) }
            ) {
                // A held burst ends when the shutter comes up; the others need a button.
                if progress.start != .held {
                    stopButton(ModeCardText.stopBurst) { send(.drive(.stopBurst)) }
                }
            }
        case .burstSaving(let saved, let taken):
            ModeCard(
                title: ModeCardText.burstSaving(saved: saved, taken: taken), detail: Text?.none,
                fractionDone: Double(saved) / Double(max(taken, 1))
            ) { EmptyView() }
        case .burstEnded(let result):
            let title = DriveText.endMessage(result) ?? ModeCardText.photosSaved(result.saved)
            // Start Burst stays on the card, so a burst never needs a hold, even before the next
            // action clears the summary (docs/design/BURST.md, 4.2).
            ModeCard(title: Text(verbatim: title), detail: ModeCardText.burstEndedDetail(result).map { Text(verbatim: $0) }) {
                stopButton(ModeCardText.startBurst, isDestructive: false) { send(.drive(.startBurst)) }
            }
        case .intervalIdle(let settings):
            SettingsCard(
                title: ModeCardText.intervalSummary(settings), detail: ModeCardText.intervalIdleDetail(settings),
                name: ModeCardText.intervalSettings, action: openIntervalSettings)
        case .intervalRunning(let progress) where progress.timeSpan != nil:
            IntervalTimeCard(progress: progress, nextPhoto: nextPhoto) {
                stopButton(ModeCardText.stopInterval) { send(.manual(.stopInterval)) }
            }
        case .intervalRunning(let progress):
            ModeCard(
                title: ModeCardText.intervalProgress(progress),
                detail: progress.isPaused ? nil : nextPhoto.map { NextPhotoDetail(timing: $0) },
                fractionDone: progress.fractionDone(at: .now)
            ) {
                stopButton(ModeCardText.stopInterval) { send(.manual(.stopInterval)) }
            }
        case .astroReady(let frameCount, let startDelay, let estimate):
            SettingsCard(
                title: ModeCardText.astroFrames(frameCount),
                detail: ModeCardText.astroSummary(startDelay: startDelay, estimate: estimate), name: AstroText.settings,
                action: openAstroSettings)
        case .astroRunning(let run):
            ModeCard(
                title: ModeCardText.astroProgress(run),
                detail: run.isPaused ? nil : run.exposureSecondsLeft.map { ModeCardText.exposureLeft($0) },
                fractionDone: run.fractionDone
            ) {
                stopButton(ModeCardText.stopFrames) { send(.astro(.stop)) }
            }
        }
    }

    /// A small capsule that stops what runs: red for Stop, plain for Cancel Timer.
    ///
    /// - Parameters:
    ///   - title: The button's name.
    ///   - isDestructive: Whether it stops a run (red) rather than cancelling a timer.
    ///   - action: Stops it.
    private func stopButton(_ title: Text, isDestructive: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(NopeCapsuleStyle(role: isDestructive ? .destructive : nil, isCompact: true, idleFill: .tile))
    }

    /// Sends an intent to the camera.
    ///
    /// - Parameter intent: The intent.
    private func send(_ intent: CameraIntent) {
        let model = model
        Task { await model.send(intent) }
    }
}

/// The running card of an interval series that stops after a time: the photos taken and the time
/// left, the next photo's time (or, paused, when the series ends), a progress bar by time, and
/// Stop. The time keeps running while the series is paused, so the card counts it down then too.
struct IntervalTimeCard<Accessory: View>: View {
    /// How often the time left and the bar are redrawn, in seconds: the time is shown in whole
    /// minutes, counted from the series' start.
    static var refreshSeconds: Double { 60 }

    /// The series' progress.
    let progress: IntervalProgress

    /// When the next photo is due, or `nil` before a photo is counted.
    let nextPhoto: NextPhotoTiming?

    /// The Stop capsule.
    let accessory: Accessory

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - progress: The series' progress; its `IntervalProgress.timeSpan` is set.
    ///   - nextPhoto: When the next photo is due, or `nil`.
    ///   - accessory: The Stop capsule.
    init(progress: IntervalProgress, nextPhoto: NextPhotoTiming?, @ViewBuilder accessory: () -> Accessory) {
        self.progress = progress
        self.nextPhoto = nextPhoto
        self.accessory = accessory()
    }

    /// The card, redrawn each minute of the series.
    var body: some View {
        let start = progress.timeSpan?.lowerBound ?? .now
        TimelineView(.periodic(from: start, by: Self.refreshSeconds)) { context in
            ModeCard(
                title: ModeCardText.intervalTimeProgress(progress, at: context.date),
                detail: IntervalTimeDetail(progress: progress, nextPhoto: nextPhoto, now: context.date),
                fractionDone: progress.fractionDone(at: context.date)
            ) {
                accessory
            }
        }
    }
}

/// The second line of ``IntervalTimeCard``: "Next photo in 6s" while it runs, "Ends at 9:41 PM"
/// while it is paused.
struct IntervalTimeDetail: View {
    /// The series' progress.
    let progress: IntervalProgress

    /// When the next photo is due, or `nil`.
    let nextPhoto: NextPhotoTiming?

    /// The current time.
    let now: Date

    /// Creates the line.
    ///
    /// - Parameters:
    ///   - progress: The series' progress.
    ///   - nextPhoto: When the next photo is due, or `nil`.
    ///   - now: The current time.
    init(progress: IntervalProgress, nextPhoto: NextPhotoTiming?, now: Date) {
        self.progress = progress
        self.nextPhoto = nextPhoto
        self.now = now
    }

    /// The line, or nothing.
    var body: some View {
        if progress.isPaused, let end = progress.timeSpan?.upperBound {
            Text(verbatim: ModeCardText.intervalEnds(at: end, now: now))
        } else if !progress.isPaused, let nextPhoto {
            NextPhotoDetail(timing: nextPhoto)
        }
    }
}

/// "Next photo in 6s", counting down each second until the photo is due.
struct NextPhotoDetail: View {
    /// When the next photo is due.
    let timing: NextPhotoTiming

    /// Creates the detail.
    ///
    /// - Parameter timing: When the next photo is due.
    init(timing: NextPhotoTiming) {
        self.timing = timing
    }

    /// The seconds left, or nothing once the photo is due.
    var body: some View {
        // Redrawn once a second, and only while a series runs and this card is on screen.
        TimelineView(.periodic(from: timing.lastPhoto, by: 1)) { context in
            if let seconds = timing.secondsLeft(at: context.date) {
                ModeCardText.nextPhoto(in: seconds)
            }
        }
    }
}

/// One mode card: the title and an optional detail line, an accessory (usually a Stop capsule)
/// trailing, and a progress bar under them when the end is known. `NopeRadius.large`, on
/// `NopeMaterial.backing`, outlined in night mode and with Increase Contrast.
struct ModeCard<Detail: View, Accessory: View>: View {
    /// What the mode does or how far it is.
    let title: Text

    /// A second, smaller line, or `nil`.
    let detail: Detail?

    /// How much is done, from 0 to 1, or `nil` for no progress bar.
    let fractionDone: Double?

    /// The trailing control.
    let accessory: Accessory

    /// Creates a card.
    ///
    /// - Parameters:
    ///   - title: What the mode does or how far it is.
    ///   - detail: A second, smaller line, or `nil`.
    ///   - fractionDone: How much is done, from 0 to 1, or `nil` for no progress bar.
    ///   - accessory: The trailing control.
    init(title: Text, detail: Detail?, fractionDone: Double? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.fractionDone = fractionDone
        self.accessory = accessory()
    }

    /// The card.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xs) {
            HStack(spacing: NopeSpace.s) {
                ModeCardLines(title: title, detail: detail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                accessory
            }
            if let fractionDone {
                ProgressView(value: min(max(fractionDone, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(NopeColor.label)
                    // The title says the same in words.
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, NopeSpace.m)
        .padding(.trailing, NopeSpace.xs)
        .padding(.vertical, NopeSpace.xs)
        .frame(minHeight: NopeSize.capsule + 2 * NopeSpace.xs)
        .modifier(ModeCardBackground())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ModeCard")
    }
}

extension ModeCard where Detail == Never {
    /// Creates a card with one line.
    ///
    /// - Parameters:
    ///   - title: What the mode does or how far it is.
    ///   - accessory: The trailing control.
    init(title: Text, @ViewBuilder accessory: () -> Accessory) {
        self.init(title: title, detail: nil, accessory: accessory)
    }
}

/// A card's title over its detail, read by VoiceOver as one text.
struct ModeCardLines<Detail: View>: View {
    /// The title.
    let title: Text

    /// The detail, or `nil`.
    let detail: Detail?

    /// Creates the lines.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - detail: The detail, or `nil`.
    init(title: Text, detail: Detail?) {
        self.title = title
        self.detail = detail
    }

    /// The lines.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xxs / 2) {
            title
                .font(NopeFont.status.monospacedDigit())
                .foregroundStyle(NopeColor.label)
            if let detail {
                detail
                    .font(NopeFont.pill.monospacedDigit())
                    .foregroundStyle(CameraColor(NopeColor.labelSecondary))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }
}

/// An idle card that is one button: Interval Settings or Astro Settings. It shows what the
/// shutter will do and a chevron; VoiceOver reads the button's name, then the card's text as its
/// value.
struct SettingsCard: View {
    /// What the shutter will do.
    let title: String

    /// A second line, or `nil`.
    let detail: String?

    /// The button's name: "Interval Settings" or "Astro Settings".
    let name: Text

    /// Opens the settings.
    let action: () -> Void

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - title: What the shutter will do.
    ///   - detail: A second line, or `nil`.
    ///   - name: The button's name.
    ///   - action: Opens the settings.
    init(title: String, detail: String?, name: Text, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.name = name
        self.action = action
    }

    /// The card.
    var body: some View {
        Button(action: action) {
            HStack(spacing: NopeSpace.s) {
                ModeCardLines(title: Text(verbatim: title), detail: detail.map { Text(verbatim: $0) })
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(NopeFont.status)
                    .foregroundStyle(CameraColor(NopeColor.labelSecondary))
                    .frame(minWidth: NopeSize.minTarget, minHeight: NopeSize.minTarget)
            }
            .padding(.leading, NopeSpace.m)
            .padding(.trailing, NopeSpace.xs)
            .padding(.vertical, NopeSpace.xxs)
            .modifier(ModeCardBackground())
            .contentShape(.rect(cornerRadius: NopeRadius.large))
        }
        .buttonStyle(ModeCardButtonStyle())
        .accessibilityLabel(name)
        // The two lines, joined as the language joins a short list ("a, b" in English).
        .accessibilityValue(Text(verbatim: ([title] + (detail.map { [$0] } ?? [])).formatted(.list(type: .and, width: .narrow))))
        .accessibilityInputLabels([name, Text(verbatim: title)])
        .accessibilityIdentifier("ModeCard")
    }
}

/// The press and disabled states of a whole-card button (``NopePressEffect``).
struct ModeCardButtonStyle: ButtonStyle {
    /// Creates the style. It holds no state.
    init() {}

    /// The pressed card.
    ///
    /// - Parameter configuration: The card and its press state.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .hoverEffect(.highlight)
            .modifier(NopePressEffect(isPressed: configuration.isPressed))
    }
}

/// A mode card's background: the backing in a `NopeRadius.large` rectangle, with an outline in
/// night mode (the night outline, as the design draws it) and with Increase Contrast.
struct ModeCardBackground: ViewModifier {
    /// Whether night mode is on.
    @Environment(\.isNightMode) private var isNightMode

    /// Whether Increase Contrast is on.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the background. It holds no state of its own.
    init() {}

    /// The outline's color, or `nil` for none.
    private var outline: Color? {
        if isNightMode { return NopeColor.nightOutlineUnderMultiply }
        return contrast == .increased ? NopeColor.labelSecondary : nil
    }

    /// The content on its background.
    ///
    /// - Parameter content: The card's content.
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: NopeRadius.large)
        content
            .nopeBackground(.backing, in: shape)
            .overlay {
                if let outline {
                    shape.strokeBorder(outline, lineWidth: NopeSize.outline)
                }
            }
    }
}

/// Feedback for the self-timer and bursts without looking at the screen: a haptic tick and a
/// spoken number each second of the countdown, and spoken start and end of a burst (AGENTS.md,
/// "Taking photos without seeing the screen"). Saved photos are announced by the camera's
/// usual save feedback.
struct DriveFeedback: ViewModifier {
    /// The drive model.
    let drive: DriveModel

    /// Creates the feedback.
    ///
    /// - Parameter drive: The drive model.
    init(drive: DriveModel) {
        self.drive = drive
    }

    /// The content with the feedback attached.
    ///
    /// - Parameter content: The camera.
    func body(content: Content) -> some View {
        content
            .sensoryFeedback(NopeHaptic.countdownSecond, trigger: drive.countdown.remainingSeconds) { _, new in new != nil }
            .onChange(of: drive.countdown.remainingSeconds) { _, remaining in
                if let remaining { Self.announce(remaining.formatted()) }
            }
            // One light tap for each photo after the first; the shutter's own haptic marks the
            // first (docs/design/BURST.md, 4.3).
            .sensoryFeedback(NopeHaptic.burstFrame, trigger: drive.burstProgress?.taken) { _, taken in (taken ?? 0) > 1 }
            // Only a burst begun with Start Burst is announced: a held one is marked by the
            // shutter sound and the taps, which speech would lag behind.
            .onChange(of: drive.burstProgress?.start) { _, start in
                if start == .started {
                    Self.announce(String(localized: "Burst started.", bundle: .module, comment: "Announced to VoiceOver when a burst starts."))
                }
            }
            .onChange(of: drive.lastBurst) { _, result in
                if let result, let message = DriveText.endMessage(result) { Self.announce(message) }
            }
    }

    /// Posts a VoiceOver announcement.
    ///
    /// - Parameter message: What to say.
    private static func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}

extension View {
    /// Adds the self-timer and burst feedback (``DriveFeedback``).
    ///
    /// - Parameter drive: The drive model.
    func driveFeedback(_ drive: DriveModel) -> some View {
        modifier(DriveFeedback(drive: drive))
    }

    /// Adds what the shutter does in the current drive mode, or with the astro helper on, to
    /// its VoiceOver value.
    ///
    /// - Parameter model: The camera model.
    func shutterDriveValue(_ model: CameraModel) -> some View {
        accessibilityValue(AstroText.shutterValue(model) ?? DriveText.shutterValue(model) ?? Text(verbatim: ""))
            .accessibilityHint(DriveText.shutterHint(model) ?? Text(verbatim: ""))
    }
}
