import Foundation
import Testing

@testable import NopeCore

/// The close-up detector judged by time (docs/design/device-feedback-1.0.md, section 6): a
/// search seen on the way into the near band counts, short searches out of the band and back
/// are allowed, and readings that arrive together prove nothing.
struct CloseUpDetectorTests {
    typealias Fixtures = AutoFixtures

    /// The lens at its nearest position, not searching.
    static let resting = Fixtures.reading(lensPosition: 0)

    /// The lens at its nearest position, searching.
    static let searchingNear = Fixtures.reading(lensPosition: 0.02, adjusting: true)

    /// Records readings a quarter second apart, from a start, and returns each answer.
    ///
    /// - Parameters:
    ///   - readings: The readings.
    ///   - detector: The detector.
    ///   - start: The time of the first reading.
    ///   - spacing: The time between readings.
    /// - Returns: The detector's answer after each reading.
    static func record(
        _ readings: [ExposureReading], in detector: inout CloseUpDetector, from start: ContinuousClock.Instant,
        spacing: Duration = .milliseconds(250)
    ) -> [Bool] {
        readings.enumerated().map { index, reading in detector.record(reading, at: start + spacing * index) }
    }

    @Test func thresholdsAreTheProvisionalValues() {
        #expect(CloseUpDetector.nearestPosition == 0.05)
        #expect(CloseUpDetector.window == .milliseconds(2500))
        #expect(CloseUpDetector.requiredNearTime == .seconds(2))
        #expect(CloseUpDetector.searchMemory == .seconds(4))
    }

    @Test func restingAtTheNearestPositionWithoutASearchIsNotTooClose() {
        var detector = CloseUpDetector()
        let answers = Self.record(Array(repeating: Self.resting, count: 20), in: &detector, from: .now)
        #expect(answers.allSatisfy { !$0 })
    }

    @Test func aSweepIntoTheNearBandThenRestingThereIsTooClose() {
        // The realistic case: autofocus searches while the lens moves in, then the lens sits at
        // its nearest position and the search has ended.
        var detector = CloseUpDetector()
        let sweep = [0.6, 0.45, 0.3, 0.15, 0.08].map { Fixtures.reading(lensPosition: $0, adjusting: true) }
        let answers = Self.record(sweep + Array(repeating: Self.resting, count: 12), in: &detector, from: .now)
        // Two seconds after reaching the band (eight readings later) it reports, and keeps
        // reporting while the lens stays.
        #expect(answers.prefix(13).allSatisfy { !$0 })
        #expect(answers.dropFirst(13).allSatisfy { $0 })
    }

    @Test func aShortSearchOutOfTheBandDoesNotStartAgain() {
        var detector = CloseUpDetector()
        let near = Array(repeating: Self.searchingNear, count: 4)
        let out = [Fixtures.reading(lensPosition: 0.2, adjusting: true)]
        // A quarter second out of the band in the middle: near for 2.25 of the last 2.5 seconds.
        let answers = Self.record(near + out + near + Array(repeating: Self.resting, count: 3), in: &detector, from: .now)
        #expect(answers.last == true)
        // A strict run would have started again at the reading out of the band.
        #expect(answers.prefix(9).allSatisfy { !$0 })
        #expect(answers.dropFirst(10).allSatisfy { $0 })
    }

    @Test func tooLongOutOfTheBandEndsIt() {
        var detector = CloseUpDetector()
        let start = ContinuousClock.now
        var answers = Self.record(Array(repeating: Self.searchingNear, count: 10), in: &detector, from: start)
        #expect(answers.last == true)
        // Out of the band from 2.5 seconds: three quarters of a second out still leaves 2 of the
        // last 2.5 seconds near; a second out doesn't.
        let out = Fixtures.reading(lensPosition: 0.5, adjusting: true)
        answers = Self.record(Array(repeating: out, count: 4), in: &detector, from: start + .milliseconds(2500))
        #expect(answers == [true, true, true, false])
    }

    @Test func aSearchLongAgoDoesNotCount() {
        var detector = CloseUpDetector()
        let start = ContinuousClock.now
        let searchedFar = detector.record(Fixtures.reading(lensPosition: 0.5, adjusting: true), at: start)
        #expect(!searchedFar)
        // The lens reaches the band five seconds later and rests: the search is too old.
        let answers = Self.record(Array(repeating: Self.resting, count: 12), in: &detector, from: start + .seconds(5))
        #expect(answers.allSatisfy { !$0 })
    }

    @Test func readingsAtOneInstantProveNothing() {
        var detector = CloseUpDetector()
        let answers = Self.record(Array(repeating: Self.searchingNear, count: 20), in: &detector, from: .now, spacing: .zero)
        #expect(answers.allSatisfy { !$0 })
    }

    @Test func aReadingHoldsUntilTheNextOne() {
        // Readings come only when something changes: two readings two seconds apart, both near,
        // count the whole time between them as near.
        var detector = CloseUpDetector()
        let start = ContinuousClock.now
        let atFirst = detector.record(Self.searchingNear, at: start)
        let twoSecondsLater = detector.record(Self.resting, at: start + .seconds(2))
        // Later, and long after with old readings dropped from the window: still near.
        let threeSecondsLater = detector.record(Self.resting, at: start + .seconds(3))
        let nineSecondsLater = detector.record(Self.resting, at: start + .seconds(9))
        #expect(!atFirst)
        #expect(twoSecondsLater)
        #expect(threeSecondsLater)
        #expect(nineSecondsLater)
    }

    @MainActor
    @Test func theModelReadsTheMonotonicClockByDefault() {
        let before = ContinuousClock.now
        let model = ManualControlsModel(backend: nil, sleep: { _ in })
        #expect(model.now() >= before)
    }
}
