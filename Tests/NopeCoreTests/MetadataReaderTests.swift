import Foundation
import Testing

@testable import NopeCore

struct TIFFReaderTests {
    typealias Directory = TIFFBuilder.Directory

    @Test(arguments: [false, true])
    func readsEveryDirectoryInBothByteOrders(bigEndian: Bool) {
        let gps = Directory([(0x0001, .ascii("N"))])
        let interoperability = Directory([(0x0001, .ascii("R98"))])
        let exif = Directory([(0x829A, .long([1, 60])), (0xA005, .directories([interoperability]))])
        let sub = Directory([(0x00FE, .long([1]))], next: Directory([(0x00FE, .long([2]))]))
        let thumbnail = Directory([(0x0103, .short([6]))])
        let root = Directory(
            [
                (0x010F, .ascii("Apple")), (0x8769, .directories([exif])), (0x8825, .directories([gps])),
                (0x014A, .directories([sub])), (0x0111, .blobs([[1, 2, 3]])), (0x0117, .long([3])),
            ], next: thumbnail)
        let result = TIFFReader.read(TIFFBuilder.build(root, bigEndian: bigEndian), extractImageData: true)
        #expect(result.inventory.problems.isEmpty)
        let found = Set(result.inventory.tags.map { "\($0.directory.rawValue):\($0.tag)" })
        #expect(
            found == [
                "primary:271", "primary:34665", "primary:34853", "primary:330", "primary:273", "primary:279",
                "exif:33434", "exif:40965", "interoperability:1", "gps:1", "subImage:254", "followingImage:259",
            ])
        #expect(result.inventory.tags.first { $0.tag == 0x010F }?.text == "Apple")
        #expect(result.primaryImageData == Data([1, 2, 3]))
    }

    @Test func readsTiledImageDataInOrder() {
        let root = Directory([(0x0144, .blobs([[1, 2], [3]])), (0x0145, .long([2, 1]))])
        #expect(TIFFReader.read(TIFFBuilder.build(root), extractImageData: true).primaryImageData == Data([1, 2, 3]))
        #expect(TIFFReader.read(TIFFBuilder.build(root)).primaryImageData == nil)
    }

    @Test func imageDataNeedsMatchingInBoundsOffsets() {
        let mismatched = Directory([(0x0111, .blobs([[1]])), (0x0117, .long([1, 1]))])
        #expect(TIFFReader.read(TIFFBuilder.build(mismatched), extractImageData: true).primaryImageData == nil)
        let outOfBounds = Directory([(0x0111, .long([4])), (0x0117, .long([9999]))])
        #expect(TIFFReader.read(TIFFBuilder.build(outOfBounds), extractImageData: true).primaryImageData == nil)
        let none = Directory([(0x0100, .short([1]))])
        #expect(TIFFReader.read(TIFFBuilder.build(none), extractImageData: true).primaryImageData == nil)
    }

    @Test func malformedHeadersAreProblems() {
        #expect(TIFFReader.read([0x49, 0x49]).inventory.problems == ["TIFF: shorter than a TIFF header"])
        #expect(TIFFReader.read(Array("XX*\0\u{8}\0\0\0".utf8)).inventory.problems == ["TIFF: no TIFF byte order mark"])
        #expect(
            TIFFReader.read([0x49, 0x49, 43, 0, 8, 0, 0, 0]).inventory.problems
                == ["TIFF: not a classic TIFF (magic number isn't 42)"])
        #expect(
            TIFFReader.read([0x49, 0x49, 42, 0, 200, 0, 0, 0]).inventory.problems == ["TIFF: unreadable primary directory"])
    }

    @Test func loopsAndUnreadablePointersAreProblems() {
        // IFD0 whose next pointer leads back to itself.
        var bytes = TIFFBuilder.build(Directory([(0x0100, .short([1]))]))
        bytes.replaceSubrange(8 + 2 + 12..<8 + 2 + 12 + 4, with: [8, 0, 0, 0])
        #expect(TIFFReader.read(bytes).inventory.problems == ["TIFF: a directory is linked twice (loop)"])
        let asciiPointer = Directory([(0x8769, .ascii("no"))])
        #expect(
            TIFFReader.read(TIFFBuilder.build(asciiPointer)).inventory.problems
                == ["TIFF: an unreadable pointer to the exif directory"])
    }

    @Test func unknownTypesAndOutOfBoundsValuesAreStillListed() {
        let root = Directory([(0x9999, .raw(type: 99, count: 1, bytes: [0])), (0x010F, .raw(type: 2, count: 400, bytes: [0x41]))])
        let inventory = TIFFReader.read(TIFFBuilder.build(root)).inventory
        #expect(inventory.tags.map(\.tag) == [0x010F, 0x9999])
        #expect(inventory.tags.allSatisfy { $0.text == nil })
    }

    @Test func directoryCountIsCapped() {
        var directory = Directory([(0x0100, .short([1]))])
        for _ in 0..<TIFFReader.maximumDirectories { directory = Directory([(0x0100, .short([1]))], next: directory) }
        #expect(TIFFReader.read(TIFFBuilder.build(directory)).inventory.problems == ["TIFF: too many directories"])
    }

    @Test func pointerTagsLeadOnlyWhereTheSpecificationsPutThem() {
        #expect(TIFFReader.childDirectory(of: 0x8769, in: .followingImage) == .exif)
        #expect(TIFFReader.childDirectory(of: 0x8825, in: .followingImage) == .gps)
        #expect(TIFFReader.childDirectory(of: 0x014A, in: .subImage) == .subImage)
        #expect(TIFFReader.childDirectory(of: 0x014A, in: .followingImage) == .subImage)
        #expect(TIFFReader.childDirectory(of: 0x8769, in: .gps) == nil)
        #expect(TIFFReader.childDirectory(of: 0xA005, in: .primary) == nil)
    }
}

struct JPEGReaderTests {
    @Test func listsEverySegmentAndTheEXIFTags() {
        let allowlist = MetadataPlan().allowlist(for: .jpeg, signed: false)
        let inventory = JPEGReader.read([UInt8](CleanFiles.jpeg(for: allowlist)))
        #expect(inventory.problems.isEmpty)
        #expect(
            inventory.blocks == [
                "jpeg:APP0:JFIF", "jpeg:APP1:Exif", "jpeg:APP2:ICC", "jpeg:APP13:empty-IPTC", "jpeg:DQT", "jpeg:SOF",
                "jpeg:DHT", "jpeg:DRI", "jpeg:SOS", "jpeg:EOI",
            ])
        #expect(Set(inventory.tags.map { MetadataAllowlist.TagID($0.directory, $0.tag) }) == allowlist.tags)
        #expect(JPEGReader.emptyIPTCSegment == JPEGTestData.emptyIPTC)
    }

    @Test func namesEveryKindOfSegment() {
        #expect(JPEGReader.blockName(marker: 0xE1, payload: Array("http://ns.adobe.com/xap/1.0/\0".utf8)) == "jpeg:APP1:XMP")
        #expect(JPEGReader.blockName(marker: 0xE1, payload: [1]) == "jpeg:APP1")
        #expect(JPEGReader.blockName(marker: 0xED, payload: [1]) == "jpeg:APP13")
        #expect(JPEGReader.blockName(marker: 0xE2, payload: Array("MPF\0".utf8)) == "jpeg:APP2")
        #expect(JPEGReader.blockName(marker: 0xE0, payload: [1]) == "jpeg:APP0")
        #expect(JPEGReader.blockName(marker: 0xEB, payload: []) == "jpeg:APP11")
        #expect(JPEGReader.blockName(marker: 0xFE, payload: []) == "jpeg:COM")
        #expect(JPEGReader.blockName(marker: 0xCC, payload: []) == "jpeg:DAC")
        #expect(JPEGReader.blockName(marker: 0xC2, payload: []) == "jpeg:SOF")
        #expect(JPEGReader.blockName(marker: 0xF0, payload: []) == "jpeg:marker-F0")
    }

    @Test func fillBytesAndTrailingDataAreHandled() {
        var bytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xFF, 0xFE, 0, 3, 0x41, 0xFF, 0xD9, 0x00]
        #expect(JPEGReader.read(bytes).blocks == ["jpeg:COM", "jpeg:EOI", "jpeg:trailing-data"])
        bytes.removeLast()
        #expect(JPEGReader.read(bytes).blocks == ["jpeg:COM", "jpeg:EOI"])
    }

    @Test func malformedFilesAreProblems() {
        #expect(JPEGReader.read([0xFF, 0xD8]).problems == ["JPEG: no start-of-image marker"])
        #expect(JPEGReader.read([0xFF, 0xD8, 0x00, 0x00]).problems == ["JPEG: expected a marker"])
        #expect(JPEGReader.read([0xFF, 0xD8, 0xFF, 0xE0, 0x00]).problems == ["JPEG: a segment is cut off"])
        #expect(JPEGReader.read([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x09]).problems == ["JPEG: a segment is cut off"])
        #expect(JPEGReader.read([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x01]).problems == ["JPEG: a segment is cut off"])
        #expect(JPEGReader.read([0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0x11]).problems == ["JPEG: no end-of-image marker"])
        let comment: [UInt8] = [0xFF, 0xFE, 0x00, 0x02]
        let many: [UInt8] = [0xFF, 0xD8] + Array(Array(repeating: comment, count: JPEGReader.maximumSegments + 1).joined())
        #expect(JPEGReader.read(many).problems == ["JPEG: too many segments"])
    }
}

struct HEIFReaderTests {
    static let exifTIFF = TIFFBuilder.build(TIFFBuilder.Directory([(0x0112, .short([1]))]))

    @Test(arguments: [false, true])
    func listsBoxesItemsPropertiesReferencesAndTheEXIFTags(dataInMediaBox: Bool) {
        let file = HEIFBuilder.build(
            items: [
                .init(id: 1, type: "hvc1"),
                .init(id: 2, type: "Exif", data: HEIFBuilder.exifItem(Self.exifTIFF)),
                .init(id: 3, type: "mime", contentType: "application/rdf+xml", data: HEIFBuilder.xmp([
                    ("photoshop", MetadataPlan.photoshopNamespace, "DateCreated", "2026-11-12T00:11:51")
                ])),
            ], dataInMediaBox: dataInMediaBox)
        let inventory = HEIFReader.read([UInt8](file))
        #expect(inventory.problems.isEmpty)
        let topLevel = dataInMediaBox ? ["heif:box:ftyp", "heif:box:mdat", "heif:box:meta"] : ["heif:box:ftyp", "heif:box:meta", "heif:box:mdat"]
        let meta = [
            "heif:meta:hdlr", "heif:meta:pitm", "heif:meta:iinf", "heif:meta:iloc", "heif:meta:iprp",
            "heif:property:ispe", "heif:property:colr", "heif:property:hvcC", "heif:meta:iref", "heif:reference:cdsc",
        ] + (dataInMediaBox ? [] : ["heif:meta:idat"])
        let items = ["heif:item:hvc1", "heif:item:Exif", "heif:item:mime:application/rdf+xml"]
        #expect(Set(inventory.blocks) == Set(topLevel + meta + items))
        #expect(inventory.tags == [MetadataInventory.Tag(directory: .primary, tag: 0x0112)])
        #expect(
            inventory.xmpProperties == [
                MetadataInventory.XMPProperty(
                    namespace: MetadataPlan.photoshopNamespace, name: "DateCreated", value: "2026-11-12T00:11:51")
            ])
    }

    @Test func otherMIMEItemsAreListedButNotParsed() {
        let file = HEIFBuilder.build(items: [.init(id: 1, type: "mime", contentType: "text/plain", data: [1])])
        #expect(HEIFReader.read([UInt8](file)).blocks.contains("heif:item:mime:text/plain"))
    }

    @Test func malformedFilesAreProblems() {
        #expect(HEIFReader.read([]).problems == ["HEIF: no ftyp box first"])
        #expect(HEIFReader.read(HEIFBuilder.box("free", [])).problems == ["HEIF: no ftyp box first"])
        #expect(HEIFReader.read([0, 0, 0, 9, 0x66]).problems.first == "HEIF: a box header is cut off")
        let tooBig = HEIFBuilder.box("ftyp", []) + [0, 0, 0, 99] + Array("mdat".utf8)
        #expect(HEIFReader.read(tooBig).problems == ["HEIF: a box doesn't fit"])
        let cutLarge = HEIFBuilder.box("ftyp", []) + [0, 0, 0, 1] + Array("mdat".utf8) + [0, 0]
        #expect(HEIFReader.read(cutLarge).problems == ["HEIF: a box header is cut off"])
        let large = HEIFBuilder.box("ftyp", []) + [0, 0, 0, 1] + Array("mdat".utf8) + [0, 0, 0, 0, 0, 0, 0, 16]
        #expect(HEIFReader.read(large).blocks == ["heif:box:ftyp", "heif:box:mdat"])
        let toEnd = HEIFBuilder.box("ftyp", []) + [0, 0, 0, 0] + Array("mdat".utf8) + [1, 2]
        #expect(HEIFReader.read(toEnd).blocks == ["heif:box:ftyp", "heif:box:mdat"])
    }

    /// A `meta` box with these children.
    static func file(meta: [UInt8]) -> [UInt8] {
        HEIFBuilder.box("ftyp", []) + HEIFBuilder.fullBox("meta", version: 0, meta)
    }

    @Test func malformedItemInformationIsAProblem() {
        let empty = Self.file(meta: HEIFBuilder.box("iinf", []))
        #expect(HEIFReader.read(empty).problems == ["HEIF: unreadable iinf"])
        let notEntry = Self.file(meta: HEIFBuilder.fullBox("iinf", version: 1, [0, 0, 0, 1] + HEIFBuilder.box("free", [])))
        #expect(HEIFReader.read(notEntry).problems == ["HEIF: an item entry HEIF doesn't define"])
        let oldEntry = Self.file(meta: HEIFBuilder.fullBox("iinf", version: 0, [0, 1] + HEIFBuilder.fullBox("infe", version: 1, [])))
        #expect(HEIFReader.read(oldEntry).problems == ["HEIF: an item entry HEIF doesn't define"])
        let shortEntry = Self.file(meta: HEIFBuilder.fullBox("iinf", version: 0, [0, 1] + HEIFBuilder.fullBox("infe", version: 3, [0, 0])))
        #expect(HEIFReader.read(shortEntry).problems == ["HEIF: unreadable item entry"])
        let version3 = Self.file(
            meta: HEIFBuilder.fullBox("iinf", version: 0, [0, 1] + HEIFBuilder.fullBox("infe", version: 3, [0, 0, 0, 7, 0, 0] + Array("mime".utf8))))
        #expect(HEIFReader.read(version3).blocks.contains("heif:item:mime:"))
    }

    @Test func malformedItemLocationsAreProblems() {
        for iloc in [
            HEIFBuilder.box("iloc", []),
            HEIFBuilder.fullBox("iloc", version: 0, [0x44, 0x00]),
            HEIFBuilder.fullBox("iloc", version: 0, [0x44, 0x00, 0, 1]),
            HEIFBuilder.fullBox("iloc", version: 1, [0x44, 0x00, 0, 1, 0, 1]),
            HEIFBuilder.fullBox("iloc", version: 2, [0x44, 0x00, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0]),
            HEIFBuilder.fullBox("iloc", version: 0, [0x44, 0x00, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0]),
            HEIFBuilder.fullBox("iloc", version: 0, [0xF4, 0x00, 0, 1, 0, 1, 0, 0, 0, 1]),
        ] {
            #expect(HEIFReader.read(Self.file(meta: iloc)).problems == ["HEIF: unreadable iloc"])
        }
    }

    @Test func metadataItemsWithBadDataAreProblems() {
        let entry = HEIFBuilder.fullBox("iinf", version: 0, [0, 1] + HEIFBuilder.itemEntry(.init(id: 1, type: "Exif")))
        // No location at all.
        #expect(HEIFReader.read(Self.file(meta: entry)).problems == ["HEIF: the Exif item's data is out of bounds"])
        // Construction method 1 without idat, method 2, and an extent past the end.
        for (method, offset, length) in [(1, 0, 4), (2, 0, 4), (0, 0, 9999)] {
            let iloc = HEIFBuilder.fullBox(
                "iloc", version: 1,
                [0x44, 0x00, 0, 1, 0, 1, 0, UInt8(method), 0, 0, 0, 1] + HEIFBuilder.be32(UInt32(offset)) + HEIFBuilder.be32(UInt32(length)))
            #expect(HEIFReader.read(Self.file(meta: entry + iloc)).problems == ["HEIF: the Exif item's data is out of bounds"])
        }
        // An Exif item whose TIFF header offset points past its end.
        let bad = HEIFBuilder.build(items: [.init(id: 1, type: "Exif", data: [0, 0, 0, 9])])
        #expect(HEIFReader.read([UInt8](bad)).problems == ["HEIF: unreadable Exif item"])
    }

    @Test func boxCountIsCapped() {
        let many = HEIFBuilder.box("ftyp", []) + Array(repeating: HEIFBuilder.box("free", []), count: HEIFReader.maximumBoxes).flatMap { $0 }
        #expect(HEIFReader.read(many).problems == ["HEIF: too many boxes"])
    }

    @Test func integersAreBoundedAndCapped() {
        #expect(HEIFReader.integer(in: [1, 2], at: 0, size: 2) == 258)
        #expect(HEIFReader.integer(in: [1, 2], at: 0, size: 0) == 0)
        #expect(HEIFReader.integer(in: [1, 2], at: 1, size: 2) == nil)
        #expect(HEIFReader.integer(in: Array(repeating: 0, count: 9), at: 0, size: 9) == nil)
        #expect(HEIFReader.integer(in: Array(repeating: 0xFF, count: 8), at: 0, size: 8) == nil)
    }
}

struct XMPReaderTests {
    @Test func readsTopLevelElementsAndAttributes() {
        let packet = HEIFBuilder.xmp(
            [
                ("xmp", MetadataPlan.xmpNamespace, "CreatorTool", " nope. "),
                ("dc", "http://purl.org/dc/elements/1.1/", "creator", "<rdf:Seq><rdf:li>A</rdf:li></rdf:Seq>"),
            ], attributes: "xmlns:tiff=\"http://ns.adobe.com/tiff/1.0/\" tiff:Make=\"Apple\"")
        let inventory = XMPReader.read(packet)
        #expect(inventory.problems.isEmpty)
        #expect(
            inventory.xmpProperties == [
                MetadataInventory.XMPProperty(namespace: "", name: "tiff:Make", value: "Apple"),
                MetadataInventory.XMPProperty(namespace: MetadataPlan.xmpNamespace, name: "CreatorTool", value: "nope."),
                MetadataInventory.XMPProperty(namespace: "http://purl.org/dc/elements/1.1/", name: "creator", value: "A"),
            ])
    }

    @Test func elementsWithoutANamespaceAreRecorded() {
        let packet = Array(
            "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description><Plain>1</Plain></rdf:Description></rdf:RDF>".utf8)
        #expect(XMPReader.read(packet).xmpProperties.map(\.name) == ["Plain"])
    }

    @Test func malformedPacketsAreProblems() {
        #expect(XMPReader.read(Array("<x:xmpmeta".utf8)).problems == ["XMP: the packet isn't well-formed XML"])
    }
}

struct MetadataFileReaderTests {
    @Test func dispatchesOnFormat() {
        let allowlist = MetadataPlan().allowlist(for: .raw, signed: false)
        let dng = MetadataFileReader.read(CleanFiles.dng(for: allowlist), format: .raw)
        #expect(dng.rawImageData == Data(CleanFiles.rawImageData))
        #expect(MetadataFileReader.rawImageData(ofDNG: CleanFiles.dng(for: allowlist)) == Data(CleanFiles.rawImageData))
        let jpeg = MetadataFileReader.read(CleanFiles.jpeg(for: MetadataPlan().allowlist(for: .jpeg, signed: false)), format: .jpeg)
        #expect(jpeg.rawImageData == nil && jpeg.inventory.blocks.contains("jpeg:EOI"))
        let heif = MetadataFileReader.read(HEIFBuilder.build(items: [.init(id: 1, type: "hvc1")]), format: .heif)
        #expect(heif.rawImageData == nil && heif.inventory.blocks.contains("heif:item:hvc1"))
    }
}
