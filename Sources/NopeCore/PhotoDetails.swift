import Foundation

/// "What's in this photo": the facts about one photo nope. just saved, read back from the
/// saved files (issue #53).
///
/// ``PhotoSaver`` builds it from each file's read-back (the project's own tag reader and
/// ImageIO), the metadata plan, the signer's manifest summary and the measured timings, and keeps
/// it in ``SavedPhoto/details``. Every value is what the file holds or what was measured; a
/// value the file doesn't hold is `nil` or empty, never estimated.
///
/// Privacy: built in memory from the just-saved photo and shown on screen only; nothing is
/// logged, stored or copied. nope. can't reopen older photos (add-only access), so details
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
        /// Whether a DNG stores lens correction instructions (opcode lists 1, 2 or 3). nope.
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
        public init(
            format: PhotoFormat, byteCount: Int, pixelWidth: Int?, pixelHeight: Int?, bitDepth: Int?,
            colorFilterPattern: String?, blackLevels: [Double], whiteLevels: [Double], storesLensCorrections: Bool,
            processing: Processing, contentCredentials: ContentCredentialsSummary?, contents: [String]
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
        }
    }

    /// What processing a file's pixels went through.
    public enum Processing: Equatable, Sendable {
        /// None by nope.: the sensor data as the camera delivered it (the DNG).
        case none
        /// Developed by nope. from the RAW, with this look.
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
        public init(
            exposureTime: Double?, iso: Double?, fNumber: Double?, focalLength: Double?, exposureBias: Double?,
            whiteBalance: WhiteBalanceSetting?, flashFired: Bool? = nil
        ) {
            self.exposureTime = exposureTime
            self.iso = iso
            self.fNumber = fNumber
            self.focalLength = focalLength
            self.exposureBias = exposureBias
            self.whiteBalance = whiteBalance
            self.flashFired = flashFired
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

        /// Creates a receipt line.
        ///
        /// - Parameters:
        ///   - item: The item.
        ///   - state: What happened to it.
        public init(item: MetadataItem, state: State) {
            self.item = item
            self.state = state
        }
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

    /// Creates details.
    ///
    /// - Parameters:
    ///   - files: Each file's details.
    ///   - exposure: The exposure as written.
    ///   - items: What happened to each optional item.
    ///   - lockedItems: The locked items kept.
    ///   - signature: The signature status.
    ///   - timings: The timings.
    public init(
        files: [File], exposure: Exposure?, items: [ItemReceipt], lockedItems: [LockedMetadataItem],
        signature: SignatureStatus, timings: SaveTimings
    ) {
        self.files = files
        self.exposure = exposure
        self.items = items
        self.lockedItems = lockedItems
        self.signature = signature
        self.timings = timings
    }

    /// The optional items that were written.
    public var writtenItems: [MetadataItem] { items.filter { $0.state == .written }.map(\.item) }

    /// The optional items that were removed or had nothing to write.
    public var leftOutItems: [ItemReceipt] { items.filter { $0.state != .written } }
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
    /// - Returns: The details.
    static func build(
        files: [CheckedFile], plan: MetadataPlan, look: DevelopedLook, signature: SignatureStatus,
        timings: SaveTimings
    ) -> PhotoDetails {
        let inventories = files.map(\.readBack.file.inventory)
        let formats = Set(files.map(\.file.format))
        return PhotoDetails(
            files: files.map { fileDetails($0, look: look) },
            exposure: inventories.lazy.compactMap(exposure(in:)).first,
            items: MetadataItem.allCases.map { item in
                ItemReceipt(item: item, state: state(of: item, settings: plan.settings, inventories: inventories))
            },
            lockedItems: lockedItems(for: formats), signature: signature, timings: timings)
    }

    /// One file's details.
    ///
    /// - Parameters:
    ///   - checked: The file and its read-back.
    ///   - look: The developed look.
    /// - Returns: The details.
    static func fileDetails(_ checked: CheckedFile, look: DevelopedLook) -> File {
        let file = checked.file
        let inventory = checked.readBack.file.inventory
        let image = checked.readBack.image
        let isRAW = file.format == .raw
        let width = isRAW ? integer(Tag.imageWidth, in: inventory) : image?.pixelWidth ?? integer(Tag.pixelXDimension, in: inventory, directory: .exif)
        let height = isRAW ? integer(Tag.imageLength, in: inventory) : image?.pixelHeight ?? integer(Tag.pixelYDimension, in: inventory, directory: .exif)
        let processing: Processing = isRAW ? .none : file.isProcessedByDevice ? .byDevice : .developed(look)
        return File(
            format: file.format, byteCount: file.data.count, pixelWidth: width, pixelHeight: height,
            bitDepth: isRAW ? integer(Tag.bitsPerSample, in: inventory) : image?.depth,
            colorFilterPattern: isRAW ? colorFilterPattern(in: inventory) : nil,
            blackLevels: isRAW ? values(Tag.blackLevel, in: inventory) : [],
            whiteLevels: isRAW ? values(Tag.whiteLevel, in: inventory) : [],
            storesLensCorrections: isRAW && inventory.tags.contains { $0.directory == .primary && Tag.opcodeLists.contains($0.tag) },
            processing: processing, contentCredentials: file.contentCredentials, contents: contents(of: inventory))
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
            flashFired: exif(Tag.flash).map { Int($0) & 1 == 1 })
        let isEmpty = [exposure.exposureTime, exposure.iso, exposure.fNumber, exposure.focalLength, exposure.exposureBias]
            .allSatisfy { $0 == nil } && whiteBalance == nil && exposure.flashFired == nil
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
