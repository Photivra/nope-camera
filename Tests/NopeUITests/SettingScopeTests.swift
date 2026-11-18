import Foundation
import NopeCore
import SwiftUI
import Testing

@testable import NopeUI

/// A device status reader that knows neither the storage nor the battery.
private struct NoStatusReader: DeviceStatusReading {
    func availableStorageBytes() -> Int64? { nil }
    func battery() -> BatteryReading? { nil }
}

/// Close-Up, Far Focus and Flash in Q and the status line are shown only where they work
/// (issues #91 and #92, docs/design/SETTING-SCOPE.md, 6: "a control on the camera or in Q: no
/// note. It is shown only where it works"). Hiding one never changes the person's choice: it
/// comes back with the same value.
@MainActor
struct SettingScopeTests {
    /// A wide lens with every manual control, the focus limits, a bracket, the ranges the astro
    /// helper needs, and a flash.
    static let wide = Lens(
        id: "wide", kind: .wide, bayerRAWFormat: "bgg4", isoRange: 50...6400, exposureDurationRange: 0.0001...1,
        aperture: .fixed(1.8), maxBracketedPhotoCount: 5,
        manualControls: ManualCapabilities(
            supportsManualExposure: true, supportsShutterPriority: true, supportsISOPriority: true,
            supportsAperturePriority: false, exposureCompensationRange: -8...8, supportsExposureLock: true,
            supportsAutoFocus: true, supportsFocusLock: true, supportsManualFocus: true, supportsManualWhiteBalance: true,
            meteringModes: [.center], supportsFocusPoint: true, supportsExposurePoint: true, supportsNearFocusLimit: true),
        flashModes: FlashMode.allCases)

    /// A started camera with the wide lens and fresh settings.
    static func context(suite: String) async -> CameraControlContext {
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        // A status reader, which the astro helper needs before it turns on.
        let model = CameraModel(
            backend: SimulatedCaptureBackend(permission: .authorized, capabilities: DeviceCapabilities(lenses: [wide])),
            deviceStatusReader: NoStatusReader())
        await model.send(.start)
        return CameraControlContext(model: model, settings: NopeSettings(defaults: store))
    }

    static func tile(_ id: String, in context: CameraControlContext) -> QuickControlItem? {
        QuickControls.current(context).first { $0.id == id }
    }

    static func pills(_ context: CameraControlContext) -> [String] {
        StatePills.current(context).map(\.id)
    }

    // MARK: - #91

    @Test func closeUpIsHiddenWhileFocusIsSetByHand() async {
        let context = await Self.context(suite: "SettingScopeTests.closeUp")
        let model = context.model
        await model.send(.manual(.setEnabled(true)))
        await model.send(.auto(.setNearFocusLimit(true)))
        #expect(Self.tile("closeUp", in: context)?.isOn == true)
        #expect(Self.pills(context).contains("closeUp"))

        await model.send(.manual(.setValue(.focus, 0.3)))
        #expect(Self.tile("closeUp", in: context) == nil)
        #expect(!Self.pills(context).contains("closeUp"))
        #expect(model.manual.nearFocusLimit, "the choice is kept")

        await model.send(.manual(.setAuto(.focus)))
        #expect(Self.tile("closeUp", in: context)?.isOn == true)
        #expect(Self.tile("closeUp", in: context)?.value != nil)
        #expect(Self.pills(context).contains("closeUp"))
    }

    @Test func farFocusIsHiddenWhileFocusIsSetByHandOrLocked() async {
        let context = await Self.context(suite: "SettingScopeTests.farFocus")
        let model = context.model
        await model.send(.manual(.setEnabled(true)))
        #expect(Self.tile("farFocus", in: context)?.isOn == false)
        await model.send(.auto(.setFarFocusLimit(true)))
        #expect(Self.tile("farFocus", in: context)?.isOn == true)
        #expect(Self.pills(context).contains("farFocus"))

        await model.send(.manual(.setValue(.focus, 0.9)))
        #expect(Self.tile("farFocus", in: context) == nil)
        #expect(Self.tile("closeUp", in: context) == nil)
        #expect(!Self.pills(context).contains("farFocus"))

        await model.send(.manual(.setAuto(.focus)))
        await model.send(.manual(.setFocusLock(true)))
        #expect(Self.tile("farFocus", in: context) == nil)
        #expect(!Self.pills(context).contains("farFocus"))

        await model.send(.manual(.setFocusLock(false)))
        #expect(Self.tile("farFocus", in: context)?.isOn == true)
        #expect(Self.pills(context).contains("farFocus"))
    }

    @Test func closeUpShowsInFullAuto() async {
        let context = await Self.context(suite: "SettingScopeTests.fullAuto")
        #expect(Self.tile("closeUp", in: context)?.isOn == false)
        #expect(Self.tile("farFocus", in: context) == nil)
    }

    // MARK: - #92

    /// Sets the flash as the app does: the stored choice, which the app passes to the model.
    static func setFlash(_ mode: FlashMode, in context: CameraControlContext) async {
        context.settings.setFlashMode(mode)
        await context.model.send(.light(.setFlashMode(mode)))
    }

    @Test func flashIsHiddenInBurst() async {
        let context = await Self.context(suite: "SettingScopeTests.burst")
        await Self.setFlash(.on, in: context)
        #expect(Self.tile("flash", in: context)?.isOn == true)
        #expect(Self.pills(context).contains("flash"))

        await context.model.send(.drive(.setMode(.burst)))
        #expect(Self.tile("flash", in: context) == nil)
        #expect(!Self.pills(context).contains("flash"))
        #expect(context.settings.flashMode == .on, "the choice is kept")

        await context.model.send(.drive(.setMode(.single)))
        #expect(Self.tile("flash", in: context)?.isOn == true)
        #expect(Self.pills(context).contains("flash"))
    }

    @Test func flashAutoIsHiddenInBurstAndShownWithTheTimer() async {
        let context = await Self.context(suite: "SettingScopeTests.auto")
        await Self.setFlash(.auto, in: context)
        await context.model.send(.drive(.setMode(.burst)))
        #expect(!Self.pills(context).contains("flash"))
        await context.model.send(.drive(.setMode(.timer(.threeSeconds))))
        #expect(Self.pills(context).contains("flash"))
        #expect(Self.tile("flash", in: context) != nil)
    }

    @Test func flashIsHiddenWithABracket() async {
        let context = await Self.context(suite: "SettingScopeTests.bracket")
        await Self.setFlash(.on, in: context)
        await context.model.send(.manual(.setEnabled(true)))
        await context.model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1))))
        #expect(Self.tile("flash", in: context) == nil)
        #expect(!Self.pills(context).contains("flash"))
        await context.model.send(.manual(.setBracket(nil)))
        #expect(Self.pills(context).contains("flash"))
    }

    @Test func flashIsHiddenWithAstro() async {
        let context = await Self.context(suite: "SettingScopeTests.astro")
        await Self.setFlash(.on, in: context)
        await context.model.send(.astro(.setOn(true)))
        #expect(context.model.astro.isOn)
        #expect(Self.tile("flash", in: context) == nil)
        #expect(!Self.pills(context).contains("flash"))
    }
}
