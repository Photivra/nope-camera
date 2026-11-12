# Third-party material

Every third-party component, dataset or specification used in this repository is listed here, with its license and source. Every dependency must be compatible with GPL-3.0-only.

| Component | Version | License | Source | Used for |
|---|---|---|---|---|
| Inter | 4.x | SIL Open Font License 1.1 | [rsms/inter](https://github.com/rsms/inter) | The "nope." wordmark, converted to outlines (brand artwork only; not bundled) |
| c2pa-swift (`C2PA`, with the prebuilt `C2PAC.xcframework` built from c2pa-rs 0.91.7) | 0.0.16 (exact) | MIT or Apache-2.0, at the user's option | [contentauth/c2pa-swift](https://github.com/contentauth/c2pa-swift) | C2PA Content Credentials: building, embedding and signing manifests (`NopeSigning`) |
| swift-certificates (`X509`) | 1.21.1 (exact) | Apache-2.0 | [apple/swift-certificates](https://github.com/apple/swift-certificates) | Each file's self-issued certificate (`NopeSigning`); also used by c2pa-swift |
| swift-asn1 (`SwiftASN1`) | 1.7.4 (exact) | Apache-2.0 | [apple/swift-asn1](https://github.com/apple/swift-asn1) | ASN.1 types for the certificate (`NopeSigning`); also used by c2pa-swift |
| swift-crypto (`Crypto`) | 4.5.2 (pinned in `Package.resolved`) | Apache-2.0 | [apple/swift-crypto](https://github.com/apple/swift-crypto) | Used by c2pa-swift and swift-certificates; on Apple platforms it uses CryptoKit |

The C2PA library is the only non-platform dependency; the three Apple packages are its own dependencies. Their license texts must ship in the app's Licenses screen (MIT or Apache-2.0 for c2pa-swift, Apache-2.0 with each package's `NOTICE.txt` for the Apple packages) when that screen is built. The prebuilt `C2PAC.xcframework` also contains the Rust crates c2pa-rs depends on; their licenses are listed in the c2pa-rs repository and must be reviewed and included with them.

## Notices and terms that apply

- **Adobe DNG.** nope. writes DNG files. Notice required by Adobe's DNG specification patent license: "This product includes DNG technology under license by Adobe." It appears in `NOTICE`, `README.md` and the app's Licenses screen.
- **SF Symbols and Apple system fonts.** Used only in the app's interface, as Apple's terms allow. Never in logos, the icon or artwork.

Apple and Android platform frameworks are part of the operating system. They aren't bundled with the app, so they aren't listed.
