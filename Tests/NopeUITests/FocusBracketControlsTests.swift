import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// Which focus bracket card shows, and its words (docs/design/BRACKETING.md, section 5).
@MainActor
struct FocusBracketControlsTests {
    /// A ready model on a simulated lens whose focus can be set, with the focus bracket on.
    func makeModel() async -> CameraModel {
        let controls = ManualCapabilities(
            supportsManualExposure: true, supportsShutterPriority: false, supportsISOPriority: false,
            supportsAperturePriority: false, exposureCompensationRange: -8...8, supportsExposureLock: true,
            supportsAutoFocus: true, supportsFocusLock: true, supportsManualFocus: true, supportsManualWhiteBalance: true,
            meteringModes: [.center])
        let lens = Lens(
            id: "wide", kind: .wide, bayerRAWFormat: "bgg4", isoRange: 50...3200, exposureDurationRange: 0.0001...1,
            aperture: .fixed(1.8), maxBracketedPhotoCount: 3, manualControls: controls)
        let model = CameraModel(
            backend: SimulatedCaptureBackend(permission: .authorized, capabilities: DeviceCapabilities(lenses: [lens])))
        await model.send(.start)
        await model.send(.bracket(.setType(.focus)))
        await model.send(.bracket(.setFocus(FocusBracketSettings(nearest: 0.12, farthest: 0.8, frameCount: 12))))
        await model.send(.bracket(.setOn(true)))
        return model
    }

    @Test func theIdleCardThenTheDial() async {
        let model = await makeModel()
        let settings = model.bracketing.focus
        #expect(BracketCardState.current(model, saved: nil, showsControls: true) == .focusIdle(settings))
        #expect(BracketCardState.current(model, saved: nil, showsControls: false) == nil)
        let ended = BracketCardState.focusEnded(
            FocusBracketResult(end: .limitReached, saved: 12, total: 12, offPlan: 0, focusAfter: .automatic))
        #expect(BracketCardState.current(model, saved: ended, showsControls: true) == ended)
        // An exposure bracket's saved card doesn't show over the focus bracket.
        #expect(BracketCardState.current(model, saved: .saved(count: 3, offsets: [-1, 0, 1]), showsControls: true) == .focusIdle(settings))
        await model.send(.bracket(.beginSettingRange(.nearest)))
        #expect(BracketCardState.current(model, saved: nil, showsControls: true) == .focusRange(FocusRangeEditing(end: .nearest, value: 0.12), value: 0.12))
        #expect(BracketCardState.focusIdle(settings).isFocus)
        #expect(!BracketCardState.focusIdle(settings).isRunning)
        #expect(BracketCardState.focusRunning(FocusBracketProgress(taken: 1, saved: 1, total: 3), positions: []).isRunning)
        #expect(!BracketCardState.idle(.standard, startDelay: nil).isFocus)
    }

    @Test func theSavedCardOfAFocusBracketIsItsEnd() {
        let place = FocusFramePlace(number: 1, plannedPosition: 0.2, reportedPosition: 0.2, positions: [0.2, 0.4, 0.6], order: .nearestFirst)
        let photo = SavedPhoto(
            formats: [.raw], isProcessedFallback: false, signature: .unsigned(.turnedOff), metadata: [:],
            bracket: BracketPlace(focus: place, count: 3))
        let result = FocusBracketResult(end: .stopped, saved: 1, total: 3, offPlan: 0, focusAfter: .stays(0.2))
        #expect(BracketCardState.saved(from: .savedBracket([photo]), focusRun: result) == .focusEnded(result))
        #expect(BracketCardState.saved(from: .savedBracket([photo])) == nil)
    }

    @Test func theWordsNeverNameADistance() {
        let settings = FocusBracketSettings(nearest: 0.12, farthest: 0.8, frameCount: 12)
        #expect(FocusBracketText.summary(settings) == "Focus bracket: 12 frames")
        #expect(FocusBracketText.range(settings) == "Focus 0.12 to 0.80, nearest first")
        #expect(FocusBracketText.range(settings.with(order: .farthestFirst)) == "Focus 0.12 to 0.80, farthest first")
        #expect(FocusBracketText.countdownDetail(settings) == "12 frames, focus 0.12 to 0.80")
        #expect(FocusBracketText.frame(4, of: 12) == "Frame 4 of 12")
        #expect(FocusBracketText.focus(0.31) == "Focus 0.31")
        let stopped = FocusBracketResult(end: .storageFull, saved: 4, total: 12, offPlan: 2, focusAfter: .automatic)
        #expect(FocusBracketText.endTitle(stopped) == "Bracket stopped: 4 of 12 photos saved")
        #expect(FocusBracketText.endDetail(stopped) == "Storage is full.\nFocus is back to Auto\n2 frames were not at their planned focus")
        let finished = FocusBracketResult(end: .limitReached, saved: 12, total: 12, offPlan: 0, focusAfter: .stays(0.8))
        #expect(FocusBracketText.endTitle(finished) == "12 photos saved")
        #expect(FocusBracketText.endDetail(finished) == "Focus stays at 0.80")
        #expect(FocusBracketText.after(.returned(0.5)) == "Focus is back to 0.50")
        #expect(FocusBracketText.reason(.batteryLow) == "The battery is low.")
        #expect(FocusBracketText.reason(.cameraStopped) == "The camera stopped.")
        #expect(FocusBracketText.reason(.stopped) == nil)
        let place = FocusFramePlace(number: 4, plannedPosition: 0.3, reportedPosition: 0.31, positions: [], order: .nearestFirst)
        #expect(FocusBracketText.chip(place, count: 12) == "Focus bracket · frame 4 of 12 · focus 0.31")
        #expect(FocusBracketText.chipSpoken(place, count: 12) == "Focus bracket, frame 4 of 12, focus 0.31.")
        #expect(BracketText.chip(BracketPlace(focus: place, count: 12)) == "Focus bracket · frame 4 of 12 · focus 0.31")
        #expect(FocusBracketText.name(.exposure) == "Exposure")
        #expect(FocusBracketText.name(.focus) == "Focus")
    }
}
