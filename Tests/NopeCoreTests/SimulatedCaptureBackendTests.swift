import Foundation
import NopeCore
import Testing

struct SimulatedCaptureBackendTests {
    static let wide = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")

    @Test func requestDefaultsToCurrentPermission() async {
        let backend = SimulatedCaptureBackend(permission: .denied)
        #expect(backend.permissionAfterRequest == .denied)
        #expect(await backend.requestPermission() == .denied)
        #expect(await backend.currentPermission() == .denied)
        #expect(await backend.deviceCapabilities() == .none)
        #expect(backend.capabilities == .none)
        #expect(backend.permission == .denied)
        #expect(backend.startError == nil && backend.captureError == nil)
        #expect(backend.previewSource is SimulatedPreviewSource)
    }

    @Test func startEmitsScriptedEvents() async throws {
        let backend = SimulatedCaptureBackend(permission: .authorized, eventsAfterStart: [.heat(.fair)])
        try await backend.startSession(CaptureRequest(lens: Self.wide))
        backend.emit(.interruptionEnded)
        await backend.stopSession()
        backend.finishEvents()
        var received: [CaptureEvent] = []
        for await event in backend.events { received.append(event) }
        #expect(received == [.heat(.fair), .interruptionEnded])
        #expect(backend.eventsAfterStart == [.heat(.fair)])
    }

    @Test func startCanFail() async {
        let backend = SimulatedCaptureBackend(permission: .authorized, startError: .configurationFailed)
        await #expect(throws: CaptureError.configurationFailed) {
            try await backend.startSession(CaptureRequest(lens: Self.wide))
        }
    }

    @Test func captureReturnsAPlaceholder() async throws {
        let backend = SimulatedCaptureBackend(permission: .authorized)
        let photo = try await backend.capturePhoto(CaptureRequest(lens: Self.wide))
        #expect(photo.data == SimulatedCaptureBackend.placeholderPhotoData)
        #expect(photo.format == .bayerRAW(pixelFormat: "bgg4"))
        #expect(photo.lensID == "wide")
        #expect(photo.dimensions == SimulatedCaptureBackend.placeholderDimensions)
        #expect(photo.iso == 100)
        #expect(photo.rawImageData == SimulatedCaptureBackend.placeholderPhotoData)

        let small = PhotoDimensions(width: 4, height: 3)
        let big = PhotoDimensions(width: 8, height: 6)
        let lens = Lens(id: "t", kind: .telephoto, bayerRAWFormat: nil, photoDimensions: [small, big])
        #expect(try await backend.capturePhoto(CaptureRequest(lens: lens)).dimensions == big)
        #expect(try await backend.capturePhoto(CaptureRequest(lens: lens)).rawImageData == nil)
    }

    @Test func captureCanFail() async {
        let backend = SimulatedCaptureBackend(permission: .authorized, captureError: .captureFailed)
        await #expect(throws: CaptureError.captureFailed) {
            try await backend.capturePhoto(CaptureRequest(lens: Self.wide))
        }
    }

    @Test func manualControlsAreAcceptedAndBracketsReturnOnePhotoPerFrame() async throws {
        let lens = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4", photoDimensions: [PhotoDimensions(width: 8, height: 6)])
        let backend = SimulatedCaptureBackend(permission: .authorized)
        try await backend.applyControls(.automatic)
        await backend.setExposureReadingsEnabled(false)
        await backend.setExposureReadingsEnabled(true)
        backend.finishEvents()
        var readings: [ExposureReading] = []
        for await reading in backend.exposureReadings { readings.append(reading) }
        #expect(readings == [SimulatedCaptureBackend.placeholderReading])

        let frames = [BracketFrame(iso: 100, exposureDuration: 0.01), BracketFrame(iso: 100, exposureDuration: 0.02)]
        let photos = try await backend.captureBracket(CaptureRequest(lens: lens), frames: frames)
        #expect(photos.map(\.exposureDuration) == [0.01, 0.02])
        #expect(photos.allSatisfy { $0.dimensions == PhotoDimensions(width: 8, height: 6) })
        #expect(photos.allSatisfy { $0.rawImageData == SimulatedCaptureBackend.placeholderPhotoData })
        let heif = Lens(id: "tele", kind: .telephoto, bayerRAWFormat: nil)
        let processed = try await backend.captureBracket(CaptureRequest(lens: heif), frames: frames)
        #expect(processed.allSatisfy { $0.rawImageData == nil })
        let placeholder = try await backend.captureBracket(CaptureRequest(lens: Self.wide), frames: frames)
        #expect(placeholder.allSatisfy { $0.dimensions == SimulatedCaptureBackend.placeholderDimensions })

        let failing = SimulatedCaptureBackend(permission: .authorized, captureError: .captureFailed)
        await #expect(throws: CaptureError.captureFailed) {
            try await failing.captureBracket(CaptureRequest(lens: Self.wide), frames: frames)
        }
    }
}
