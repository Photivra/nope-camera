import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// Which mode card shows for each state of the drive modes, and the numbers on the cards
/// (docs/design/BUILD-SPEC.md, 3.5).
struct DriveCardsTests {
    /// The card for a state; every value not given is idle.
    private func card(
        mode: DriveMode = .single, countdown: Int? = nil, burst: BurstProgress? = nil, endedBurst: BurstResult? = nil,
        burstSpeed: BurstSpeed = .fast, burstLimit: Int? = nil, interval: IntervalProgress? = nil, isAstroOn: Bool = false,
        astroRun: AstroRun? = nil, estimate: AstroEstimate? = nil, showsControls: Bool = true
    ) -> ModeCardState? {
        ModeCardState.resolve(
            mode: mode, countdownRemaining: countdown, burst: burst, endedBurst: endedBurst, burstSpeed: burstSpeed,
            burstLimit: burstLimit, intervalProgress: interval,
            intervalSettings: .standard, isAstroOn: isAstroOn, astroRun: astroRun, astroStartDelay: .tenSeconds,
            astroEstimate: estimate, showsControls: showsControls)
    }

    @Test func singleAndTimerHaveNoIdleCard() {
        #expect(card(mode: .single) == nil)
        #expect(card(mode: .timer(.threeSeconds)) == nil)
    }

    @Test func burstIdleCardShowsTheSpeedAndHidesInCleanView() {
        #expect(card(mode: .burst) == .burstIdle(.fast))
        #expect(card(mode: .burst, burstSpeed: .slow) == .burstIdle(.slow))
        #expect(card(mode: .burst, showsControls: false) == nil)
        #expect(!ModeCardState.burstIdle(.fast).isRunning)
    }

    @Test func aBurstLimitShowsInTheIdleCard() {
        #expect(card(mode: .burst, burstLimit: 10) == .burstIdle(.fast, limit: 10))
        #expect(card(mode: .burst, burstSpeed: .slow, burstLimit: 3) == .burstIdle(.slow, limit: 3))
        #expect(card(mode: .burst, burstLimit: 10, showsControls: false) == nil)
        let running = BurstProgress(taken: 3, saved: 2, start: .limited, limit: 10)
        #expect(card(mode: .burst, burst: running, burstLimit: 10) == .burstRunning(running))
        let ended = BurstResult(end: .countReached, saved: 10, start: .limited, limit: 10)
        #expect(card(mode: .burst, endedBurst: ended, burstLimit: 10) == .burstEnded(ended))
    }

    @MainActor
    @Test func aLimitedBurstKeepsItsSummary() {
        #expect(ModeCardState.showsEnd(BurstResult(end: .countReached, saved: 10, start: .limited, limit: 10)))
        #expect(ModeCardState.showsEnd(BurstResult(end: .stopped, saved: 1, start: .limited, limit: 10)))
    }

    @Test func burstCardsResolveRunningThenSavingThenEndedThenIdle() {
        let running = BurstProgress(taken: 12, saved: 11, start: .held, rate: 2.6)
        let summary = BurstResult(end: .stopped, saved: 12, start: .held, duration: .seconds(4.2), rate: 2.6)
        #expect(card(mode: .burst, burst: running, endedBurst: summary) == .burstRunning(running))
        let saving = BurstProgress(taken: 12, saved: 9, start: .held, isSaving: true)
        #expect(card(mode: .burst, burst: saving, endedBurst: summary) == .burstSaving(saved: 9, taken: 12))
        #expect(card(mode: .burst, burst: saving, showsControls: false) == .burstSaving(saved: 9, taken: 12))
        #expect(ModeCardState.burstSaving(saved: 9, taken: 12).isRunning)
        #expect(card(mode: .burst, endedBurst: summary) == .burstEnded(summary))
        #expect(card(mode: .burst, endedBurst: summary, showsControls: false) == nil)
    }

    @MainActor
    @Test func aBurstKeepsAnEndCardForASummaryOrAStopByItself() {
        #expect(ModeCardState.showsEnd(BurstResult(end: .stopped, saved: 12, start: .held)))
        #expect(ModeCardState.showsEnd(BurstResult(end: .limitReached, saved: 50, start: .counted)))
        #expect(ModeCardState.showsEnd(BurstResult(end: .storageFull, saved: 0, start: .held)))
        #expect(!ModeCardState.showsEnd(BurstResult(end: .stopped, saved: 1, start: .held)), "one photo is a photo")
        #expect(!ModeCardState.showsEnd(BurstResult(end: .countReached, saved: 3, start: .counted)), "Siri says it")
        #expect(!ModeCardState.showsEnd(BurstResult(end: .failed, saved: 3, start: .held)))
    }

    @Test func runningModesShowTheirProgress() {
        #expect(card(mode: .timer(.threeSeconds), countdown: 3) == .timerCountdown(remaining: 3))
        let burst = BurstProgress(taken: 12, saved: 11)
        #expect(card(mode: .burst, burst: burst) == .burstRunning(burst))
        let progress = IntervalProgress(taken: 3, total: 10)
        #expect(card(mode: .interval, interval: progress) == .intervalRunning(progress))
        // A series started from Siri or a preset shows whatever the mode.
        #expect(card(mode: .single, interval: progress) == .intervalRunning(progress))
    }

    @Test func idleCardsOpenTheirSettingsAndHideInCleanView() {
        #expect(card(mode: .interval) == .intervalIdle(.standard))
        #expect(card(mode: .interval, showsControls: false) == nil)
        let estimate = AstroEstimate(frameCount: 20, shutter: 1, bytes: 486_000_000, framesThatFit: nil)
        #expect(card(isAstroOn: true, estimate: estimate) == .astroReady(frameCount: 20, startDelay: .tenSeconds, estimate: estimate))
        #expect(card(isAstroOn: true, showsControls: false) == nil)
    }

    @Test func runningCardsStayInCleanView() {
        #expect(card(mode: .timer(.tenSeconds), countdown: 9, showsControls: false) == .timerCountdown(remaining: 9))
        let run = AstroRun(taken: 6, frameCount: 20, isPaused: false, shutter: 1)
        #expect(card(isAstroOn: true, astroRun: run, showsControls: false) == .astroRunning(run))
        #expect(ModeCardState.timerCountdown(remaining: 1).isRunning)
        #expect(ModeCardState.astroRunning(run).isRunning)
        #expect(!ModeCardState.intervalIdle(.standard).isRunning)
        #expect(!ModeCardState.astroReady(frameCount: 20, startDelay: .tenSeconds, estimate: nil).isRunning)
        #expect(!ModeCardState.burstEnded(BurstResult(end: .storageFull, saved: 2)).isRunning)
        #expect(ModeCardState.astroCountdown(remaining: 2).isRunning)
        #expect(ModeCardState.burstRunning(BurstProgress(taken: 1, saved: 0)).isRunning)
        #expect(ModeCardState.intervalRunning(IntervalProgress(taken: 0, total: 2)).isRunning)
    }

    @Test func astroCountsDownToItsFirstFrameThenKeepsItsProgress() {
        #expect(card(countdown: 8, isAstroOn: true) == .astroCountdown(remaining: 8))
        // After a pause the start delay runs again; the card keeps the run's frame count.
        let run = AstroRun(taken: 7, frameCount: 20, isPaused: false, shutter: 1)
        #expect(card(countdown: 10, isAstroOn: true, astroRun: run) == .astroRunning(run))
    }

    @Test func aBurstThatStoppedByItselfSaysWhyInBurstMode() {
        let ended = BurstResult(end: .limitReached, saved: 50)
        #expect(card(mode: .burst, endedBurst: ended) == .burstEnded(ended))
        #expect(card(mode: .single, endedBurst: ended) == nil)
        #expect(card(mode: .burst, endedBurst: ended, showsControls: false) == nil)
    }

    @Test func astroRunNumbers() {
        let run = AstroRun(taken: 6, frameCount: 20, isPaused: false, shutter: 1)
        #expect(run.frameNumber == 7)
        #expect(run.fractionDone == 0.3)
        #expect(run.exposureSecondsLeft == 14)
        let last = AstroRun(taken: 20, frameCount: 20, isPaused: false, shutter: 2)
        #expect(last.frameNumber == 20)
        #expect(last.exposureSecondsLeft == 0)
        #expect(AstroRun(taken: 0, frameCount: 5, isPaused: true, shutter: nil).exposureSecondsLeft == nil)
        #expect(AstroRun(taken: 0, frameCount: 0, isPaused: false, shutter: 1).fractionDone == 0)
    }

    @Test func nextPhotoCountsDownInWholeSeconds() {
        let start = ContinuousClock.now
        let timing = NextPhotoTiming(due: start + .seconds(10))
        #expect(timing.secondsLeft(at: start) == 10)
        #expect(timing.secondsLeft(at: start + .seconds(4.2)) == 6)
        #expect(timing.secondsLeft(at: start + .seconds(9.99)) == 1)
        // Once due, the photo is being taken or waits for the camera: no time is shown.
        #expect(timing.secondsLeft(at: start + .seconds(10)) == nil)
        #expect(timing.secondsLeft(at: start + .seconds(12)) == nil)
    }

    @MainActor
    @Test func cardWordsUseSystemFormatting() {
        #expect(ModeCardText.intervalSummary(.standard) == "Every 10 seconds, 10 photos")
        #expect(ModeCardText.astroFrames(20) == "Astro frames: 20")
        let estimate = AstroEstimate(frameCount: 20, shutter: 1, bytes: 486_000_000, framesThatFit: nil)
        let summary = ModeCardText.astroSummary(startDelay: .tenSeconds, estimate: estimate)
        #expect(summary?.hasPrefix("After 10 seconds · 20") == true)
        #expect(summary?.contains("486") == true)
        #expect(ModeCardText.astroSummary(startDelay: .tenSeconds, estimate: nil) == nil)
        #expect(
            ModeCardText.astroSummary(
                startDelay: .threeSeconds, estimate: AstroEstimate(frameCount: 5, shutter: nil, bytes: 1, framesThatFit: nil)) == nil)
        #expect(ModeCardText.shortDuration(13).contains("13"))
        #expect(ModeCardText.spokenDuration(120) == "2 minutes")
        #expect(AstroText.turnedOn(isNightModeOn: true) == "Astro on. Manual controls and night mode are on.")
        // Night mode is named only while it is on (Astro from a preset doesn't turn it on).
        #expect(AstroText.turnedOn(isNightModeOn: false) == "Astro on. Manual controls are on.")
    }
}
