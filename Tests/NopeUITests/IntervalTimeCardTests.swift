import Foundation
import NopeCore
import SwiftUI
import Testing

@testable import NopeUI

/// The words of the interval card for a series that stops after a time: the idle summary, the
/// time left with the count (one photo and several), and when a paused series ends.
@MainActor
struct IntervalTimeCardTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// A moment of the monotonic clock, for series that start at it.
    static let instant = ContinuousClock.now

    /// A series of `seconds` that started at ``instant``.
    func timed(taken: Int, seconds: Double, isPaused: Bool = false) -> IntervalProgress {
        IntervalProgress(
            taken: taken, total: nil, isPaused: isPaused, deadline: Self.instant + .seconds(seconds), duration: .seconds(seconds))
    }

    @Test func theIdleCardSaysHowLongTheSeriesRuns() {
        let timed = IntervalSettings(interval: 10, count: 10, stopAfter: .time, duration: 5400)
        #expect(ModeCardText.intervalSummary(timed) == "Every 10 seconds, for 1 hour, 30 minutes")
        #expect(ModeCardText.intervalSummary(.standard) == "Every 10 seconds, 10 photos")
        #expect(ModeCardText.intervalIdleDetail(timed) == nil)
        #expect(ModeCardText.intervalIdleDetail(.standard) == nil)
        let tooLong = timed.with(interval: 3600).with(duration: 1800)
        #expect(ModeCardText.intervalIdleDetail(tooLong) == "Choose an interval shorter than the time.")
    }

    @Test func theRunningCardCountsPhotosAndTheTimeLeft() {
        let now = Self.instant + .seconds(18 * 60)
        let one = timed(taken: 1, seconds: 5400)
        #expect(ModeCardText.intervalTimeProgressString(one, at: now) == "1 photo taken · 1 hr, 12 min left")
        let twelve = timed(taken: 12, seconds: 5400)
        #expect(ModeCardText.intervalTimeProgressString(twelve, at: now) == "12 photos taken · 1 hr, 12 min left")
        #expect(
            ModeCardText.intervalTimeProgressString(twelve, at: now, width: .wide)
                == "12 photos taken · 1 hour, 12 minutes left")
        // Part of a minute counts as a whole one.
        #expect(
            ModeCardText.intervalTimeProgressString(twelve, at: Self.instant + .seconds(5400 - 20))
                == "12 photos taken · 1 min left")
        #expect(
            ModeCardText.intervalTimeProgressString(timed(taken: 12, seconds: 5400, isPaused: true), at: now)
                == "Paused: 12 photos taken · 1 hr, 12 min left")
        #expect(
            ModeCardText.intervalTimeProgressString(IntervalProgress(taken: 0, total: 10), at: now)
                == "0 photos taken · 0 min left")
    }

    @Test func aPausedCardSaysWhenTheSeriesEnds() {
        let now = Self.start
        let sameDay = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
        let expectedTime = sameDay.formatted(.dateTime.hour().minute())
        if Calendar.current.isDate(sameDay, inSameDayAs: now) {
            #expect(ModeCardText.intervalEnds(at: sameDay, now: now) == "Ends at \(expectedTime)")
        }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        #expect(
            ModeCardText.intervalEnds(at: tomorrow, now: now)
                == "Ends at \(tomorrow.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
    }

    @Test func aTimedSeriesShowsItsRunningCard() {
        let progress = timed(taken: 2, seconds: 600)
        let state = ModeCardState.resolve(
            mode: .interval, countdownRemaining: nil, burst: nil, endedBurst: nil, intervalProgress: progress,
            intervalSettings: .standard, isAstroOn: false, astroRun: nil, astroStartDelay: .tenSeconds,
            astroEstimate: nil, showsControls: false)
        #expect(state == .intervalRunning(progress))
        #expect(IntervalTimeCard<EmptyView>.refreshSeconds == 60)
    }
}
