import Foundation
import Testing

@testable import NopeCore

/// The Standard File Tags option (owner decision 2026-11-16): the Exif standard's required,
/// non-identifying tags, on by default and outside the master switch; off is the minimal set.
struct StandardFileTagsTests {
    static func settings(standardTags: Bool, _ items: [MetadataItem] = []) -> MetadataSettings {
        var settings = MetadataSettings()
        for item in items { settings.set(item, isOn: true) }
        settings.writesStandardFileTags = standardTags
        return settings
    }

    static func exif(_ properties: [String: Any]) -> [String: Any] {
        properties["{Exif}"] as? [String: Any] ?? [:]
    }

    @Test func onByDefaultOutsideTheMasterSwitchAndStoredOnlyWhenOff() throws {
        var settings = MetadataSettings()
        #expect(settings.writesStandardFileTags)
        settings.setRemovesAllOptionalDetails(false)
        settings.setRemovesAllOptionalDetails(true)
        #expect(settings.writesStandardFileTags)
        settings.writesStandardFileTags = false
        settings.setRemovesAllOptionalDetails(true)
        #expect(!settings.writesStandardFileTags)
        let decoded = try JSONDecoder().decode(MetadataSettings.self, from: JSONEncoder().encode(settings))
        #expect(!decoded.writesStandardFileTags)
        settings.writesStandardFileTags = true
        #expect(settings == MetadataSettings())
        let old = #"{"removesAllOptionalDetails":true,"enabledItems":[],"signsPhotos":true,"ownerName":"","copyrightNotice":""}"#
        #expect(try JSONDecoder().decode(MetadataSettings.self, from: Data(old.utf8)).writesStandardFileTags)
    }

    @Test(arguments: [PhotoFormat.heif, .jpeg])
    func developedCopiesGetTheFixedExifValuesOnlyWhenOn(format: PhotoFormat) {
        let on = MetadataPlan(settings: Self.settings(standardTags: true)).properties(for: format, from: [:], orientation: 1)
        #expect(Self.exif(on)["ExifVersion"] as? [Int] == [2, 3, 2])
        #expect(Self.exif(on)["ComponentsConfiguration"] as? [Int] == [1, 2, 3, 0])
        #expect(Self.exif(on)["FlashPixVersion"] as? [Int] == [1, 0])
        #expect(Self.exif(on)["ColorSpace"] as? Int == 0xFFFF)
        #expect(on["{GPS}"] == nil)
        let off = MetadataPlan(settings: Self.settings(standardTags: false)).properties(for: format, from: [:], orientation: 1)
        #expect(off["{Exif}"] == nil)
        // A value the source already has is kept.
        let source: [String: Any] = ["{Exif}": ["ColorSpace": 1, "ComponentsConfiguration": [4, 5, 6, 0]]]
        let kept = MetadataPlan(settings: Self.settings(standardTags: true)).properties(for: format, from: source)
        #expect(Self.exif(kept)["ColorSpace"] as? Int == 1)
        #expect(Self.exif(kept)["ComponentsConfiguration"] as? [Int] == [4, 5, 6, 0])
    }

    @Test(arguments: PhotoFormat.allCases)
    func aLocationGetsItsGPSVersionOnlyWhenOn(format: PhotoFormat) {
        for standardTags in [true, false] {
            var plan = MetadataPlan(settings: Self.settings(standardTags: standardTags, [.location]))
            plan.location = PhotoLocation(latitude: 1, longitude: 2, altitude: nil)
            let gps = plan.properties(for: format, from: [:])["{GPS}"] as? [String: Any]
            #expect((gps?["GPSVersion"] as? [Int]) == (standardTags ? [2, 3, 0, 0] : nil), "\(format) \(standardTags)")
            #expect(plan.allowlist(for: format, signed: false).allows(ImageIOKey("{GPS}", "GPSVersion")))
        }
        let existing: [String: Any] = ["{GPS}": ["GPSVersion": [2, 2, 0, 0], "Latitude": 1.0]]
        let plan = MetadataPlan(settings: Self.settings(standardTags: true, [.location]))
        #expect((plan.properties(for: format, from: existing)["{GPS}"] as? [String: Any])?["GPSVersion"] as? [Int] == [2, 2, 0, 0])
    }

    @Test func aDNGWithoutTheDateCarriesTheStandardUnknownDateOnlyWhenOn() {
        let dateTime = MetadataAllowlist.TagID(.primary, 0x0132)
        for standardTags in [true, false] {
            let plan = MetadataPlan(settings: Self.settings(standardTags: standardTags))
            let tiff = plan.properties(for: .raw, from: [:])["{TIFF}"] as? [String: Any]
            let expected = standardTags ? MetadataPlan.unknownDateTime : ""
            #expect(tiff?["DateTime"] as? String == expected)
            // Issue #65: the four keys are always there.
            #expect(Set((tiff ?? [:]).keys).isSuperset(of: ["DateTime", "Make", "Model", "Software"]))
            #expect(
                plan.allowlist(for: .raw, signed: false).textRules[dateTime]
                    == (standardTags ? .blankDate : .exactly("")))
        }
        // The unknown form has no digits: it says nothing about when the photo was taken.
        #expect(MetadataPlan.unknownDateTime.count == 19)
        #expect(MetadataPlan.unknownDateTime.allSatisfy { $0 == " " || $0 == ":" })
        // With the date on, the system's date is written either way.
        let withDate = Self.settings(standardTags: true, [.dateAndTime])
        let source: [String: Any] = ["{TIFF}": ["DateTime": "2026:11:16 10:00:00"]]
        let tiff = MetadataPlan(settings: withDate).properties(for: .raw, from: source)["{TIFF}"] as? [String: Any]
        #expect(tiff?["DateTime"] as? String == "2026:11:16 10:00:00")
        // A DNG gets no HEIF or JPEG structure tags.
        #expect(Self.exif(MetadataPlan().properties(for: .raw, from: [:]))["ComponentsConfiguration"] == nil)
    }

    @MainActor
    @Test func theSettingIsStored() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.metadata.writesStandardFileTags)
        settings.setWritesStandardFileTags(false)
        #expect(!NopeSettings(defaults: scratch.defaults).metadata.writesStandardFileTags)
        settings.setRemovesAllOptionalDetails(true)
        #expect(!NopeSettings(defaults: scratch.defaults).metadata.writesStandardFileTags)
    }
}
