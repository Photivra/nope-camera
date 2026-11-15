import Foundation
import NopeCore

/// Writes a 256 × 256 Bayer DNG whose metadata is exactly an ImageIO property dictionary, the
/// way AVFoundation writes a DNG from the replacement metadata nope. gives it
/// (`AVCapturePhoto.fileDataRepresentation(with:)`), for the file compatibility matrix (issue #58).
///
/// Test-only: the app never writes DNG bytes itself. The dictionary is the one
/// `MetadataPlan.properties(for:from:orientation:)` builds for the RAW, so the fixture carries
/// what nope. asks the system to write for each switch combination. The layout (IFD0 holding the
/// image, then the EXIF and GPS directories, then the pixels) follows TIFF 6.0 and DNG 1.7.1.0;
/// a camera DNG's own layout comes from AVFoundation and is checked on a device
/// (docs/TESTING.md, "File compatibility").
enum FixtureDNG {
    /// The pixel width and height. ImageIO on macOS 27 doesn't recognize a DNG of 200 × 200 or
    /// smaller as a DNG (`SyntheticPhotos.dng()`).
    static let size: UInt32 = 256

    /// A TIFF field type (TIFF 6.0, section 2, "Types").
    enum FieldType: UInt16 {
        case byte = 1, ascii = 2, short = 3, long = 4, rational = 5, undefined = 7, signedRational = 10

        /// Bytes per value.
        var width: Int {
            switch self {
            case .byte, .ascii, .undefined: 1
            case .short: 2
            case .long: 4
            case .rational, .signedRational: 8
            }
        }
    }

    /// A field this writer can't encode: the matrix would otherwise test a file that doesn't
    /// match the dictionary.
    struct UnsupportedField: Error, CustomStringConvertible {
        let key: String
        var description: String { "FixtureDNG can't write \(key)" }
    }

    /// The type each tag is written with, from the TIFF 6.0, EXIF 3.0 and DNG 1.7.1.0 tag tables.
    static func fieldType(_ directory: TIFFDirectory, _ tag: UInt16) -> FieldType? {
        switch (directory, tag) {
        case (.primary, 0x010F), (.primary, 0x0110), (.primary, 0x0131), (.primary, 0x0132), (.primary, 0x013B),
            (.primary, 0x013C), (.primary, 0x8298), (.primary, 0xC614):
            .ascii
        case (.primary, 0x0112), (.primary, 0xC65A), (.primary, 0xC65B): .short
        case (.primary, 0xC612), (.primary, 0xC613): .byte
        case (.primary, 0xC61A), (.primary, 0xC61D): .long
        case (.primary, 0xC621), (.primary, 0xC622), (.primary, 0xC62A): .signedRational
        case (.primary, 0xC628), (.primary, 0xC630): .rational
        case (.exif, 0x9000), (.exif, 0xA301): .undefined
        case (.exif, 0x9003), (.exif, 0x9004), (.exif, 0x9010), (.exif, 0x9011), (.exif, 0x9012), (.exif, 0x9290),
            (.exif, 0x9291), (.exif, 0x9292), (.exif, 0xA433), (.exif, 0xA434):
            .ascii
        case (.exif, 0x829A), (.exif, 0x829D), (.exif, 0x9202), (.exif, 0x9205), (.exif, 0x920A), (.exif, 0xA432):
            .rational
        case (.exif, 0x9201), (.exif, 0x9203), (.exif, 0x9204): .signedRational
        case (.exif, 0x8822), (.exif, 0x8827), (.exif, 0x8830), (.exif, 0x9207), (.exif, 0x9209), (.exif, 0x9214),
            (.exif, 0xA217), (.exif, 0xA402), (.exif, 0xA403), (.exif, 0xA405), (.exif, 0xA406):
            .short
        case (.exif, 0xA002), (.exif, 0xA003): .long
        case (.gps, 0x0000), (.gps, 0x0005): .byte
        case (.gps, 0x0001), (.gps, 0x0003): .ascii
        case (.gps, 0x0002), (.gps, 0x0004), (.gps, 0x0006): .rational
        default: nil
        }
    }

    /// One directory entry, with its whole value.
    struct Entry {
        let tag: UInt16
        let type: FieldType
        let count: Int
        var value: [UInt8]
    }

    /// The ImageIO key each catalog field is written from: its first key (the others are
    /// ImageIO's mirrors, such as IPTC `Byline` for `Artist`).
    static let fieldsByKey: [String: MetadataField] = Dictionary(
        MetadataField.catalog.compactMap { field in field.imageIOKeys.first.map { ($0.description, field) } },
        uniquingKeysWith: { first, _ in first })

    /// Writes the DNG.
    ///
    /// - Parameter properties: The metadata, keyed like `CGImageProperties.h`.
    /// - Returns: The file.
    /// - Throws: ``UnsupportedField`` for a key this writer has no tag type for.
    static func make(properties: [String: Any]) throws -> Data {
        var primary: [Entry] = structure()
        var exif: [Entry] = []
        var gps: [Entry] = []
        for (name, value) in properties {
            if name == "Orientation" { continue }  // ImageIO's mirror of {TIFF}.Orientation
            if name == "{MakerApple}" {
                // An opaque maker note, as the switch allows (EXIF 3.0, `MakerNote`, UNDEFINED).
                exif.append(Entry(tag: 0x927C, type: .undefined, count: 16, value: Array("nope. fixture\0\0\0".utf8)))
                continue
            }
            guard let dictionary = value as? [String: Any] else { throw UnsupportedField(key: name) }
            for (key, item) in dictionary {
                let id = "\(name).\(key)"
                if id == "{Exif}.ExifVersion" { continue }  // written below, as EXIF's four digits
                guard let field = fieldsByKey[id], let type = fieldType(field.directory, field.tag) else {
                    throw UnsupportedField(key: id)
                }
                let entry = try encode(item, tag: field.tag, type: type, key: id)
                switch field.directory {
                case .primary: primary.append(entry)
                case .exif: exif.append(entry)
                case .gps: gps.append(entry)
                default: throw UnsupportedField(key: id)
                }
            }
        }
        // DNG requires these; MetadataPlan copies them from the system's metadata (locked).
        exif.append(Entry(tag: 0x9000, type: .undefined, count: 4, value: Array("0232".utf8)))
        exif = deduplicated(exif)
        return layout(primary: primary, exif: exif, gps: gps)
    }

    /// Keeps the first entry for each tag.
    private static func deduplicated(_ entries: [Entry]) -> [Entry] {
        var seen: Set<UInt16> = []
        return entries.filter { seen.insert($0.tag).inserted }
    }

    /// The image structure tags of a single-strip, uncompressed, 16-bit RGGB image.
    private static func structure() -> [Entry] {
        [
            Entry(tag: 0x00FE, type: .long, count: 1, value: le32(0)),  // NewSubFileType: main image
            Entry(tag: 0x0100, type: .long, count: 1, value: le32(size)),  // ImageWidth
            Entry(tag: 0x0101, type: .long, count: 1, value: le32(size)),  // ImageLength
            Entry(tag: 0x0102, type: .short, count: 1, value: le16(16)),  // BitsPerSample
            Entry(tag: 0x0103, type: .short, count: 1, value: le16(1)),  // Compression: none
            Entry(tag: 0x0106, type: .short, count: 1, value: le16(32803)),  // PhotometricInterpretation: CFA
            Entry(tag: 0x0111, type: .long, count: 1, value: le32(0)),  // StripOffsets, set by layout
            Entry(tag: 0x0115, type: .short, count: 1, value: le16(1)),  // SamplesPerPixel
            Entry(tag: 0x0116, type: .long, count: 1, value: le32(size)),  // RowsPerStrip
            Entry(tag: 0x0117, type: .long, count: 1, value: le32(size * size * 2)),  // StripByteCounts
            Entry(tag: 0x828D, type: .short, count: 2, value: le16(2) + le16(2)),  // CFARepeatPatternDim
            Entry(tag: 0x828E, type: .byte, count: 4, value: [0, 1, 1, 2]),  // CFAPattern: RGGB
        ]
    }

    /// Encodes one ImageIO value as a field.
    private static func encode(_ value: Any, tag: UInt16, type: FieldType, key: String) throws -> Entry {
        if type == .ascii {
            guard let text = value as? String else { throw UnsupportedField(key: key) }
            let bytes = Array(text.utf8) + [0]
            return Entry(tag: tag, type: type, count: bytes.count, value: bytes)
        }
        var numbers: [Double]
        if let number = value as? NSNumber {
            numbers = [number.doubleValue]
        } else if let array = value as? [NSNumber] {
            numbers = array.map(\.doubleValue)
        } else {
            throw UnsupportedField(key: key)
        }
        // GPSLatitude and GPSLongitude are degrees, minutes and seconds (EXIF 3.0, 4.6.6);
        // ImageIO reports them as decimal degrees.
        if key == "{GPS}.Latitude" || key == "{GPS}.Longitude" { numbers += [0, 0] }
        var bytes: [UInt8] = []
        for number in numbers {
            switch type {
            case .byte, .undefined: bytes.append(UInt8(number))
            case .short: bytes += le16(UInt16(number))
            case .long: bytes += le32(UInt32(number))
            case .rational: bytes += le32(UInt32((number * 1_000_000).rounded())) + le32(1_000_000)
            case .signedRational:
                bytes += le32(UInt32(bitPattern: Int32((number * 1_000_000).rounded()))) + le32(1_000_000)
            case .ascii: break
            }
        }
        return Entry(tag: tag, type: type, count: numbers.count, value: bytes)
    }

    /// Lays the file out: header, IFD0, the EXIF and GPS directories, then the pixels.
    private static func layout(primary: [Entry], exif: [Entry], gps: [Entry]) -> Data {
        var primary = primary
        primary.append(Entry(tag: 0x8769, type: .long, count: 1, value: le32(0)))
        if !gps.isEmpty { primary.append(Entry(tag: 0x8825, type: .long, count: 1, value: le32(0))) }
        primary = deduplicated(primary)
        let ifd0Offset = 8
        let exifOffset = ifd0Offset + blockSize(primary)
        let gpsOffset = exifOffset + blockSize(exif)
        let pixelOffset = gpsOffset + (gps.isEmpty ? 0 : blockSize(gps))
        for index in primary.indices {
            switch primary[index].tag {
            case 0x0111: primary[index].value = le32(UInt32(pixelOffset))
            case 0x8769: primary[index].value = le32(UInt32(exifOffset))
            case 0x8825: primary[index].value = le32(UInt32(gpsOffset))
            default: break
            }
        }
        var bytes: [UInt8] = Array("II".utf8) + le16(42) + le32(UInt32(ifd0Offset))
        bytes += block(primary, at: ifd0Offset)
        bytes += block(exif, at: exifOffset)
        if !gps.isEmpty { bytes += block(gps, at: gpsOffset) }
        precondition(bytes.count == pixelOffset)
        for index in 0..<Int(size * size) { bytes += le16(UInt16(index * 7 % 4096)) }
        return Data(bytes)
    }

    /// The size of a directory with its out-of-line values, each padded to an even length.
    private static func blockSize(_ entries: [Entry]) -> Int {
        2 + entries.count * 12 + 4 + entries.reduce(0) { $0 + outOfLineSize($1) }
    }

    /// The bytes a value takes after the directory: 0 when it fits in the entry.
    private static func outOfLineSize(_ entry: Entry) -> Int {
        entry.value.count <= 4 ? 0 : entry.value.count + entry.value.count % 2
    }

    /// One directory (entries sorted by tag, as TIFF requires) followed by its values.
    private static func block(_ entries: [Entry], at offset: Int) -> [UInt8] {
        let sorted = entries.sorted { $0.tag < $1.tag }
        var head = le16(UInt16(sorted.count))
        var tail: [UInt8] = []
        var dataOffset = offset + 2 + sorted.count * 12 + 4
        for entry in sorted {
            head += le16(entry.tag) + le16(entry.type.rawValue) + le32(UInt32(entry.count))
            if entry.value.count <= 4 {
                head += entry.value + [UInt8](repeating: 0, count: 4 - entry.value.count)
            } else {
                head += le32(UInt32(dataOffset))
                let padded = entry.value + (entry.value.count % 2 == 1 ? [0] : [])
                tail += padded
                dataOffset += padded.count
            }
        }
        head += le32(0)  // no next IFD
        return head + tail
    }

    private static func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
    private static func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) } }
}
