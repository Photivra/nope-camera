# ``NopeSigning``

C2PA Content Credentials for every saved file, with a new key for each file, fully offline.

## Overview

`NopeSigning` implements `NopeCore`'s `PhotoSigning` protocol with ``ContentCredentialsSigner``.
For each file (DNG, HEIF or JPEG) it:

1. creates a new P-256 key: in the Secure Enclave on a device (``SecureEnclaveKeyProvider``), or
   in software in the Simulator only (``SimulatorSoftwareKeyProvider``, compiled only for the
   Simulator);
2. issues an anonymous certificate to that key, signed by the key itself;
3. embeds a manifest that says only what nope. did, and signs it with the key (ES256), with no
   timestamp authority and no network;
4. releases the key, which is never stored or used again.

The signature proves the file hasn't changed since nope. signed it. Because the certificate
isn't chained to a trusted certificate authority, validators report the signer as untrusted;
that is expected. Nothing in the signature identifies the person or the device, and no two
files share a key.

```swift
let signer = ContentCredentialsSigner(
    keyProvider: platformKeyProvider(), generator: ClaimGenerator(version: "0.1.0"))
let signed = try await signer.sign(dngBytes, as: .singleFrameRAW)
```

Related documentation in the repository: `docs/PRIVACY.md` ("Content Credentials": exactly what
a signature contains and what it adds to each format), `docs/ARCHITECTURE.md`,
`docs/TESTING.md` ("Checking signatures") and `docs/research/c2pa-signing.md`.

## Topics

### Signing

- ``ContentCredentialsSigner``
- ``ClaimGenerator``

### Keys

- ``PerPhotoSigningKey``
- ``SigningKeyProvider``
- ``SecureEnclaveKeyProvider``
- ``SimulatorSoftwareKeyProvider``
- ``platformKeyProvider()``
