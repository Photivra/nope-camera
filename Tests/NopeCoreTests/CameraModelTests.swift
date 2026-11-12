import Foundation
import NopeCore
import Testing

@MainActor
struct CameraModelTests {
    static let wideRAW = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")
    static let teleHEIF = Lens(id: "tele", kind: .telephoto, bayerRAWFormat: nil, magnification: 5)
    static let oneLens = DeviceCapabilities(lenses: [wideRAW])
    static let twoLenses = DeviceCapabilities(lenses: [wideRAW, teleHEIF])

    /// A save pipeline with fakes: clean developed files, the project reader, and a library
    /// that records what is added.
    static func saver(library: FakeLibrary = FakeLibrary(), developer: FakeDeveloper = FakeDeveloper()) -> PhotoSaver {
        PhotoSaver(developer: developer, signer: nil, reader: BytesReader(), library: library, appVersion: "0.2.0")
    }

    /// A model that is ready and running.
    static func runningModel(_ backend: ScriptedBackend, saver: PhotoSaver? = saver()) async -> CameraModel {
        let model = CameraModel(backend: backend, saver: saver)
        await model.send(.start)
        return model
    }

    @Test func startsInStartingState() {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: .authorized))
        #expect(model.state == .starting)
        #expect(model.sessionStatus == .stopped)
        #expect(model.captureStatus == .idle)
        #expect(model.selectedLens == nil)
        #expect(model.captureFormat == nil)
        #expect(model.capabilities == nil)
        #expect(!model.canCapture)
        #expect(model.previewSource is SimulatedPreviewSource)
    }

    @Test(arguments: [
        (CameraPermission.notDetermined, CameraState.needsPermission),
        (.denied, .permissionDenied),
        (.restricted, .permissionDenied),
    ])
    func startMapsPermissionToState(permission: CameraPermission, expected: CameraState) async {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: permission, capabilities: Self.oneLens))
        await model.send(.start)
        #expect(model.state == expected)
        #expect(model.sessionStatus == .stopped)
    }

    @Test func authorizedWithCameraStartsTheDefaultLens() async {
        let backend = ScriptedBackend(capabilities: Self.twoLenses)
        let model = await Self.runningModel(backend)
        #expect(model.state == .ready(Self.twoLenses))
        #expect(model.capabilities == Self.twoLenses)
        #expect(model.selectedLensID == "wide")
        #expect(model.selectedLens == Self.wideRAW)
        #expect(model.captureFormat == .bayerRAW(pixelFormat: "bgg4"))
        #expect(model.sessionStatus == .running)
        #expect(model.canCapture)
        #expect(model.previewSource == nil)
        #expect(await backend.startRequests == [CaptureRequest(lens: Self.wideRAW)])
    }

    @Test func authorizedWithoutCameraIsUnavailable() async {
        let model = CameraModel(backend: SimulatedCaptureBackend(permission: .authorized))
        await model.send(.start)
        #expect(model.state == .unavailable)
        #expect(model.sessionStatus == .stopped)
    }

    @Test func requestingPermissionUsesTheAnswer() async {
        let backend = SimulatedCaptureBackend(
            permission: .notDetermined, permissionAfterRequest: .authorized, capabilities: Self.oneLens)
        let model = CameraModel(backend: backend)
        await model.send(.start)
        #expect(model.state == .needsPermission)
        await model.send(.requestPermission)
        #expect(model.state == .ready(Self.oneLens))
        #expect(model.sessionStatus == .running)
    }

    @Test func declinedRequestIsDenied() async {
        let backend = SimulatedCaptureBackend(permission: .notDetermined, permissionAfterRequest: .denied)
        let model = CameraModel(backend: backend)
        await model.send(.requestPermission)
        #expect(model.state == .permissionDenied)
    }

    @Test func startFailureIsReported() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens, startErrors: [.configurationFailed])
        let model = await Self.runningModel(backend)
        #expect(model.sessionStatus == .failed(.configurationFailed))
        #expect(!model.canCapture)
    }

    @Test func selectingALensSwitchesTheFormat() async {
        let backend = ScriptedBackend(capabilities: Self.twoLenses)
        let model = await Self.runningModel(backend)
        await model.send(.selectLens("missing"))
        await model.send(.selectLens("wide"))
        #expect(await backend.startRequests.count == 1)
        await model.send(.selectLens("tele"))
        #expect(model.selectedLens == Self.teleHEIF)
        #expect(model.captureFormat == .processedFallback(.heif))
        #expect(model.sessionStatus == .running)
        #expect(await backend.startRequests.last == CaptureRequest(lens: Self.teleHEIF))
    }

    @Test func selectingALensBeforeReadyIsIgnored() async {
        let backend = ScriptedBackend(capabilities: Self.twoLenses)
        let model = CameraModel(backend: backend)
        await model.send(.selectLens("tele"))
        #expect(model.selectedLensID == nil)
        #expect(await backend.startRequests.isEmpty)
    }

    @Test func captureSavesThePhotoAfterTheReadBack() async {
        let library = FakeLibrary()
        let model = await Self.runningModel(ScriptedBackend(capabilities: Self.oneLens), saver: Self.saver(library: library))
        await model.send(.capture)
        guard case .saved(let photo) = model.captureStatus else {
            Issue.record("expected a saved photo, got \(model.captureStatus)")
            return
        }
        #expect(photo.formats == [.raw, .heif])
        #expect(photo.signature == .unsigned(.unavailable))
        #expect(model.canCapture)
        #expect(await library.added.count == 1)
    }

    @Test func captureUsesTheCurrentMetadataSettings() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = await Self.runningModel(backend)
        model.saveSettings.metadata.set(.location, isOn: true)
        await model.send(.capture)
        let request = await backend.captureRequests.first
        #expect(request?.metadata == MetadataPlan(settings: model.saveSettings.metadata, appVersion: "0.2.0"))
        guard case .saved = model.captureStatus else {
            Issue.record("expected a saved photo, got \(model.captureStatus)")
            return
        }
    }

    @Test func withoutASaverNothingIsSaved() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = await Self.runningModel(backend, saver: nil)
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.savingUnavailable))
        #expect(await backend.captureRequests.first?.metadata == MetadataPlan())
    }

    @Test func aSaveFailureIsReported() async {
        let model = await Self.runningModel(
            ScriptedBackend(capabilities: Self.oneLens), saver: Self.saver(library: FakeLibrary(error: .photosAccessDenied)))
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.photosAccessDenied))
        #expect(model.canCapture)
    }

    @Test func theShutterIsDisabledWhileSaving() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = await Self.runningModel(backend, saver: Self.saver(library: FakeLibrary(), developer: FakeDeveloper(delay: true)))
        let capture = Task { await model.send(.capture) }
        while model.captureStatus != .saving { await Task.yield() }
        #expect(!model.canCapture)
        await model.send(.capture)
        #expect(await backend.captureRequests.count == 1)
        await capture.value
    }

    @Test func captureFailureIsReported() async {
        let model = await Self.runningModel(ScriptedBackend(capabilities: Self.oneLens, captureError: .captureFailed))
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.captureFailed))
    }

    @Test func blankPictureRestartsTheCameraOnceAndRetries() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens, captureErrors: [.blankPicture, nil])
        let model = await Self.runningModel(backend)
        await model.send(.capture)
        guard case .saved(let photo) = model.captureStatus else {
            Issue.record("expected a saved photo, got \(model.captureStatus)")
            return
        }
        #expect(photo.formats == [.raw, .heif])
        #expect(model.sessionStatus == .running)
        #expect(await backend.stopCount == 1)
        #expect(await backend.startRequests.count == 2)
        #expect(await backend.captureRequests.count == 2)
    }

    @Test func blankPictureAfterTheRestartMeansNoPicture() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens, captureError: .blankPicture)
        let model = await Self.runningModel(backend)
        await model.send(.capture)
        #expect(model.sessionStatus == .noPicture)
        #expect(model.captureStatus == .failed(.blankPicture))
        #expect(!model.canCapture)
        #expect(await backend.stopCount == 1)
        #expect(await backend.startRequests.count == 2)
        #expect(await backend.captureRequests.count == 2)

        // The shutter is disabled: no further restarts or captures.
        await model.send(.capture)
        #expect(await backend.captureRequests.count == 2)
        #expect(await backend.stopCount == 1)
    }

    @Test func anotherLensTriesAgainAfterNoPicture() async {
        let backend = ScriptedBackend(capabilities: Self.twoLenses, captureErrors: [.blankPicture, .blankPicture])
        let model = await Self.runningModel(backend)
        await model.send(.capture)
        #expect(model.sessionStatus == .noPicture)
        await model.send(.selectLens("tele"))
        #expect(model.sessionStatus == .running)
        await model.send(.capture)
        guard case .saved = model.captureStatus else {
            Issue.record("expected a saved photo, got \(model.captureStatus)")
            return
        }
    }

    @Test func blankPictureWithAFailedRestartReportsTheStartFailure() async {
        let backend = ScriptedBackend(
            capabilities: Self.oneLens, startErrors: [nil, .configurationFailed], captureErrors: [.blankPicture])
        let model = await Self.runningModel(backend)
        await model.send(.capture)
        #expect(model.sessionStatus == .failed(.configurationFailed))
        #expect(model.captureStatus == .failed(.blankPicture))
        #expect(await backend.captureRequests.count == 1)
    }

    @Test func blankPictureThenAnotherErrorReportsThatError() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens, captureErrors: [.blankPicture, .captureFailed])
        let model = await Self.runningModel(backend)
        await model.send(.capture)
        #expect(model.sessionStatus == .running)
        #expect(model.captureStatus == .failed(.captureFailed))
    }

    @Test func captureIsIgnoredWhenNotRunning() async {
        let model = CameraModel(backend: ScriptedBackend(capabilities: Self.oneLens))
        await model.send(.capture)
        #expect(model.captureStatus == .idle)
    }

    @Test func interruptionPausesAndResumes() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = await Self.runningModel(backend)
        backend.emit(.interrupted(.inUseElsewhere))
        backend.finish()
        await model.observeEvents()
        #expect(model.sessionStatus == .interrupted(.inUseElsewhere))
        #expect(!model.canCapture)

        let resumed = ScriptedBackend(capabilities: Self.oneLens)
        let resumedModel = await Self.runningModel(resumed)
        resumed.emit(.interrupted(.multitasking), .interruptionEnded)
        resumed.finish()
        await resumedModel.observeEvents()
        #expect(resumedModel.sessionStatus == .running)
    }

    @Test func interruptionEndedWithoutInterruptionChangesNothing() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens, startErrors: [.configurationFailed])
        let model = await Self.runningModel(backend)
        backend.emit(.interruptionEnded)
        backend.finish()
        await model.observeEvents()
        #expect(model.sessionStatus == .failed(.configurationFailed))
    }

    @Test func criticalHeatPausesUntilTheDeviceCools() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = await Self.runningModel(backend)
        backend.emit(.heat(.critical), .heat(.critical))
        backend.emit(.heat(.serious))
        backend.finish()
        await model.observeEvents()
        #expect(await backend.stopCount == 1)
        #expect(await backend.startRequests.count == 2)
        #expect(model.sessionStatus == .running)
    }

    @Test func heatBelowCriticalWhileRunningChangesNothing() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = await Self.runningModel(backend)
        backend.emit(.heat(.fair))
        backend.finish()
        await model.observeEvents()
        #expect(model.sessionStatus == .running)
        #expect(await backend.startRequests.count == 1)
    }

    @Test func criticalHeatBeforeStartKeepsTheCameraOff() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = CameraModel(backend: backend)
        backend.emit(.heat(.critical))
        backend.finish()
        await model.observeEvents()
        await model.send(.start)
        #expect(model.state == .ready(Self.oneLens))
        #expect(model.sessionStatus == .pausedForHeat)
        #expect(await backend.startRequests.isEmpty)
        #expect(await backend.stopCount == 0)
    }

    @Test func runtimeErrorRestartsTheCamera() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = await Self.runningModel(backend)
        backend.emit(.failed)
        backend.finish()
        await model.observeEvents()
        #expect(await backend.startRequests.count == 2)
        #expect(model.sessionStatus == .running)
    }

    @Test func runtimeErrorBeforeReadyDoesNothing() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = CameraModel(backend: backend)
        backend.emit(.failed)
        backend.finish()
        await model.observeEvents()
        #expect(await backend.startRequests.isEmpty)
        #expect(model.sessionStatus == .stopped)
    }

    @Test func eventDuringStartWins() async {
        let backend = ScriptedBackend(capabilities: Self.oneLens)
        let model = CameraModel(backend: backend)
        backend.emit(.interrupted(.other))
        backend.finish()
        await backend.setOnStart { await model.observeEvents() }
        await model.send(.start)
        #expect(model.sessionStatus == .interrupted(.other))
    }
}
