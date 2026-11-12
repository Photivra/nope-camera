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
        if addsUnexpectedTag { tags.append(MetadataInventory.Tag(directory: .primary, tag: Self.futureSystemTag)) }
        return MetadataReadBack(
            file: MetadataFileReader.Result(
                inventory: MetadataInventory(tags: tags),
                rawImageData: file.format == .raw ? SimulatedCaptureBackend.placeholderPhotoData : nil),
            imageIOKeys: [])
    }
}

/// Accepts or refuses every add, without touching the Simulator's photo library.
struct SimulatedPhotoLibrary: PhotoLibrary {
    /// Whether adding is allowed.
    let allowsAdding: Bool

    /// Does nothing, or throws `CaptureError.photosAccessDenied`.
    func add(_ assets: [PhotoLibraryAsset]) async throws(CaptureError) {
        guard allowsAdding else { throw .photosAccessDenied }
    }
}
#endif
