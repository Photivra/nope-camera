import Foundation
import NopeCore

/// A small, seeded random number generator (SplitMix64), so every fuzz run is reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Builds TIFF structures (DNG files and EXIF blocks) from a tree of directories, for the
/// read-back tests. Test-only: the app never writes bytes itself.
enum TIFFBuilder {
    /// One entry's value.
    indirect enum Value {
        case short([UInt16])
        case long([UInt32])
        case ascii(String)
        case bytes([UInt8])
        /// A field of an arbitrary type code and count, with these raw bytes.
        case raw(type: UInt16, count: UInt32, bytes: [UInt8])
        /// A LONG pointer to child directories.
        case directories([Directory])
        /// A LONG offset to a blob appended to the file (for StripOffsets and TileOffsets).
        case blobs([[UInt8]])
    }

    /// One directory: its entries, and the directory chained after it.
    final class Directory {
        var entries: [(UInt16, Value)]
        var next: Directory?

        init(_ entries: [(UInt16, Value)], next: Directory? = nil) {
            self.entries = entries
            self.next = next
        }
    }

    /// Builds a TIFF file.
    static func build(_ root: Directory, bigEndian: Bool = false) -> [UInt8] {
        var writer = Writer(bigEndian: bigEndian)
        writer.bytes = bigEndian ? [0x4D, 0x4D] : [0x49, 0x49]
        writer.bytes += writer.u16(42) + writer.u32(8)
        _ = writer.write(root)
        return writer.bytes
    }

    /// Lays out directories, out-of-line values, child directories and blobs.
    struct Writer {
        let bigEndian: Bool
        var bytes: [UInt8] = []

        func u16(_ value: UInt16) -> [UInt8] {
            let pair = [UInt8(value >> 8), UInt8(value & 0xFF)]
            return bigEndian ? pair : pair.reversed()
        }

        func u32(_ value: UInt32) -> [UInt8] {
            bigEndian ? u16(UInt16(value >> 16)) + u16(UInt16(value & 0xFFFF)) : u16(UInt16(value & 0xFFFF)) + u16(UInt16(value >> 16))
        }

        mutating func patch(_ at: Int, _ value: [UInt8]) {
            for (index, byte) in value.enumerated() { bytes[at + index] = byte }
        }

        /// Writes a directory (and everything it points to) at the end; returns its offset.
        mutating func write(_ directory: Directory) -> UInt32 {
            if bytes.count % 2 == 1 { bytes.append(0) }
            let start = bytes.count
            let entries = directory.entries.sorted { $0.0 < $1.0 }
            bytes += u16(UInt16(entries.count)) + Array(repeating: 0, count: entries.count * 12 + 4)
            var pending: [(Int, [Directory])] = []
            var blobs: [(Int, [[UInt8]])] = []
            for (index, (tag, value)) in entries.enumerated() {
                let at = start + 2 + index * 12
                let (type, count, payload): (UInt16, UInt32, [UInt8])
                switch value {
                case .short(let values): (type, count, payload) = (3, UInt32(values.count), values.flatMap(u16))
                case .long(let values): (type, count, payload) = (4, UInt32(values.count), values.flatMap(u32))
                case .ascii(let text):
                    let characters = Array(text.utf8) + [0]
                    (type, count, payload) = (2, UInt32(characters.count), characters)
                case .bytes(let values): (type, count, payload) = (1, UInt32(values.count), values)
                case .raw(let rawType, let rawCount, let rawBytes): (type, count, payload) = (rawType, rawCount, rawBytes)
                case .directories(let children):
                    (type, count, payload) = (4, UInt32(children.count), Array(repeating: 0, count: children.count * 4))
                case .blobs(let values):
                    (type, count, payload) = (4, UInt32(values.count), Array(repeating: 0, count: values.count * 4))
                }
                patch(at, u16(tag) + u16(type) + u32(count))
                var valueAt = at + 8
                if payload.count > 4 {
                    if bytes.count % 2 == 1 { bytes.append(0) }
                    patch(at + 8, u32(UInt32(bytes.count)))
                    valueAt = bytes.count
                    bytes += payload
                } else {
                    patch(at + 8, payload + Array(repeating: 0, count: 4 - payload.count))
                }
                if case .directories(let children) = value { pending.append((valueAt, children)) }
                if case .blobs(let values) = value { blobs.append((valueAt, values)) }
            }
            for (valueAt, children) in pending {
                for (index, child) in children.enumerated() {
                    let offset = write(child)
                    patch(valueAt + index * 4, u32(offset))
                }
            }
            for (valueAt, values) in blobs {
                for (index, blob) in values.enumerated() {
                    patch(valueAt + index * 4, u32(UInt32(bytes.count)))
                    bytes += blob
                }
            }
            if let next = directory.next {
                let offset = write(next)
                patch(start + 2 + entries.count * 12, u32(offset))
            }
            return UInt32(start)
        }
    }
}

/// Builds files that hold exactly what an allowlist allows, for the property tests.
enum CleanFiles {
    /// The RAW image data every built DNG carries.
    static let rawImageData: [UInt8] = Array(0..<64).map { UInt8($0 * 3 & 0xFF) }

    /// A value that passes a text rule.
    static func text(for rule: MetadataAllowlist.TextRule?) -> String {
        switch rule {
        case .exactly(let text): text
        case .prefix(let prefix): prefix + " (27.2.1)"
        case .any, nil: "27.2.1"
        }
    }

    /// The directories of a TIFF structure holding every allowed tag of the allowlist (and, for a
    /// wildcard GPS directory, two GPS tags), plus any extra tags.
    static func tiff(
        for allowlist: MetadataAllowlist, extra: [(TIFFDirectory, UInt16)] = [], includeRawData: Bool = true
    ) -> TIFFBuilder.Directory {
        var byDirectory: [TIFFDirectory: [(UInt16, TIFFBuilder.Value)]] = [:]
        let pointers: Set<UInt16> = [0x8769, 0x8825, 0x0111, 0x0117, 0x0144, 0x0145]
        for id in allowlist.tags where !pointers.contains(id.tag) {
            let rule = allowlist.textRules[id]
            let value: TIFFBuilder.Value = rule == nil ? .short([1]) : .ascii(text(for: rule))
            byDirectory[id.directory, default: []].append((id.tag, value))
        }
        for (directory, tag) in extra { byDirectory[directory, default: []].append((tag, .short([7]))) }
        if allowlist.wildcardDirectories.contains(.gps) {
            byDirectory[.gps, default: []] += [(0x0001, .ascii("N")), (0x0002, .short([1, 2, 3]))]
        }
        var primary = byDirectory[.primary] ?? []
        if includeRawData && allowlist.format == .raw {
            primary += [(0x0111, .blobs([rawImageData])), (0x0117, .long([UInt32(rawImageData.count)]))]
        }
        if let exif = byDirectory[.exif] {
            primary.append((0x8769, .directories([TIFFBuilder.Directory(exif)])))
        }
        if let gps = byDirectory[.gps] {
            primary.append((0x8825, .directories([TIFFBuilder.Directory(gps)])))
        }
        return TIFFBuilder.Directory(primary)
    }

    /// A DNG holding exactly what the allowlist allows.
    static func dng(for allowlist: MetadataAllowlist, extra: [(TIFFDirectory, UInt16)] = []) -> Data {
        Data(TIFFBuilder.build(tiff(for: allowlist, extra: extra)))
    }

    /// A JPEG holding exactly what the allowlist allows, plus extra segments.
    static func jpeg(
        for allowlist: MetadataAllowlist, extraTags: [(TIFFDirectory, UInt16)] = [], extraSegments: [(UInt8, [UInt8])] = []
    ) -> Data {
        let exif = Array("Exif".utf8) + [0, 0] + TIFFBuilder.build(tiff(for: allowlist, extra: extraTags), bigEndian: true)
        var segments: [(UInt8, [UInt8])] = [
            (0xE0, Array("JFIF".utf8) + [0, 1, 1, 0, 0, 72, 0, 72, 0, 0]),
            (0xE1, exif),
            (0xE2, Array("ICC_PROFILE".utf8) + [0, 1, 1, 0xAA]),
            (0xED, JPEGTestData.emptyIPTC),
            (0xDB, Array(repeating: 1, count: 65)),
            (0xC0, [8, 0, 2, 0, 2, 1, 1, 0x11, 0]),
            (0xC4, Array(repeating: 0, count: 17)),
            (0xDD, [0, 4]),
        ]
        segments += extraSegments
        if allowlist.blocks.contains("jpeg:APP11") { segments.append((0xEB, Array("JP".utf8) + [0, 0])) }
        var bytes: [UInt8] = [0xFF, 0xD8]
        for (marker, payload) in segments {
            bytes += [0xFF, marker, UInt8((payload.count + 2) >> 8), UInt8((payload.count + 2) & 0xFF)] + payload
        }
        // Start of scan, entropy-coded data with a stuffed byte and a restart marker, then the end.
        bytes += [0xFF, 0xDA, 0, 8, 1, 1, 0, 0, 0x3F, 0] + [0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD0, 0x56] + [0xFF, 0xD9]
        return Data(bytes)
    }
}

/// Byte-level constants shared by the JPEG tests.
enum JPEGTestData {
    /// ImageIO's empty IPTC APP13 payload (see `JPEGReader.emptyIPTCSegment`).
    static let emptyIPTC: [UInt8] =
        Array("Photoshop 3.0".utf8) + [0x00]
        + Array("8BIM".utf8) + [0x04, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        + Array("8BIM".utf8) + [0x04, 0x25, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10]
        + [0xD4, 0x1D, 0x8C, 0xD9, 0x8F, 0x00, 0xB2, 0x04, 0xE9, 0x80, 0x09, 0x98, 0xEC, 0xF8, 0x42, 0x7E]
}

/// Builds HEIF files box by box, for the read-back tests.
enum HEIFBuilder {
    /// A box: a 32-bit size, a type and a payload.
    static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be32(UInt32(payload.count + 8)) + Array(type.utf8) + payload
    }

    /// A full box: a box whose payload starts with a version and 24 bits of flags.
    static func fullBox(_ type: String, version: UInt8, _ payload: [UInt8]) -> [UInt8] {
        box(type, [version, 0, 0, 0] + payload)
    }

    static func be16(_ value: Int) -> [UInt8] { [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
    static func be32(_ value: UInt32) -> [UInt8] { [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }

    /// One item: its ID, type, content type for `mime`, and its data.
    struct Item {
        let id: Int
        let type: String
        var contentType = ""
        var data: [UInt8] = []
    }

    /// An `infe` version 2 entry.
    static func itemEntry(_ item: Item) -> [UInt8] {
        var payload = be16(item.id) + be16(0) + Array(item.type.utf8) + [0]  // id, protection, type, empty name
        if item.type == "mime" { payload += Array(item.contentType.utf8) + [0] }
        return fullBox("infe", version: 2, payload)
    }

    /// Builds a HEIF file. Item data goes in `idat` (construction method 1), or, with
    /// `dataInMediaBox`, in an `mdat` placed before `meta` (construction method 0, file offsets).
    static func build(
        items: [Item], properties: [String] = ["ispe", "colr", "hvcC"], references: [String] = ["cdsc"],
        extraTopLevel: [[UInt8]] = [], dataInMediaBox: Bool = false
    ) -> Data {
        let ftyp = box("ftyp", Array("heicmif1heic".utf8))
        var dataBytes: [UInt8] = []
        var extents: [(id: Int, offset: Int, length: Int)] = []
        for item in items where !item.data.isEmpty {
            extents.append((item.id, dataBytes.count, item.data.count))
            dataBytes += item.data
        }
        let mdat = box("mdat", dataBytes)
        let mediaBase = dataInMediaBox ? ftyp.count + 8 : 0
        var iloc: [UInt8] = [0x44, 0x40] + be16(extents.count)  // offset 4, length 4, base offset 4, index 0
        for extent in extents {
            iloc += be16(extent.id) + be16(dataInMediaBox ? 0 : 1) + be16(0) + be32(0) + be16(1)
            iloc += be32(UInt32(mediaBase + extent.offset)) + be32(UInt32(extent.length))
        }
        var meta: [UInt8] = []
        meta += fullBox("hdlr", version: 0, be32(0) + Array("pict".utf8) + Array(repeating: 0, count: 13))
        meta += fullBox("pitm", version: 0, be16(1))
        meta += fullBox("iinf", version: 0, be16(items.count) + items.flatMap(itemEntry))
        meta += fullBox("iloc", version: 1, iloc)
        meta += box("iprp", box("ipco", properties.flatMap { box($0, [0, 0, 0, 0]) }) + fullBox("ipma", version: 0, be32(0)))
        meta += fullBox("iref", version: 0, references.flatMap { box($0, be16(2) + be16(1) + be16(1)) })
        if !dataInMediaBox { meta += box("idat", dataBytes) }
        let metaBox = fullBox("meta", version: 0, meta)
        let body = dataInMediaBox ? ftyp + mdat + metaBox : ftyp + metaBox + mdat
        return Data(body + extraTopLevel.flatMap { $0 })
    }

    /// The `Exif` item payload: a 4-byte offset of 0, then a TIFF structure.
    static func exifItem(_ tiff: [UInt8]) -> [UInt8] {
        [0, 0, 0, 0] + tiff
    }

    /// An XMP packet with these properties as elements of one `rdf:Description`.
    static func xmp(_ properties: [(prefix: String, namespace: String, name: String, value: String)], attributes: String = "") -> [UInt8] {
        let namespaces = Set(properties.map { "xmlns:\($0.prefix)=\"\($0.namespace)\"" }).sorted().joined(separator: " ")
        let body = properties.map { "<\($0.prefix):\($0.name)>\($0.value)</\($0.prefix):\($0.name)>" }.joined()
        let xml = """
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\
            <rdf:Description rdf:about="" \(namespaces) \(attributes)>\(body)</rdf:Description></rdf:RDF></x:xmpmeta>
            """
        return Array(xml.utf8)
    }
}
