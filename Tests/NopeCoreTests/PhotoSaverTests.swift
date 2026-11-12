import Foundation
import NopeCore
import Testing

/// Develops clean files for the plan it is given, or throws.
struct FakeDeveloper: PhotoDeveloping {
    var error: CaptureError?
    /// Whether to wait a moment first, so a test can see the saving state.
    var delay = false
    /// Records the look of every development.
    var looks = LookRecorder()

    func develop(_ raw: PhotoFile, to format: PhotoFormat, look: DevelopedLook, metadata: MetadataPlan)
        async throws(CaptureError) -> PhotoFile
    {
        await looks.record(look)
        if delay { try? await Task.sleep(for: .milliseconds(200)) }
        if let error { throw error }
        let allowlist = metadata.allowlist(for: format, signed: false)
        switch format {
        case .jpeg: return PhotoFile(format: .jpeg, data: CleanFiles.jpeg(for: allowlist))
        default: return PhotoFile(format: format, data: FakeFiles.heif(for: allowlist))
        }
    }
}

/// Records the looks a developer was asked for.
actor LookRecorder {
    private(set) var looks: [DevelopedLook] = []

    func record(_ look: DevelopedLook) {
        looks.append(look)
    }
}

enum FakeFiles {
    /// A clean HEIF: one image item and an EXIF item with the allowed tags.
    static func heif(for allowlist: MetadataAllowlist, extraTopLevel: [[UInt8]] = []) -> Data {
        let tiff = TIFFBuilder.build(CleanFiles.tiff(for: allowlist))
        return HEIFBuilder.build(
            items: [.init(id: 1, type: "hvc1"), .init(id: 2, type: "Exif", data: HEIFBuilder.exifItem(tiff))],
            extraTopLevel: extraTopLevel)
    }
}

/// Signs by adding the format's Content Credentials block, or fails for chosen formats.
struct FakeSigner: PhotoSigning {
    struct Failure: Error {}
    var failing: Set<PhotoFormat> = []
    /// Whether signing also changes the RAW image data (it must never do that).
    var changesRawData = false

    func sign(_ file: PhotoFile) async throws -> PhotoFile {
        if failing.contains(file.format) { throw Failure() }
        var data = [UInt8](file.data)
        switch file.format {
        case .raw:
            let root = CleanFiles.tiff(for: MetadataPlan().allowlist(for: .raw, signed: false))
            root.entries.append((0xCD41, .bytes(Array("c2pa".utf8))))
            if changesRawData { root.entries.removeAll { $0.0 == 0x0111 }; root.entries.append((0x0111, .blobs([[9]]))) }
            data = TIFFBuilder.build(root)
        case .jpeg:
            data.insert(contentsOf: [0xFF, 0xEB, 0, 4, 0x4A, 0x50], at: 2)
        case .heif:
            data += HEIFBuilder.box("uuid", [1, 2])
        }
        return PhotoFile(format: file.format, data: Data(data))
    }
}

/// Reads with the project reader only (ImageIO is tested in NopeDevelop), or throws.
struct BytesReader: MetadataReading {
    var error: CaptureError?
    var imageIOKeys: [ImageIOKey] = []

    func readBack(_ file: PhotoFile) throws(CaptureError) -> MetadataReadBack {
        if let error { throw error }
        return MetadataReadBack(file: MetadataFileReader.read(file.data, format: file.format), imageIOKeys: imageIOKeys)
    }
}

/// Records what is added, or throws.
actor FakeLibrary: PhotoLibrary {
    let error: CaptureError?
    private(set) var added: [[PhotoLibraryAsset]] = []

    init(error: CaptureError? = nil) {
        self.error = error
    }

    func add(_ assets: [PhotoLibraryAsset]) async throws(CaptureError) {
        if let error { throw error }
        added.append(assets)
    }
}

struct PhotoSaverTests {
    static let lens = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")

    /// A captured RAW whose DNG is clean for the settings.
    static func rawPhoto(_ settings: MetadataSettings = MetadataSettings()) -> CapturedPhoto {
        let allowlist = MetadataPlan(settings: settings, appVersion: "0.2.0").allowlist(for: .raw, signed: false)
        return CapturedPhoto(
            data: CleanFiles.dng(for: allowlist), format: .bayerRAW(pixelFormat: "bgg4"), lensID: "wide",
            dimensions: PhotoDimensions(width: 4, height: 3), exposureDuration: nil, iso: nil,
            rawImageData: Data(CleanFiles.rawImageData))
    }

    static func saver(
        developer: FakeDeveloper = FakeDeveloper(), signer: FakeSigner? = nil, reader: BytesReader = BytesReader(),
        library: FakeLibrary
    ) -> PhotoSaver {
        PhotoSaver(developer: developer, signer: signer, reader: reader, library: library, appVersion: "0.2.0")
    }

    @Test func rawPlusHEIFIsSavedAsOnePairedAsset() async throws {
        let library = FakeLibrary()
        var settings = SaveSettings()
        settings.metadata.signsPhotos = false
        let saved = try await Self.saver(library: library).save(Self.rawPhoto(), settings: settings)
        #expect(saved.formats == [.raw, .heif])
        #expect(saved.signature == .unsigned(.turnedOff))
        #expect(!saved.isProcessedFallback)
        #expect(Set(saved.metadata.keys) == [.raw, .heif])
        let assets = await library.added
        #expect(assets.count == 1)
        #expect(assets.first?.count == 1)
        #expect(assets.first?.first?.primary.format == .raw)
        #expect(assets.first?.first?.alternate?.format == .heif)
    }

    @Test func everyFormatAndEveryCustomSwitchSaves() async throws {
        let library = FakeLibrary()
        var settings = SaveSettings()
        settings.setFormat(.jpeg, isSelected: true)
        settings.metadata.setRemovesAllOptionalDetails(false)
        for item in MetadataItem.allCases { settings.metadata.set(item, isOn: true) }
        settings.metadata.ownerName = "A. Person"
        let saved = try await Self.saver(signer: FakeSigner(), library: library).save(
            Self.rawPhoto(settings.metadata), settings: settings)
        #expect(saved.formats == [.raw, .heif, .jpeg])
        #expect(saved.signature == .signed)
        let assets = await library.added.first ?? []
        #expect(assets.map(\.primary.format) == [.raw, .jpeg])
        #expect(assets.first?.alternate?.format == .heif)
    }

    @Test(arguments: DevelopedLook.allCases)
    func theDevelopedLookIsPassedToTheDeveloper(look: DevelopedLook) async throws {
        let developer = FakeDeveloper()
        var settings = SaveSettings()
        settings.setFormat(.jpeg, isSelected: true)
        settings.developedLook = look
        _ = try await Self.saver(developer: developer, library: FakeLibrary()).save(Self.rawPhoto(), settings: settings)
        #expect(await developer.looks.looks == [look, look])
    }

    @Test func noSignerSavesUnsignedAndSaysSo() async throws {
        let saved = try await Self.saver(library: FakeLibrary()).save(Self.rawPhoto(), settings: SaveSettings())
        #expect(saved.signature == .unsigned(.unavailable))
    }

    @Test func aSigningFailureSavesUnsignedAndSaysSo() async throws {
        let saved = try await Self.saver(signer: FakeSigner(failing: [.heif]), library: FakeLibrary()).save(
            Self.rawPhoto(), settings: SaveSettings())
        #expect(saved.signature == .unsigned(.failed))
    }

    @Test func aSignerThatChangesTheRAWDataIsRejected() async {
        let library = FakeLibrary()
        await #expect(throws: CaptureError.metadataNotAllowed) {
            try await Self.saver(signer: FakeSigner(changesRawData: true), library: library).save(
                Self.rawPhoto(), settings: SaveSettings())
        }
        #expect(await library.added.isEmpty)
    }

    @Test func aFileWithATagOffTheAllowlistIsNeverSaved() async {
        let library = FakeLibrary()
        let allowlist = MetadataPlan().allowlist(for: .raw, signed: false)
        let photo = CapturedPhoto(
            data: CleanFiles.dng(for: allowlist, extra: [(.primary, 0xC7FF)]), format: .bayerRAW(pixelFormat: "bgg4"),
            lensID: "wide", dimensions: PhotoDimensions(width: 4, height: 3), exposureDuration: nil, iso: nil,
            rawImageData: Data(CleanFiles.rawImageData))
        await #expect(throws: CaptureError.metadataNotAllowed) {
            try await Self.saver(library: library).save(photo, settings: SaveSettings())
        }
        #expect(await library.added.isEmpty)
    }

    @Test func anUnexpectedImageIOKeyIsNeverSaved() async {
        let library = FakeLibrary()
        let reader = BytesReader(imageIOKeys: [ImageIOKey("{MakerApple}", "3")])
        await #expect(throws: CaptureError.metadataNotAllowed) {
            try await Self.saver(reader: reader, library: library).save(Self.rawPhoto(), settings: SaveSettings())
        }
        #expect(await library.added.isEmpty)
    }

    @Test func readBackAndLibraryErrorsArePassedOn() async {
        await #expect(throws: CaptureError.metadataNotAllowed) {
            try await Self.saver(reader: BytesReader(error: .metadataNotAllowed), library: FakeLibrary()).save(
                Self.rawPhoto(), settings: SaveSettings())
        }
        await #expect(throws: CaptureError.photosAccessDenied) {
            try await Self.saver(library: FakeLibrary(error: .photosAccessDenied)).save(Self.rawPhoto(), settings: SaveSettings())
        }
        await #expect(throws: CaptureError.developmentFailed) {
            try await Self.saver(developer: FakeDeveloper(error: .developmentFailed), library: FakeLibrary()).save(
                Self.rawPhoto(), settings: SaveSettings())
        }
    }

    @Test func rawOnlyAndDevelopedOnlySelections() async throws {
        var settings = SaveSettings()
        settings.setFormat(.heif, isSelected: false)
        #expect(try await Self.saver(library: FakeLibrary()).save(Self.rawPhoto(), settings: settings).formats == [.raw])
        settings.setFormat(.jpeg, isSelected: true)
        settings.setFormat(.raw, isSelected: false)
        let library = FakeLibrary()
        #expect(try await Self.saver(library: library).save(Self.rawPhoto(), settings: settings).formats == [.jpeg])
        #expect(await library.added.first?.first?.alternate == nil)
    }

    @Test(arguments: [ProcessedFallback.heif, .jpeg])
    func processedFallbackSavesItsOwnFile(fallback: ProcessedFallback) async throws {
        let format: PhotoFormat = fallback == .heif ? .heif : .jpeg
        let allowlist = MetadataPlan().allowlist(for: format, signed: false)
        let data = format == .heif ? FakeFiles.heif(for: allowlist) : CleanFiles.jpeg(for: allowlist)
        let photo = CapturedPhoto(
            data: data, format: .processedFallback(fallback), lensID: "tele", dimensions: PhotoDimensions(width: 4, height: 3),
            exposureDuration: nil, iso: nil)
        let saved = try await Self.saver(library: FakeLibrary()).save(photo, settings: SaveSettings())
        #expect(saved.formats == [format])
        #expect(saved.isProcessedFallback)
    }

    @Test func planUsesTheAppVersion() {
        let plan = Self.saver(library: FakeLibrary()).plan(for: MetadataSettings())
        #expect(plan.appVersion == "0.2.0")
        #expect(plan.settings == MetadataSettings())
    }

    @Test func assetsPairRAWWithHEIFFirstThenJPEG() {
        let raw = PhotoFile(format: .raw, data: Data([1]))
        let heif = PhotoFile(format: .heif, data: Data([2]))
        let jpeg = PhotoFile(format: .jpeg, data: Data([3]))
        #expect(PhotoLibraryAsset.assets(for: [raw, jpeg]) == [PhotoLibraryAsset(primary: raw, alternate: jpeg)])
        #expect(PhotoLibraryAsset.assets(for: [raw]) == [PhotoLibraryAsset(primary: raw)])
        #expect(PhotoLibraryAsset.assets(for: [heif, jpeg]) == [PhotoLibraryAsset(primary: heif), PhotoLibraryAsset(primary: jpeg)])
        #expect(
            PhotoLibraryAsset.assets(for: [raw, heif, jpeg])
                == [PhotoLibraryAsset(primary: raw, alternate: heif), PhotoLibraryAsset(primary: jpeg)])
    }
}
