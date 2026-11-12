import Foundation

/// A directory (IFD) of a TIFF structure: a DNG file, or the EXIF block inside a HEIF or JPEG.
///
/// Tag numbers are only meaningful within their directory (GPS tags reuse low numbers), so the
/// allowlist and the read-back both name a tag by its directory and number. Directories follow
/// TIFF 6.0 (section 2), EXIF 3.0 (section 4.6) and DNG 1.7 (chapter 3).
public enum TIFFDirectory: String, CaseIterable, Codable, Hashable, Sendable {
    /// The first image directory (IFD0). In nope.'s DNG it holds the RAW image itself.
    case primary
    /// The EXIF directory, reached through tag `0x8769`.
    case exif
    /// The GPS directory, reached through tag `0x8825`.
    case gps
    /// The interoperability directory, reached through tag `0xA005`.
    case interoperability
    /// A directory reached through `SubIFDs` (`0x014A`), such as a second image in a DNG.
    case subImage
    /// A directory chained after IFD0 (IFD1 and later), such as an embedded thumbnail.
    case followingImage
}

/// Everything metadata-like that the read-back found in one file: every TIFF tag in every
/// directory, every container block (JPEG segment, HEIF box, item and property), and every
/// XMP property.
///
/// ``MetadataFileReader`` builds it from the file's bytes; ``MetadataVerifier`` compares it with
/// the allowlist. Privacy: it holds the file's tag values only in memory, and a ``SavedPhoto``
/// keeps it for the "What's in your last photo" screen (issue #1); it is never logged.
public struct MetadataInventory: Equatable, Sendable {
    /// One TIFF tag found in a directory.
    public struct Tag: Hashable, Sendable {
        /// The directory the tag is in.
        public let directory: TIFFDirectory
        /// The tag number.
        public let tag: UInt16
        /// The value of an ASCII tag, without the trailing NUL, or `nil` for other types.
        public let text: String?

        /// Creates a tag record.
        ///
        /// - Parameters:
        ///   - directory: The directory the tag is in.
        ///   - tag: The tag number.
        ///   - text: The ASCII value, or `nil`.
        public init(directory: TIFFDirectory, tag: UInt16, text: String? = nil) {
            self.directory = directory
            self.tag = tag
            self.text = text
        }
    }

    /// One top-level XMP property (a child of `rdf:Description`, or one of its attributes).
    public struct XMPProperty: Hashable, Sendable {
        /// The namespace URI, such as `http://ns.adobe.com/photoshop/1.0/`.
        public let namespace: String
        /// The local name, such as `DateCreated`.
        public let name: String
        /// The property's text, trimmed; empty for a structure.
        public let value: String

        /// Creates an XMP property record.
        ///
        /// - Parameters:
        ///   - namespace: The namespace URI.
        ///   - name: The local name.
        ///   - value: The text value.
        public init(namespace: String, name: String, value: String) {
            self.namespace = namespace
            self.name = name
            self.value = value
        }
    }

    /// Every TIFF tag, in file order.
    public var tags: [Tag]

    /// Every container block, named like `jpeg:APP1:Exif` or `heif:item:hvc1`, in file order.
    public var blocks: [String]

    /// Every top-level XMP property, in file order.
    public var xmpProperties: [XMPProperty]

    /// Anything the reader couldn't read: a truncated directory, a loop, an unknown structure.
    /// The verifier rejects a file with any problem (fail closed).
    public var problems: [String]

    /// Creates an inventory.
    ///
    /// - Parameters:
    ///   - tags: The TIFF tags.
    ///   - blocks: The container blocks.
    ///   - xmpProperties: The XMP properties.
    ///   - problems: What couldn't be read.
    public init(tags: [Tag] = [], blocks: [String] = [], xmpProperties: [XMPProperty] = [], problems: [String] = []) {
        self.tags = tags
        self.blocks = blocks
        self.xmpProperties = xmpProperties
        self.problems = problems
    }

    /// Adds everything from another inventory, such as the EXIF block inside a HEIF.
    ///
    /// - Parameter other: The inventory to add.
    mutating func append(_ other: MetadataInventory) {
        tags += other.tags
        blocks += other.blocks
        xmpProperties += other.xmpProperties
        problems += other.problems
    }
}
