import Foundation
import SwiftUI
import Testing

@testable import NopeUI

/// The launch mark drawn in the app's first frames (docs/design/LAUNCH-SCREEN.md, 5 and 6.3) has
/// the launch image's geometry and colors.
struct StartIndicatorTests {
    /// The mark's square: ``NopeSize/startMark``, 96 points.
    static let square = CGRect(x: 0, y: 0, width: NopeSize.startMark, height: NopeSize.startMark)

    @Test func theMarkIsNinetySixPointsWithTheIconsColors() {
        #expect(NopeSize.startMark == 96)
        #expect(DesignTokensTests.hex(NopeColor.launchBackground) == "#000000FF")
        #expect(DesignTokensTests.hex(NopeColor.mark) == "#EDEDEEFF")
        #expect(DesignTokensTests.hex(NopeColor.markPeriod) == "#40C8E0FF")
    }

    @Test func theFrameIsSeventyEightByFiftyFourAndSitsThreePointsHigh() {
        // On the 1024-unit grid the frame runs from 96 to 928 across and 192 to 768 down: at 96
        // points, 78 × 54 points with its center 3 points above the square's center.
        let frame = StartMarkShape(part: .frame).path(in: Self.square).boundingRect
        #expect(abs(frame.width - 78) < 0.001)
        #expect(abs(frame.height - 54) < 0.001)
        #expect(abs(frame.midX - 48) < 0.001)
        #expect(abs(frame.midY - 45) < 0.001)
    }

    @Test func theLetterAndThePeriodSitInsideTheFrame() {
        let letter = StartMarkShape(part: .letter).path(in: Self.square).boundingRect
        // n.svg: 352 to 688 across, 288 to 640 down; the arch's top is 456 - 168 = 288.
        #expect(abs(letter.minX - 352 * 96 / 1024) < 0.01)
        #expect(abs(letter.maxX - 688 * 96 / 1024) < 0.01)
        #expect(abs(letter.minY - 288 * 96 / 1024) < 0.01)
        #expect(abs(letter.maxY - 640 * 96 / 1024) < 0.01)
        // The arch is open underneath: the point between the stems under the arch is empty, the
        // stems and the top of the arch are filled.
        let letterPath = StartMarkShape(part: .letter).path(in: Self.square)
        #expect(!letterPath.contains(CGPoint(x: 520 * 96 / 1024, y: 560 * 96 / 1024)))
        #expect(letterPath.contains(CGPoint(x: 384 * 96 / 1024, y: 560 * 96 / 1024)))
        #expect(letterPath.contains(CGPoint(x: 656 * 96 / 1024, y: 560 * 96 / 1024)))
        #expect(letterPath.contains(CGPoint(x: 520 * 96 / 1024, y: 320 * 96 / 1024)))
        let period = StartMarkShape(part: .period).path(in: Self.square).boundingRect
        // A 9-point circle at (776, 576).
        #expect(abs(period.width - 9) < 0.001)
        #expect(abs(period.midX - 776 * 96 / 1024) < 0.001)
        #expect(abs(period.midY - 576 * 96 / 1024) < 0.001)
    }

    @Test func theWordsStartFortyPointsUnderTheMarksCenter() {
        #expect(StartIndicator.wordsTop == 40)
    }
}
