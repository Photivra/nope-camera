import Foundation
import NopeCore

/// A manual-capable test backend: records applied controls, reading switches and brackets, and
/// lets a test script errors and readings.
actor ScriptedManualBackend: ManualCaptureBackend {
    nonisolated let events: AsyncStream<CaptureEvent>
    nonisolated let exposureReadings: AsyncStream<ExposureReading>
    nonisolated let previewSource: (any CameraPreviewSource)? = nil
    private nonisolated let eventContinuation: AsyncStream<CaptureEvent>.Continuation
    private nonisolated let readingContinuation: AsyncStream<ExposureReading>.Continuation

    let capabilities: DeviceCapabilities
    private var applyErrors: [CaptureError?]
    private let bracketError: CaptureError?

    private(set) var startRequests: [CaptureRequest] = []
    private(set) var applied: [DeviceControls] = []
    private(set) var readingSwitches: [Bool] = []
    private(set) var brackets: [[BracketFrame]] = []
    private(set) var captureCount = 0

    init(lenses: [Lens], applyErrors: [CaptureError?] = [], bracketError: CaptureError? = nil) {
        capabilities = DeviceCapabilities(lenses: lenses)
        self.applyErrors = applyErrors
        self.bracketError = bracketError
        (events, eventContinuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        (exposureReadings, readingContinuation) = AsyncStream.makeStream(of: ExposureReading.self)
    }

    nonisolated func emit(_ readings: ExposureReading...) {
        for reading in readings { readingContinuation.yield(reading) }
    }

    nonisolated func finishReadings() {
        readingContinuation.finish()
    }

    func currentPermission() async -> CameraPermission { .authorized }
    func requestPermission() async -> CameraPermission { .authorized }
    func deviceCapabilities() async -> DeviceCapabilities { capabilities }
    func startSession(_ request: CaptureRequest) async throws(CaptureError) { startRequests.append(request) }
    func stopSession() async {}

    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        captureCount += 1
        return Self.photo(for: request, exposureDuration: 0.01, iso: 100)
    }

    /// A photo whose file is clean for the request's metadata plan, as the real backend writes
    /// it (the same files `ScriptedBackend` returns).
    static func photo(for request: CaptureRequest, exposureDuration: Double, iso: Double) -> CapturedPhoto {
        let isRAW = request.format.isBayerRAW
        let allowlist = request.metadata.allowlist(for: isRAW ? .raw : .heif, signed: false)
        return CapturedPhoto(
            data: isRAW ? CleanFiles.dng(for: allowlist) : FakeFiles.heif(for: allowlist), format: request.format,
            lensID: request.lens.id, dimensions: PhotoDimensions(width: 4, height: 3),
            exposureDuration: exposureDuration, iso: iso, rawImageData: isRAW ? Data(CleanFiles.rawImageData) : nil)
    }

    func applyControls(_ controls: DeviceControls) async throws(CaptureError) {
        applied.append(controls)
        let error = applyErrors.isEmpty ? nil : applyErrors.removeFirst()
        if let error { throw error }
    }

    func setExposureReadingsEnabled(_ enabled: Bool) async {
        readingSwitches.append(enabled)
    }

    func captureBracket(_ request: CaptureRequest, frames: [BracketFrame]) async throws(CaptureError)
        -> [CapturedPhoto]
    {
        brackets.append(frames)
        if let bracketError { throw bracketError }
        return frames.map { Self.photo(for: request, exposureDuration: $0.exposureDuration, iso: $0.iso) }
    }
}

/// Lenses and readings shared by the manual control tests.
enum ManualFixtures {
    /// Every manual control, with priority modes (iOS 27).
    static let full = ManualCapabilities(
        supportsManualExposure: true, supportsShutterPriority: true, supportsISOPriority: true,
        supportsAperturePriority: true, exposureCompensationRange: -8...8, supportsExposureLock: true,
        supportsAutoFocus: true, supportsFocusLock: true, supportsManualFocus: true, supportsManualWhiteBalance: true,
        meteringModes: [.center, .spot, .wholeFrame])

    /// Manual exposure without priority modes (before iOS 27).
    static let basic = ManualCapabilities(
        supportsManualExposure: true, supportsShutterPriority: false, supportsISOPriority: false,
        supportsAperturePriority: false, exposureCompensationRange: -8...8, supportsExposureLock: true,
        supportsAutoFocus: true, supportsFocusLock: true, supportsManualFocus: true, supportsManualWhiteBalance: true,
        meteringModes: [.center])

    /// A wide lens with every control and a variable aperture.
    static let wide = Lens(
        id: "wide", kind: .wide, bayerRAWFormat: "bgg4", isoRange: 50...6400, exposureDurationRange: 0.0001...1,
        aperture: ApertureRange(minimumFNumber: 1.5, maximumFNumber: 4, recommendedStops: [1.5, 2, 2.8, 4]),
        maxBracketedPhotoCount: 5, manualControls: full)

    /// A lens with manual exposure but no priority modes, and a fixed aperture.
    static let basicLens = Lens(
        id: "basic", kind: .ultraWide, bayerRAWFormat: "rgg4", isoRange: 20...3200, exposureDurationRange: 0.0001...1,
        aperture: .fixed(2.2), maxBracketedPhotoCount: 3, manualControls: basic)

    /// A lens with no manual controls and no ranges.
    static let bare = Lens(id: "bare", kind: .front, bayerRAWFormat: nil)

    /// A reading: ISO 200, 1/100 s, 0.5 EV over, focus 0.8, f/1.5, 4000 K with tint 10.
    static let reading = ExposureReading(
        iso: 200, exposureDuration: 0.01, exposureOffset: 0.5, lensPosition: 0.8, aperture: 1.5,
        whiteBalance: WhiteBalance(temperature: 4000, tint: 10))
}
