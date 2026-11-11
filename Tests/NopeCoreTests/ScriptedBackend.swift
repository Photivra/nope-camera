import Foundation
import NopeCore

/// A test backend that records every call and lets a test script results and events.
actor ScriptedBackend: CaptureBackend {
    nonisolated let events: AsyncStream<CaptureEvent>
    nonisolated let previewSource: (any CameraPreviewSource)? = nil
    private nonisolated let continuation: AsyncStream<CaptureEvent>.Continuation

    let permission: CameraPermission
    let capabilities: DeviceCapabilities
    private var startErrors: [CaptureError?]
    private let captureError: CaptureError?
    private var onStart: (@Sendable () async -> Void)?

    private(set) var startRequests: [CaptureRequest] = []
    private(set) var stopCount = 0

    init(
        permission: CameraPermission = .authorized, capabilities: DeviceCapabilities,
        startErrors: [CaptureError?] = [], captureError: CaptureError? = nil
    ) {
        self.permission = permission
        self.capabilities = capabilities
        self.startErrors = startErrors
        self.captureError = captureError
        (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
    }

    nonisolated func emit(_ events: CaptureEvent...) {
        for event in events { continuation.yield(event) }
    }

    nonisolated func finish() {
        continuation.finish()
    }

    func setOnStart(_ hook: @escaping @Sendable () async -> Void) {
        onStart = hook
    }

    func currentPermission() async -> CameraPermission { permission }
    func requestPermission() async -> CameraPermission { permission }
    func deviceCapabilities() async -> DeviceCapabilities { capabilities }

    func startSession(_ request: CaptureRequest) async throws(CaptureError) {
        startRequests.append(request)
        let hook = onStart
        onStart = nil
        await hook?()
        let error = startErrors.isEmpty ? nil : startErrors.removeFirst()
        if let error { throw error }
    }

    func stopSession() async {
        stopCount += 1
    }

    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        if let captureError { throw captureError }
        return CapturedPhoto(
            data: Data([0x4E]), format: request.format, lensID: request.lens.id,
            dimensions: PhotoDimensions(width: 4, height: 3), exposureDuration: 0.01, iso: 64)
    }
}
