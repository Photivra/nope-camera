# Photivra Nope Camera

A free, open-source camera app for iPhone and iPad, with Android planned. It captures a photo with as little processing as the device allows, signs it with C2PA Content Credentials, and saves it to Photos. The app makes no network calls and has no analytics.

**Status:** in development (0.x). The camera captures single-frame Bayer RAW (DNG) and saves it to Photos with only the metadata you allow, checked by reading each file back; photos are not signed yet. HEIF and JPEG are developed from the same RAW with no noise reduction, sharpening or local tone mapping, and either one global tone curve (Standard, the default) or none (Flat). The design is in issue #1; the code layout is in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and how to run the tests is in [`docs/TESTING.md`](docs/TESTING.md).

## License

The source code is licensed under the GNU General Public License, version 3 only (GPL-3.0-only); see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

The Photivra and Nope Camera names, the app icon, the logo and the wordmark are not covered by the license; see [`TRADEMARKS.md`](TRADEMARKS.md).

Third-party material is listed in [`THIRD_PARTY.md`](THIRD_PARTY.md). To contribute, see [`CONTRIBUTING.md`](CONTRIBUTING.md). Coding agents start with [`AGENTS.md`](AGENTS.md); language models can use [`llms.txt`](llms.txt).

This product includes DNG technology under license by Adobe.
