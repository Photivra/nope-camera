import Foundation

/// Whether a saved photo is signed, and if not, why.
///
/// An unsigned photo is never presented as signed: the interface shows the reason (issue #1,
/// "never hidden: not signed").
public enum SignatureStatus: Equatable, Sendable {
    /// Why a photo isn't signed. It is also sent to the Apple Watch app (``PhoneUpdate``), so
    /// its raw values are part of the watch message format.
    public enum UnsignedReason: String, Equatable, Codable, Sendable, CaseIterable {
        /// The person turned signing off (``MetadataSettings/signsPhotos``).
        case turnedOff
        /// This build has no signer (no ``PhotoSigning`` was supplied).
        case unavailable
        /// The signer failed for at least one file.
        case failed
        /// A signed file failed the read-back, for example because the system can't open it,
        /// so its unsigned file, which passed, was saved instead (issue #66).
        case signedFileFailedCheck
    }

    /// Every file carries a Content Credentials manifest.
    case signed
    /// At least one file has no manifest, for this reason.
    case unsigned(UnsignedReason)
}

/// A photo that passed the read-back and was added to Photos.
public struct SavedPhoto: Equatable, Sendable {
    /// The formats saved, in the order they were built.
    public let formats: [PhotoFormat]
    /// Whether the photo is the processed fallback of a lens without Bayer RAW.
    public let isProcessedFallback: Bool
    /// Whether the photo is signed.
    public let signature: SignatureStatus
    /// Every tag, block and property of each saved file, for the "What's in your last photo"
    /// screen (issue #1). Kept in memory only, because add-only access can't read Photos.
    public let metadata: [PhotoFormat: MetadataInventory]
    /// A small picture of the photo for the last-photo thumbnail (issue #36), or `nil` when
    /// there is no thumbnailer or the file couldn't be read. In memory only.
    public let thumbnail: PhotoThumbnail?
    /// "What's in this photo": the facts read back from the saved files (issue #53), or `nil`
    /// for a record made outside ``PhotoSaver``. In memory only.
    public let details: PhotoDetails?
    /// The photo's place in an exposure bracket, or `nil` for a photo taken on its own. In
    /// memory only: the session's values, never written to the files
    /// (docs/design/BRACKETING.md, section 4, "The result").
    public let bracket: BracketPlace?

    /// Creates a saved-photo record.
    ///
    /// - Parameters:
    ///   - formats: The formats saved.
    ///   - isProcessedFallback: Whether it is the processed fallback.
    ///   - signature: The signature status.
    ///   - metadata: Each file's read-back inventory.
    ///   - thumbnail: The photo's thumbnail, or `nil`.
    ///   - details: The photo's details, or `nil`.
    ///   - bracket: The photo's place in a bracket, or `nil`.
    public init(
        formats: [PhotoFormat], isProcessedFallback: Bool, signature: SignatureStatus,
        metadata: [PhotoFormat: MetadataInventory], thumbnail: PhotoThumbnail? = nil, details: PhotoDetails? = nil,
        bracket: BracketPlace? = nil
    ) {
        self.formats = formats
        self.isProcessedFallback = isProcessedFallback
        self.signature = signature
        self.metadata = metadata
        self.thumbnail = thumbnail
        self.details = details
        self.bracket = bracket
    }

    /// The same record with its place in a bracket.
    ///
    /// - Parameter place: The photo's place in its bracket.
    /// - Returns: The record with ``bracket`` set.
    func placed(in place: BracketPlace) -> SavedPhoto {
        SavedPhoto(
            formats: formats, isProcessedFallback: isProcessedFallback, signature: signature, metadata: metadata,
            thumbnail: thumbnail, details: details, bracket: place)
    }
}
