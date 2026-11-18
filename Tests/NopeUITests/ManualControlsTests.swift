import Foundation
import NopeCore
import SwiftUI
import Testing

@testable import NopeUI

/// The manual readout row's arrangement and the dial's meter rule (docs/design/BUILD-SPEC.md,
/// 3.4).
@MainActor
struct ManualControlsTests {
    /// Six readouts and More, each readout at most `widest` points wide at its ideal size.
    ///
    /// - Parameter widest: The widest readout's ideal width, in points.
    static func ideals(widest: CGFloat) -> [CGSize] {
        [CGSize(width: widest - 8, height: NopeSize.readout)] + Array(repeating: CGSize(width: widest, height: NopeSize.readout), count: 5)
            + [CGSize(width: NopeSize.minTarget, height: NopeSize.readout)]
    }

    /// On a 402-point iPhone the picture's bottom stack offers 386 points: six readouts of the
    /// widest value ("5,200 K" at the default text size, 45.3 points) fit in one row.
    @Test func sixReadoutsFitInOneRowOnA402PointIPhone() {
        let arrangement = ReadoutRowLayout.arrangement(ideals: Self.ideals(widest: 45.3), width: 386, spacing: NopeSpace.xxs)
        #expect(arrangement.isOneRow)
        #expect(arrangement.size == CGSize(width: 386, height: NopeSize.readout))
        // The readouts share what More and the gaps leave.
        #expect(abs(arrangement.cellWidth * 6 + NopeSize.minTarget + NopeSpace.xxs * 6 - 386) < 0.001)
    }

    /// When the readouts don't fit, they take two rows of four equal cells.
    @Test func readoutsTakeTwoRowsWhenTheyDontFit() {
        let arrangement = ReadoutRowLayout.arrangement(ideals: Self.ideals(widest: 60), width: 320, spacing: NopeSpace.xxs)
        #expect(!arrangement.isOneRow)
        #expect(arrangement.size.height == NopeSize.readout * 2 + NopeSpace.xxs)
        #expect(abs(arrangement.cellWidth - (320 - 3 * NopeSpace.xxs) / 4) < 0.001)
    }

    /// A cell is never narrower than the widest readout, even when the row overflows.
    @Test func cellsNeverShrinkBelowTheWidestReadout() {
        let arrangement = ReadoutRowLayout.arrangement(ideals: Self.ideals(widest: 100), width: 300, spacing: NopeSpace.xxs)
        #expect(!arrangement.isOneRow)
        #expect(arrangement.cellWidth >= 100)
        #expect(arrangement.size.width > 300)
    }

    /// Without an offered width the row reports the width one row needs.
    @Test func idealWidthIsOneRow() {
        let arrangement = ReadoutRowLayout.arrangement(ideals: Self.ideals(widest: 40), width: nil, spacing: NopeSpace.xxs)
        #expect(arrangement.isOneRow)
        #expect(arrangement.size.width == (40 + NopeSpace.xxs) * 6 + NopeSize.minTarget + NopeSpace.xxs * 6)
    }

    /// The meter shows beside the value only for the controls that change the exposure.
    @Test func meterOnlyForExposureControls() {
        let withMeter = ManualControl.allCases.filter { ControlDial.showsMeter(for: $0) }
        #expect(withMeter == [.exposureCompensation, .iso, .shutter, .aperture])
    }
}
