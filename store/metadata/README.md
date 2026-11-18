# App Store listing text

One folder per App Store locale, one file per App Store Connect field (`name.txt`,
`subtitle.txt`, `promotional_text.txt`, `description.txt`, `keywords.txt`), in the layout
fastlane `deliver` reads. The files hold only the field text, so this page records their review
status.

Version 1.0.0 is listed in English only (issue #86). A listing in another language is added
together with that language in the app; the earlier draft translations are in the git history.

Field limits, the rules the text follows, and the claim table (which features each sentence
depends on) are in [`docs/store/README.md`](../../docs/store/README.md).

## Review status

**Every file here is a draft that needs human review.** Nothing is approved for submission.
Before a release, the maintainer removes any sentence whose feature isn't in the release.

| Locale | Language | Source | Status |
|---|---|---|---|
| `en-US` | English (U.S.) | Written by the project | Draft, needs human review |

## Notes for reviewers

- Keep "nope." exactly as written: lowercase, with the period. "Photivra Nope Camera" is never
  translated.
- Apple setting and feature names (App Privacy Report, Voice Control, Settings) must match the
  names Apple uses on the current iOS version.
- The Honesty screen's name must match the app's own name for that screen.
