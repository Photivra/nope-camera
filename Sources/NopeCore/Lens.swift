import Foundation

/// One physical camera on the device, described as plain data.
///
/// Lenses are discovered at run time by a ``CaptureBackend``; an interface renders them without
/// knowing the hardware (AGENTS.md, "Capabilities are data").
public struct Lens: Identifiable, Equatable, Sendable {
    /// Where a lens sits and how wide it sees.
    public enum Kind: Equatable, Sendable, CaseIterable {
        /// The rear ultra wide camera.
        case ultraWide
        /// The rear wide (main) camera.
        case wide
        /// A rear telephoto camera.
        case telephoto
        /// The front camera.
        case front
    }

    /// A stable identifier for this lens on this device, supplied by the backend.
    ///
    /// It identifies the lens only within one run of the app and is never written to a photo.
    public let id: String

    /// Where the lens sits and how wide it sees.
    public let kind: Kind

    /// Whether this lens delivers single-frame Bayer RAW.
    ///
    /// When it's `false`, the lens can only give the HEIF fallback, which has some device
    /// processing, and the interface must say so (issue #1, "No-RAW fallback").
    public let supportsBayerRAW: Bool

    /// Creates a lens description.
    ///
    /// - Parameters:
    ///   - id: A stable identifier for the lens within this run of the app.
    ///   - kind: Where the lens sits and how wide it sees.
    ///   - supportsBayerRAW: Whether the lens delivers single-frame Bayer RAW.
    public init(id: String, kind: Kind, supportsBayerRAW: Bool) {
        self.id = id
        self.kind = kind
        self.supportsBayerRAW = supportsBayerRAW
    }
}
