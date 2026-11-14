import Foundation
import NopeCore
import Testing

/// The metadata comparison of the comparison shot (issue #55), from fixture inventories.
struct MetadataComparisonTests {
    typealias Tag = MetadataInventory.Tag

    /// What a phone's own HEIF carries by default, in the shape the tag reader reports it.
    static let phone = MetadataInventory(
        tags: [
            Tag(directory: .primary, tag: 0x010F, text: "Maker"),
            Tag(directory: .primary, tag: 0x0131, text: "26.1"),
            Tag(directory: .primary, tag: 0x0112, values: [6]),
            Tag(directory: .exif, tag: 0x829A, values: [0.01]),
            Tag(directory: .exif, tag: 0x9010, text: "+01:00"),
            Tag(directory: .exif, tag: 0x927C),
            Tag(directory: .exif, tag: 0xA420, text: "ABC123"),
            Tag(directory: .exif, tag: 0xA460, values: [2]),
            Tag(directory: .gps, tag: 0x0002, values: [52, 22, 0]),
            Tag(directory: .exif, tag: 0xC7FF, values: [1]),
            // A repeated tag is listed once, with its first value.
            Tag(directory: .exif, tag: 0x829A, values: [0.5]),
        ],
        blocks: ["heif:item:hvc1", "heif:item:hvc1", "heif:item:Exif"],
        xmpProperties: [
            MetadataInventory.XMPProperty(namespace: "http://ns.adobe.com/xap/1.0/mm/", name: "DocumentID", value: "uuid:1"),
            MetadataInventory.XMPProperty(namespace: "http://ns.adobe.com/xap/1.0/", name: "Structure", value: ""),
            // A repeated property is listed once.
            MetadataInventory.XMPProperty(namespace: "http://ns.adobe.com/xap/1.0/", name: "Structure", value: "again"),
        ])

    /// What nope.'s saved, signed HEIF carries.
    static let nope = MetadataInventory(
        tags: [
            Tag(directory: .primary, tag: 0x0112, values: [6]),
            Tag(directory: .primary, tag: 0x0131, text: "Photivra Nope Camera 0.2.0"),
            Tag(directory: .exif, tag: 0x829A, values: [0.02]),
        ],
        blocks: ["heif:item:hvc1", "heif:item:Exif", "heif:box:uuid"])

    static let comparison = MetadataComparison(phone: phone, nope: nope)

    static func entry(_ name: String) -> MetadataComparison.Entry? {
        comparison.entries.first { $0.name == name }
    }

    @Test func groupsEachItemByHowItDiffers() {
        let groups = Dictionary(grouping: Self.comparison.entries, by: \.difference).mapValues { $0.map(\.name) }
        #expect(
            groups[.onlyInPhoneVersion] == [
                "Make", "OffsetTime", "MakerNote", "ImageUniqueID", "CompositeImage", "GPSLatitude", "exif 0xC7FF",
                "DocumentID", "Structure",
            ])
        #expect(groups[.different] == ["Software", "ExposureTime", "heif:item:hvc1"])
        #expect(groups[.same] == ["Orientation", "heif:item:Exif"])
        #expect(groups[.onlyInNopeFile] == ["heif:box:uuid"])
        #expect(Self.comparison.entries(.same).map(\.name) == ["Orientation", "heif:item:Exif"])
    }

    @Test func keepsEachFilesValue() {
        let exposure = Self.entry("ExposureTime")
        #expect(exposure?.phoneValue == .numbers([0.01]))
        #expect(exposure?.nopeValue == .numbers([0.02]))
        #expect(exposure?.kind == .tag(.exif))
        #expect(exposure?.id == "tag:exif:33434")
        #expect(Self.entry("Make")?.phoneValue == .text("Maker"))
        #expect(Self.entry("Make")?.nopeValue == nil)
        #expect(Self.entry("MakerNote")?.phoneValue == .present)
        #expect(Self.entry("heif:item:hvc1")?.phoneValue == .count(2))
        #expect(Self.entry("heif:item:hvc1")?.nopeValue == .count(1))
        #expect(Self.entry("heif:item:hvc1")?.kind == .block)
        #expect(Self.entry("DocumentID")?.phoneValue == .text("uuid:1"))
        #expect(Self.entry("DocumentID")?.kind == .xmp(namespace: "http://ns.adobe.com/xap/1.0/mm/"))
        #expect(Self.entry("Structure")?.phoneValue == .present)
        #expect(Self.entry("heif:box:uuid")?.phoneValue == nil)
    }

    @Test func linksEachItemToItsPrivacySwitch() {
        #expect(Self.entry("Make")?.item == .cameraMakeAndModel)
        #expect(Self.entry("OffsetTime")?.item == .timeZone)
        #expect(Self.entry("MakerNote")?.item == .makerNotes)
        #expect(Self.entry("GPSLatitude")?.item == .location)
        #expect(Self.entry("ExposureTime")?.item == .exposureSettings)
        // The phone's software is the system version; nope.'s is the app's name.
        #expect(Self.entry("Software")?.item == .systemVersion)
        #expect(Self.entry("ImageUniqueID")?.item == nil)
        #expect(Self.entry("Orientation")?.item == nil)
        #expect(Self.entry("heif:item:Exif")?.item == nil)
    }

    @Test func marksIdentifyingValues() {
        let identifying = Self.comparison.entries.filter(\.isIdentifying).map(\.name)
        #expect(identifying == ["MakerNote", "ImageUniqueID", "GPSLatitude", "DocumentID"])
    }

    @Test func marksNopesSignature() {
        #expect(Self.comparison.entries.filter(\.isSignature).map(\.name) == ["heif:box:uuid"])
        let signedDNG = MetadataComparison(
            phone: MetadataInventory(), nope: MetadataInventory(tags: [Tag(directory: .primary, tag: 0xCD41)], blocks: ["jpeg:APP11"]))
        #expect(signedDNG.entries.map(\.isSignature) == [true, true])
        #expect(signedDNG.entries.map(\.difference) == [.onlyInNopeFile, .onlyInNopeFile])
        #expect(signedDNG.entries.first?.name == "C2PA manifest")
    }

    @Test func namesTagsFromTheCatalogTheEXIFTablesOrTheirNumber() {
        for (directory, tag, name) in [
            (TIFFDirectory.exif, UInt16(0xA431), "BodySerialNumber"), (.exif, 0xA435, "LensSerialNumber"),
            (.exif, 0xA430, "CameraOwnerName"), (.gps, 0x0011, "GPSImgDirection"), (.exif, 0x9010, "OffsetTime"),
            (.primary, 0xC7FF, "primary 0xC7FF"),
        ] {
            let entry = MetadataComparison(phone: MetadataInventory(tags: [Tag(directory: directory, tag: tag, text: "x")]), nope: MetadataInventory())
                .entries.first
            #expect(entry?.name == name)
        }
        let serial = MetadataComparison(
            phone: MetadataInventory(tags: [Tag(directory: .exif, tag: 0xA431, text: "SN")]), nope: MetadataInventory())
        #expect(serial.entries.first?.isIdentifying == true)
    }

    @Test func anIdentifyingValueOnlyNopesFileHoldsIsMaskedToo() {
        let comparison = MetadataComparison(
            phone: MetadataInventory(), nope: MetadataInventory(tags: [Tag(directory: .gps, tag: 0x0002, values: [1])]))
        #expect(comparison.entries.first?.isIdentifying == true)
        #expect(comparison.entries.first?.item == .location)
    }

    @Test func comparesEmptyFiles() {
        #expect(MetadataComparison(phone: MetadataInventory(), nope: MetadataInventory()).entries.isEmpty)
    }

    @Test func entriesCanBeMadeDirectly() {
        let entry = MetadataComparison.Entry(
            id: "x", name: "X", kind: .block, phoneValue: nil, nopeValue: nil, item: nil, isIdentifying: false,
            isSignature: false)
        #expect(entry.difference == .onlyInNopeFile)
    }
}
