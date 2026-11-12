import Foundation

/// Lists every tag in every directory of a TIFF structure, and finds a DNG's RAW image data.
///
/// This is the project's own tag reader for the read-back (AGENTS.md, "Fail closed"). It reads
/// only; nothing here writes or edits bytes. It is written from TIFF 6.0 (section 2: header,
/// IFDs and field types), EXIF 3.0 (section 4.6: the EXIF, GPS and interoperability pointers)
/// and DNG 1.7 (SubIFDs and the RAW image directory). Every read is bounds-checked, every
/// directory is visited once, and the number of directories and entries is capped, so a damaged
/// or hostile file produces ``MetadataInventory/problems`` and never a crash. The fuzz tests in
/// `NopeCoreTests` feed it random and mutated files.
struct TIFFReader {
    /// The most directories a file may have. nope.'s DNG has two (IFD0 and EXIF).
    static let maximumDirectories = 64
    /// The most entries one directory may have. nope.'s largest has about 40.
    static let maximumEntriesPerDirectory = 1024

    /// TIFF field types and their sizes in bytes (TIFF 6.0 section 2, and type 13, IFD, from
    /// TIFF Technical Note 1). Unknown types are recorded with no size.
    static let fieldTypeSizes: [UInt16: Int] = [
        1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, 13: 4,
    ]

    /// The ASCII field type.
    static let asciiType: UInt16 = 2

    /// Tag numbers this reader follows or uses.
    enum Tag {
        /// `SubIFDs` (DNG and TIFF-EP).
        static let subIFDs: UInt16 = 0x014A
        /// The EXIF directory pointer.
        static let exifPointer: UInt16 = 0x8769
        /// The GPS directory pointer.
        static let gpsPointer: UInt16 = 0x8825
        /// The interoperability directory pointer (inside the EXIF directory).
        static let interoperabilityPointer: UInt16 = 0xA005
        /// `StripOffsets`.
        static let stripOffsets: UInt16 = 0x0111
        /// `StripByteCounts`.
        static let stripByteCounts: UInt16 = 0x0117
        /// `TileOffsets`.
        static let tileOffsets: UInt16 = 0x0144
        /// `TileByteCounts`.
        static let tileByteCounts: UInt16 = 0x0145
    }

    /// The result of reading a TIFF structure.
    struct Result: Equatable {
        /// Every tag found, and any problem.
        var inventory = MetadataInventory()
        /// The bytes of IFD0's image data (its tiles or strips, concatenated in order), or
        /// `nil` when IFD0 has none. For nope.'s DNG this is the compressed RAW sensor data.
        var primaryImageData: Data?

        /// Creates an empty result: no tags, no problems and no image data.
        init() {}
    }

    /// One IFD entry's location in the file.
    private struct Entry {
        /// The tag number.
        let tag: UInt16
        /// The field type.
        let type: UInt16
        /// The number of values.
        let count: Int
        /// Where the values start, or `nil` if they are out of bounds or the type is unknown.
        let valueOffset: Int?
    }

    /// The file's bytes.
    private let bytes: [UInt8]
    /// Whether the file is big-endian (`MM`).
    private var bigEndian = false
    /// Directory offsets already read, to stop loops.
    private var visited = Set<Int>()
    /// The number of directories read so far.
    private var directoryCount = 0
    /// What has been found so far.
    private var result = Result()

    /// Creates a reader over a file's bytes.
    ///
    /// - Parameter bytes: The TIFF structure, starting at its byte order mark.
    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Reads a TIFF structure.
    ///
    /// - Parameters:
    ///   - bytes: The bytes, starting at the `II` or `MM` byte order mark.
    ///   - extractImageData: Whether to collect IFD0's image data (only for a DNG).
    /// - Returns: Every tag, the problems, and IFD0's image data if asked for.
    static func read(_ bytes: [UInt8], extractImageData: Bool = false) -> Result {
        var reader = TIFFReader(bytes: bytes)
        reader.run(extractImageData: extractImageData)
        return reader.result
    }

    /// Reads the header and the chain of image directories.
    ///
    /// - Parameter extractImageData: Whether to collect IFD0's image data.
    private mutating func run(extractImageData: Bool) {
        guard bytes.count >= 8 else { return problem("shorter than a TIFF header") }
        switch (bytes[0], bytes[1]) {
        case (0x49, 0x49): bigEndian = false
        case (0x4D, 0x4D): bigEndian = true
        default: return problem("no TIFF byte order mark")
        }
        guard u16(2) == 42 else { return problem("not a classic TIFF (magic number isn't 42)") }
        var offset = Int(u32(inBounds: 4))
        var directory = TIFFDirectory.primary
        while offset != 0 {
            guard let (entries, next) = readDirectory(at: offset, as: directory) else { return }
            if directory == .primary && extractImageData {
                result.primaryImageData = imageData(in: entries)
            }
            offset = next
            directory = .followingImage
        }
    }

    /// Reads one directory, records its tags, follows its pointers, and returns its entries and
    /// the next directory's offset.
    ///
    /// - Parameters:
    ///   - offset: Where the directory starts.
    ///   - directory: Which kind of directory it is.
    /// - Returns: The entries and the next-directory offset, or `nil` if it can't be read.
    private mutating func readDirectory(at offset: Int, as directory: TIFFDirectory) -> ([Entry], Int)? {
        guard directoryCount < Self.maximumDirectories else {
            problem("too many directories")
            return nil
        }
        guard visited.insert(offset).inserted else {
            problem("a directory is linked twice (loop)")
            return nil
        }
        directoryCount += 1
        guard let count = u16(offset).map(Int.init), count <= Self.maximumEntriesPerDirectory,
            let next = u32(offset + 2 + count * 12)
        else {
            problem("unreadable \(directory.rawValue) directory")
            return nil
        }
        let entries = (0..<count).map { entry(at: offset + 2 + $0 * 12) }
        for entry in entries {
            result.inventory.tags.append(
                MetadataInventory.Tag(directory: directory, tag: entry.tag, text: text(of: entry)))
        }
        for entry in entries {
            follow(entry, from: directory)
        }
        return (entries, Int(next))
    }

    /// Reads one 12-byte IFD entry. The caller has checked that the whole directory is in
    /// bounds.
    ///
    /// - Parameter position: Where the entry starts.
    /// - Returns: The entry.
    private func entry(at position: Int) -> Entry {
        let tag = u16(inBounds: position)
        let type = u16(inBounds: position + 2)
        let count = Int(u32(inBounds: position + 4))
        guard let size = Self.fieldTypeSizes[type] else {
            return Entry(tag: tag, type: type, count: count, valueOffset: nil)
        }
        let length = count * size
        let start = length <= 4 ? position + 8 : Int(u32(inBounds: position + 8))
        let inBounds = start + length <= bytes.count
        return Entry(tag: tag, type: type, count: count, valueOffset: inBounds ? start : nil)
    }

    /// Follows a pointer tag into its child directories.
    ///
    /// - Parameters:
    ///   - entry: The entry.
    ///   - directory: The directory the entry is in.
    private mutating func follow(_ entry: Entry, from directory: TIFFDirectory) {
        guard let child = Self.childDirectory(of: entry.tag, in: directory) else { return }
        let offsets = values(of: entry)
        guard !offsets.isEmpty else { return problem("an unreadable pointer to the \(child.rawValue) directory") }
        for offset in offsets {
            var next: Int? = offset
            // SubIFDs may chain further directories; the EXIF and GPS directories end with 0.
            while let current = next, current != 0 {
                next = readDirectory(at: current, as: child)?.1
            }
        }
    }

    /// The directory a pointer tag leads to, or `nil` if the tag isn't a pointer there.
    ///
    /// - Parameters:
    ///   - tag: The tag number.
    ///   - directory: The directory the tag is in.
    /// - Returns: The child directory.
    static func childDirectory(of tag: UInt16, in directory: TIFFDirectory) -> TIFFDirectory? {
        switch (directory, tag) {
        case (.primary, Tag.subIFDs), (.subImage, Tag.subIFDs), (.followingImage, Tag.subIFDs): .subImage
        case (.primary, Tag.exifPointer), (.followingImage, Tag.exifPointer): .exif
        case (.primary, Tag.gpsPointer), (.followingImage, Tag.gpsPointer): .gps
        case (.exif, Tag.interoperabilityPointer): .interoperability
        default: nil
        }
    }

    /// The unsigned integer values of a SHORT, LONG or IFD entry, or none for other types or
    /// out-of-bounds values.
    ///
    /// - Parameter entry: The entry.
    /// - Returns: The values.
    private func values(of entry: Entry) -> [Int] {
        guard let start = entry.valueOffset else { return [] }
        switch entry.type {
        case 3: return (0..<entry.count).compactMap { u16(start + $0 * 2).map(Int.init) }
        case 4, 13: return (0..<entry.count).compactMap { u32(start + $0 * 4).map(Int.init) }
        default: return []
        }
    }

    /// The text of an ASCII entry, up to the first NUL, or `nil` for other types.
    ///
    /// - Parameter entry: The entry.
    /// - Returns: The text.
    private func text(of entry: Entry) -> String? {
        guard entry.type == Self.asciiType, let start = entry.valueOffset else { return nil }
        let characters = bytes[start..<start + entry.count].prefix { $0 != 0 }
        return String(decoding: characters, as: UTF8.self)
    }

    /// IFD0's tiles or strips, concatenated in order.
    ///
    /// - Parameter entries: IFD0's entries.
    /// - Returns: The image data, or `nil` if IFD0 has no complete, in-bounds image data.
    private func imageData(in entries: [Entry]) -> Data? {
        func values(_ tag: UInt16) -> [Int]? {
            entries.first { $0.tag == tag }.map(self.values(of:))
        }
        guard let offsets = values(Tag.tileOffsets) ?? values(Tag.stripOffsets),
            let counts = values(Tag.tileByteCounts) ?? values(Tag.stripByteCounts),
            !offsets.isEmpty, offsets.count == counts.count
        else { return nil }
        var data = Data()
        for (offset, count) in zip(offsets, counts) {
            guard offset + count <= bytes.count else { return nil }
            data.append(contentsOf: bytes[offset..<offset + count])
        }
        return data
    }

    /// Records a problem.
    ///
    /// - Parameter description: What couldn't be read.
    private mutating func problem(_ description: String) {
        result.inventory.problems.append("TIFF: \(description)")
    }

    /// A 16-bit value in the file's byte order, or `nil` past the end.
    ///
    /// - Parameter offset: Where the value starts; never negative.
    private func u16(_ offset: Int) -> UInt16? {
        offset + 2 <= bytes.count ? u16(inBounds: offset) : nil
    }

    /// A 32-bit value in the file's byte order, or `nil` past the end.
    ///
    /// - Parameter offset: Where the value starts; never negative.
    private func u32(_ offset: Int) -> UInt32? {
        offset + 4 <= bytes.count ? u32(inBounds: offset) : nil
    }

    /// A 16-bit value the caller has already bounds-checked.
    ///
    /// - Parameter offset: Where the value starts; `offset + 2` is within the file.
    private func u16(inBounds offset: Int) -> UInt16 {
        let (first, second) = (UInt16(bytes[offset]), UInt16(bytes[offset + 1]))
        return bigEndian ? first << 8 | second : second << 8 | first
    }

    /// A 32-bit value the caller has already bounds-checked.
    ///
    /// - Parameter offset: Where the value starts; `offset + 4` is within the file.
    private func u32(inBounds offset: Int) -> UInt32 {
        let (first, second) = (UInt32(u16(inBounds: offset)), UInt32(u16(inBounds: offset + 2)))
        return bigEndian ? first << 16 | second : second << 16 | first
    }
}
