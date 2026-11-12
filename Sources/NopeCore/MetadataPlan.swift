import Foundation

/// Turns the person's ``MetadataSettings`` into each file's metadata: the allowlist a file is
/// checked against, and the ImageIO property dictionary a file is written with.
///
/// Privacy rule: a file's metadata is built from the allowlist, never by deleting known tags
/// from what the system wrote (AGENTS.md, "Metadata is allowlisted and verified"). The builder
/// starts from an empty dictionary and copies in only the values of fields in
/// ``MetadataField/catalog`` that the switches allow, so a tag a future iOS adds is never copied.
public struct MetadataPlan: Equatable, Sendable {
    /// The `UniqueCameraModel` a DNG carries when ``MetadataItem/exactCameraModel`` is off. The
    /// DNG standard requires the tag (DNG 1.7, "UniqueCameraModel"), so nope. writes a value
    /// that names no device.
    public static let genericUniqueCameraModel = "Generic camera"

    /// The app's name as written into `Software` when ``MetadataItem/appNameAndVersion`` is on:
    /// the full product name, as the owner decided (2026-11-12), so files say "Photivra Nope
    /// Camera 0.2.0", or "Photivra Nope Camera 0.2.0 (27.2.1)" with the system version.
    public static let appName = "Photivra Nope Camera"

    /// The XMP basic namespace (XMP part 1, 8.4).
    public static let xmpNamespace = "http://ns.adobe.com/xap/1.0/"
    /// The Photoshop namespace, used by ImageIO for `DateCreated` (XMP part 2, 3.2).
    public static let photoshopNamespace = "http://ns.adobe.com/photoshop/1.0/"
    /// The Dublin Core namespace, used by ImageIO for `creator` and `rights` (XMP part 1, 8.3).
    public static let dublinCoreNamespace = "http://purl.org/dc/elements/1.1/"

    /// ImageIO's top-level keys that describe the decoded image rather than a tag in the file.
    static let derivedImageIOKeys: [String] = [
        "ColorModel", "Depth", "PixelWidth", "PixelHeight", "ProfileName", "DPIWidth", "DPIHeight", "PrimaryImage",
        "HasAlpha", "IsFloat", "IsIndexed",
    ]

    /// The JPEG segments every JPEG may have: structure, the EXIF block, the color profile and
    /// ImageIO's empty IPTC record (``JPEGReader/emptyIPTCSegment``).
    static let jpegBlocks: Set<String> = [
        "jpeg:APP0:JFIF", "jpeg:APP1:Exif", "jpeg:APP2:ICC", "jpeg:APP13:empty-IPTC", "jpeg:SOF", "jpeg:DHT",
        "jpeg:DQT", "jpeg:DRI", "jpeg:SOS", "jpeg:EOI",
    ]

    /// The HEIF boxes, items, properties and references every HEIF may have: the image (one
    /// `hvc1` item, or a `grid` of them), the EXIF item, the color profile (`colr`) and the
    /// image's layout. No thumbnails (`thmb`) or auxiliary images (`auxl`).
    static let heifBlocks: Set<String> = [
        "heif:box:ftyp", "heif:box:meta", "heif:box:mdat", "heif:meta:hdlr", "heif:meta:dinf", "heif:meta:pitm",
        "heif:meta:iinf", "heif:meta:iref", "heif:meta:iprp", "heif:meta:iloc", "heif:meta:idat", "heif:item:hvc1",
        "heif:item:grid", "heif:item:Exif", "heif:property:colr", "heif:property:ispe", "heif:property:irot",
        "heif:property:imir", "heif:property:pixi", "heif:property:hvcC", "heif:property:clli",
        "heif:reference:dimg", "heif:reference:cdsc",
    ]

    /// The HEIF block for the XMP item, allowed only when an XMP property is.
    static let heifXMPBlock = "heif:item:mime:\(HEIFReader.xmpContentType)"

    /// Where a Content Credentials manifest lives in each format, allowed only in a signed file.
    /// From the C2PA 2.1 specification, appendix A ("Embedding manifests"): JUMBF in JPEG APP11
    /// segments (A.3.1), a top-level `uuid` box in ISOBMFF files such as HEIF (A.4), and TIFF
    /// tag 52545 (`0xCD41`) for TIFF and DNG (A.3.3). The signing module confirms these when it
    /// lands.
    static let contentCredentialsTag = MetadataAllowlist.TagID(.primary, 0xCD41)
    /// The JPEG segment that holds a Content Credentials manifest.
    static let contentCredentialsJPEGBlock = "jpeg:APP11"
    /// The HEIF box that holds a Content Credentials manifest.
    static let contentCredentialsHEIFBlock = "heif:box:uuid"

    /// The tags a DNG can't be opened without (DNG 1.7, chapter 4): `CFARepeatPatternDim`,
    /// `CFAPattern`, `DNGVersion`, `UniqueCameraModel` and `ColorMatrix1`.
    static let requiredDNGTags: Set<MetadataAllowlist.TagID> = Set(
        [0x828D, 0x828E, 0xC612, 0xC614, 0xC621].map { MetadataAllowlist.TagID(.primary, $0) })

    /// The XMP properties ImageIO writes into a HEIF to mirror a tag, with that tag.
    static let xmpMirrors: [(field: MetadataField, name: MetadataAllowlist.XMPName)] = [
        (.software, MetadataAllowlist.XMPName(xmpNamespace, "CreatorTool")),
        (.artist, MetadataAllowlist.XMPName(dublinCoreNamespace, "creator")),
        (.copyright, MetadataAllowlist.XMPName(dublinCoreNamespace, "rights")),
    ]

    /// The person's choices.
    public let settings: MetadataSettings

    /// The app's version, such as `0.2.0`, written with the app's name when
    /// ``MetadataItem/appNameAndVersion`` is on.
    public let appVersion: String

    /// Creates a plan.
    ///
    /// - Parameters:
    ///   - settings: The person's choices. Defaults to the first-launch settings: every optional
    ///     detail removed.
    ///   - appVersion: The app's version, from its bundle.
    public init(settings: MetadataSettings = MetadataSettings(), appVersion: String = "") {
        self.settings = settings
        self.appVersion = appVersion
    }

    /// The `Software` value that names the app, such as `Photivra Nope Camera 0.2.0`.
    var appSoftwareName: String {
        appVersion.isEmpty ? Self.appName : "\(Self.appName) \(appVersion)"
    }

    /// What `Software` (and XMP `CreatorTool`) must be: the app's name, the system's version, or
    /// both, as the switches say.
    var softwareRule: MetadataAllowlist.TextRule {
        switch (settings.isOn(.appNameAndVersion), settings.isOn(.systemVersion)) {
        case (true, true): .prefix(appSoftwareName)
        case (true, false): .exactly(appSoftwareName)
        default: .any
        }
    }

    /// Whether a field is written to a file of a format.
    ///
    /// - Parameters:
    ///   - field: The field.
    ///   - format: The file's format.
    /// - Returns: `true` if the field's switch is on (or it is locked), and, for the name and
    ///   copyright, the person entered the text.
    func writes(_ field: MetadataField, in format: PhotoFormat) -> Bool {
        guard field.formats.contains(format) else { return false }
        switch field {
        case .uniqueCameraModel: return true
        case .artist: return settings.isOn(.nameAndCopyright) && !settings.ownerName.isEmpty
        case .copyright: return settings.isOn(.nameAndCopyright) && !settings.copyrightNotice.isEmpty
        default: break
        }
        switch field.group {
        case .locked: return true
        case .optional(let items): return !items.isDisjoint(with: settings.enabledItems)
        }
    }

    /// The allowlist for one file.
    ///
    /// - Parameters:
    ///   - format: The file's format.
    ///   - signed: Whether the file carries a Content Credentials manifest, which adds the
    ///     manifest's tag or block.
    /// - Returns: Everything the file may carry.
    public func allowlist(for format: PhotoFormat, signed: Bool) -> MetadataAllowlist {
        let fields = MetadataField.catalog.filter { writes($0, in: format) }
        var tags = Set(fields.map { MetadataAllowlist.TagID($0.directory, $0.tag) })
        var blocks: Set<String> = []
        var xmp: Set<MetadataAllowlist.XMPName> = []
        var wildcardDictionaries: Set<String> = []
        var textRules: [MetadataAllowlist.TagID: MetadataAllowlist.TextRule] = [
            MetadataAllowlist.TagID(.primary, MetadataField.software.tag): softwareRule,
            MetadataAllowlist.TagID(.primary, MetadataField.artist.tag): .exactly(settings.ownerName),
            MetadataAllowlist.TagID(.primary, MetadataField.copyright.tag): .exactly(settings.copyrightNotice),
        ]
        if !settings.isOn(.exactCameraModel) {
            textRules[MetadataAllowlist.TagID(.primary, MetadataField.uniqueCameraModel.tag)] =
                .exactly(Self.genericUniqueCameraModel)
        }
        switch format {
        case .raw:
            if signed { tags.insert(Self.contentCredentialsTag) }
        case .jpeg:
            blocks = Self.jpegBlocks
            if signed { blocks.insert(Self.contentCredentialsJPEGBlock) }
            wildcardDictionaries.insert("{JFIF}")
        case .heif:
            blocks = Self.heifBlocks
            if signed { blocks.insert(Self.contentCredentialsHEIFBlock) }
            wildcardDictionaries.insert("ContentLightLevelInfo")
            if settings.isOn(.dateAndTime) {
                xmp.formUnion([
                    MetadataAllowlist.XMPName(Self.photoshopNamespace, "DateCreated"),
                    MetadataAllowlist.XMPName(Self.xmpNamespace, "CreateDate"),
                    MetadataAllowlist.XMPName(Self.xmpNamespace, "ModifyDate"),
                ])
            }
            for (field, name) in Self.xmpMirrors where fields.contains(field) { xmp.insert(name) }
            if !xmp.isEmpty { blocks.insert(Self.heifXMPBlock) }
        }
        if settings.isOn(.location) { wildcardDictionaries.insert(MetadataField.gps) }
        if settings.isOn(.makerNotes) { wildcardDictionaries.insert(MetadataField.makerApple) }
        let imageIOKeys = Set(fields.flatMap(\.imageIOKeys) + Self.derivedImageIOKeys.map { ImageIOKey(nil, $0) })
        return MetadataAllowlist(
            format: format, tags: tags, wildcardDirectories: settings.isOn(.location) ? [.gps] : [], blocks: blocks,
            xmpProperties: xmp, imageIOKeys: imageIOKeys, wildcardImageIODictionaries: wildcardDictionaries,
            requiredTags: format == .raw ? Self.requiredDNGTags : [], textRules: textRules,
            xmpTextRules: [
                Self.xmpMirrors[0].name: softwareRule, Self.xmpMirrors[1].name: .exactly(settings.ownerName),
                Self.xmpMirrors[2].name: .exactly(settings.copyrightNotice),
            ],
            allowsSubSecondDates: settings.isOn(.subSecondTime), allowsTimeZoneDates: settings.isOn(.timeZone))
    }

    /// Builds the ImageIO property dictionary to write a file with, from the system's metadata.
    ///
    /// Privacy rule: the result starts empty, and only allowlisted values are copied in
    /// (AGENTS.md, "Build metadata from the allowlist"). The app's name, the generic camera model,
    /// and the person's name and copyright are written by nope.; everything else is the system's
    /// own value.
    ///
    /// - Parameters:
    ///   - format: The file's format.
    ///   - source: The system's metadata, as ImageIO property dictionaries (for example
    ///     `AVCapturePhoto.metadata`, or the properties of the DNG a HEIF is developed from).
    ///   - orientation: An orientation to write instead of the source's, such as 1 (up) for a
    ///     photo developed upright; `nil` keeps the source's.
    /// - Returns: The dictionary, keyed like `CGImageProperties.h`.
    public func properties(for format: PhotoFormat, from source: [String: Any], orientation: Int? = nil) -> [String: Any] {
        var result: [String: Any] = [:]
        let special: [MetadataField] = [.software, .uniqueCameraModel, .artist, .copyright]
        for field in MetadataField.catalog where writes(field, in: format) && !special.contains(field) {
            for key in field.imageIOKeys {
                if let value = Self.value(of: key, in: source) { Self.put(value, at: key, in: &result) }
            }
        }
        for (item, dictionary) in [(MetadataItem.location, MetadataField.gps), (.makerNotes, MetadataField.makerApple)]
        where settings.isOn(item) {
            if let value = source[dictionary] { result[dictionary] = value }
        }
        let systemSoftware = Self.value(of: ImageIOKey(MetadataField.tiff, "Software"), in: source) as? String
        if let software = softwareValue(systemSoftware: systemSoftware) {
            Self.put(software, at: ImageIOKey(MetadataField.tiff, "Software"), in: &result)
        }
        if writes(.uniqueCameraModel, in: format) {
            let model = MetadataField.uniqueCameraModel.imageIOKeys[0]
            let value = settings.isOn(.exactCameraModel) ? Self.value(of: model, in: source) : Self.genericUniqueCameraModel
            if let value { Self.put(value, at: model, in: &result) }
        }
        if writes(.artist, in: format) { Self.put(settings.ownerName, at: MetadataField.artist.imageIOKeys[0], in: &result) }
        if writes(.copyright, in: format) {
            Self.put(settings.copyrightNotice, at: MetadataField.copyright.imageIOKeys[0], in: &result)
        }
        if let orientation {
            for key in MetadataField.orientation.imageIOKeys { Self.put(orientation, at: key, in: &result) }
        }
        return result
    }

    /// The `Software` value: the app's name, the system's version, both, or nothing.
    ///
    /// - Parameter systemSoftware: The system's `Software` value, if it wrote one.
    /// - Returns: The value to write, or `nil` to write none.
    func softwareValue(systemSoftware: String?) -> String? {
        let app = settings.isOn(.appNameAndVersion) ? appSoftwareName : nil
        let system = settings.isOn(.systemVersion) ? systemSoftware : nil
        switch (app, system) {
        case (let app?, let system?): return "\(app) (\(system))"
        case (let app?, nil): return app
        case (nil, let system): return system
        }
    }

    /// The value under an ImageIO key in a property dictionary.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - dictionary: The property dictionary.
    /// - Returns: The value, or `nil` if absent.
    static func value(of key: ImageIOKey, in dictionary: [String: Any]) -> Any? {
        guard let name = key.dictionary else { return dictionary[key.key] }
        return (dictionary[name] as? [String: Any])?[key.key]
    }

    /// Stores a value under an ImageIO key, creating the sub-dictionary if needed.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - key: The key.
    ///   - dictionary: The property dictionary to change.
    static func put(_ value: Any, at key: ImageIOKey, in dictionary: inout [String: Any]) {
        guard let name = key.dictionary else {
            dictionary[key.key] = value
            return
        }
        var sub = dictionary[name] as? [String: Any] ?? [:]
        sub[key.key] = value
        dictionary[name] = sub
    }
}
