import Foundation
import Testing

@testable import NopeCore

/// Makes a 2 × 1 preview of the file it is given and decodes it to 1 × 1, recording what it was
/// asked for.
final class RecordingPreviewer: PhotoPreviewing, @unchecked Sendable {
    private let lock = NSLock()
    private var formats: [PhotoFormat] = []
    private var sizes: [Int?] = []

    /// The preview every file gets.
    static let preview = PhotoPreview(width: 2, height: 1, data: Data([1, 2, 3]))!
    /// The pixels every decode gives.
    static let pixels = PhotoThumbnail(width: 1, height: 1, rgba: Data([9, 9, 9, 255]))!

    /// The formats it made previews of.
    var requested: [PhotoFormat] { lock.withLock { formats } }
    /// The sizes it decoded to.
    var decodedSizes: [Int?] { lock.withLock { sizes } }

    func preview(of file: PhotoFile) -> PhotoPreview? {
        lock.withLock { formats.append(file.format) }
        return Self.preview
    }

    func decode(_ preview: PhotoPreview, maximumPixelSize: Int?) -> PhotoThumbnail? {
        lock.withLock { sizes.append(maximumPixelSize) }
        return Self.pixels
    }
}

/// This session's photos and their previews, for the Last Photo viewer: what is kept, the
/// limits, when previews are released, and the viewer's hardware shutter rule
/// (docs/design/BUILD-SPEC.md, 3.14; docs/PRIVACY.md, "Last photo and its details").
@MainActor
struct SessionPhotosTests {
    /// A saved-photo record; the format tells records apart.
    static func saved(_ format: PhotoFormat = .heif) -> SavedPhoto {
        SavedPhoto(formats: [format], isProcessedFallback: false, signature: .unsigned(.turnedOff), metadata: [:])
    }

    /// A preview with `bytes` bytes of data.
    static func preview(bytes: Int) -> PhotoPreview? {
        PhotoPreview(width: 4, height: 3, data: Data(repeating: 7, count: bytes))
    }

    nonisolated static let noon = Date(timeIntervalSince1970: 1_800_000_000)
    static let wide = CameraModelTests.wideRAW

    /// A list with small limits for the tests.
    static func list(count: Int = 10, previews: Int = 10, decoder: (any PhotoPreviewing)? = nil) -> SessionPhotos {
        SessionPhotos(decoder: decoder, countLimit: count, previewLimit: previews)
    }

    /// A save pipeline with fakes and a previewer.
    static func saver(previewer: RecordingPreviewer? = RecordingPreviewer()) -> PhotoSaver {
        PhotoSaver(
            developer: FakeDeveloper(), signer: nil, reader: BytesReader(), library: FakeLibrary(), appVersion: "0.2.0",
            previewer: previewer)
    }

    // MARK: - Values

    @Test func theStandardLimits() {
        let list = SessionPhotos(decoder: nil)
        #expect(list.photos.isEmpty)
        #expect(list.newest == nil)
        #expect(list.previewBytes == 0)
        #expect(list.countLimit == 100)
        #expect(list.previewLimit == 20)
        #expect(SessionPhotos.previewMaximumPixelSize == 3072)
        #expect(SessionPhotos.maximumPreviews == 20)
        #expect(SessionPhotos.maximumCount == 100)
    }

    @Test func aPreviewNeedsASizeAndData() {
        #expect(PhotoPreview(width: 0, height: 1, data: Data([1])) == nil)
        #expect(PhotoPreview(width: 1, height: 0, data: Data([1])) == nil)
        #expect(PhotoPreview(width: 1, height: 1, data: Data()) == nil)
        #expect(PhotoPreview(width: 3, height: 4, data: Data([1]))?.longestSide == 4)
    }

    @Test func aRecordComparesItsPreviewWithTheSavedSize() throws {
        let file = PhotoDetails.File(
            format: .heif, byteCount: 10, pixelWidth: 4032, pixelHeight: 3024, bitDepth: 10, colorFilterPattern: nil,
            blackLevels: [], whiteLevels: [], storesLensCorrections: false, processing: .developed(.standard),
            contentCredentials: nil, contents: [])
        let unsized = PhotoDetails.File(
            format: .raw, byteCount: 10, pixelWidth: nil, pixelHeight: 3024, bitDepth: nil, colorFilterPattern: nil,
            blackLevels: [], whiteLevels: [], storesLensCorrections: false, processing: .none, contentCredentials: nil,
            contents: [])
        let details = PhotoDetails(
            files: [unsized, file], exposure: nil, items: [], lockedItems: [], signature: .signed, timings: SaveTimings(),
            rawClipping: nil, distortionCorrection: nil)
        let photo = SavedPhoto(formats: [.raw, .heif], isProcessedFallback: false, signature: .signed, metadata: [:], details: details)
        let small = SessionPhoto(id: 1, photo: photo, lens: Self.wide, takenAt: Self.noon, preview: Self.preview(bytes: 1))
        #expect(small.photoLongestSide == 4032)
        #expect(small.previewIsSmallerThanPhoto)
        let large = SessionPhoto(
            id: 2, photo: photo, lens: nil, takenAt: Self.noon, preview: PhotoPreview(width: 4032, height: 3024, data: Data([1])))
        #expect(!large.previewIsSmallerThanPhoto)
        let none = SessionPhoto(id: 3, photo: photo, lens: nil, takenAt: Self.noon, preview: nil)
        #expect(!none.previewIsSmallerThanPhoto)
        // Without details the saved size isn't known, so no claim is made.
        let unknown = SessionPhoto(id: 4, photo: Self.saved(), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 1))
        #expect(unknown.photoLongestSide == nil)
        #expect(!unknown.previewIsSmallerThanPhoto)
    }

    // MARK: - The list

    @Test func photosAreKeptOldestFirstWithIDsThatAreNeverReused() {
        let list = Self.list(count: 2)
        list.add(Self.saved(.raw), lens: Self.wide, takenAt: Self.noon, preview: Self.preview(bytes: 8))
        list.add(Self.saved(.heif), lens: nil, takenAt: Self.noon.addingTimeInterval(1), preview: nil)
        #expect(list.photos.map(\.id) == [1, 2])
        #expect(list.photos.map(\.photo.formats) == [[.raw], [.heif]])
        #expect(list.photos.first?.lens == Self.wide)
        #expect(list.newest?.takenAt == Self.noon.addingTimeInterval(1))
        #expect(list.previewBytes == 8)
        #expect(list.photo(id: 1)?.photo.formats == [.raw])
        // A third photo drops the oldest record, whole.
        list.add(Self.saved(.jpeg), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 4))
        #expect(list.photos.map(\.id) == [2, 3])
        #expect(list.photo(id: 1) == nil)
        #expect(list.previewBytes == 4)
    }

    @Test func aCountLimitBelowOneKeepsTheNewest() {
        let list = Self.list(count: 0)
        list.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: nil)
        list.add(Self.saved(.jpeg), lens: nil, takenAt: Self.noon, preview: nil)
        #expect(list.photos.map(\.id) == [2])
    }

    @Test func onlyTheNewestPhotosKeepAPreview() {
        let list = Self.list(count: 10, previews: 2)
        list.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 1))
        list.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: nil)
        list.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 1))
        #expect(list.photos.map { $0.preview != nil } == [false, false, true])
        list.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 1))
        #expect(list.photos.map { $0.preview != nil } == [false, false, true, true])
        list.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 1))
        // The records stay; the preview of the photo that fell out of the newest two is released.
        #expect(list.photos.map(\.id) == [1, 2, 3, 4, 5])
        #expect(list.photos.map { $0.preview != nil } == [false, false, false, true, true])
        #expect(list.previewBytes == 2)
    }

    @Test func releasingPreviewsKeepsTheRecords() {
        let list = Self.list()
        // Nothing to release: nothing changes.
        list.releasePreviews()
        list.add(Self.saved(.raw), lens: Self.wide, takenAt: Self.noon, preview: Self.preview(bytes: 8))
        list.add(Self.saved(.heif), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 8))
        let before = list.photos
        list.releasePreviews()
        #expect(list.previewBytes == 0)
        #expect(list.photos.map(\.id) == before.map(\.id))
        #expect(list.photos.map(\.photo) == before.map(\.photo))
        #expect(list.photos.map(\.lens) == before.map(\.lens))
        #expect(list.photos.map(\.takenAt) == before.map(\.takenAt))
        #expect(list.photos.allSatisfy { $0.preview == nil })
    }

    @Test func aListWithoutADecoderMakesNoPreviews() {
        // The Lock Screen camera's pipeline has no previewer (`NopeCaptureExtension`).
        #expect(!SessionPhotos(decoder: nil).makesPreviews)
        #expect(SessionPhotos(decoder: RecordingPreviewer()).makesPreviews)
        #expect(!CameraModel(backend: ScriptedBackend(capabilities: CameraModelTests.oneLens), saver: Self.saver(previewer: nil)).sessionPhotos.makesPreviews)
        #expect(CameraModel(backend: ScriptedBackend(capabilities: CameraModelTests.oneLens), saver: Self.saver()).sessionPhotos.makesPreviews)
    }

    @Test func aPictureIsDecodedOnRequestAndNotKept() async {
        let decoder = RecordingPreviewer()
        let list = Self.list(decoder: decoder)
        list.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 4))
        list.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: nil)
        #expect(await list.picture(of: 1) == RecordingPreviewer.pixels)
        #expect(await list.picture(of: 1, maximumPixelSize: 1200) == RecordingPreviewer.pixels)
        #expect(decoder.decodedSizes == [nil, 1200])
        // No preview, an unknown photo, or no decoder: nothing to decode.
        #expect(await list.picture(of: 2) == nil)
        #expect(await list.picture(of: 9) == nil)
        let noDecoder = Self.list()
        noDecoder.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 4))
        #expect(await noDecoder.picture(of: 1) == nil)
        #expect(decoder.decodedSizes.count == 2)
    }

    // MARK: - The save pipeline

    @Test func thePreviewComesFromTheDevelopedFile() async throws {
        let previewer = RecordingPreviewer()
        let result = try await Self.saver(previewer: previewer).saveWithPreview(
            PhotoSaverTests.rawPhoto(), settings: SaveSettings.rawPlusHEIFSigned)
        #expect(previewer.requested == [.heif])
        #expect(result.preview == RecordingPreviewer.preview)
    }

    @Test func rawOnlyMakesThePreviewFromTheDNG() async throws {
        let previewer = RecordingPreviewer()
        var settings = SaveSettings.rawPlusHEIFSigned
        settings.setFormat(.heif, isSelected: false)
        _ = try await Self.saver(previewer: previewer).saveWithPreview(PhotoSaverTests.rawPhoto(), settings: settings)
        #expect(previewer.requested == [.raw])
    }

    @Test func thePublicSaveMakesNoPreview() async throws {
        let previewer = RecordingPreviewer()
        _ = try await Self.saver(previewer: previewer).save(PhotoSaverTests.rawPhoto(), settings: SaveSettings.rawPlusHEIFSigned)
        #expect(previewer.requested.isEmpty)
    }

    @Test func noPreviewerMeansNoPreview() async throws {
        let result = try await Self.saver(previewer: nil).saveWithPreview(
            PhotoSaverTests.rawPhoto(), settings: SaveSettings.rawPlusHEIFSigned)
        #expect(result.preview == nil)
    }

    // MARK: - The model

    /// A running model whose saves make previews, with a fixed wall clock.
    static func model(_ backend: any CaptureBackend = ScriptedBackend(capabilities: CameraModelTests.oneLens)) async
        -> CameraModel
    {
        let model = CameraModel(backend: backend, saver: saver(), sleep: { _ in })
        model.wallClock = { SessionPhotosTests.noon }
        await model.send(.start)
        return model
    }

    @Test func eachSaveIsKeptWithItsLensTimeAndPreview() async {
        let model = await Self.model()
        #expect(model.sessionPhotos.photos.isEmpty)
        await model.send(.capture)
        await model.send(.capture)
        guard case .saved(let saved) = model.captureStatus else {
            Issue.record("expected a saved photo, got \(model.captureStatus)")
            return
        }
        #expect(model.sessionPhotos.photos.map(\.id) == [1, 2])
        #expect(model.sessionPhotos.newest?.photo == saved)
        #expect(model.sessionPhotos.newest?.lens == Self.wide)
        #expect(model.sessionPhotos.newest?.takenAt == Self.noon)
        #expect(model.sessionPhotos.newest?.preview == RecordingPreviewer.preview)
        // The model's list decodes with the saver's previewer.
        #expect(await model.sessionPhotos.picture(of: 2) == RecordingPreviewer.pixels)
    }

    @Test func aModelWithoutASaverKeepsNothing() async {
        let model = CameraModel(backend: ScriptedBackend(capabilities: CameraModelTests.oneLens), saver: nil)
        await model.send(.start)
        await model.send(.capture)
        #expect(model.captureStatus == .failed(.savingUnavailable))
        #expect(model.sessionPhotos.photos.isEmpty)
        #expect(model.sessionPhotos.decoder == nil)
    }

    @Test func leavingTheForegroundClosesTheViewerAndReleasesThePreviews() async {
        let model = await Self.model()
        await model.send(.capture)
        await model.send(.setViewerOpen(true))
        await model.send(.setInForeground(true))
        #expect(model.isViewerOpen)
        #expect(model.sessionPhotos.newest?.preview != nil)
        await model.send(.setInForeground(false))
        #expect(!model.isViewerOpen)
        #expect(model.sessionPhotos.photos.count == 1)
        #expect(model.sessionPhotos.newest?.preview == nil)
        #expect(model.sessionPhotos.newest?.previewWasReleased == true)
        // A photo saved while in the background (Siri, a series) keeps no preview: it was
        // made and released at once.
        await model.send(.capture)
        #expect(model.sessionPhotos.photos.count == 2)
        #expect(model.sessionPhotos.previewBytes == 0)
        #expect(model.sessionPhotos.newest?.previewWasReleased == true)
        // Back in the foreground, new photos have previews again.
        await model.send(.setInForeground(true))
        await model.send(.capture)
        #expect(model.sessionPhotos.newest?.preview != nil)
        #expect(model.sessionPhotos.newest?.previewWasReleased == false)
    }

    @Test func aPreviewThatWasNeverMadeIsNotCalledReleased() async {
        // No preview was made (here, no previewer), in the foreground or not (third review of
        // 1.0.0, L8): the viewer must not say one was released.
        let model = CameraModel(
            backend: ScriptedBackend(capabilities: CameraModelTests.oneLens), saver: Self.saver(previewer: nil), sleep: { _ in })
        await model.send(.start)
        await model.send(.setInForeground(true))
        await model.send(.capture)
        await model.send(.setInForeground(false))
        await model.send(.capture)
        #expect(model.sessionPhotos.photos.map(\.previewWasReleased) == [false, false])
        // A list release keeps a released record released, and marks a made preview released.
        let list = Self.list()
        list.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 1))
        list.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: nil, previewWasReleased: true)
        list.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: nil)
        list.releasePreviews()
        #expect(list.photos.map(\.previewWasReleased) == [true, true, false])
        let limited = Self.list(count: 10, previews: 1)
        limited.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 1))
        limited.add(Self.saved(), lens: nil, takenAt: Self.noon, preview: Self.preview(bytes: 1))
        #expect(limited.photos.map(\.previewWasReleased) == [true, false])
    }

    @Test func lowMemoryReleasesThePreviews() async {
        let model = await Self.model()
        await model.send(.capture)
        await model.send(.releasePhotoPreviews)
        #expect(model.sessionPhotos.photos.count == 1)
        #expect(model.sessionPhotos.previewBytes == 0)
    }

    @Test func aBlankPictureRetryIsKept() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens, captureErrors: [.blankPicture, nil])
        let model = await Self.model(backend)
        await model.send(.capture)
        #expect(model.sessionPhotos.photos.map(\.lens) == [Self.wide])
    }

    @Test func eachBracketFrameIsKept() async throws {
        let backend = ScriptedManualBackend(lenses: [ManualFixtures.wide])
        let model = await Self.model(backend)
        await model.send(.manual(.setEnabled(true)))
        await model.send(.manual(.setBracket(BracketSettings(frameCount: 3, step: 1))))
        backend.emit(ManualFixtures.reading)
        backend.finishReadings()
        await model.manual.observeReadings()
        await model.send(.capture)
        guard case .savedBracket(let photos) = model.captureStatus else {
            Issue.record("expected a bracket, got \(model.captureStatus)")
            return
        }
        #expect(model.sessionPhotos.photos.map(\.photo) == photos)
        #expect(model.sessionPhotos.photos.allSatisfy { $0.preview != nil && $0.lens == ManualFixtures.wide })
    }

    @Test func eachBurstFrameIsKept() async {
        let hooked = HookedBackend(ScriptedBackend(capabilities: CameraModelTests.oneLens))
        let model = await Self.model(hooked)
        await hooked.setOnCapture { [model] count in
            guard count == 3 else { return }
            await model.send(.drive(.hardwareButton(.released)))
        }
        await model.send(.drive(.setMode(.burst)))
        await model.send(.drive(.hardwareButton(.pressed)))
        guard case .savedBurst(let photos) = model.captureStatus else {
            Issue.record("expected a burst, got \(model.captureStatus)")
            return
        }
        #expect(model.sessionPhotos.photos.map(\.photo) == photos)
        #expect(model.sessionPhotos.photos.map(\.id) == [1, 2, 3])
        #expect(model.sessionPhotos.photos.allSatisfy { $0.lens == Self.wide && $0.takenAt == Self.noon })
    }

    @Test func theComparisonShotsOwnPhotoIsKept() async {
        let backend = ScriptedComparisonBackend(capabilities: ComparisonTests.lenses)
        let model = await Self.model(backend)
        model.comparison.renderer = RecordingRenderer()
        await model.send(.comparison(.setOn(true)))
        await model.send(.capture)
        guard case .saved(let saved) = model.captureStatus else {
            Issue.record("expected a saved photo, got \(model.captureStatus)")
            return
        }
        // Only the app's own photo: the phone-processed one is never saved or kept.
        #expect(model.sessionPhotos.photos.map(\.photo) == [saved])
        #expect(model.sessionPhotos.newest?.preview == RecordingPreviewer.preview)
        #expect(model.sessionPhotos.newest?.lens == ComparisonTests.lenses.lenses.first)
    }

    // MARK: - The hardware shutter while the viewer is open (decision V1)

    @Test func aHardwarePressClosesTheViewerAndTakesNoPhoto() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await Self.model(backend)
        await model.send(.setViewerOpen(true))
        await model.send(.drive(.hardwareButton(.pressed)))
        #expect(!model.isViewerOpen)
        await model.send(.drive(.hardwareButton(.released)))
        #expect(await backend.captureRequests.isEmpty)
        // The next press takes a photo.
        await model.send(.drive(.hardwareButton(.pressed)))
        await model.send(.drive(.hardwareButton(.released)))
        #expect(await backend.captureRequests.count == 1)
    }

    @Test func aReleaseAloneClosesTheViewerAndTakesNoPhoto() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await Self.model(backend)
        await model.send(.setViewerOpen(true))
        await model.send(.drive(.hardwareButton(.released)))
        #expect(!model.isViewerOpen)
        #expect(await backend.captureRequests.isEmpty)
        await model.send(.drive(.hardwareButton(.released)))
        #expect(await backend.captureRequests.count == 1)
    }

    @Test func aBurstPressClosesTheViewerAndStartsNoBurst() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await Self.model(backend)
        await model.send(.drive(.setMode(.burst)))
        await model.send(.setViewerOpen(true))
        await model.send(.drive(.hardwareButton(.pressed)))
        await model.send(.drive(.hardwareButton(.cancelled)))
        #expect(!model.isViewerOpen)
        #expect(await backend.captureRequests.isEmpty)
        #expect(model.drive.burstProgress == nil)
    }

    @Test func otherWaysToTakeAPhotoStillWorkWithTheViewerOpen() async {
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens)
        let model = await Self.model(backend)
        await model.send(.setViewerOpen(true))
        // Siri, Shortcuts and the Apple Watch app send the capture intent.
        await model.send(.capture)
        #expect(await backend.captureRequests.count == 1)
        #expect(model.isViewerOpen)
        #expect(model.canCapture)
        #expect(model.handlesHardwareButtons)
        await model.send(.setViewerOpen(false))
        #expect(!model.isViewerOpen)
    }
}
