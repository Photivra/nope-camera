import Foundation

/// One file of a photo, on its way to Photos: a DNG, or a HEIF or JPEG.
///
/// Privacy: files live in memory only. They go from memory to Photos and are never written to
/// disk by `NopeCore` (AGENTS.md, "Photos never linger").
public struct PhotoFile: Equatable, Sendable {
    /// The file's format.
    public let format: PhotoFormat
    /// The file's bytes.
    public let data: Data

    /// Creates a file.
    ///
    /// - Parameters:
    ///   - format: The file's format.
    ///   - data: The file's bytes.
    public init(format: PhotoFormat, data: Data) {
        self.format = format
        self.data = data
    }
}

/// What the read-back found in one file: the project's own reader's result, plus the property
/// keys ImageIO reports when it opens the file.
public struct MetadataReadBack: Equatable, Sendable {
    /// Every tag, block and property, and the RAW image data of a DNG.
    public let file: MetadataFileReader.Result
    /// Every key in ImageIO's property dictionaries for the image, as ``ImageIOKey`` values.
    public let imageIOKeys: [ImageIOKey]

    /// Creates a read-back result.
    ///
    /// - Parameters:
    ///   - file: The project reader's result.
    ///   - imageIOKeys: ImageIO's keys.
    public init(file: MetadataFileReader.Result, imageIOKeys: [ImageIOKey]) {
        self.file = file
        self.imageIOKeys = imageIOKeys
    }
}

/// Reads a finished file back, before it is saved (AGENTS.md, "Fail closed").
///
/// `NopeDevelop` implements it with ``MetadataFileReader`` and ImageIO (`ImageIOReadBack`).
public protocol MetadataReading: Sendable {
    /// Reads a file back.
    ///
    /// - Parameter file: The finished file, after signing.
    /// - Returns: What the file holds.
    /// - Throws: ``CaptureError/metadataNotAllowed`` if the system can't open the file as one
    ///   image of its format, so its contents can't be confirmed.
    func readBack(_ file: PhotoFile) throws(CaptureError) -> MetadataReadBack
}

/// Develops a HEIF or JPEG from a RAW photo.
///
/// `NopeDevelop` implements it with Core Image and the system encoders (`RAWDeveloper`).
public protocol PhotoDeveloping: Sendable {
    /// Develops a file from the RAW, with metadata built from the plan.
    ///
    /// - Parameters:
    ///   - raw: The DNG, with its metadata already built from the allowlist.
    ///   - format: ``PhotoFormat/heif`` or ``PhotoFormat/jpeg``.
    ///   - look: The tone of the developed file.
    ///   - metadata: The plan the new file's metadata is built from.
    /// - Returns: The developed file.
    /// - Throws: ``CaptureError/developmentFailed`` if the RAW can't be developed or encoded.
    func develop(_ raw: PhotoFile, to format: PhotoFormat, look: DevelopedLook, metadata: MetadataPlan)
        async throws(CaptureError) -> PhotoFile
}

/// The hook where Content Credentials signing plugs in: after the files are built and before
/// they are read back and saved.
///
/// `NopeSigning` implements it with a fresh Secure Enclave key for every photo (AGENTS.md,
/// "Every photo is signed, with a fresh key per photo"). ``PhotoSaver`` calls it for each file
/// when ``MetadataSettings/signsPhotos`` is on. The signed file is then read back like any
/// other: its manifest may add only the block the allowlist names for a signed file
/// (``MetadataPlan/allowlist(for:signed:)``), and a DNG's RAW image data must not change.
///
/// With no signer, files are saved unsigned and the status says so
/// (``SignatureStatus/unsigned(_:)`` with ``SignatureStatus/UnsignedReason/unavailable``).
public protocol PhotoSigning: Sendable {
    /// Signs one file.
    ///
    /// - Parameter file: The file to sign.
    /// - Returns: The same file with a Content Credentials manifest.
    /// - Throws: Any error; the file is then saved unsigned, and the status says signing failed.
    func sign(_ file: PhotoFile) async throws -> PhotoFile
}

/// One Photos asset to create: one file, or a RAW with its processed version as a pair.
public struct PhotoLibraryAsset: Equatable, Sendable {
    /// The asset's main file: the DNG of a RAW pair, otherwise the only file.
    public let primary: PhotoFile
    /// The processed file paired with a RAW, or `nil`.
    public let alternate: PhotoFile?

    /// Creates an asset.
    ///
    /// - Parameters:
    ///   - primary: The main file.
    ///   - alternate: The paired processed file, or `nil`.
    public init(primary: PhotoFile, alternate: PhotoFile? = nil) {
        self.primary = primary
        self.alternate = alternate
    }

    /// Groups a photo's files into Photos assets.
    ///
    /// A RAW and one processed file (HEIF if there is one, otherwise JPEG) become one asset with
    /// the DNG as its main resource and the processed file as its alternate, as Apple documents
    /// for RAW plus processed captures ("Capturing Photos in RAW and Apple ProRAW Formats", "Save
    /// the photos to the photos library":
    /// https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats).
    /// Any other file is its own asset.
    ///
    /// - Parameter files: The photo's files.
    /// - Returns: The assets to create, in one change.
    public static func assets(for files: [PhotoFile]) -> [PhotoLibraryAsset] {
        guard let raw = files.first(where: { $0.format == .raw }) else {
            return files.map { PhotoLibraryAsset(primary: $0) }
        }
        let partner = files.first { $0.format == .heif } ?? files.first { $0.format == .jpeg }
        let others = files.filter { $0 != raw && $0 != partner }
        return [PhotoLibraryAsset(primary: raw, alternate: partner)] + others.map { PhotoLibraryAsset(primary: $0) }
    }
}

/// Adds photos to the library with add-only access.
///
/// `NopeCapture` implements it with PhotoKit (`PhotoKitLibrary`). Add-only access can't read
/// the library, including nope.'s own photos.
public protocol PhotoLibrary: Sendable {
    /// Asks for add-only access if needed, then adds every asset in one change.
    ///
    /// Side effects: may show the system's add-only Photos prompt (the localized
    /// `NSPhotoLibraryAddUsageDescription`); adds the assets to Photos.
    ///
    /// - Parameter assets: The assets to add.
    /// - Throws: ``CaptureError/photosAccessDenied`` without access, or
    ///   ``CaptureError/saveFailed`` if Photos reports an error.
    func add(_ assets: [PhotoLibraryAsset]) async throws(CaptureError)
}
