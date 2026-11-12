import Foundation

/// Lists every box, item, item property and item reference of a HEIF file, and reads the tags
/// in its EXIF item and the properties in its XMP item.
///
/// Read-only, bounds-checked and fuzz-tested, like ``TIFFReader``. Written from ISO/IEC 14496-12
/// (ISOBMFF: box headers 4.2, `meta` 8.11.1, `iloc` 8.11.3, `iinf`/`infe` 8.11.6, `iref`
/// 8.11.12, `idat` 8.11.11) and ISO/IEC 23008-12 (HEIF: `iprp`/`ipco`/`ipma` 9.3, the `Exif`
/// item and its TIFF header offset in annex A.2.1, XMP as a `mime` item in A.2.2).
///
/// Block names:
/// - `heif:box:<type>` for each top-level box;
/// - `heif:meta:<type>` for each box inside `meta`;
/// - `heif:item:<type>` for each item, and `heif:item:mime:<content type>` for a MIME item;
/// - `heif:property:<type>` for each item property;
/// - `heif:reference:<type>` for each item reference type.
struct HEIFReader {
    /// The XMP content type of a `mime` item.
    static let xmpContentType = "application/rdf+xml"
    /// The most boxes the reader reads before giving up.
    static let maximumBoxes = 4096

    /// One box: its type and where its payload is.
    private struct Box: Equatable {
        /// The four-character type.
        let type: String
        /// The first byte after the header.
        let payloadStart: Int
        /// The first byte after the box.
        let end: Int
    }

    /// One item from `iinf`.
    private struct Item: Equatable {
        /// The item ID.
        let id: Int
        /// The four-character item type.
        let type: String
        /// The content type of a `mime` item, otherwise empty.
        let contentType: String
    }

    /// The file's bytes.
    private let bytes: [UInt8]
    /// What has been found so far.
    private var inventory = MetadataInventory()
    /// The number of boxes read so far.
    private var boxCount = 0
    /// The items from `iinf`.
    private var items: [Item] = []
    /// Each item's data ranges from `iloc`, by item ID, as offsets in the file or in `idat`.
    private var locations: [Int: (constructionMethod: Int, extents: [Range<Int>])] = [:]
    /// The payload range of `idat`, if any.
    private var itemDataRange: Range<Int>?

    /// Creates a reader.
    ///
    /// - Parameter bytes: The whole file.
    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Reads a HEIF file.
    ///
    /// - Parameter bytes: The whole file.
    /// - Returns: Every block, the EXIF tags, the XMP properties, and any problem.
    static func read(_ bytes: [UInt8]) -> MetadataInventory {
        var reader = HEIFReader(bytes: bytes)
        reader.run()
        return reader.inventory
    }

    /// Reads the top-level boxes, then the metadata items they point to.
    private mutating func run() {
        let topLevel = boxes(in: 0..<bytes.count)
        guard topLevel.first?.type == "ftyp" else { return problem("no ftyp box first") }
        for box in topLevel {
            inventory.blocks.append("heif:box:\(box.type)")
            if box.type == "meta" { readMeta(box) }
        }
        for item in items {
            inventory.blocks.append(item.type == "mime" ? "heif:item:mime:\(item.contentType)" : "heif:item:\(item.type)")
            readMetadataItem(item)
        }
    }

    /// Reads the boxes inside `meta` (a full box: 4 bytes of version and flags first).
    ///
    /// - Parameter meta: The `meta` box.
    private mutating func readMeta(_ meta: Box) {
        for box in boxes(in: meta.payloadStart + 4..<meta.end) {
            inventory.blocks.append("heif:meta:\(box.type)")
            switch box.type {
            case "iinf": readItemInfo(box)
            case "iloc": readItemLocations(box)
            case "iprp": readProperties(box)
            case "iref": readReferences(box)
            case "idat": itemDataRange = box.payloadStart..<box.end
            default: break
            }
        }
    }

    /// Reads `iinf` and its `infe` entries (versions 2 and 3, the only ones HEIF uses).
    ///
    /// - Parameter box: The `iinf` box.
    private mutating func readItemInfo(_ box: Box) {
        guard let version = byte(box.payloadStart) else { return problem("unreadable iinf") }
        let entriesStart = box.payloadStart + 4 + (version == 0 ? 2 : 4)
        for entry in boxes(in: entriesStart..<box.end) {
            guard entry.type == "infe", let entryVersion = byte(entry.payloadStart), entryVersion >= 2 else {
                problem("an item entry HEIF doesn't define")
                continue
            }
            let idSize = entryVersion == 2 ? 2 : 4
            let typeStart = entry.payloadStart + 4 + idSize + 2
            guard let id = integer(at: entry.payloadStart + 4, size: idSize), typeStart + 4 <= entry.end else {
                problem("unreadable item entry")
                continue
            }
            let type = fourCharacterCode(at: typeStart)
            // item_name, then content_type for a `mime` item: NUL-terminated strings.
            let name = nulTerminated(from: typeStart + 4, end: entry.end)
            let contentType = type == "mime" ? nulTerminated(from: name.next, end: entry.end).text : ""
            items.append(Item(id: id, type: type, contentType: contentType))
        }
    }

    /// Reads `iloc`: where each item's bytes are.
    ///
    /// - Parameter box: The `iloc` box.
    private mutating func readItemLocations(_ box: Box) {
        var position = box.payloadStart
        guard let version = byte(position), let sizes = byte(position + 4), let moreSizes = byte(position + 5) else {
            return problem("unreadable iloc")
        }
        let offsetSize = Int(sizes >> 4), lengthSize = Int(sizes & 0x0F), baseOffsetSize = Int(moreSizes >> 4)
        let indexSize = version >= 1 ? Int(moreSizes & 0x0F) : 0
        position += 6
        let countSize = version < 2 ? 2 : 4
        guard let itemCount = integer(at: position, size: countSize) else { return problem("unreadable iloc") }
        position += countSize
        for _ in 0..<min(itemCount, Self.maximumBoxes) {
            let idSize = version < 2 ? 2 : 4
            guard let id = integer(at: position, size: idSize) else { return problem("unreadable iloc") }
            position += idSize
            // Versions 1 and 2 add 12 reserved bits and a 4-bit construction method.
            let methodSize = version >= 1 ? 2 : 0
            guard let method = integer(at: position, size: methodSize) else { return problem("unreadable iloc") }
            let constructionMethod = method & 0x0F
            position += methodSize + 2  // then data_reference_index
            guard let baseOffset = integer(at: position, size: baseOffsetSize),
                let extentCount = integer(at: position + baseOffsetSize, size: 2)
            else { return problem("unreadable iloc") }
            position += baseOffsetSize + 2
            var extents: [Range<Int>] = []
            for _ in 0..<min(extentCount, Self.maximumBoxes) {
                position += indexSize
                guard let offset = integer(at: position, size: offsetSize),
                    let length = integer(at: position + offsetSize, size: lengthSize)
                else { return problem("unreadable iloc") }
                position += offsetSize + lengthSize
                extents.append(baseOffset + offset..<baseOffset + offset + length)
            }
            locations[id] = (constructionMethod, extents)
        }
    }

    /// Reads `iprp`: each property in `ipco` (the association table, `ipma`, holds no
    /// metadata).
    ///
    /// - Parameter box: The `iprp` box.
    private mutating func readProperties(_ box: Box) {
        for child in boxes(in: box.payloadStart..<box.end) where child.type == "ipco" {
            for property in boxes(in: child.payloadStart..<child.end) {
                inventory.blocks.append("heif:property:\(property.type)")
            }
        }
    }

    /// Reads `iref`: the type of each reference, such as `thmb` for a thumbnail or `cdsc` for
    /// metadata describing an image.
    ///
    /// - Parameter box: The `iref` box.
    private mutating func readReferences(_ box: Box) {
        for reference in boxes(in: box.payloadStart + 4..<box.end) {
            inventory.blocks.append("heif:reference:\(reference.type)")
        }
    }

    /// Reads the tags of an `Exif` item or the properties of an XMP `mime` item.
    ///
    /// - Parameter item: The item.
    private mutating func readMetadataItem(_ item: Item) {
        let isXMP = item.type == "mime" && item.contentType == Self.xmpContentType
        guard item.type == "Exif" || isXMP else { return }
        guard let data = itemData(item.id) else { return problem("the \(item.type) item's data is out of bounds") }
        if isXMP {
            inventory.append(XMPReader.read(data))
            return
        }
        // The Exif item starts with a 4-byte offset to the TIFF header (ISO/IEC 23008-12 A.2.1).
        guard let headerOffset = Self.integer(in: data, at: 0, size: 4), 4 + headerOffset <= data.count else {
            return problem("unreadable Exif item")
        }
        inventory.append(TIFFReader.read(Array(data[(4 + headerOffset)...])).inventory)
    }

    /// An item's bytes, joined from its extents.
    ///
    /// - Parameter id: The item ID.
    /// - Returns: The bytes, or `nil` if the item has no location or one is out of bounds.
    private func itemData(_ id: Int) -> [UInt8]? {
        guard let location = locations[id] else { return nil }
        // Construction method 0 is an offset in the file, 1 an offset in `idat`; 2 (an offset
        // in another item) isn't used for metadata, so it is refused.
        let base: Range<Int>?
        switch location.constructionMethod {
        case 0: base = 0..<bytes.count
        case 1: base = itemDataRange
        default: base = nil
        }
        guard let base else { return nil }
        var data: [UInt8] = []
        for extent in location.extents {
            let range = base.lowerBound + extent.lowerBound..<base.lowerBound + extent.upperBound
            guard range.upperBound <= base.upperBound else { return nil }
            data += bytes[range]
        }
        return data
    }

    /// Splits a range of the file into boxes.
    ///
    /// - Parameter range: The bytes to split.
    /// - Returns: The boxes; reading stops at the first box that doesn't fit, with a problem.
    private mutating func boxes(in range: Range<Int>) -> [Box] {
        var result: [Box] = []
        var position = range.lowerBound
        while position < range.upperBound {
            boxCount += 1
            guard boxCount <= Self.maximumBoxes else {
                problem("too many boxes")
                break
            }
            guard var size = integer(at: position, size: 4), position + 8 <= range.upperBound else {
                problem("a box header is cut off")
                break
            }
            var header = 8
            if size == 1 {
                // A 64-bit size follows the type.
                guard let largeSize = integer(at: position + 8, size: 8) else {
                    problem("a box header is cut off")
                    break
                }
                size = largeSize
                header = 16
            } else if size == 0 {
                size = range.upperBound - position
            }
            guard size >= header, position + size <= range.upperBound else {
                problem("a box doesn't fit")
                break
            }
            result.append(Box(type: fourCharacterCode(at: position + 4), payloadStart: position + header, end: position + size))
            position += size
        }
        return result
    }

    /// A NUL-terminated string.
    ///
    /// - Parameters:
    ///   - start: The first byte.
    ///   - end: The end of the enclosing box.
    /// - Returns: The text and the position after the NUL (or `end`).
    private func nulTerminated(from start: Int, end: Int) -> (text: String, next: Int) {
        guard start < end else { return ("", end) }
        let slice = bytes[start..<end]
        let terminator = slice.firstIndex(of: 0) ?? end
        return (String(decoding: bytes[start..<terminator], as: UTF8.self), min(terminator + 1, end))
    }

    /// A four-character code; the caller has checked that it is in bounds.
    ///
    /// - Parameter position: The first byte.
    private func fourCharacterCode(at position: Int) -> String {
        String(decoding: bytes[position..<position + 4], as: UTF8.self)
    }

    /// One byte, or `nil` past the end.
    ///
    /// - Parameter position: The byte's position.
    private func byte(_ position: Int) -> UInt8? {
        position < bytes.count ? bytes[position] : nil
    }

    /// A big-endian unsigned integer of 0 to 8 bytes in the file, or `nil` past the end. A size
    /// of 0 reads as 0, as ISOBMFF specifies for absent fields.
    ///
    /// - Parameters:
    ///   - position: The first byte.
    ///   - size: The number of bytes.
    private func integer(at position: Int, size: Int) -> Int? {
        Self.integer(in: bytes, at: position, size: size)
    }

    /// A big-endian unsigned integer of 0 to 8 bytes in a buffer, or `nil` past the end or when
    /// it is larger than an eighth of `Int.max`, so sums of a few of them can't overflow.
    ///
    /// - Parameters:
    ///   - buffer: The bytes.
    ///   - position: The first byte.
    ///   - size: The number of bytes.
    static func integer(in buffer: [UInt8], at position: Int, size: Int) -> Int? {
        guard size <= 8, position + size <= buffer.count else { return nil }
        let value = buffer[position..<position + size].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return value <= UInt64(Int.max / 8) ? Int(value) : nil
    }

    /// Records a problem.
    ///
    /// - Parameter description: What couldn't be read.
    private mutating func problem(_ description: String) {
        inventory.problems.append("HEIF: \(description)")
    }
}
