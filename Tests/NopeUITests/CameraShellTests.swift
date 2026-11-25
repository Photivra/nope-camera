import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// The drive strip's words, the lens row's centering (docs/design/BUILD-SPEC.md, 3.1 and 3.5) and
/// the space between the camera's control rows (issue #116; docs/design/finish-1.0.md, 1.2 to 1.4).
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

    /// The spare height and row gap of each screen size in docs/design/finish-1.0.md, 1.3, with
    /// the safe-area insets measured on the iOS 27.2 Simulators: screen (width, height), insets
    /// (top, bottom), spare height, row gap.
    static let screenSizes: [(size: CGSize, insets: (top: CGFloat, bottom: CGFloat), spare: CGFloat, gap: CGFloat)] = [
        (CGSize(width: 393, height: 852), (59, 34), 3, 2),
        (CGSize(width: 402, height: 874), (62, 34), 10, 4),
        (CGSize(width: 390, height: 844), (47, 34), 11, 5),
        (CGSize(width: 414, height: 896), (48, 34), 30, 11),
        (CGSize(width: 430, height: 932), (59, 34), 34, 12),
        (CGSize(width: 440, height: 956), (62, 34), 41, 15),
        (CGSize(width: 428, height: 926), (47, 34), 42, 15),
    ]

    /// The space between the status line and the shutter row at its smallest, for a screen.
    static func middleSpace(_ size: CGSize, insets: (top: CGFloat, bottom: CGFloat)) -> CGSize {
        CGSize(
            width: size.width,
            height: size.height - insets.top - insets.bottom - CameraLayout.topBarHeight - CameraLayout.shutterRowHeight)
    }

    /// The rows' own height: the 56-point lens row and the 44-point drive strip.
    static let rowsHeight = NopeSize.lensRow + NopeSize.driveRow

    @Test(arguments: screenSizes.indices)
    func eachScreenSizeGetsTheDesignsGap(index: Int) {
        let screen = Self.screenSizes[index]
        let space = Self.middleSpace(screen.size, insets: screen.insets)
        let spare = CameraLayout.spareHeight(in: space, bandsHeight: Self.rowsHeight)
        #expect(spare.rounded(.down) == screen.spare.rounded(.down) || spare.rounded(.up) == screen.spare, "spare \(spare)")
        #expect(CameraLayout.rowGap(spareHeight: spare) == screen.gap)
        // The picture keeps its size: the rows and the gap fit below the whole picture.
        #expect(!CameraLayout.bandsOverlayPicture(in: space, bandsHeight: Self.rowsHeight))
        #expect(CameraLayout.lensRowLift(rowGap: screen.gap) == 0)
    }

    @Test func theSmallestIPhonesHaveNoSpareHeight() {
        // 4.7-inch (375 × 667, insets 20 / 0) and 5.4-inch (375 × 812, insets 50 / 34): the rows
        // overlay the picture, so nothing is shared and the lens controls move up instead.
        for (size, insets) in [(CGSize(width: 375, height: 667), (CGFloat(20), CGFloat(0))), (CGSize(width: 375, height: 812), (50, 34))] {
            let space = Self.middleSpace(size, insets: insets)
            #expect(CameraLayout.bandsOverlayPicture(in: space, bandsHeight: Self.rowsHeight))
            #expect(CameraLayout.spareHeight(in: space, bandsHeight: Self.rowsHeight) == 0)
            #expect(CameraLayout.rowGap(spareHeight: 0) == 0)
            #expect(CameraLayout.lensRowLift(rowGap: 0) == 2)
        }
    }

    @Test func theGapTakesTwoPointsThenAThirdUpToTheCap() {
        #expect(CameraLayout.minimumRowGap == 2)
        #expect(CameraLayout.rowGap(spareHeight: -5) == 0)
        #expect(CameraLayout.rowGap(spareHeight: 0) == 0)
        #expect(CameraLayout.rowGap(spareHeight: 1) == 1)
        #expect(CameraLayout.rowGap(spareHeight: 1.5) == 1)
        #expect(CameraLayout.rowGap(spareHeight: 2) == 2)
        #expect(CameraLayout.rowGap(spareHeight: 4.9) == 2)
        #expect(CameraLayout.rowGap(spareHeight: 5) == 3)
        #expect(CameraLayout.rowGap(spareHeight: 41.33) == 15)
        // 2 + (68 - 2) / 3 = 24, the cap (NopeSpace.l), and never more.
        #expect(CameraLayout.rowGap(spareHeight: 68) == 24)
        #expect(CameraLayout.rowGap(spareHeight: 500) == CameraLayout.maximumRowGap)
        #expect(CameraLayout.maximumRowGap == NopeSpace.l)
    }

    @Test func theLensControlsAlwaysKeepTheTargetGap() {
        for gap in [CGFloat(0), 1, 2, 3, 15, 24] {
            let lift = CameraLayout.lensRowLift(rowGap: gap)
            // The lens row's inset below its controls, the gap and the lift: at least 8 points.
            #expect(CameraLayout.lensRowInset + gap + lift >= NopeSize.targetGap)
            #expect(lift >= 0 && lift <= CameraLayout.minimumRowGap)
        }
        #expect(CameraLayout.lensRowLift(rowGap: 1) == 1)
    }

    @Test func theShutterStaysEightPointsBelowTheStrip() {
        // At its smallest the row is 88 points: 4 points above the contents put the 76-point
        // shutter 8 below the strip and 4 above the row's lower edge.
        #expect(CameraLayout.shutterRowTopPadding(shutterRowHeight: 88) == 4)
        #expect(CameraLayout.shutterRowTopPadding(shutterRowHeight: 89) == 2 * 1.5)
        #expect(CameraLayout.shutterRowTopPadding(shutterRowHeight: 92) == 0)
        #expect(CameraLayout.shutterRowTopPadding(shutterRowHeight: 114) == 0)
        // Never more than the row leaves around the shutter.
        #expect(CameraLayout.shutterRowTopPadding(shutterRowHeight: 78) == 2)
        // From its smallest height (NopeSize.shutterRowMin) up.
        for height in stride(from: CameraLayout.shutterRowHeight, through: 120, by: 0.5) {
            let padding = CameraLayout.shutterRowTopPadding(shutterRowHeight: height)
            let above = padding + (height - padding - NopeSize.shutter) / 2
            #expect(above >= NopeSize.targetGap - 0.001, "row \(height)")
        }
    }

    @Test func theColumnGivesTheShutterRoomWhenTall() {
        #expect(CameraLayout.columnShutterGap(columnHeight: 1032) == NopeSpace.m)
        #expect(CameraLayout.columnShutterGap(columnHeight: 600) == NopeSpace.m)
        #expect(CameraLayout.columnShutterGap(columnHeight: 599) == NopeSpace.xs)
        #expect(CameraLayout.columnShutterGap(columnHeight: 0) == NopeSpace.xs)
    }
}
