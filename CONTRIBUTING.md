# Contributing

Thank you for your interest in Photivra Nope Camera. The design is in issue #1, and the rules every change follows are in [`AGENTS.md`](AGENTS.md). In brief:

- **Evidence:** back every change with documentation, a specification, or a test or measurement.
- **Tests:** ship tests with every change. CI enforces full coverage of non-UI code.
- **Privacy:** keep the app free of network calls, analytics and third-party SDKs.
- **Interface:** use native platform interface elements.

## Pull requests

- Work on a branch, and open a pull request against `main`.
- Sign off each commit (`git commit -s`).
- Keep each pull request focused on one change. Describe what changed and how it was tested.
- Report security issues privately through GitHub's private vulnerability reporting, not in a public issue.

## Translations

Contributions to internationalization and translation are welcome, from new languages to native-speaker reviews of existing drafts.

- **Where the text lives:** every user-facing string is in a String Catalog (`.xcstrings`), each with a comment that explains where it appears. Honesty and privacy wording is in `Honesty.xcstrings`; it must say exactly what the English says, never more.
- **How to work:** in Xcode, Product › Export Localizations gives a standard XLIFF (`.xcloc`) file for one language; edit it in any translation tool and send it back, or edit the catalogs directly in a pull request.
- **Terms:** use Apple's own names for system features in your language (Settings, Photos, Lock Screen and so on, as iOS shows them) and the words photographers in your region use.
- **Checks:** `scripts/check-localization.sh` checks every catalog; the UI tests run with long-text and right-to-left pseudo-languages.
- **Status:** 1.0.0 ships in English; Spanish (with a Latin American variant) is drafted for 1.1.0 and needs native-speaker review. Open an issue to say which language you'd like to work on.

## Licensing of contributions

This project has one copyright holder, Shackelford Creative, LLC (see `NOTICE`). That allows the app to be distributed through app stores whose terms are not compatible with the GPL for third parties.

- **Contributions from anyone other than the maintainer are merged only after the contributor has signed the project's contributor license agreement (CLA).** Contributors keep their copyright, and grant the right to distribute their contribution under the GPL and through app stores.
- **The CLA text is not published yet.** Until it is (as `CLA.md`), outside pull requests are reviewed and discussed, but not merged.

Contributions are licensed under GPL-3.0-only (see `LICENSE`). Brand assets are excluded (see `TRADEMARKS.md`).
