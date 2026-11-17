import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// The drive strip's words and the lens row's centering (docs/design/BUILD-SPEC.md, 3.1 and 3.5).
struct CameraShellTests {
    @Test func selectedWordFollowsTheModeAndAstro() {
        #expect(DriveWord.selected(mode: .single, isAstroOn: false) == .single)
        #expect(DriveWord.selected(mode: .timer(.tenSeconds), isAstroOn: false) == .timer)
        #expect(DriveWord.selected(mode: .burst, isAstroOn: false) == .burst)
        #expect(DriveWord.selected(mode: .interval, isAstroOn: false) == .interval)
        // The astro helper takes over the shutter whatever the mode.
        #expect(DriveWord.selected(mode: .burst, isAstroOn: true) == .astro)
    }

    @Test func astroIsOfferedOnlyWhereItCanBeUsed() {
        #expect(DriveWord.offered(offersAstro: true) == [.single, .timer, .burst, .interval, .astro])
        #expect(DriveWord.offered(offersAstro: false) == [.single, .timer, .burst, .interval])
    }

    @Test func eachWordChoosesItsMode() {
        #expect(DriveWord.single.mode(timerDelay: .threeSeconds) == .single)
        #expect(DriveWord.timer.mode(timerDelay: .tenSeconds) == .timer(.tenSeconds))
        #expect(DriveWord.burst.mode(timerDelay: .threeSeconds) == .burst)
        #expect(DriveWord.interval.mode(timerDelay: .threeSeconds) == .interval)
        #expect(DriveWord.astro.mode(timerDelay: .threeSeconds) == nil)
        #expect(Set(DriveWord.allCases.map(\.systemImage)).count == DriveWord.allCases.count)
    }

    @Test func middleIsCenteredWhenTheSidesAllowIt() {
        let frames = CenteredRowLayout.horizontalFrames(widths: (90, 140, 44), width: 370, spacing: 8)
        #expect(frames.middle == 115...255)
        #expect(frames.leading == 0...90)
        #expect(frames.trailing == 326...370)
    }

    @Test func middleMovesAwayFromAWideSide() {
        // A long Manual word: centered, the group would start at 115, inside the 130-point side.
        let frames = CenteredRowLayout.horizontalFrames(widths: (130, 140, 44), width: 370, spacing: 8)
        #expect(frames.middle.lowerBound == 138)
        #expect(frames.middle.upperBound <= frames.trailing.lowerBound - 8)
    }

    @Test func sidesShareWhatIsLeftWhenNothingFits() {
        let frames = CenteredRowLayout.horizontalFrames(widths: (200, 140, 200), width: 370, spacing: 8)
        #expect(frames.middle == 115...255)
        #expect(frames.leading == 0...107)
        #expect(frames.trailing == 263...370)
    }
}
