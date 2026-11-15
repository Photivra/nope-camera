import Foundation
import ImageIO
import NopeCore
import Testing

@testable import NopeSigning

/// A small seeded random number generator (SplitMix64), so every fuzz run is reproducible.
struct SlotRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Writes TIFF files with any layout the slot must handle: either byte order, IFD0 first or
/// last, out-of-line values, image data on both sides of IFD0, SubIFDs, EXIF and GPS directories,
/// a chained IFD1 and SHORT or LONG offsets. Test-only.
struct SlotTIFF {
    /// One entry: a plain value, child directories, or image data the entry points to.
    enum Value {
        case bytes(type: UInt16, count: Int, [UInt8])
        case directories([Directory])
        case data(type: UInt16, [[UInt8]])
    }

    /// One directory and the directory chained after it.
    final class Directory {
        var entries: [(UInt16, Value)]
        var next: Directory?
        init(_ entries: [(UInt16, Value)], next: Directory? = nil) {
            self.entries = entries
            self.next = next
        }
    }

    let bigEndian: Bool
    /// Whether IFD0 comes after everything it points to.
    let firstDirectoryLast: Bool
    private(set) var bytes: [UInt8] = []

    init(bigEndian: Bool, firstDirectoryLast: Bool = false) {
        self.bigEndian = bigEndian
        self.firstDirectoryLast = firstDirectoryLast
    }

    func u16(_ value: Int) -> [UInt8] {
        let pair = [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
        return bigEndian ? pair : pair.reversed()
    }

    func u32(_ value: Int) -> [UInt8] {
        bigEndian ? u16(value >> 16) + u16(value & 0xFFFF) : u16(value & 0xFFFF) + u16(value >> 16)
    }

    /// The whole file.
    static func build(_ root: Directory, bigEndian: Bool = false, firstDirectoryLast: Bool = false) -> Data {
        var writer = SlotTIFF(bigEndian: bigEndian, firstDirectoryLast: firstDirectoryLast)
        writer.bytes = (bigEndian ? [0x4D, 0x4D] : [0x49, 0x49]) + writer.u16(42) + [0, 0, 0, 0]
        let first = writer.write(root)
        writer.bytes.replaceSubrange(4..<8, with: writer.u32(first))
        return Data(writer.bytes)
    }

    /// Appends the data an entry points to and returns the entry's 4 value bytes.
    private mutating func payload(for value: Value) -> (type: UInt16, count: Int, field: [UInt8]) {
        switch value {
        case .bytes(let type, let count, let raw):
            guard raw.count > 4 else { return (type, count, raw + Array(repeating: 0, count: 4 - raw.count)) }
            align()
            let at = bytes.count
            bytes += raw
            return (type, count, u32(at))
        case .directories(let children):
            let offsets = children.map { write($0) }
            return arrayField(type: 4, offsets)
        case .data(let type, let blobs):
            var offsets: [Int] = []
            for blob in blobs {
                align()
                offsets.append(bytes.count)
                bytes += blob
            }
            return arrayField(type: type, offsets)
        }
    }

    /// The field for an array of offsets, stored out of line when it doesn't fit.
    private mutating func arrayField(type: UInt16, _ offsets: [Int]) -> (type: UInt16, count: Int, field: [UInt8]) {
        let raw = offsets.flatMap { type == 3 ? u16($0) : u32($0) }
        guard raw.count > 4 else { return (type, offsets.count, raw + Array(repeating: 0, count: 4 - raw.count)) }
        align()
        let at = bytes.count
        bytes += raw
        return (type, offsets.count, u32(at))
    }

    private mutating func align() {
        if bytes.count % 2 == 1 { bytes.append(0) }
    }

    /// Writes a directory: its values first when IFD0 goes last, else the table first.
    @discardableResult
    mutating func write(_ directory: Directory) -> Int {
        let entries = directory.entries.sorted { $0.0 < $1.0 }
        if firstDirectoryLast {
            let fields = entries.map { (tag: $0.0, payload: payload(for: $0.1)) }
            let next = directory.next.map { write($0) } ?? 0
            align()
            let start = bytes.count
            bytes += u16(fields.count)
            for (tag, field) in fields { bytes += u16(Int(tag)) + u16(Int(field.type)) + u32(field.count) + field.field }
            bytes += u32(next)
            return start
        }
        align()
        let start = bytes.count
        bytes += u16(entries.count) + Array(repeating: 0, count: entries.count * 12 + 4)
        for (index, (tag, value)) in entries.enumerated() {
            let field = payload(for: value)
            bytes.replaceSubrange(
                start + 2 + index * 12..<start + 14 + index * 12,
                with: u16(Int(tag)) + u16(Int(field.type)) + u32(field.count) + field.field)
        }
        if let next = directory.next {
            let offset = write(next)
            bytes.replaceSubrange(start + 2 + entries.count * 12..<start + 6 + entries.count * 12, with: u32(offset))
        }
        return start
    }
}

/// An independent reader for the tests: every directory in tree order, each entry's tag, type,
/// count and value bytes, with pointers and image offsets replaced by what they point to.
enum SlotReader {
    struct Entry: Equatable {
        let tag: UInt16
        let type: UInt16
        let count: Int
        let value: [UInt8]
    }

    static let sizes: [UInt16: Int] = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, 13: 4]

    /// Every directory's entries; an image data entry's value is the first 2 bytes at each offset
    /// (every test blob is at least that long), and a pointer's is empty: its children follow.
    static func read(_ data: Data) -> [[Entry]] {
        let bytes = [UInt8](data)
        let big = bytes[0] == 0x4D
        func u16(_ at: Int) -> Int { big ? Int(bytes[at]) << 8 | Int(bytes[at + 1]) : Int(bytes[at + 1]) << 8 | Int(bytes[at]) }
        func u32(_ at: Int) -> Int { big ? u16(at) << 16 | u16(at + 2) : u16(at + 2) << 16 | u16(at) }
        var directories: [[Entry]] = []
        func walk(_ start: Int) {
            var offset = start
            while offset != 0 {
                let count = u16(offset)
                var entries: [Entry] = []
                var children: [Int] = []
                for index in 0..<count {
                    let at = offset + 2 + index * 12
                    let tag = UInt16(u16(at))
                    let type = UInt16(u16(at + 2))
                    let number = u32(at + 4)
                    let length = sizes[type]! * number
                    let valueAt = length > 4 ? u32(at + 8) : at + 8
                    var value = Array(bytes[valueAt..<valueAt + length])
                    if DNGManifestSlot.directoryPointerTags.contains(tag) || DNGManifestSlot.dataOffsetTags.contains(tag) {
                        let targets = (0..<number).map { type == 3 ? u16(valueAt + $0 * 2) : u32(valueAt + $0 * 4) }
                        if DNGManifestSlot.directoryPointerTags.contains(tag) {
                            children += targets
                            value = []
                        } else {
                            value = targets.flatMap { Array(bytes[$0..<min($0 + 2, bytes.count)]) }
                        }
                    }
                    if tag == DNGManifestSlot.storeTag { value = Array(bytes[valueAt..<valueAt + length]) }
                    entries.append(Entry(tag: tag, type: type, count: number, value: value))
                }
                directories.append(entries)
                children.forEach(walk)
                offset = u32(offset + 2 + count * 12)
            }
        }
        walk(u32(4))
        return directories
    }
}

@Suite(.timeLimit(.minutes(1)))
struct DNGManifestSlotTests {
    /// A layout with everything the walk follows: out-of-line values, a SubIFD with its own
    /// strips, EXIF and GPS directories (with an interoperability directory), IFD1 with a JPEG
    /// thumbnail offset, SHORT strip offsets, and tags after 52545.
    static func richRoot(shortOffsets: Bool = false) -> SlotTIFF.Directory {
        let interop = SlotTIFF.Directory([(0x0001, .bytes(type: 2, count: 4, Array("R98\0".utf8)))])
        let exif = SlotTIFF.Directory([
            (0x829A, .bytes(type: 5, count: 1, [0, 0, 0, 1, 0, 0, 0, 60])),
            (0xA005, .directories([interop])),
        ])
        let gps = SlotTIFF.Directory([(0x0001, .bytes(type: 2, count: 2, Array("N\0".utf8)))])
        let sub = SlotTIFF.Directory([(0x0111, .data(type: 4, [[1, 2, 3, 4, 5, 6, 7, 8], [9, 10, 11, 12]]))])
        let ifd1 = SlotTIFF.Directory([(0x0201, .data(type: 4, [[0xFF, 0xD8, 0xFF, 0xD9]]))])
        return SlotTIFF.Directory(
            [
                (0x00FE, .bytes(type: 4, count: 1, [0, 0, 0, 0])),
                (0x0110, .bytes(type: 2, count: 12, Array("Test model\0\0".utf8))),
                (0x0111, .data(type: shortOffsets ? 3 : 4, [Array(repeating: 7, count: 32), Array(repeating: 8, count: 32)])),
                (0x014A, .directories([sub])),
                (0x8769, .directories([exif])),
                (0x8825, .directories([gps])),
                (0xC612, .bytes(type: 1, count: 4, [1, 4, 0, 0])),
                (0xC621, .bytes(type: 10, count: 2, [0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4])),
                (0xC7FE, .bytes(type: 3, count: 1, [0, 1])),
            ], next: ifd1)
    }

    /// The reader's view with the store entry taken out.
    static func withoutStore(_ directories: [[SlotReader.Entry]]) -> [[SlotReader.Entry]] {
        directories.map { $0.filter { $0.tag != DNGManifestSlot.storeTag } }
    }

    @Test(arguments: [false, true], [false, true])
    func insertionKeepsEveryValueAndAddsOnlyTheStore(bigEndian: Bool, firstDirectoryLast: Bool) throws {
        let original = SlotTIFF.build(Self.richRoot(), bigEndian: bigEndian, firstDirectoryLast: firstDirectoryLast)
        let bound = try DNGManifestSlot.insert(storeLength: 40, into: original)
        let before = SlotReader.read(original)
        let after = SlotReader.read(bound.file)
        #expect(Self.withoutStore(after) == before)
        // The entry is in IFD0, in tag order, type UNDEFINED, and points at the store at the end.
        let first = try #require(after.first)
        #expect(first.map(\.tag) == first.map(\.tag).sorted())
        let store = try #require(first.first { $0.tag == DNGManifestSlot.storeTag })
        #expect(store.type == 7 && store.count == 40 && store.value == Array(repeating: 0, count: 40))
        #expect(bound.storeRange.upperBound == bound.file.count)
        #expect(bound.storeRange.lowerBound % 2 == 0)
        // IFD0 stays where it was, and the file grows by the entry, any padding and the store.
        #expect(bound.file.prefix(8) == original.prefix(8))
        #expect(bound.file.count - original.count - 12 - 40 <= 1)
    }

    @Test func shortStripOffsetsMoveToo() throws {
        let original = SlotTIFF.build(Self.richRoot(shortOffsets: true))
        let bound = try DNGManifestSlot.insert(storeLength: 8, into: original)
        #expect(Self.withoutStore(SlotReader.read(bound.file)) == SlotReader.read(original))
    }

    @Test func theProjectReaderSeesTheSameTagsAndRAWData() throws {
        let original = SyntheticPhotos.dng()
        let bound = try DNGManifestSlot.insert(storeLength: 1000, into: original)
        let before = MetadataFileReader.read(original, format: .raw)
        let after = MetadataFileReader.read(bound.file, format: .raw)
        #expect(after.inventory.problems.isEmpty)
        #expect(after.inventory.tags.filter { $0.tag != DNGManifestSlot.storeTag } == before.inventory.tags)
        #expect(after.rawImageData == before.rawImageData)
        #expect(after.rawImageData != nil)
        #expect(ImageIOType.read(bound.file) == ImageIOType(type: ImageIOType.of(.raw), count: 1))
    }

    @Test func aStoreMustFitItsSlotExactly() throws {
        let bound = try DNGManifestSlot.insert(storeLength: 10, into: SyntheticPhotos.dng())
        let filled = try bound.replacingStore(with: Data(repeating: 0xAB, count: 10))
        #expect(filled.count == bound.file.count)
        #expect(filled.suffix(10) == Data(repeating: 0xAB, count: 10))
        #expect(throws: DNGManifestSlot.Failure.storeSizeChanged) { try bound.replacingStore(with: Data(count: 9)) }
        #expect(throws: DNGManifestSlot.Failure.storeSizeChanged) { try bound.replacingStore(with: Data(count: 11)) }
    }

    /// Each kind of file the slot refuses, rather than guessing.
    @Test func filesItCantHandleSafelyAreRejected() {
        func rejects(_ data: Data, _ failure: DNGManifestSlot.Failure, storeLength: Int = 16, line: Int = #line) {
            #expect(throws: failure, "line \(line)") { try DNGManifestSlot.insert(storeLength: storeLength, into: data) }
        }
        let good = SlotTIFF.build(Self.richRoot())
        rejects(Data([0x49, 0x49, 42]), .unreadable)
        rejects(Data("XX".utf8) + good.dropFirst(2), .unreadable)
        var notClassic = good
        notClassic[2] = 43
        rejects(notClassic, .unreadable)
        var pastEnd = good
        pastEnd.replaceSubrange(4..<8, with: [0xF0, 0xFF, 0, 0])
        rejects(pastEnd, .unreadable)
        rejects(good.prefix(20), .unreadable)  // IFD0's table runs past the end
        rejects(SlotTIFF.build(SlotTIFF.Directory([(0x0100, .bytes(type: 99, count: 1, [1]))])), .unreadable)
        rejects(SlotTIFF.build(SlotTIFF.Directory([(0x0100, .bytes(type: 4, count: 900, [1, 2, 3, 4, 5]))])), .unreadable)
        rejects(SlotTIFF.build(SlotTIFF.Directory([(0x8769, .bytes(type: 2, count: 2, [0, 0]))])), .unreadable)
        rejects(SlotTIFF.build(SlotTIFF.Directory([(0xCD41, .bytes(type: 7, count: 8, Array(repeating: 1, count: 8)))])), .alreadyHasStore)
        rejects(good, .tooLarge, storeLength: 4)
        rejects(good, .tooLarge, storeLength: Int(UInt32.max))
        // A loop: IFD0's next directory is IFD0.
        var loop = SlotTIFF.build(SlotTIFF.Directory([(0x0100, .bytes(type: 3, count: 1, [1, 0]))]))
        loop.replaceSubrange(8 + 2 + 12..<8 + 2 + 12 + 4, with: [8, 0, 0, 0])
        rejects(loop, .unreadable)
        // A chain longer than any DNG.
        var chain = SlotTIFF.Directory([(0x0100, .bytes(type: 3, count: 1, [1, 0]))])
        for _ in 0..<DNGManifestSlot.maximumDirectories { chain = SlotTIFF.Directory(chain.entries, next: chain) }
        rejects(SlotTIFF.build(chain), .unreadable)
        // IFD0 holds 65,535 entries, the most its count can say, so there's no room for one more.
        rejects(Self.fullDirectory(), .tooLarge)
    }

    /// A value that starts before the insertion point and ends after it: IFD0 is written inside
    /// an out-of-line value's bytes.
    @Test func aValueAcrossTheInsertionPointIsRejected() throws {
        var bytes: [UInt8] = [0x49, 0x49, 42, 0, 16, 0, 0, 0]
        // Value bytes 8..<60 cover IFD0 at 16; IFD0's one entry (tag 0x0100) points at them.
        bytes += Array(repeating: 0, count: 8)
        bytes += [1, 0] + [0x00, 0x01, 1, 0, 52, 0, 0, 0, 8, 0, 0, 0] + [0, 0, 0, 0]
        bytes += Array(repeating: 0, count: 60 - bytes.count)
        #expect(throws: DNGManifestSlot.Failure.valueCrossesInsertionPoint) {
            try DNGManifestSlot.insert(storeLength: 8, into: Data(bytes))
        }
    }

    /// A SHORT strip offset past the insertion point that would no longer fit in 16 bits.
    @Test func aShortOffsetThatWouldOverflowIsRejected() {
        // IFD0's table ends at 38, so the 65,490 bytes put the strip at 65,528: a SHORT now,
        // 65,540 after the move.
        let big = Array(repeating: UInt8(1), count: 65_490)
        let root = SlotTIFF.Directory([
            (0x0100, .bytes(type: 1, count: big.count, big)),
            (0x0111, .data(type: 3, [[1, 2]])),
        ])
        #expect(throws: DNGManifestSlot.Failure.tooLarge) {
            try DNGManifestSlot.insert(storeLength: 8, into: SlotTIFF.build(root))
        }
    }

    static func fullDirectory() -> Data {
        var bytes: [UInt8] = [0x49, 0x49, 42, 0, 8, 0, 0, 0, 0xFF, 0xFF]
        for _ in 0..<65_535 {
            bytes += [0xFE, 0x00, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0]
        }
        return Data(bytes + [0, 0, 0, 0])
    }

    /// Random layouts: the slot keeps every value. Random damage to them: the slot either
    /// rejects the file or returns one, and never crashes or reads out of bounds (seeded).
    @Test func fuzzedLayoutsKeepEveryValueAndDamagedFilesNeverCrash() throws {
        var random = SlotRandom(state: 0x6E6F_7065)
        for round in 0..<400 {
            let root = Self.randomDirectory(depth: 0, using: &random)
            let file = SlotTIFF.build(root, bigEndian: Bool.random(using: &random), firstDirectoryLast: Bool.random(using: &random))
            let length = Int.random(in: 5...64, using: &random)
            let bound = try DNGManifestSlot.insert(storeLength: length, into: file)
            #expect(Self.withoutStore(SlotReader.read(bound.file)) == SlotReader.read(file), "round \(round)")
            var damaged = [UInt8](file)
            for _ in 0..<Int.random(in: 1...6, using: &random) {
                damaged[Int.random(in: 0..<damaged.count, using: &random)] = UInt8.random(in: 0...255, using: &random)
            }
            if Bool.random(using: &random) { damaged.removeLast(Int.random(in: 0..<damaged.count, using: &random)) }
            _ = try? DNGManifestSlot.insert(storeLength: length, into: Data(damaged))
        }
    }

    static func randomDirectory(depth: Int, using random: inout SlotRandom) -> SlotTIFF.Directory {
        var tags = Set<UInt16>()
        var entries: [(UInt16, SlotTIFF.Value)] = []
        for _ in 0..<Int.random(in: 1...8, using: &random) {
            let tag = [UInt16(0x0100), 0x0110, 0x0132, 0x829A, 0xC612, 0xC621, 0xC7FE, 0xD000].randomElement(using: &random)!
            guard tags.insert(tag).inserted else { continue }
            let type = [UInt16(1), 2, 3, 4, 5, 7, 10].randomElement(using: &random)!
            let count = Int.random(in: 1...6, using: &random)
            let raw = (0..<count * SlotReader.sizes[type]!).map { _ in UInt8.random(in: 0...255, using: &random) }
            entries.append((tag, .bytes(type: type, count: count, raw)))
        }
        let blobs = (0..<Int.random(in: 1...3, using: &random)).map { _ in
            (0..<Int.random(in: 2...20, using: &random)).map { _ in UInt8.random(in: 0...255, using: &random) }
        }
        entries.append((Bool.random(using: &random) ? 0x0111 : 0x0144, .data(type: 4, blobs)))
        if depth < 2 {
            for pointer in [UInt16(0x014A), 0x8769, 0x8825] where Bool.random(using: &random) {
                entries.append((pointer, .directories([randomDirectory(depth: depth + 1, using: &random)])))
            }
        }
        let next = depth == 0 && Bool.random(using: &random) ? randomDirectory(depth: 2, using: &random) : nil
        return SlotTIFF.Directory(entries, next: next)
    }
}
