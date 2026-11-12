import Foundation

/// The software named in each manifest as the claim generator: Photivra Nope Camera and its version.
///
/// The C2PA specification requires `claim_generator_info.name` (C2PA 2.2, §10.2). Privacy rule:
/// the name and version are the same for everyone running that version of nope.; no device,
/// operating system or user detail is added.
public struct ClaimGenerator: Equatable, Sendable {
    /// The name every manifest gives: the full product name, "Photivra Nope Camera".
    public static let appName = "Photivra Nope Camera"

    /// The generator's name.
    public let name: String

    /// The app's marketing version, for example `0.1.0`.
    public let version: String

    /// Creates the claim generator for a version of nope.
    ///
    /// - Parameter version: The app's marketing version (`CFBundleShortVersionString`), for
    ///   example `0.1.0`.
    public init(version: String) {
        self.name = Self.appName
        self.version = version
    }
}
