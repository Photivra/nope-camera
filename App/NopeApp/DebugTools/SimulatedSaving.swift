#if DEBUG
// Debug-only: the simulated save steps the UI tests use. Compiled only in the Debug
// configuration; Release builds always use the RAW developer, the ImageIO read-back and PhotoKit.

import Foundation
import NopeCore

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

    /// Returns the tags a clean DNG needs (`MetadataPlan`'s required tags, with the generic
    /// camera model), the placeholder RAW data, and the future tag if asked for.
    func readBack(_ file: PhotoFile) throws(CaptureError) -> MetadataReadBack {
        var tags: [MetadataInventory.Tag] = []
        if file.format == .raw {
            tags = [0x828D, 0x828E, 0xC612, 0xC621].map { MetadataInventory.Tag(directory: .primary, tag: $0) }
            tags.append(MetadataInventory.Tag(directory: .primary, tag: 0xC614, text: MetadataPlan.genericUniqueCameraModel))
        }
        // A file that isn't the placeholder was changed by a breaking signer: it fails.
        if addsUnexpectedTag || file.data != SimulatedCaptureBackend.placeholderPhotoData {
            tags.append(MetadataInventory.Tag(directory: .primary, tag: Self.futureSystemTag))
        }
        return MetadataReadBack(
            file: MetadataFileReader.Result(
                inventory: MetadataInventory(tags: tags),
                rawImageData: file.format == .raw ? SimulatedCaptureBackend.placeholderPhotoData : nil),
            imageIOKeys: [])
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

    /// Does nothing, or throws `CaptureError.photosAccessDenied`.
    func add(_ assets: [PhotoLibraryAsset]) async throws(CaptureError) {
        guard allowsAdding else { throw .photosAccessDenied }
        if addSeconds > 0 { try? await Task.sleep(for: .seconds(addSeconds)) }
    }
}
#endif
