import Foundation
import NopeCore
import Testing

/// A clock that moves 10 milliseconds every time it is read.
final class TickingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now

    /// Returns the current instant, then moves on 10 milliseconds.
    func now() -> ContinuousClock.Instant {
        lock.withLock {
            defer { instant = instant.advanced(by: .milliseconds(10)) }
            return instant
        }
    }
}

/// Makes a 1 × 1 thumbnail of the file it is given, and records which format that was.
final class RecordingThumbnailer: PhotoThumbnailing, @unchecked Sendable {
    private let lock = NSLock()
    private var formats: [PhotoFormat] = []
    /// Whether every thumbnail fails.
    let fails: Bool

    init(fails: Bool = false) {
        self.fails = fails
    }

    /// The formats it was asked for.
    var requested: [PhotoFormat] { lock.withLock { formats } }

    func thumbnail(of file: PhotoFile) -> PhotoThumbnail? {
        lock.withLock { formats.append(file.format) }
        return fails ? nil : PhotoThumbnail(width: 1, height: 1, rgba: Data([1, 2, 3, 255]))
    }
}

/// The thumbnail, details and timings ``PhotoSaver`` adds to each saved photo (issues #36, #53).
struct PhotoSaverDetailsTests {
    static func saver(
        signer: FakeSigner? = nil, reader: BytesReader = BytesReader(), thumbnailer: RecordingThumbnailer?,
        clock: TickingClock = TickingClock()
    ) -> PhotoSaver {
        PhotoSaver(
            developer: FakeDeveloper(), signer: signer, reader: reader, library: FakeLibrary(), appVersion: "0.2.0",
            thumbnailer: thumbnailer, now: clock.now)
    }

    @Test func theThumbnailComesFromTheDevelopedFile() async throws {
        let thumbnailer = RecordingThumbnailer()
        let saved = try await Self.saver(thumbnailer: thumbnailer).save(
            PhotoSaverTests.rawPhoto(), settings: SaveSettings.rawPlusHEIFSigned, captureDuration: .milliseconds(42))
        #expect(thumbnailer.requested == [.heif])
        #expect(saved.thumbnail == PhotoThumbnail(width: 1, height: 1, rgba: Data([1, 2, 3, 255])))
        #expect(saved.details?.timings.capture == .milliseconds(42))
    }

    @Test func rawOnlyMakesTheThumbnailFromTheDNG() async throws {
        let thumbnailer = RecordingThumbnailer(fails: true)
        var settings = SaveSettings.rawPlusHEIFSigned
        settings.setFormat(.heif, isSelected: false)
        let saved = try await Self.saver(thumbnailer: thumbnailer).save(PhotoSaverTests.rawPhoto(), settings: settings)
        #expect(thumbnailer.requested == [.raw])
        #expect(saved.thumbnail == nil)
        // Nothing to develop, so no development time.
        #expect(saved.details?.timings.develop == nil)
    }

    @Test func noThumbnailerMeansNoThumbnail() async throws {
        let saved = try await Self.saver(thumbnailer: nil).save(PhotoSaverTests.rawPhoto(), settings: SaveSettings.rawPlusHEIFSigned)
        #expect(saved.thumbnail == nil)
        #expect(saved.details?.files.map(\.format) == [.raw, .heif])
    }

    /// Each step reads the clock twice, 10 milliseconds apart: RAW + HEIF, signed, so one
    /// development, two signings, four read-backs (unsigned and signed) and one save.
    @Test func eachStepIsTimed() async throws {
        let saved = try await Self.saver(signer: FakeSigner(), thumbnailer: nil).save(
            PhotoSaverTests.rawPhoto(), settings: SaveSettings.rawPlusHEIFSigned)
        let timings = try #require(saved.details?.timings)
        #expect(timings.capture == nil)
        #expect(timings.develop == .milliseconds(10))
        #expect(timings.sign == .milliseconds(20))
        #expect(timings.readBack == .milliseconds(40))
        #expect(timings.save == .milliseconds(10))
        #expect(saved.details?.signature == .signed)
    }

    @Test func signingOffIsNotTimed() async throws {
        var settings = SaveSettings.rawPlusHEIFSigned
        settings.metadata.signsPhotos = false
        let saved = try await Self.saver(signer: FakeSigner(), thumbnailer: nil).save(PhotoSaverTests.rawPhoto(), settings: settings)
        #expect(saved.details?.timings.sign == nil)
        #expect(saved.details?.signature == .unsigned(.turnedOff))
    }

    @Test func theSignersSummaryReachesTheDetails() async throws {
        let summary = ContentCredentialsSummary(
            generatorName: "Photivra Nope Camera", generatorVersion: "0.2.0", actionDescription: "Captured.",
            manifestSHA256: "ab")
        let saved = try await Self.saver(signer: FakeSigner(summary: summary), thumbnailer: nil).save(
            PhotoSaverTests.rawPhoto(), settings: SaveSettings.rawPlusHEIFSigned)
        #expect(saved.details?.files.map(\.contentCredentials) == [summary, summary])
    }
}

/// The model times each capture for the details.
@MainActor
struct CaptureTimingTests {
    @Test(arguments: [[CaptureError?](), [.blankPicture, nil]])
    func theCaptureIsTimed(errors: [CaptureError?]) async {
        let clock = TickingClock()
        let backend = ScriptedBackend(capabilities: CameraModelTests.oneLens, captureErrors: errors)
        let model = CameraModel(backend: backend, saver: CameraModelTests.saver(), clock: NopeClock(now: clock.now))
        await model.send(.start)
        await model.send(.capture)
        guard case .saved(let photo) = model.captureStatus else {
            Issue.record("expected a saved photo, got \(model.captureStatus)")
            return
        }
        #expect(photo.details?.timings.capture == .milliseconds(10))
    }
}

/// What the save passes on to What's in This Photo (`docs/design/BUILD-SPEC.md`, section 6,
/// item 17): the copies' options, the pairing, the Standard File Tags and what the camera
/// reported. (Standard File Tags off is covered from built files in `PhotoDetailsValuesTests`.)
struct PhotoSaverDetailsValuesTests {
    @Test func theSaveSettingsAndTheCaptureReachTheDetails() async throws {
        var settings = SaveSettings.rawPlusHEIFSigned
        var options = DevelopedFileOptions()
        options.colorSpace = .sRGB
        options.heifQuality = .medium
        settings.fileOptions = options
        let photo = PhotoSaverTests.rawPhoto()
        let saved = try await PhotoSaverDetailsTests.saver(thumbnailer: nil).save(photo, settings: settings)
        let details = try #require(saved.details)
        #expect(details.capture == PhotoDetails.CaptureReport(photo))
        #expect(details.inPhotos == PhotoDetails.PhotosPairing(pairedFormat: .heif, separateFormat: nil))
        #expect(details.writesStandardFileTags)
        let heif = try #require(details.files.first { $0.format == .heif })
        #expect(heif.colorSpace == .sRGB && heif.quality == .medium)
        #expect(details.files.first { $0.format == .raw }?.colorSpace == nil)
    }
}
