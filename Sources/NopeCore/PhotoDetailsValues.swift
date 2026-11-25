import Foundation

// The values "What's in This Photo" shows beyond the files' sizes and the exposure basics
// (`docs/design/BUILD-SPEC.md`, section 6, items 16 and 17): named EXIF codes, the lens and
// camera names, a DNG's structure, each written item's value, every entry of the read-back,
// what the camera reported and how Photos groups a RAW pair.
//
// Privacy: everything here comes from the read-back of the files just saved
// (`SavedPhoto.metadata`), the settings they were saved with and what the camera reported, all
// already in memory. Nothing new is read, stored, logged or copied; identifying values are
// marked so an interface hides them until the person asks.

extension PhotoDetails {
    /// The EXIF `ExposureMode` value (EXIF 3.0, tag `0xA402`).
    public enum ExposureModeValue: Equatable, Sendable {
        /// 0: auto exposure.
        case auto
        /// 1: manual exposure.
        case manual
        /// 2: auto bracket.
        case autoBracket
        /// A code EXIF 3.0 doesn't name, shown as its number.
        case other(Int)

        /// The value of a code.
        ///
        /// - Parameter code: The tag's value.
        init(code: Int) {
            self =
                switch code {
                case 0: .auto
                case 1: .manual
                case 2: .autoBracket
                default: .other(code)
                }
        }
    }

    /// The EXIF `ExposureProgram` value (EXIF 3.0, tag `0x8822`).
    public enum ExposureProgramValue: Equatable, Sendable {
        /// 0: not defined.
        case notDefined
        /// 1: manual.
        case manual
        /// 2: normal program.
        case normal
        /// 3: aperture priority.
        case aperturePriority
        /// 4: shutter priority.
        case shutterPriority
        /// 5: creative program (biased toward depth of field).
        case creative
        /// 6: action program (biased toward a fast shutter).
        case action
        /// 7: portrait mode.
        case portrait
        /// 8: landscape mode.
        case landscape
        /// A code EXIF 3.0 doesn't name, shown as its number.
        case other(Int)

        /// The named values, by code.
        static let named: [ExposureProgramValue] = [
            .notDefined, .manual, .normal, .aperturePriority, .shutterPriority, .creative, .action, .portrait, .landscape,
        ]

        /// The value of a code.
        ///
        /// - Parameter code: The tag's value.
        init(code: Int) {
            self = Self.named.indices.contains(code) ? Self.named[code] : .other(code)
        }
    }

    /// The EXIF `MeteringMode` value (EXIF 3.0, tag `0x9207`).
    public enum MeteringValue: Equatable, Sendable {
        /// 0: unknown.
        case unknown
        /// 1: average.
        case average
        /// 2: center-weighted average, the app's Center metering.
        case centerWeighted
        /// 3: spot, the app's Spot metering.
        case spot
        /// 4: multi-spot.
        case multiSpot
        /// 5: pattern.
        case pattern
        /// 6: partial.
        case partial
        /// 255: other.
        case otherMode
        /// A code EXIF 3.0 doesn't name, shown as its number.
        case other(Int)

        /// The named values of codes 0 to 6.
        static let named: [MeteringValue] = [.unknown, .average, .centerWeighted, .spot, .multiSpot, .pattern, .partial]

        /// The value of a code.
        ///
        /// - Parameter code: The tag's value.
        init(code: Int) {
            if code == 255 {
                self = .otherMode
            } else {
                self = Self.named.indices.contains(code) ? Self.named[code] : .other(code)
            }
        }
    }

    /// A DNG's `Compression` value (TIFF 6.0 and DNG 1.7, "Compression").
    public enum RAWCompression: Equatable, Sendable {
        /// 1: uncompressed.
        case uncompressed
        /// 7: lossless JPEG, as the DNG specification uses code 7 for RAW data.
        case losslessJPEG
        /// 34892: lossy JPEG (DNG 1.4).
        case lossyJPEG
        /// 52546: JPEG XL (DNG 1.7).
        case jpegXL
        /// A code this list doesn't name, shown as its number.
        case other(Int)

        /// The value of a code.
        ///
        /// - Parameter code: The tag's value.
        init(code: Int) {
            self =
                switch code {
                case 1: .uncompressed
                case 7: .losslessJPEG
                case 34892: .lossyJPEG
                case 52546: .jpegXL
                default: .other(code)
                }
        }

        /// Whether the RAW data keeps every value of the sensor's samples.
        public var isLossless: Bool { self == .uncompressed || self == .losslessJPEG }
    }

    /// A DNG's structure, from its IFD0 tags (DNG 1.7, chapter 4). Each list is empty when the
    /// file doesn't have the tag.
    public struct RAWStructure: Equatable, Sendable {
        /// `ActiveArea`: top, left, bottom and right of the area of the sensor with image data.
        public let activeArea: [Double]
        /// `DefaultCropOrigin`: the crop's origin, horizontal then vertical.
        public let defaultCropOrigin: [Double]
        /// `DefaultCropSize`: the crop's width and height.
        public let defaultCropSize: [Double]
        /// `Compression`, or `nil` when the file doesn't say.
        public let compression: RAWCompression?
        /// `DNGVersion`: four numbers, such as 1, 4, 0, 0.
        public let dngVersion: [Int]
        /// `BaselineExposure`, in EV, or `nil`.
        public let baselineExposure: Double?
        /// `AsShotNeutral`: the white balance at capture, as one value per color plane.
        public let asShotNeutral: [Double]

        /// Creates a DNG structure.
        ///
        /// - Parameters:
        ///   - activeArea: The active area.
        ///   - defaultCropOrigin: The default crop's origin.
        ///   - defaultCropSize: The default crop's size.
        ///   - compression: The compression, or `nil`.
        ///   - dngVersion: The DNG version's four numbers.
        ///   - baselineExposure: The baseline exposure in EV, or `nil`.
        ///   - asShotNeutral: The as-shot neutral.
        public init(
            activeArea: [Double], defaultCropOrigin: [Double], defaultCropSize: [Double], compression: RAWCompression?,
            dngVersion: [Int], baselineExposure: Double?, asShotNeutral: [Double]
        ) {
            self.activeArea = activeArea
            self.defaultCropOrigin = defaultCropOrigin
            self.defaultCropSize = defaultCropSize
            self.compression = compression
            self.dngVersion = dngVersion
            self.baselineExposure = baselineExposure
            self.asShotNeutral = asShotNeutral
        }

        /// The DNG version as written, such as "1.4" or "1.7.1": its four numbers without the
        /// trailing zeros, keeping at least two; `nil` without a version.
        public var dngVersionText: String? {
            guard !dngVersion.isEmpty else { return nil }
            var parts = dngVersion
            while parts.count > 2, parts.last == 0 { parts.removeLast() }
            return parts.map(String.init).joined(separator: ".")
        }
    }

    /// The lens and camera names the files hold (EXIF `LensModel` and `LensMake`, TIFF `Make`
    /// and `Model`), each `nil` when no file holds it with text.
    public struct LensAndCamera: Equatable, Sendable {
        /// `LensModel`, such as "iPhone 16 Pro Max back camera 6.86mm f/1.78".
        public let lensModel: String?
        /// `LensMake`, such as "Apple".
        public let lensMake: String?
        /// `Make`, such as "Apple".
        public let make: String?
        /// `Model`, such as "iPhone 16 Pro Max".
        public let model: String?

        /// Creates the names.
        ///
        /// - Parameters:
        ///   - lensModel: The lens model, or `nil`.
        ///   - lensMake: The lens make, or `nil`.
        ///   - make: The camera make, or `nil`.
        ///   - model: The camera model, or `nil`.
        public init(lensModel: String?, lensMake: String?, make: String?, model: String?) {
            self.lensModel = lensModel
            self.lensMake = lensMake
            self.make = make
            self.model = model
        }

        /// The camera as make and model, such as "Apple iPhone 16 Pro Max"; the model alone
        /// when it already starts with the make; `nil` with neither.
        public var camera: String? {
            switch (make, model) {
            case (let make?, let model?): model.hasPrefix(make) ? model : "\(make) \(model)"
            case (let make?, nil): make
            case (nil, let model): model
            }
        }
    }

    /// A written item's value as the files hold it.
    public enum ItemValue: Equatable, Sendable {
        /// Text as written, such as a camera name or a version.
        case text(String)
        /// A date and time, read from `DateTimeOriginal` (or `DateTime`) with the file's time
        /// offset, or the device's time zone when the file has none, for the interface to format.
        case date(Date)
        /// A place, from the GPS tags.
        case location(PhotoLocation)
    }

    /// What the camera reported for the photo, kept in memory with the details for the session
    /// (`docs/PRIVACY.md`, "Last photo and its details"). Shown only where the files don't
    /// hold the same value, marked "Not in the files".
    public struct CaptureReport: Equatable, Sendable {
        /// The exposure duration the camera reported, in seconds, or `nil`.
        public let exposureDuration: Double?
        /// The ISO the camera reported, or `nil`.
        public let iso: Double?
        /// The lens the photo was taken with.
        public let lensID: Lens.ID

        /// Creates a report.
        ///
        /// - Parameters:
        ///   - exposureDuration: The exposure duration in seconds, or `nil`.
        ///   - iso: The ISO, or `nil`.
        ///   - lensID: The lens.
        public init(exposureDuration: Double?, iso: Double?, lensID: Lens.ID) {
            self.exposureDuration = exposureDuration
            self.iso = iso
            self.lensID = lensID
        }

        /// The report of a captured photo.
        ///
        /// - Parameter photo: The photo.
        public init(_ photo: CapturedPhoto) {
            self.init(exposureDuration: photo.exposureDuration, iso: photo.iso, lensID: photo.lensID)
        }
    }

    /// How a RAW and a copy were added to Photos: as one photo, the RAW with its paired copy,
    /// and any other copy as a photo of its own (``PhotoLibraryAsset/assets(for:pairing:)``).
    public struct PhotosPairing: Equatable, Sendable {
        /// The copy paired with the RAW.
        public let pairedFormat: PhotoFormat
        /// The copy saved as a photo of its own, or `nil`.
        public let separateFormat: PhotoFormat?

        /// Creates a pairing.
        ///
        /// - Parameters:
        ///   - pairedFormat: The copy paired with the RAW.
        ///   - separateFormat: The copy saved on its own, or `nil`.
        public init(pairedFormat: PhotoFormat, separateFormat: PhotoFormat?) {
            self.pairedFormat = pairedFormat
            self.separateFormat = separateFormat
        }

        /// The pairing of the saved files, as the library was asked to add them, or `nil`
        /// without a RAW and a copy.
        ///
        /// - Parameters:
        ///   - files: The saved files.
        ///   - pairing: The person's pairing choice.
        init?(files: [PhotoFile], pairing: RAWPairing) {
            let assets = PhotoLibraryAsset.assets(for: files, pairing: pairing)
            guard let pair = assets.first(where: { $0.alternate != nil }), let alternate = pair.alternate else {
                return nil
            }
            self.init(
                pairedFormat: alternate.format,
                separateFormat: assets.first { $0.alternate == nil && $0.primary.format != .raw }?.primary.format)
        }
    }

    /// One tag, block or XMP property of a file, as the Every Tag page lists it.
    public struct TagEntry: Equatable, Sendable, Identifiable {
        /// Where an entry lives in the file.
        public enum Place: CaseIterable, Equatable, Sendable {
            /// IFD0 below `DNGVersion` (`0xC612`), and the image directories after it: the TIFF
            /// tags.
            case tiff
            /// The EXIF directory and its interoperability directory.
            case exif
            /// The GPS directory.
            case gps
            /// IFD0 from `DNGVersion` up, without the Content Credentials tag.
            case dng
            /// The XMP properties.
            case xmp
            /// The container's blocks: JPEG segments, HEIF boxes, items and properties.
            case fileStructure
            /// The Content Credentials manifest: the DNG tag or the HEIF or JPEG block.
            case contentCredentials
        }

        /// What decides whether the file holds an entry.
        public enum Control: Equatable, Sendable {
            /// The switch for this optional item.
            case setting(MetadataItem)
            /// Nothing: every file of this format holds it.
            case alwaysSaved
            /// The app's Content Credentials signature.
            case signature
        }

        /// A stable identifier: the entry's place and number or name.
        public let id: String
        /// The specification's name, such as `ExposureTime`.
        public let name: String
        /// Where it lives.
        public let place: Place
        /// Its value.
        public let value: MetadataComparison.Value
        /// The TIFF tag number, or `nil` for a block or an XMP property.
        public let tagNumber: UInt16?
        /// What decides whether the file holds it.
        public let control: Control
        /// Whether the value identifies the person or the device, as in ``MetadataComparison``.
        public let isIdentifying: Bool

        /// Creates an entry.
        ///
        /// - Parameters:
        ///   - id: The identifier.
        ///   - name: The name.
        ///   - place: Where it lives.
        ///   - value: Its value.
        ///   - tagNumber: The tag number, or `nil`.
        ///   - control: What decides whether the file holds it.
        ///   - isIdentifying: Whether to hide the value until asked.
        public init(
            id: String, name: String, place: Place, value: MetadataComparison.Value, tagNumber: UInt16?,
            control: Control, isIdentifying: Bool
        ) {
            self.id = id
            self.name = name
            self.place = place
            self.value = value
            self.tagNumber = tagNumber
            self.control = control
            self.isIdentifying = isIdentifying
        }

        /// Whether the value is hidden until the person asks: an identifying value the reader
        /// could read.
        public var hidesValue: Bool { isIdentifying && value != .present }

        /// The tag number as four hexadecimal digits, such as `0x829A`; `nil` for a block or an
        /// XMP property.
        public var tagNumberText: String? {
            tagNumber.map { number in
                let digits = String(number, radix: 16, uppercase: true)
                return "0x" + String(repeating: "0", count: 4 - digits.count) + digits
            }
        }
    }
}

extension PhotoDetails {
    /// Every entry of a read-back, from ``MetadataComparison/items(in:)``.
    ///
    /// - Parameter inventory: The read-back.
    /// - Returns: The entries, in file order.
    static func entries(of inventory: MetadataInventory) -> [TagEntry] {
        MetadataComparison.items(in: inventory).map { item in
            let control: TagEntry.Control =
                if item.isSignature {
                    .signature
                } else if let switchItem = item.item ?? mirroredItem(item) {
                    .setting(switchItem)
                } else {
                    .alwaysSaved
                }
            return TagEntry(
                id: item.id, name: item.name, place: place(of: item), value: item.value, tagNumber: item.tagNumber,
                control: control, isIdentifying: item.isIdentifying)
        }
    }

    /// The switch of an XMP property that mirrors a TIFF tag (`CreatorTool`, `creator`,
    /// `rights`), judged by its value as the tag would be.
    ///
    /// - Parameter item: An item.
    /// - Returns: The switch, or `nil` for anything else.
    static func mirroredItem(_ item: MetadataComparison.Item) -> MetadataItem? {
        guard case .xmp(let namespace) = item.kind, case .text(let text) = item.value,
            let field = MetadataPlan.xmpMirrors.first(where: { $0.name == .init(namespace, item.name) })?.field
        else { return nil }
        let tag = MetadataInventory.Tag(directory: field.directory, tag: field.tag, text: text)
        return MetadataItem.allCases.first { holds($0, tag) }
    }

    /// An item's place in the file.
    ///
    /// - Parameter item: The item.
    /// - Returns: The place.
    static func place(of item: MetadataComparison.Item) -> TagEntry.Place {
        if item.isSignature { return .contentCredentials }
        switch item.kind {
        case .block: return .fileStructure
        case .xmp: return .xmp
        case .tag(.exif), .tag(.interoperability): return .exif
        case .tag(.gps): return .gps
        case .tag(.primary): return item.tagNumber.map { $0 >= Tag.dngVersion } == true ? .dng : .tiff
        case .tag: return .tiff
        }
    }

    /// A DNG's structure.
    ///
    /// - Parameter inventory: The DNG's read-back.
    /// - Returns: The structure.
    static func rawStructure(in inventory: MetadataInventory) -> RAWStructure {
        RAWStructure(
            activeArea: values(Tag.activeArea, in: inventory),
            defaultCropOrigin: values(Tag.defaultCropOrigin, in: inventory),
            defaultCropSize: values(Tag.defaultCropSize, in: inventory),
            compression: integer(Tag.compression, in: inventory).map(RAWCompression.init(code:)),
            dngVersion: values(Tag.dngVersion, in: inventory).map { Int($0) },
            baselineExposure: value(Tag.baselineExposure, in: inventory),
            asShotNeutral: values(Tag.asShotNeutral, in: inventory))
    }

    /// The first non-empty text of a tag in any of the files.
    ///
    /// - Parameters:
    ///   - tag: The tag number.
    ///   - directory: The directory.
    ///   - inventories: The read-backs.
    /// - Returns: The text, or `nil`.
    static func text(_ tag: UInt16, _ directory: TIFFDirectory, in inventories: [MetadataInventory]) -> String? {
        inventories.lazy.flatMap(\.tags).first { $0.directory == directory && $0.tag == tag && $0.text?.isEmpty == false }?
            .text
    }

    /// The lens and camera names, or `nil` when the files hold none.
    ///
    /// - Parameter inventories: The read-backs.
    /// - Returns: The names.
    static func lensAndCamera(in inventories: [MetadataInventory]) -> LensAndCamera? {
        let names = LensAndCamera(
            lensModel: text(Tag.lensModel, .exif, in: inventories), lensMake: text(Tag.lensMake, .exif, in: inventories),
            make: text(Tag.make, .primary, in: inventories), model: text(Tag.model, .primary, in: inventories))
        return [names.lensModel, names.lensMake, names.make, names.model].allSatisfy { $0 == nil } ? nil : names
    }

    /// A written item's value, or `nil` when it has none to show.
    ///
    /// - Parameters:
    ///   - item: The item.
    ///   - inventories: The read-backs.
    /// - Returns: The value.
    static func value(of item: MetadataItem, in inventories: [MetadataInventory]) -> ItemValue? {
        func joined(_ parts: String?...) -> ItemValue? {
            let present = parts.compactMap { $0 }
            return present.isEmpty ? nil : .text(present.joined(separator: ", "))
        }
        let software = text(Tag.software, .primary, in: inventories)
        switch item {
        case .location:
            return location(in: inventories).map(ItemValue.location)
        case .dateAndTime:
            return date(in: inventories).map(ItemValue.date)
        case .subSecondTime:
            return joined(Tag.subSecondTimes.lazy.compactMap { text($0, .exif, in: inventories) }.first)
        case .timeZone:
            return joined(Tag.offsetTimes.lazy.compactMap { text($0, .exif, in: inventories) }.first)
        case .cameraMakeAndModel:
            return joined(lensAndCamera(in: inventories)?.camera)
        case .lensMakeAndModel:
            return joined(text(Tag.lensMake, .exif, in: inventories), text(Tag.lensModel, .exif, in: inventories))
        case .exactCameraModel:
            return joined(text(Tag.uniqueCameraModel, .primary, in: inventories))
        case .systemVersion:
            return joined(MetadataPlan.systemVersion(fromSoftware: software))
        case .appNameAndVersion:
            // "Photivra Nope Camera 1.0.0 (27.2.1)": the app's part, before the system's.
            return joined(software?.components(separatedBy: " (").first)
        case .nameAndCopyright:
            return joined(text(Tag.artist, .primary, in: inventories), text(Tag.copyright, .primary, in: inventories))
        case .lensCorrections, .exposureSettings, .makerNotes:
            return nil
        }
    }

    /// The photo's date and time: `DateTimeOriginal`, or `DateTime`, as "YYYY:MM:DD HH:MM:SS"
    /// (EXIF 3.0, 4.6.5), in the time zone of `OffsetTimeOriginal` or `OffsetTime` ("+01:00"),
    /// or the device's time zone when the file has no offset; `nil` for a blank or malformed date.
    ///
    /// - Parameter inventories: The read-backs.
    /// - Returns: The date.
    static func date(in inventories: [MetadataInventory]) -> Date? {
        guard let written = text(Tag.dateTimeOriginal, .exif, in: inventories) ?? text(Tag.dateTime, .primary, in: inventories)
        else { return nil }
        let numbers = written.split(whereSeparator: { $0 == ":" || $0 == " " }).compactMap { Int($0) }
        guard numbers.count == 6 else { return nil }
        let offset = Tag.offsetTimes.lazy.compactMap { text($0, .exif, in: inventories) }.first.flatMap(timeZone(offset:))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = offset ?? .current
        return calendar.date(
            from: DateComponents(
                year: numbers[0], month: numbers[1], day: numbers[2], hour: numbers[3], minute: numbers[4],
                second: numbers[5]))
    }

    /// A time zone from an EXIF offset such as "+01:00" or "-05:30", or `nil` if malformed.
    ///
    /// - Parameter offset: The offset text.
    /// - Returns: The time zone.
    static func timeZone(offset: String) -> TimeZone? {
        let sign: Int? =
            switch offset.first {
            case "+": 1
            case "-": -1
            default: nil
            }
        let parts = offset.dropFirst().split(separator: ":").compactMap { Int($0) }
        guard let sign, parts.count == 2 else { return nil }
        return TimeZone(secondsFromGMT: sign * (parts[0] * 3600 + parts[1] * 60))
    }

    /// The location the GPS tags hold: latitude and longitude as degrees, minutes and seconds
    /// with their references, and the altitude below sea level when `GPSAltitudeRef` is 1
    /// (EXIF 3.0, 4.6.6); `nil` without a latitude and longitude.
    ///
    /// - Parameter inventories: The read-backs.
    /// - Returns: The location.
    static func location(in inventories: [MetadataInventory]) -> PhotoLocation? {
        guard let gps = inventories.first(where: { $0.tags.contains { $0.directory == .gps } }) else { return nil }
        func degrees(_ tag: UInt16, negativeRef: String, refTag: UInt16) -> Double? {
            let parts = values(tag, in: gps, directory: .gps)
            guard parts.count == 3 else { return nil }
            let magnitude = parts[0] + parts[1] / 60 + parts[2] / 3600
            return text(refTag, .gps, in: [gps]) == negativeRef ? -magnitude : magnitude
        }
        guard let latitude = degrees(Tag.gpsLatitude, negativeRef: "S", refTag: Tag.gpsLatitudeRef),
            let longitude = degrees(Tag.gpsLongitude, negativeRef: "W", refTag: Tag.gpsLongitudeRef)
        else { return nil }
        let altitude = value(Tag.gpsAltitude, in: gps, directory: .gps).map { meters in
            value(Tag.gpsAltitudeRef, in: gps, directory: .gps) == 1 ? -meters : meters
        }
        return PhotoLocation(latitude: latitude, longitude: longitude, altitude: altitude)
    }
}
