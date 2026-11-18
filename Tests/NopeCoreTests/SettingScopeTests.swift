import Foundation
import Testing

@testable import NopeCore

/// Where Close-Up, Far Focus and the flash are used (issues #91 and #92,
/// docs/design/SETTING-SCOPE.md, 6 and 7): the state an interface reads to show each control
/// only where it works, and the person's stored choice, which is never changed.
@MainActor
struct SettingScopeTests {
    /// Every manual control, the focus limits, a bracket of up to five frames, the ranges the
    /// astro helper needs, and a flash.
    static let wide = Lens(
        id: "wide", kind: .wide, bayerRAWFormat: "bgg4", isoRange: 50...6400, exposureDurationRange: 0.0001...1,
        aperture: .fixed(1.8), maxBracketedPhotoCount: 5, manualControls: AutoFixtures.aids,
        flashModes: FlashMode.allCases, hasTorch: true)

    /// A started camera with the wide lens and, optionally, others.
    static func running(lenses: [Lens] = [wide]) async -> CameraModel {
        let model = CameraModel(
            backend: SimulatedCaptureBackend(permission: .authorized, capabilities: DeviceCapabilities(lenses: lenses)),
            deviceStatusReader: FakeStatusReader(bytes: nil))
        await model.send(.start)
        return model
    }

    // MARK: - Close-Up and Far Focus (#91)

    @Test func autofocusIsInUseInFullAutoAndWithFocusOnAuto() async {
        let model = await Self.running()
        #expect(model.manual.autoFocusIsInUse)
        await model.send(.manual(.setEnabled(true)))
        #expect(model.manual.autoFocusIsInUse)
    }

    @Test func focusSetByHandStopsAutofocusButKeepsTheLimitsStored() async {
        let model = await Self.running()
        await model.send(.manual(.setEnabled(true)))
        await model.send(.auto(.setNearFocusLimit(true)))
        await model.send(.manual(.setValue(.focus, 0.3)))
        #expect(model.manual.settings.focus != nil)
        #expect(!model.manual.autoFocusIsInUse)
        // The limit is only not used: the camera gets none, and the choice is kept.
        let sent = DeviceControls(settings: model.manual.settings, lens: Self.wide, assist: model.manual.assist)
        #expect(!sent.nearFocusLimit)
        #expect(model.manual.nearFocusLimit)
        await model.send(.manual(.setAuto(.focus)))
        #expect(model.manual.autoFocusIsInUse)
        #expect(model.manual.nearFocusLimit)

        await model.send(.auto(.setFarFocusLimit(true)))
        await model.send(.manual(.setValue(.focus, 0.9)))
        #expect(!model.manual.autoFocusIsInUse)
        #expect(model.manual.farFocusLimit)
    }

    @Test func aFocusLockStopsAutofocus() async {
        let model = await Self.running()
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setFocusLock(true)))
        #expect(model.manual.settings.focusLocked)
        #expect(!model.manual.autoFocusIsInUse)
        await model.send(.manual(.setFocusLock(false)))
        #expect(model.manual.autoFocusIsInUse)
    }

    @Test func noAutofocusWithoutALensOrOnAFixedFocusLens() async {
        let idle = CameraModel(backend: SimulatedCaptureBackend(permission: .authorized))
        #expect(!idle.manual.autoFocusIsInUse)
        let fixed = await Self.running(lenses: [AutoFixtures.fixedFocus])
        #expect(!fixed.manual.autoFocusIsInUse)
    }

    // MARK: - Flash (#92)

    @Test func singlePhotosAndTheTimerUseTheFlash() async {
        let model = await Self.running()
        await model.send(.light(.setFlashMode(.on)))
        #expect(model.shutterUsesFlash)
        #expect(model.flashModeForShutter == .on)
        await model.send(.drive(.setMode(.timer(.threeSeconds))))
        #expect(model.flashModeForShutter == .on)
    }

    @Test func burstNeverUsesTheFlashAndKeepsTheChoice() async {
        let model = await Self.running()
        await model.send(.light(.setFlashMode(.auto)))
        await model.send(.drive(.setMode(.burst)))
        #expect(!model.shutterUsesFlash)
        #expect(model.flashModeForShutter == .off)
        #expect(model.light.flashMode == .auto)
        await model.send(.drive(.setMode(.single)))
        #expect(model.flashModeForShutter == .auto)
    }

    @Test func aBracketNeverUsesTheFlash() async {
        let model = await Self.running()
        await model.send(.light(.setFlashMode(.on)))
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1))))
        #expect(model.manual.bracket != nil)
        #expect(model.flashModeForShutter == .off)
        await model.send(.manual(.setBracket(nil)))
        #expect(model.flashModeForShutter == .on)
    }

    @Test func astroNeverUsesTheFlash() async {
        let model = await Self.running()
        await model.send(.light(.setFlashMode(.on)))
        await model.send(.astro(.setOn(true)))
        #expect(model.astro.isOn)
        #expect(model.flashModeForShutter == .off)
        #expect(model.light.flashMode == .on)
    }

    @Test func theTorchStillTurnsTheFlashOff() async {
        let model = await Self.running()
        await model.send(.light(.setFlashMode(.on)))
        await model.send(.light(.setTorch(true)))
        #expect(model.shutterUsesFlash)
        #expect(model.flashModeForShutter == .off)
    }
}
