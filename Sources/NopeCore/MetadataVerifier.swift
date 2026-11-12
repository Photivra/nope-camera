import Foundation

/// One reason a read-back file fails the allowlist.
public enum MetadataViolation: Hashable, Sendable {
    /// Part of the file couldn't be read, so it can't be shown to be clean.
    case unreadable(String)
    /// A tag that isn't on the allowlist.
    case unexpectedTag(MetadataAllowlist.TagID)
    /// A tag the file can't be opened without is missing.
    case missingTag(MetadataAllowlist.TagID)
    /// An allowed tag with a value nope. didn't write, such as an exact camera model when the
    /// generic one was asked for.
    case unexpectedValue(MetadataAllowlist.TagID)
    /// A container block that isn't on the allowlist, such as an XMP segment or a thumbnail.
    case unexpectedBlock(String)
    /// An XMP property that isn't on the allowlist.
    case unexpectedXMPProperty(MetadataAllowlist.XMPName)
    /// An allowed XMP property with a value that isn't, such as a date with a time zone when the
    /// time zone is off.
    case unexpectedXMPValue(MetadataAllowlist.XMPName)
    /// An ImageIO property that isn't on the allowlist.
    case unexpectedImageIOKey(ImageIOKey)
    /// The DNG's RAW image data isn't the data the camera returned.
    case rawImageDataChanged
    /// The DNG has no readable RAW image data, or there was no reference to compare it with.
    case rawImageDataMissing
}

/// Compares a read-back file with its allowlist (AGENTS.md, "Fail closed").
///
/// A file passes only with no violation at all. The save pipeline (``PhotoSaver``) never adds a
/// file that fails to Photos.
public enum MetadataVerifier {
    /// Lists every way a file breaks its allowlist.
    ///
    /// - Parameters:
    ///   - readBack: What the read-back found in the file.
    ///   - allowlist: What the file may carry.
    ///   - expectedRawImageData: For a DNG, the RAW image data the camera returned; ignored for
    ///     other formats.
    /// - Returns: The violations, in file order; empty means the file passes.
    public static func violations(
        in readBack: MetadataReadBack, allowlist: MetadataAllowlist, expectedRawImageData: Data?
    ) -> [MetadataViolation] {
        let inventory = readBack.file.inventory
        var violations = inventory.problems.map(MetadataViolation.unreadable)
        for tag in inventory.tags {
            let id = MetadataAllowlist.TagID(tag.directory, tag.tag)
            if !allowlist.allows(id) {
                violations.append(.unexpectedTag(id))
            } else if let rule = allowlist.textRules[id], !rule.accepts(tag.text) {
                violations.append(.unexpectedValue(id))
            }
        }
        let present = Set(inventory.tags.map { MetadataAllowlist.TagID($0.directory, $0.tag) })
        violations += allowlist.requiredTags.subtracting(present).sorted { $0.tag < $1.tag }.map(MetadataViolation.missingTag)
        violations += inventory.blocks.filter { !allowlist.blocks.contains($0) }.map(MetadataViolation.unexpectedBlock)
        for property in inventory.xmpProperties {
            let name = MetadataAllowlist.XMPName(property.namespace, property.name)
            if !allowlist.xmpProperties.contains(name) {
                violations.append(.unexpectedXMPProperty(name))
            } else if !accepts(property, name: name, allowlist: allowlist) {
                violations.append(.unexpectedXMPValue(name))
            }
        }
        violations += readBack.imageIOKeys.filter { !allowlist.allows($0) }.map(MetadataViolation.unexpectedImageIOKey)
        if allowlist.format == .raw {
            if let saved = readBack.file.rawImageData, let expectedRawImageData {
                if saved != expectedRawImageData { violations.append(.rawImageDataChanged) }
            } else {
                violations.append(.rawImageDataMissing)
            }
        }
        return violations
    }

    /// Whether an allowed XMP property's value is allowed: a property that mirrors a tag follows
    /// that tag's rule, and a date carries a fraction of a second or a time zone only when those
    /// switches are on.
    ///
    /// - Parameters:
    ///   - property: The property.
    ///   - name: Its name.
    ///   - allowlist: The allowlist.
    /// - Returns: `true` if the value is allowed.
    static func accepts(
        _ property: MetadataInventory.XMPProperty, name: MetadataAllowlist.XMPName, allowlist: MetadataAllowlist
    ) -> Bool {
        if let rule = allowlist.xmpTextRules[name] { return rule.accepts(property.value) }
        let date = XMPDate(property.value)
        return (allowlist.allowsSubSecondDates || !date.hasFraction) && (allowlist.allowsTimeZoneDates || !date.hasZone)
    }
}

/// What an XMP date (ISO 8601, XMP part 1, 8.2.1.1) carries beyond the date and time.
struct XMPDate: Equatable {
    /// Whether the seconds have a fraction, such as `.473`.
    let hasFraction: Bool
    /// Whether a time zone follows the time: `Z`, or `+hh:mm` / `-hh:mm`.
    let hasZone: Bool

    /// Reads a date such as `2026-11-12T00:11:51.473-05:00`.
    ///
    /// - Parameter text: The date text.
    init(_ text: String) {
        guard let timeStart = text.firstIndex(of: "T") else {
            hasFraction = false
            hasZone = false
            return
        }
        let time = text[timeStart...]
        hasFraction = time.contains(".")
        hasZone = time.contains("Z") || time.contains("+") || time.contains("-")
    }
}
