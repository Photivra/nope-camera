import Foundation
import NopeCore
import Testing

struct MetadataSettingsTests {
    @Test func firstLaunchRemovesEverythingAndSigns() {
        let settings = MetadataSettings()
        #expect(settings.removesAllOptionalDetails)
        #expect(!settings.isCustom)
        #expect(settings.enabledItems.isEmpty)
        #expect(settings.signsPhotos)
        #expect(settings.ownerName.isEmpty)
        #expect(settings.copyrightNotice.isEmpty)
        for item in MetadataItem.allCases { #expect(!settings.isOn(item)) }
    }

    @Test func defaultsWhenCustomizingMatchThePrivacyTable() {
        let on = Set(MetadataItem.allCases.filter(\.isOnWhenCustomizing))
        #expect(
            on == [
                .dateAndTime, .cameraMakeAndModel, .lensMakeAndModel, .exactCameraModel, .lensCorrections,
                .exposureSettings, .appNameAndVersion,
            ])
    }

    @Test func turningTheMasterOffSetsTheDefaults() {
        var settings = MetadataSettings()
        settings.setRemovesAllOptionalDetails(false)
        #expect(settings.isCustom)
        #expect(settings.enabledItems == Set(MetadataItem.allCases.filter(\.isOnWhenCustomizing)))
    }

    @Test func turningAnItemOnTurnsTheMasterOffAndOnlyThatItemOn() {
        var settings = MetadataSettings()
        settings.set(.location, isOn: true)
        #expect(settings.isCustom)
        #expect(!settings.removesAllOptionalDetails)
        #expect(settings.enabledItems == [.location])
    }

    @Test func turningTheMasterBackOnTurnsEveryItemOff() {
        var settings = MetadataSettings()
        settings.setRemovesAllOptionalDetails(false)
        settings.set(.makerNotes, isOn: true)
        settings.setRemovesAllOptionalDetails(true)
        #expect(settings.enabledItems.isEmpty)
        #expect(!settings.isCustom)
    }

    @Test func turningAnItemOffKeepsCustom() {
        var settings = MetadataSettings()
        settings.set(.timeZone, isOn: true)
        settings.set(.timeZone, isOn: false)
        #expect(settings.isCustom)
        #expect(settings.enabledItems.isEmpty)
    }

    @Test func signingIsOutsideTheMasterSwitch() {
        var settings = MetadataSettings()
        settings.signsPhotos = false
        settings.setRemovesAllOptionalDetails(false)
        settings.setRemovesAllOptionalDetails(true)
        #expect(!settings.signsPhotos)
    }

    @Test func settingsRoundTripThroughCodable() throws {
        var settings = SaveSettings()
        settings.metadata.set(.location, isOn: true)
        settings.metadata.ownerName = "A. Person"
        settings.setFormat(.jpeg, isSelected: true)
        settings.developedLook = .flat
        let decoded = try JSONDecoder().decode(SaveSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(PhotoFormat(rawValue: "raw") == .raw)
    }

    @Test func formatsDefaultToRAWPlusHEIFAndNeverBecomeEmpty() {
        var settings = SaveSettings()
        #expect(settings.formats == [.raw, .heif])
        #expect(settings.metadata == MetadataSettings())
        #expect(settings.developedLook == .standard)
        #expect(DevelopedLook(rawValue: "flat") == .flat)
        var results: [Bool] = []
        results.append(settings.setFormat(.jpeg, isSelected: true))
        #expect(settings.formats == [.raw, .heif, .jpeg])
        results.append(settings.setFormat(.raw, isSelected: false))
        results.append(settings.setFormat(.heif, isSelected: false))
        #expect(settings.formats == [.jpeg])
        results.append(settings.setFormat(.jpeg, isSelected: false))
        #expect(settings.formats == [.jpeg])
        results.append(settings.setFormat(.raw, isSelected: false))
        #expect(settings.formats == [.jpeg])
        #expect(results == [true, true, true, false, true])
    }
}
