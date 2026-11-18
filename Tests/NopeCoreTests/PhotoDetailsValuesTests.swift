import Foundation
import Testing

@testable import NopeCore

/// The values What's in This Photo shows (`docs/design/BUILD-SPEC.md`, section 6, items 16 and
/// 17), read by the project's own reader from DNG, HEIF and JPEG files built byte by byte.
struct PhotoDetailsValuesTests {
    typealias Value = TIFFBuilder.Value
    typealias Directory = TIFFBuilder.Directory

    /// Every optional detail on.
    static let everything: MetadataSettings = {
        var settings = MetadataSettings()
        settings.setRemovesAllOptionalDetails(false)
        for item in MetadataItem.allCases { settings.set(item, isOn: true) }
        return settings
    }()

    /// RATIONAL (type 5) or SRATIONAL (type 10) values, little-endian, each as a fraction over
    /// 1000.
    static func rational(_ values: [Double], signed: Bool = false) -> Value {
        let bytes = values.flatMap { value -> [UInt8] in
            let numerator = UInt32(bitPattern: Int32((value * 1000).rounded()))
            return [numerator, 1000].flatMap { part in (0..<4).map { UInt8((part >> (8 * $0)) & 0xFF) } }
        }
        return .raw(type: signed ? 10 : 5, count: UInt32(values.count), bytes: bytes)
    }

    /// An UNDEFINED (type 7) value of these bytes.
    static func undefined(_ bytes: [UInt8]) -> Value {
        .raw(type: 7, count: UInt32(bytes.count), bytes: bytes)
    }

    /// The EXIF directory of a photo with every exposure value.
    static var exif: [(UInt16, Value)] {
        [
            (0x829A, rational([0.008])), (0x829D, rational([1.78])), (0x8822, .short([2])), (0x8827, .short([200])),
            (0x9003, .ascii("2026:11:18 14:41:07")), (0x9011, .ascii("+01:00")), (0x9291, .ascii("123")),
            (0x9203, rational([7.2], signed: true)), (0x9204, rational([0], signed: true)), (0x9205, rational([1.66])),
            (0x9207, .short([5])), (0x9209, .short([16])), (0x920A, rational([6.86])),
            (0x9214, .short([2015, 1511, 2217, 1330])), (0xA402, .short([0])), (0xA403, .short([0])), (0xA405, .short([24])),
            (0xA433, .ascii("Apple")), (0xA434, .ascii("iPhone 16 Pro Max back camera 6.86mm f/1.78")),
            (0x927C, undefined([1, 2, 3, 4, 5])),
        ]
    }

    /// The GPS directory of a place south and east, below sea level.
    static var gps: [(UInt16, Value)] {
        [
            (0x0000, .bytes([2, 3, 0, 0])), (0x0001, .ascii("S")), (0x0002, rational([45, 31, 23.16])),
            (0x0003, .ascii("E")), (0x0004, rational([122, 40, 35.4])), (0x0005, .bytes([1])), (0x0006, rational([12])),
        ]
    }

    /// A DNG with every value What's in This Photo reads.
    static var dng: Data {
        let primary: [(UInt16, Value)] = [
            (0x0100, .long([4032])), (0x0101, .long([3024])), (0x0102, .short([12])), (0x0103, .short([7])),
            (0x010F, .ascii("Apple")), (0x0110, .ascii("iPhone 16 Pro Max")), (0x0131, .ascii("Photivra Nope Camera 1.0.0 (27.2.1)")),
            (0x0132, .ascii("2026:11:18 14:41:07")), (0x013B, .ascii("Ada")), (0x8298, .ascii("© Ada")),
            (0x828D, .short([2, 2])), (0x828E, .bytes([0, 1, 1, 2])), (0xC612, .bytes([1, 4, 0, 0])),
            (0xC614, .ascii("iPhone 16 Pro Max")), (0xC61A, .short([528, 528, 528, 528])), (0xC61D, .short([4095])),
            (0xC61F, .short([8, 8])), (0xC620, .short([4032, 3024])), (0xC628, rational([0.48, 1, 0.62])),
            (0xC62A, rational([0], signed: true)), (0xC68D, .short([0, 0, 3024, 4224])), (0xC741, undefined([0, 0, 0, 0, 1])),
            (0xCD41, undefined([9, 9, 9, 9, 9])),
            (0x8769, .directories([Directory(exif)])), (0x8825, .directories([Directory(gps)])),
        ]
        return Data(TIFFBuilder.build(Directory(primary)))
    }

    /// A HEIF with an EXIF item (exposure only, without the lens names) and an XMP packet that
    /// mirrors the app's name.
    static var heif: Data {
        let tiff = TIFFBuilder.build(
            Directory([
                (0x8769, .directories([Directory([(0x829A, rational([0.008])), (0x9207, .short([2])), (0xA001, .short([0xFFFF]))])])),
                (0xA005, .short([1])),
            ]))
        return HEIFBuilder.build(items: [
            .init(id: 1, type: "hvc1"),
            .init(id: 2, type: "Exif", data: HEIFBuilder.exifItem(tiff)),
            .init(id: 3, type: "mime", contentType: "application/rdf+xml", data: HEIFBuilder.xmp([
                ("xmp", MetadataPlan.xmpNamespace, "CreatorTool", "Photivra Nope Camera 1.0.0"),
                ("xmp", MetadataPlan.xmpNamespace, "CreateDate", "2026-11-18T14:41:07"),
            ])),
        ])
    }

    /// A JPEG from the phone's camera (a lens without RAW), signed: an EXIF block with the camera
    /// names and nothing else, and a Content Credentials segment.
    static var jpeg: Data {
        let tiff = TIFFBuilder.build(Directory([(0x010F, .ascii("Apple")), (0x0110, .ascii("Apple iPhone 16 Pro Max"))]), bigEndian: true)
        let segments: [(UInt8, [UInt8])] = [
            (0xE1, Array("Exif".utf8) + [0, 0] + tiff), (0xEB, Array("JP".utf8) + [0, 0]),
            (0xDB, Array(repeating: 1, count: 65)), (0xC0, [8, 0, 2, 0, 2, 1, 1, 0x11, 0]),
        ]
        var bytes: [UInt8] = [0xFF, 0xD8]
        for (marker, payload) in segments {
            bytes += [0xFF, marker, UInt8((payload.count + 2) >> 8), UInt8((payload.count + 2) & 0xFF)] + payload
        }
        bytes += [0xFF, 0xDA, 0, 8, 1, 1, 0, 0, 0x3F, 0, 0x12, 0xFF, 0xD9]
        return Data(bytes)
    }

    /// A file read back by the project's own reader.
    static func checked(
        _ format: PhotoFormat, _ data: Data, image: ImageProperties? = nil, byDevice: Bool = false
    ) -> PhotoDetails.CheckedFile {
        let result = MetadataFileReader.read(data, format: format)
        #expect(result.inventory.problems.isEmpty)
        return PhotoDetails.CheckedFile(
            file: PhotoFile(format: format, data: data, isProcessedByDevice: byDevice),
            readBack: MetadataReadBack(file: result, imageIOKeys: [], image: image))
    }

    static func build(
        _ files: [PhotoDetails.CheckedFile], settings: MetadataSettings = everything,
        options: DevelopedFileOptions = DevelopedFileOptions(), pairing: RAWPairing = .heif,
        capture: PhotoDetails.CaptureReport? = nil
    ) -> PhotoDetails {
        PhotoDetails.build(
            files: files, plan: MetadataPlan(settings: settings, appVersion: "1.0.0"), look: .standard,
            signature: .signed, timings: SaveTimings(), options: options, pairing: pairing, capture: capture)
    }

    @Test func aDNGGivesEveryExposureValue() throws {
        let details = Self.build([Self.checked(.raw, Self.dng)])
        let exposure = try #require(details.exposure)
        #expect(exposure.exposureTime == 0.008 && exposure.iso == 200 && exposure.fNumber == 1.78)
        #expect(exposure.equivalentFocalLength == 24 && exposure.exposureMode == .auto && exposure.program == .normal)
        #expect(exposure.metering == .pattern && exposure.brightness == 7.2 && exposure.subjectArea == [2015, 1511, 2217, 1330])
        // APEX 1.66 is f/1.78 (2^(1.66/2)).
        #expect(abs((exposure.largestAperture ?? 0) - 1.778) < 0.001)
        #expect(exposure.flashFired == false && exposure.hasMoreDetails)
    }

    @Test func aDNGGivesItsStructureAndSize() throws {
        let file = try #require(Self.build([Self.checked(.raw, Self.dng)]).rawFile)
        let structure = try #require(file.rawStructure)
        #expect(structure.activeArea == [0, 0, 3024, 4224] && structure.defaultCropOrigin == [8, 8])
        #expect(structure.defaultCropSize == [4032, 3024] && structure.compression == .losslessJPEG)
        #expect(structure.dngVersion == [1, 4, 0, 0] && structure.dngVersionText == "1.4")
        #expect(structure.baselineExposure == 0 && structure.asShotNeutral == [0.48, 1, 0.62])
        #expect(file.megapixels == 12 && file.colorSpace == nil && file.quality == nil)
    }

    @Test func aDNGGivesTheLensAndCamera() {
        let names = Self.build([Self.checked(.raw, Self.dng)]).lensAndCamera
        #expect(
            names
                == PhotoDetails.LensAndCamera(
                    lensModel: "iPhone 16 Pro Max back camera 6.86mm f/1.78", lensMake: "Apple", make: "Apple",
                    model: "iPhone 16 Pro Max"))
        #expect(names?.camera == "Apple iPhone 16 Pro Max")
    }

    @Test func aDNGGivesEachWrittenItemsValue() throws {
        let details = Self.build([Self.checked(.raw, Self.dng)])
        func value(_ item: MetadataItem) -> PhotoDetails.ItemValue? { details.items.first { $0.item == item }?.value }
        #expect(value(.subSecondTime) == .text("123"))
        #expect(value(.timeZone) == .text("+01:00"))
        #expect(value(.cameraMakeAndModel) == .text("Apple iPhone 16 Pro Max"))
        #expect(value(.lensMakeAndModel) == .text("Apple, iPhone 16 Pro Max back camera 6.86mm f/1.78"))
        #expect(value(.exactCameraModel) == .text("iPhone 16 Pro Max"))
        #expect(value(.systemVersion) == .text("27.2.1"))
        #expect(value(.appNameAndVersion) == .text("Photivra Nope Camera 1.0.0"))
        #expect(value(.nameAndCopyright) == .text("Ada, © Ada"))
        #expect(value(.exposureSettings) == nil && value(.lensCorrections) == nil && value(.makerNotes) == nil)
        // 14:41:07 at +01:00 is 13:41:07 UTC.
        let date = try #require({ if case .date(let date) = value(.dateAndTime) { date } else { nil } }())
        #expect(date == Date(timeIntervalSince1970: 1_795_009_267))
        // 45° 31′ 23.16″ S, 122° 40′ 35.4″ E, 12 m below sea level.
        let place = try #require({ if case .location(let place) = value(.location) { place } else { nil } }())
        #expect(abs(place.latitude + 45.5231) < 0.0001 && abs(place.longitude - 122.6765) < 0.0001 && place.altitude == -12)
        #expect(details.holdsLocation && details.optionalDetailCount == 12)
        #expect(details.items.first { $0.item == .location }?.isIdentifying == true)
        #expect(details.items.first { $0.item == .makerNotes }?.isIdentifying == true)
        #expect(details.items.first { $0.item == .timeZone }?.isIdentifying == false)
    }

    @Test func aDNGsEntriesAreGroupedAndNamed() throws {
        let file = try #require(Self.build([Self.checked(.raw, Self.dng)]).rawFile)
        #expect(file.entries.count == file.contents.count)
        #expect(file.places == [.tiff, .exif, .gps, .dng, .contentCredentials])
        let exposureTime = try #require(file.entries(in: .exif).first { $0.name == "ExposureTime" })
        #expect(exposureTime.value == .numbers([0.008]) && exposureTime.tagNumberText == "0x829A")
        #expect(exposureTime.control == .setting(.exposureSettings) && !exposureTime.hidesValue)
        let latitude = try #require(file.entries(in: .gps).first { $0.name == "GPSLatitude" })
        #expect(latitude.isIdentifying && latitude.hidesValue && latitude.control == .setting(.location))
        let makerNote = try #require(file.entries(in: .exif).first { $0.name == "MakerNote" })
        #expect(makerNote.isIdentifying && !makerNote.hidesValue)
        #expect(file.entries(in: .tiff).contains { $0.name == "ImageWidth" && $0.control == .alwaysSaved })
        #expect(file.entries(in: .dng).map(\.name).contains("DNGVersion"))
        #expect(file.entries(in: .dng).allSatisfy { ($0.tagNumber ?? 0) >= 0xC612 })
        let signature = try #require(file.entries(in: .contentCredentials).first)
        #expect(signature.control == .signature && signature.tagNumberText == "0xCD41")
        #expect(file.entries.first { $0.tagNumber == 0x0000 }?.tagNumberText == "0x0000")
    }

    @Test func aHEIFCopyGivesItsOptionsBlocksAndXMP() throws {
        var options = DevelopedFileOptions()
        options.colorSpace = .sRGB
        options.heifQuality = .high
        let details = Self.build(
            [Self.checked(.heif, Self.heif, image: ImageProperties(pixelWidth: 1920, pixelHeight: 1440, depth: 10))],
            options: options)
        let file = try #require(details.files.first)
        #expect(file.colorSpace == .sRGB && file.quality == .high && file.megapixels == 2.8 && file.rawStructure == nil)
        #expect(file.places == [.tiff, .exif, .xmp, .fileStructure])
        #expect(file.entries(in: .xmp).first { $0.name == "CreatorTool" }?.control == .setting(.appNameAndVersion))
        #expect(file.entries(in: .xmp).first { $0.name == "CreateDate" }?.control == .alwaysSaved)
        #expect(file.entries(in: .fileStructure).first { $0.name == "heif:item:hvc1" }?.value == .count(1))
        // The interoperability directory is listed with EXIF.
        #expect(file.entries(in: .exif).count == 3)
        // Only the metering is a "more" value; the lens names are missing.
        #expect(details.exposure?.metering == .centerWeighted && details.lensAndCamera == nil)
        #expect(details.items.first { $0.item == .appNameAndVersion }?.value == nil)
    }

    @Test func aProcessedJPEGHasNoCopyOptionsAndASignatureBlock() throws {
        let details = Self.build([Self.checked(.jpeg, Self.jpeg, byDevice: true)])
        let file = try #require(details.files.first)
        #expect(file.colorSpace == nil && file.quality == nil && file.megapixels == nil)
        #expect(file.entries(in: .contentCredentials).map(\.name) == ["jpeg:APP11"])
        #expect(file.entries(in: .contentCredentials).first?.control == .signature)
        #expect(details.lensAndCamera?.camera == "Apple iPhone 16 Pro Max" && details.lensAndCamera?.lensModel == nil)
        #expect(details.exposure == nil && details.inPhotos == nil)
    }

    @Test func theCapturedExposureShowsOnlyWhenTheFilesHoldNone() {
        let capture = PhotoDetails.CaptureReport(exposureDuration: 1.0 / 60, iso: 100, lensID: "wide")
        let bare = Self.checked(.raw, Data(TIFFBuilder.build(Directory([(0x0100, .long([4032]))]))))
        let notInFiles = Self.build([bare], settings: MetadataSettings(), capture: capture)
        #expect(notInFiles.exposureNotInFiles == capture && notInFiles.lensNotInFiles == "wide")
        let inFiles = Self.build([Self.checked(.raw, Self.dng)], capture: capture)
        #expect(inFiles.exposureNotInFiles == nil && inFiles.lensNotInFiles == nil)
        let nothingReported = PhotoDetails.CaptureReport(exposureDuration: nil, iso: nil, lensID: "wide")
        #expect(Self.build([bare], capture: nothingReported).exposureNotInFiles == nil)
        let isoOnly = PhotoDetails.CaptureReport(exposureDuration: nil, iso: 50, lensID: "wide")
        #expect(Self.build([bare], capture: isoOnly).exposureNotInFiles == isoOnly)
        #expect(Self.build([bare]).exposureNotInFiles == nil && Self.build([bare]).lensNotInFiles == nil)
        #expect(notInFiles.optionalDetailCount == 0 && !notInFiles.holdsLocation)
        #expect(notInFiles.location?.state == .removed && notInFiles.writtenReceipts.isEmpty)
    }

    @Test func theCaptureReportComesFromTheCapturedPhoto() {
        let photo = CapturedPhoto(
            data: Data(), format: .bayerRAW(pixelFormat: "rggb"), lensID: "tele", dimensions: PhotoDimensions(width: 1, height: 1),
            exposureDuration: 0.5, iso: 64)
        #expect(PhotoDetails.CaptureReport(photo) == PhotoDetails.CaptureReport(exposureDuration: 0.5, iso: 64, lensID: "tele"))
    }

    @Test func standardFileTagsFollowTheSettings() {
        var off = Self.everything
        off.writesStandardFileTags = false
        #expect(!Self.build([Self.checked(.raw, Self.dng)], settings: off).writesStandardFileTags)
        #expect(Self.build([Self.checked(.raw, Self.dng)]).writesStandardFileTags)
    }

    @Test func photosPairsTheRAWWithTheChosenCopy() {
        let raw = PhotoFile(format: .raw, data: Data([1]))
        let heif = PhotoFile(format: .heif, data: Data([2]))
        let jpeg = PhotoFile(format: .jpeg, data: Data([3]))
        #expect(PhotoDetails.PhotosPairing(files: [raw, heif], pairing: .heif) == .init(pairedFormat: .heif, separateFormat: nil))
        #expect(PhotoDetails.PhotosPairing(files: [raw, heif, jpeg], pairing: .jpeg) == .init(pairedFormat: .jpeg, separateFormat: .heif))
        #expect(PhotoDetails.PhotosPairing(files: [raw], pairing: .heif) == nil)
        #expect(PhotoDetails.PhotosPairing(files: [heif, jpeg], pairing: .heif) == nil)
    }

    @Test func exifCodesAreNamedOrKeptAsNumbers() {
        #expect([0, 1, 2, 9].map(PhotoDetails.ExposureModeValue.init(code:)) == [.auto, .manual, .autoBracket, .other(9)])
        #expect(
            (0...9).map(PhotoDetails.ExposureProgramValue.init(code:)) == [
                .notDefined, .manual, .normal, .aperturePriority, .shutterPriority, .creative, .action, .portrait, .landscape,
                .other(9),
            ])
        #expect(
            [0, 1, 2, 3, 4, 5, 6, 255, 7].map(PhotoDetails.MeteringValue.init(code:)) == [
                .unknown, .average, .centerWeighted, .spot, .multiSpot, .pattern, .partial, .otherMode, .other(7),
            ])
        let compressions = [1, 7, 34892, 52546, 8].map(PhotoDetails.RAWCompression.init(code:))
        #expect(compressions == [.uncompressed, .losslessJPEG, .lossyJPEG, .jpegXL, .other(8)])
        #expect(compressions.map(\.isLossless) == [true, true, false, false, false])
    }

    @Test func dngVersionsDropTrailingZeros() {
        func text(_ version: [Int]) -> String? {
            PhotoDetails.RAWStructure(
                activeArea: [], defaultCropOrigin: [], defaultCropSize: [], compression: nil, dngVersion: version,
                baselineExposure: nil, asShotNeutral: []
            ).dngVersionText
        }
        #expect(text([]) == nil && text([1, 4, 0, 0]) == "1.4" && text([1, 7, 1, 0]) == "1.7.1" && text([2, 0]) == "2.0")
    }

    @Test func theCameraJoinsMakeAndModelOnce() {
        func camera(_ make: String?, _ model: String?) -> String? {
            PhotoDetails.LensAndCamera(lensModel: nil, lensMake: nil, make: make, model: model).camera
        }
        #expect(camera("Apple", "iPhone 16") == "Apple iPhone 16")
        #expect(camera("Apple", "Apple iPhone 16") == "Apple iPhone 16")
        #expect(camera("Apple", nil) == "Apple" && camera(nil, "iPhone 16") == "iPhone 16" && camera(nil, nil) == nil)
    }

    @Test func datesUseTheFilesOffsetOrTheDevicesTimeZone() throws {
        typealias Tag = MetadataInventory.Tag
        func date(_ tags: [Tag]) -> Date? { PhotoDetails.date(in: [MetadataInventory(tags: tags)]) }
        let local = try #require(date([Tag(directory: .primary, tag: 0x0132, text: "2026:11:18 14:41:07")]))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: local)
        #expect([parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second] == [2026, 11, 18, 14, 41, 7])
        let west = date([
            Tag(directory: .exif, tag: 0x9003, text: "2026:11:18 14:41:07"), Tag(directory: .exif, tag: 0x9010, text: "-05:30"),
        ])
        #expect(west == Date(timeIntervalSince1970: 1_795_032_667))
        #expect(date([Tag(directory: .primary, tag: 0x0132, text: MetadataPlan.unknownDateTime)]) == nil)
        #expect(date([]) == nil)
        #expect(PhotoDetails.timeZone(offset: "01:00") == nil && PhotoDetails.timeZone(offset: "+1") == nil)
    }

    @Test func locationsNeedALatitudeAndLongitude() {
        typealias Tag = MetadataInventory.Tag
        func place(_ tags: [Tag]) -> PhotoLocation? { PhotoDetails.location(in: [MetadataInventory(tags: tags)]) }
        let north = [
            Tag(directory: .gps, tag: 0x0001, text: "N"), Tag(directory: .gps, tag: 0x0002, values: [0, 30, 0]),
            Tag(directory: .gps, tag: 0x0003, text: "W"), Tag(directory: .gps, tag: 0x0004, values: [1, 0, 0]),
        ]
        #expect(place(north) == PhotoLocation(latitude: 0.5, longitude: -1))
        let above = north + [Tag(directory: .gps, tag: 0x0005, values: [0]), Tag(directory: .gps, tag: 0x0006, values: [312])]
        #expect(place(above)?.altitude == 312)
        #expect(place(Array(north.prefix(2))) == nil)
        #expect(place([Tag(directory: .gps, tag: 0x0002, values: [1])]) == nil)
        #expect(place([]) == nil)
    }

    @Test func itemsWithoutValuesInTheFilesHaveNone() {
        for item in MetadataItem.allCases {
            #expect(PhotoDetails.value(of: item, in: [MetadataInventory()]) == nil, "\(item)")
        }
    }

    @Test func placesFollowTheDirectoryAndTagNumber() {
        func place(_ directory: TIFFDirectory, _ tag: UInt16) -> PhotoDetails.TagEntry.Place {
            PhotoDetails.place(of: MetadataComparison.tagItem(MetadataInventory.Tag(directory: directory, tag: tag)))
        }
        #expect(place(.primary, 0x0100) == .tiff && place(.primary, 0xC612) == .dng && place(.primary, 0xCD41) == .contentCredentials)
        #expect(place(.exif, 0x829A) == .exif && place(.interoperability, 1) == .exif && place(.gps, 2) == .gps)
        #expect(place(.subImage, 0x0100) == .tiff && place(.followingImage, 0x0201) == .tiff)
        let block = MetadataComparison.Item(
            id: "b", name: "jpeg:SOI", kind: .block, value: .count(1), item: nil, isIdentifying: false, isSignature: false)
        #expect(PhotoDetails.place(of: block) == .fileStructure && block.tagNumber == nil)
    }

    @Test func onlyMirroredXMPTextHasASwitch() {
        let structure = MetadataComparison.Item(
            id: "x", name: "CreatorTool", kind: .xmp(namespace: MetadataPlan.xmpNamespace), value: .present, item: nil,
            isIdentifying: false, isSignature: false)
        #expect(PhotoDetails.mirroredItem(structure) == nil)
        let rights = MetadataComparison.Item(
            id: "r", name: "rights", kind: .xmp(namespace: MetadataPlan.dublinCoreNamespace), value: .text("© Ada"), item: nil,
            isIdentifying: false, isSignature: false)
        #expect(PhotoDetails.mirroredItem(rights) == .nameAndCopyright)
        let block = MetadataComparison.Item(
            id: "b", name: "CreatorTool", kind: .block, value: .text("x"), item: nil, isIdentifying: false, isSignature: false)
        #expect(PhotoDetails.mirroredItem(block) == nil)
    }

    @Test func megapixelsAreWholeFromTenUp() {
        func megapixels(_ width: Int?, _ height: Int?) -> Double? {
            PhotoDetails.File(
                format: .heif, byteCount: 1, pixelWidth: width, pixelHeight: height, bitDepth: nil, colorFilterPattern: nil,
                blackLevels: [], whiteLevels: [], storesLensCorrections: false, processing: .none, contentCredentials: nil,
                contents: []
            ).megapixels
        }
        #expect(megapixels(4032, 3024) == 12 && megapixels(8064, 6048) == 49 && megapixels(1920, 1440) == 2.8)
        #expect(megapixels(nil, 1) == nil && megapixels(1, nil) == nil)
    }

    @Test func moreExposureDetailsCountEachValue() {
        func exposure(_ build: (inout [String: Any]) -> Void = { _ in }) -> PhotoDetails.Exposure {
            var values: [String: Any] = [:]
            build(&values)
            return PhotoDetails.Exposure(
                exposureTime: nil, iso: nil, fNumber: nil, focalLength: nil, exposureBias: nil, whiteBalance: nil,
                exposureMode: values["mode"] as? PhotoDetails.ExposureModeValue,
                program: values["program"] as? PhotoDetails.ExposureProgramValue,
                metering: values["metering"] as? PhotoDetails.MeteringValue, brightness: values["brightness"] as? Double,
                largestAperture: values["largest"] as? Double, subjectArea: values["area"] as? [Double] ?? [])
        }
        #expect(!exposure().hasMoreDetails)
        #expect(exposure { $0["mode"] = PhotoDetails.ExposureModeValue.manual }.hasMoreDetails)
        #expect(exposure { $0["program"] = PhotoDetails.ExposureProgramValue.manual }.hasMoreDetails)
        #expect(exposure { $0["metering"] = PhotoDetails.MeteringValue.spot }.hasMoreDetails)
        #expect(exposure { $0["brightness"] = 1.0 }.hasMoreDetails)
        #expect(exposure { $0["largest"] = 1.8 }.hasMoreDetails)
        #expect(exposure { $0["area"] = [1.0, 2.0] }.hasMoreDetails)
        // A file with only the 35 mm equivalent still has an exposure.
        let equivalent = MetadataInventory(tags: [MetadataInventory.Tag(directory: .exif, tag: 0xA405, values: [24])])
        #expect(PhotoDetails.exposure(in: equivalent)?.equivalentFocalLength == 24)
        let subjectOnly = MetadataInventory(tags: [MetadataInventory.Tag(directory: .exif, tag: 0x9214, values: [1, 2])])
        #expect(PhotoDetails.exposure(in: subjectOnly)?.subjectArea == [1, 2])
    }
}
