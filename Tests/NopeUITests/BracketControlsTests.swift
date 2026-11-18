import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// The Bracket word of the drive strip and which bracket card shows in each state
/// (docs/design/BRACKETING.md, sections 3 and 4).
@MainActor
struct BracketControlsTests {
    @Test func bracketIsSelectedWithSingleOrTheTimer() {
        #expect(DriveWord.selected(mode: .single, isAstroOn: false, isBracketOn: true) == .bracket)
        #expect(DriveWord.selected(mode: .timer(.tenSeconds), isAstroOn: false, isBracketOn: true) == .bracket)
        #expect(DriveWord.selected(mode: .burst, isAstroOn: false, isBracketOn: true) == .burst)
        #expect(DriveWord.selected(mode: .single, isAstroOn: true, isBracketOn: true) == .astro)
        #expect(DriveWord.selected(mode: .timer(.threeSeconds), isAstroOn: false) == .timer)
    }

    @Test func bracketIsTheFourthOfSixWords() {
        #expect(
            DriveWord.offered(offersAstro: true, offersBracket: true) == [.single, .timer, .burst, .bracket, .interval, .astro])
        #expect(DriveWord.offered(offersAstro: false, offersBracket: true) == [.single, .timer, .burst, .bracket, .interval])
        #expect(DriveWord.bracket.mode(timerDelay: .threeSeconds) == nil)
        #expect(DriveWord.bracket.systemImage == "square.3.layers.3d")
        #expect(DriveWord.bracket.string == "Bracket")
    }

    @Test func whichCardShows() {
        let bracket = BracketSettings.standard
        func card(
            bracket: BracketSettings? = bracket, delay: SelfTimerDelay? = nil, countdown: Int? = nil,
            progress: BracketProgress? = nil, saved: BracketCardState? = nil, showsControls: Bool = true
        ) -> BracketCardState? {
            BracketCardState.resolve(
                bracket: bracket, startDelay: delay, countdownRemaining: countdown, progress: progress, saved: saved,
                showsControls: showsControls)
        }
        #expect(card(bracket: nil) == nil)
        #expect(card() == .idle(bracket, startDelay: nil))
        #expect(card(delay: .threeSeconds) == .idle(bracket, startDelay: .threeSeconds))
        #expect(card(showsControls: false) == nil)
        #expect(card(countdown: 3, showsControls: false) == .countdown(remaining: 3, bracket))
        let taking = BracketProgress(taken: 0, saved: 0, total: 3)
        let saving = BracketProgress(taken: 3, saved: 2, total: 3)
        // A Siri bracket taken once shows its progress with no bracket on.
        #expect(card(bracket: nil, progress: taking) == .taking(total: 3))
        #expect(card(progress: saving, showsControls: false) == .saving(saving))
        let saved = BracketCardState.saved(count: 3, offsets: [-1, 0, 1])
        #expect(card(saved: saved) == saved)
        #expect(card(saved: saved, showsControls: false) == nil)
        let running = [BracketCardState.countdown(remaining: 1, bracket), .taking(total: 3), .saving(saving)].map(\.isRunning)
        #expect(running == [true, true, true])
        let idle = [BracketCardState.idle(bracket, startDelay: nil), saved].map(\.isRunning)
        #expect(idle == [false, false])
    }

    @Test func theSavedCardComesFromABracketsResult() {
        let frame = BracketFramePlan(
            number: 1, requestedOffset: 0, offset: 0, frame: BracketFrame(iso: 100, exposureDuration: 0.01),
            limitingFrameNumber: nil)
        let place = BracketPlace(type: .exposure, frame: frame, count: 3, offsets: [0, -1, 1], order: .meteredFirst)
        let photo = SavedPhoto(formats: [.raw], isProcessedFallback: false, signature: .signed, metadata: [:], bracket: place)
        #expect(BracketCardState.saved(from: .savedBracket([photo, photo, photo])) == .saved(count: 3, offsets: [0, -1, 1]))
        let plain = SavedPhoto(formats: [.raw], isProcessedFallback: false, signature: .signed, metadata: [:])
        #expect(BracketCardState.saved(from: .savedBracket([plain])) == nil)
        #expect(BracketCardState.saved(from: .idle) == nil)
    }

    @Test func theWords() {
        let bracket = BracketSettings(frameCount: 5, step: 2, order: .meteredFirst)
        #expect(BracketText.summary(bracket) == "Exposure bracket: 5 frames, 2 EV apart")
        #expect(BracketText.offsets(bracket.offsets) == "0, -2, +2, -4, +4 EV")
        #expect(BracketText.idleDetail(.standard, startDelay: .threeSeconds) == "-1, 0, +1 EV · after 3 seconds")
        #expect(BracketText.framesAndOffsets(.standard) == "3 frames, -1, 0, +1 EV")
        #expect(BracketText.stopped(BracketProgress(taken: 3, saved: 2, total: 3)) == "Bracket stopped: 2 of 3 photos saved.")
        let frame = BracketFramePlan(
            number: 2, requestedOffset: 0, offset: 0, frame: BracketFrame(iso: 200, exposureDuration: 1.0 / 125),
            limitingFrameNumber: nil)
        let place = BracketPlace(type: .exposure, frame: frame, count: 3, offsets: [-1, 0, 1], order: .darkestFirst)
        #expect(BracketText.chip(place) == "Exposure bracket · frame 2 of 3 · 0 EV")
        #expect(BracketText.chipSpoken(place) == "Exposure bracket, frame 2 of 3, 0 EV.")
        #expect(BracketOrder.allCases.map(BracketText.name) == ["Darkest First", "Metered First", "Brightest First"])
    }
}
