#if DEBUG
// Debug-only: the simulated save steps the UI tests use. Compiled only in the Debug
// configuration; Release builds always use the RAW developer, the ImageIO read-back and PhotoKit.

import Foundation
import NopeCore
import Synchronization

/// Returns the RAW's placeholder bytes as the developed file: the simulated backend's photo isn't
/// an image.
struct SimulatedDeveloper: PhotoDeveloping {
    /// Returns a file of the requested format with the RAW's bytes.
    func develop(_ raw: PhotoFile, to format: PhotoFormat, look: DevelopedLook, metadata: MetadataPlan)
        async throws(CaptureError) -> PhotoFile
    {
        PhotoFile(format: format, data: raw.data)
    }
}

/// Reports a clean file for the first-launch settings, or one with a simulated future system
/// tag, so the UI tests can show both the saved and the rejected states.
struct SimulatedReadBack: MetadataReading {
    /// A tag number no specification defines, standing in for a tag a future iOS adds.
    static let futureSystemTag: UInt16 = 0xC7FF

    /// Whether every file carries ``futureSystemTag``.
    let addsUnexpectedTag: Bool

    /// The size and depth reported for a HEIF or JPEG: 4032 × 3024 pixels, 8 bits.
    static let processedImage = ImageProperties(pixelWidth: 4032, pixelHeight: 3024, depth: 8)

    /// The fuller tag set of `-NopeSimulatedFileTags`, or `nil` for the minimal one.
    var fullTags: SimulatedFileTags? = SimulatedFileTags.fromLaunchArguments()

    /// Returns the tags a clean DNG needs (`MetadataPlan`'s required tags, with the generic
    /// camera model), the placeholder RAW data, and the future tag if asked for.
    func readBack(_ file: PhotoFile) throws(CaptureError) -> MetadataReadBack {
        var tags: [MetadataInventory.Tag] = []
        if file.format == .raw {
            tags = [0x828D, 0x828E, 0xC612, 0xC621].map { MetadataInventory.Tag(directory: .primary, tag: $0) }
            tags.append(MetadataInventory.Tag(directory: .primary, tag: 0xC614, text: MetadataPlan.genericUniqueCameraModel))
        }
        if let fullTags {
            tags = fullTags.tags(for: file.format, replacing: tags)
        }
        // A file that isn't the placeholder was changed by a breaking signer: it fails.
        if addsUnexpectedTag || file.data != SimulatedCaptureBackend.placeholderPhotoData {
            tags.append(MetadataInventory.Tag(directory: .primary, tag: Self.futureSystemTag))
        }
        return MetadataReadBack(
            file: MetadataFileReader.Result(
                inventory: MetadataInventory(tags: tags),
                rawImageData: file.format == .raw ? SimulatedCaptureBackend.placeholderPhotoData : nil),
            imageIOKeys: [],
            // A HEIF or JPEG reports a 12-megapixel size, as ImageIO does, so the Last Photo
            // viewer knows its preview is smaller than the photo.
            image: file.format == .raw ? nil : Self.processedImage)
    }
}

/// The fuller tag set the UI tests of What's in This Photo use (`-NopeSimulatedFileTags full`,
/// or `fullNoLocation` for a location switch that had nothing to write): realistic exposure,
/// lens, camera, date, DNG structure and location values, each only where the allowlist of the
/// current settings allows it, so the read-back still passes the verifier exactly as a real file
/// would. The settings are read from the UI test settings store when the file is read back.
struct SimulatedFileTags: Sendable {
    /// The launch argument: `-NopeSimulatedFileTags`.
    static let argument = "-NopeSimulatedFileTags"

    /// The `UserDefaults` key of the save settings (`NopeSettings`' `NopeSettings.save`).
    static let saveSettingsKey = "NopeSettings.save"

    /// The launch argument that sets the save settings of a UI test launch, as the JSON
    /// `NopeSettings` stores, in Base64: `-NopeSimulatedSaveSettings`.
    static let saveSettingsArgument = "-NopeSimulatedSaveSettings"

    /// Whether the GPS tags are written when the Location switch is on.
    let writesLocation: Bool

    /// The app's version, for the `Software` text rule.
    let appVersion: String

    /// The tag set chosen by the launch arguments, or `nil` without the argument.
    static func fromLaunchArguments(appVersion: String = "") -> SimulatedFileTags? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return SimulatedFileTags(writesLocation: arguments[index + 1] != "fullNoLocation", appVersion: appVersion)
    }

    /// The candidate tags: the values a recent iPhone writes, with the simulated place
    /// (`SimulatedLocationProvider.place`, 0.5° N, 0.5° E).
    static let candidates: [MetadataInventory.Tag] = {
        typealias Tag = MetadataInventory.Tag
        let primary: [Tag] = [
            Tag(directory: .primary, tag: 0x0100, values: [4032]), Tag(directory: .primary, tag: 0x0101, values: [3024]),
            Tag(directory: .primary, tag: 0x0102, values: [12]), Tag(directory: .primary, tag: 0x0103, values: [7]),
            Tag(directory: .primary, tag: 0x010F, text: "Apple"), Tag(directory: .primary, tag: 0x0110, text: "iPhone"),
            Tag(directory: .primary, tag: 0x0131, text: "Photivra Nope Camera"),
            Tag(directory: .primary, tag: 0x0132, text: "2026:11:18 14:41:07"),
            Tag(directory: .primary, tag: 0xC61A, values: [528, 528, 528, 528]), Tag(directory: .primary, tag: 0xC61D, values: [4095]),
            Tag(directory: .primary, tag: 0xC61F, values: [0, 0]), Tag(directory: .primary, tag: 0xC620, values: [4032, 3024]),
            Tag(directory: .primary, tag: 0xC628, values: [0.48, 1, 0.62]), Tag(directory: .primary, tag: 0xC62A, values: [0]),
            Tag(directory: .primary, tag: 0xC68D, values: [0, 0, 3024, 4032]),
        ]
        let exif: [Tag] = [
            Tag(directory: .exif, tag: 0x829A, values: [1.0 / 60]), Tag(directory: .exif, tag: 0x829D, values: [1.78]),
            Tag(directory: .exif, tag: 0x8822, values: [2]), Tag(directory: .exif, tag: 0x8827, values: [100]),
            Tag(directory: .exif, tag: 0x9003, text: "2026:11:18 14:41:07"), Tag(directory: .exif, tag: 0x9203, values: [7.2]),
            Tag(directory: .exif, tag: 0x9204, values: [0]), Tag(directory: .exif, tag: 0x9205, values: [1.66]),
            Tag(directory: .exif, tag: 0x9207, values: [5]), Tag(directory: .exif, tag: 0x9209, values: [16]),
            Tag(directory: .exif, tag: 0x920A, values: [6.86]), Tag(directory: .exif, tag: 0xA002, values: [4032]),
            Tag(directory: .exif, tag: 0xA003, values: [3024]), Tag(directory: .exif, tag: 0xA402, values: [0]),
            Tag(directory: .exif, tag: 0xA403, values: [0]), Tag(directory: .exif, tag: 0xA405, values: [24]),
            Tag(directory: .exif, tag: 0xA433, text: "Apple"),
            Tag(directory: .exif, tag: 0xA434, text: "iPhone back camera 6.86mm f/1.78"),
        ]
        let gps: [Tag] = [
            Tag(directory: .gps, tag: 0x0001, text: "N"), Tag(directory: .gps, tag: 0x0002, values: [0, 30, 0]),
            Tag(directory: .gps, tag: 0x0003, text: "E"), Tag(directory: .gps, tag: 0x0004, values: [0, 30, 0]),
        ]
        return primary + exif + gps
    }()

    /// The save settings in the UI test settings store, or the defaults.
    func settings() -> SaveSettings {
        let store = UserDefaults(suiteName: SimulatedCameraLaunch.settingsSuiteName)
        return store?.data(forKey: Self.saveSettingsKey).flatMap { try? JSONDecoder().decode(SaveSettings.self, from: $0) }
            ?? SaveSettings()
    }

    /// The minimal tags plus every candidate the format's allowlist allows, with the text a
    /// text rule asks for.
    ///
    /// - Parameters:
    ///   - format: The file's format.
    ///   - minimal: The minimal tags.
    /// - Returns: The tags.
    func tags(for format: PhotoFormat, replacing minimal: [MetadataInventory.Tag]) -> [MetadataInventory.Tag] {
        let plan = MetadataPlan(settings: settings().metadata, appVersion: appVersion)
        let allowlist = plan.allowlist(for: format, signed: false)
        var tags = minimal
        for candidate in Self.candidates {
            let id = MetadataAllowlist.TagID(candidate.directory, candidate.tag)
            guard allowlist.allows(id), !tags.contains(where: { $0.directory == candidate.directory && $0.tag == candidate.tag }),
                candidate.directory != .gps || writesLocation
            else { continue }
            if format != .raw && candidate.directory == .primary && candidate.tag >= 0xC612 { continue }
            switch allowlist.textRules[id] {
            case .exactly(let text): tags.append(.init(directory: candidate.directory, tag: candidate.tag, text: text))
            case .prefix(let prefix): tags.append(.init(directory: candidate.directory, tag: candidate.tag, text: prefix))
            case .oneOf(let texts): tags.append(.init(directory: candidate.directory, tag: candidate.tag, text: texts.first ?? ""))
            case .blankDate: tags.append(.init(directory: candidate.directory, tag: candidate.tag, text: MetadataPlan.unknownDateTime))
            case .any, nil: tags.append(candidate)
            }
        }
        return tags
    }
}

/// Stands in for the signer: returns each file unchanged, so the status shows "Saved and
/// signed."; fails, so it shows the signing-failed message; or returns a changed file that
/// fails the read-back, so the unsigned file is saved and the status says why (issue #66). The simulated backend's
/// placeholder bytes aren't an image the real signer can sign; `NopeSigningTests` cover real
/// signing.
struct SimulatedSigner: PhotoSigning {
    /// Why the simulated signer failed.
    struct Failure: Error {}

    /// Whether every file fails to sign.
    let fails: Bool

    /// Whether every signed file is changed so that it fails the read-back.
    var breaksFiles = false

    /// Returns the file, a changed copy, or throws ``Failure``.
    func sign(_ file: PhotoFile) async throws -> PhotoFile {
        if fails { throw Failure() }
        guard breaksFiles else { return file }
        return PhotoFile(format: file.format, data: file.data + [0], isProcessedByDevice: file.isProcessedByDevice)
    }
}

/// Makes a plain gray-blue thumbnail: the simulated backend's photo isn't an image, and
/// `NopeDevelopTests` cover the ImageIO thumbnailer.
struct SimulatedThumbnailer: PhotoThumbnailing {
    /// The thumbnail's side, in pixels.
    static let side = 8

    /// Returns the same small thumbnail for every file.
    func thumbnail(of file: PhotoFile) -> PhotoThumbnail? {
        let pixel: [UInt8] = [70, 90, 120, 255]
        return PhotoThumbnail(
            width: Self.side, height: Self.side, rgba: Data(Array(repeating: pixel, count: Self.side * Self.side).joined()))
    }
}

/// Makes the compare view's two pictures (issue #55): plain 4:3 pictures held upright, gray-blue
/// for the app's file and warm orange for the phone-processed one, so the divider is visible. The
/// simulated photos aren't images; `NopeDevelopTests` cover the ImageIO thumbnailer.
struct SimulatedComparisonRenderer: PhotoThumbnailing {
    /// The picture's width, in pixels.
    static let width = 30
    /// The picture's height, in pixels.
    static let height = 40

    /// Returns a picture in the file's color.
    func thumbnail(of file: PhotoFile) -> PhotoThumbnail? {
        let pixel: [UInt8] = file.isProcessedByDevice ? [200, 120, 60, 255] : [70, 90, 120, 255]
        return PhotoThumbnail(
            width: Self.width, height: Self.height,
            rgba: Data(Array(repeating: pixel, count: Self.width * Self.height).joined()))
    }
}

/// Makes the Last Photo viewer's previews (`SessionPhotos`): a plain 3:4 gray-blue picture, held
/// upright, whose "compressed" bytes are its pixels. The simulated photos aren't images;
/// `NopeDevelopTests` cover the ImageIO previewer.
struct SimulatedPreviewer: PhotoPreviewing {
    /// The picture's width, in pixels.
    static let width = 30
    /// The picture's height, in pixels.
    static let height = 40
    /// The picture's pixels.
    static let pixels = Data(Array(repeating: [UInt8]([70, 90, 120, 255]), count: width * height).joined())

    /// Returns the same preview for every file.
    func preview(of file: PhotoFile) -> PhotoPreview? {
        PhotoPreview(width: Self.width, height: Self.height, data: Self.pixels)
    }

    /// Returns the picture at its own size.
    func decode(_ preview: PhotoPreview, maximumPixelSize: Int?) -> PhotoThumbnail? {
        PhotoThumbnail(width: preview.width, height: preview.height, rgba: preview.data)
    }
}

/// Accepts or refuses every add, without touching the Simulator's photo library.
struct SimulatedPhotoLibrary: PhotoLibrary {
    /// Whether adding is allowed.
    let allowsAdding: Bool

    /// How long each add takes, in seconds, so a burst runs long enough to watch.
    var addSeconds = 0.0

    /// How many adds succeed before every later one fails with `CaptureError.saveFailed`, or
    /// `nil` for no limit: a photo that fails while the Last Photo viewer is open.
    var successfulAdds: Int?

    /// The adds so far.
    private let adds = AddCount()

    /// Does nothing, or throws `CaptureError.photosAccessDenied`, or `saveFailed` past
    /// ``successfulAdds``.
    func add(_ assets: [PhotoLibraryAsset]) async throws(CaptureError) {
        guard allowsAdding else { throw .photosAccessDenied }
        if let successfulAdds, adds.next() > successfulAdds { throw .saveFailed }
        if addSeconds > 0 { try? await Task.sleep(for: .seconds(addSeconds)) }
    }
}

/// Counts the simulated library's adds.
final class AddCount: Sendable {
    /// The count.
    private let count = Mutex(0)

    /// Adds one and returns the new count.
    func next() -> Int {
        count.withLock { value in
            value += 1
            return value
        }
    }
}
#endif
