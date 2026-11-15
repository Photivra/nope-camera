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
    /// Whether the phone's camera processed the file: the HEIF or JPEG of a lens without Bayer
    /// RAW. `false` for a DNG and for a HEIF or JPEG the app developed from the RAW. The signer
    /// uses it to describe the file truthfully in its Content Credentials.
    public let isProcessedByDevice: Bool
    /// What the file's Content Credentials manifest says, set by the signer on the file it
    /// returns; `nil` for an unsigned file. The "What's in this photo" details show it.
    public let contentCredentials: ContentCredentialsSummary?

    /// Creates a file.
    ///
    /// - Parameters:
    ///   - format: The file's format.
    ///   - data: The file's bytes.
    ///   - isProcessedByDevice: Whether the phone's camera processed it (the fallback of a lens
    ///     without Bayer RAW). Defaults to `false`.
    ///   - contentCredentials: What the file's manifest says, for a signed file. Defaults to
    ///     `nil`.
    public init(
        format: PhotoFormat, data: Data, isProcessedByDevice: Bool = false,
        contentCredentials: ContentCredentialsSummary? = nil
    ) {
        self.format = format
        self.data = data
        self.isProcessedByDevice = isProcessedByDevice
        self.contentCredentials = contentCredentials
    }
}

/// What the read-back found in one file: the project's own reader's result, plus the property
/// keys ImageIO reports when it opens the file.
public struct MetadataReadBack: Equatable, Sendable {
    /// Every tag, block and property, and the RAW image data of a DNG.
    public let file: MetadataFileReader.Result
    /// Every key in ImageIO's property dictionaries for the image, as ``ImageIOKey`` values.
    public let imageIOKeys: [ImageIOKey]
    /// The image's size and bit depth as ImageIO reports them, or `nil` when the reader doesn't
    /// supply them.
    public let image: ImageProperties?

    /// Creates a read-back result.
    ///
    /// - Parameters:
    ///   - file: The project reader's result.
    ///   - imageIOKeys: ImageIO's keys.
    ///   - image: ImageIO's size and bit depth, or `nil`.
    public init(file: MetadataFileReader.Result, imageIOKeys: [ImageIOKey], image: ImageProperties? = nil) {
        self.file = file
        self.imageIOKeys = imageIOKeys
        self.image = image
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

    /// Develops a file from the RAW with the person's encoding options (issue #57).
    ///
    /// ``PhotoSaver`` calls this one. The default implementation ignores `options` and calls
    /// ``develop(_:to:look:metadata:)``, for developers that have no options, such as test fakes.
    ///
    /// - Parameters:
    ///   - raw: The DNG, with its metadata already built from the allowlist.
    ///   - format: ``PhotoFormat/heif`` or ``PhotoFormat/jpeg``.
    ///   - look: The tone of the developed file.
    ///   - options: The compression, HEIF bit depth and color space.
    ///   - metadata: The plan the new file's metadata is built from.
    /// - Returns: The developed file.
    /// - Throws: ``CaptureError/developmentFailed`` if the RAW can't be developed or encoded.
    func develop(
        _ raw: PhotoFile, to format: PhotoFormat, look: DevelopedLook, options: DevelopedFileOptions,
        metadata: MetadataPlan
    ) async throws(CaptureError) -> PhotoFile
}

extension PhotoDeveloping {
    /// Develops a file without encoding options: calls ``develop(_:to:look:metadata:)``.
    ///
    /// - Parameters:
    ///   - raw: The DNG.
    ///   - format: ``PhotoFormat/heif`` or ``PhotoFormat/jpeg``.
    ///   - look: The tone of the developed file.
    ///   - options: Ignored.
    ///   - metadata: The plan the new file's metadata is built from.
    /// - Returns: The developed file.
    /// - Throws: Whatever ``develop(_:to:look:metadata:)`` throws.
    public func develop(
        _ raw: PhotoFile, to format: PhotoFormat, look: DevelopedLook, options: DevelopedFileOptions,
        metadata: MetadataPlan
    ) async throws(CaptureError) -> PhotoFile {
        try await develop(raw, to: format, look: look, metadata: metadata)
    }
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
    /// Any other file is its own asset. When both a HEIF and a JPEG are saved, `pairing` says
    /// which one is paired with the RAW (issue #50); the other is its own asset.
    ///
    /// - Parameters:
    ///   - files: The photo's files.
    ///   - pairing: The processed copy to pair with the RAW when there are two. Defaults to
    ///     ``RAWPairing/heif``.
    /// - Returns: The assets to create, in one change.
    public static func assets(for files: [PhotoFile], pairing: RAWPairing = .heif) -> [PhotoLibraryAsset] {
        guard let raw = files.first(where: { $0.format == .raw }) else {
            return files.map { PhotoLibraryAsset(primary: $0) }
        }
        let other: PhotoFormat = pairing == .heif ? .jpeg : .heif
        let partner = files.first { $0.format == pairing.format } ?? files.first { $0.format == other }
        let others = files.filter { $0 != raw && $0 != partner }
        return [PhotoLibraryAsset(primary: raw, alternate: partner)] + others.map { PhotoLibraryAsset(primary: $0) }
    }
}

/// Adds photos to the library with add-only access.
///
/// `NopeCapture` implements it with PhotoKit (`PhotoKitLibrary`). Add-only access can't read
/// the library, including the app's own photos.
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
