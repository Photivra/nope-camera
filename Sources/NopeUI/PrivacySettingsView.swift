import NopeCore
import SwiftUI

/// The metadata switches, the signing switch and the locked items, as in `docs/PRIVACY.md`,
/// "Metadata plan".
///
/// The master switch comes first, then one switch per optional item with what turning it off
/// costs, then signing (outside the master switch), then the items every file keeps, each
/// marked locked with the reason. All wording is a privacy claim, so it lives in
/// `Honesty.xcstrings` (AGENTS.md, "Honesty wording is kept apart"). The rules are in
/// `MetadataSettings`; this view only shows them.
struct PrivacySettingsView: View {
    /// The settings to show and change.
    let settings: NopeSettings

    /// Creates the privacy settings.
    ///
    /// - Parameter settings: The settings to show and change.
    init(settings: NopeSettings) {
        self.settings = settings
    }

    /// The form.
    var body: some View {
        Form {
            masterSection
            itemsSection
            signingSection
            lockedSection
        }
        .navigationTitle(Text("Privacy", bundle: .module, comment: "Settings row and screen title: which details are saved in each photo, and signing."))
    }

    /// "Remove all optional details".
    private var masterSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { settings.metadata.removesAllOptionalDetails },
                    set: { settings.setRemovesAllOptionalDetails($0) })
            ) {
                Text("Remove All Optional Details", tableName: "Honesty", bundle: .module, comment: "Master switch: when on, photos keep only the details they need to open.")
            }
        } footer: {
            Text(
                "On: each photo keeps only what it needs to open. Off: choose each item below.", tableName: "Honesty", bundle: .module,
                comment: "Explains the master switch. Must not claim more than the English.")
        }
    }

    /// One switch per optional item, each with what turning it off costs.
    private var itemsSection: some View {
        Section {
            ForEach(MetadataItem.offeredInSettings, id: \.self) { item in
                Toggle(
                    isOn: Binding(
                        get: { settings.metadata.isOn(item) },
                        set: { settings.setMetadataItem(item, isIncluded: $0) })
                ) {
                    SettingLabel(title: Text(Self.title(of: item)), explanation: Text(Self.explanation(of: item)))
                }
            }
        } header: {
            Text("In Each Photo", tableName: "Honesty", bundle: .module, comment: "Section header above the switches for optional details saved in each photo.")
        }
    }

    /// The Content Credentials signature, outside the master switch.
    private var signingSection: some View {
        Section {
            Toggle(isOn: Binding(get: { settings.signsPhotos }, set: { settings.setSignsPhotos($0) })) {
                SettingLabel(
                    title: Text("Sign Each Photo", tableName: "Honesty", bundle: .module, comment: "Switch that adds a Content Credentials signature to each photo."),
                    explanation: Text(
                        "Lets anyone check that the photo hasn't changed since nope. saved it. If off, the photo can't be checked for changes.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Explains the signing switch. Keep \"nope.\" unchanged. Must not claim more than the English: the signature shows changes, it doesn't prove who took the photo."))
            }
        } header: {
            Text("Content Credentials", tableName: "Honesty", bundle: .module, comment: "Section header for the photo signature. Content Credentials is the name of the C2PA signature standard's label.")
        }
    }

    /// The items every file keeps, each locked with its reason.
    private var lockedSection: some View {
        Section {
            ForEach(LockedMetadataItem.allCases, id: \.self) { item in
                HStack {
                    SettingLabel(title: Text(Self.title(of: item)), explanation: Text(Self.explanation(of: item)))
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text("Locked", tableName: "Honesty", bundle: .module, comment: "VoiceOver: this detail is always saved and can't be turned off."))
            }
        } header: {
            Text("Always Saved", tableName: "Honesty", bundle: .module, comment: "Section header above the details every photo keeps.")
        } footer: {
            Text(
                "A photo can't be opened or shown correctly without these. None of them identify you or link your photos.",
                tableName: "Honesty", bundle: .module, comment: "Explains why the locked details are always saved. Must not claim more than the English.")
        }
    }

    /// The settings row's value: "All Removed" or "Custom".
    ///
    /// - Parameter metadata: The metadata settings.
    /// - Returns: The summary text.
    static func summary(of metadata: MetadataSettings) -> Text {
        if metadata.removesAllOptionalDetails {
            Text("All Optional Removed", tableName: "Honesty", bundle: .module, comment: "Settings row value: the master switch is on and no optional details are saved.")
        } else {
            Text("Custom", tableName: "Honesty", bundle: .module, comment: "Settings row value: the person chose the optional details one by one.")
        }
    }

    /// An optional item's name.
    ///
    /// - Parameter item: The item.
    /// - Returns: A localized title from `Honesty.xcstrings`.
    static func title(of item: MetadataItem) -> LocalizedStringResource {
        switch item {
        case .location: LocalizedStringResource("Location", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item: where the photo was taken.")
        case .dateAndTime: LocalizedStringResource("Date and Time Taken", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item.")
        case .subSecondTime: LocalizedStringResource("Sub-Second Time", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item: fractions of a second in the time taken.")
        case .timeZone: LocalizedStringResource("Time Zone", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item.")
        case .cameraMakeAndModel: LocalizedStringResource("Camera Make and Model", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item: which device took the photo.")
        case .lensMakeAndModel: LocalizedStringResource("Lens Make and Model", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item: which lens took the photo.")
        case .exactCameraModel: LocalizedStringResource("Exact Model for RAW Editors", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item: the exact device model, used by RAW editing apps to pick a color profile. RAW is a file format name.")
        case .lensCorrections: LocalizedStringResource("Lens Correction Instructions", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item: instructions editors can use to correct lens distortion.")
        case .exposureSettings: LocalizedStringResource("Exposure Settings", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item: shutter speed, ISO, aperture and focal length.")
        case .systemVersion: LocalizedStringResource("iOS Version", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item: the operating system version. iOS is a product name; keep it unchanged.")
        case .makerNotes: LocalizedStringResource("Maker Notes", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item: the camera maker's private notes in the file.")
        case .nameAndCopyright: LocalizedStringResource("Your Name and Copyright", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item.")
        case .appNameAndVersion: LocalizedStringResource("App Name and Version", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Metadata item: records that nope. made the file.")
        }
    }

    /// What an optional item is for, and what turning it off costs (`docs/PRIVACY.md`).
    ///
    /// - Parameter item: The item.
    /// - Returns: A localized explanation from `Honesty.xcstrings`.
    static func explanation(of item: MetadataItem) -> LocalizedStringResource {
        switch item {
        case .location: LocalizedStringResource("Off: nothing is lost. Location is only added if you turn it on.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What turning off location costs.")
        case .dateAndTime: LocalizedStringResource("Off: Photos sorts it by the date it was saved instead.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What turning off the date costs. Photos is the system photo library app.")
        case .subSecondTime: LocalizedStringResource("Off: nothing visible changes.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What turning off a metadata item costs: nothing the person can see.")
        case .timeZone: LocalizedStringResource("Off: the photo's local time can't be converted to other time zones.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What turning off the time zone costs.")
        case .cameraMakeAndModel: LocalizedStringResource("Off: apps can't show which device took it.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What turning off the camera model costs.")
        case .lensMakeAndModel: LocalizedStringResource("Off: apps can't show which lens took it.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What turning off the lens model costs.")
        case .exactCameraModel: LocalizedStringResource("Off: some RAW editors can't choose their color profile for this camera and use the file's own color data instead. The DNG standard requires this item, so nope. writes a generic value instead.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What turning off the exact model costs. RAW and DNG are file format names. Keep \"nope.\" unchanged.")
        case .lensCorrections: LocalizedStringResource("Off: editors can't automatically correct this lens's distortion and vignetting. The pixels are never corrected either way.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What turning off lens correction instructions costs.")
        case .exposureSettings: LocalizedStringResource("Shutter speed, ISO, aperture and focal length. Off: you can't see later how the photo was taken.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What the exposure settings are, and what turning them off costs.")
        case .systemVersion: LocalizedStringResource("Off: nothing visible changes.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What turning off a metadata item costs: nothing the person can see.")
        case .makerNotes: LocalizedStringResource("Hold the time since the device restarted and IDs for each photo, which can link your photos. Off: nothing visible changes.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What maker notes contain, and what turning them off costs.")
        case .nameAndCopyright: LocalizedStringResource("Off: nothing is lost. Only written if you enter them.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What turning off the name and copyright costs.")
        case .appNameAndVersion: LocalizedStringResource("Off: apps can't show what made the file.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "What turning off the app name costs.")
        }
    }

    /// A locked item's name.
    ///
    /// - Parameter item: The item.
    /// - Returns: A localized title from `Honesty.xcstrings`.
    static func title(of item: LockedMetadataItem) -> LocalizedStringResource {
        switch item {
        case .imageLayout: LocalizedStringResource("Image Size and Layout", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Locked metadata item: image size, bit depth, compression and data layout.")
        case .colorFilterPattern: LocalizedStringResource("Color Filter Pattern", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Locked metadata item: the sensor's red, green and blue pixel pattern.")
        case .blackAndWhiteLevels: LocalizedStringResource("Black and White Levels", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Locked metadata item.")
        case .colorCalibration: LocalizedStringResource("Color Data and White Balance", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Locked metadata item: color matrices and the as-shot white balance.")
        case .dngVersion: LocalizedStringResource("DNG Version", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Locked metadata item. DNG is a file format name.")
        case .orientation: LocalizedStringResource("Orientation", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Locked metadata item: which way up the photo is.")
        case .colorProfile: LocalizedStringResource("Color Profile (HEIF and JPEG)", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Locked metadata item. HEIF and JPEG are file format names.")
        }
    }

    /// Why a locked item can't be removed (`docs/PRIVACY.md`, "Locked").
    ///
    /// - Parameter item: The item.
    /// - Returns: A localized explanation from `Honesty.xcstrings`.
    static func explanation(of item: LockedMetadataItem) -> LocalizedStringResource {
        switch item {
        case .imageLayout: LocalizedStringResource("Without it, the file can't be read at all.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Why the image size and layout are always saved.")
        case .colorFilterPattern: LocalizedStringResource("Tells editors which pixels are red, green and blue. Without it, the RAW has no color.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Why the color filter pattern is always saved. RAW is a file format name.")
        case .blackAndWhiteLevels: LocalizedStringResource("Without them, shadows and highlights come out wrong.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Why the black and white levels are always saved.")
        case .colorCalibration: LocalizedStringResource("Without them, colors are wrong.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Why the color data and white balance are always saved.")
        case .dngVersion: LocalizedStringResource("Required by the DNG standard. Editors refuse the file without it.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Why the DNG version is always saved. DNG is a file format name.")
        case .orientation: LocalizedStringResource("Without it, the photo shows sideways or upside down.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Why the orientation is always saved.")
        case .colorProfile: LocalizedStringResource("Without it, colors look washed out or oversaturated.", table: "Honesty", bundle: .atURL(Bundle.module.bundleURL), comment: "Why the color profile is always saved.")
        }
    }
}

/// A setting's name with its explanation below it, both wrapping onto as many lines as the
/// text size needs.
struct SettingLabel: View {
    /// The setting's name.
    let title: Text

    /// What the setting does, and what turning it off costs.
    let explanation: Text

    /// Creates the label.
    ///
    /// - Parameters:
    ///   - title: The setting's name.
    ///   - explanation: What the setting does, and what turning it off costs.
    init(title: Text, explanation: Text) {
        self.title = title
        self.explanation = explanation
    }

    /// The name above the explanation.
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
            explanation
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
