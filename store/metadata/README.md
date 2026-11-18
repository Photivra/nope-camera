# App Store listing text

One folder per App Store locale, one file per App Store Connect field (`name.txt`,
`subtitle.txt`, `promotional_text.txt`, `description.txt`, `keywords.txt`), in the layout
fastlane `deliver` reads. The files hold only the field text, so this page records their review
status.

Version 1.0.0 is listed in English and Spanish (issues #86 and #87). The Spanish listings,
`es-ES` and `es-MX` (from the app's `es` and `es-419` strings), are added together with the
Spanish strings; as of 2026-11-18 they are drafts on branch `spanish-1.1.0`, not on this branch.
Other languages come back in later releases; their earlier draft translations are in the git
history.

Field limits, the rules the text follows, and the claim table (which features each sentence
depends on) are in [`docs/store/README.md`](../../docs/store/README.md).

## Review status

**Every file here is a draft that needs human review.** Nothing is approved for submission.
Before a release, the maintainer removes any sentence whose feature isn't in the release.

| Locale | Language | Source | Status |
|---|---|---|---|
| `en-US` | English (U.S.) | Written by the project | Draft, needs human review |
| `es-ES` | Spanish (Spain) | Translation of `en-US` (issue #87) | Not on this branch yet; needs native-speaker review |
| `es-MX` | Spanish (Mexico) | `es-ES` with the app's `es-419` wording (issue #87) | Not on this branch yet; needs native-speaker review |

## Notes for reviewers

- Keep "nope." exactly as written: lowercase, with the period. "Photivra Nope Camera" is never
  translated.
- Apple setting and feature names (App Privacy Report, Voice Control, Settings) must match the
  names Apple uses on the current iOS version.
- The Honesty screen's name must match the app's own name for that screen.
