import Foundation
import NopeCore

/// The kinds of file nope. signs, each with the honest description its manifest carries.
///
/// Derived from a `PhotoFile`: its format, and whether the phone's camera processed it.
enum SignableFile: Equatable, Hashable, Sendable, CaseIterable {
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

    /// The kind of a file on its way to Photos.
    ///
    /// - Parameter file: The file.
    init(_ file: PhotoFile) {
        switch (file.format, file.isProcessedByDevice) {
        case (.raw, _): self = .singleFrameRAW
        case (.heif, false): self = .developedHEIF
        case (.jpeg, false): self = .developedJPEG
        case (.heif, true): self = .deviceProcessedHEIF
        case (.jpeg, true): self = .deviceProcessedJPEG
        }
    }

    /// The file's format.
    var format: PhotoFormat {
        switch self {
        case .singleFrameRAW: .raw
        case .developedHEIF, .deviceProcessedHEIF: .heif
        case .developedJPEG, .deviceProcessedJPEG: .jpeg
        }
    }

    /// Whether the phone's camera processed the file.
    var isProcessedByDevice: Bool {
        self == .deviceProcessedHEIF || self == .deviceProcessedJPEG
    }

    /// The media type the C2PA library is given, which decides where the manifest is stored:
    /// DNG tag 52545 (`0xCD41`) in IFD0, a top-level HEIF `uuid` box with the C2PA UUID
    /// `D8FEC3D6-1B0E-483C-9297-5828877EC481`, or JPEG APP11 (`0xFFEB`) segments (C2PA 2.2,
    /// appendix A). `MetadataPlan.allowlist(for:signed:)` in `NopeCore` permits exactly these.
    var mediaType: String {
        switch format {
        case .raw: "image/x-adobe-dng"
        case .heif: "image/heic"
        case .jpeg: "image/jpeg"
        }
    }
}

/// Why a file couldn't be signed. `PhotoSaver` then saves the file unsigned and the status says
/// signing failed.
public enum PhotoSigningError: Error, Equatable, Sendable {
    /// A new key couldn't be created, for example because the Secure Enclave is unavailable.
    case keyCreationFailed

    /// The key, the certificate or the C2PA library couldn't produce a signed file, for example
    /// because the file isn't a valid DNG, HEIF or JPEG.
    case signingFailed
}
