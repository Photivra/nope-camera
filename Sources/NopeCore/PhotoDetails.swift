import Foundation

/// "What's in this photo": the facts about one photo the app just saved, read back from the
/// saved files (issue #53).
///
/// ``PhotoSaver`` builds it from each file's read-back (the project's own tag reader and
/// ImageIO), the metadata plan, the signer's manifest summary and the measured timings, and keeps
/// it in ``SavedPhoto/details``. Every value is what the file holds or what was measured; a
/// value the file doesn't hold is `nil` or empty, never estimated.
///
/// Privacy: built in memory from the just-saved photo and shown on screen only; nothing is
/// logged, stored or copied. The app can't reopen older photos (add-only access), so details
/// exist only for photos taken in this session.
public struct PhotoDetails: Equatable, Sendable {
    /// One saved file.
    public struct File: Equatable, Sendable {
        /// The file's format.
        public let format: PhotoFormat
        /// The file's size, in bytes.
        public let byteCount: Int
        /// The image width in pixels: for a DNG, the RAW data's `ImageWidth`; for HEIF and
        /// JPEG, the width ImageIO reports (or the EXIF `PixelXDimension`).
        public let pixelWidth: Int?
        /// The image height in pixels, read like ``pixelWidth``.
        public let pixelHeight: Int?
        /// Bits per sample: a DNG's `BitsPerSample`, or the bit depth ImageIO reports for HEIF and
        /// JPEG.
        public let bitDepth: Int?
        /// A DNG's color filter pattern, such as `RGGB`, from `CFARepeatPatternDim` and
        /// `CFAPattern` (TIFF/EP; DNG 1.7, "CFAPattern"); `nil` otherwise.
        public let colorFilterPattern: String?
        /// A DNG's `BlackLevel` values; empty otherwise.
        public let blackLevels: [Double]
        /// A DNG's `WhiteLevel` values; empty otherwise.
        public let whiteLevels: [Double]
        /// Whether a DNG stores lens correction instructions (opcode lists 1, 2 or 3). The app
        /// never applies them to the pixels.
        public let storesLensCorrections: Bool
        /// What processing the file's pixels went through.
        public let processing: Processing
        /// What the file's Content Credentials manifest says, or `nil` when it isn't signed.
        public let contentCredentials: ContentCredentialsSummary?
        /// Every tag, block and property the read-back found, by its specification name (such as
        /// `ExposureTime` or `jpeg:APP1:Exif`), in file order. A tag without a catalog name is
        /// shown by its directory and number, such as `primary 0xC7FF`.
        public let contents: [String]
        /// Every tag, block and XMP property the read-back found, once each, with its value, the
        /// setting that controls it and its place in the file, for the Every Tag page. Built as
        /// ``MetadataComparison`` builds its items, so a repeated tag is listed once and a
        /// repeated block once with its count.
        public let entries: [TagEntry]
        /// A DNG's structure: active area, default crop, compression, DNG version, baseline
        /// exposure and as-shot neutral; `nil` for HEIF and JPEG.
        public let rawStructure: RAWStructure?
        /// The color space a HEIF or JPEG copy was developed in (``DevelopedFileOptions``);
        /// `nil` for the DNG and for a processed fallback, whose color the camera chose.
        public let colorSpace: OutputColorSpace?
        /// The compression quality a HEIF or JPEG copy was encoded with
        /// (``DevelopedFileOptions``); `nil` for the DNG and for a processed fallback.
        public let quality: CompressionQuality?

        /// Creates a file's details.
        ///
        /// - Parameters:
        ///   - format: The format.
        ///   - byteCount: The size in bytes.
        ///   - pixelWidth: The width in pixels.
        ///   - pixelHeight: The height in pixels.
        ///   - bitDepth: Bits per sample.
        ///   - colorFilterPattern: The color filter pattern.
        ///   - blackLevels: The black levels.
        ///   - whiteLevels: The white levels.
        ///   - storesLensCorrections: Whether lens correction instructions are stored.
        ///   - processing: The processing.
        ///   - contentCredentials: The manifest summary.
        ///   - contents: The names of everything found.
        ///   - entries: Everything found, with values. Defaults to none.
        ///   - rawStructure: A DNG's structure, or `nil`.
        ///   - colorSpace: A developed copy's color space, or `nil`.
        ///   - quality: A developed copy's compression quality, or `nil`.
        public init(
            format: PhotoFormat, byteCount: Int, pixelWidth: Int?, pixelHeight: Int?, bitDepth: Int?,
            colorFilterPattern: String?, blackLevels: [Double], whiteLevels: [Double], storesLensCorrections: Bool,
            processing: Processing, contentCredentials: ContentCredentialsSummary?, contents: [String],
            entries: [TagEntry] = [], rawStructure: RAWStructure? = nil, colorSpace: OutputColorSpace? = nil,
            quality: CompressionQuality? = nil
        ) {
            self.format = format
            self.byteCount = byteCount
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.bitDepth = bitDepth
            self.colorFilterPattern = colorFilterPattern
            self.blackLevels = blackLevels
            self.whiteLevels = whiteLevels
            self.storesLensCorrections = storesLensCorrections
            self.processing = processing
            self.contentCredentials = contentCredentials
            self.contents = contents
            self.entries = entries
            self.rawStructure = rawStructure
            self.colorSpace = colorSpace
            self.quality = quality
        }

        /// The image's size in megapixels, as cameras state it: whole megapixels from 10 up
        /// (4032 × 3024 is 12 MP), one decimal below (1920 × 1440 is 2.8 MP); `nil` without a
        /// pixel size.
        public var megapixels: Double? {
            guard let pixelWidth, let pixelHeight else { return nil }
            let exact = Double(pixelWidth * pixelHeight) / 1_000_000
            return exact >= 10 ? exact.rounded() : (exact * 10).rounded() / 10
        }

        /// The places that hold entries, in ``TagEntry/Place`` order.
        public var places: [TagEntry.Place] {
            TagEntry.Place.allCases.filter { place in entries.contains { $0.place == place } }
        }

        /// The entries in one place, in file order.
        ///
        /// - Parameter place: The place.
        /// - Returns: The entries.
        public func entries(in place: TagEntry.Place) -> [TagEntry] {
            entries.filter { $0.place == place }
        }
    }

    /// What processing a file's pixels went through.
    public enum Processing: Equatable, Sendable {
        /// None by the app: the sensor data as the camera delivered it (the DNG).
        case none
        /// Developed by the app from the RAW, with this look.
        case developed(DevelopedLook)
        /// Processed by the phone's camera, because the lens can't save RAW.
        case byDevice
    }

    /// The exposure as the file records it, in its EXIF tags.
    public struct Exposure: Equatable, Sendable {
        /// `ExposureTime`, in seconds.
        public let exposureTime: Double?
        /// `PhotographicSensitivity` (ISO).
        public let iso: Double?
        /// `FNumber`, the aperture's f-number.
        public let fNumber: Double?
        /// `FocalLength`, in millimeters (the lens's real focal length, not the 35 mm equivalent).
        public let focalLength: Double?
        /// `ExposureBiasValue`, in EV.
        public let exposureBias: Double?
        /// `WhiteBalance`: automatic or manual.
        public let whiteBalance: WhiteBalanceSetting?
        /// Whether the flash fired: bit 0 of the EXIF `Flash` tag (EXIF 3.0, tag `0x9209`).
        public let flashFired: Bool?
        /// `FocalLengthIn35mmFilm`: the focal length a 35 mm camera would need for the same
        /// field of view, in millimeters.
        public let equivalentFocalLength: Double?
        /// `ExposureMode`: automatic, manual or auto bracket.
        public let exposureMode: ExposureModeValue?
        /// `ExposureProgram`: the program the camera used.
        public let program: ExposureProgramValue?
        /// `MeteringMode`: how the camera measured the scene.
        public let metering: MeteringValue?
        /// `BrightnessValue`: the scene's brightness, in EV (APEX).
        public let brightness: Double?
        /// The lens's largest aperture as an f-number, from `MaxApertureValue` (an APEX value
        /// `A`, so the f-number is 2^(A/2); EXIF 3.0, 4.6.5).
        public let largestAperture: Double?
        /// `SubjectArea`: the subject's place in the picture, as two to four numbers (a point,
        /// a circle or a rectangle, in pixels); empty when the file doesn't say.
        public let subjectArea: [Double]

        /// Creates the exposure details.
        ///
        /// - Parameters:
        ///   - exposureTime: The exposure time in seconds.
        ///   - iso: The ISO.
        ///   - fNumber: The f-number.
        ///   - focalLength: The focal length in millimeters.
        ///   - exposureBias: The exposure bias in EV.
        ///   - whiteBalance: The white balance setting.
        ///   - flashFired: Whether the flash fired. Defaults to `nil` (not recorded).
        ///   - equivalentFocalLength: The 35 mm equivalent focal length in millimeters, or `nil`.
        ///   - exposureMode: The exposure mode, or `nil`.
        ///   - program: The exposure program, or `nil`.
        ///   - metering: The metering mode, or `nil`.
        ///   - brightness: The brightness in EV, or `nil`.
        ///   - largestAperture: The lens's largest aperture as an f-number, or `nil`.
        ///   - subjectArea: The subject area, or none.
        public init(
            exposureTime: Double?, iso: Double?, fNumber: Double?, focalLength: Double?, exposureBias: Double?,
            whiteBalance: WhiteBalanceSetting?, flashFired: Bool? = nil, equivalentFocalLength: Double? = nil,
            exposureMode: ExposureModeValue? = nil, program: ExposureProgramValue? = nil, metering: MeteringValue? = nil,
            brightness: Double? = nil, largestAperture: Double? = nil, subjectArea: [Double] = []
        ) {
            self.exposureTime = exposureTime
            self.iso = iso
            self.fNumber = fNumber
            self.focalLength = focalLength
            self.exposureBias = exposureBias
            self.whiteBalance = whiteBalance
            self.flashFired = flashFired
            self.equivalentFocalLength = equivalentFocalLength
            self.exposureMode = exposureMode
            self.program = program
            self.metering = metering
            self.brightness = brightness
            self.largestAperture = largestAperture
            self.subjectArea = subjectArea
        }

        /// Whether any of the details behind More Exposure Details is recorded.
        public var hasMoreDetails: Bool {
            exposureMode != nil || program != nil || metering != nil || brightness != nil || largestAperture != nil
                || !subjectArea.isEmpty
        }
    }

    /// The EXIF `WhiteBalance` tag's value (EXIF 3.0, tag `0xA403`).
    public enum WhiteBalanceSetting: Equatable, Sendable {
        /// 0: automatic white balance.
        case automatic
        /// 1: manual white balance.
        case manual
    }

    /// What happened to one optional metadata item.
    public struct ItemReceipt: Equatable, Sendable {
        /// What happened.
        public enum State: Equatable, Sendable {
            /// The item's switch is on and the files hold it.
            case written
            /// The item's switch is off, so it isn't in the files. For the exact camera model, a
            /// generic value stands in, because DNG requires the tag.
            case removed
            /// The item's switch is on, but there was nothing to write, such as no location yet
            /// (location access off, or no fix before the photo; issue #43), or lens correction
            /// instructions the camera didn't supply.
            case nothingToWrite
        }

        /// The item.
        public let item: MetadataItem
        /// What happened to it.
        public let state: State
        /// The item's value as the files hold it, for a written item whose value can be read:
        /// the date, the location, a name or a version. `nil` for an item that wasn't written,
        /// and for one with no readable value (maker notes, lens corrections) or whose values
        /// are shown elsewhere (exposure settings).
        public let value: ItemValue?

        /// Creates a receipt line.
        ///
        /// - Parameters:
        ///   - item: The item.
        ///   - state: What happened to it.
        ///   - value: Its value as written, or `nil`. Defaults to `nil`.
        public init(item: MetadataItem, state: State, value: ItemValue? = nil) {
            self.item = item
            self.state = state
            self.value = value
        }

        /// Whether the value identifies the person or the device, so an interface hides it
        /// until asked: the location and the maker notes, as in ``MetadataComparison``.
        public var isIdentifying: Bool { item == .location || item == .makerNotes }
    }

    /// Each saved file, in the order it was built (RAW first).
    public let files: [File]
    /// The exposure as written, from the first file that records it, or `nil` when no file does
    /// (exposure settings off).
    public let exposure: Exposure?
    /// Every optional metadata item, in `MetadataItem.allCases` order, with what happened to it.
    public let items: [ItemReceipt]
    /// The locked items the saved formats keep, because the photo can't be opened without them.
    public let lockedItems: [LockedMetadataItem]
    /// Whether the photo is signed, or why not.
    public let signature: SignatureStatus
    /// How long each step took.
    public let timings: SaveTimings
    /// The clipping counted from the RAW sensor data at capture time, or why it wasn't measured;
    /// `nil` for a photo without RAW (a lens's processed fallback).
    public let rawClipping: RAWClippingResult?
    /// For a lens's processed fallback, whether the app could turn off the camera's geometric
    /// distortion correction on that lens, as the camera reported it (issue #80); `nil` for a
    /// photo with RAW, whose files never have the correction (``DistortionCorrection``).
    public let distortionCorrection: DistortionCorrection?
    /// The lens and camera names the files hold, or `nil` when they hold none.
    public let lensAndCamera: LensAndCamera?
    /// What the camera reported for this photo (shutter, ISO and lens), kept in memory with the
    /// details for the session, or `nil` for details made outside ``PhotoSaver``.
    public let capture: CaptureReport?
    /// How a RAW and a copy were added to Photos as one asset, or `nil` when there was no pair.
    public let inPhotos: PhotosPairing?
    /// Whether the files were written with the Standard File Tags (``MetadataSettings/writesStandardFileTags``).
    public let writesStandardFileTags: Bool

    /// Creates details.
    ///
    /// - Parameters:
    ///   - files: Each file's details.
    ///   - exposure: The exposure as written.
    ///   - items: What happened to each optional item.
    ///   - lockedItems: The locked items kept.
    ///   - signature: The signature status.
    ///   - timings: The timings.
    ///   - rawClipping: The RAW clipping, or `nil`.
    ///   - distortionCorrection: The lens's distortion correction for a processed fallback, or
    ///     `nil`.
    ///   - lensAndCamera: The lens and camera names in the files, or `nil`.
    ///   - capture: What the camera reported, or `nil`.
    ///   - inPhotos: How a RAW and a copy were paired in Photos, or `nil`.
    ///   - writesStandardFileTags: Whether the Standard File Tags were written. Defaults to `true`.
    public init(
        files: [File], exposure: Exposure?, items: [ItemReceipt], lockedItems: [LockedMetadataItem],
        signature: SignatureStatus, timings: SaveTimings, rawClipping: RAWClippingResult? = nil,
        distortionCorrection: DistortionCorrection? = nil, lensAndCamera: LensAndCamera? = nil,
        capture: CaptureReport? = nil, inPhotos: PhotosPairing? = nil, writesStandardFileTags: Bool = true
    ) {
        self.rawClipping = rawClipping
        self.distortionCorrection = distortionCorrection
        self.files = files
        self.exposure = exposure
        self.items = items
        self.lockedItems = lockedItems
        self.signature = signature
        self.timings = timings
        self.lensAndCamera = lensAndCamera
        self.capture = capture
        self.inPhotos = inPhotos
        self.writesStandardFileTags = writesStandardFileTags
    }

    /// The optional items that were written.
    public var writtenItems: [MetadataItem] { items.filter { $0.state == .written }.map(\.item) }

    /// The optional items that were removed or had nothing to write.
    public var leftOutItems: [ItemReceipt] { items.filter { $0.state != .written } }

    /// The written optional items with their values.
    public var writtenReceipts: [ItemReceipt] { items.filter { $0.state == .written } }

    /// How many optional details the files hold, not counting the location, which has its own
    /// line in the summary.
    public var optionalDetailCount: Int { writtenItems.filter { $0 != .location }.count }

    /// What happened to the location: written, removed or nothing to write.
    public var location: ItemReceipt? { items.first { $0.item == .location } }

    /// Whether the files hold a location (GPS tags).
    public var holdsLocation: Bool { location?.state == .written }

    /// The shutter and ISO the camera reported, shown marked "Not in the files" when the files
    /// hold no exposure (Exposure Settings off); `nil` when the files hold the exposure or the
    /// camera reported neither (`docs/design/BUILD-SPEC.md`, 3.15, P2).
    public var exposureNotInFiles: CaptureReport? {
        guard exposure == nil, let capture, capture.exposureDuration != nil || capture.iso != nil else { return nil }
        return capture
    }

    /// The lens the photo was taken with, shown marked "Not in the files" when the files hold
    /// no lens name; `nil` when they hold one or the lens isn't known.
    public var lensNotInFiles: Lens.ID? {
        guard lensAndCamera?.lensModel == nil else { return nil }
        return capture?.lensID
    }

    /// Whether the photo has a RAW file, so the RAW Sensor Data group applies.
    public var rawFile: File? { files.first { $0.format == .raw } }
}

extension PhotoDetails {
    /// One finished file and what its read-back found.
    struct CheckedFile {
        /// The file as saved.
        let file: PhotoFile
        /// The file's read-back.
        let readBack: MetadataReadBack

        /// Pairs a file with its read-back.
        ///
        /// - Parameters:
        ///   - file: The file as saved.
        ///   - readBack: The file's read-back.
        init(file: PhotoFile, readBack: MetadataReadBack) {
            self.file = file
            self.readBack = readBack
        }
    }

    /// Tag numbers the details read (TIFF 6.0, EXIF 3.0, DNG 1.7).
    enum Tag {
        /// `ImageWidth`.
        static let imageWidth: UInt16 = 0x0100
        /// `ImageLength`.
        static let imageLength: UInt16 = 0x0101
        /// `BitsPerSample`.
        static let bitsPerSample: UInt16 = 0x0102
        /// `CFARepeatPatternDim`.
        static let cfaRepeatPatternDim: UInt16 = 0x828D
        /// `CFAPattern`.
        static let cfaPattern: UInt16 = 0x828E
        /// `BlackLevel`.
        static let blackLevel: UInt16 = 0xC61A
        /// `WhiteLevel`.
        static let whiteLevel: UInt16 = 0xC61D
        /// `OpcodeList1`, `OpcodeList2` and `OpcodeList3`.
        static let opcodeLists: Set<UInt16> = [0xC740, 0xC741, 0xC74E]
        /// `ExposureTime`.
        static let exposureTime: UInt16 = 0x829A
        /// `FNumber`.
        static let fNumber: UInt16 = 0x829D
        /// `PhotographicSensitivity`.
        static let iso: UInt16 = 0x8827
        /// `ExposureBiasValue`.
        static let exposureBias: UInt16 = 0x9204
        /// `FocalLength`.
        static let focalLength: UInt16 = 0x920A
        /// `WhiteBalance`.
        static let whiteBalance: UInt16 = 0xA403
        /// `Flash`.
        static let flash: UInt16 = 0x9209
        /// `PixelXDimension`.
        static let pixelXDimension: UInt16 = 0xA002
        /// `PixelYDimension`.
        static let pixelYDimension: UInt16 = 0xA003
        /// The Content Credentials manifest in a DNG (C2PA 2.1, A.3.3).
        static let contentCredentials: UInt16 = 0xCD41
        /// `MakerNote`.
        static let makerNote: UInt16 = 0x927C
        /// `FocalLengthIn35mmFilm`.
        static let equivalentFocalLength: UInt16 = 0xA405
        /// `ExposureMode`.
        static let exposureMode: UInt16 = 0xA402
        /// `ExposureProgram`.
        static let exposureProgram: UInt16 = 0x8822
        /// `MeteringMode`.
        static let meteringMode: UInt16 = 0x9207
        /// `BrightnessValue`.
        static let brightness: UInt16 = 0x9203
        /// `MaxApertureValue`.
        static let maxAperture: UInt16 = 0x9205
        /// `SubjectArea`.
        static let subjectArea: UInt16 = 0x9214
        /// `Compression`.
        static let compression: UInt16 = 0x0103
        /// `DNGVersion`, the first DNG tag: IFD0 tags from here up are DNG's (DNG 1.7, chapter 4).
        static let dngVersion: UInt16 = 0xC612
        /// `DefaultCropOrigin`.
        static let defaultCropOrigin: UInt16 = 0xC61F
        /// `DefaultCropSize`.
        static let defaultCropSize: UInt16 = 0xC620
        /// `AsShotNeutral`.
        static let asShotNeutral: UInt16 = 0xC628
        /// `BaselineExposure`.
        static let baselineExposure: UInt16 = 0xC62A
        /// `ActiveArea`.
        static let activeArea: UInt16 = 0xC68D
        /// `Make`.
        static let make: UInt16 = 0x010F
        /// `Model`.
        static let model: UInt16 = 0x0110
        /// `DateTime`.
        static let dateTime: UInt16 = 0x0132
        /// `Software`.
        static let software: UInt16 = 0x0131
        /// `Artist`.
        static let artist: UInt16 = 0x013B
        /// `Copyright`.
        static let copyright: UInt16 = 0x8298
        /// `DateTimeOriginal`.
        static let dateTimeOriginal: UInt16 = 0x9003
        /// `OffsetTimeOriginal`, then `OffsetTime`.
        static let offsetTimes: [UInt16] = [0x9011, 0x9010]
        /// `SubSecTimeOriginal`, then `SubSecTime`.
        static let subSecondTimes: [UInt16] = [0x9291, 0x9290]
        /// `LensMake`.
        static let lensMake: UInt16 = 0xA433
        /// `LensModel`.
        static let lensModel: UInt16 = 0xA434
        /// `UniqueCameraModel`.
        static let uniqueCameraModel: UInt16 = 0xC614
        /// GPS `GPSLatitudeRef`, `GPSLatitude`, `GPSLongitudeRef`, `GPSLongitude`,
        /// `GPSAltitudeRef` and `GPSAltitude` (EXIF 3.0, 4.6.6).
        static let gpsLatitudeRef: UInt16 = 0x0001
        /// `GPSLatitude`.
        static let gpsLatitude: UInt16 = 0x0002
        /// `GPSLongitudeRef`.
        static let gpsLongitudeRef: UInt16 = 0x0003
        /// `GPSLongitude`.
        static let gpsLongitude: UInt16 = 0x0004
        /// `GPSAltitudeRef`.
        static let gpsAltitudeRef: UInt16 = 0x0005
        /// `GPSAltitude`.
        static let gpsAltitude: UInt16 = 0x0006
    }

    /// The color names of TIFF/EP's `CFAPattern` codes: 0 red, 1 green, 2 blue, 3 cyan,
    /// 4 magenta, 5 yellow, 6 white (ISO 12234-2, "CFAPattern").
    static let colorFilterLetters: [Character] = ["R", "G", "B", "C", "M", "Y", "W"]

    /// Builds the details of one saved photo.
    ///
    /// - Parameters:
    ///   - files: Each saved file with its read-back, in the order they were built.
    ///   - plan: The metadata plan the files were written with.
    ///   - look: The look HEIF and JPEG were developed with.
    ///   - signature: The photo's signature status.
    ///   - timings: The measured timings.
    ///   - rawClipping: The clipping counted at capture time, or `nil`.
    ///   - distortionCorrection: The lens's distortion correction for a processed fallback, or
    ///     `nil`.
    ///   - options: The options the HEIF and JPEG copies were developed with.
    ///   - pairing: Which copy the person pairs with the RAW in Photos.
    ///   - capture: What the camera reported, or `nil`.
    /// - Returns: The details.
    static func build(
        files: [CheckedFile], plan: MetadataPlan, look: DevelopedLook, signature: SignatureStatus,
        timings: SaveTimings, rawClipping: RAWClippingResult? = nil, distortionCorrection: DistortionCorrection? = nil,
        options: DevelopedFileOptions = DevelopedFileOptions(), pairing: RAWPairing = .heif,
        capture: CaptureReport? = nil
    ) -> PhotoDetails {
        let inventories = files.map(\.readBack.file.inventory)
        let formats = Set(files.map(\.file.format))
        return PhotoDetails(
            files: files.map { fileDetails($0, look: look, options: options) },
            exposure: inventories.lazy.compactMap(exposure(in:)).first,
            items: MetadataItem.allCases.map { item in
                let state = state(of: item, settings: plan.settings, inventories: inventories)
                return ItemReceipt(
                    item: item, state: state, value: state == .written ? value(of: item, in: inventories) : nil)
            },
            lockedItems: lockedItems(for: formats), signature: signature, timings: timings, rawClipping: rawClipping,
            distortionCorrection: distortionCorrection, lensAndCamera: lensAndCamera(in: inventories),
            capture: capture, inPhotos: PhotosPairing(files: files.map(\.file), pairing: pairing),
            writesStandardFileTags: plan.settings.writesStandardFileTags)
    }

    /// One file's details.
    ///
    /// - Parameters:
    ///   - checked: The file and its read-back.
    ///   - look: The developed look.
    ///   - options: The options developed copies were made with.
    /// - Returns: The details.
    static func fileDetails(
        _ checked: CheckedFile, look: DevelopedLook, options: DevelopedFileOptions = DevelopedFileOptions()
    ) -> File {
        let file = checked.file
        let inventory = checked.readBack.file.inventory
        let image = checked.readBack.image
        let isRAW = file.format == .raw
        let width = isRAW ? integer(Tag.imageWidth, in: inventory) : image?.pixelWidth ?? integer(Tag.pixelXDimension, in: inventory, directory: .exif)
        let height = isRAW ? integer(Tag.imageLength, in: inventory) : image?.pixelHeight ?? integer(Tag.pixelYDimension, in: inventory, directory: .exif)
        let processing: Processing = isRAW ? .none : file.isProcessedByDevice ? .byDevice : .developed(look)
        let isDeveloped = !isRAW && !file.isProcessedByDevice
        return File(
            format: file.format, byteCount: file.data.count, pixelWidth: width, pixelHeight: height,
            bitDepth: isRAW ? integer(Tag.bitsPerSample, in: inventory) : image?.depth,
            colorFilterPattern: isRAW ? colorFilterPattern(in: inventory) : nil,
            blackLevels: isRAW ? values(Tag.blackLevel, in: inventory) : [],
            whiteLevels: isRAW ? values(Tag.whiteLevel, in: inventory) : [],
            storesLensCorrections: isRAW && inventory.tags.contains { $0.directory == .primary && Tag.opcodeLists.contains($0.tag) },
            processing: processing, contentCredentials: file.contentCredentials, contents: contents(of: inventory),
            entries: entries(of: inventory), rawStructure: isRAW ? rawStructure(in: inventory) : nil,
            colorSpace: isDeveloped ? options.colorSpace : nil,
            quality: isDeveloped ? options.quality(for: file.format) : nil)
    }

    /// The values of a tag in a directory, or none if the file doesn't have it.
    ///
    /// - Parameters:
    ///   - tag: The tag number.
    ///   - inventory: The file's read-back.
    ///   - directory: The directory. Defaults to IFD0.
    /// - Returns: The values.
    static func values(_ tag: UInt16, in inventory: MetadataInventory, directory: TIFFDirectory = .primary) -> [Double] {
        inventory.tags.first { $0.directory == directory && $0.tag == tag }?.values ?? []
    }

    /// The first value of a tag, or `nil`.
    ///
    /// - Parameters:
    ///   - tag: The tag number.
    ///   - inventory: The file's read-back.
    ///   - directory: The directory. Defaults to IFD0.
    /// - Returns: The value.
    static func value(_ tag: UInt16, in inventory: MetadataInventory, directory: TIFFDirectory = .primary) -> Double? {
        values(tag, in: inventory, directory: directory).first
    }

    /// The first value of a tag as a whole number, or `nil`.
    ///
    /// - Parameters:
    ///   - tag: The tag number.
    ///   - inventory: The file's read-back.
    ///   - directory: The directory. Defaults to IFD0.
    /// - Returns: The value.
    static func integer(_ tag: UInt16, in inventory: MetadataInventory, directory: TIFFDirectory = .primary) -> Int? {
        value(tag, in: inventory, directory: directory).map { Int($0) }
    }

    /// A DNG's color filter pattern as letters, row by row, such as `RGGB`, or `nil` when the
    /// pattern is missing, doesn't match its dimensions, or uses an unknown color code.
    ///
    /// - Parameter inventory: The DNG's read-back.
    /// - Returns: The pattern.
    static func colorFilterPattern(in inventory: MetadataInventory) -> String? {
        let dimensions = values(Tag.cfaRepeatPatternDim, in: inventory)
        let codes = values(Tag.cfaPattern, in: inventory)
        guard dimensions.count == 2, !codes.isEmpty, Int(dimensions[0] * dimensions[1]) == codes.count else { return nil }
        let letters = codes.map { Int($0) }.map { $0 < colorFilterLetters.count ? colorFilterLetters[$0] : nil }
        guard letters.allSatisfy({ $0 != nil }) else { return nil }
        return String(letters.compactMap { $0 })
    }

    /// The exposure a file's EXIF records, or `nil` when it records none of it.
    ///
    /// - Parameter inventory: The file's read-back.
    /// - Returns: The exposure.
    static func exposure(in inventory: MetadataInventory) -> Exposure? {
        func exif(_ tag: UInt16) -> Double? { value(tag, in: inventory, directory: .exif) }
        let whiteBalance: WhiteBalanceSetting? =
            switch exif(Tag.whiteBalance) {
            case 0: .automatic
            case 1: .manual
            default: nil
            }
        let exposure = Exposure(
            exposureTime: exif(Tag.exposureTime), iso: exif(Tag.iso), fNumber: exif(Tag.fNumber),
            focalLength: exif(Tag.focalLength), exposureBias: exif(Tag.exposureBias), whiteBalance: whiteBalance,
            flashFired: exif(Tag.flash).map { Int($0) & 1 == 1 },
            equivalentFocalLength: exif(Tag.equivalentFocalLength),
            exposureMode: exif(Tag.exposureMode).map { ExposureModeValue(code: Int($0)) },
            program: exif(Tag.exposureProgram).map { ExposureProgramValue(code: Int($0)) },
            metering: exif(Tag.meteringMode).map { MeteringValue(code: Int($0)) },
            brightness: exif(Tag.brightness),
            // APEX aperture value A is the f-number N with A = 2 log2(N) (EXIF 3.0, 4.6.5).
            largestAperture: exif(Tag.maxAperture).map { pow(2, $0 / 2) },
            subjectArea: values(Tag.subjectArea, in: inventory, directory: .exif))
        let isEmpty = [
            exposure.exposureTime, exposure.iso, exposure.fNumber, exposure.focalLength, exposure.exposureBias,
            exposure.equivalentFocalLength,
        ].allSatisfy { $0 == nil } && whiteBalance == nil && exposure.flashFired == nil && !exposure.hasMoreDetails
        return isEmpty ? nil : exposure
    }

    /// The names of everything a read-back found: each tag by its catalog name, then each
    /// container block and XMP property.
    ///
    /// - Parameter inventory: The read-back.
    /// - Returns: The names, in file order.
    static func contents(of inventory: MetadataInventory) -> [String] {
        inventory.tags.map(name(of:)) + inventory.blocks + inventory.xmpProperties.map(\.name)
    }

    /// A tag's specification name from ``MetadataField/catalog``, `C2PA manifest` for the Content
    /// Credentials tag, or its directory and hexadecimal number.
    ///
    /// - Parameter tag: The tag.
    /// - Returns: The name.
    static func name(of tag: MetadataInventory.Tag) -> String {
        if let field = MetadataField.catalog.first(where: { $0.directory == tag.directory && $0.tag == tag.tag }) {
            return field.name
        }
        if tag.directory == .primary && tag.tag == Tag.contentCredentials { return "C2PA manifest" }
        let number = String(tag.tag, radix: 16, uppercase: true)
        return "\(tag.directory.rawValue) 0x\(String(repeating: "0", count: max(0, 4 - number.count)))\(number)"
    }

    /// What happened to an optional item: written, removed by its switch, or nothing to write.
    ///
    /// An ASCII tag with empty text doesn't count as written: a DNG always carries `DateTime`,
    /// `Make`, `Model` and `Software`, empty when their switches are off (issue #65).
    ///
    /// - Parameters:
    ///   - item: The item.
    ///   - settings: The metadata choices the files were written with.
    ///   - inventories: Each file's read-back.
    /// - Returns: The state.
    static func state(
        of item: MetadataItem, settings: MetadataSettings, inventories: [MetadataInventory]
    ) -> ItemReceipt.State {
        guard settings.isOn(item) else { return .removed }
        let tags = inventories.flatMap(\.tags).filter { $0.text?.isEmpty != true }
        return tags.contains { holds(item, $0) } ? .written : .nothingToWrite
    }

    /// Whether a tag carries an item.
    ///
    /// - Parameters:
    ///   - item: The item.
    ///   - tag: A tag with a value.
    /// - Returns: `true` if the tag is one of the item's.
    static func holds(_ item: MetadataItem, _ tag: MetadataInventory.Tag) -> Bool {
        switch item {
        case .location:
            return tag.directory == .gps
        case .makerNotes:
            return tag.directory == .exif && tag.tag == Tag.makerNote
        case .exactCameraModel:
            return tag.tag == MetadataField.uniqueCameraModel.tag && tag.text != MetadataPlan.genericUniqueCameraModel
        case .appNameAndVersion, .systemVersion:
            guard tag.directory == .primary, tag.tag == MetadataField.software.tag, let text = tag.text else { return false }
            let hasAppName = text.hasPrefix(MetadataPlan.appName)
            return item == .appNameAndVersion ? hasAppName : MetadataPlan.systemVersion(fromSoftware: text) != nil
        default:
            return MetadataField.catalog.contains { field in
                field.directory == tag.directory && field.tag == tag.tag && field.group == .optional([item])
            }
        }
    }

    /// The locked items the saved formats keep.
    ///
    /// - Parameter formats: The saved formats.
    /// - Returns: The items, in `LockedMetadataItem.allCases` order.
    static func lockedItems(for formats: Set<PhotoFormat>) -> [LockedMetadataItem] {
        let hasRAW = formats.contains(.raw)
        let hasProcessed = formats.contains(.heif) || formats.contains(.jpeg)
        return LockedMetadataItem.allCases.filter { item in
            switch item {
            case .imageLayout, .orientation: true
            case .colorFilterPattern, .blackAndWhiteLevels, .colorCalibration, .dngVersion: hasRAW
            case .colorProfile: hasProcessed
            }
        }
    }
}
