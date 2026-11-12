import Foundation

/// A metadata group the photo can't work without, so it has no switch.
///
/// Each case is a row of the "Locked" table in `docs/PRIVACY.md`. None of them identifies the
/// person or links their photos.
public enum LockedMetadata: String, CaseIterable, Codable, Hashable, Sendable {
    /// Image size, bit depth, compression, data layout, crop and resolution. Without them the
    /// file can't be read at all.
    case imageStructure
    /// The color filter pattern: which sensor pixels are red, green and blue. Without it the RAW
    /// has no color.
    case colorFilterPattern
    /// Black and white levels, baseline exposure and the sensor's noise profile. Without them
    /// shadows and highlights come out wrong.
    case levels
    /// Color matrices, calibration illuminants and the as-shot white balance. Without them
    /// colors are wrong.
    case colorCalibration
    /// The DNG version. Editors refuse a DNG without it.
    case dngVersion
    /// Orientation. Without it the photo shows sideways or upside down.
    case orientation
    /// The color profile of a HEIF or JPEG. Without it colors look washed out or oversaturated.
    case colorProfile
}

/// Where ImageIO puts a value in a property dictionary: a sub-dictionary such as `{Exif}` and a
/// key such as `ExposureTime`, or a top-level key.
///
/// The strings are the values of ImageIO's `kCGImageProperty…` constants
/// (`ImageIO/CGImageProperties.h`); `NopeDevelopTests` checks each one against the constant.
public struct ImageIOKey: Hashable, Sendable, CustomStringConvertible {
    /// The sub-dictionary, such as `{Exif}`, or `nil` for a top-level key.
    public let dictionary: String?
    /// The key.
    public let key: String

    /// Creates a key.
    ///
    /// - Parameters:
    ///   - dictionary: The sub-dictionary, or `nil` for a top-level key.
    ///   - key: The key.
    public init(_ dictionary: String?, _ key: String) {
        self.dictionary = dictionary
        self.key = key
    }

    /// The key as `{Exif}.ExposureTime`, or the bare key at the top level.
    public var description: String {
        dictionary.map { "\($0).\(key)" } ?? key
    }
}

/// One tag on the allowlist: where it lives in the file, its ImageIO names, which switch (or
/// lock) controls it, and which formats may carry it.
///
/// ``MetadataField/catalog`` lists every one; nothing outside it is ever written or accepted.
public struct MetadataField: Hashable, Sendable {
    /// What controls a field.
    public enum Group: Hashable, Sendable {
        /// Written when any of these optional items is on.
        case optional(Set<MetadataItem>)
        /// Always written where the format has it.
        case locked(LockedMetadata)
    }

    /// The tag's name in its specification, such as `ExposureTime`.
    public let name: String
    /// The TIFF directory the tag is in.
    public let directory: TIFFDirectory
    /// The tag number.
    public let tag: UInt16
    /// The tag's ImageIO keys. Values are copied from the system's metadata under each key that
    /// is present; the read-back accepts each one.
    public let imageIOKeys: [ImageIOKey]
    /// The switch or lock that controls the field.
    public let group: Group
    /// The formats that may carry the field.
    public let formats: Set<PhotoFormat>

    /// Creates a field.
    ///
    /// - Parameters:
    ///   - name: The tag's name.
    ///   - directory: The TIFF directory.
    ///   - tag: The tag number.
    ///   - imageIOKeys: The ImageIO keys.
    ///   - group: The switch or lock.
    ///   - formats: The formats that may carry it.
    init(
        _ name: String, _ directory: TIFFDirectory, _ tag: UInt16, _ imageIOKeys: [ImageIOKey], _ group: Group,
        _ formats: Set<PhotoFormat>
    ) {
        self.name = name
        self.directory = directory
        self.tag = tag
        self.imageIOKeys = imageIOKeys
        self.group = group
        self.formats = formats
    }
}

extension MetadataField {
    /// ImageIO's TIFF dictionary, `kCGImagePropertyTIFFDictionary`.
    static let tiff = "{TIFF}"
    /// ImageIO's EXIF dictionary, `kCGImagePropertyExifDictionary`.
    static let exif = "{Exif}"
    /// ImageIO's auxiliary EXIF dictionary, `kCGImagePropertyExifAuxDictionary`.
    static let exifAux = "{ExifAux}"
    /// ImageIO's DNG dictionary, `kCGImagePropertyDNGDictionary`.
    static let dng = "{DNG}"
    /// ImageIO's GPS dictionary, `kCGImagePropertyGPSDictionary`.
    static let gps = "{GPS}"
    /// ImageIO's Apple maker note dictionary, `kCGImagePropertyMakerAppleDictionary`.
    static let makerApple = "{MakerApple}"
    /// ImageIO's IPTC dictionary, `kCGImagePropertyIPTCDictionary`. ImageIO mirrors the artist
    /// and copyright into it when it writes a HEIF.
    static let iptc = "{IPTC}"

    /// Every format.
    private static let all: Set<PhotoFormat> = [.raw, .heif, .jpeg]
    /// DNG only.
    private static let rawOnly: Set<PhotoFormat> = [.raw]
    /// HEIF and JPEG.
    private static let processed: Set<PhotoFormat> = [.heif, .jpeg]

    /// A locked field.
    private static func locked(
        _ name: String, _ directory: TIFFDirectory, _ tag: UInt16, _ keys: [ImageIOKey], _ lock: LockedMetadata,
        _ formats: Set<PhotoFormat>
    ) -> MetadataField {
        MetadataField(name, directory, tag, keys, .locked(lock), formats)
    }

    /// A field controlled by one optional item.
    private static func item(
        _ name: String, _ directory: TIFFDirectory, _ tag: UInt16, _ keys: [ImageIOKey], _ item: MetadataItem,
        _ formats: Set<PhotoFormat>
    ) -> MetadataField {
        MetadataField(name, directory, tag, keys, .optional([item]), formats)
    }

    /// An EXIF exposure field, written by every format when exposure settings are on.
    private static func exposure(_ name: String, _ tag: UInt16, key: String? = nil) -> MetadataField {
        item(name, .exif, tag, [ImageIOKey(exif, key ?? name)], .exposureSettings, all)
    }

    /// The `Software` tag (`0x0131`), shared by the system version and the app name switches.
    public static let software = MetadataField(
        "Software", .primary, 0x0131, [ImageIOKey(tiff, "Software")], .optional([.systemVersion, .appNameAndVersion]),
        all)

    /// The DNG `UniqueCameraModel` tag (`0xC614`). Required by DNG, so a DNG always carries it;
    /// its value is generic when ``MetadataItem/exactCameraModel`` is off.
    public static let uniqueCameraModel = item(
        "UniqueCameraModel", .primary, 0xC614, [ImageIOKey(dng, "UniqueCameraModel")], .exactCameraModel, rawOnly)

    /// The `Artist` tag (`0x013B`), which ImageIO also reports as IPTC `Byline`.
    public static let artist = item(
        "Artist", .primary, 0x013B, [ImageIOKey(tiff, "Artist"), ImageIOKey(iptc, "Byline")], .nameAndCopyright, all)

    /// The `Copyright` tag (`0x8298`), which ImageIO also reports as IPTC `CopyrightNotice`.
    public static let copyright = item(
        "Copyright", .primary, 0x8298, [ImageIOKey(tiff, "Copyright"), ImageIOKey(iptc, "CopyrightNotice")],
        .nameAndCopyright, all)

    /// The `Orientation` tag (`0x0112`), also ImageIO's top-level `Orientation`.
    public static let orientation = locked(
        "Orientation", .primary, 0x0112, [ImageIOKey(tiff, "Orientation"), ImageIOKey(nil, "Orientation")],
        .orientation, all)

    /// The EXIF directory pointer (`0x8769`).
    static let exifPointer = locked("ExifIFD", .primary, 0x8769, [], .imageStructure, all)

    /// The GPS directory pointer (`0x8825`). The GPS directory's own tags are allowed as a
    /// whole when location is on (``MetadataPlan``).
    static let gpsPointer = item("GPSInfoIFD", .primary, 0x8825, [], .location, all)

    /// The maker note (`0x927C`). ImageIO shows Apple's as the `{MakerApple}` dictionary.
    static let makerNote = item("MakerNote", .exif, 0x927C, [], .makerNotes, all)

    /// Every field nope. may write, with its switch or lock and its formats. Built from the
    /// device tag check (`docs/PRIVACY.md`, "Tag check") and the TIFF 6.0, EXIF 3.0 and DNG 1.7
    /// tag tables. A tag that isn't here is never written and fails the read-back.
    public static let catalog: [MetadataField] = structure + raw + capture + [
        software, uniqueCameraModel, artist, copyright, orientation, exifPointer, gpsPointer, makerNote,
    ]

    /// The locked image structure fields.
    private static let structure: [MetadataField] = [
        locked("NewSubfileType", .primary, 0x00FE, [], .imageStructure, rawOnly),
        locked("ImageWidth", .primary, 0x0100, [], .imageStructure, rawOnly),
        locked("ImageLength", .primary, 0x0101, [], .imageStructure, rawOnly),
        locked("BitsPerSample", .primary, 0x0102, [], .imageStructure, rawOnly),
        locked("Compression", .primary, 0x0103, [ImageIOKey(tiff, "Compression")], .imageStructure, rawOnly),
        locked(
            "PhotometricInterpretation", .primary, 0x0106, [ImageIOKey(tiff, "PhotometricInterpretation")],
            .imageStructure, rawOnly),
        locked("StripOffsets", .primary, 0x0111, [], .imageStructure, rawOnly),
        locked("SamplesPerPixel", .primary, 0x0115, [], .imageStructure, rawOnly),
        locked("RowsPerStrip", .primary, 0x0116, [], .imageStructure, rawOnly),
        locked("StripByteCounts", .primary, 0x0117, [], .imageStructure, rawOnly),
        locked("XResolution", .primary, 0x011A, [ImageIOKey(tiff, "XResolution")], .imageStructure, processed),
        locked("YResolution", .primary, 0x011B, [ImageIOKey(tiff, "YResolution")], .imageStructure, processed),
        locked("PlanarConfiguration", .primary, 0x011C, [], .imageStructure, rawOnly),
        locked("ResolutionUnit", .primary, 0x0128, [ImageIOKey(tiff, "ResolutionUnit")], .imageStructure, processed),
        locked("TileWidth", .primary, 0x0142, [ImageIOKey(tiff, "TileWidth")], .imageStructure, [.raw, .heif]),
        locked("TileLength", .primary, 0x0143, [ImageIOKey(tiff, "TileLength")], .imageStructure, [.raw, .heif]),
        locked("TileOffsets", .primary, 0x0144, [], .imageStructure, rawOnly),
        locked("TileByteCounts", .primary, 0x0145, [], .imageStructure, rawOnly),
        locked("YCbCrPositioning", .primary, 0x0213, [], .imageStructure, processed),
        locked("ExifVersion", .exif, 0x9000, [ImageIOKey(exif, "ExifVersion")], .imageStructure, all),
        locked(
            "ComponentsConfiguration", .exif, 0x9101, [ImageIOKey(exif, "ComponentsConfiguration")], .imageStructure,
            processed),
        locked("FlashpixVersion", .exif, 0xA000, [ImageIOKey(exif, "FlashPixVersion")], .imageStructure, processed),
        locked("ColorSpace", .exif, 0xA001, [ImageIOKey(exif, "ColorSpace")], .colorProfile, processed),
        locked("PixelXDimension", .exif, 0xA002, [ImageIOKey(exif, "PixelXDimension")], .imageStructure, all),
        locked("PixelYDimension", .exif, 0xA003, [ImageIOKey(exif, "PixelYDimension")], .imageStructure, all),
    ]

    /// The DNG fields that describe the RAW data.
    private static let raw: [MetadataField] = [
        locked("CFARepeatPatternDim", .primary, 0x828D, [], .colorFilterPattern, rawOnly),
        locked("CFAPattern", .primary, 0x828E, [ImageIOKey(exif, "CFAPattern")], .colorFilterPattern, rawOnly),
        locked("DNGVersion", .primary, 0xC612, [ImageIOKey(dng, "DNGVersion")], .dngVersion, rawOnly),
        locked("DNGBackwardVersion", .primary, 0xC613, [ImageIOKey(dng, "DNGBackwardVersion")], .dngVersion, rawOnly),
        locked("CFAPlaneColor", .primary, 0xC616, [ImageIOKey(dng, "CFAPlaneColor")], .colorFilterPattern, rawOnly),
        locked("CFALayout", .primary, 0xC617, [ImageIOKey(dng, "CFALayout")], .colorFilterPattern, rawOnly),
        locked("BlackLevelRepeatDim", .primary, 0xC619, [ImageIOKey(dng, "BlackLevelRepeatDim")], .levels, rawOnly),
        locked("BlackLevel", .primary, 0xC61A, [ImageIOKey(dng, "BlackLevel")], .levels, rawOnly),
        locked("WhiteLevel", .primary, 0xC61D, [ImageIOKey(dng, "WhiteLevel")], .levels, rawOnly),
        locked("DefaultCropOrigin", .primary, 0xC61F, [ImageIOKey(dng, "DefaultCropOrigin")], .imageStructure, rawOnly),
        locked("DefaultCropSize", .primary, 0xC620, [ImageIOKey(dng, "DefaultCropSize")], .imageStructure, rawOnly),
        locked("ColorMatrix1", .primary, 0xC621, [ImageIOKey(dng, "ColorMatrix1")], .colorCalibration, rawOnly),
        locked("ColorMatrix2", .primary, 0xC622, [ImageIOKey(dng, "ColorMatrix2")], .colorCalibration, rawOnly),
        locked("AsShotNeutral", .primary, 0xC628, [ImageIOKey(dng, "AsShotNeutral")], .colorCalibration, rawOnly),
        locked("BaselineExposure", .primary, 0xC62A, [ImageIOKey(dng, "BaselineExposure")], .levels, rawOnly),
        locked(
            "CalibrationIlluminant1", .primary, 0xC65A, [ImageIOKey(dng, "CalibrationIlluminant1")],
            .colorCalibration, rawOnly),
        locked(
            "CalibrationIlluminant2", .primary, 0xC65B, [ImageIOKey(dng, "CalibrationIlluminant2")],
            .colorCalibration, rawOnly),
        locked("ActiveArea", .primary, 0xC68D, [ImageIOKey(dng, "ActiveArea")], .imageStructure, rawOnly),
        locked(
            "NoiseReductionApplied", .primary, 0xC6F7, [ImageIOKey(dng, "NoiseReductionApplied")], .levels, rawOnly),
        locked("NoiseProfile", .primary, 0xC761, [ImageIOKey(dng, "NoiseProfile")], .levels, rawOnly),
        item("OpcodeList1", .primary, 0xC740, [ImageIOKey(dng, "OpcodeList1")], .lensCorrections, rawOnly),
        // ImageIO names these two `DNGOpcodeList2` and `DNGOpcodeList3` (the values of
        // kCGImagePropertyDNGOpcodeList2 and 3), unlike OpcodeList1.
        item("OpcodeList2", .primary, 0xC741, [ImageIOKey(dng, "DNGOpcodeList2")], .lensCorrections, rawOnly),
        item("OpcodeList3", .primary, 0xC74E, [ImageIOKey(dng, "DNGOpcodeList3")], .lensCorrections, rawOnly),
        item("LensInfo", .primary, 0xC630, [ImageIOKey(dng, "LensInfo")], .lensMakeAndModel, rawOnly),
    ]

    /// The fields that describe the capture: dates, camera, lens and exposure.
    private static let capture: [MetadataField] = [
        item("DateTime", .primary, 0x0132, [ImageIOKey(tiff, "DateTime")], .dateAndTime, all),
        item("DateTimeOriginal", .exif, 0x9003, [ImageIOKey(exif, "DateTimeOriginal")], .dateAndTime, all),
        item("DateTimeDigitized", .exif, 0x9004, [ImageIOKey(exif, "DateTimeDigitized")], .dateAndTime, all),
        item("SubSecTime", .exif, 0x9290, [ImageIOKey(exif, "SubsecTime")], .subSecondTime, all),
        item("SubSecTimeOriginal", .exif, 0x9291, [ImageIOKey(exif, "SubsecTimeOriginal")], .subSecondTime, all),
        item("SubSecTimeDigitized", .exif, 0x9292, [ImageIOKey(exif, "SubsecTimeDigitized")], .subSecondTime, all),
        item("OffsetTime", .exif, 0x9010, [ImageIOKey(exif, "OffsetTime")], .timeZone, all),
        item("OffsetTimeOriginal", .exif, 0x9011, [ImageIOKey(exif, "OffsetTimeOriginal")], .timeZone, all),
        item("OffsetTimeDigitized", .exif, 0x9012, [ImageIOKey(exif, "OffsetTimeDigitized")], .timeZone, all),
        item("Make", .primary, 0x010F, [ImageIOKey(tiff, "Make")], .cameraMakeAndModel, all),
        item("Model", .primary, 0x0110, [ImageIOKey(tiff, "Model")], .cameraMakeAndModel, all),
        item("HostComputer", .primary, 0x013C, [ImageIOKey(tiff, "HostComputer")], .cameraMakeAndModel, all),
        item(
            "LensSpecification", .exif, 0xA432, [ImageIOKey(exif, "LensSpecification"), ImageIOKey(exifAux, "LensInfo")],
            .lensMakeAndModel, all),
        item("LensMake", .exif, 0xA433, [ImageIOKey(exif, "LensMake")], .lensMakeAndModel, all),
        item(
            "LensModel", .exif, 0xA434, [ImageIOKey(exif, "LensModel"), ImageIOKey(exifAux, "LensModel")],
            .lensMakeAndModel, all),
        exposure("ExposureTime", 0x829A),
        exposure("FNumber", 0x829D),
        exposure("ExposureProgram", 0x8822),
        exposure("PhotographicSensitivity", 0x8827, key: "ISOSpeedRatings"),
        exposure("SensitivityType", 0x8830),
        exposure("ShutterSpeedValue", 0x9201),
        exposure("ApertureValue", 0x9202),
        exposure("BrightnessValue", 0x9203),
        exposure("ExposureBiasValue", 0x9204),
        exposure("MaxApertureValue", 0x9205),
        exposure("MeteringMode", 0x9207),
        exposure("Flash", 0x9209),
        exposure("FocalLength", 0x920A),
        exposure("SubjectArea", 0x9214),
        exposure("SensingMethod", 0xA217),
        exposure("SceneType", 0xA301),
        exposure("ExposureMode", 0xA402),
        exposure("WhiteBalance", 0xA403),
        exposure("FocalLengthIn35mmFilm", 0xA405, key: "FocalLenIn35mmFilm"),
        exposure("SceneCaptureType", 0xA406),
    ]
}
