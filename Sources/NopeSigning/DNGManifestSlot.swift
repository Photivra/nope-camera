import Foundation

/// Makes room for a Content Credentials store in a DNG while keeping IFD0 where it is.
///
/// Why this exists (issue #66): the C2PA library's own DNG writer appends a new copy of IFD0 at
/// the end of the file, with tag 52545 added, and points the header at it. ImageIO then no longer
/// recognizes the file as a DNG: measured on an iPhone 16 Pro Max with iOS 27.2.1,
/// `CGImageSourceCreateWithData` reports `public.tiff` with 0 images, and macOS 27 reports
/// `public.tiff` too. A DNG with the same tag inserted into IFD0 in place opens as
/// `com.adobe.raw-image` (`docs/TESTING.md`, "Signed DNG and ImageIO").
///
/// So the signer inserts the entry itself: tag 52545 (`0xCD41`), type UNDEFINED, in IFD0 at its
/// ascending tag position (C2PA 2.2, appendix A.3.3; TIFF 6.0, section 2: "The entries in an IFD
/// must be sorted in ascending order by Tag"), with the store at the end of the file. Every byte
/// after the new entry moves 12 bytes later, and every offset that points past it moves with it.
/// 12 keeps every value on the word boundary TIFF requires. The C2PA library's data-hash
/// workflow then hashes the file with the store excluded and signs it, and the signed store
/// replaces the placeholder byte for byte (``ContentCredentialsSigner``).
///
/// Privacy rule: this adds the Content Credentials store and its entry and changes nothing else.
/// It never removes or rewrites a tag (AGENTS.md, "remove metadata through system APIs, never by
/// editing bytes"). It is byte-level code, so it is fuzz-tested (`DNGManifestSlotTests`), and the
/// signed file is read back against the allowlist like every other file.
///
/// Limits, each rejected with ``Failure``: classic TIFF only (not BigTIFF), at most
/// ``maximumDirectories`` directories, a file that already has tag 52545, a value that crosses
/// the insertion point, and an offset stored as SHORT that would no longer fit. Data whose own
/// contents hold absolute file offsets can't be fixed up; of the tags nope. allows, only the
/// Apple maker note (`0x927C`) holds offsets, and those are relative to the maker note's own
/// start (an assumption from ExifTool's Apple maker note table, checked on a device with an
/// exiftool dump of a signed DNG: `docs/PRIVACY.md`, "Device checks").
enum DNGManifestSlot {
    /// Why a file can't take a store.
    enum Failure: Error, Equatable {
        /// The bytes aren't a classic TIFF, or a directory or value lies outside the file.
        case unreadable
        /// The file already has a Content Credentials store.
        case alreadyHasStore
        /// A value starts before the insertion point and ends after it.
        case valueCrossesInsertionPoint
        /// An offset stored as SHORT, or the grown file, wouldn't fit its field.
        case tooLarge
        /// A store to put in the slot isn't the slot's size, so it would move other bytes.
        case storeSizeChanged
    }

    /// A DNG with room for the store.
    struct Bound: Equatable {
        /// The file with the new entry and, at the end, the placeholder store.
        let file: Data
        /// Where the store is: what the data hash excludes, and what the signed store replaces.
        let storeRange: Range<Int>

        /// Creates a bound file.
        ///
        /// - Parameters:
        ///   - file: The file with the entry and the placeholder store.
        ///   - storeRange: Where the store is in the file.
        init(file: Data, storeRange: Range<Int>) {
            self.file = file
            self.storeRange = storeRange
        }

        /// The file with a store in the slot.
        ///
        /// - Parameter store: The placeholder or the signed store.
        /// - Returns: The file.
        /// - Throws: ``Failure/storeSizeChanged`` unless the store is exactly the slot's size.
        func replacingStore(with store: Data) throws(Failure) -> Data {
            guard store.count == storeRange.count else { throw .storeSizeChanged }
            var result = file
            result.replaceSubrange(storeRange, with: store)
            return result
        }
    }

    /// The Content Credentials tag, 52545 (C2PA 2.2, appendix A.3.3).
    static let storeTag: UInt16 = 0xCD41
    /// The UNDEFINED field type (TIFF 6.0, section 2).
    static let undefinedType: UInt16 = 7
    /// The size of one IFD entry, and so how far every later byte moves.
    static let entrySize = 12
    /// More directories than any DNG nope. writes; a file with more is rejected, so a loop or a
    /// hostile file can't make the walk unbounded.
    static let maximumDirectories = 64

    /// Pointer tags whose values are offsets of child directories (TIFF 6.0 and its supplements,
    /// EXIF 3.0): SubIFDs, the EXIF, GPS and interoperability directories.
    static let directoryPointerTags: Set<UInt16> = [0x014A, 0x8769, 0x8825, 0xA005]
    /// Tags whose values are offsets of image data: StripOffsets, FreeOffsets, TileOffsets and
    /// JPEGInterchangeFormat (TIFF 6.0, sections 3, 8, 15 and 22).
    static let dataOffsetTags: Set<UInt16> = [0x0111, 0x0120, 0x0144, 0x0201]
    /// Bytes per value of each TIFF field type (TIFF 6.0, section 2; type 13, IFD, from the
    /// TIFF supplement 1).
    static let typeSizes: [UInt16: Int] = [
        1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, 13: 4,
    ]

    /// Inserts tag 52545 into IFD0 and appends a store of zeros.
    ///
    /// - Parameters:
    ///   - storeLength: The store's exact length in bytes, more than 4 (the placeholder's length).
    ///   - dng: The DNG, as written and read back.
    /// - Returns: The new file and where the store is in it.
    /// - Throws: ``Failure`` if the file can't take the store safely.
    static func insert(storeLength: Int, into dng: Data) throws(Failure) -> Bound {
        var layout = try Layout(bytes: [UInt8](dng))
        try layout.walk()
        return try layout.insert(storeLength: storeLength)
    }
}

extension DNGManifestSlot {
    /// One 4-byte offset somewhere in the file, and the value it holds.
    struct Offset {
        /// Where the field is.
        let position: Int
        /// Whether the field is a SHORT (2 bytes) rather than a LONG.
        let isShort: Bool
        /// The offset it holds.
        let value: Int

        /// Records an offset field.
        ///
        /// - Parameters:
        ///   - position: Where the field is, in bytes from the start of the file.
        ///   - isShort: Whether the field is a SHORT.
        ///   - value: The offset it holds, in bytes from the start of the file.
        init(position: Int, isShort: Bool, value: Int) {
            self.position = position
            self.isShort = isShort
            self.value = value
        }
    }

    /// The parsed file: its byte order, IFD0, and every offset field found by the walk.
    struct Layout {
        /// The file.
        let bytes: [UInt8]
        /// Whether the file is big-endian (`MM`).
        let bigEndian: Bool
        /// Where IFD0 starts.
        let firstDirectory: Int
        /// Every offset field.
        private(set) var offsets: [Offset] = []
        /// Every out-of-line value, as a byte range, to check none crosses the insertion point.
        private(set) var values: [Range<Int>] = []
        /// Directories already read, against loops.
        private var visited: Set<Int> = []

        /// Reads the header.
        ///
        /// - Parameter bytes: The file.
        /// - Throws: ``Failure/unreadable`` for anything but a classic TIFF header.
        init(bytes: [UInt8]) throws(Failure) {
            guard bytes.count >= 8 else { throw .unreadable }
            switch (bytes[0], bytes[1]) {
            case (0x49, 0x49): bigEndian = false
            case (0x4D, 0x4D): bigEndian = true
            default: throw .unreadable
            }
            self.bytes = bytes
            guard Self.u16(bytes, 2, bigEndian: bigEndian) == 42 else { throw .unreadable }
            firstDirectory = Self.u32(bytes, 4, bigEndian: bigEndian)
        }

        /// The insertion point: after IFD0's entries with a lower tag number.
        var insertionPoint: Int {
            let count = u16(firstDirectory)
            let lower = (0..<count).filter { u16(firstDirectory + 2 + $0 * entrySize) < Int(storeTag) }.count
            return firstDirectory + 2 + lower * entrySize
        }

        /// Walks every directory reachable from the header, recording offsets and values.
        ///
        /// - Throws: ``Failure`` for an unreadable directory or value, or an existing store.
        mutating func walk() throws(Failure) {
            try walkChain(from: firstDirectory, isMain: true)
        }

        /// Walks a directory and the directories chained after it.
        ///
        /// - Parameters:
        ///   - start: The first directory's offset.
        ///   - isMain: Whether this is IFD0's chain, where a store may not already be.
        private mutating func walkChain(from start: Int, isMain: Bool) throws(Failure) {
            var next = start
            var first = isMain
            while next != 0 {
                next = try walkDirectory(at: next, isFirst: first)
                first = false
            }
        }

        /// Records one directory's offsets and values, walks its children, and returns the
        /// next directory's offset.
        ///
        /// - Parameters:
        ///   - start: Where the directory starts.
        ///   - isFirst: Whether it is IFD0.
        /// - Returns: The next directory's offset, 0 for none.
        private mutating func walkDirectory(at start: Int, isFirst: Bool) throws(Failure) -> Int {
            guard visited.count < maximumDirectories, visited.insert(start).inserted,
                start + 2 <= bytes.count
            else { throw .unreadable }
            let count = u16(start)
            let nextField = start + 2 + count * entrySize
            guard nextField + 4 <= bytes.count else { throw .unreadable }
            for index in 0..<count {
                try walkEntry(at: start + 2 + index * entrySize, inFirst: isFirst)
            }
            offsets.append(Offset(position: nextField, isShort: false, value: u32(nextField)))
            return u32(nextField)
        }

        /// Records one entry's out-of-line value, the offsets it holds, and its child
        /// directories.
        ///
        /// - Parameters:
        ///   - position: Where the entry starts.
        ///   - inFirst: Whether the entry is in IFD0.
        private mutating func walkEntry(at position: Int, inFirst: Bool) throws(Failure) {
            let tag = UInt16(u16(position))
            let type = UInt16(u16(position + 2))
            let count = u32(position + 4)
            if inFirst && tag == storeTag { throw .alreadyHasStore }
            // An unknown type's size is unknown, so where its value is can't be known either.
            guard let size = typeSizes[type] else { throw .unreadable }
            let length = size * count
            var valueStart = position + 8
            if length > 4 {
                valueStart = u32(position + 8)
                guard valueStart + length <= bytes.count else { throw .unreadable }
                offsets.append(Offset(position: position + 8, isShort: false, value: valueStart))
                values.append(valueStart..<valueStart + length)
            }
            let pointsToDirectories = directoryPointerTags.contains(tag)
            guard pointsToDirectories || dataOffsetTags.contains(tag) else { return }
            guard type == 3 || type == 4 || type == 13 else { throw .unreadable }
            for index in 0..<count {
                let field = valueStart + index * size
                let value = size == 2 ? u16(field) : u32(field)
                offsets.append(Offset(position: field, isShort: size == 2, value: value))
                if pointsToDirectories { try walkChain(from: value, isMain: false) }
            }
        }

        /// Builds the new file.
        ///
        /// - Parameter storeLength: The store's length.
        /// - Returns: The file and the store's range.
        /// - Throws: ``Failure`` if a value crosses the insertion point or a field overflows.
        func insert(storeLength: Int) throws(Failure) -> Bound {
            let point = insertionPoint
            guard values.allSatisfy({ !($0.lowerBound < point && $0.upperBound > point) }) else {
                throw .valueCrossesInsertionPoint
            }
            guard u16(firstDirectory) < Int(UInt16.max) else { throw .tooLarge }
            var file = bytes
            for offset in offsets where offset.value >= point {
                let moved = offset.value + entrySize
                guard !offset.isShort || moved <= Int(UInt16.max) else { throw .tooLarge }
                write(moved, at: offset.position, isShort: offset.isShort, into: &file)
            }
            write(u16(firstDirectory) + 1, at: firstDirectory, isShort: true, into: &file)
            // The store starts on a word boundary (TIFF 6.0, section 2).
            let shiftedLength = file.count + entrySize
            let storeStart = shiftedLength + shiftedLength % 2
            guard storeLength > 4, storeStart + storeLength <= Int(UInt32.max) else { throw .tooLarge }
            var entry = [UInt8](repeating: 0, count: entrySize)
            write(Int(storeTag), at: 0, isShort: true, into: &entry)
            write(Int(undefinedType), at: 2, isShort: true, into: &entry)
            write(storeLength, at: 4, isShort: false, into: &entry)
            write(storeStart, at: 8, isShort: false, into: &entry)
            file.insert(contentsOf: entry, at: point)
            file += [UInt8](repeating: 0, count: storeStart - file.count + storeLength)
            return Bound(file: Data(file), storeRange: storeStart..<storeStart + storeLength)
        }

        /// Writes a SHORT or LONG in the file's byte order.
        ///
        /// - Parameters:
        ///   - value: The value; it fits the field.
        ///   - position: Where the field is.
        ///   - isShort: Whether it is 2 bytes rather than 4.
        ///   - target: The bytes to change.
        private func write(_ value: Int, at position: Int, isShort: Bool, into target: inout [UInt8]) {
            let width = isShort ? 2 : 4
            for index in 0..<width {
                let shift = 8 * (bigEndian ? width - 1 - index : index)
                target[position + index] = UInt8(truncatingIfNeeded: value >> shift)
            }
        }

        /// A 16-bit value; the caller has checked the bounds.
        private func u16(_ offset: Int) -> Int {
            Self.u16(bytes, offset, bigEndian: bigEndian)
        }

        /// A 32-bit value; the caller has checked the bounds.
        private func u32(_ offset: Int) -> Int {
            Self.u32(bytes, offset, bigEndian: bigEndian)
        }

        /// A 16-bit value in a byte order.
        ///
        /// - Parameters:
        ///   - bytes: The file.
        ///   - offset: Where the value starts; `offset + 2` is within the file.
        ///   - bigEndian: The byte order.
        static func u16(_ bytes: [UInt8], _ offset: Int, bigEndian: Bool) -> Int {
            let (first, second) = (Int(bytes[offset]), Int(bytes[offset + 1]))
            return bigEndian ? first << 8 | second : second << 8 | first
        }

        /// A 32-bit value in a byte order.
        ///
        /// - Parameters:
        ///   - bytes: The file.
        ///   - offset: Where the value starts; `offset + 4` is within the file.
        ///   - bigEndian: The byte order.
        static func u32(_ bytes: [UInt8], _ offset: Int, bigEndian: Bool) -> Int {
            let (first, second) = (u16(bytes, offset, bigEndian: bigEndian), u16(bytes, offset + 2, bigEndian: bigEndian))
            return bigEndian ? first << 16 | second : second << 16 | first
        }
    }
}
