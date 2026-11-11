# Third-party material

Every third-party component, dataset or specification used in this repository is listed here, with its license and source. Every dependency must be compatible with GPL-3.0-only.

| Component | Version | License | Source | Used for |
|---|---|---|---|---|
| Inter | 4.x | SIL Open Font License 1.1 | [rsms/inter](https://github.com/rsms/inter) | The "nope." wordmark, converted to outlines (brand artwork only; not bundled) |

The C2PA library is planned as the only non-platform dependency. It will be listed here when it's added.

## Notices and terms that apply

- **Adobe DNG.** nope. writes DNG files. Notice required by Adobe's DNG specification patent license: "This product includes DNG technology under license by Adobe." It appears in `NOTICE`, `README.md` and the app's Licenses screen.
- **SF Symbols and Apple system fonts.** Used only in the app's interface, as Apple's terms allow. Never in logos, the icon or artwork.
- **Planned dependencies.** C2PA (`c2pa-swift`, MIT or Apache-2.0) and the Apple packages it uses (`swift-certificates`, `swift-asn1`, `swift-crypto`, Apache-2.0). They will be listed in the table, with versions, when added.

Apple and Android platform frameworks are part of the operating system. They aren't bundled with the app, so they aren't listed.
