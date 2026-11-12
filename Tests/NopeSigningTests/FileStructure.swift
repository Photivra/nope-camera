import Foundation

/// Reads big- and little-endian integers from file bytes, for the structure checks below.
extension Data {
    func bigEndian16(at offset: Int) -> Int { Int(self[startIndex + offset]) << 8 | Int(self[startIndex + offset + 1]) }
    func bigEndian32(at offset: Int) -> Int { bigEndian16(at: offset) << 16 | bigEndian16(at: offset + 2) }
    func littleEndian16(at offset: Int) -> Int { Int(self[startIndex + offset]) | Int(self[startIndex + offset + 1]) << 8 }
    func littleEndian32(at offset: Int) -> Int { littleEndian16(at: offset) | littleEndian16(at: offset + 2) << 16 }
}

/// Lists a JPEG's markers up to the start of scan (ISO/IEC 10918-1, annex B).
enum JPEGSegments {
    static func markers(_ data: Data) -> [UInt16] {
        var markers: [UInt16] = []
        var offset = 2  // after SOI
        while offset + 4 <= data.count {
            let marker = UInt16(data.bigEndian16(at: offset))
            markers.append(marker)
            if marker == 0xFFDA { break }  // start of scan
            offset += 2 + data.bigEndian16(at: offset + 2)
        }
        return markers
    }
}

/// Lists a HEIF file's top-level boxes (ISO/IEC 14496-12, §4.2).
enum HEIFBoxes {
    static func boxes(_ data: Data) -> [(type: String, offset: Int, size: Int)] {
        var result: [(String, Int, Int)] = []
        var offset = 0
        while offset + 8 <= data.count {
            let size = data.bigEndian32(at: offset)
            let type = String(decoding: data[(data.startIndex + offset + 4)..<(data.startIndex + offset + 8)], as: UTF8.self)
            result.append((type, offset, size))
            guard size >= 8 else { break }
            offset += size
        }
        return result
    }

    static func topLevel(_ data: Data) -> [String] { boxes(data).map(\.type) }

    /// The extended type of every top-level `uuid` box.
    static func uuids(_ data: Data) -> [UUID] {
        boxes(data).filter { $0.type == "uuid" }.map { box in
            let start = data.startIndex + box.offset + 8
            return NSUUID(uuidBytes: [UInt8](data[start..<(start + 16)])) as UUID
        }
    }
}

/// Lists the entries of a little-endian TIFF file's first IFD (TIFF 6.0, section 2).
enum TIFFTags {
    struct Entry: Equatable {
        let tag: UInt16
        let type: Int
        let count: Int
    }

    static func firstIFD(_ data: Data) -> [Entry] {
        let ifd = data.littleEndian32(at: 4)
        let count = data.littleEndian16(at: ifd)
        return (0..<count).map { index in
            let entry = ifd + 2 + index * 12
            return Entry(
                tag: UInt16(data.littleEndian16(at: entry)), type: data.littleEndian16(at: entry + 2),
                count: data.littleEndian32(at: entry + 4))
        }
    }
}
