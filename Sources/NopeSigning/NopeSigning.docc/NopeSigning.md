# ``NopeSigning``

C2PA signing with a fresh Secure Enclave key for every photo.

## Overview

`NopeSigning` signs each photo with a key created for that photo alone and then discarded, so no
two photos can be linked through their signatures. In the app the key is a Secure Enclave key;
tests use CryptoKit's software key.

The scaffold contains the per-photo signer. The C2PA manifest, built with the C2PA library,
follows (see `docs/research/c2pa-signing.md`).

Related documentation: `docs/ARCHITECTURE.md` and `docs/PRIVACY.md` in the repository.

## Topics

### Signing

- ``PerPhotoSigner``
- ``PerPhotoSigningKey``
- ``SignedData``
- ``SigningError``
