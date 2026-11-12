import Foundation

/// Signs one finished file with Content Credentials (C2PA) and returns the signed file.
///
/// The save pipeline calls the signer after the file's metadata has been built from the
/// allowlist, and before the read-back check and the save to Photos:
///
/// 1. build the file's metadata from the allowlist;
/// 2. sign it with ``sign(_:as:)``, when ``SigningSettings/isEnabled`` is on;
/// 3. read the signed file back and check every tag and block against the allowlist, which
///    includes the Content Credentials store described by ``ContentCredentialsStore``;
/// 4. add the file to Photos.
///
/// Any change to the bytes after step 2 breaks the signature, so nothing may rewrite the file
/// between signing and saving.
///
/// `NopeSigning` provides the implementation; tests and interfaces use fakes. Privacy rule:
/// every call uses a new key that is discarded afterward, so no two files can be linked through
/// their signatures (AGENTS.md, "Honesty").
///
/// ```swift
/// let signed = try await signer.sign(dngBytes, as: .singleFrameRAW)
/// ```
public protocol PhotoSigning: Sendable {
    /// Signs one file.
    ///
    /// - Parameters:
    ///   - data: The complete file, with its final metadata.
    ///   - file: What the file is, which decides its media type and the manifest's description.
    /// - Returns: The same file with a Content Credentials manifest embedded. The image data and
    ///   metadata are otherwise unchanged; ``ContentCredentialsStore`` lists what is added.
    /// - Throws: ``PhotoSigningError`` when the file can't be signed. The save pipeline must then
    ///   tell the person the photo is not signed; it never fails silently.
    func sign(_ data: Data, as file: SignableFile) async throws(PhotoSigningError) -> Data
}

/// The kinds of file nope. signs, each with the honest description its manifest carries.
public enum SignableFile: Equatable, Hashable, Sendable, CaseIterable {
    /// Single-frame Bayer RAW, saved as DNG.
    case singleFrameRAW
    /// HEIF developed by nope. from a single-frame RAW.
    case developedHEIF
    /// JPEG developed by nope. from a single-frame RAW.
    case developedJPEG
    /// HEIF processed by the phone's camera, for a lens without Bayer RAW.
    case deviceProcessedHEIF
    /// JPEG processed by the phone's camera, for a lens without Bayer RAW or HEIF.
    case deviceProcessedJPEG

    /// The file nope. saves for a format it writes from a Bayer RAW capture.
    ///
    /// - Parameter format: The saved format: the DNG itself, or a file developed from it.
    public init(developedFrom format: PhotoFormat) {
        switch format {
        case .raw: self = .singleFrameRAW
        case .heif: self = .developedHEIF
        case .jpeg: self = .developedJPEG
        }
    }

    /// The file nope. saves for a lens without Bayer RAW.
    ///
    /// - Parameter fallback: The processed format the lens gave.
    public init(fallback: ProcessedFallback) {
        switch fallback {
        case .heif: self = .deviceProcessedHEIF
        case .jpeg: self = .deviceProcessedJPEG
        }
    }

    /// The file's container, which decides where the signature is stored.
    public var container: ContentCredentialsStore {
        switch self {
        case .singleFrameRAW: .dng
        case .developedHEIF, .deviceProcessedHEIF: .heif
        case .developedJPEG, .deviceProcessedJPEG: .jpeg
        }
    }
}

/// Where signing stores the Content Credentials manifest in each container.
///
/// Signing adds exactly one item to a file, and nothing else: no XMP, no EXIF tag, no thumbnail.
/// The metadata read-back allowlist must permit this item for signed files, and only this item
/// (AGENTS.md, "Metadata is allowlisted and verified"). The locations come from the C2PA
/// specification 2.2, appendix A, "Embedding manifests into assets", and were checked on files
/// signed by `NopeSigning` (`Tests/NopeSigningTests`).
public enum ContentCredentialsStore: Equatable, Hashable, Sendable, CaseIterable {
    /// DNG: the manifest store in TIFF tag 52545 (`0xCD41`), type `UNDEFINED`, in IFD0.
    case dng
    /// HEIF: the manifest store in a top-level `uuid` box with the C2PA UUID
    /// ``heifBoxUUID``.
    case heif
    /// JPEG: the manifest store as JUMBF in one or more APP11 (`0xFFEB`) segments, each with
    /// the common identifier `JP`.
    case jpeg

    /// The TIFF tag that holds the manifest store in a DNG: 52545 (`0xCD41`).
    public static let dngTag: UInt16 = 52545

    /// The JPEG marker of the segments that hold the manifest store: APP11 (`0xFFEB`).
    public static let jpegMarker: UInt16 = 0xFFEB

    /// The extended type of the HEIF `uuid` box that holds the manifest store:
    /// `D8FEC3D6-1B0E-483C-9297-5828877EC481`.
    public static let heifBoxUUID = UUID(uuidString: "D8FEC3D6-1B0E-483C-9297-5828877EC481")!

    /// The media type the C2PA library is given for the container.
    public var mediaType: String {
        switch self {
        case .dng: "image/x-adobe-dng"
        case .heif: "image/heic"
        case .jpeg: "image/jpeg"
        }
    }
}

/// Why a file couldn't be signed.
///
/// An unsigned photo is never saved silently: the interface says the photo is not signed.
public enum PhotoSigningError: Error, Equatable, Sendable {
    /// A new key couldn't be created, for example because the Secure Enclave is unavailable.
    case keyCreationFailed

    /// The key, the certificate or the C2PA library couldn't produce a signed file, for example
    /// because the file isn't a valid DNG, HEIF or JPEG.
    case signingFailed
}
