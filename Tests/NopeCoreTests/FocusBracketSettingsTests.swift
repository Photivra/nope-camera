import Foundation
import Testing

@testable import NopeCore

/// A focus bracket's settings: the positions, the step, the order and the frame choices
/// (docs/design/BRACKETING.md, section 5).
struct FocusBracketSettingsTests {
    @Test func positionsAreEvenlySpacedInTheOrderTaken() {
        let settings = FocusBracketSettings(nearest: 0.2, farthest: 0.8, frameCount: 7)
        let expected = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
        #expect(zip(settings.positions, expected).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(settings.positions.last == 0.8)
        #expect(abs(settings.step - 0.1) < 1e-9)
        let reversed = settings.with(order: .farthestFirst)
        #expect(reversed.positions == settings.positions.reversed())
    }

    @Test func theStandardBracketCoversTheWholeRange() {
        let standard = FocusBracketSettings.standard
        #expect(standard.nearest == 0)
        #expect(standard.farthest == 1)
        #expect(standard.frameCount == 10)
        #expect(standard.order == .nearestFirst)
        #expect(standard.returnsFocus)
        #expect(standard.isWholeRange)
        #expect(!standard.with(nearest: 0.1).isWholeRange)
        #expect(!standard.with(farthest: 0.9).isWholeRange)
    }

    @Test func swappedEndsAreOrderedAndKeptInsideTheScale() {
        let swapped = FocusBracketSettings(nearest: 0.9, farthest: 0.1, frameCount: 3)
        #expect(swapped.nearest == 0.1)
        #expect(swapped.farthest == 0.9)
        let outside = FocusBracketSettings(nearest: -1, farthest: 2, frameCount: 3)
        #expect(outside.nearest == 0)
        #expect(outside.farthest == 1)
        let same = FocusBracketSettings(nearest: 0.5, farthest: 0.5, frameCount: 3)
        #expect(same.positions == [0.5, 0.5, 0.5])
        #expect(same.step == 0)
    }

    @Test func frameCountsMoveToTheNearestOffered() {
        #expect(FocusBracketSettings.frameCounts == [3, 5, 7, 10, 12, 15, 20, 30, 40, 50])
        #expect(FocusBracketSettings.offeredFrameCount(nearestTo: 1) == 3)
        #expect(FocusBracketSettings.offeredFrameCount(nearestTo: 11) == 10)
        #expect(FocusBracketSettings.offeredFrameCount(nearestTo: 25) == 20)
        #expect(FocusBracketSettings.offeredFrameCount(nearestTo: 500) == 50)
        #expect(FocusBracketSettings(nearest: 0, farthest: 1, frameCount: 13).frameCount == 12)
    }

    @Test func aCopyChangesOneValue() {
        let settings = FocusBracketSettings(nearest: 0.1, farthest: 0.7, frameCount: 12, order: .farthestFirst, returnsFocus: false)
        #expect(settings.with() == settings)
        #expect(settings.with(frameCount: 20).frameCount == 20)
        #expect(settings.with(returnsFocus: true).returnsFocus)
        #expect(settings.with(order: .nearestFirst).order == .nearestFirst)
    }

    @Test func settingsAreStoredByName() throws {
        let settings = FocusBracketSettings(nearest: 0.25, farthest: 0.75, frameCount: 5, order: .farthestFirst)
        let decoded = try JSONDecoder().decode(FocusBracketSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(FocusBracketOrder.farthestFirst.rawValue == "farthestFirst")
        #expect(BracketType.focus.rawValue == "focus")
        #expect(BracketType.allCases == [.exposure, .focus])
    }

    @Test func aLensOffersFocusOnlyWhenItsFocusCanBeSet() {
        #expect(FocusBracketSettings.isAvailable(on: ManualFixtures.wide))
        #expect(!FocusBracketSettings.isAvailable(on: ManualFixtures.bare))
    }
}

/// A focus frame's place, the progress and the result.
struct FocusBracketValuesTests {
    @Test func aFrameIsOffPlanBeyondTheTolerance() {
        let near = FocusFramePlace(number: 1, plannedPosition: 0.5, reportedPosition: 0.49, positions: [0.5], order: .nearestFirst)
        let far = FocusFramePlace(number: 1, plannedPosition: 0.5, reportedPosition: 0.45, positions: [0.5], order: .nearestFirst)
        #expect(!near.isOffPlan)
        #expect(far.isOffPlan)
        let place = BracketPlace(focus: far, count: 3)
        #expect(place.type == .focus)
        #expect(place.number == 1)
        #expect(place.count == 3)
        #expect(place.frame == nil)
        #expect(place.offsets.isEmpty)
        #expect(place.order == nil)
        #expect(place.focus == far)
    }

    @Test func anExposurePlaceKeepsItsFrame() {
        let frame = BracketFramePlan(
            number: 2, requestedOffset: 0, offset: 0, frame: BracketFrame(iso: 100, exposureDuration: 0.01),
            limitingFrameNumber: nil)
        let place = BracketPlace(type: .exposure, frame: frame, count: 3, offsets: [-1, 0, 1], order: .darkestFirst)
        #expect(place.number == 2)
        #expect(place.focus == nil)
        #expect(place.order == .darkestFirst)
    }

    @Test func progressCountsTheFrameBeingTaken() {
        let progress = FocusBracketProgress(taken: 0, saved: 0, total: 3)
        #expect(progress.frameNumber == 1)
        #expect(progress.position == nil)
        #expect(!progress.isPaused)
        let later = progress.with(taken: 3, saved: 3, position: 0.4, isPaused: true)
        #expect(later.frameNumber == 3)
        #expect(later.position == 0.4)
        #expect(later.isPaused)
        #expect(later.with().position == 0.4)
    }

    @Test func aResultIsFinishedOnlyWithEveryFrameSaved() {
        #expect(FocusBracketResult(end: .limitReached, saved: 3, total: 3, offPlan: 0, focusAfter: .automatic).isFinished)
        #expect(!FocusBracketResult(end: .limitReached, saved: 2, total: 3, offPlan: 0, focusAfter: .automatic).isFinished)
        #expect(!FocusBracketResult(end: .stopped, saved: 3, total: 3, offPlan: 0, focusAfter: .stays(1)).isFinished)
    }

    @Test func theEditingStateFollowsTheLensOnlyAfterATap() {
        let editing = FocusRangeEditing(end: .nearest, value: 0.2)
        #expect(!editing.followsLens)
        #expect(FocusRangeEditing(end: .farthest, value: 0.2, followsLens: true).followsLens)
    }
}

/// The shortcut request for a focus bracket.
struct FocusBracketShortcutTests {
    @Test func aRequestIsAnExposureBracketByDefault() {
        let request = BracketShortcut(frameCount: 3, step: 1)
        #expect(request.type == .exposure)
        #expect(request.focusFrameCount == 10)
        #expect(request.focusRange == .asSet)
    }

    @Test func aFocusRequestMovesItsFramesToTheNearestOffered() {
        let request = BracketShortcut(type: .focus, focusFrameCount: 44, focusRange: .wholeRange, frameCount: 3, step: 1)
        #expect(request.type == .focus)
        #expect(request.focusFrameCount == 40)
        #expect(request.focusRange == .wholeRange)
        #expect(FocusBracketRange.allCases == [.asSet, .wholeRange])
    }
}
