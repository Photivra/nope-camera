import Foundation
import NopeCore
import Testing

/// The exact tags each format may carry for each switch (AGENTS.md: "metadata tests asserting
/// the exact tags written for each switch combination"). Written out by hand from
/// docs/PRIVACY.md, independently of `MetadataField.catalog`, so a change to either fails here.
enum ExpectedTags {
    typealias ID = MetadataAllowlist.TagID

    static func ids(_ directory: TIFFDirectory, _ tags: [UInt16]) -> Set<ID> {
        Set(tags.map { ID(directory, $0) })
    }

    /// Locked tags, by format.
    static func locked(_ format: PhotoFormat) -> Set<ID> {
        switch format {
        case .raw:
            ids(
                .primary,
                [
                    0x00FE, 0x0100, 0x0101, 0x0102, 0x0103, 0x0106, 0x0111, 0x0112, 0x0115, 0x0116, 0x0117, 0x011C,
                    0x0142, 0x0143, 0x0144, 0x0145, 0x8769, 0x828D, 0x828E, 0xC612, 0xC613, 0xC614, 0xC616, 0xC617,
                    0xC619, 0xC61A, 0xC61D, 0xC61F, 0xC620, 0xC621, 0xC622, 0xC628, 0xC62A, 0xC65A, 0xC65B, 0xC68D,
                    0xC6F7, 0xC761,
                ]) .union(ids(.exif, [0x9000, 0xA002, 0xA003]))
        case .heif:
            ids(.primary, [0x0112, 0x011A, 0x011B, 0x0128, 0x0142, 0x0143, 0x0213, 0x8769])
                .union(ids(.exif, [0x9000, 0x9101, 0xA000, 0xA001, 0xA002, 0xA003]))
        case .jpeg:
            ids(.primary, [0x0112, 0x011A, 0x011B, 0x0128, 0x0213, 0x8769])
                .union(ids(.exif, [0x9000, 0x9101, 0xA000, 0xA001, 0xA002, 0xA003]))
        }
    }

    /// The tags one switch adds, by format.
    static func item(_ item: MetadataItem, _ format: PhotoFormat) -> Set<ID> {
        switch item {
        case .location: ids(.primary, [0x8825])
        case .dateAndTime: ids(.primary, [0x0132]).union(ids(.exif, [0x9003, 0x9004]))
        case .subSecondTime: ids(.exif, [0x9290, 0x9291, 0x9292])
        case .timeZone: ids(.exif, [0x9010, 0x9011, 0x9012])
        case .cameraMakeAndModel: ids(.primary, [0x010F, 0x0110, 0x013C])
        case .lensMakeAndModel:
            ids(.exif, [0xA432, 0xA433, 0xA434]).union(format == .raw ? ids(.primary, [0xC630]) : [])
        case .exactCameraModel: []  // A DNG always has it (locked above); only its value changes.
        case .lensCorrections: format == .raw ? ids(.primary, [0xC740, 0xC741, 0xC74E]) : []
        case .exposureSettings:
            ids(
                .exif,
                [
                    0x829A, 0x829D, 0x8822, 0x8827, 0x8830, 0x9201, 0x9202, 0x9203, 0x9204, 0x9205, 0x9207, 0x9209,
                    0x920A, 0x9214, 0xA217, 0xA301, 0xA402, 0xA403, 0xA405, 0xA406,
                ])
        case .systemVersion, .appNameAndVersion: ids(.primary, [0x0131])
        case .makerNotes: ids(.exif, [0x927C])
        case .nameAndCopyright: ids(.primary, [0x013B, 0x8298])
        }
    }

    /// Every tag a file may carry for some settings.
    static func all(_ settings: MetadataSettings, _ format: PhotoFormat, signed: Bool) -> Set<ID> {
        var result = locked(format)
        for item in settings.enabledItems where item != .nameAndCopyright { result.formUnion(self.item(item, format)) }
        if settings.isOn(.nameAndCopyright) {
            if !settings.ownerName.isEmpty { result.insert(ID(.primary, 0x013B)) }
            if !settings.copyrightNotice.isEmpty { result.insert(ID(.primary, 0x8298)) }
        }
        if signed && format == .raw { result.insert(ID(.primary, 0xCD41)) }
        return result
    }

    /// Settings from a bit mask over `MetadataItem.allCases`.
    static func settings(mask: Int, name: String = "A. Person", copyright: String = "© A. Person") -> MetadataSettings {
        var settings = MetadataSettings()
        for (index, item) in MetadataItem.allCases.enumerated() where mask & (1 << index) != 0 {
            settings.set(item, isOn: true)
        }
        settings.ownerName = name
        settings.copyrightNotice = copyright
        return settings
    }
}

struct MetadataPlanTests {
    @Test func firstLaunchFilesCarryOnlyLockedTags() {
        let plan = MetadataPlan()
        for format in PhotoFormat.allCases {
            let allowlist = plan.allowlist(for: format, signed: false)
            #expect(allowlist.tags == ExpectedTags.locked(format), "\(format)")
            #expect(allowlist.wildcardDirectories.isEmpty)
            #expect(allowlist.xmpProperties.isEmpty)
        }
        #expect(
            plan.allowlist(for: .raw, signed: false).textRules[MetadataAllowlist.TagID(.primary, 0xC614)]
                == .exactly(MetadataPlan.genericUniqueCameraModel))
    }

    /// Every one of the 8,192 switch combinations, for every format, signed and not: the allowed
    /// tags are exactly the locked tags plus the tags of each switch that is on.
    @Test func everySwitchCombinationAllowsExactlyItsTags() {
        for mask in 0..<(1 << MetadataItem.allCases.count) {
            let settings = ExpectedTags.settings(mask: mask)
            let plan = MetadataPlan(settings: settings, appVersion: "0.2.0")
            for format in PhotoFormat.allCases {
                for signed in [false, true] {
                    let allowlist = plan.allowlist(for: format, signed: signed)
                    guard allowlist.tags == ExpectedTags.all(settings, format, signed: signed) else {
                        Issue.record("mask \(mask), \(format), signed \(signed): \(allowlist.tags.symmetricDifference(ExpectedTags.all(settings, format, signed: signed)))")
                        return
                    }
                    #expect(allowlist.wildcardDirectories == (settings.isOn(.location) ? [.gps] : []))
                    #expect(allowlist.allowsSubSecondDates == settings.isOn(.subSecondTime))
                    #expect(allowlist.allowsTimeZoneDates == settings.isOn(.timeZone))
                }
            }
        }
    }

    @Test func nameAndCopyrightAreWrittenOnlyWhenEntered() {
        var settings = MetadataSettings()
        settings.set(.nameAndCopyright, isOn: true)
        let empty = MetadataPlan(settings: settings).allowlist(for: .jpeg, signed: false)
        #expect(!empty.tags.contains(MetadataAllowlist.TagID(.primary, 0x013B)))
        #expect(!empty.tags.contains(MetadataAllowlist.TagID(.primary, 0x8298)))
        settings.ownerName = "A. Person"
        let named = MetadataPlan(settings: settings).allowlist(for: .jpeg, signed: false)
        #expect(named.tags.contains(MetadataAllowlist.TagID(.primary, 0x013B)))
        #expect(named.textRules[MetadataAllowlist.TagID(.primary, 0x013B)] == .exactly("A. Person"))
    }

    @Test(arguments: [
        (false, false, MetadataAllowlist.TextRule.any),
        (true, false, .exactly("Photivra Nope Camera 0.2.0")),
        (true, true, .prefix("Photivra Nope Camera 0.2.0")),
        (false, true, .any),
    ])
    func softwareRuleFollowsTheSwitches(app: Bool, system: Bool, rule: MetadataAllowlist.TextRule) {
        var settings = MetadataSettings()
        settings.set(.appNameAndVersion, isOn: app)
        settings.set(.systemVersion, isOn: system)
        let allowlist = MetadataPlan(settings: settings, appVersion: "0.2.0").allowlist(for: .heif, signed: false)
        #expect(allowlist.textRules[MetadataAllowlist.TagID(.primary, 0x0131)] == rule)
        #expect(allowlist.xmpTextRules[MetadataAllowlist.XMPName(MetadataPlan.xmpNamespace, "CreatorTool")] == rule)
    }

    @Test func blocksPerFormat() {
        let plan = MetadataPlan()
        #expect(plan.allowlist(for: .raw, signed: true).blocks.isEmpty)
        let jpeg = plan.allowlist(for: .jpeg, signed: false)
        #expect(jpeg.blocks.contains("jpeg:APP1:Exif") && !jpeg.blocks.contains("jpeg:APP1:XMP"))
        #expect(!jpeg.blocks.contains("jpeg:APP11"))
        #expect(plan.allowlist(for: .jpeg, signed: true).blocks.contains("jpeg:APP11"))
        #expect(jpeg.wildcardImageIODictionaries == ["{JFIF}"])
        let heif = plan.allowlist(for: .heif, signed: false)
        #expect(!heif.blocks.contains("heif:box:uuid") && !heif.blocks.contains("heif:reference:thmb"))
        #expect(!heif.blocks.contains("heif:item:mime:application/rdf+xml"))
        #expect(plan.allowlist(for: .heif, signed: true).blocks.contains("heif:box:uuid"))
        #expect(heif.requiredTags.isEmpty)
        #expect(plan.allowlist(for: .raw, signed: false).requiredTags.count == 5)
    }

    @Test func heifXMPIsAllowedOnlyForDatesAndSoftware() {
        var settings = MetadataSettings()
        settings.set(.dateAndTime, isOn: true)
        var heif = MetadataPlan(settings: settings).allowlist(for: .heif, signed: false)
        #expect(heif.blocks.contains("heif:item:mime:application/rdf+xml"))
        #expect(
            heif.xmpProperties == [
                MetadataAllowlist.XMPName(MetadataPlan.photoshopNamespace, "DateCreated"),
                MetadataAllowlist.XMPName(MetadataPlan.xmpNamespace, "CreateDate"),
                MetadataAllowlist.XMPName(MetadataPlan.xmpNamespace, "ModifyDate"),
            ])
        settings = MetadataSettings()
        settings.set(.systemVersion, isOn: true)
        heif = MetadataPlan(settings: settings).allowlist(for: .heif, signed: false)
        #expect(heif.xmpProperties == [MetadataAllowlist.XMPName(MetadataPlan.xmpNamespace, "CreatorTool")])
        #expect(MetadataPlan(settings: settings).allowlist(for: .jpeg, signed: false).xmpProperties.isEmpty)
    }

    @Test func gpsAndMakerNotesAreWildcardImageIODictionaries() {
        var settings = MetadataSettings()
        settings.set(.location, isOn: true)
        settings.set(.makerNotes, isOn: true)
        let allowlist = MetadataPlan(settings: settings).allowlist(for: .raw, signed: false)
        #expect(allowlist.wildcardImageIODictionaries == ["{GPS}", "{MakerApple}"])
        #expect(allowlist.allows(ImageIOKey("{GPS}", "Latitude")))
        #expect(allowlist.allows(MetadataAllowlist.TagID(.gps, 0x0002)))
        #expect(!MetadataPlan().allowlist(for: .raw, signed: false).allows(ImageIOKey("{GPS}", "Latitude")))
        #expect(!MetadataPlan().allowlist(for: .raw, signed: false).allows(ImageIOKey(nil, "Unknown")))
        #expect(MetadataPlan().allowlist(for: .raw, signed: false).allows(ImageIOKey(nil, "PixelWidth")))
    }

    @Test func catalogKeysAreUniqueAndDescribed() {
        let ids = MetadataField.catalog.map { MetadataAllowlist.TagID($0.directory, $0.tag) }
        #expect(Set(ids).count == ids.count)
        #expect(ImageIOKey("{Exif}", "FNumber").description == "{Exif}.FNumber")
        #expect(ImageIOKey(nil, "Orientation").description == "Orientation")
        #expect(MetadataAllowlist.TagID(.exif, 0x829A).description == "exif 0x829A")
        #expect(LockedMetadata.allCases.count == 7)
        #expect(MetadataField.software.name == "Software")
    }
}

/// The ImageIO dictionary each file is written with.
struct MetadataPropertiesTests {
    /// The system's metadata for a RAW, shaped like `AVCapturePhoto.metadata` on the tag check
    /// device (docs/PRIVACY.md), plus a key no catalog lists, standing in for a future tag.
    nonisolated(unsafe) static let systemMetadata: [String: Any] = [
        "Orientation": 6,
        "{TIFF}": [
            "Make": "Apple", "Model": "iPhone", "Software": "27.2.1", "DateTime": "2026:11:12 00:11:51",
            "Orientation": 6, "HostComputer": "iPhone",
        ] as [String: Any],
        "{Exif}": [
            "ExposureTime": 0.0166, "FNumber": 1.78, "ISOSpeedRatings": [250], "DateTimeOriginal": "2026:11:12 00:11:51",
            "SubsecTimeOriginal": "473", "OffsetTime": "-05:00", "LensModel": "back camera", "FutureTag": "x",
            "ExifVersion": [2, 3, 2],
        ] as [String: Any],
        "{DNG}": [
            "UniqueCameraModel": "iPhone17,2 back camera", "DNGVersion": [1, 3], "BlackLevel": [528],
            "DNGOpcodeList3": Data([1, 2]),
        ] as [String: Any],
        "{MakerApple}": ["3": 12345] as [String: Any],
        "{GPS}": ["Latitude": 1.0] as [String: Any],
        "{FutureDictionary}": ["Key": 1] as [String: Any],
    ]

    static func keys(_ properties: [String: Any]) -> Set<String> {
        var keys: Set<String> = []
        for (name, value) in properties {
            if let dictionary = value as? [String: Any] {
                keys.formUnion(dictionary.keys.map { "\(name).\($0)" })
            } else {
                keys.insert(name)
            }
        }
        return keys
    }

    @Test func firstLaunchCopiesOnlyLockedValuesAndTheGenericModel() {
        let properties = MetadataPlan().properties(for: .raw, from: Self.systemMetadata)
        #expect(
            Self.keys(properties) == [
                "Orientation", "{TIFF}.Orientation", "{Exif}.ExifVersion", "{DNG}.DNGVersion", "{DNG}.BlackLevel",
                "{DNG}.UniqueCameraModel",
            ])
        #expect((properties["{DNG}"] as? [String: Any])?["UniqueCameraModel"] as? String == "Generic camera")
    }

    @Test func everyCustomItemCopiesItsValues() {
        var settings = MetadataSettings()
        for item in MetadataItem.allCases { settings.set(item, isOn: true) }
        settings.ownerName = "A. Person"
        settings.copyrightNotice = "© A. Person"
        let properties = MetadataPlan(settings: settings, appVersion: "0.2.0").properties(
            for: .raw, from: Self.systemMetadata)
        let keys = Self.keys(properties)
        #expect(!keys.contains("{Exif}.FutureTag"))
        #expect(!keys.contains("{FutureDictionary}.Key"))
        #expect(keys.isSuperset(of: ["{GPS}.Latitude", "{MakerApple}.3", "{DNG}.DNGOpcodeList3", "{TIFF}.HostComputer"]))
        let tiff = properties["{TIFF}"] as? [String: Any]
        #expect(tiff?["Software"] as? String == "Photivra Nope Camera 0.2.0 (27.2.1)")
        #expect(tiff?["Artist"] as? String == "A. Person")
        #expect(tiff?["Copyright"] as? String == "© A. Person")
        #expect((properties["{DNG}"] as? [String: Any])?["UniqueCameraModel"] as? String == "iPhone17,2 back camera")
    }

    @Test func developedFilesTakeAnUprightOrientationAndNoDNGTags() {
        let properties = MetadataPlan().properties(for: .heif, from: Self.systemMetadata, orientation: 1)
        #expect(properties["Orientation"] as? Int == 1)
        #expect((properties["{TIFF}"] as? [String: Any])?["Orientation"] as? Int == 1)
        #expect(properties["{DNG}"] == nil)
    }

    @Test func exactModelWithoutASourceValueWritesNone() {
        var settings = MetadataSettings()
        settings.set(.exactCameraModel, isOn: true)
        let properties = MetadataPlan(settings: settings).properties(for: .raw, from: [:])
        #expect(properties.isEmpty)
    }

    @Test(arguments: [
        (true, false, "27.2.1" as String?, "Photivra Nope Camera" as String?),
        (true, true, nil, "Photivra Nope Camera"),
        (false, true, "27.2.1", "27.2.1"),
        (false, false, "27.2.1", nil),
    ])
    func softwareValue(app: Bool, system: Bool, source: String?, expected: String?) {
        var settings = MetadataSettings()
        settings.set(.appNameAndVersion, isOn: app)
        settings.set(.systemVersion, isOn: system)
        var metadata: [String: Any] = [:]
        if let source { metadata["{TIFF}"] = ["Software": source] }
        let properties = MetadataPlan(settings: settings).properties(for: .jpeg, from: metadata)
        #expect((properties["{TIFF}"] as? [String: Any])?["Software"] as? String == expected)
    }
}
