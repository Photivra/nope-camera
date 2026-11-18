import Foundation

/// A ``CaptureBackend`` that returns fixed answers instead of talking to hardware.
///
/// Use it in tests, SwiftUI previews and UI tests. It never shows a system prompt, has no
/// video, and returns a small placeholder instead of a real photo. As a
/// ``ManualCaptureBackend`` it accepts every control without changing anything, reports its
/// ``reading`` (``placeholderReading`` by default) when readings are turned on, and returns one
/// placeholder per bracket frame. As a ``LightCaptureBackend`` it reports the torch on at the level asked for, or
/// ``TorchStatus/unavailable`` when created with `torchAvailable: false`.
///
/// ```swift
/// let backend = SimulatedCaptureBackend(
///     permission: .notDetermined,
///     permissionAfterRequest: .authorized,
///     capabilities: DeviceCapabilities(lenses: [Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")])
/// )
/// let model = CameraModel(backend: backend)
/// ```
public struct SimulatedCaptureBackend: ManualCaptureBackend, LightCaptureBackend {
    /// The bytes of every simulated photo. They are not an image file.
    public static let placeholderPhotoData = Data("nope. simulated photo".utf8)

    /// The size reported for a simulated photo when the lens lists no photo sizes: 12 MP, 4:3.
    public static let placeholderDimensions = PhotoDimensions(width: 4032, height: 3024)

    /// The reading sent when readings are turned on: ISO 100, 1/120 s, on target, focus in the
    /// middle, f/1.8 and 5200 K.
    public static let placeholderReading = ExposureReading(
        iso: 100, exposureDuration: 1.0 / 120.0, exposureOffset: 0, lensPosition: 0.5, aperture: 1.8,
        whiteBalance: WhiteBalance(temperature: 5200))

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

    /// Whether the system allows the torch; `false` simulates a device too hot for it.
    public let torchAvailable: Bool

    /// How long ``capturePhoto(_:)`` takes, in seconds: zero, or a camera slow enough for a tap
    /// on the shutter in burst mode to end before a second photo (docs/design/BURST.md, 5.2).
    public let captureSeconds: Double

    /// The error ``captureComparison(_:)`` throws, or `nil` to succeed.
    public let comparisonError: CaptureError?

    /// The event stream. It carries ``eventsAfterStart`` and anything sent with ``emit(_:)``.
    public let events: AsyncStream<CaptureEvent>

    /// How far short of a focus position the simulated lens stops, on the 0 to 1 scale
    /// (``setFocus(lensPosition:)``): 0 reaches every position, so tests can also cover a lens
    /// whose reported focus differs from the plan.
    public let focusShortfall: Double

    /// A ``SimulatedPreviewSource``: there is no video.
    public let previewSource: (any CameraPreviewSource)?

    /// Feeds ``events``.
    private let continuation: AsyncStream<CaptureEvent>.Continuation

    /// The readings stream: ``reading``, ``readingCount`` times, each time readings are turned
    /// on.
    public let exposureReadings: AsyncStream<ExposureReading>

    /// The reading sent when readings are turned on.
    public let reading: ExposureReading

    /// How many times ``reading`` is sent when readings are turned on.
    public let readingCount: Int

    /// Feeds ``exposureReadings``.
    private let readingsContinuation: AsyncStream<ExposureReading>.Continuation

    /// The live analyses: ``placeholderAnalysis(for:)`` each time analysis is asked for.
    public let frameAnalyses: AsyncStream<FrameAnalysis>

    /// Feeds ``frameAnalyses``.
    let analysesContinuation: AsyncStream<FrameAnalysis>.Continuation

    /// The live readout's values: ``placeholderStats`` each time they are turned on.
    public let statsReadings: AsyncStream<CameraStatsReading>

    /// Feeds ``statsReadings``.
    let statsContinuation: AsyncStream<CameraStatsReading>.Continuation

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
    ///   - reading: The reading to report, for example a dim scene. Defaults to
    ///     ``placeholderReading``.
    ///   - readingCount: How many times to report it when readings turn on, for example enough
    ///     for the close-up suggestion. Defaults to 1.
    ///   - torchAvailable: Whether the system allows the torch. Defaults to `true`.
    ///   - comparisonError: The error taking the comparison shot's second photo throws, or
    ///     `nil` to succeed.
    ///   - captureSeconds: How long taking a photo takes, in seconds. Defaults to 0.
    ///   - focusShortfall: How far short of each focus position the simulated lens stops, from 0;
    ///     0 by default.
    public init(
        permission: CameraPermission,
        permissionAfterRequest: CameraPermission? = nil,
        capabilities: DeviceCapabilities = .none,
        startError: CaptureError? = nil,
        captureError: CaptureError? = nil,
        eventsAfterStart: [CaptureEvent] = [],
        reading: ExposureReading = placeholderReading,
        readingCount: Int = 1,
        torchAvailable: Bool = true,
        comparisonError: CaptureError? = nil,
        captureSeconds: Double = 0,
        focusShortfall: Double = 0
    ) {
        self.focusShortfall = focusShortfall
        self.comparisonError = comparisonError
        self.captureSeconds = captureSeconds
        self.reading = reading
        self.readingCount = readingCount
        self.permission = permission
        self.permissionAfterRequest = permissionAfterRequest ?? permission
        self.capabilities = capabilities
        self.startError = startError
        self.captureError = captureError
        self.eventsAfterStart = eventsAfterStart
        self.torchAvailable = torchAvailable
        (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        (exposureReadings, readingsContinuation) = AsyncStream.makeStream(of: ExposureReading.self)
        (frameAnalyses, analysesContinuation) = AsyncStream.makeStream(of: FrameAnalysis.self)
        (statsReadings, statsContinuation) = AsyncStream.makeStream(of: CameraStatsReading.self)
        previewSource = SimulatedPreviewSource()
    }

    /// Sends an event to ``events``, as if the system reported it.
    ///
    /// - Parameter event: The event to send.
    public func emit(_ event: CaptureEvent) {
        continuation.yield(event)
    }

    /// Ends ``events`` and ``exposureReadings``, so ``CameraModel/observeEvents()`` and
    /// ``ManualControlsModel/observeReadings()`` return once they have applied everything sent
    /// so far. Also ends ``frameAnalyses`` and ``statsReadings``.
    public func finishEvents() {
        continuation.finish()
        readingsContinuation.finish()
        analysesContinuation.finish()
        statsContinuation.finish()
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

    /// The RAW clipping of every simulated RAW photo: 12 million photosites, 0.4% clipped
    /// highlights and 0.1% clipped shadows, in the proportions of an RGGB pattern.
    public static let placeholderClipping = RAWClippingResult.measured(
        RAWClipping(channels: [
            RAWClipping.Channel(color: .red, photosites: 3_000_000, highlights: 12_000, shadows: 3_000),
            RAWClipping.Channel(color: .green, photosites: 6_000_000, highlights: 24_000, shadows: 6_000),
            RAWClipping.Channel(color: .blue, photosites: 3_000_000, highlights: 12_000, shadows: 3_000),
        ]))

    /// Returns a placeholder photo for the request, or throws ``captureError``.
    ///
    /// - Parameter request: The lens and format of the photo.
    /// - Returns: ``placeholderPhotoData`` labeled with the request's format and lens, the
    ///   lens's largest photo size (or ``placeholderDimensions``), 1/60 s and ISO 100; for Bayer
    ///   RAW, ``placeholderPhotoData`` is also the reference RAW image data.
    /// - Throws: ``captureError``.
    public func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        if captureSeconds > 0 { try? await Task.sleep(for: .seconds(captureSeconds)) }
        if let captureError { throw captureError }
        return CapturedPhoto(
            data: Self.placeholderPhotoData,
            format: request.format,
            lensID: request.lens.id,
            dimensions: request.lens.photoDimensions.last ?? Self.placeholderDimensions,
            exposureDuration: 1.0 / 60.0,
            iso: 100,
            rawImageData: request.format.isBayerRAW ? Self.placeholderPhotoData : nil,
            rawClipping: request.format.isBayerRAW ? Self.placeholderClipping : nil
        )
    }

    /// Accepts the controls without changing anything.
    ///
    /// - Parameter controls: Ignored.
    public func applyControls(_ controls: DeviceControls) async throws(CaptureError) {}

    /// Sends ``reading``, ``readingCount`` times, when readings are turned on.
    ///
    /// - Parameter enabled: Whether readings are on.
    public func setExposureReadingsEnabled(_ enabled: Bool) async {
        guard enabled else { return }
        for _ in 0..<max(readingCount, 0) { readingsContinuation.yield(reading) }
    }

    /// Returns one placeholder photo per frame, in the order asked for, with the frame's ISO and
    /// duration, or throws ``captureError``. The order is the bracket's order
    /// (``BracketSettings/order``), so the UI tests can check it.
    ///
    /// - Parameters:
    ///   - request: The lens and format of the photos.
    ///   - frames: The frames.
    /// - Returns: One photo per frame.
    /// - Throws: ``captureError``.
    public func captureBracket(_ request: CaptureRequest, frames: [BracketFrame]) async throws(CaptureError)
        -> [CapturedPhoto]
    {
        if let captureError { throw captureError }
        return frames.map { frame in
            CapturedPhoto(
                data: Self.placeholderPhotoData,
                format: request.format,
                lensID: request.lens.id,
                dimensions: request.lens.photoDimensions.last ?? Self.placeholderDimensions,
                exposureDuration: frame.exposureDuration,
                iso: frame.iso,
                rawImageData: request.format.isBayerRAW ? Self.placeholderPhotoData : nil,
                rawClipping: request.format.isBayerRAW ? Self.placeholderClipping : nil
            )
        }
    }

    /// Reports the position asked for, less ``focusShortfall``, within 0 to 1. There is no lens
    /// to move.
    ///
    /// - Parameter lensPosition: The position asked for.
    /// - Returns: The simulated lens's position.
    /// - Throws: ``captureError``.
    public func setFocus(lensPosition: Double) async throws(CaptureError) -> Double {
        if let captureError { throw captureError }
        return (lensPosition - focusShortfall).limited(to: 0...1)
    }

    /// Reports the torch on at `level`, off for `nil`, or ``TorchStatus/unavailable`` when
    /// ``torchAvailable`` is `false`. There is no light to switch.
    ///
    /// - Parameter level: The brightness, or `nil` for off.
    /// - Returns: The simulated light's state.
    public func setTorch(level: Double?) async -> TorchStatus {
        guard let level else { return .off }
        return torchAvailable ? .on(level: level) : .unavailable
    }
}
