import Foundation

/// A ``CaptureBackend`` that returns fixed answers instead of talking to hardware.
///
/// Use it in tests, SwiftUI previews and UI tests. It never shows a system prompt, has no
/// video, and returns a small placeholder instead of a real photo.
///
/// ```swift
/// let backend = SimulatedCaptureBackend(
///     permission: .notDetermined,
///     permissionAfterRequest: .authorized,
///     capabilities: DeviceCapabilities(lenses: [Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")])
/// )
/// let model = CameraModel(backend: backend)
/// ```
public struct SimulatedCaptureBackend: CaptureBackend {
    /// The bytes of every simulated photo. They are not an image file.
    public static let placeholderPhotoData = Data("nope. simulated photo".utf8)

    /// The size reported for a simulated photo when the lens lists no photo sizes: 12 MP, 4:3.
    public static let placeholderDimensions = PhotoDimensions(width: 4032, height: 3024)

    /// The permission reported before any request.
    public let permission: CameraPermission

    /// The permission reported after ``requestPermission()``.
    public let permissionAfterRequest: CameraPermission

    /// The capabilities reported by ``deviceCapabilities()``.
    public let capabilities: DeviceCapabilities

    /// The error ``startSession(_:)`` throws, or `nil` to succeed.
    public let startError: CaptureError?

    /// The error ``capturePhoto(_:)`` throws, or `nil` to succeed.
    public let captureError: CaptureError?

    /// Events emitted each time ``startSession(_:)`` succeeds, for example an interruption.
    public let eventsAfterStart: [CaptureEvent]

    /// The event stream. It carries ``eventsAfterStart`` and anything sent with ``emit(_:)``.
    public let events: AsyncStream<CaptureEvent>

    /// A ``SimulatedPreviewSource``: there is no video.
    public let previewSource: (any CameraPreviewSource)?

    /// Feeds ``events``.
    private let continuation: AsyncStream<CaptureEvent>.Continuation

    /// Creates a simulated backend.
    ///
    /// - Parameters:
    ///   - permission: The permission reported before any request.
    ///   - permissionAfterRequest: The permission reported after a request. Defaults to
    ///     `permission`, as if the person dismissed the prompt without changing anything.
    ///   - capabilities: The capabilities to report. Defaults to ``DeviceCapabilities/none``.
    ///   - startError: The error starting the camera throws, or `nil` to succeed.
    ///   - captureError: The error taking a photo throws, or `nil` to succeed.
    ///   - eventsAfterStart: Events to emit each time the camera starts.
    public init(
        permission: CameraPermission,
        permissionAfterRequest: CameraPermission? = nil,
        capabilities: DeviceCapabilities = .none,
        startError: CaptureError? = nil,
        captureError: CaptureError? = nil,
        eventsAfterStart: [CaptureEvent] = []
    ) {
        self.permission = permission
        self.permissionAfterRequest = permissionAfterRequest ?? permission
        self.capabilities = capabilities
        self.startError = startError
        self.captureError = captureError
        self.eventsAfterStart = eventsAfterStart
        (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        previewSource = SimulatedPreviewSource()
    }

    /// Sends an event to ``events``, as if the system reported it.
    ///
    /// - Parameter event: The event to send.
    public func emit(_ event: CaptureEvent) {
        continuation.yield(event)
    }

    /// Ends ``events``, so ``CameraModel/observeEvents()`` returns once it has applied every
    /// event sent so far.
    public func finishEvents() {
        continuation.finish()
    }

    /// Returns ``permission``.
    public func currentPermission() async -> CameraPermission {
        permission
    }

    /// Returns ``permissionAfterRequest`` without showing a prompt.
    public func requestPermission() async -> CameraPermission {
        permissionAfterRequest
    }

    /// Returns ``capabilities``.
    public func deviceCapabilities() async -> DeviceCapabilities {
        capabilities
    }

    /// Throws ``startError`` if set; otherwise emits ``eventsAfterStart``.
    ///
    /// - Parameter request: Ignored.
    /// - Throws: ``startError``.
    public func startSession(_ request: CaptureRequest) async throws(CaptureError) {
        if let startError { throw startError }
        for event in eventsAfterStart { continuation.yield(event) }
    }

    /// Does nothing: there is no camera to stop.
    public func stopSession() async {}

    /// Returns a placeholder photo for the request, or throws ``captureError``.
    ///
    /// - Parameter request: The lens and format of the photo.
    /// - Returns: ``placeholderPhotoData`` labeled with the request's format and lens, the
    ///   lens's largest photo size (or ``placeholderDimensions``), 1/60 s and ISO 100; for Bayer
    ///   RAW, ``placeholderPhotoData`` is also the reference RAW image data.
    /// - Throws: ``captureError``.
    public func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        if let captureError { throw captureError }
        return CapturedPhoto(
            data: Self.placeholderPhotoData,
            format: request.format,
            lensID: request.lens.id,
            dimensions: request.lens.photoDimensions.last ?? Self.placeholderDimensions,
            exposureDuration: 1.0 / 60.0,
            iso: 100,
            rawImageData: request.format.isBayerRAW ? Self.placeholderPhotoData : nil
        )
    }
}
