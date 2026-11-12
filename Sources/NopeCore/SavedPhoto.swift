import Foundation

/// Whether a saved photo is signed, and if not, why.
///
/// An unsigned photo is never presented as signed: the interface shows the reason (issue #1,
/// "never hidden: not signed").
public enum SignatureStatus: Equatable, Sendable {
    /// Why a photo isn't signed.
    public enum UnsignedReason: Equatable, Sendable, CaseIterable {
        /// The person turned signing off (``MetadataSettings/signsPhotos``).
        case turnedOff
        /// This build has no signer (no ``PhotoSigning`` was supplied).
        case unavailable
        /// The signer failed for at least one file.
        case failed
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

    /// Creates a saved-photo record.
    ///
    /// - Parameters:
    ///   - formats: The formats saved.
    ///   - isProcessedFallback: Whether it is the processed fallback.
    ///   - signature: The signature status.
    ///   - metadata: Each file's read-back inventory.
    public init(
        formats: [PhotoFormat], isProcessedFallback: Bool, signature: SignatureStatus,
        metadata: [PhotoFormat: MetadataInventory]
    ) {
        self.formats = formats
        self.isProcessedFallback = isProcessedFallback
        self.signature = signature
        self.metadata = metadata
    }
}
