import Foundation

/// The metadata of the app's saved file and of the phone's fully processed version, side by side
/// (issue #55, "Compare the metadata").
///
/// Both sides come from the project's own tag reader (``MetadataFileReader``): the app's from the
/// read-back of the saved file, the phone's from the in-memory file iOS wrote. Each tag, block
/// and XMP property becomes one ``Entry``, grouped by ``Difference``.
///
/// Privacy: built and shown in memory only; nothing is stored, logged or copied. Values that
/// can identify the device or link photos are marked ``Entry/isIdentifying`` so an interface
/// masks them until the person asks to see them.
public struct MetadataComparison: Equatable, Sendable {
    /// A tag's place: its directory and number.
    typealias TagID = MetadataAllowlist.TagID

    /// How an item differs between the two files.
    public enum Difference: Equatable, Sendable, CaseIterable {
        /// Only the phone's version has it.
        case onlyInPhoneVersion
        /// Both have it, with different values.
        case different
        /// Only the app's file has it, such as its signature.
        case onlyInNopeFile
        /// Both have it, with the same value.
        case same
    }

    /// What an item holds.
    public enum Value: Equatable, Sendable {
        /// Text: an ASCII tag or an XMP property.
        case text(String)
        /// Numbers: a numeric tag's values, rationals divided out.
        case numbers([Double])
        /// A container block, found this many times.
        case count(Int)
        /// Present, with no value the reader records (such as a maker note's bytes).
        case present
    }

    /// Where an item lives in the file.
    public enum Kind: Equatable, Sendable {
        /// A TIFF tag in this directory (EXIF, GPS, IFD0).
        case tag(TIFFDirectory)
        /// A container block: a HEIF box, item or property, or a JPEG segment.
        case block
        /// A top-level XMP property, in this namespace.
        case xmp(namespace: String)
    }

    /// One tag, block or property, with each file's value.
    public struct Entry: Equatable, Sendable, Identifiable {
        /// A stable identifier: the item's place and number or name.
        public let id: String
        /// The item's specification name, such as `ImageUniqueID`, `heif:item:hvc1` or
        /// `DocumentID`. A tag without a known name is shown by its directory and number.
        public let name: String
        /// Where it lives.
        public let kind: Kind
        /// The phone's value, or `nil` when the phone's version doesn't have it.
        public let phoneValue: Value?
        /// The app's value, or `nil` when the app's file doesn't have it.
        public let nopeValue: Value?
        /// How the two differ.
        public let difference: Difference
        /// The privacy switch that controls the item in the app (`docs/PRIVACY.md`), or `nil` when
        /// no switch does: the app then never writes it unless it is locked.
        public let item: MetadataItem?
        /// Whether the value can identify the device or link photos (maker notes, location,
        /// unique IDs and serial numbers). Show it masked until the person asks.
        public let isIdentifying: Bool
        /// Whether the item is the app's Content Credentials signature.
        public let isSignature: Bool

        /// Creates an entry.
        ///
        /// - Parameters:
        ///   - id: A stable identifier.
        ///   - name: The item's name.
        ///   - kind: Where it lives.
        ///   - phoneValue: The phone's value, or `nil`.
        ///   - nopeValue: the app's value, or `nil`.
        ///   - item: The privacy switch, or `nil`.
        ///   - isIdentifying: Whether to mask the value.
        ///   - isSignature: Whether it is the app's signature.
        public init(
            id: String, name: String, kind: Kind, phoneValue: Value?, nopeValue: Value?, item: MetadataItem?,
            isIdentifying: Bool, isSignature: Bool
        ) {
            self.id = id
            self.name = name
            self.kind = kind
            self.phoneValue = phoneValue
            self.nopeValue = nopeValue
            self.difference =
                switch (phoneValue, nopeValue) {
                case (.some(let phone), .some(let nope)): phone == nope ? .same : .different
                case (.some, .none): .onlyInPhoneVersion
                default: .onlyInNopeFile
                }
            self.item = item
            self.isIdentifying = isIdentifying
            self.isSignature = isSignature
        }
    }

    /// Every entry: the phone's items in file order, then those only the app's file has.
    public let entries: [Entry]

    /// Compares two files' metadata.
    ///
    /// - Parameters:
    ///   - phone: What the tag reader found in the phone's version.
    ///   - nope: What the read-back found in the app's saved file.
    public init(phone: MetadataInventory, nope: MetadataInventory) {
        let phoneItems = Self.items(in: phone)
        let nopeItems = Self.items(in: nope)
        var nopeByID: [String: Item] = [:]
        for item in nopeItems { nopeByID[item.id] = item }
        let phoneIDs = Set(phoneItems.map(\.id))
        entries =
            phoneItems.map { Self.entry($0, phone: $0, nope: nopeByID[$0.id]) }
            + nopeItems.filter { !phoneIDs.contains($0.id) }.map { Self.entry($0, phone: nil, nope: $0) }
    }

    /// The entries with one difference, in order.
    ///
    /// - Parameter difference: The difference.
    /// - Returns: The entries.
    public func entries(_ difference: Difference) -> [Entry] {
        entries.filter { $0.difference == difference }
    }

    /// One item as one file holds it, before the two files are paired.
    struct Item: Equatable {
        /// The identifier both files share.
        let id: String
        /// The item's name.
        let name: String
        /// Where it lives.
        let kind: Kind
        /// Its value.
        let value: Value
        /// The privacy switch, or `nil`.
        let item: MetadataItem?
        /// Whether the value is identifying.
        let isIdentifying: Bool
        /// Whether it is a signature.
        let isSignature: Bool

        /// Creates an item.
        ///
        /// - Parameters:
        ///   - id: The identifier both files share.
        ///   - name: The item's name.
        ///   - kind: Where it lives.
        ///   - value: Its value.
        ///   - item: The privacy switch, or `nil`.
        ///   - isIdentifying: Whether the value is identifying.
        ///   - isSignature: Whether it is a signature.
        init(
            id: String, name: String, kind: Kind, value: Value, item: MetadataItem?, isIdentifying: Bool,
            isSignature: Bool
        ) {
            self.id = id
            self.name = name
            self.kind = kind
            self.value = value
            self.item = item
            self.isIdentifying = isIdentifying
            self.isSignature = isSignature
        }
    }

    /// Pairs one item's two sides.
    ///
    /// - Parameters:
    ///   - side: The side the item is listed from: the phone's, or the app's when only the app's
    ///     file has it. Its name, place and privacy switch are shown.
    ///   - phone: The phone's side, or `nil`.
    ///   - nope: the app's side, or `nil`.
    /// - Returns: The entry.
    static func entry(_ side: Item, phone: Item?, nope: Item?) -> Entry {
        Entry(
            id: side.id, name: side.name, kind: side.kind, phoneValue: phone?.value, nopeValue: nope?.value,
            item: side.item ?? nope?.item, isIdentifying: side.isIdentifying || nope?.isIdentifying == true,
            isSignature: nope?.isSignature == true)
    }

    /// Every item of a file, once each: its tags (the first of a repeated tag), its container
    /// blocks with how often each appears, and its XMP properties.
    ///
    /// - Parameter inventory: The file's metadata.
    /// - Returns: The items, in file order.
    static func items(in inventory: MetadataInventory) -> [Item] {
        var seen: Set<String> = []
        var items: [Item] = []
        for tag in inventory.tags {
            let item = tagItem(tag)
            if seen.insert(item.id).inserted { items.append(item) }
        }
        for block in inventory.blocks where seen.insert("block:\(block)").inserted {
            items.append(
                Item(
                    id: "block:\(block)", name: block, kind: .block, value: .count(inventory.blocks.lazy.filter { $0 == block }.count), item: nil,
                    isIdentifying: false, isSignature: signatureBlocks.contains(block)))
        }
        for property in inventory.xmpProperties {
            let id = "xmp:\(property.namespace)\(property.name)"
            guard seen.insert(id).inserted else { continue }
            items.append(
                Item(
                    id: id, name: property.name, kind: .xmp(namespace: property.namespace),
                    value: property.value.isEmpty ? .present : .text(property.value), item: nil,
                    isIdentifying: property.name.hasSuffix("ID"), isSignature: false))
        }
        return items
    }

    /// One tag as an item.
    ///
    /// - Parameter tag: The tag.
    /// - Returns: The item.
    static func tagItem(_ tag: MetadataInventory.Tag) -> Item {
        let value: Value = tag.text.map(Value.text) ?? (tag.values.isEmpty ? .present : .numbers(tag.values))
        let item = MetadataItem.allCases.first { PhotoDetails.holds($0, tag) }
        let key = TagID(tag.directory, tag.tag)
        return Item(
            id: "tag:\(tag.directory.rawValue):\(tag.tag)", name: name(of: tag), kind: .tag(tag.directory), value: value,
            item: item, isIdentifying: item == .location || item == .makerNotes || identifyingTags.contains(key),
            isSignature: key == MetadataPlan.contentCredentialsTag)
    }

    /// A tag's name: from the allowlist's catalog, from ``otherTagNames``, or its directory and
    /// number (``PhotoDetails/name(of:)``).
    ///
    /// - Parameter tag: The tag.
    /// - Returns: The name.
    static func name(of tag: MetadataInventory.Tag) -> String {
        otherTagNames[TagID(tag.directory, tag.tag)] ?? PhotoDetails.name(of: tag)
    }

    /// The container blocks that hold the app's Content Credentials manifest.
    static let signatureBlocks: Set<String> = [
        MetadataPlan.contentCredentialsHEIFBlock, MetadataPlan.contentCredentialsJPEGBlock,
    ]

    /// Tags whose values identify the device or one photo: `ImageUniqueID`, `CameraOwnerName`,
    /// `BodySerialNumber` and `LensSerialNumber` (EXIF 3.0, 4.6.5, tags `0xA420`, `0xA430`,
    /// `0xA431` and `0xA435`).
    static let identifyingTags: Set<TagID> = [
        TagID(.exif, 0xA420), TagID(.exif, 0xA430),
        TagID(.exif, 0xA431), TagID(.exif, 0xA435),
    ]

    /// Names of tags the phone may write that the app never does, so they aren't in
    /// ``MetadataField/catalog``: from the EXIF 3.0 tag tables (4.6.5 for EXIF, 4.6.6 for GPS).
    static let otherTagNames: [TagID: String] = [
        TagID(.exif, 0x8832): "RecommendedExposureIndex",
        TagID(.exif, 0x9206): "SubjectDistance",
        TagID(.exif, 0x9208): "LightSource",
        TagID(.exif, 0x9286): "UserComment",
        TagID(.exif, 0xA401): "CustomRendered",
        TagID(.exif, 0xA404): "DigitalZoomRatio",
        TagID(.exif, 0xA408): "Contrast",
        TagID(.exif, 0xA409): "Saturation",
        TagID(.exif, 0xA40A): "Sharpness",
        TagID(.exif, 0xA40C): "SubjectDistanceRange",
        TagID(.exif, 0xA420): "ImageUniqueID",
        TagID(.exif, 0xA430): "CameraOwnerName",
        TagID(.exif, 0xA431): "BodySerialNumber",
        TagID(.exif, 0xA435): "LensSerialNumber",
        TagID(.exif, 0xA460): "CompositeImage",
        TagID(.exif, 0xA461): "SourceImageNumberOfCompositeImage",
        TagID(.exif, 0xA462): "SourceExposureTimesOfCompositeImage",
        TagID(.gps, 0x0007): "GPSTimeStamp",
        TagID(.gps, 0x000C): "GPSSpeedRef",
        TagID(.gps, 0x000D): "GPSSpeed",
        TagID(.gps, 0x0010): "GPSImgDirectionRef",
        TagID(.gps, 0x0011): "GPSImgDirection",
        TagID(.gps, 0x0017): "GPSDestBearingRef",
        TagID(.gps, 0x0018): "GPSDestBearing",
        TagID(.gps, 0x001D): "GPSDateStamp",
        TagID(.gps, 0x001F): "GPSHPositioningError",
    ]
}
