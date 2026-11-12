# Third-party material

Every third-party component, dataset or specification used in this repository is listed here, with its license and source. Every dependency must be compatible with GPL-3.0-only.

| Component | Version | License | Source | Used for |
|---|---|---|---|---|
| Inter | 4.x | SIL Open Font License 1.1 | [rsms/inter](https://github.com/rsms/inter) | The "nope." wordmark, converted to outlines (brand artwork only; not bundled) |
| c2pa-rs (`c2pa-c-ffi`, built from source as `C2PAC.xcframework`, network features off) | 0.92.0 (tag `c2pa-v0.92.0`, commit `83eba34`) | MIT or Apache-2.0, at the user's option | [contentauth/c2pa-rs](https://github.com/contentauth/c2pa-rs) | C2PA Content Credentials: building, embedding and signing manifests (`c2pa-lib/README.md`) |
| Rust crates compiled into `C2PAC` | See `c2pa-lib/CRATES.md` | Each listed there; all GPL-3.0-only compatible (checked by cargo-deny with `c2pa-lib/deny.toml`) | crates.io | Dependencies of c2pa-rs |
| c2pa-swift (`C2PA`, vendored in `Vendor/c2pa-swift`, without its networking code) | 0.1.0 (commit `901cfbf`) | MIT or Apache-2.0, at the user's option | [contentauth/c2pa-swift](https://github.com/contentauth/c2pa-swift) | The Swift interface to the C2PA library (`NopeSigning`); changes listed in `Vendor/c2pa-swift/README.md` |
| swift-certificates (`X509`) | 1.21.1 (exact) | Apache-2.0 | [apple/swift-certificates](https://github.com/apple/swift-certificates) | Each file's self-issued certificate (`NopeSigning`); also used by c2pa-swift |
| swift-asn1 (`SwiftASN1`) | 1.7.4 (exact) | Apache-2.0 | [apple/swift-asn1](https://github.com/apple/swift-asn1) | ASN.1 types for the certificate (`NopeSigning`); also used by c2pa-swift |
| swift-crypto (`Crypto`) | 4.5.2 (exact) | Apache-2.0 | [apple/swift-crypto](https://github.com/apple/swift-crypto) | Used by c2pa-swift and swift-certificates; on Apple platforms it uses CryptoKit |

The C2PA library (c2pa-rs and its Swift wrapper) is the only non-platform dependency; the three Apple packages are its own dependencies. Their license texts must ship in the app's Licenses screen when that screen is built: MIT or Apache-2.0 for c2pa-rs and c2pa-swift (`Vendor/c2pa-swift/LICENSE-MIT`, `LICENSE-APACHE`), Apache-2.0 with each package's `NOTICE.txt` for the Apple packages, and the license of every crate in `c2pa-lib/CRATES.md`. Build tools (Rust 1.99.1 via rustup, cargo-deny 0.20.2) aren't bundled.

## Notices and terms that apply

- **Adobe DNG.** nope. writes DNG files. Notice required by Adobe's DNG specification patent license: "This product includes DNG technology under license by Adobe." It appears in `NOTICE`, `README.md` and the app's Licenses screen.
- **SF Symbols and Apple system fonts.** Used only in the app's interface, as Apple's terms allow. Never in logos, the icon or artwork.

Apple and Android platform frameworks are part of the operating system. They aren't bundled with the app, so they aren't listed.
