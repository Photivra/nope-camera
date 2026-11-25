import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// How the lens controls show that the lens can't be changed (issue #96;
/// docs/design/lens-while-busy.md, sections 2 and 4).
struct LensBusyTests {
    @Test func aSeriesDimsAtOnceAndAPhotoOnlyAfterTheDelay() {
        #expect(!LensBusyState.isDrawnDimmed(for: nil, photoDelayPassed: true))
        #expect(!LensBusyState.isDrawnDimmed(for: .takingPhoto, photoDelayPassed: false))
        #expect(LensBusyState.isDrawnDimmed(for: .takingPhoto, photoDelayPassed: true))
        #expect(LensBusyState.isDrawnDimmed(for: .runningSeries, photoDelayPassed: false))
        #expect(LensBusyState.isDrawnDimmed(for: .comparing, photoDelayPassed: false))
        #expect(NopeMotion.busyDimDelay == .milliseconds(500))
    }

    @Test func theControlsAreDisabledWhateverTheReason() {
        #expect(!LensBusyState.free.isDisabled)
        for blocker in [LensChangeBlocker.takingPhoto, .runningSeries, .comparing] {
            #expect(LensBusyState(blocker: blocker, isDrawnDimmed: false).isDisabled)
        }
    }

    @Test func onlyASeriesGivesTheBusyHint() {
        #expect(LensBusyState(blocker: .runningSeries, isDrawnDimmed: true).hint != nil)
        #expect(LensBusyState(blocker: .takingPhoto, isDrawnDimmed: true).hint == nil)
        #expect(LensBusyState(blocker: .comparing, isDrawnDimmed: true).hint == nil)
        #expect(LensBusyState.free.hint == nil)
    }
}
