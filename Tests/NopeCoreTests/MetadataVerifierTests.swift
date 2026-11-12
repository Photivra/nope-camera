import Foundation
import Testing

@testable import NopeCore

/// Reads a file with the project reader and no ImageIO keys, and verifies it.
func violations(
    _ data: Data, _ format: PhotoFormat, _ allowlist: MetadataAllowlist, imageIOKeys: [ImageIOKey] = [],
    expectedRaw: Data? = Data(CleanFiles.rawImageData)
) -> [MetadataViolation] {
    let readBack = MetadataReadBack(file: MetadataFileReader.read(data, format: format), imageIOKeys: imageIOKeys)
    return MetadataVerifier.violations(in: readBack, allowlist: allowlist, expectedRawImageData: expectedRaw)
}

struct MetadataVerifierTests {
    static let plan = MetadataPlan()

    @Test func cleanFilesPass() {
        for format in PhotoFormat.allCases {
            let allowlist = Self.plan.allowlist(for: format, signed: false)
            let data: Data
            switch format {
            case .raw: data = CleanFiles.dng(for: allowlist)
            case .jpeg: data = CleanFiles.jpeg(for: allowlist)
            case .heif:
                data = HEIFBuilder.build(items: [
                    .init(id: 1, type: "hvc1"),
                    .init(id: 2, type: "Exif", data: HEIFBuilder.exifItem(TIFFBuilder.build(CleanFiles.tiff(for: allowlist)))),
                ])
            }
            #expect(violations(data, format, allowlist, imageIOKeys: [ImageIOKey(nil, "PixelWidth")]).isEmpty, "\(format)")
        }
    }

    @Test func unexpectedTagIsRejected() {
        let allowlist = Self.plan.allowlist(for: .raw, signed: false)
        let data = CleanFiles.dng(for: allowlist, extra: [(.exif, 0x927C)])
        #expect(violations(data, .raw, allowlist) == [.unexpectedTag(MetadataAllowlist.TagID(.exif, 0x927C))])
    }

    @Test func exactCameraModelWhenGenericWasAskedForIsRejected() {
        let allowlist = Self.plan.allowlist(for: .raw, signed: false)
        let root = CleanFiles.tiff(for: allowlist)
        root.entries.removeAll { $0.0 == 0xC614 }
        root.entries.append((0xC614, .ascii("iPhone17,2 back camera")))
        #expect(
            violations(Data(TIFFBuilder.build(root)), .raw, allowlist)
                == [.unexpectedValue(MetadataAllowlist.TagID(.primary, 0xC614))])
    }

    @Test func missingRequiredDNGTagIsRejected() {
        let allowlist = Self.plan.allowlist(for: .raw, signed: false)
        let root = CleanFiles.tiff(for: allowlist)
        root.entries.removeAll { $0.0 == 0xC621 || $0.0 == 0xC612 }
        #expect(
            violations(Data(TIFFBuilder.build(root)), .raw, allowlist)
                == [.missingTag(MetadataAllowlist.TagID(.primary, 0xC612)), .missingTag(MetadataAllowlist.TagID(.primary, 0xC621))])
    }

    @Test func changedOrMissingRAWDataIsRejected() {
        let allowlist = Self.plan.allowlist(for: .raw, signed: false)
        let data = CleanFiles.dng(for: allowlist)
        #expect(violations(data, .raw, allowlist, expectedRaw: Data([9])) == [.rawImageDataChanged])
        #expect(violations(data, .raw, allowlist, expectedRaw: nil) == [.rawImageDataMissing])
        let noRaw = Data(TIFFBuilder.build(CleanFiles.tiff(for: allowlist, includeRawData: false)))
        #expect(violations(noRaw, .raw, allowlist) == [.rawImageDataMissing])
    }

    @Test func unreadableFilesAreRejected() {
        let allowlist = Self.plan.allowlist(for: .jpeg, signed: false)
        #expect(violations(Data([1, 2, 3]), .jpeg, allowlist) == [.unreadable("JPEG: no start-of-image marker")])
    }

    @Test func unexpectedBlocksAndImageIOKeysAreRejected() {
        let allowlist = Self.plan.allowlist(for: .jpeg, signed: false)
        let xmp = Array("http://ns.adobe.com/xap/1.0/\0<x/>".utf8)
        let data = CleanFiles.jpeg(for: allowlist, extraSegments: [(0xE1, xmp), (0xFE, [0x41])])
        #expect(
            violations(data, .jpeg, allowlist, imageIOKeys: [ImageIOKey("{IPTC}", "DateCreated")]) == [
                .unexpectedBlock("jpeg:APP1:XMP"), .unexpectedBlock("jpeg:COM"),
                .unexpectedImageIOKey(ImageIOKey("{IPTC}", "DateCreated")),
            ])
    }

    @Test func xmpPropertiesAndTheirValuesAreChecked() {
        var settings = MetadataSettings()
        settings.set(.dateAndTime, isOn: true)
        settings.set(.appNameAndVersion, isOn: true)
        let allowlist = MetadataPlan(settings: settings, appVersion: "1.0.0").allowlist(for: .heif, signed: false)
        let photoshop = MetadataPlan.photoshopNamespace, xmp = MetadataPlan.xmpNamespace
        let packet = HEIFBuilder.xmp([
            ("photoshop", photoshop, "DateCreated", "2026-11-12T00:11:51"),
            ("xmp", xmp, "CreateDate", "2026-11-12T00:11:51.473"),
            ("xmp", xmp, "ModifyDate", "2026-11-12T00:11:51-05:00"),
            ("xmp", xmp, "CreatorTool", "Photivra Nope Camera 1.0.0"),
            ("xmp", xmp, "Rating", "5"),
        ])
        let file = HEIFBuilder.build(items: [.init(id: 1, type: "mime", contentType: "application/rdf+xml", data: packet)])
        #expect(
            violations(file, .heif, allowlist) == [
                .unexpectedXMPValue(MetadataAllowlist.XMPName(xmp, "CreateDate")),
                .unexpectedXMPValue(MetadataAllowlist.XMPName(xmp, "ModifyDate")),
                .unexpectedXMPProperty(MetadataAllowlist.XMPName(xmp, "Rating")),
            ])
    }

    @Test func mirroredNameAndCopyrightMustMatchTheSettings() {
        var settings = MetadataSettings()
        settings.set(.nameAndCopyright, isOn: true)
        settings.ownerName = "A. Person"
        settings.copyrightNotice = "A. Person"
        let allowlist = MetadataPlan(settings: settings).allowlist(for: .heif, signed: false)
        let dc = MetadataPlan.dublinCoreNamespace
        let packet = HEIFBuilder.xmp([("dc", dc, "creator", "A. Person"), ("dc", dc, "rights", "Someone else")])
        let file = HEIFBuilder.build(items: [.init(id: 1, type: "mime", contentType: "application/rdf+xml", data: packet)])
        #expect(violations(file, .heif, allowlist) == [.unexpectedXMPValue(MetadataAllowlist.XMPName(dc, "rights"))])
        #expect(allowlist.allows(ImageIOKey("{IPTC}", "Byline")))
    }

    @Test(arguments: [
        ("2026-11-12", false, false), ("2026-11-12T00:11:51", false, false), ("2026-11-12T00:11:51.4", true, false),
        ("2026-11-12T00:11Z", false, true), ("2026-11-12T00:11+01:00", false, true),
    ])
    func xmpDatesAreParsed(text: String, fraction: Bool, zone: Bool) {
        let date = XMPDate(text)
        #expect(date.hasFraction == fraction)
        #expect(date.hasZone == zone)
    }

    @Test func textRulesAcceptOnlyTheirValues() {
        #expect(MetadataAllowlist.TextRule.exactly("a").accepts("a"))
        #expect(!MetadataAllowlist.TextRule.exactly("a").accepts(nil))
        #expect(MetadataAllowlist.TextRule.prefix("nope.").accepts("nope. 1 (27)"))
        #expect(!MetadataAllowlist.TextRule.prefix("nope.").accepts(nil))
        #expect(MetadataAllowlist.TextRule.any.accepts(nil))
    }
}

/// Fail-closed property and fuzz tests: whatever is injected into a clean file, including a tag a
/// future iOS might add, the file is rejected; and no input, however damaged, crashes a reader.
struct MetadataFailClosedFuzzTests {
    /// A tag number no specification defines, standing in for a tag a future iOS adds to the DNG.
    static let futureSystemTag: UInt16 = 0xC7FF

    @Test func simulatedFutureSystemTagIsRejectedInEveryFormatAndSetting() {
        var generator = SeededGenerator(seed: 25)
        for _ in 0..<64 {
            let mask = Int.random(in: 0..<(1 << MetadataItem.allCases.count), using: &generator)
            let plan = MetadataPlan(settings: ExpectedTags.settings(mask: mask), appVersion: "0.2.0")
            for directory in [TIFFDirectory.primary, .exif] {
                let raw = plan.allowlist(for: .raw, signed: false)
                let dng = CleanFiles.dng(for: raw, extra: [(directory, Self.futureSystemTag)])
                #expect(violations(dng, .raw, raw) == [.unexpectedTag(MetadataAllowlist.TagID(directory, Self.futureSystemTag))])
                let jpegAllowlist = plan.allowlist(for: .jpeg, signed: false)
                let jpeg = CleanFiles.jpeg(for: jpegAllowlist, extraTags: [(directory, Self.futureSystemTag)])
                #expect(
                    violations(jpeg, .jpeg, jpegAllowlist)
                        == [.unexpectedTag(MetadataAllowlist.TagID(directory, Self.futureSystemTag))])
            }
            let heifAllowlist = plan.allowlist(for: .heif, signed: false)
            let tiff = TIFFBuilder.build(CleanFiles.tiff(for: heifAllowlist, extra: [(.exif, Self.futureSystemTag)]))
            let heif = HEIFBuilder.build(items: [.init(id: 1, type: "Exif", data: HEIFBuilder.exifItem(tiff))])
            #expect(violations(heif, .heif, heifAllowlist) == [.unexpectedTag(MetadataAllowlist.TagID(.exif, Self.futureSystemTag))])
        }
    }

    /// Every tag number that isn't on the allowlist, in every directory, is rejected.
    @Test func everyTagOffTheAllowlistIsRejected() {
        var generator = SeededGenerator(seed: 7)
        let allowlist = MetadataPlan().allowlist(for: .raw, signed: false)
        let pointers: Set<UInt16> = [0x014A, 0x8769, 0x8825, 0xA005]
        for _ in 0..<500 {
            let tag = UInt16.random(in: 0...UInt16.max, using: &generator)
            let directory = [TIFFDirectory.primary, .exif].randomElement(using: &generator)!
            guard !allowlist.allows(MetadataAllowlist.TagID(directory, tag)), !pointers.contains(tag) else { continue }
            let found = violations(CleanFiles.dng(for: allowlist, extra: [(directory, tag)]), .raw, allowlist)
            #expect(found.contains(.unexpectedTag(MetadataAllowlist.TagID(directory, tag))), "\(directory) \(tag)")
        }
    }

    @Test func unexpectedContainerBlocksAreRejected() {
        let jpegAllowlist = MetadataPlan().allowlist(for: .jpeg, signed: false)
        for (marker, payload, name) in [
            (UInt8(0xE2), Array("MPF\0".utf8), "jpeg:APP2"), (0xED, [0x01], "jpeg:APP13"), (0xEB, [0x4A], "jpeg:APP11"),
            (0xE9, [0x00], "jpeg:APP9"),
        ] {
            let file = CleanFiles.jpeg(for: jpegAllowlist, extraSegments: [(marker, payload)])
            #expect(violations(file, .jpeg, jpegAllowlist) == [.unexpectedBlock(name)])
        }
        let heifAllowlist = MetadataPlan().allowlist(for: .heif, signed: false)
        let thumbnail = HEIFBuilder.build(items: [.init(id: 1, type: "hvc1")], references: ["thmb"])
        #expect(violations(thumbnail, .heif, heifAllowlist) == [.unexpectedBlock("heif:reference:thmb")])
        let gainMap = HEIFBuilder.build(items: [.init(id: 1, type: "tmap")], properties: ["ispe"])
        #expect(violations(gainMap, .heif, heifAllowlist) == [.unexpectedBlock("heif:item:tmap")])
        let manifest = HEIFBuilder.build(items: [.init(id: 1, type: "hvc1")], extraTopLevel: [HEIFBuilder.box("uuid", [1])])
        #expect(violations(manifest, .heif, heifAllowlist) == [.unexpectedBlock("heif:box:uuid")])
        #expect(violations(manifest, .heif, MetadataPlan().allowlist(for: .heif, signed: true)).isEmpty)
        let xmp = HEIFBuilder.build(items: [.init(id: 1, type: "mime", contentType: "application/rdf+xml", data: HEIFBuilder.xmp([]))])
        #expect(violations(xmp, .heif, heifAllowlist) == [.unexpectedBlock("heif:item:mime:application/rdf+xml")])
    }

    /// Random byte flips, truncations and insertions never crash a reader, and a damaged file is
    /// only ever accepted if everything the reader found is allowed.
    @Test func mutatedFilesNeverCrashTheReaders() {
        var generator = SeededGenerator(seed: 2026)
        let plan = MetadataPlan(settings: ExpectedTags.settings(mask: 0b1_1111_1111_1111), appVersion: "0.2.0")
        let raw = plan.allowlist(for: .raw, signed: true), jpeg = plan.allowlist(for: .jpeg, signed: true)
        let heif = plan.allowlist(for: .heif, signed: true)
        let tiff = TIFFBuilder.build(CleanFiles.tiff(for: heif))
        let seeds: [(PhotoFormat, MetadataAllowlist, [UInt8])] = [
            (.raw, raw, [UInt8](CleanFiles.dng(for: raw))),
            (.jpeg, jpeg, [UInt8](CleanFiles.jpeg(for: jpeg))),
            (.heif, heif, [UInt8](HEIFBuilder.build(items: [.init(id: 2, type: "Exif", data: HEIFBuilder.exifItem(tiff))]))),
        ]
        for (format, allowlist, seed) in seeds {
            for _ in 0..<1500 {
                var bytes = seed
                for _ in 0..<Int.random(in: 1...8, using: &generator) {
                    let position = Int.random(in: 0..<bytes.count, using: &generator)
                    switch Int.random(in: 0..<4, using: &generator) {
                    case 0: bytes[position] = UInt8.random(in: 0...255, using: &generator)
                    case 1: bytes[position] ^= 1 << UInt8.random(in: 0...7, using: &generator)
                    case 2: bytes.removeSubrange(position...)
                    default: bytes.insert(UInt8.random(in: 0...255, using: &generator), at: position)
                    }
                    if bytes.isEmpty { bytes = [0] }
                }
                let found = violations(Data(bytes), format, allowlist)
                let result = MetadataFileReader.read(Data(bytes), format: format)
                if found.isEmpty {
                    #expect(result.inventory.problems.isEmpty)
                    #expect(result.inventory.tags.allSatisfy { allowlist.allows(MetadataAllowlist.TagID($0.directory, $0.tag)) })
                    #expect(result.inventory.blocks.allSatisfy(allowlist.blocks.contains))
                }
            }
        }
    }

    /// Random bytes of every length are read without crashing.
    @Test func randomBytesNeverCrashTheReaders() {
        var generator = SeededGenerator(seed: 1)
        for _ in 0..<2000 {
            let count = Int.random(in: 0..<256, using: &generator)
            var bytes = (0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) }
            // Give some inputs a valid start, so the readers go deeper.
            switch Int.random(in: 0..<4, using: &generator) {
            case 0 where bytes.count >= 8: bytes.replaceSubrange(0..<4, with: [0x49, 0x49, 42, 0])
            case 1 where bytes.count >= 4: bytes.replaceSubrange(0..<2, with: [0xFF, 0xD8])
            case 2: bytes = HEIFBuilder.box("ftyp", []) + bytes
            default: break
            }
            for format in PhotoFormat.allCases {
                _ = MetadataFileReader.read(Data(bytes), format: format)
            }
        }
    }
}
