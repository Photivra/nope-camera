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
    @Test func locationIsOfferedAndNameIsNotYet() {
        #expect(MetadataItem.location.isOfferedInSettings)
        #expect(!MetadataItem.nameAndCopyright.isOfferedInSettings)
        #expect(MetadataItem.offeredInSettings.count == MetadataItem.allCases.count - 1)
        #expect(MetadataItem.offeredInSettings.first == .location)
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
        // Issue #80: RAW only, signing off, Face Detection off, the Processed marker on.
        #expect(settings.formats == [.raw])
        #expect(settings.orderedFormats == [.raw])
        #expect(settings.metadata == MetadataSettings())
        #expect(settings.save == SaveSettings())
        #expect(!settings.signsPhotos)
        #expect(!settings.followsFaces)
        #expect(settings.showsProcessedMarker)
        #expect(!settings.savesDevelopedFormat)
        #expect(!settings.showsManualControls)
        #expect(!settings.startsInCleanView)
        #expect(settings.developedLook == .standard)
        #expect(!settings.showsLiveActivity)
    }

    @Test func everyChangeIsSavedAndReloaded() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.setFormat(.jpeg, isSelected: true))
        #expect(settings.setFormat(.heif, isSelected: false))
        settings.setMetadataItem(.timeZone, isIncluded: true)
        settings.setSignsPhotos(true)
        settings.setShowsProcessedMarker(false)
        settings.setShowsManualControls(true)
        settings.setStartsInCleanView(true)
        settings.setDevelopedLook(.flat)
        settings.setShowsLiveActivity(true)

        let reloaded = NopeSettings(defaults: scratch.defaults)
        #expect(reloaded.orderedFormats == [.raw, .jpeg])
        #expect(reloaded.metadata.isCustom)
        #expect(reloaded.metadata.enabledItems == [.timeZone])
        #expect(reloaded.signsPhotos)
        #expect(!reloaded.showsProcessedMarker)
        #expect(reloaded.showsManualControls)
        #expect(reloaded.developedLook == .flat)
        #expect(reloaded.startsInCleanView)
        #expect(reloaded.showsLiveActivity)

        reloaded.setRemovesAllOptionalDetails(true)
        let master = NopeSettings(defaults: scratch.defaults).metadata
        #expect(master.removesAllOptionalDetails)
        #expect(master.enabledItems.isEmpty)
    }

    @Test func theLastFormatCantBeTurnedOff() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(!settings.canTurnOff(.raw, deviceSupportsBayerRAW: true))
        settings.setFormat(.heif, isSelected: true)
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
        // RAW only (the default) leaves nothing a device without RAW can save: HEIF stands in.
        #expect(settings.selectedFormats(deviceSupportsBayerRAW: false) == [.heif])
        #expect(settings.selectedFormats(deviceSupportsBayerRAW: true) == [.raw])
        #expect(!settings.canTurnOff(.heif, deviceSupportsBayerRAW: false))
        settings.setFormat(.jpeg, isSelected: true)
        #expect(settings.selectedFormats(deviceSupportsBayerRAW: false) == [.jpeg])
        settings.setFormat(.heif, isSelected: true)
        #expect(settings.selectedFormats(deviceSupportsBayerRAW: false) == [.heif, .jpeg])
        #expect(settings.selectedFormats(deviceSupportsBayerRAW: true) == [.raw, .heif, .jpeg])
        settings.setFormat(.jpeg, isSelected: false)
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

    @MainActor
    @Test func theFastShutterChoiceIsSavedAndAnUnknownOneIsStandard() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.fastShutter == .handheld)
        settings.setFastShutter(.freezeFastMotion)
        #expect(NopeSettings(defaults: scratch.defaults).fastShutter == .freezeFastMotion)
        scratch.defaults.set("warp", forKey: NopeSettings.Key.fastShutter)
        #expect(NopeSettings(defaults: scratch.defaults).fastShutter == .handheld)
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
        #expect(!settings.savesDevelopedFormat)
        settings.setFormat(.heif, isSelected: true)
        #expect(settings.savesDevelopedFormat)
        settings.setFormat(.heif, isSelected: false)
        #expect(!settings.savesDevelopedFormat)
    }

    @Test func settingsSavedBeforeTheNewDefaultsAreKept() {
        // Stored by 0.x before issue #80: RAW plus HEIF, signing on and Face Detection on.
        let scratch = ScratchDefaults()
        let old = #"{"formats":["raw","heif"],"metadata":{"removesAllOptionalDetails":true,"enabledItems":[],"signsPhotos":true,"ownerName":"","copyrightNotice":""},"developedLook":"standard"}"#
        scratch.defaults.set(Data(old.utf8), forKey: NopeSettings.Key.save)
        scratch.defaults.set(true, forKey: NopeSettings.Key.followsFaces)
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.formats == [.raw, .heif])
        #expect(settings.signsPhotos)
        #expect(settings.followsFaces)
        #expect(settings.showsProcessedMarker)
        // A stored "off" is kept too.
        scratch.defaults.set(false, forKey: NopeSettings.Key.followsFaces)
        #expect(!NopeSettings(defaults: scratch.defaults).followsFaces)
    }

    // MARK: - Burst Limit (issue #121)

    @Test func theBurstLimitChoicesAreTheDesigns() {
        #expect(BurstLimit.allCases == [.off, .three, .five, .ten, .twenty, .fifty])
        #expect(BurstLimit.allCases.map(\.rawValue) == ["off", "three", "five", "ten", "twenty", "fifty"])
        #expect(BurstLimit.allCases.map(\.frameCount) == [nil, 3, 5, 10, 20, 50])
        #expect(BurstLimit.standard == .off, "Off by default, so a burst works as before")
        // The count never goes above the cap of a burst.
        for limit in BurstLimit.allCases {
            #expect((limit.frameCount ?? 0) <= DriveModel.maximumBurstFrames, "\(limit)")
        }
    }

    @Test func theBurstLimitIsOffByDefaultAndStoredByName() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.burstLimit == .off)
        for limit in BurstLimit.allCases {
            settings.setBurstLimit(limit)
            #expect(settings.burstLimit == limit)
            #expect(scratch.defaults.string(forKey: NopeSettings.Key.burstLimit) == limit.rawValue)
            #expect(NopeSettings(defaults: scratch.defaults).burstLimit == limit)
        }
        // Another process's change is picked up by reload.
        scratch.defaults.set("five", forKey: NopeSettings.Key.burstLimit)
        #expect(settings.reload())
        #expect(settings.burstLimit == .five)
        // An unknown stored value, as from a later version, reads as Off.
        scratch.defaults.set("hundred", forKey: NopeSettings.Key.burstLimit)
        #expect(NopeSettings(defaults: scratch.defaults).burstLimit == .off)
        scratch.defaults.set(10, forKey: NopeSettings.Key.burstLimit)
        #expect(NopeSettings(defaults: scratch.defaults).burstLimit == .off)
    }

    @Test func theBurstLimitIsInPresetsAndTheLockScreenSnapshot() async throws {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        settings.setBurstLimit(.twenty)
        // The Lock Screen camera gets it with the other settings (it applies there too).
        let lockScreen = NopeSettings(defaults: ScratchDefaults().defaults)
        #expect(lockScreen.apply(try settings.makeSnapshot()))
        #expect(lockScreen.burstLimit == .twenty)
        // A preset keeps it; Factory Defaults turns it off.
        let presets = SettingsPresets(settings: settings)
        let preset = try presets.saveCurrent(named: "Sports", camera: nil)
        _ = await presets.apply(.factoryDefaults, camera: nil, location: nil)
        #expect(settings.burstLimit == .off)
        _ = await presets.apply(.saved(preset.id), camera: nil, location: nil)
        #expect(settings.burstLimit == .twenty)
    }

    @Test func theProcessedMarkerSwitchIsSavedAndReloaded() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(settings.showsProcessedMarker)
        settings.setShowsProcessedMarker(false)
        #expect(!settings.showsProcessedMarker)
        #expect(!NopeSettings(defaults: scratch.defaults).showsProcessedMarker)
        // Another process's change is picked up by reload.
        let other = NopeSettings(defaults: scratch.defaults)
        settings.setShowsProcessedMarker(true)
        #expect(other.reload())
        #expect(other.showsProcessedMarker)
        // A launch argument string reads as a Boolean.
        scratch.defaults.set("NO", forKey: NopeSettings.Key.showsProcessedMarker)
        #expect(!NopeSettings(defaults: scratch.defaults).showsProcessedMarker)
    }
}
