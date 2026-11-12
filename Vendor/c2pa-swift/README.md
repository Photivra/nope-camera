# c2pa-swift (vendored, trimmed)

The Swift wrapper of the C2PA library, copied from
[contentauth/c2pa-swift](https://github.com/contentauth/c2pa-swift) release **v0.1.0**
(commit `901cfbf371a5c1caaf2674732f6e282294388ab5`, folder `Library/Sources`), and built as the
`C2PA` target of `Package.swift`. It is used by `NopeSigning` only.

License: MIT or Apache-2.0, at the user's option (`LICENSE-MIT`, `LICENSE-APACHE`). Each file
keeps its original license header. Copyright (c) 2025 Guardian Project and the c2pa-swift
contributors.

## Why it is vendored

nope. links no networking code (AGENTS.md, "No network, no analytics"). The upstream wrapper
contains `URLSession` code, so it is copied here without it, and it links the network-free C2PA
library built by `scripts/build-c2pa-lib.sh` (`c2pa-lib/README.md`) instead of upstream's
prebuilt one.

## Changes from upstream v0.1.0

Changed files carry a `nope.:` comment where code was removed.

- Removed `WebServiceSigner.swift` (a remote signer over `URLSession`).
- `C2PAContext.swift`: removed the initializer that resolves HTTP requests with a `URLSession`
  (`init(settings:signer:onProgress:urlSession:)`) and its documentation link.
- `Builder.swift` and `Manifest/ManifestValidator.swift`: removed the `NSLog` calls that logged
  manifest validation warnings and errors. nope. logs nothing about photos or their metadata.
- `Signer.swift`: removed the documentation link to `WebServiceSigner`.
- Documentation examples in `Reader.swift`, `C2PAContext.swift`,
  `Manifest/ManifestValidationResult.swift` and `Manifest/ManifestValidator.swift`: `print(` is
  written `show(`, so the repository's logging check stays strict.
- Removed the DocC catalog `C2PA.docc`.

No other line is changed. To update, copy the new release's `Library/Sources` over
`Sources/C2PA`, reapply these changes, and update the version here, in `THIRD_PARTY.md` and in
`c2pa-lib/versions.env` (the wrapper must match the c2pa-rs version it was written for).
