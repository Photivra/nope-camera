import Foundation
import Testing

@testable import NopeCore

/// A scripted backend that can also take the comparison shot's second photo (issue #55).
actor ScriptedComparisonBackend: ComparisonCaptureBackend {
    nonisolated let events: AsyncStream<CaptureEvent>
    nonisolated let previewSource: (any CameraPreviewSource)? = nil

    /// The scripted camera for everything but the second photo.
    let camera: ScriptedBackend
    /// The error the second photo throws, or `nil`.
    let comparisonError: CaptureError?
    /// The second photo's metadata.
    let metadata: MetadataInventory
    private(set) var comparisonRequests: [CaptureRequest] = []

    /// The bytes of every phone-processed photo.
    static let phoneData = Data("phone".utf8)

    init(
        capabilities: DeviceCapabilities, captureError: CaptureError? = nil, comparisonError: CaptureError? = nil,
        metadata: MetadataInventory = MetadataInventory()
    ) {
        camera = ScriptedBackend(capabilities: capabilities, captureError: captureError)
        events = camera.events
        self.comparisonError = comparisonError
        self.metadata = metadata
    }

    func currentPermission() async -> CameraPermission { await camera.currentPermission() }
    func requestPermission() async -> CameraPermission { await camera.requestPermission() }
    func deviceCapabilities() async -> DeviceCapabilities { await camera.deviceCapabilities() }
    func startSession(_ request: CaptureRequest) async throws(CaptureError) { try await camera.startSession(request) }
    func stopSession() async { await camera.stopSession() }
    func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
        try await camera.capturePhoto(request)
    }

    func captureComparison(_ request: CaptureRequest) async throws(CaptureError) -> PhoneProcessedPhoto {
        comparisonRequests.append(request)
        if let comparisonError { throw comparisonError }
        return PhoneProcessedPhoto(
            data: Self.phoneData, format: .heif, dimensions: PhotoDimensions(width: 4, height: 3), metadata: metadata)
    }
}

/// Makes a picture of every file, recording which files it was given; optionally slowly.
final class RecordingRenderer: PhotoThumbnailing, @unchecked Sendable {
    /// The files rendered. Guarded by `lock`.
    private var files: [PhotoFile] = []
    private let lock = NSLock()
    /// How long each picture takes, in seconds.
    let seconds: Double

    init(seconds: Double = 0) {
        self.seconds = seconds
    }

    var rendered: [PhotoFile] { lock.withLock { files } }

    func thumbnail(of file: PhotoFile) -> PhotoThumbnail? {
        if seconds > 0 { Thread.sleep(forTimeInterval: seconds) }
        lock.withLock { files.append(file) }
        return PhotoThumbnail(width: 1, height: 1, rgba: Data(file.isProcessedByDevice ? [1, 1, 1, 255] : [2, 2, 2, 255]))
    }
}

/// A clock that moves one second each time it is read.
final class SteppingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    private let start = ContinuousClock.now

    var now: @Sendable () -> ContinuousClock.Instant {
        { [self] in
            lock.withLock {
                reads += 1
                return start + .seconds(reads)
            }
        }
    }
}

@MainActor
struct ComparisonTests {
    static let wide = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")
    static let front = Lens(id: "front", kind: .front, bayerRAWFormat: "bgg4")
    static let lenses = DeviceCapabilities(lenses: [wide, front])

    /// The phone's metadata in the tests: an ID only the phone writes, and an exposure time.
    static let phoneMetadata = MetadataInventory(tags: [
        MetadataInventory.Tag(directory: .exif, tag: 0xA420, text: "ABC123"),
        MetadataInventory.Tag(directory: .exif, tag: 0x829A, values: [0.01]),
    ])

    static func model(
        _ backend: any CaptureBackend, library: FakeLibrary = FakeLibrary(), saver: Bool = true,
        renderer: (any PhotoThumbnailing)? = RecordingRenderer(), now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) async -> CameraModel {
        let model = CameraModel(
            backend: backend, saver: saver ? CameraModelTests.saver(library: library) : nil, now: now)
        model.comparison.renderer = renderer
        await model.send(.start)
        return model
    }

    @Test func isOffAtFirstAndCanBeTurnedOnWithABackendThatTakesTheSecondPhoto() async {
        let model = await Self.model(ScriptedComparisonBackend(capabilities: Self.lenses))
        #expect(model.comparison.isAvailable)
        #expect(!model.comparison.isOn)
        #expect(!model.comparisonAppliesToNextPhoto)
        await model.send(.comparison(.setOn(true)))
        #expect(model.comparison.isOn)
        #expect(model.comparisonAppliesToNextPhoto)
        // An interval series takes its own photos, without the comparison.
        await model.send(.drive(.setMode(.interval)))
        #expect(!model.comparisonAppliesToNextPhoto)
        await model.send(.drive(.setMode(.single)))
        await model.send(.comparison(.setOn(false)))
        #expect(!model.comparison.isOn)
    }

    @Test func staysOffWithABackendThatCantTakeTheSecondPhoto() async {
        let model = await Self.model(ScriptedBackend(capabilities: Self.lenses))
        #expect(!model.comparison.isAvailable)
        await model.send(.comparison(.setOn(true)))
        #expect(!model.comparison.isOn)
        await model.send(.capture)
        #expect(model.comparison.state == .idle)
    }

    @Test func whileOffOnlyNopesPhotoIsTaken() async {
        let backend = ScriptedComparisonBackend(capabilities: Self.lenses)
        let model = await Self.model(backend)
        await model.send(.capture)
        #expect(await backend.comparisonRequests.isEmpty)
        #expect(model.comparison.state == .idle)
        guard case .saved = model.captureStatus else {
            Issue.record("expected a saved photo, got \(model.captureStatus)")
            return
        }
    }

    @Test func takesBothPhotosSavesOnlyNopesAndOpensTheCompareView() async throws {
        let backend = ScriptedComparisonBackend(capabilities: Self.lenses, metadata: Self.phoneMetadata)
        let library = FakeLibrary()
        let renderer = RecordingRenderer()
        let clock = SteppingClock()
        let model = await Self.model(backend, library: library, renderer: renderer, now: clock.now)
        await model.send(.comparison(.setOn(true)))
        await model.send(.capture)

        let nopeRequest = try #require(await backend.camera.captureRequests.first)
        #expect(await backend.comparisonRequests == [nopeRequest])
        guard case .saved(let saved) = model.captureStatus else {
            Issue.record("expected a saved photo, got \(model.captureStatus)")
            return
        }
        // Only nope.'s files reach Photos; the phone's bytes never do.
        let added = await library.added
        #expect(added.count == 1)
        let addedFiles = added.flatMap { $0.flatMap { [$0.primary] + ($0.alternate.map { [$0] } ?? []) } }
        #expect(addedFiles.map(\.format) == [.raw, .heif])
        #expect(!addedFiles.contains { $0.data == ScriptedComparisonBackend.phoneData || $0.isProcessedByDevice })

        guard case .ready(let comparison) = model.comparison.state else {
            Issue.record("expected the compare view, got \(model.comparison.state)")
            return
        }
        // The shown nope. file is the developed HEIF, the same kind of file as the phone's.
        #expect(comparison.nopeFile?.format == .heif)
        #expect(comparison.nopeFile == saved.details?.files.first { $0.format == .heif })
        #expect(comparison.nopeImage?.rgba == Data([2, 2, 2, 255]))
        #expect(comparison.phoneImage?.rgba == Data([1, 1, 1, 255]))
        #expect(renderer.rendered.map(\.format).sorted { $0.rawValue < $1.rawValue } == [.heif, .heif])
        #expect(comparison.phoneFormat == .heif)
        #expect(comparison.phoneDimensions == PhotoDimensions(width: 4, height: 3))
        #expect(comparison.metadata == MetadataComparison(phone: Self.phoneMetadata, nope: saved.metadata[.heif] ?? MetadataInventory()))
        #expect(comparison.metadata.entries(.onlyInPhoneVersion).contains { $0.name == "ImageUniqueID" })
        // The clock is read for nope.'s start, its capture time, then the second photo's start.
        #expect(comparison.secondPhotoDelay == .seconds(2))
        #expect(!comparison.mirrorsPhoneImage)

        // While the view is open, no photo can be taken and the hardware buttons are the system's.
        #expect(model.comparison.isPresented)
        #expect(!model.canCapture)
        #expect(!model.handlesHardwareButtons)
        await model.send(.capture)
        #expect(await backend.camera.captureRequests.count == 1)

        await model.send(.comparison(.close))
        #expect(model.comparison.state == .idle)
        #expect(model.canCapture)
        #expect(model.handlesHardwareButtons)
    }

    @Test func aMirroredFrontPhotoMirrorsThePhonesPicture() async {
        let backend = ScriptedComparisonBackend(capabilities: Self.lenses)
        let model = await Self.model(backend)
        model.saveSettings.mirrorsFrontCamera = true
        await model.send(.selectLens("front"))
        await model.send(.comparison(.setOn(true)))
        await model.send(.capture)
        guard case .ready(let comparison) = model.comparison.state else {
            Issue.record("expected the compare view, got \(model.comparison.state)")
            return
        }
        #expect(comparison.mirrorsPhoneImage)
    }

    @Test func withoutARendererItIsntOffered() async {
        // As in the Lock Screen capture extension, which sets no renderer.
        let model = await Self.model(ScriptedComparisonBackend(capabilities: Self.lenses), renderer: nil)
        #expect(!model.comparison.isAvailable)
        await model.send(.comparison(.setOn(true)))
        #expect(!model.comparison.isOn)
    }

    @Test func whenTheSecondPhotoFailsNopesPhotoIsStillSaved() async {
        let backend = ScriptedComparisonBackend(capabilities: Self.lenses, comparisonError: .captureFailed)
        let library = FakeLibrary()
        let model = await Self.model(backend, library: library)
        await model.send(.comparison(.setOn(true)))
        await model.send(.capture)
        guard case .saved = model.captureStatus else {
            Issue.record("expected a saved photo, got \(model.captureStatus)")
            return
        }
        #expect(await library.added.count == 1)
        #expect(model.comparison.state == .failed(.captureFailed))
        #expect(model.comparison.isPresented)
        await model.send(.comparison(.close))
        #expect(!model.comparison.isPresented)
    }

    @Test func whenNopesPhotoFailsNoSecondPhotoIsTaken() async {
        let backend = ScriptedComparisonBackend(capabilities: Self.lenses, captureError: .captureFailed)
        let model = await Self.model(backend)
        await model.send(.comparison(.setOn(true)))
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.captureFailed))
        #expect(await backend.comparisonRequests.isEmpty)
        #expect(model.comparison.state == .idle)
    }

    @Test func whenNopesPhotoCantBeSavedThePhonesVersionIsDropped() async {
        let backend = ScriptedComparisonBackend(capabilities: Self.lenses)
        let model = await Self.model(backend, library: FakeLibrary(error: .photosAccessDenied))
        await model.send(.comparison(.setOn(true)))
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.photosAccessDenied))
        #expect(await backend.comparisonRequests.count == 1)
        #expect(model.comparison.state == .idle)
    }

    @Test func withoutASaverNothingIsSavedOrCompared() async {
        let backend = ScriptedComparisonBackend(capabilities: Self.lenses)
        let model = await Self.model(backend, saver: false)
        await model.send(.comparison(.setOn(true)))
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.savingUnavailable))
        #expect(model.comparison.state == .idle)
    }

    @Test func aBurstIsNeverAComparisonShot() async {
        let model = await Self.model(ScriptedComparisonBackend(capabilities: Self.lenses))
        await model.send(.comparison(.setOn(true)))
        await model.send(.drive(.setMode(.burst)))
        #expect(!model.comparisonAppliesToNextPhoto)
    }

    @Test func closingWhilePreparingDropsTheResult() async {
        let model = await Self.model(
            ScriptedComparisonBackend(capabilities: Self.lenses), renderer: RecordingRenderer(seconds: 0.3))
        await model.send(.comparison(.setOn(true)))
        let capture = Task { await model.send(.capture) }
        for _ in 0..<1000 where model.comparison.state != .preparing {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.comparison.state == .preparing)
        await model.send(.comparison(.close))
        await capture.value
        #expect(model.comparison.state == .idle)
    }

    @Test func aRAWOnlyPhotoIsComparedAsItsDNG() async {
        let model = await Self.model(ScriptedComparisonBackend(capabilities: Self.lenses))
        _ = model.saveSettings.setFormat(.heif, isSelected: false)
        await model.send(.comparison(.setOn(true)))
        await model.send(.capture)
        guard case .ready(let comparison) = model.comparison.state else {
            Issue.record("expected the compare view, got \(model.comparison.state)")
            return
        }
        #expect(comparison.nopeFile?.format == .raw)
        #expect(comparison.nopeFile?.processing == PhotoDetails.Processing.none)
    }

    @Test func showsTheDevelopedFileWhenThereIsOneOtherwiseTheRAW() {
        let raw = PhotoFile(format: .raw, data: Data([1]))
        let heif = PhotoFile(format: .heif, data: Data([2]))
        let jpeg = PhotoFile(format: .jpeg, data: Data([3]))
        #expect(ComparisonModel.shownFile(in: [raw, heif, jpeg]) == heif)
        #expect(ComparisonModel.shownFile(in: [raw, jpeg]) == jpeg)
        #expect(ComparisonModel.shownFile(in: [raw]) == raw)
        #expect(ComparisonModel.shownFile(in: []) == nil)
    }

    @Test func rendersNothingWithoutAFile() async {
        #expect(await ComparisonModel.render(nil, with: RecordingRenderer()) == nil)
        #expect(await ComparisonModel.render(PhotoFile(format: .heif, data: Data()), with: nil) == nil)
    }

    @Test func comparesAnEmptyInventoryWithoutAFile() {
        let saved = SavedPhoto(formats: [], isProcessedFallback: false, signature: .signed, metadata: [:])
        #expect(ComparisonModel.inventory(of: nil, in: saved) == MetadataInventory())
        #expect(ComparisonModel.inventory(of: PhotoFile(format: .heif, data: Data()), in: saved) == MetadataInventory())
    }

    @Test func theSimulatedBackendTakesAPlaceholderSecondPhoto() async throws {
        let backend = SimulatedCaptureBackend(permission: .authorized)
        let photo = try await backend.captureComparison(CaptureRequest(lens: Self.wide))
        #expect(photo.data == SimulatedCaptureBackend.placeholderComparisonData)
        #expect(photo.format == .heif)
        #expect(photo.dimensions == SimulatedCaptureBackend.placeholderDimensions)
        #expect(photo.metadata == SimulatedCaptureBackend.placeholderComparisonMetadata)
        let jpegLens = Lens(id: "jpeg", kind: .wide, bayerRAWFormat: nil, processedFallback: .jpeg)
        #expect(try await backend.captureComparison(CaptureRequest(lens: jpegLens)).format == .jpeg)
        let failing = SimulatedCaptureBackend(permission: .authorized, comparisonError: .notRunning)
        await #expect(throws: CaptureError.notRunning) {
            try await failing.captureComparison(CaptureRequest(lens: Self.wide))
        }
    }

    @Test func phoneProcessedPhotoKeepsItsValues() {
        let photo = PhoneProcessedPhoto(
            data: Data([1]), format: .jpeg, dimensions: PhotoDimensions(width: 2, height: 1), metadata: Self.phoneMetadata)
        #expect(photo.data == Data([1]))
        #expect(photo.format == .jpeg)
        #expect(photo.dimensions == PhotoDimensions(width: 2, height: 1))
        #expect(photo.metadata == Self.phoneMetadata)
    }
}
