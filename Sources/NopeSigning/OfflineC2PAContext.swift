import C2PA
import Foundation

/// Builds the C2PA library context nope. signs with: fully offline, no thumbnail, no timestamp.
///
/// Privacy and network rule: nope. makes no network calls (AGENTS.md, "No network, no
/// analytics"). The C2PA library can fetch remote manifests, certificate status (OCSP) and
/// timestamps, so the context shuts every path off twice:
/// - the settings turn off each fetch and allow no network host at all
///   (`core.allowed_network_hosts` set to an empty list blocks all traffic);
/// - the context's HTTP resolver, which the library calls for every request, refuses every
///   request without sending it.
enum OfflineC2PAContext {
    /// Why the HTTP resolver refused a request.
    enum NetworkRefused: Error, Equatable {
        /// nope. never makes a network request.
        case networkIsNeverUsed
    }

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

    /// Refuses a network request without sending it.
    ///
    /// Generic over the request type so the tests can call it: the library's `HTTPRequest` has no
    /// public initializer. The context passes it as its `HTTPRequest` resolver.
    ///
    /// - Parameter request: The request the library asked for. It is ignored.
    /// - Returns: Never returns.
    /// - Throws: ``NetworkRefused/networkIsNeverUsed``, always.
    @Sendable static func refuse<Request>(_ request: Request) throws -> HTTPResponse {
        throw NetworkRefused.networkIsNeverUsed
    }

    /// Creates a new context whose HTTP resolver refuses every request.
    ///
    /// - Parameter definition: The settings. Signing always uses ``settings``; the tests pass
    ///   settings that let the library try a fetch, to prove the resolver refuses it.
    /// - Returns: The context.
    /// - Throws: `C2PAError` if the library rejects the settings.
    static func make(_ definition: C2PASettingsDefinition = settings) throws -> C2PAContext {
        try C2PAContext(settings: C2PASettings(definition: definition), httpResolver: refuse)
    }
}
