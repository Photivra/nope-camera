import Foundation

/// Whether nope. signs each saved file with Content Credentials (C2PA).
///
/// Signing has its own switch in settings, outside the "Remove all optional details" master
/// switch, and is on by default (docs/PRIVACY.md, "Metadata plan"). The settings screen edits this
/// value; the save pipeline reads it and calls a ``PhotoSigning`` signer only when
/// ``isEnabled`` is `true`. When it is off, the file is saved unsigned and nothing about signing
/// is written to it.
public struct SigningSettings: Equatable, Hashable, Sendable, Codable {
    /// Whether each saved file is signed. `true` by default.
    public var isEnabled: Bool

    /// The settings when the app is first installed: signing on.
    public static let `default` = SigningSettings()

    /// Creates signing settings.
    ///
    /// - Parameter isEnabled: Whether each saved file is signed. Defaults to `true`.
    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }
}
