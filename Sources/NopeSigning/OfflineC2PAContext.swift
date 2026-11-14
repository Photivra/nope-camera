import C2PA
import Foundation

/// Builds the C2PA library context nope. signs with: fully offline, no thumbnail, no timestamp.
///
/// Privacy and network rule: nope. makes no network calls and links no networking code
/// (AGENTS.md, "No network, no analytics"). The C2PA library nope. links is built without any
/// network feature (`c2pa-lib/README.md`), so it has no HTTP client to call. The settings also
/// turn off every fetch and allow no network host (`core.allowed_network_hosts` set to an empty
/// list blocks all traffic), so the library never asks for one.
enum OfflineC2PAContext {
    /// The settings: offline, no automatic timestamp, no thumbnail, no OCSP.
    ///
    /// - `core.allowed_network_hosts`: an empty list, which blocks all traffic.
    /// - `verify.ocsp_fetch`, `verify.remote_manifest_fetch`: off.
    /// - `verify.verify_trust`, `verify.verify_after_sign`: off while signing. The anonymous
    ///   certificate is never on a trust list, and the tests verify every signed file instead.
    /// - `builder.thumbnail.enabled`: off, so no image derived from the photo is added.
    /// - `builder.auto_timestamp_assertion.enabled`: off, so no time is added.
    static let settings = C2PASettingsDefinition(
        version: 1,
        core: CoreSettings(allowedNetworkHosts: []),
        verify: VerifySettings(
            verifyAfterSign: false, verifyTrust: false, ocspFetch: false, remoteManifestFetch: false),
        builder: BuilderSettingsDefinition(
            thumbnail: ThumbnailSettings(enabled: false),
            autoTimestampAssertion: TimeStampSettings(enabled: false))
    )

    /// Creates a new context with ``settings``.
    ///
    /// - Returns: The context.
    /// - Throws: `C2PAError` if the library rejects the settings.
    static func make() throws -> C2PAContext {
        try C2PAContext(settings: C2PASettings(definition: settings))
    }

    /// Creates a new context with ``settings`` that signs with one signer, for the data-hash
    /// workflow (`Builder.signEmbeddable(format:)` signs with the context's signer).
    ///
    /// - Parameter signer: The signer; the context takes ownership of it.
    /// - Returns: The context.
    /// - Throws: `C2PAError` if the library rejects the settings or the signer.
    static func make(signer: sending Signer) throws -> C2PAContext {
        try C2PAContext(settings: C2PASettings(definition: settings), signer: signer)
    }
}
