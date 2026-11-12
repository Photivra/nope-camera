import Foundation

/// One optional metadata item a person can switch on or off.
///
/// Each case is a row of the "Switches" table in `docs/PRIVACY.md` ("Metadata plan"). Removing
/// any of them never breaks the photo. Items the photo can't work without are locked and have no
/// case here (``MetadataField/Group/locked(_:)``). The Content Credentials signature has its own
/// switch outside this list (``MetadataSettings/signsPhotos``).
public enum MetadataItem: String, CaseIterable, Codable, Hashable, Sendable {
    /// Location, altitude and direction (the EXIF GPS directory). nope. doesn't capture a
    /// location yet, so with this item on no location is written either.
    case location
    /// The date and time the photo was taken.
    case dateAndTime
    /// The fraction of a second of each timestamp.
    case subSecondTime
    /// The time zone offset of each timestamp.
    case timeZone
    /// The camera's make and model, such as the phone model.
    case cameraMakeAndModel
    /// The lens's make and model, and its focal length and aperture range.
    case lensMakeAndModel
    /// The exact camera model for RAW editors (DNG `UniqueCameraModel`). The DNG standard
    /// requires the tag, so when this item is off nope. writes
    /// ``MetadataPlan/genericUniqueCameraModel`` instead of removing it.
    case exactCameraModel
    /// The lens correction instructions in a DNG (opcode lists). The pixels are never corrected
    /// either way.
    case lensCorrections
    /// The exposure settings: shutter speed, ISO, aperture, focal length and related EXIF tags.
    case exposureSettings
    /// The phone's system version, which the system writes as the software name.
    case systemVersion
    /// The camera maker's private notes. Apple's hold the time since the device restarted and
    /// per-photo identifiers, which can link photos.
    case makerNotes
    /// The photographer's name and copyright notice, written only when the person enters them
    /// (``MetadataSettings/ownerName`` and ``MetadataSettings/copyrightNotice``).
    case nameAndCopyright
    /// The app's name and version ("Photivra Nope Camera" and its version number).
    case appNameAndVersion

    /// The item's setting when the person turns "Remove all optional details" off: the
    /// "Default" column of `docs/PRIVACY.md`.
    public var isOnWhenCustomizing: Bool {
        switch self {
        case .dateAndTime, .cameraMakeAndModel, .lensMakeAndModel, .exactCameraModel, .lensCorrections,
            .exposureSettings, .appNameAndVersion:
            true
        case .location, .subSecondTime, .timeZone, .systemVersion, .makerNotes, .nameAndCopyright:
            false
        }
    }
}

/// The person's metadata choices: the master switch, one switch per optional item, and the
/// signature switch.
///
/// This is the settings model the Settings screens are built on, and the only input the
/// metadata allowlist takes (``MetadataPlan``). It holds the rules of `docs/PRIVACY.md`,
/// "Metadata plan", so an interface only shows the values and calls the mutating methods:
///
/// - "Remove all optional details" (``removesAllOptionalDetails``) is on by default, and then
///   every item is off.
/// - Turning any item on turns the master off; the interface then shows "Custom" (``isCustom``).
/// - Turning the master back on turns every item off again.
/// - Turning the master off sets every item to its documented default
///   (``MetadataItem/isOnWhenCustomizing``).
/// - Signing (``signsPhotos``) is outside the master switch and on by default.
///
/// ```swift
/// var settings = MetadataSettings()          // master on, every item off
/// settings.set(.location, isOn: true)        // master off ("Custom"), location on
/// settings.setRemovesAllOptionalDetails(true) // every item off again
/// ```
///
/// The type is `Codable`, so an interface can store it; nothing in `NopeCore` writes it to disk.
public struct MetadataSettings: Equatable, Codable, Sendable {
    /// Whether "Remove all optional details" is on. When it is, ``enabledItems`` is empty.
    public private(set) var removesAllOptionalDetails: Bool

    /// The optional items that are on. Always empty while ``removesAllOptionalDetails`` is on.
    public private(set) var enabledItems: Set<MetadataItem>

    /// Whether each photo is signed with Content Credentials. Outside the master switch; on by
    /// default.
    public var signsPhotos: Bool

    /// The name written as the photo's artist when ``MetadataItem/nameAndCopyright`` is on.
    /// Empty means nothing is written.
    public var ownerName: String

    /// The copyright notice written when ``MetadataItem/nameAndCopyright`` is on. Empty means
    /// nothing is written.
    public var copyrightNotice: String

    /// The settings on first launch: every optional detail removed, photos signed, and no name
    /// or copyright entered.
    public init() {
        removesAllOptionalDetails = true
        enabledItems = []
        signsPhotos = true
        ownerName = ""
        copyrightNotice = ""
    }

    /// Whether the interface should show "Custom": the master switch is off.
    public var isCustom: Bool {
        !removesAllOptionalDetails
    }

    /// Whether an optional item is on.
    ///
    /// - Parameter item: The item.
    /// - Returns: `true` when the item will be written.
    public func isOn(_ item: MetadataItem) -> Bool {
        enabledItems.contains(item)
    }

    /// Turns "Remove all optional details" on or off.
    ///
    /// - Parameter isOn: `true` turns every item off; `false` sets every item to its default
    ///   (``MetadataItem/isOnWhenCustomizing``).
    public mutating func setRemovesAllOptionalDetails(_ isOn: Bool) {
        removesAllOptionalDetails = isOn
        enabledItems = isOn ? [] : Set(MetadataItem.allCases.filter(\.isOnWhenCustomizing))
    }

    /// Turns one optional item on or off. Turning an item on turns the master switch off.
    ///
    /// - Parameters:
    ///   - item: The item.
    ///   - isOn: Whether it is written.
    public mutating func set(_ item: MetadataItem, isOn: Bool) {
        if isOn {
            enabledItems.insert(item)
            removesAllOptionalDetails = false
        } else {
            enabledItems.remove(item)
        }
    }
}
