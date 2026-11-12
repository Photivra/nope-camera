# App Store listing text

One folder per App Store locale, one file per App Store Connect field (`name.txt`,
`subtitle.txt`, `promotional_text.txt`, `description.txt`, `keywords.txt`), in the layout
fastlane `deliver` reads. The files hold only the field text, so this page records their review
status.

Field limits, the rules the text follows, and the claim table (which features each sentence
depends on) are in [`docs/store/README.md`](../../docs/store/README.md).

## Review status

**Every file here is a draft that needs human review.** Nothing is approved for submission.
Before a release, a fluent human reviews every language (AGENTS.md, "Localization"), and the
maintainer removes any sentence whose feature isn't in the release.

| Locale | Language | Source | Status |
|---|---|---|---|
| `en-US` | English (U.S.) | Written by the project | Draft, needs human review |
| `ja` | Japanese | AI translation of `en-US` | Draft, needs human review |
| `es-ES` | Spanish (Spain) | AI translation of `en-US` | Draft, needs human review |
| `fr-FR` | French | AI translation of `en-US` | Draft, needs human review |
| `de-DE` | German | AI translation of `en-US` | Draft, needs human review |
| `ko` | Korean | AI translation of `en-US` | Draft, needs human review |
| `zh-Hant` | Chinese (Traditional) | AI translation of `en-US` | Draft, needs human review |
| `zh-Hans` | Chinese (Simplified) | AI translation of `en-US` | Draft, needs human review |
| `pt-BR` | Portuguese (Brazil) | AI translation of `en-US` | Draft, needs human review |
| `it` | Italian | AI translation of `en-US` | Draft, needs human review |
| `nl-NL` | Dutch | AI translation of `en-US` | Draft, needs human review |

The app's `es` and `fr` localizations map to the App Store's `es-ES` and `fr-FR`. Whether to add
`es-MX` and `fr-CA` copies is open.

## Notes for reviewers

- Keep "nope." exactly as written: lowercase, with the period, unchanged in translation.
  "Photivra Nope Camera" is never translated.
- Apple setting and feature names (App Privacy Report, Voice Control, Settings) must match the
  names Apple uses in that language on the current iOS version.
- The Honesty screen's name must match the app's own translation once that screen ships.
- A translation must not claim more than the English.
