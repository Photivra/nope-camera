// dump-tags.swift: lists every metadata tag in DNG, TIFF, HEIC and JPEG files, on a Mac.
//
// Usage:
//   swift scripts/dump-tags.swift [--redact] [--out <folder>] <file-or-folder>...
//   swift scripts/dump-tags.swift --self-test
//
// For each file it reports:
//   (a) every ImageIO property dictionary (CGImageSourceCopyPropertiesAtIndex), including
//       {MakerApple}, {Exif}, {TIFF}, {DNG}, {GPS} and {IPTC}, and every XMP tag
//       (CGImageSourceCopyMetadataAtIndex, enumerated recursively);
//   (b) for DNG and TIFF, a walk of the raw TIFF structure: every IFD entry's tag ID, name,
//       type, count and a short value preview, following SubIFDs (0x014A), the EXIF IFD
//       (0x8769), the GPS IFD (0x8825) and the interoperability IFD (0xA005).
// The text report goes to standard output and to <out>/tags-report.txt; the same data goes to
// <out>/tags-report.json. <out> defaults to the first input's folder.
//
// The reports contain serial numbers and other identifiers from the files. Never commit them;
// pass --redact to replace identifying values before sharing a report. See docs/TESTING.md,
// "Tag check".
//
// Native frameworks only (Foundation, ImageIO). Reads local files; never uploads or fetches.
// The TIFF walker is written from the TIFF 6.0, EXIF 3.0 and DNG 1.7 specifications.

import Foundation
import ImageIO

// MARK: - TIFF structure walk

/// A TIFF field type (TIFF 6.0 section 2, plus the IFD type from TIFF Technical Note 1).
struct TIFFFieldType {
    let name: String
    let size: Int

    static func of(_ code: UInt16) -> TIFFFieldType? {
        switch code {
        case 1: TIFFFieldType(name: "BYTE", size: 1)
        case 2: TIFFFieldType(name: "ASCII", size: 1)
        case 3: TIFFFieldType(name: "SHORT", size: 2)
        case 4: TIFFFieldType(name: "LONG", size: 4)
        case 5: TIFFFieldType(name: "RATIONAL", size: 8)
        case 6: TIFFFieldType(name: "SBYTE", size: 1)
        case 7: TIFFFieldType(name: "UNDEFINED", size: 1)
        case 8: TIFFFieldType(name: "SSHORT", size: 2)
        case 9: TIFFFieldType(name: "SLONG", size: 4)
        case 10: TIFFFieldType(name: "SRATIONAL", size: 8)
        case 11: TIFFFieldType(name: "FLOAT", size: 4)
        case 12: TIFFFieldType(name: "DOUBLE", size: 8)
        case 13: TIFFFieldType(name: "IFD", size: 4)
        default: nil
        }
    }
}

/// Which tag table names an IFD's entries: GPS and interoperability tags reuse low numbers.
enum IFDKind: String {
    case image, exif, gps, interoperability
}

/// One IFD entry.
struct TIFFEntry: Codable, Equatable {
    let tag: UInt16
    let name: String
    let type: String
    let count: UInt32
    let preview: String
}

/// One IFD: where it is in the file and its entries.
struct TIFFDirectory: Codable, Equatable {
    let path: String
    let offset: UInt32
    let entries: [TIFFEntry]
}

/// The result of walking a TIFF file.
struct TIFFWalk: Codable, Equatable {
    var byteOrder = ""
    var directories: [TIFFDirectory] = []
    var problems: [String] = []
}

/// Walks the IFDs of a classic TIFF file (DNG is TIFF-based). Bounds-checked: malformed input
/// produces entries in `problems`, never a crash. BigTIFF is reported, not walked.
struct TIFFWalker {
    /// Stops runaway files: no real DNG comes near these.
    static let maximumDirectories = 256
    static let maximumEntriesPerDirectory = 4096
    static let previewValueLimit = 8
    static let previewByteLimit = 16
    static let previewTextLimit = 64

    /// Tags that hold identifiers; `--redact` hides their values.
    static let identifyingTags: Set<UInt16> = [0xA420, 0xA430, 0xA431, 0xA435, 0xC62F, 0xC65D, 0x927C]

    let bytes: [UInt8]
    let redact: Bool
    private var bigEndian = false
    private var visited = Set<UInt32>()
    private var result = TIFFWalk()

    init(bytes: [UInt8], redact: Bool = false) {
        self.bytes = bytes
        self.redact = redact
    }

    /// Walks the file from its header.
    static func walk(_ bytes: [UInt8], redact: Bool = false) -> TIFFWalk {
        var walker = TIFFWalker(bytes: bytes, redact: redact)
        walker.run()
        return walker.result
    }

    private mutating func run() {
        guard bytes.count >= 8 else { return result.problems.append("file shorter than a TIFF header") }
        switch (bytes[0], bytes[1]) {
        case (0x49, 0x49): bigEndian = false; result.byteOrder = "little-endian (II)"
        case (0x4D, 0x4D): bigEndian = true; result.byteOrder = "big-endian (MM)"
        default: return result.problems.append("not a TIFF byte order mark")
        }
        guard let magic = u16(2) else { return }
        if magic == 43 { return result.problems.append("BigTIFF is not supported") }
        guard magic == 42 else { return result.problems.append("TIFF magic is \(magic), not 42") }
        var offset = u32(4) ?? 0
        var index = 0
        while offset != 0 {
            guard let next = directory(at: offset, path: "IFD\(index)", kind: .image) else { break }
            offset = next
            index += 1
        }
    }

    /// Reads one IFD, recurses into its child IFDs, and returns the next-IFD offset.
    private mutating func directory(at offset: UInt32, path: String, kind: IFDKind) -> UInt32? {
        guard result.directories.count < Self.maximumDirectories else {
            result.problems.append("\(path): directory limit reached")
            return nil
        }
        guard visited.insert(offset).inserted else {
            result.problems.append("\(path): offset \(offset) already visited (loop)")
            return nil
        }
        guard let count = u16(Int(offset)), count <= Self.maximumEntriesPerDirectory else {
            result.problems.append("\(path): unreadable entry count at offset \(offset)")
            return nil
        }
        var entries: [TIFFEntry] = []
        var children: [(UInt32, String, IFDKind)] = []
        for index in 0..<Int(count) {
            let entryOffset = Int(offset) + 2 + index * 12
            guard let tag = u16(entryOffset), let typeCode = u16(entryOffset + 2),
                let valueCount = u32(entryOffset + 4)
            else {
                result.problems.append("\(path): entry \(index) is past the end of the file")
                break
            }
            let name = Self.name(of: tag, kind: kind)
            guard let type = TIFFFieldType.of(typeCode) else {
                entries.append(TIFFEntry(tag: tag, name: name, type: "type \(typeCode)", count: valueCount, preview: "?"))
                continue
            }
            let length = Int(valueCount) * type.size
            let valueOffset = length <= 4 ? entryOffset + 8 : Int(u32(entryOffset + 8) ?? UInt32.max)
            let inBounds = length >= 0 && valueOffset <= bytes.count && length <= bytes.count - valueOffset
            var preview = inBounds ? self.preview(type: type, at: valueOffset, count: Int(valueCount)) : "<out of bounds>"
            if redact && (Self.identifyingTags.contains(tag) || kind == .gps) {
                preview = "<redacted>"
            }
            entries.append(TIFFEntry(tag: tag, name: name, type: type.name, count: valueCount, preview: preview))
            guard inBounds, let child = Self.childKind(of: tag, in: kind) else { continue }
            for (number, childOffset) in offsets(type: type, at: valueOffset, count: Int(valueCount)).enumerated() {
                let suffix = valueCount > 1 ? "[\(number)]" : ""
                children.append((childOffset, "\(path)/\(name)\(suffix)", child))
            }
        }
        result.directories.append(TIFFDirectory(path: path, offset: offset, entries: entries))
        for (childOffset, childPath, childKind) in children {
            var next = directory(at: childOffset, path: childPath, kind: childKind)
            var number = 1
            // SubIFDs may chain further IFDs; EXIF and GPS IFDs normally end with 0.
            while let nextOffset = next, nextOffset != 0 {
                next = directory(at: nextOffset, path: "\(childPath)+\(number)", kind: childKind)
                number += 1
            }
        }
        return u32(Int(offset) + 2 + Int(count) * 12)
    }

    /// The kind of IFD a pointer tag leads to, or `nil` if the tag isn't a pointer.
    static func childKind(of tag: UInt16, in kind: IFDKind) -> IFDKind? {
        guard kind == .image || kind == .exif else { return nil }
        switch tag {
        case 0x014A: return .image
        case 0x8769: return .exif
        case 0x8825: return .gps
        case 0xA005: return .interoperability
        default: return nil
        }
    }

    private func offsets(type: TIFFFieldType, at offset: Int, count: Int) -> [UInt32] {
        (0..<count).compactMap { index in
            type.size == 2 ? u16(offset + index * 2).map(UInt32.init) : (type.size == 4 ? u32(offset + index * 4) : nil)
        }
    }

    private func preview(type: TIFFFieldType, at offset: Int, count: Int) -> String {
        switch type.name {
        case "ASCII":
            let text = bytes[offset..<offset + count].prefix { $0 != 0 }
            let string = String(decoding: text.prefix(Self.previewTextLimit), as: UTF8.self)
            return "\"\(string)\"" + (text.count > Self.previewTextLimit ? "…" : "")
        case "BYTE", "SBYTE", "UNDEFINED":
            let hex = bytes[offset..<offset + min(count, Self.previewByteLimit)].map { String(format: "%02x", $0) }
            return hex.joined(separator: " ") + (count > Self.previewByteLimit ? " … (\(count) bytes)" : "")
        default:
            let shown = (0..<min(count, Self.previewValueLimit)).map { number($0, type: type, at: offset) }
            return shown.joined(separator: ", ") + (count > Self.previewValueLimit ? ", … (\(count) values)" : "")
        }
    }

    private func number(_ index: Int, type: TIFFFieldType, at offset: Int) -> String {
        let position = offset + index * type.size
        switch type.name {
        case "SHORT": return "\(u16(position) ?? 0)"
        case "SSHORT": return "\(Int16(bitPattern: u16(position) ?? 0))"
        case "LONG", "IFD": return "\(u32(position) ?? 0)"
        case "SLONG": return "\(Int32(bitPattern: u32(position) ?? 0))"
        case "RATIONAL": return "\(u32(position) ?? 0)/\(u32(position + 4) ?? 0)"
        case "SRATIONAL":
            return "\(Int32(bitPattern: u32(position) ?? 0))/\(Int32(bitPattern: u32(position + 4) ?? 0))"
        case "FLOAT": return "\(Float(bitPattern: u32(position) ?? 0))"
        case "DOUBLE":
            let high = UInt64(u32(bigEndian ? position : position + 4) ?? 0)
            let low = UInt64(u32(bigEndian ? position + 4 : position) ?? 0)
            return "\(Double(bitPattern: high << 32 | low))"
        default: return "?"
        }
    }

    func u16(_ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        let (a, b) = (UInt16(bytes[offset]), UInt16(bytes[offset + 1]))
        return bigEndian ? a << 8 | b : b << 8 | a
    }

    func u32(_ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        let values = bytes[offset..<offset + 4].map(UInt32.init)
        return bigEndian
            ? values[0] << 24 | values[1] << 16 | values[2] << 8 | values[3]
            : values[3] << 24 | values[2] << 16 | values[1] << 8 | values[0]
    }

    /// The tag's name from TIFF 6.0, EXIF 3.0 or DNG 1.7, or "Unknown".
    static func name(of tag: UInt16, kind: IFDKind) -> String {
        switch kind {
        case .gps: return gpsTagNames[tag] ?? "Unknown"
        case .interoperability: return interoperabilityTagNames[tag] ?? "Unknown"
        case .image, .exif: return tagNames[tag] ?? "Unknown"
        }
    }

    static let interoperabilityTagNames: [UInt16: String] = [
        0x0001: "InteroperabilityIndex", 0x0002: "InteroperabilityVersion",
    ]

    static let gpsTagNames: [UInt16: String] = [
        0x0000: "GPSVersionID", 0x0001: "GPSLatitudeRef", 0x0002: "GPSLatitude", 0x0003: "GPSLongitudeRef",
        0x0004: "GPSLongitude", 0x0005: "GPSAltitudeRef", 0x0006: "GPSAltitude", 0x0007: "GPSTimeStamp",
        0x0008: "GPSSatellites", 0x0009: "GPSStatus", 0x000A: "GPSMeasureMode", 0x000B: "GPSDOP",
        0x000C: "GPSSpeedRef", 0x000D: "GPSSpeed", 0x000E: "GPSTrackRef", 0x000F: "GPSTrack",
        0x0010: "GPSImgDirectionRef", 0x0011: "GPSImgDirection", 0x0012: "GPSMapDatum",
        0x0013: "GPSDestLatitudeRef", 0x0014: "GPSDestLatitude", 0x0015: "GPSDestLongitudeRef",
        0x0016: "GPSDestLongitude", 0x0017: "GPSDestBearingRef", 0x0018: "GPSDestBearing",
        0x0019: "GPSDestDistanceRef", 0x001A: "GPSDestDistance", 0x001B: "GPSProcessingMethod",
        0x001C: "GPSAreaInformation", 0x001D: "GPSDateStamp", 0x001E: "GPSDifferential",
        0x001F: "GPSHPositioningError",
    ]

    static let tagNames: [UInt16: String] = [
        // TIFF 6.0 and TIFF/EP
        0x00FE: "NewSubfileType", 0x00FF: "SubfileType", 0x0100: "ImageWidth", 0x0101: "ImageLength",
        0x0102: "BitsPerSample", 0x0103: "Compression", 0x0106: "PhotometricInterpretation",
        0x010A: "FillOrder", 0x010D: "DocumentName", 0x010E: "ImageDescription", 0x010F: "Make",
        0x0110: "Model", 0x0111: "StripOffsets", 0x0112: "Orientation", 0x0115: "SamplesPerPixel",
        0x0116: "RowsPerStrip", 0x0117: "StripByteCounts", 0x011A: "XResolution", 0x011B: "YResolution",
        0x011C: "PlanarConfiguration", 0x0128: "ResolutionUnit", 0x0131: "Software", 0x0132: "DateTime",
        0x013B: "Artist", 0x013C: "HostComputer", 0x013D: "Predictor", 0x0142: "TileWidth",
        0x0143: "TileLength", 0x0144: "TileOffsets", 0x0145: "TileByteCounts", 0x014A: "SubIFDs",
        0x0152: "ExtraSamples", 0x0153: "SampleFormat", 0x015B: "JPEGTables",
        0x0201: "JPEGInterchangeFormat", 0x0202: "JPEGInterchangeFormatLength",
        0x0211: "YCbCrCoefficients", 0x0212: "YCbCrSubSampling", 0x0213: "YCbCrPositioning",
        0x0214: "ReferenceBlackWhite", 0x02BC: "XMP", 0x828D: "CFARepeatPatternDim",
        0x828E: "CFAPattern", 0x8298: "Copyright", 0x83BB: "IPTC-NAA", 0x8649: "ImageResources",
        0x8769: "ExifIFD", 0x8773: "InterColorProfile", 0x8825: "GPSInfoIFD", 0x9216: "TIFF-EPStandardID",
        // EXIF 3.0
        0x829A: "ExposureTime", 0x829D: "FNumber", 0x8822: "ExposureProgram", 0x8824: "SpectralSensitivity",
        0x8827: "PhotographicSensitivity", 0x8828: "OECF", 0x8830: "SensitivityType",
        0x8831: "StandardOutputSensitivity", 0x8832: "RecommendedExposureIndex", 0x8833: "ISOSpeed",
        0x9000: "ExifVersion", 0x9003: "DateTimeOriginal", 0x9004: "DateTimeDigitized",
        0x9010: "OffsetTime", 0x9011: "OffsetTimeOriginal", 0x9012: "OffsetTimeDigitized",
        0x9101: "ComponentsConfiguration", 0x9102: "CompressedBitsPerPixel", 0x9201: "ShutterSpeedValue",
        0x9202: "ApertureValue", 0x9203: "BrightnessValue", 0x9204: "ExposureBiasValue",
        0x9205: "MaxApertureValue", 0x9206: "SubjectDistance", 0x9207: "MeteringMode", 0x9208: "LightSource",
        0x9209: "Flash", 0x920A: "FocalLength", 0x9214: "SubjectArea", 0x927C: "MakerNote",
        0x9286: "UserComment", 0x9290: "SubSecTime", 0x9291: "SubSecTimeOriginal",
        0x9292: "SubSecTimeDigitized", 0x9400: "Temperature", 0x9401: "Humidity", 0x9402: "Pressure",
        0x9403: "WaterDepth", 0x9404: "Acceleration", 0x9405: "CameraElevationAngle",
        0xA000: "FlashpixVersion", 0xA001: "ColorSpace", 0xA002: "PixelXDimension",
        0xA003: "PixelYDimension", 0xA004: "RelatedSoundFile", 0xA005: "InteroperabilityIFD",
        0xA20B: "FlashEnergy", 0xA20E: "FocalPlaneXResolution", 0xA20F: "FocalPlaneYResolution",
        0xA210: "FocalPlaneResolutionUnit", 0xA214: "SubjectLocation", 0xA215: "ExposureIndex",
        0xA217: "SensingMethod", 0xA300: "FileSource", 0xA301: "SceneType", 0xA302: "CFAPattern",
        0xA401: "CustomRendered", 0xA402: "ExposureMode", 0xA403: "WhiteBalance",
        0xA404: "DigitalZoomRatio", 0xA405: "FocalLengthIn35mmFilm", 0xA406: "SceneCaptureType",
        0xA407: "GainControl", 0xA408: "Contrast", 0xA409: "Saturation", 0xA40A: "Sharpness",
        0xA40B: "DeviceSettingDescription", 0xA40C: "SubjectDistanceRange", 0xA420: "ImageUniqueID",
        0xA430: "CameraOwnerName", 0xA431: "BodySerialNumber", 0xA432: "LensSpecification",
        0xA433: "LensMake", 0xA434: "LensModel", 0xA435: "LensSerialNumber", 0xA436: "ImageTitle",
        0xA437: "Photographer", 0xA438: "ImageEditor", 0xA439: "CameraFirmware",
        0xA43A: "RAWDevelopingSoftware", 0xA43B: "ImageEditingSoftware", 0xA43C: "MetadataEditingSoftware",
        0xA460: "CompositeImage", 0xA461: "SourceImageNumberOfCompositeImage",
        0xA462: "SourceExposureTimesOfCompositeImage", 0xA500: "Gamma",
        // DNG 1.7
        0xC612: "DNGVersion", 0xC613: "DNGBackwardVersion", 0xC614: "UniqueCameraModel",
        0xC615: "LocalizedCameraModel", 0xC616: "CFAPlaneColor", 0xC617: "CFALayout",
        0xC618: "LinearizationTable", 0xC619: "BlackLevelRepeatDim", 0xC61A: "BlackLevel",
        0xC61B: "BlackLevelDeltaH", 0xC61C: "BlackLevelDeltaV", 0xC61D: "WhiteLevel", 0xC61E: "DefaultScale",
        0xC61F: "DefaultCropOrigin", 0xC620: "DefaultCropSize", 0xC621: "ColorMatrix1",
        0xC622: "ColorMatrix2", 0xC623: "CameraCalibration1", 0xC624: "CameraCalibration2",
        0xC625: "ReductionMatrix1", 0xC626: "ReductionMatrix2", 0xC627: "AnalogBalance",
        0xC628: "AsShotNeutral", 0xC629: "AsShotWhiteXY", 0xC62A: "BaselineExposure",
        0xC62B: "BaselineNoise", 0xC62C: "BaselineSharpness", 0xC62D: "BayerGreenSplit",
        0xC62E: "LinearResponseLimit", 0xC62F: "CameraSerialNumber", 0xC630: "LensInfo",
        0xC631: "ChromaBlurRadius", 0xC632: "AntiAliasStrength", 0xC633: "ShadowScale",
        0xC634: "DNGPrivateData", 0xC635: "MakerNoteSafety", 0xC65A: "CalibrationIlluminant1",
        0xC65B: "CalibrationIlluminant2", 0xC65C: "BestQualityScale", 0xC65D: "RawDataUniqueID",
        0xC68B: "OriginalRawFileName", 0xC68C: "OriginalRawFileData", 0xC68D: "ActiveArea",
        0xC68E: "MaskedAreas", 0xC68F: "AsShotICCProfile", 0xC690: "AsShotPreProfileMatrix",
        0xC691: "CurrentICCProfile", 0xC692: "CurrentPreProfileMatrix", 0xC6BF: "ColorimetricReference",
        0xC6F3: "CameraCalibrationSignature", 0xC6F4: "ProfileCalibrationSignature",
        0xC6F5: "ExtraCameraProfiles", 0xC6F6: "AsShotProfileName", 0xC6F7: "NoiseReductionApplied",
        0xC6F8: "ProfileName", 0xC6F9: "ProfileHueSatMapDims", 0xC6FA: "ProfileHueSatMapData1",
        0xC6FB: "ProfileHueSatMapData2", 0xC6FC: "ProfileToneCurve", 0xC6FD: "ProfileEmbedPolicy",
        0xC6FE: "ProfileCopyright", 0xC714: "ForwardMatrix1", 0xC715: "ForwardMatrix2",
        0xC716: "PreviewApplicationName", 0xC717: "PreviewApplicationVersion",
        0xC718: "PreviewSettingsName", 0xC719: "PreviewSettingsDigest", 0xC71A: "PreviewColorSpace",
        0xC71B: "PreviewDateTime", 0xC71C: "RawImageDigest", 0xC71D: "OriginalRawFileDigest",
        0xC71E: "SubTileBlockSize", 0xC71F: "RowInterleaveFactor", 0xC725: "ProfileLookTableDims",
        0xC726: "ProfileLookTableData", 0xC740: "OpcodeList1", 0xC741: "OpcodeList2",
        0xC74E: "OpcodeList3", 0xC761: "NoiseProfile", 0xC763: "TimeCodes", 0xC764: "FrameRate",
        0xC772: "TStop", 0xC789: "ReelName", 0xC791: "OriginalDefaultFinalSize",
        0xC792: "OriginalBestQualityFinalSize", 0xC793: "OriginalDefaultCropSize", 0xC7A1: "CameraLabel",
        0xC7A3: "ProfileHueSatMapEncoding", 0xC7A4: "ProfileLookTableEncoding",
        0xC7A5: "BaselineExposureOffset", 0xC7A6: "DefaultBlackRender", 0xC7A7: "NewRawImageDigest",
        0xC7A8: "RawToPreviewGain", 0xC7B5: "DefaultUserCrop", 0xCD2D: "DepthFormat", 0xCD2E: "DepthNear",
        0xCD2F: "DepthFar", 0xCD30: "DepthUnits", 0xCD31: "DepthMeasureType", 0xCD32: "EnhanceParams",
        0xCD33: "ProfileGainTableMap", 0xCD34: "SemanticName", 0xCD35: "SemanticInstanceID",
        0xCD36: "CalibrationIlluminant3", 0xCD37: "CameraCalibration3", 0xCD38: "ColorMatrix3",
        0xCD39: "ForwardMatrix3", 0xCD3A: "IlluminantData1", 0xCD3B: "IlluminantData2",
        0xCD3C: "IlluminantData3", 0xCD3D: "MaskSubArea", 0xCD3E: "ProfileHueSatMapData3",
        0xCD3F: "ReductionMatrix3", 0xCD40: "RGBTables",
    ]
}

// MARK: - ImageIO properties and XMP

/// Fragments of property names whose values `--redact` hides.
let identifyingKeyFragments = ["serial", "uniqueid", "owner"]

/// Converts an ImageIO value to something JSONSerialization accepts, redacting if asked.
func jsonValue(_ value: Any, key: String = "", redact: Bool) -> Any {
    if redact && identifyingKeyFragments.contains(where: key.lowercased().contains) { return "<redacted>" }
    switch value {
    case let dictionary as [String: Any]:
        let hideAll = redact && (key == "{GPS}" || key == "{MakerApple}")
        return dictionary.reduce(into: [String: Any]()) {
            $0[$1.key] = hideAll ? "<redacted>" : jsonValue($1.value, key: $1.key, redact: redact)
        }
    case let array as [Any]: return array.map { jsonValue($0, key: key, redact: redact) }
    case let string as String: return string
    case let number as NSNumber: return number.doubleValue.isFinite ? number : "\(number)"
    case let data as Data:
        return "<\(data.count) bytes: \(data.prefix(16).map { String(format: "%02x", $0) }.joined())>"
    default: return "\(value)"
    }
}

/// Every ImageIO property dictionary and XMP tag of one file.
func imageIOReport(_ url: URL, redact: Bool) -> [String: Any] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return ["error": "ImageIO can't open the file"] }
    var report: [String: Any] = ["type": CGImageSourceGetType(source) as String? ?? "unknown"]
    if let container = CGImageSourceCopyProperties(source, nil) as? [String: Any] {
        report["containerProperties"] = jsonValue(container, redact: redact)
    }
    var images: [[String: Any]] = []
    for index in 0..<CGImageSourceGetCount(source) {
        var image: [String: Any] = ["index": index]
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] {
            image["properties"] = jsonValue(properties, redact: redact)
        }
        var xmp: [[String: String]] = []
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil) {
            let options = [kCGImageMetadataEnumerateRecursively: true] as CFDictionary
            CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, options) { path, tag in
                let value = CGImageMetadataTagCopyValue(tag).map { "\($0)" } ?? ""
                let isStructure = CGImageMetadataTagGetType(tag) != .string
                let hidden = redact && identifyingKeyFragments.contains(where: (path as String).lowercased().contains)
                xmp.append(["path": path as String, "value": hidden ? "<redacted>" : (isStructure ? "<structure>" : value)])
                return true
            }
        }
        image["xmp"] = xmp
        images.append(image)
    }
    report["images"] = images
    return report
}

// MARK: - Text output

func text(for file: String, imageIO: [String: Any], tiff: TIFFWalk?) -> String {
    var lines = ["==== \(file)", "ImageIO type: \(imageIO["type"] ?? "?")"]
    func flatten(_ value: Any, prefix: String) {
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() { flatten(dictionary[key]!, prefix: prefix.isEmpty ? key : "\(prefix).\(key)") }
        } else if let array = value as? [Any], array.contains(where: { $0 is [String: Any] }) {
            for (index, element) in array.enumerated() { flatten(element, prefix: "\(prefix)[\(index)]") }
        } else {
            lines.append("  \(prefix) = \("\(value)".replacingOccurrences(of: "\n", with: " "))")
        }
    }
    if let error = imageIO["error"] { lines.append("  error: \(error)") }
    if let container = imageIO["containerProperties"] {
        lines.append("-- Container properties")
        flatten(container, prefix: "")
    }
    for image in imageIO["images"] as? [[String: Any]] ?? [] {
        lines.append("-- Image \(image["index"] ?? "?") properties")
        flatten(image["properties"] ?? [:], prefix: "")
        let xmp = image["xmp"] as? [[String: String]] ?? []
        lines.append("-- Image \(image["index"] ?? "?") XMP (\(xmp.count) tags)")
        for tag in xmp { lines.append("  \(tag["path"] ?? "") = \(tag["value"] ?? "")") }
    }
    if let tiff {
        lines.append("-- TIFF structure (\(tiff.byteOrder))")
        for directory in tiff.directories {
            lines.append("  \(directory.path) at offset \(directory.offset), \(directory.entries.count) entries")
            for entry in directory.entries {
                let id = String(format: "0x%04X", entry.tag)
                lines.append("    \(id) \(entry.name) \(entry.type)[\(entry.count)] = \(entry.preview)")
            }
        }
        for problem in tiff.problems { lines.append("  problem: \(problem)") }
    }
    return lines.joined(separator: "\n")
}

// MARK: - Self-test

/// Builds small synthetic TIFF files and checks the walker against them. Exits non-zero on
/// failure. Run by scripts/test-dump-tags.sh in CI.
func selfTest() -> Bool {
    var failures: [String] = []
    func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }

    for bigEndian in [false, true] {
        let walk = TIFFWalker.walk(SyntheticTIFF.make(bigEndian: bigEndian))
        let label = bigEndian ? "big-endian" : "little-endian"
        let paths = walk.directories.map(\.path)
        check(walk.problems.isEmpty, "\(label): unexpected problems \(walk.problems)")
        check(walk.byteOrder.hasPrefix(bigEndian ? "big" : "little"), "\(label): byte order \(walk.byteOrder)")
        check(paths == ["IFD0", "IFD0/SubIFDs", "IFD0/ExifIFD", "IFD0/GPSInfoIFD", "IFD1"], "\(label): paths \(paths)")
        func entry(_ path: String, _ tag: UInt16) -> TIFFEntry? {
            walk.directories.first { $0.path == path }?.entries.first { $0.tag == tag }
        }
        check(entry("IFD0", 0x010F) == TIFFEntry(tag: 0x010F, name: "Make", type: "ASCII", count: 4, preview: "\"Nop\""), "\(label): Make")
        check(entry("IFD0", 0x0100)?.preview == "640", "\(label): inline SHORT")
        check(entry("IFD0", 0xC62F)?.preview == "\"CAMERA-SERIAL-1\"", "\(label): CameraSerialNumber at an offset")
        check(entry("IFD0", 0xC614)?.name == "UniqueCameraModel", "\(label): UniqueCameraModel name")
        check(entry("IFD0", 0x011A)?.preview == "72/1", "\(label): RATIONAL")
        check(entry("IFD0/SubIFDs", 0xC65D)?.preview == "00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f", "\(label): RawDataUniqueID")
        check(entry("IFD0/ExifIFD", 0xA431)?.name == "BodySerialNumber", "\(label): BodySerialNumber")
        check(entry("IFD0/ExifIFD", 0xA420)?.name == "ImageUniqueID", "\(label): ImageUniqueID")
        check(entry("IFD0/ExifIFD", 0xA435)?.name == "LensSerialNumber", "\(label): LensSerialNumber")
        check(entry("IFD0/ExifIFD", 0x927C)?.preview == "41 70 70 6c 65", "\(label): MakerNote bytes")
        check(entry("IFD0/GPSInfoIFD", 0x0001)?.name == "GPSLatitudeRef", "\(label): GPS table")
        check(entry("IFD1", 0x0103)?.preview == "1", "\(label): IFD1 chain")

        let redacted = TIFFWalker.walk(SyntheticTIFF.make(bigEndian: bigEndian), redact: true)
        let hidden = redacted.directories.flatMap(\.entries).filter { $0.preview == "<redacted>" }.map(\.tag)
        check(Set(hidden) == [0xC62F, 0xC65D, 0xA431, 0xA420, 0xA435, 0x927C, 0x0001], "\(label): redaction \(hidden)")
    }

    // Malformed input never crashes and is reported.
    check(TIFFWalker.walk([]).problems == ["file shorter than a TIFF header"], "empty file")
    check(TIFFWalker.walk(Array("not a tiff".utf8)).problems == ["not a TIFF byte order mark"], "bad byte order")
    check(TIFFWalker.walk([0x49, 0x49, 43, 0, 8, 0, 0, 0]).problems == ["BigTIFF is not supported"], "BigTIFF")
    let loop: [UInt8] = [0x49, 0x49, 42, 0, 8, 0, 0, 0, 0, 0, 8, 0, 0, 0]  // IFD0 points to itself
    check(TIFFWalker.walk(loop).problems.first?.contains("loop") == true, "IFD loop")
    let full = SyntheticTIFF.make(bigEndian: false)
    for length in stride(from: 0, to: full.count, by: 3) {
        _ = TIFFWalker.walk(Array(full.prefix(length)))  // every truncation must return
    }
    var corrupt = full
    for index in stride(from: 8, to: corrupt.count, by: 5) { corrupt[index] = 0xFF }
    _ = TIFFWalker.walk(corrupt)

    if failures.isEmpty {
        print("dump-tags self-test passed")
        return true
    }
    failures.forEach { print("dump-tags self-test FAILED: \($0)") }
    return false
}

/// Writes a small, valid TIFF with an IFD0 chain, a SubIFD, an EXIF IFD and a GPS IFD.
enum SyntheticTIFF {
    struct Field {
        let tag: UInt16
        let type: UInt16
        let count: UInt32
        let data: [UInt8]  // already in the file's byte order
    }

    static func make(bigEndian: Bool) -> [UInt8] {
        func u16(_ value: UInt16) -> [UInt8] {
            let bytes = [UInt8(value & 0xFF), UInt8(value >> 8)]
            return bigEndian ? bytes.reversed() : bytes
        }
        func u32(_ value: UInt32) -> [UInt8] {
            let bytes = (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
            return bigEndian ? bytes.reversed() : bytes
        }
        func ascii(_ tag: UInt16, _ text: String) -> Field {
            let bytes = Array(text.utf8) + [0]
            return Field(tag: tag, type: 2, count: UInt32(bytes.count), data: bytes)
        }
        func pointer(_ tag: UInt16) -> Field { Field(tag: tag, type: 4, count: 1, data: u32(0)) }

        // Layout: header, then IFDs in this order, each followed by its out-of-line values.
        let ifd0 = [
            Field(tag: 0x0100, type: 3, count: 1, data: u16(640)),
            ascii(0x010F, "Nop"),
            Field(tag: 0x011A, type: 5, count: 1, data: u32(72) + u32(1)),
            pointer(0x014A), pointer(0x8769), pointer(0x8825),
            ascii(0xC614, "Synthetic Camera"),
            ascii(0xC62F, "CAMERA-SERIAL-1"),
        ]
        let sub = [Field(tag: 0xC65D, type: 1, count: 16, data: Array(0..<16))]
        let exif = [
            Field(tag: 0x927C, type: 7, count: 5, data: Array("Apple".utf8)), ascii(0xA420, "0123456789ABCDEF0123456789ABCDEF"),
            ascii(0xA431, "BODY-SERIAL-1"), ascii(0xA435, "LENS-SERIAL-1"),
        ]
        let gps = [ascii(0x0001, "N")]
        let ifd1 = [Field(tag: 0x0103, type: 3, count: 1, data: u16(1))]
        let directories = [ifd0, sub, exif, gps, ifd1]

        func size(_ fields: [Field]) -> Int {
            2 + fields.count * 12 + 4 + fields.reduce(0) { $0 + ($1.data.count > 4 ? $1.data.count + $1.data.count % 2 : 0) }
        }
        var offsets: [Int] = []
        var position = 8
        for fields in directories {
            offsets.append(position)
            position += size(fields)
        }
        // Patch the pointers now that every IFD's offset is known.
        let targets: [UInt16: Int] = [0x014A: offsets[1], 0x8769: offsets[2], 0x8825: offsets[3]]
        var file = (bigEndian ? [0x4D, 0x4D] : [0x49, 0x49]) + u16(42) + u32(8)
        for (index, fields) in directories.enumerated() {
            var extra: [UInt8] = []
            var extraOffset = offsets[index] + 2 + fields.count * 12 + 4
            file += u16(UInt16(fields.count))
            for field in fields {
                let data = targets[field.tag].map { u32(UInt32($0)) } ?? field.data
                file += u16(field.tag) + u16(field.type) + u32(field.count)
                if data.count <= 4 {
                    file += data + [UInt8](repeating: 0, count: 4 - data.count)
                } else {
                    file += u32(UInt32(extraOffset))
                    let padded = data + (data.count % 2 == 1 ? [0] : [])
                    extra += padded
                    extraOffset += padded.count
                }
            }
            // IFD0 chains to IFD1; every other IFD ends the chain.
            file += u32(index == 0 ? UInt32(offsets[4]) : 0)
            file += extra
        }
        return file
    }
}

// MARK: - Main

let supportedExtensions: Set<String> = ["dng", "tif", "tiff", "heic", "heif", "jpg", "jpeg"]
let tiffExtensions: Set<String> = ["dng", "tif", "tiff"]

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--self-test"] { exit(selfTest() ? 0 : 1) }
let redact = arguments.contains("--redact")
arguments.removeAll { $0 == "--redact" }
var outputFolder: URL?
if let index = arguments.firstIndex(of: "--out"), index + 1 < arguments.count {
    outputFolder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    arguments.removeSubrange(index...index + 1)
}
guard !arguments.isEmpty else {
    print("usage: swift scripts/dump-tags.swift [--redact] [--out <folder>] <file-or-folder>...")
    print("       swift scripts/dump-tags.swift --self-test")
    exit(2)
}

var files: [URL] = []
for argument in arguments {
    let url = URL(fileURLWithPath: argument)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        print("not found: \(argument)")
        exit(1)
    }
    if isDirectory.boolValue {
        let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        files += contents.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    } else {
        files.append(url)
    }
}
let first = URL(fileURLWithPath: arguments[0])
var isFolder: ObjCBool = false
FileManager.default.fileExists(atPath: first.path, isDirectory: &isFolder)
let out = outputFolder ?? (isFolder.boolValue ? first : first.deletingLastPathComponent())

var textReport: [String] = []
var jsonReport: [[String: Any]] = []
for file in files {
    let imageIO = imageIOReport(file, redact: redact)
    var tiff: TIFFWalk?
    if tiffExtensions.contains(file.pathExtension.lowercased()), let data = try? Data(contentsOf: file) {
        tiff = TIFFWalker.walk([UInt8](data), redact: redact)
    }
    let section = text(for: file.lastPathComponent, imageIO: imageIO, tiff: tiff)
    print(section)
    print("")
    textReport.append(section)
    var entry: [String: Any] = ["file": file.lastPathComponent, "imageIO": imageIO]
    if let tiff, let data = try? JSONEncoder().encode(tiff), let object = try? JSONSerialization.jsonObject(with: data) {
        entry["tiff"] = object
    }
    jsonReport.append(entry)
}

do {
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try (textReport.joined(separator: "\n\n") + "\n").write(
        to: out.appendingPathComponent("tags-report.txt"), atomically: true, encoding: .utf8)
    let json = try JSONSerialization.data(withJSONObject: jsonReport, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: out.appendingPathComponent("tags-report.json"))
    print("Wrote \(files.count) file report(s) to \(out.path)/tags-report.txt and tags-report.json")
} catch {
    print("could not write the reports: \(error.localizedDescription)")
    exit(1)
}
