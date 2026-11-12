import Foundation

/// The key provider for this build: a software key in the Simulator, the Secure Enclave
/// everywhere else.
///
/// A device build always gets ``SecureEnclaveKeyProvider``; the software key isn't compiled into
/// it at all. When a device has no usable Secure Enclave, signing fails and the photo is saved
/// with a "not signed" message; it never falls back to a software key.
///
/// - Returns: The provider the app should give ``ContentCredentialsSigner``.
public func platformKeyProvider() -> any SigningKeyProvider {
    #if targetEnvironment(simulator)
    SimulatorSoftwareKeyProvider()
    #else
    SecureEnclaveKeyProvider()
    #endif
}
