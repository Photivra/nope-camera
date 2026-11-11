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

        let small = PhotoDimensions(width: 4, height: 3)
        let big = PhotoDimensions(width: 8, height: 6)
        let lens = Lens(id: "t", kind: .telephoto, bayerRAWFormat: nil, photoDimensions: [small, big])
        #expect(try await backend.capturePhoto(CaptureRequest(lens: lens)).dimensions == big)
    }

    @Test func captureCanFail() async {
        let backend = SimulatedCaptureBackend(permission: .authorized, captureError: .captureFailed)
        await #expect(throws: CaptureError.captureFailed) {
            try await backend.capturePhoto(CaptureRequest(lens: Self.wide))
        }
    }
}
