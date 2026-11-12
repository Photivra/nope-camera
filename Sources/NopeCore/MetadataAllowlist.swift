import Foundation

/// Everything one file may carry: the exact tags, container blocks, XMP properties and ImageIO
/// keys, for one format and one set of switches.
///
/// ``MetadataPlan/allowlist(for:signed:)`` builds it; ``MetadataVerifier`` checks a read-back
/// file against it. Anything not listed fails the check (AGENTS.md, "Metadata is allowlisted
/// and verified, never blocklisted").
public struct MetadataAllowlist: Equatable, Sendable {
    /// A tag by directory and number.
    public struct TagID: Hashable, Sendable, CustomStringConvertible {
        /// The directory.
        public let directory: TIFFDirectory
        /// The tag number.
        public let tag: UInt16

        /// Creates a tag ID.
        ///
        /// - Parameters:
        ///   - directory: The directory.
        ///   - tag: The tag number.
        public init(_ directory: TIFFDirectory, _ tag: UInt16) {
            self.directory = directory
            self.tag = tag
        }

        /// The tag as `exif 0x829A`.
        public var description: String {
            "\(directory.rawValue) " + String(format: "0x%04X", tag)
        }
    }

    /// An XMP property by namespace URI and local name.
    public struct XMPName: Hashable, Sendable {
        /// The namespace URI.
        public let namespace: String
        /// The local name.
        public let name: String

        /// Creates an XMP name.
        ///
        /// - Parameters:
        ///   - namespace: The namespace URI.
        ///   - name: The local name.
        public init(_ namespace: String, _ name: String) {
            self.namespace = namespace
            self.name = name
        }
    }

    /// What an ASCII tag's value must be.
    public enum TextRule: Equatable, Sendable {
        /// Exactly this text.
        case exactly(String)
        /// Text that starts with this prefix.
        case prefix(String)
        /// Any text: the value is the system's own (for example the system version).
        case any

        /// Whether a value follows the rule.
        ///
        /// - Parameter value: The tag's text, or `nil` if it isn't ASCII.
        /// - Returns: `true` if it follows the rule.
        public func accepts(_ value: String?) -> Bool {
            switch self {
            case .exactly(let expected): value == expected
            case .prefix(let prefix): value?.hasPrefix(prefix) == true
            case .any: true
            }
        }
    }

    /// The format the allowlist is for.
    public let format: PhotoFormat
    /// The tags that may appear.
    public let tags: Set<TagID>
    /// Directories whose every tag may appear (the GPS directory when location is on).
    public let wildcardDirectories: Set<TIFFDirectory>
    /// The container blocks that may appear (see ``JPEGReader`` and ``HEIFReader`` for names).
    public let blocks: Set<String>
    /// The XMP properties that may appear.
    public let xmpProperties: Set<XMPName>
    /// The ImageIO keys the read-back may report.
    public let imageIOKeys: Set<ImageIOKey>
    /// ImageIO sub-dictionaries whose every key may appear, such as `{GPS}` when location is on.
    public let wildcardImageIODictionaries: Set<String>
    /// Tags that must be present: for a DNG, the tags the DNG standard requires to open a Bayer
    /// RAW at all (DNG 1.7, chapter 4: `DNGVersion`, `UniqueCameraModel`, `ColorMatrix1`, and the
    /// CFA pattern tags), so a file AVFoundation wrote without them is rejected too.
    public let requiredTags: Set<TagID>
    /// Required values for ASCII tags, such as the generic `UniqueCameraModel`.
    public let textRules: [TagID: TextRule]
    /// Required values for XMP properties that mirror a tag: `CreatorTool` mirrors `Software`,
    /// and `dc:creator` and `dc:rights` mirror the artist and copyright. Other allowed XMP
    /// properties are dates.
    public let xmpTextRules: [XMPName: TextRule]
    /// Whether XMP dates may carry a fraction of a second.
    public let allowsSubSecondDates: Bool
    /// Whether XMP dates may carry a time zone.
    public let allowsTimeZoneDates: Bool

    /// Creates an allowlist. ``MetadataPlan`` is the only producer in the app.
    ///
    /// - Parameters:
    ///   - format: The format.
    ///   - tags: The allowed tags.
    ///   - wildcardDirectories: Directories allowed as a whole.
    ///   - blocks: The allowed container blocks.
    ///   - xmpProperties: The allowed XMP properties.
    ///   - imageIOKeys: The allowed ImageIO keys.
    ///   - wildcardImageIODictionaries: ImageIO dictionaries allowed as a whole.
    ///   - requiredTags: Tags that must be present.
    ///   - textRules: Required ASCII values.
    ///   - xmpTextRules: Required values for XMP properties that mirror a tag.
    ///   - allowsSubSecondDates: Whether XMP dates may have a fraction.
    ///   - allowsTimeZoneDates: Whether XMP dates may have a time zone.
    public init(
        format: PhotoFormat, tags: Set<TagID>, wildcardDirectories: Set<TIFFDirectory>, blocks: Set<String>,
        xmpProperties: Set<XMPName>, imageIOKeys: Set<ImageIOKey>, wildcardImageIODictionaries: Set<String>,
        requiredTags: Set<TagID>, textRules: [TagID: TextRule], xmpTextRules: [XMPName: TextRule], allowsSubSecondDates: Bool,
        allowsTimeZoneDates: Bool
    ) {
        self.format = format
        self.tags = tags
        self.wildcardDirectories = wildcardDirectories
        self.blocks = blocks
        self.xmpProperties = xmpProperties
        self.imageIOKeys = imageIOKeys
        self.wildcardImageIODictionaries = wildcardImageIODictionaries
        self.requiredTags = requiredTags
        self.textRules = textRules
        self.xmpTextRules = xmpTextRules
        self.allowsSubSecondDates = allowsSubSecondDates
        self.allowsTimeZoneDates = allowsTimeZoneDates
    }

    /// Whether a tag may appear.
    ///
    /// - Parameter id: The tag.
    public func allows(_ id: TagID) -> Bool {
        tags.contains(id) || wildcardDirectories.contains(id.directory)
    }

    /// Whether an ImageIO key may appear.
    ///
    /// - Parameter key: The key.
    public func allows(_ key: ImageIOKey) -> Bool {
        imageIOKeys.contains(key) || key.dictionary.map(wildcardImageIODictionaries.contains) == true
    }
}
