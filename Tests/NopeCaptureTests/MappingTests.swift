import AVFoundation
import Foundation
import NopeCore
import Testing

@testable import NopeCapture

struct FourCharacterCodeTests {
    @Test func roundTripsPrintableCodes() throws {
        let code = try #require(FourCharacterCode.code("bgg4"))
        #expect(code == 0x6267_6734)
        #expect(FourCharacterCode.string(code) == "bgg4")
    }

    @Test func unprintableCodesBecomeHex() {
        #expect(FourCharacterCode.string(0) == "0x00000000")
    }

    @Test(arguments: ["bgg", "bgg44", "bg\u{7}4", "bgé"])
    func rejectsInvalidStrings(string: String) {
        #expect(FourCharacterCode.code(string) == nil)
    }
}

struct DeviceMappingTests {
    @Test(arguments: [
        (AVCaptureDevice.DeviceType.builtInWideAngleCamera, CameraDeviceDescription.DeviceType.wideAngle),
        (.builtInUltraWideCamera, .ultraWide),
        (.builtInTelephotoCamera, .telephoto),
        (.builtInTripleCamera, .other),
        (.builtInLiDARDepthCamera, .other),
    ])
    func deviceTypes(type: AVCaptureDevice.DeviceType, expected: CameraDeviceDescription.DeviceType) {
        #expect(CameraDeviceDescription.DeviceType(type) == expected)
    }

    @Test(arguments: [
        (AVCaptureDevice.Position.back, CameraDeviceDescription.Position.back),
        (.front, .front),
        (.unspecified, .unspecified),
    ])
    func positions(position: AVCaptureDevice.Position, expected: CameraDeviceDescription.Position) {
        #expect(CameraDeviceDescription.Position(position) == expected)
    }

    @Test(arguments: [
        (AVCaptureSession.InterruptionReason.videoDeviceNotAvailableInBackground, InterruptionReason.backgrounded),
        (.audioDeviceInUseByAnotherClient, .inUseElsewhere),
        (.videoDeviceInUseByAnotherClient, .inUseElsewhere),
        (.videoDeviceNotAvailableWithMultipleForegroundApps, .multitasking),
        (.videoDeviceNotAvailableDueToSystemPressure, .systemPressure),
    ])
    func interruptionReasons(reason: AVCaptureSession.InterruptionReason, expected: InterruptionReason) {
        #expect(InterruptionReason(reason) == expected)
    }

    @Test func unknownInterruptionReasonsAreOther() {
        #expect(InterruptionReason(nil) == .other)
        // Sensitive content mitigation (iOS 26) and a value from a later iOS.
        #expect(InterruptionReason(AVCaptureSession.InterruptionReason(rawValue: 6)) == .other)
        #expect(InterruptionReason(AVCaptureSession.InterruptionReason(rawValue: 99)) == .other)
    }

    @Test(arguments: [
        (ProcessInfo.ThermalState.nominal, HeatLevel.nominal),
        (.fair, .fair),
        (.serious, .serious),
        (.critical, .critical),
    ])
    func thermalStates(state: ProcessInfo.ThermalState, expected: HeatLevel) {
        #expect(HeatLevel(state) == expected)
    }

    @Test func unknownThermalStateIsSeriousWithoutPausing() throws {
        let future = try #require(ProcessInfo.ThermalState(rawValue: 99))
        #expect(HeatLevel(future) == .serious)
        #expect(!HeatLevel(future).requiresPause)
    }

    @Test func previewSourceHoldsTheSession() {
        let session = AVCaptureSession()
        #expect(CaptureSessionPreviewSource(session: session).session === session)
    }

    @MainActor
    @Test func connectingALayerShowsTheSessionOnce() {
        let session = AVCaptureSession()
        let source = CaptureSessionPreviewSource(session: session)
        let layer = AVCaptureVideoPreviewLayer()
        source.connect(layer)
        #expect(layer.session === session)
        // Connecting the same layer again keeps the session and has no camera to rotate for.
        source.connect(layer)
        #expect(layer.session === session)
        #expect(source.rotation.captureAngle == nil)
    }
}

struct CaptureReadinessTests {
    @Test(arguments: [
        (AVCapturePhotoOutput.CaptureReadiness.ready, CaptureReadiness.ready),
        (.sessionNotRunning, .sessionNotRunning),
        (.notReadyMomentarily, .notReady),
        (.notReadyWaitingForCapture, .notReady),
        (.notReadyWaitingForProcessing, .notReady),
    ])
    func mapsSystemValues(value: AVCapturePhotoOutput.CaptureReadiness, expected: CaptureReadiness) {
        #expect(CaptureReadiness(value) == expected)
    }

    @Test func readyAtOnce() async throws {
        #expect(try await CaptureReadiness.waitUntilReady(timeout: 1, interval: 0.001) { .ready })
    }

    @Test func waitsUntilReady() async throws {
        let reads = Counter()
        let ready = try await CaptureReadiness.waitUntilReady(timeout: 5, interval: 0.001) {
            await reads.next() < 3 ? .notReady : .ready
        }
        #expect(ready)
        #expect(await reads.value == 4)
    }

    @Test func givesUpAfterTheTimeout() async throws {
        #expect(try await !CaptureReadiness.waitUntilReady(timeout: 0.01, interval: 0.002) { .notReady })
    }

    @Test func stopsWhenTheSessionIsntRunning() async {
        await #expect(throws: CaptureError.notRunning) {
            try await CaptureReadiness.waitUntilReady(timeout: 1, interval: 0.001) { .sessionNotRunning }
        }
    }
}

/// Counts calls across concurrency domains.
actor Counter {
    private(set) var value = 0

    /// Returns the count before this call, then increments it.
    func next() -> Int {
        defer { value += 1 }
        return value
    }
}
