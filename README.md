# Photivra Nope Camera

A free, open-source camera app for iPhone and iPad, with Android planned. It captures a photo with as little processing as the device allows, can sign it with C2PA Content Credentials (off by default), and saves it to Photos. The app makes no network calls and has no analytics.

**Status:** 1.0.0, the first App Store release (in review before release). The camera captures single-frame Bayer RAW (DNG) and saves it to Photos with only the metadata you allow, checked by reading each file back, and signed with Content Credentials only when signing is on (off by default). HEIF and JPEG are developed from the same RAW with noise reduction, sharpening and local tone mapping turned off, and either one global tone curve (Standard, the default) or none (Flat). The design is in issue #1; the code layout is in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and how to run the tests is in [`docs/TESTING.md`](docs/TESTING.md).

## Requirements

Photivra Nope Camera supports the two latest versions of each operating system: iOS and iPadOS 26 and 27, and watchOS 26 and 27 for the Apple Watch app.

- **iPhone:** iPhone 11 and later and iPhone SE (2nd generation) and later, including iPhone Duo.
- **iPad:** iPad Pro 12.9-inch (3rd generation) and later, iPad Pro 11-inch (1st generation) and later, iPad Air (3rd generation) and later, iPad (8th generation) and later, and iPad mini (5th generation) and later.
- **Apple Watch:** Apple Watch Series 6 and later, Apple Watch SE (2nd generation) and later, and Apple Watch Ultra and later, paired with an iPhone running the app. The watch app is a remote shutter; it takes no photos itself.

These are the devices that run iOS, iPadOS and watchOS 26, as Apple lists them. Devices that run only an earlier version, such as iPhone XS, XS Max and XR, aren't supported. The app detects each camera feature at run time and shows only what the device supports.

**What was tested.** The real hardware for 1.0.0 is an iPhone 16 Pro Max (iOS 27.2.1), an iPad Air (5th generation) and an Apple Watch Series 10 (watchOS 27.2.1) paired with that iPhone. Other models, and iOS, iPadOS and watchOS 26, were tested only in Apple's Simulator, which has no real camera. Details and the known limits are in [`docs/TESTING.md`](docs/TESTING.md), "What was tested on real hardware".

## Languages

Version 1.0.0 is in English only. Spanish is in the backlog (#87). The interface is built for translation (every string is in a String Catalog, and layouts are tested with long text and right to left), and other languages are welcome in later releases.

**Translators wanted.** Translations and native-speaker reviews are welcome for later releases, including Spanish (issue #87). See [Translations](CONTRIBUTING.md#translations) in CONTRIBUTING.md and the [help wanted issue](https://github.com/Photivra/nope-camera/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22+translations).

## Website

The public site, [nope.photivra.com](https://nope.photivra.com/), holds the privacy policy, support and accessibility pages for people who use the app. It is built from `site/` with no JavaScript, cookies or analytics, and its words come from the files in this repository: the policy from [`docs/store/privacy-policy-draft.md`](docs/store/privacy-policy-draft.md), the statements from the App Store description, and the device list from "Requirements" above. To change it, edit those files or `site/`, then run `scripts/check-site.sh --preview` (it needs `npm ci --ignore-scripts` in `site/` once). The design is [`docs/design/nope-site.md`](docs/design/nope-site.md); publishing is the maintainer's and is described in [`docs/RELEASING.md`](docs/RELEASING.md).

## License

The source code is licensed under the GNU General Public License, version 3 only (GPL-3.0-only); see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

The Photivra and Nope Camera names, the app icon, the logo and the wordmark are not covered by the license; see [`TRADEMARKS.md`](TRADEMARKS.md).

Third-party material is listed in [`THIRD_PARTY.md`](THIRD_PARTY.md). To contribute, see [`CONTRIBUTING.md`](CONTRIBUTING.md). Coding agents start with [`AGENTS.md`](AGENTS.md); language models can use [`llms.txt`](llms.txt).

This product includes DNG technology under license by Adobe.
