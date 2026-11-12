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
    private var captureErrors: [CaptureError?]
    private var onStart: (@Sendable () async -> Void)?

    private(set) var startRequests: [CaptureRequest] = []
    private(set) var stopCount = 0
    private(set) var captureRequests: [CaptureRequest] = []

    init(
        permission: CameraPermission = .authorized, capabilities: DeviceCapabilities,
        startErrors: [CaptureError?] = [], captureError: CaptureError? = nil, captureErrors: [CaptureError?] = []
    ) {
        self.permission = permission
        self.capabilities = capabilities
        self.startErrors = startErrors
        self.captureError = captureError
        self.captureErrors = captureErrors
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
        captureRequests.append(request)
        let error = captureErrors.isEmpty ? captureError : captureErrors.removeFirst()
        if let error { throw error }
        // A file that is clean for the request's metadata plan, as the real backend writes it.
        let isRAW = request.format.isBayerRAW
        let allowlist = request.metadata.allowlist(for: isRAW ? .raw : .heif, signed: false)
        return CapturedPhoto(
            data: isRAW ? CleanFiles.dng(for: allowlist) : FakeFiles.heif(for: allowlist), format: request.format,
            lensID: request.lens.id, dimensions: PhotoDimensions(width: 4, height: 3), exposureDuration: 0.01, iso: 64,
            rawImageData: isRAW ? Data(CleanFiles.rawImageData) : nil)
    }
}
