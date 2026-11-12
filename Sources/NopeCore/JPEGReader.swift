import Foundation

/// Lists every segment of a JPEG file and reads the tags in its EXIF segment.
///
/// Read-only, bounds-checked and fuzz-tested, like ``TIFFReader``. Written from ITU-T T.81
/// (JPEG, annex B: markers and segments), EXIF 3.0 section 4.5.4 (the `Exif\0\0` APP1 segment),
/// ICC.1 annex B.4 (the `ICC_PROFILE` APP2 segment), XMP part 3 section 1.1.3 (the XMP APP1
/// segment) and C2PA 2.1 section A.3.1 (JUMBF in APP11 segments).
///
/// Each segment becomes a block named `jpeg:<marker>` with an identifier where the marker is
/// shared, for example `jpeg:APP1:Exif` or `jpeg:APP2:ICC`. Entropy-coded data after a start of
/// scan is skipped up to the next marker; anything after the end-of-image marker is reported as
/// `jpeg:trailing-data`, because extra images (such as a multi-picture file) live there.
enum JPEGReader {
    /// The APP13 segment ImageIO writes into every JPEG: "Photoshop 3.0", an empty IPTC record
    /// (image resource `0x0404`, length 0) and that record's MD5 digest (resource `0x0425`,
    /// the MD5 of no bytes). It holds no information; any other APP13 content is reported as
    /// `jpeg:APP13`. Observed with ImageIO on macOS 27 and the iOS 27 Simulator.
    static let emptyIPTCSegment: [UInt8] =
        Array("Photoshop 3.0".utf8) + [0x00]
        + Array("8BIM".utf8) + [0x04, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        + Array("8BIM".utf8) + [0x04, 0x25, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10]
        + [0xD4, 0x1D, 0x8C, 0xD9, 0x8F, 0x00, 0xB2, 0x04, 0xE9, 0x80, 0x09, 0x98, 0xEC, 0xF8, 0x42, 0x7E]

    /// The identifier that starts an EXIF APP1 segment.
    static let exifIdentifier: [UInt8] = Array("Exif".utf8) + [0, 0]
    /// The identifier that starts an XMP APP1 segment.
    static let xmpIdentifier: [UInt8] = Array("http://ns.adobe.com/xap/1.0/".utf8) + [0]
    /// The identifier that starts an ICC profile APP2 segment.
    static let iccIdentifier: [UInt8] = Array("ICC_PROFILE".utf8) + [0]
    /// The identifier that starts a JFIF APP0 segment.
    static let jfifIdentifier: [UInt8] = Array("JFIF".utf8) + [0]

    /// The most segments a file may have before the reader gives up.
    static let maximumSegments = 4096

    /// Reads a JPEG file.
    ///
    /// - Parameter bytes: The whole file.
    /// - Returns: Every segment as a block, the EXIF tags, and any problem.
    static func read(_ bytes: [UInt8]) -> MetadataInventory {
        var inventory = MetadataInventory()
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
            inventory.problems.append("JPEG: no start-of-image marker")
            return inventory
        }
        var position = 2
        var segments = 0
        while position < bytes.count {
            segments += 1
            guard segments <= maximumSegments else {
                inventory.problems.append("JPEG: too many segments")
                return inventory
            }
            guard position + 1 < bytes.count, bytes[position] == 0xFF else {
                inventory.problems.append("JPEG: expected a marker")
                return inventory
            }
            let marker = bytes[position + 1]
            if marker == 0xD9 {
                inventory.blocks.append("jpeg:EOI")
                if position + 2 < bytes.count { inventory.blocks.append("jpeg:trailing-data") }
                return inventory
            }
            if marker == 0xFF {
                // Fill bytes before a marker (T.81 B.1.1.2).
                position += 1
                continue
            }
            guard position + 4 <= bytes.count else {
                inventory.problems.append("JPEG: a segment is cut off")
                return inventory
            }
            let length = Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
            let end = position + 2 + length
            guard length >= 2, end <= bytes.count else {
                inventory.problems.append("JPEG: a segment is cut off")
                return inventory
            }
            let payload = Array(bytes[position + 4..<end])
            inventory.blocks.append(blockName(marker: marker, payload: payload))
            if marker == 0xE1, payload.starts(with: exifIdentifier) {
                inventory.append(TIFFReader.read(Array(payload.dropFirst(exifIdentifier.count))).inventory)
            }
            position = marker == 0xDA ? skipEntropyCodedData(bytes, from: end) : end
        }
        inventory.problems.append("JPEG: no end-of-image marker")
        return inventory
    }

    /// The block name of a segment.
    ///
    /// - Parameters:
    ///   - marker: The marker's second byte.
    ///   - payload: The segment's bytes after its length.
    /// - Returns: A name such as `jpeg:SOF` or `jpeg:APP1:Exif`.
    static func blockName(marker: UInt8, payload: [UInt8]) -> String {
        switch marker {
        case 0xC4: return "jpeg:DHT"
        case 0xCC: return "jpeg:DAC"
        case 0xC0...0xCF: return "jpeg:SOF"
        case 0xDA: return "jpeg:SOS"
        case 0xDB: return "jpeg:DQT"
        case 0xDD: return "jpeg:DRI"
        case 0xFE: return "jpeg:COM"
        case 0xE0 where payload.starts(with: jfifIdentifier): return "jpeg:APP0:JFIF"
        case 0xE1 where payload.starts(with: exifIdentifier): return "jpeg:APP1:Exif"
        case 0xE1 where payload.starts(with: xmpIdentifier): return "jpeg:APP1:XMP"
        case 0xE2 where payload.starts(with: iccIdentifier): return "jpeg:APP2:ICC"
        case 0xED where payload == emptyIPTCSegment: return "jpeg:APP13:empty-IPTC"
        case 0xE0...0xEF: return "jpeg:APP\(marker - 0xE0)"
        default: return String(format: "jpeg:marker-%02X", marker)
        }
    }

    /// Skips the entropy-coded data after a start-of-scan segment.
    ///
    /// Inside it, `0xFF 0x00` is a stuffed data byte and `0xFF 0xD0`–`0xD7` are restart
    /// markers (T.81 B.1.1.5 and B.2.1); any other `0xFF xx` is the next marker.
    ///
    /// - Parameters:
    ///   - bytes: The file.
    ///   - start: The first byte after the start-of-scan segment.
    /// - Returns: The position of the next marker, or the end of the file.
    static func skipEntropyCodedData(_ bytes: [UInt8], from start: Int) -> Int {
        var position = start
        while position + 1 < bytes.count {
            if bytes[position] == 0xFF {
                let next = bytes[position + 1]
                if next != 0x00 && !(0xD0...0xD7).contains(next) { return position }
            }
            position += 1
        }
        return bytes.count
    }
}
