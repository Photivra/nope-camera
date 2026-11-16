import Foundation
import Testing

@testable import NopeCore

/// The "What's in this photo" details (issue #53), built from read-back fixtures, and the values
/// the TIFF reader records for them.
struct PhotoDetailsTests {
    typealias Tag = MetadataInventory.Tag

    /// A DNG's read-back: size, bit depth, a 2 × 2 RGGB pattern, levels, an opcode list, the
    /// exposure in its EXIF directory, and the four tags that are empty when their switches are off.
    static let rawInventory = MetadataInventory(tags: [
        Tag(directory: .primary, tag: 0x0100, values: [4032]),
        Tag(directory: .primary, tag: 0x0101, values: [3024]),
        Tag(directory: .primary, tag: 0x0102, values: [16]),
        Tag(directory: .primary, tag: 0x828D, values: [2, 2]),
        Tag(directory: .primary, tag: 0x828E, values: [0, 1, 1, 2]),
        Tag(directory: .primary, tag: 0xC61A, values: [528, 528, 528, 528]),
        Tag(directory: .primary, tag: 0xC61D, values: [4095]),
        Tag(directory: .primary, tag: 0xC741),
        Tag(directory: .primary, tag: 0xC614, text: MetadataPlan.genericUniqueCameraModel),
        Tag(directory: .primary, tag: 0x0132, text: ""),
        Tag(directory: .primary, tag: 0x010F, text: ""),
        Tag(directory: .primary, tag: 0x0110, text: ""),
        Tag(directory: .primary, tag: 0x0131, text: "Photivra Nope Camera 0.2.0"),
        Tag(directory: .primary, tag: 0xCD41),
        Tag(directory: .exif, tag: 0x829A, values: [1.0 / 120]),
        Tag(directory: .exif, tag: 0x8827, values: [125]),
        Tag(directory: .exif, tag: 0x829D, values: [1.78]),
        Tag(directory: .exif, tag: 0x920A, values: [6.86]),
        Tag(directory: .exif, tag: 0x9204, values: [0]),
        Tag(directory: .exif, tag: 0xA403, values: [0]),
        Tag(directory: .primary, tag: 0xC7FF),
    ])

    /// A HEIF's read-back: an EXIF size, one block and one XMP property.
    static let heifInventory = MetadataInventory(
        tags: [Tag(directory: .exif, tag: 0xA002, values: [4000]), Tag(directory: .exif, tag: 0xA003, values: [3000])],
        blocks: ["heif:item:hvc1"],
        xmpProperties: [.init(namespace: MetadataPlan.xmpNamespace, name: "CreatorTool", value: "x")])

    static let summary = ContentCredentialsSummary(
        generatorName: "Photivra Nope Camera", generatorVersion: "0.2.0", actionDescription: "Captured.",
        manifestSHA256: String(repeating: "a", count: 64))

    static func checked(
        _ format: PhotoFormat, _ inventory: MetadataInventory, image: ImageProperties? = nil, byDevice: Bool = false,
        bytes: Int = 10, credentials: ContentCredentialsSummary? = nil
    ) -> PhotoDetails.CheckedFile {
        PhotoDetails.CheckedFile(
            file: PhotoFile(format: format, data: Data(count: bytes), isProcessedByDevice: byDevice, contentCredentials: credentials),
            readBack: MetadataReadBack(
                file: MetadataFileReader.Result(inventory: inventory, rawImageData: nil), imageIOKeys: [], image: image))
    }

    static func build(_ files: [PhotoDetails.CheckedFile], settings: MetadataSettings = MetadataSettings(), look: DevelopedLook = .standard) -> PhotoDetails {
        PhotoDetails.build(
            files: files, plan: MetadataPlan(settings: settings, appVersion: "0.2.0"), look: look, signature: .signed,
            timings: SaveTimings(capture: .milliseconds(30)))
    }

    @Test func rawAndHEIFFilesHoldTheirFacts() {
        let details = Self.build([
            Self.checked(.raw, Self.rawInventory, bytes: 1200, credentials: Self.summary),
            Self.checked(.heif, Self.heifInventory, image: ImageProperties(pixelWidth: 4032, pixelHeight: 3024, depth: 10)),
        ])
        let raw = details.files[0]
        #expect(raw.format == .raw && raw.byteCount == 1200)
        #expect(raw.pixelWidth == 4032 && raw.pixelHeight == 3024 && raw.bitDepth == 16)
        #expect(raw.colorFilterPattern == "RGGB")
        #expect(raw.blackLevels == [528, 528, 528, 528] && raw.whiteLevels == [4095])
        #expect(raw.storesLensCorrections)
        #expect(raw.processing == .none)
        #expect(raw.contentCredentials == Self.summary)
        #expect(raw.contents.contains("ExposureTime") && raw.contents.contains("C2PA manifest"))
        #expect(raw.contents.contains("primary 0xC7FF"))
        let heif = details.files[1]
        #expect(heif.pixelWidth == 4032 && heif.pixelHeight == 3024 && heif.bitDepth == 10)
        #expect(heif.colorFilterPattern == nil && heif.blackLevels.isEmpty && !heif.storesLensCorrections)
        #expect(heif.processing == .developed(.standard))
        #expect(heif.contents == ["PixelXDimension", "PixelYDimension", "heif:item:hvc1", "CreatorTool"])
        #expect(details.signature == .signed && details.timings.capture == .milliseconds(30))
        #expect(
            details.exposure
                == PhotoDetails.Exposure(
                    exposureTime: 1.0 / 120, iso: 125, fNumber: 1.78, focalLength: 6.86, exposureBias: 0,
                    whiteBalance: .automatic))
        #expect(details.lockedItems == LockedMetadataItem.allCases)
    }

    @Test func developedFilesFallBackToTheEXIFSize() {
        let details = Self.build([Self.checked(.jpeg, Self.heifInventory)], look: .flat)
        #expect(details.files[0].pixelWidth == 4000 && details.files[0].pixelHeight == 3000)
        #expect(details.files[0].bitDepth == nil)
        #expect(details.files[0].processing == .developed(.flat))
        #expect(details.exposure == nil)
        #expect(details.lockedItems == [.imageLayout, .orientation, .colorProfile])
    }

    @Test func rawClippingSharesPerColorAndOverall() {
        let clipping = RAWClipping(channels: [
            RAWClipping.Channel(color: .red, photosites: 4, highlights: 1, shadows: 0),
            RAWClipping.Channel(color: .green, photosites: 8, highlights: 0, shadows: 2),
            RAWClipping.Channel(color: .blue, photosites: 4, highlights: 1, shadows: 2),
        ])
        #expect(clipping.photosites == 16)
        #expect(clipping.highlights == 2 && clipping.shadows == 4)
        #expect(clipping.highlightShare == 0.125)
        #expect(clipping.shadowShare == 0.25)
        #expect(clipping.channels[0].highlightShare == 0.25)
        #expect(clipping.channels[1].shadowShare == 0.25)
        // Nothing counted reads as no clipping, not as a division by zero.
        let empty = RAWClipping(channels: [RAWClipping.Channel(color: .red, photosites: 0, highlights: 0, shadows: 0)])
        #expect(empty.highlightShare == 0 && empty.shadowShare == 0)
        #expect(empty.channels[0].highlightShare == 0)
        #expect(RAWClipping.margin == 0.005)
        #expect(RAWClippingFailure.allCases.count == 5)
    }

    @Test func detailsKeepTheRAWClipping() {
        let measured = PhotoDetails.build(
            files: [Self.checked(.raw, Self.rawInventory)], plan: MetadataPlan(settings: MetadataSettings(), appVersion: "0.2.0"),
            look: .standard, signature: .signed, timings: SaveTimings(), rawClipping: .notMeasured(.sizeMismatch))
        #expect(measured.rawClipping == .notMeasured(.sizeMismatch))
        #expect(Self.build([Self.checked(.raw, Self.rawInventory)]).rawClipping == nil)
    }

    @Test func theFallbackIsProcessedByTheDevice() {
        let details = Self.build([Self.checked(.heif, MetadataInventory(), byDevice: true)])
        #expect(details.files[0].processing == .byDevice)
        #expect(details.files[0].pixelWidth == nil)
    }

    @Test func rawOnlyKeepsTheRAWLockedItems() {
        #expect(
            PhotoDetails.lockedItems(for: [.raw])
                == [.imageLayout, .colorFilterPattern, .blackAndWhiteLevels, .colorCalibration, .dngVersion, .orientation])
    }

    @Test func everyFormatCombinationBuildsDetails() {
        let combinations: [[PhotoFormat]] = [[.raw], [.raw, .heif], [.raw, .jpeg], [.raw, .heif, .jpeg], [.heif], [.jpeg], [.heif, .jpeg]]
        for formats in combinations {
            let details = Self.build(formats.map { Self.checked($0, $0 == .raw ? Self.rawInventory : Self.heifInventory) })
            #expect(details.files.map(\.format) == formats)
            #expect(details.items.count == MetadataItem.allCases.count)
        }
    }

    @Test func colorFilterPatternNeedsMatchingDimensionsAndKnownColors() {
        func pattern(_ dimensions: [Double], _ codes: [Double]) -> String? {
            PhotoDetails.colorFilterPattern(
                in: MetadataInventory(tags: [
                    Tag(directory: .primary, tag: 0x828D, values: dimensions),
                    Tag(directory: .primary, tag: 0x828E, values: codes),
                ]))
        }
        #expect(pattern([2, 2], [2, 1, 1, 0]) == "BGGR")
        #expect(pattern([2, 2], [3, 4, 5, 6]) == "CMYW")
        #expect(pattern([2, 2], [0, 1, 2]) == nil)
        #expect(pattern([2], [0]) == nil)
        #expect(pattern([1, 1], []) == nil)
        #expect(pattern([1, 1], [7]) == nil)
    }

    @Test func exposureReadsEachWhiteBalanceValue() {
        func whiteBalance(_ value: Double) -> PhotoDetails.WhiteBalanceSetting? {
            PhotoDetails.exposure(in: MetadataInventory(tags: [Tag(directory: .exif, tag: 0xA403, values: [value])]))?.whiteBalance
        }
        #expect(whiteBalance(0) == .automatic)
        #expect(whiteBalance(1) == .manual)
        #expect(PhotoDetails.exposure(in: MetadataInventory(tags: [Tag(directory: .exif, tag: 0xA403, values: [5])])) == nil)
        #expect(PhotoDetails.exposure(in: MetadataInventory(tags: [Tag(directory: .exif, tag: 0x8827, values: [50])]))?.iso == 50)
        func flash(_ value: Double) -> Bool? {
            PhotoDetails.exposure(in: MetadataInventory(tags: [Tag(directory: .exif, tag: 0x9209, values: [value])]))?.flashFired
        }
        #expect(flash(0x10) == false)
        #expect(flash(0x19) == true)
    }

    @Test func itemsAreRemovedWrittenOrHaveNothingToWrite() {
        let defaults = Self.build([Self.checked(.raw, Self.rawInventory)])
        // First launch: every optional item off, so each one is removed.
        #expect(defaults.items.allSatisfy { $0.state == .removed })
        #expect(defaults.writtenItems.isEmpty && defaults.leftOutItems.count == MetadataItem.allCases.count)

        var settings = MetadataSettings()
        for item in MetadataItem.allCases { settings.set(item, isOn: true) }
        let inventory = MetadataInventory(tags: [
            Tag(directory: .gps, tag: 0x0001, text: "N"),
            Tag(directory: .exif, tag: 0x927C),
            Tag(directory: .primary, tag: 0xC614, text: "iPhone"),
            Tag(directory: .primary, tag: 0x0131, text: "Photivra Nope Camera 0.2.0 (27.2.1)"),
            Tag(directory: .exif, tag: 0x9003, text: "2026:11:14 10:00:00"),
            Tag(directory: .primary, tag: 0x010F, text: ""),
        ])
        let all = Self.build([Self.checked(.raw, inventory)], settings: settings)
        func state(_ item: MetadataItem) -> PhotoDetails.ItemReceipt.State? {
            all.items.first { $0.item == item }?.state
        }
        for item in [MetadataItem.location, .makerNotes, .exactCameraModel, .appNameAndVersion, .systemVersion, .dateAndTime] {
            #expect(state(item) == .written, "\(item)")
        }
        #expect(all.writtenItems == [.location, .dateAndTime, .exactCameraModel, .systemVersion, .makerNotes, .appNameAndVersion])
        // An empty Make doesn't count; nothing else is in the file.
        for item in [MetadataItem.cameraMakeAndModel, .lensCorrections, .subSecondTime, .nameAndCopyright] {
            #expect(state(item) == .nothingToWrite, "\(item)")
        }
    }

    @Test func softwareAndModelRulesMatchOnlyTheirValues() {
        func holds(_ item: MetadataItem, _ tag: Tag) -> Bool { PhotoDetails.holds(item, tag) }
        let appOnly = Tag(directory: .primary, tag: 0x0131, text: "Photivra Nope Camera 0.2.0")
        #expect(holds(.appNameAndVersion, appOnly) && !holds(.systemVersion, appOnly))
        let systemOnly = Tag(directory: .primary, tag: 0x0131, text: "27.2.1")
        #expect(!holds(.appNameAndVersion, systemOnly) && holds(.systemVersion, systemOnly))
        #expect(!holds(.systemVersion, Tag(directory: .primary, tag: 0x0131)))
        #expect(!holds(.systemVersion, Tag(directory: .exif, tag: 0x0131, text: "27.2.1")))
        #expect(!holds(.systemVersion, Tag(directory: .primary, tag: 0x0132, text: "27.2.1")))
        #expect(!holds(.exactCameraModel, Tag(directory: .primary, tag: 0xC614, text: MetadataPlan.genericUniqueCameraModel)))
        #expect(!holds(.makerNotes, Tag(directory: .primary, tag: 0x927C)))
        #expect(!holds(.makerNotes, Tag(directory: .exif, tag: 0x9003)))
    }

    @Test func tagNamesComeFromTheCatalog() {
        #expect(PhotoDetails.name(of: Tag(directory: .exif, tag: 0x829A)) == "ExposureTime")
        #expect(PhotoDetails.name(of: Tag(directory: .primary, tag: 0xCD41)) == "C2PA manifest")
        // The GPS fields of issue #43 are in the catalog; any other GPS tag has no name.
        #expect(PhotoDetails.name(of: Tag(directory: .gps, tag: 0x0001)) == "GPSLatitudeRef")
        #expect(PhotoDetails.name(of: Tag(directory: .gps, tag: 0x0011)) == "gps 0x0011")
        #expect(PhotoDetails.name(of: Tag(directory: .exif, tag: 0xCD41)) == "exif 0xCD41")
    }

    @Test func thumbnailsCheckTheirSize() {
        #expect(PhotoThumbnail(width: 2, height: 1, rgba: Data(count: 8))?.bytesPerRow == 8)
        #expect(PhotoThumbnail(width: 2, height: 1, rgba: Data(count: 7)) == nil)
        #expect(PhotoThumbnail(width: 0, height: 1, rgba: Data()) == nil)
        #expect(PhotoThumbnail(width: 1, height: 0, rgba: Data()) == nil)
    }

    @Test func timingsAddUpAndRoundToMilliseconds() {
        var timings = SaveTimings()
        timings.add(.milliseconds(10), to: \.sign)
        timings.add(.microseconds(2600), to: \.sign)
        #expect(timings.sign == .microseconds(12_600))
        #expect(SaveTimings.milliseconds(.microseconds(12_600)) == 13)
        #expect(SaveTimings.milliseconds(.seconds(2)) == 2000)
        #expect(SaveTimings(develop: .zero, readBack: .zero, save: .zero).capture == nil)
    }

    @Test func theTIFFReaderRecordsNumericValues() {
        let root = TIFFBuilder.Directory([
            (0x0001, .bytes([200])),
            (0x0002, .raw(type: 6, count: 1, bytes: [0xFF, 0, 0, 0])),
            (0x0003, .short([4032])),
            (0x0004, .raw(type: 8, count: 1, bytes: [0xFE, 0xFF, 0, 0])),
            (0x0005, .long([70000])),
            (0x0006, .raw(type: 9, count: 1, bytes: [0xFD, 0xFF, 0xFF, 0xFF])),
            (0x0007, .raw(type: 5, count: 1, bytes: [1, 0, 0, 0, 120, 0, 0, 0])),
            (0x0008, .raw(type: 10, count: 1, bytes: [0xFF, 0xFF, 0xFF, 0xFF, 3, 0, 0, 0])),
            (0x0009, .raw(type: 5, count: 1, bytes: [1, 0, 0, 0, 0, 0, 0, 0])),
            (0x000A, .short(Array(repeating: 1, count: TIFFReader.maximumRecordedValues + 1))),
            (0x000B, .raw(type: 11, count: 1, bytes: [0, 0, 0x80, 0x3F])),
            (0x000C, .ascii("text")),
            (0x0111, .long([8])),
        ])
        let tags = TIFFReader.read(TIFFBuilder.build(root)).inventory.tags
        func values(_ tag: UInt16) -> [Double] { tags.first { $0.tag == tag }?.values ?? [-99] }
        #expect(values(0x0001) == [200])
        #expect(values(0x0002) == [-1])
        #expect(values(0x0003) == [4032])
        #expect(values(0x0004) == [-2])
        #expect(values(0x0005) == [70000])
        #expect(values(0x0006) == [-3])
        #expect(values(0x0007) == [1.0 / 120])
        #expect(values(0x0008) == [-1.0 / 3])
        #expect(values(0x0009).isEmpty)
        #expect(values(0x000A).isEmpty)
        #expect(values(0x000B).isEmpty)
        #expect(values(0x000C).isEmpty)
        #expect(values(0x0111).isEmpty)
        // Out-of-bounds values give none.
        let truncated = TIFFReader.read(Array(TIFFBuilder.build(TIFFBuilder.Directory([(0x0001, .long([1, 2]))])).prefix(30)))
        #expect(truncated.inventory.tags.first?.values == [])
    }
}
