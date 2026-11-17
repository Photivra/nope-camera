import Foundation
import Testing

@testable import NopeCore

// Issue #57, the settings left open after 0.2.0: the Far Focus limit, Face Detection and the
// photo size of each lens.

/// The values: which lens offers which sizes, and which controls the aids add.
struct CaptureSettingValueTests {
    static let small = PhotoDimensions(width: 4032, height: 3024)
    static let deferredOnly = PhotoDimensions(width: 5712, height: 4284)
    static let large = PhotoDimensions(width: 8064, height: 6048)

    /// A lens without Bayer RAW that reports three sizes, the deferred-only 24 MP among them.
    static let fallbackLens = Lens(
        id: "front-no-raw", kind: .front, bayerRAWFormat: nil, photoDimensions: [small, deferredOnly, large])

    @Test func onlyALensWithoutRAWOffersSizesWithoutTheDeferredOne() {
        #expect(Self.fallbackLens.photoSizeChoices == [Self.small, Self.large])
        #expect(Self.fallbackLens.defaultPhotoSize == Self.small)
        let raw = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4", photoDimensions: [Self.small, Self.large])
        #expect(raw.photoSizeChoices.isEmpty)
        #expect(raw.photoSize(for: Self.large) == Self.small)
        let one = Lens(id: "one", kind: .front, bayerRAWFormat: nil, photoDimensions: [Self.small, Self.deferredOnly])
        #expect(one.photoSizeChoices.isEmpty)
        #expect(Lens(id: "none", kind: .front, bayerRAWFormat: nil).defaultPhotoSize == nil)
    }

    @Test func aChoiceTheLensDoesNotOfferFallsBackToTheDefault() {
        #expect(Self.fallbackLens.photoSize(for: Self.large) == Self.large)
        #expect(Self.fallbackLens.photoSize(for: nil) == Self.small)
        #expect(Self.fallbackLens.photoSize(for: Self.deferredOnly) == Self.small)
        #expect(Self.fallbackLens.photoSize(for: PhotoDimensions(width: 1, height: 1)) == Self.small)
        #expect(CaptureRequest(lens: Self.fallbackLens).photoSize == nil)
        #expect(CaptureRequest(lens: Self.fallbackLens, format: .processedFallback(.heif)).photoSize == nil)
    }

    @Test func farLimitNeedsAutofocusSupportAndNeverJoinsTheNearLimit() {
        let far = DeviceControls(settings: .automatic, lens: AutoFixtures.wide, assist: AssistSettings(farFocusLimit: true))
        #expect(far.farFocusLimit && !far.nearFocusLimit)
        #expect(AutoFixtures.aids.supportsFarFocusLimit)
        let both = AssistSettings(nearFocusLimit: true, farFocusLimit: true)
        #expect(!both.farFocusLimit)
        var edited = AssistSettings(nearFocusLimit: true)
        edited.farFocusLimit = true
        let nearWins = DeviceControls(settings: .automatic, lens: AutoFixtures.wide, assist: edited)
        #expect(nearWins.nearFocusLimit && !nearWins.farFocusLimit)
        let direct = DeviceControls(
            exposure: .locked, focus: .automatic, whiteBalance: .automatic, metering: .center, nearFocusLimit: true,
            farFocusLimit: true)
        #expect(!direct.farFocusLimit)
        let manualFocus = DeviceControls(
            settings: ManualSettings(focus: 0.3), lens: AutoFixtures.wide, assist: AssistSettings(farFocusLimit: true))
        #expect(!manualFocus.farFocusLimit)
        #expect(!DeviceControls(settings: .automatic, lens: ManualFixtures.wide, assist: AssistSettings(farFocusLimit: true)).farFocusLimit)
    }

    @Test func faceDetectionIsPassedOnAndOnByDefault() {
        #expect(AssistSettings.none.followsFaces)
        #expect(DeviceControls.automatic.followsFaces)
        let off = DeviceControls(settings: .automatic, lens: AutoFixtures.wide, assist: AssistSettings(followsFaces: false))
        #expect(!off.followsFaces)
        #expect(off != .automatic)
    }
}

/// The aids and the photo size through `CameraModel`.
@MainActor
struct CaptureSettingModelTests {
    func makeModel(lenses: [Lens] = [AutoFixtures.wide], enabled: Bool = false) async -> (CameraModel, ScriptedManualBackend) {
        let backend = ScriptedManualBackend(lenses: lenses)
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.start)
        if enabled { await model.send(.manual(.setEnabled(true))) }
        return (model, backend)
    }

    @Test func nearAndFarLimitsReplaceEachOtherAndAllAutoClearsThem() async {
        let (model, backend) = await makeModel(enabled: true)
        await model.send(.auto(.setFarFocusLimit(true)))
        #expect(model.manual.farFocusLimit)
        #expect(await backend.applied.last?.farFocusLimit == true)
        await model.send(.auto(.setNearFocusLimit(true)))
        #expect(model.manual.nearFocusLimit && !model.manual.farFocusLimit)
        await model.send(.auto(.setFarFocusLimit(true)))
        #expect(!model.manual.nearFocusLimit && model.manual.farFocusLimit)
        // The same value again applies nothing.
        let count = await backend.applied.count
        await model.send(.auto(.setFarFocusLimit(true)))
        #expect(await backend.applied.count == count)
        await model.send(.manual(.allAuto))
        #expect(!model.manual.farFocusLimit)
        await model.send(.auto(.setFarFocusLimit(true)))
        await model.send(.auto(.setFarFocusLimit(false)))
        #expect(!model.manual.farFocusLimit)
        #expect(await backend.applied.last == .automatic)
    }

    @Test func aLensWithoutARangeLimitRefusesFarFocus() async {
        let (model, backend) = await makeModel(lenses: [ManualFixtures.wide], enabled: true)
        let count = await backend.applied.count
        await model.send(.auto(.setFarFocusLimit(true)))
        #expect(!model.manual.farFocusLimit)
        #expect(await backend.applied.count == count)
    }

    @Test func faceDetectionIsAppliedAndKeptByAllAuto() async {
        let (model, backend) = await makeModel()
        #expect(model.manual.followsFaces)
        await model.send(.auto(.setFollowsFaces(false)))
        #expect(!model.manual.followsFaces)
        #expect(await backend.applied.last?.followsFaces == false)
        let count = await backend.applied.count
        await model.send(.auto(.setFollowsFaces(false)))
        #expect(await backend.applied.count == count)
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.allAuto))
        #expect(!model.manual.followsFaces)
        await model.send(.auto(.setFollowsFaces(true)))
        #expect(await backend.applied.last?.followsFaces == true)
    }

    @Test func aNewPhotoSizeRestartsTheCameraOnlyWhenTheSelectedLensChanges() async {
        let lens = CaptureSettingValueTests.fallbackLens
        let other = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4", photoDimensions: [CaptureSettingValueTests.small])
        let (model, backend) = await makeModel(lenses: [lens, other])
        await model.send(.selectLens(lens.id))
        #expect(await backend.startRequests.last?.photoSize == CaptureSettingValueTests.small)
        let starts = await backend.startRequests.count
        await model.send(.setPhotoSizes([lens.id: CaptureSettingValueTests.large]))
        #expect(model.photoSizes == [lens.id: CaptureSettingValueTests.large])
        #expect(await backend.startRequests.count == starts + 1)
        #expect(await backend.startRequests.last?.photoSize == CaptureSettingValueTests.large)
        // Another lens's size, or a size the lens doesn't offer that resolves to the same one,
        // changes nothing on the camera.
        await model.send(.setPhotoSizes([lens.id: CaptureSettingValueTests.large, other.id: CaptureSettingValueTests.large]))
        #expect(await backend.startRequests.count == starts + 1)
        await model.send(.selectLens(other.id))
        #expect(await backend.startRequests.last?.photoSize == CaptureSettingValueTests.small)
    }

    @Test func photoSizesBeforeTheCameraStartsAreUsedWhenItStarts() async {
        let lens = CaptureSettingValueTests.fallbackLens
        let backend = ScriptedManualBackend(lenses: [lens])
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver())
        await model.send(.setPhotoSizes([lens.id: CaptureSettingValueTests.large]))
        #expect(await backend.startRequests.isEmpty)
        await model.send(.start)
        #expect(await backend.startRequests.last?.photoSize == CaptureSettingValueTests.large)
    }
}

/// The settings stored on the device.
@MainActor
struct CaptureSettingStorageTests {
    @Test func defaultsAreTheSystemBehavior() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        // Face Detection is off by default (issue #80).
        #expect(!settings.followsFaces)
        #expect(settings.photoSizes.isEmpty)
        #expect(settings.photoSize(for: CaptureSettingValueTests.fallbackLens) == CaptureSettingValueTests.small)
    }

    @Test func changesAreRememberedAndTheDefaultSizeIsNotStored() {
        let scratch = ScratchDefaults()
        let lens = CaptureSettingValueTests.fallbackLens
        let settings = NopeSettings(defaults: scratch.defaults)
        settings.setFollowsFaces(true)
        settings.setPhotoSize(CaptureSettingValueTests.large, for: lens)
        // A size the lens doesn't offer is ignored.
        settings.setPhotoSize(CaptureSettingValueTests.deferredOnly, for: lens)
        let reloaded = NopeSettings(defaults: scratch.defaults)
        #expect(reloaded.followsFaces)
        #expect(reloaded.photoSizes == [lens.id: CaptureSettingValueTests.large])
        #expect(reloaded.photoSize(for: lens) == CaptureSettingValueTests.large)
        reloaded.setPhotoSize(CaptureSettingValueTests.small, for: lens)
        #expect(NopeSettings(defaults: scratch.defaults).photoSizes.isEmpty)
    }

    @Test func unreadableSizesFallBackToTheDefaults() {
        let scratch = ScratchDefaults()
        scratch.defaults.set(Data("not json".utf8), forKey: NopeSettings.Key.photoSizes)
        #expect(NopeSettings(defaults: scratch.defaults).photoSizes.isEmpty)
    }
}
