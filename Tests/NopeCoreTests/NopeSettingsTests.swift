import Foundation
import Testing

@testable import NopeCore

/// A fresh, empty `UserDefaults` suite for one test, removed when the test ends.
final class ScratchDefaults {
    /// The suite's name.
    let name = "NopeSettingsTests.\(UUID().uuidString)"

    /// The store.
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

struct MetadataPresentationTests {
    @Test func locationAndNameAreNotOfferedYet() {
        #expect(!MetadataItem.location.isOfferedInSettings)
        #expect(!MetadataItem.nameAndCopyright.isOfferedInSettings)
        #expect(MetadataItem.offeredInSettings.count == MetadataItem.allCases.count - 2)
        #expect(MetadataItem.offeredInSettings.first == .dateAndTime)
    }

    @Test func lockedItemsMatchThePrivacyPlan() {
        #expect(LockedMetadataItem.allCases.count == 7)
    }
}

@MainActor
struct NopeSettingsTests {
    @Test func firstLaunchDefaults() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.formats == [.raw, .heif])
        #expect(settings.orderedFormats == [.raw, .heif])
        #expect(settings.metadata == MetadataSettings())
        #expect(settings.save == SaveSettings())
        #expect(settings.signsPhotos)
        #expect(!settings.showsManualControls)
        #expect(!settings.startsInCleanView)
        #expect(settings.developedLook == .standard)
    }

    @Test func everyChangeIsSavedAndReloaded() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.setFormat(.jpeg, isSelected: true))
        #expect(settings.setFormat(.heif, isSelected: false))
        settings.setMetadataItem(.timeZone, isIncluded: true)
        settings.setSignsPhotos(false)
        settings.setShowsManualControls(true)
        settings.setStartsInCleanView(true)
        settings.setDevelopedLook(.flat)

        let reloaded = NopeSettings(defaults: scratch.defaults)
        #expect(reloaded.orderedFormats == [.raw, .jpeg])
        #expect(reloaded.metadata.isCustom)
        #expect(reloaded.metadata.enabledItems == [.timeZone])
        #expect(!reloaded.signsPhotos)
        #expect(reloaded.showsManualControls)
        #expect(reloaded.developedLook == .flat)
        #expect(reloaded.startsInCleanView)

        reloaded.setRemovesAllOptionalDetails(true)
        let master = NopeSettings(defaults: scratch.defaults).metadata
        #expect(master.removesAllOptionalDetails)
        #expect(master.enabledItems.isEmpty)
    }

    @Test func theLastFormatCantBeTurnedOff() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.canTurnOff(.raw, deviceSupportsBayerRAW: true))
        settings.setFormat(.heif, isSelected: false)
        #expect(!settings.canTurnOff(.raw, deviceSupportsBayerRAW: true))
        #expect(!settings.setFormat(.raw, isSelected: false))
        #expect(settings.formats == [.raw])
    }

    @Test func rawIsUnavailableWithoutBayerRAW() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(!NopeSettings.isAvailable(.raw, deviceSupportsBayerRAW: false))
        #expect(NopeSettings.isAvailable(.raw, deviceSupportsBayerRAW: true))
        #expect(NopeSettings.isAvailable(.heif, deviceSupportsBayerRAW: false))
        #expect(settings.selectedFormats(deviceSupportsBayerRAW: false) == [.heif])
        #expect(settings.selectedFormats(deviceSupportsBayerRAW: true) == [.raw, .heif])
        // HEIF is the only format this device can save, so it stays on.
        #expect(!settings.canTurnOff(.heif, deviceSupportsBayerRAW: false))
        #expect(settings.canTurnOff(.heif, deviceSupportsBayerRAW: true))
    }

    @Test func unreadableValuesFallBackToDefaults() {
        let scratch = ScratchDefaults()
        scratch.defaults.set(Data(#"{"formats":["tiff"]}"#.utf8), forKey: NopeSettings.Key.save)
        scratch.defaults.set("maybe", forKey: NopeSettings.Key.showsManualControls)
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.save == SaveSettings())
        #expect(!settings.showsManualControls)
        #expect(settings.developedLook == .standard)
    }

    @Test func theOldManualControlsOptionIsMigratedOnce() {
        let scratch = ScratchDefaults()
        scratch.defaults.set(true, forKey: NopeSettings.Key.legacyManualControls)
        #expect(NopeSettings(defaults: scratch.defaults).showsManualControls)
        #expect(scratch.defaults.object(forKey: NopeSettings.Key.legacyManualControls) == nil)
        #expect(NopeSettings(defaults: scratch.defaults).showsManualControls)

        // A value the model already stored wins over the old key.
        scratch.defaults.set(false, forKey: NopeSettings.Key.legacyManualControls)
        #expect(NopeSettings(defaults: scratch.defaults).showsManualControls)
        #expect(scratch.defaults.object(forKey: NopeSettings.Key.legacyManualControls) == nil)
    }

    @Test func launchArgumentStringsReadAsBooleans() {
        let scratch = ScratchDefaults()
        scratch.defaults.set("YES", forKey: NopeSettings.Key.showsManualControls)
        #expect(NopeSettings(defaults: scratch.defaults).showsManualControls)
    }

    @Test func developedFormatsAreReported() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.savesDevelopedFormat)
        settings.setFormat(.heif, isSelected: false)
        #expect(!settings.savesDevelopedFormat)
    }
}
