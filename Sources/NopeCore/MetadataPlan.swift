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
    /// DNG standard requires the tag (DNG 1.7, "UniqueCameraModel"), so the app writes a value
    /// that names no device.
    public static let genericUniqueCameraModel = "Generic camera"

    /// The app's name as written into `Software` when ``MetadataItem/appNameAndVersion`` is on:
    /// the full product name, as the owner decided (2026-11-12), so files say "Photivra Nope
    /// Camera 0.2.0", or "Photivra Nope Camera 0.2.0 (27.2.1)" with the system version.
    public static let appName = "Photivra Nope Camera"

    /// The `{TIFF}` fields a DNG's replacement metadata must always contain: `DateTime`, `Make`,
    /// `Model` and `Software`.
    ///
    /// Measured on an iPhone 16 Pro Max with iOS 27.2.1 (issue #65):
    /// `AVCapturePhoto.fileDataRepresentation(with:)` returns `nil` for a Bayer RAW photo unless
    /// the replacement metadata's `{TIFF}` dictionary has all four keys. Leaving out any one of
    /// them fails; an empty string for each works; `NSNull` doesn't. Apple doesn't document the
    /// requirement. Privacy rule: when a field's switch is off, the app writes an empty string, never
    /// a made-up value, so the DNG still says nothing about the date, camera or software; with the
    /// standard file tags on, the date is the Exif standard's all-blank "unknown" form instead
    /// (``unknownDateTime``), which holds no date either.
    public static let requiredRAWTIFFFields: [MetadataField] = [.dateTime, .make, .model, .software]

    /// The `DateTime` a DNG carries when its date switch is off and the standard file tags are
    /// on: the Exif standard's form for an unknown date, "all the character spaces except colons
    /// filled with blank characters" (Exif 2.32 and 3.0, `DateTime`). It says nothing about when
    /// the photo was taken, and `exiftool -validate` accepts it, where it reports an empty string
    /// as an invalid date. It is still a value, so AVFoundation's need for the key (issue #65)
    /// is met.
    public static let unknownDateTime = "    :  :     :  :  "

    /// `ComponentsConfiguration` for a YCbCr image: Y, Cb, Cr and an unused fourth component
    /// (Exif 2.32, `ComponentsConfiguration`, "4 5 6 0" is RGB, "1 2 3 0" the default for YCbCr).
    public static let ycbcrComponentsConfiguration = [1, 2, 3, 0]

    /// `ExifVersion` 2.32 ("0232"), the version ImageIO writes into the files it encodes itself.
    public static let exifVersion = [2, 3, 2]

    /// `FlashpixVersion` 1.0, the only version the Exif standard defines (Exif 2.32,
    /// `FlashpixVersion`, "0100").
    public static let flashpixVersion = [1, 0]

    /// `ColorSpace` for any color space other than sRGB: "Uncalibrated" (Exif 2.32, `ColorSpace`,
    /// `0xFFFF`). `PhotoEncoder` writes 1 (sRGB) for an sRGB copy.
    public static let uncalibratedColorSpace = 0xFFFF

    /// `GPSVersionID` 2.3.0.0, the version of the GPS directory in Exif 2.3 and later.
    public static let gpsVersion = [2, 3, 0, 0]

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

    /// ImageIO's top-level keys that describe a decoded HEIF and are allowed only in a HEIF.
    /// `Headroom` is the image's HDR headroom as the reader derives it. The iOS 26.5 Simulator
    /// reports it on every HEIF the app writes, with no new box in the file (the HEIF block
    /// check finds none; the content light level box, `heif:property:clli`, is already allowed),
    /// where iOS 27.2 reports the `ContentLightLevelInfo` dictionary instead.
    static let heifDerivedImageIOKeys: [String] = ["Headroom"]

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

    /// Whether the photo is saved mirrored left to right: a front camera photo with
    /// ``SaveSettings/mirrorsFrontCamera`` on (issue #45). The mirroring is done only through
    /// the orientation value (``mirroredOrientation(_:)``): the sensor data is never changed.
    /// ``CameraModel`` sets it for each capture. Off by default.
    public var mirrorsHorizontally = false

    /// Where the photo was taken, written when ``MetadataItem/location`` is on, or `nil` for no
    /// location (issue #43). ``CameraModel`` sets it for each capture from ``LocationTagging``;
    /// nothing else supplies a location, and the system's own metadata carries none.
    public var location: PhotoLocation?

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
        let written = MetadataField.catalog.filter { writes($0, in: format) }
        let alwaysPresent = format == .raw ? Self.requiredRAWTIFFFields.filter { !written.contains($0) } : []
        let fields = written + alwaysPresent
        var tags = Set(fields.map { MetadataAllowlist.TagID($0.directory, $0.tag) })
        var blocks: Set<String> = []
        var xmp: Set<MetadataAllowlist.XMPName> = []
        var derivedKeys = Self.derivedImageIOKeys
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
        // A DNG always carries these four, empty when their switch is off (issue #65). With the
        // standard file tags on, the date is written as the standard's unknown form; any blank
        // date passes (empty, or blanks and colons however AVFoundation pads or trims them),
        // since how it stores the value is a device check and none of them holds a date.
        for field in alwaysPresent {
            let rule: MetadataAllowlist.TextRule =
                field == .dateTime && settings.writesStandardFileTags ? .blankDate : .exactly("")
            textRules[MetadataAllowlist.TagID(field.directory, field.tag)] = rule
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
            derivedKeys += Self.heifDerivedImageIOKeys
            if settings.isOn(.dateAndTime) {
                xmp.formUnion([
                    MetadataAllowlist.XMPName(Self.photoshopNamespace, "DateCreated"),
                    MetadataAllowlist.XMPName(Self.xmpNamespace, "CreateDate"),
                    MetadataAllowlist.XMPName(Self.xmpNamespace, "ModifyDate"),
                ])
            }
            for (field, name) in Self.xmpMirrors where written.contains(field) { xmp.insert(name) }
            if !xmp.isEmpty { blocks.insert(Self.heifXMPBlock) }
        }
        if settings.isOn(.makerNotes) { wildcardDictionaries.insert(MetadataField.makerApple) }
        let imageIOKeys = Set(fields.flatMap(\.imageIOKeys) + derivedKeys.map { ImageIOKey(nil, $0) })
        return MetadataAllowlist(
            format: format, tags: tags, wildcardDirectories: [], blocks: blocks,
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
    /// the person's name and copyright, the ``location`` and a mirrored orientation
    /// (``mirrorsHorizontally``) are written by the app; everything else is the system's own value. A DNG's dictionary always has the ``requiredRAWTIFFFields``, with an empty
    /// string for each one whose switch is off.
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
            for key in field.imageIOKeys where Self.isWritten(key, in: format) {
                if let value = Self.value(of: key, in: source) { Self.put(value, at: key, in: &result) }
            }
        }
        if settings.isOn(.makerNotes), let value = source[MetadataField.makerApple] {
            result[MetadataField.makerApple] = value
        }
        // Privacy rule (issue #43): the GPS directory is built from the plan's location only,
        // with the fields of `MetadataField.gpsFields`; a developed copy takes the same fields
        // from its DNG through the catalog loop above.
        if settings.isOn(.location), let location { result[MetadataField.gps] = location.gpsProperties }
        if settings.writesStandardFileTags { addStandardFileTags(for: format, to: &result) }
        let sourceSoftware = Self.value(of: ImageIOKey(MetadataField.tiff, "Software"), in: source) as? String
        if let software = softwareValue(systemSoftware: Self.systemVersion(fromSoftware: sourceSoftware)) {
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
        } else if mirrorsHorizontally {
            let current = MetadataField.orientation.imageIOKeys.lazy.compactMap { Self.value(of: $0, in: source) as? Int }
                .first
            let mirrored = Self.mirroredOrientation(current ?? 1)
            for key in MetadataField.orientation.imageIOKeys { Self.put(mirrored, at: key, in: &result) }
        }
        if format == .raw {
            // AVFoundation writes no DNG without these four keys (issue #65): an empty string
            // stands in for a value the switches leave out, or the system didn't supply.
            for field in Self.requiredRAWTIFFFields where Self.value(of: field.imageIOKeys[0], in: result) == nil {
                let placeholder = field == .dateTime && settings.writesStandardFileTags ? Self.unknownDateTime : ""
                Self.put(placeholder, at: field.imageIOKeys[0], in: &result)
            }
        }
        return result
    }

    /// Adds the standard file tags (``MetadataSettings/writesStandardFileTags``) a file doesn't
    /// have yet: in a HEIF or JPEG the EXIF `ExifVersion`, `ComponentsConfiguration`,
    /// `FlashpixVersion` and `ColorSpace`, and in any file with a GPS directory its `GPSVersionID`. Each is a fixed
    /// value from the Exif standard on the allowlist (locked image structure, or the location
    /// item's GPS fields), so nothing identifying is added; a value the source already has is
    /// kept.
    ///
    /// ImageIO writes no `YCbCrPositioning` (IFD0 `0x0213`): `CGImageProperties.h` has no key for
    /// it, and neither the `{TIFF}` dictionary nor an XMP `tiff:YCbCrPositioning` tag puts it in
    /// a JPEG's EXIF (macOS 27.2, 2026-11-16). It also drops `ColorSpace` from a Display P3
    /// JPEG; a Display P3 HEIF keeps it (`docs/TESTING.md`, "External validators").
    ///
    /// - Parameters:
    ///   - format: The file's format.
    ///   - result: The property dictionary being built.
    func addStandardFileTags(for format: PhotoFormat, to result: inout [String: Any]) {
        if format != .raw {
            let exif = MetadataField.exif
            for (key, value) in [
                ("ExifVersion", Self.exifVersion as Any), ("ComponentsConfiguration", Self.ycbcrComponentsConfiguration as Any), ("FlashPixVersion", Self.flashpixVersion),
                ("ColorSpace", Self.uncalibratedColorSpace),
            ] where Self.value(of: ImageIOKey(exif, key), in: result) == nil {
                Self.put(value, at: ImageIOKey(exif, key), in: &result)
            }
        }
        let version = ImageIOKey(MetadataField.gps, PhotoLocation.versionKey)
        if result[MetadataField.gps] != nil, Self.value(of: version, in: result) == nil {
            Self.put(Self.gpsVersion, at: version, in: &result)
        }
    }

    /// Whether a value under an ImageIO key is copied into a file of a format.
    ///
    /// A HEIF or JPEG never gets the `{ExifAux}` dictionary (issue #58). ImageIO reports a DNG's
    /// `LensSpecification` and `LensModel` again as `{ExifAux}` `LensInfo` and `LensModel`, so
    /// a developed copy's source has both; written back, ImageIO stores the `{ExifAux}` values
    /// as XMP `aux:LensInfo` and `aux:Lens` properties, which no allowlist permits, and the
    /// read-back rejected the photo: with "Lens make and model" on and a HEIF or JPEG selected,
    /// nothing was saved (`FileCompatibilityTests`, iOS 27.2 Simulator, 2026-11-14). The same
    /// values are still written as the EXIF `LensSpecification` and `LensModel` tags. A DNG keeps
    /// every key: its metadata is written by AVFoundation, which the device tag check covers.
    ///
    /// - Parameters:
    ///   - key: The ImageIO key.
    ///   - format: The file's format.
    /// - Returns: `false` for an `{ExifAux}` key in a HEIF or JPEG; otherwise `true`.
    static func isWritten(_ key: ImageIOKey, in format: PhotoFormat) -> Bool {
        format == .raw || key.dictionary != MetadataField.exifAux
    }

    /// The orientation that shows a photo mirrored left to right, for an EXIF/TIFF orientation
    /// value (issue #45).
    ///
    /// TIFF 6.0 (`Orientation`, tag 274) and EXIF 3.0 define eight values: 1 upright, 2 mirrored,
    /// 3 turned 180°, 4 turned 180° and mirrored, 5 mirrored and turned 90° counterclockwise
    /// (a transpose), 6 turned 90° clockwise, 7 mirrored and turned 90° clockwise (a transverse)
    /// and 8 turned 90° counterclockwise. Mirroring the upright result left to right swaps each
    /// pair: 1↔2, 3↔4, 5↔6 and 7↔8. The sensor data is never changed.
    ///
    /// - Parameter orientation: The orientation the photo would be shown with, 1 to 8. Any other
    ///   value is treated as 1, upright.
    /// - Returns: The mirrored orientation, 1 to 8.
    public static func mirroredOrientation(_ orientation: Int) -> Int {
        let value = (1...8).contains(orientation) ? orientation : 1
        return value.isMultiple(of: 2) ? value - 1 : value + 1
    }

    /// The system's version in a `Software` value: the value itself when the system wrote it, the
    /// part in parentheses when the app wrote both ("Photivra Nope Camera 0.2.0 (27.2.1)"), or none.
    ///
    /// A HEIF or JPEG is developed from the DNG's metadata, whose `Software` the app already
    /// wrote, so reading it as the system's own value would nest the app's name:
    /// "Photivra Nope Camera 0.2.0 (Photivra Nope Camera 0.2.0 (27.2.1))".
    ///
    /// - Parameter software: The source's `Software` value, if any.
    /// - Returns: The system's version, or `nil` if there is none (also for an empty value).
    static func systemVersion(fromSoftware software: String?) -> String? {
        guard let software, !software.isEmpty else { return nil }
        guard software.hasPrefix(appName) else { return software }
        guard software.hasSuffix(")"), let open = software.range(of: " (", options: .backwards) else { return nil }
        let version = software[open.upperBound..<software.index(before: software.endIndex)]
        return version.isEmpty ? nil : String(version)
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
