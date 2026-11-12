# App Store listing drafts

Status: **draft, needs human review.** Nothing here is approved for submission. The English text
is a draft for the maintainer; every other language is an AI translation that a fluent human
must review before release (AGENTS.md, "Localization").

The listing text itself lives in [`store/metadata/<locale>/`](../../store/metadata/README.md)
(AGENTS.md, "Localization"), one file per App Store Connect field, with its review status in
that folder's README. This folder holds the rules, limits and claim table for that text, and
the other submission answers:

| File | What it holds |
|---|---|
| [`store/metadata/`](../../store/metadata/README.md) | Name, subtitle, promotional text, description and keywords for the 11 launch languages, in 13 App Store locales (Spanish and French in two regions each) |
| [`app-privacy-label.md`](app-privacy-label.md) | App Store Connect App Privacy answers ("Data Not Collected") |
| [`accessibility-label.md`](accessibility-label.md) | Accessibility Nutrition Label answers, and the evidence each one needs |
| [`privacy-policy-draft.md`](privacy-policy-draft.md) | The privacy policy, for the maintainer to publish |

## Field limits (App Store Connect)

| Field | Limit | Notes |
|---|---|---|
| Name | 30 characters | "Photivra Nope Camera" (20) in every language; never translated |
| Subtitle | 30 characters | "RAW photos. No tracking." (maintainer's choice, 24); translations keep the same meaning within 30 |
| Promotional text | 170 characters | Can be changed without a new build |
| Description | 4,000 characters | Plain text, no markup |
| Keywords | 100 characters | The drafts give both characters and UTF-8 bytes; the Japanese and Korean keywords are over 100 bytes, so shorten them if App Store Connect rejects them. Comma separated, no spaces needed; words in the name are already indexed, so "camera", "Photivra" and "nope" are left out; no other apps' names |

Source: [App Store Connect: app information](https://developer.apple.com/help/app-store-connect/reference/app-information/)
and [platform version information](https://developer.apple.com/help/app-store-connect/reference/platform-version-information/).

## Rules the text follows

- Positioning from issue #1: easy, with no setup; as little processing as the phone allows; and
  privacy. No comparisons that name other apps.
- Wording from `docs/research/privacy-claims.md` and issue #1, "Wording rules": "as little
  processing as your phone allows", never "zero processing"; the signature "shows whether the
  file has been changed", never that the photo is real or who took it.
- "nope." stays lowercase with its period in every language; "Photivra" has no period.
- Translations claim no more than the English.
- **Names of other companies' features:** the text may use "Content Credentials", "App Privacy
  Report", "iOS" and "VoiceOver" as plain, factual names (maintainer's decision, 2026-11-12),
  never with their logos. ProRAW, Voice Control and Settings are used the same way.

## Claims and what they depend on

The description describes the planned 1.0 app. As of 2026-11-12, saving to Photos with the
metadata allowlist and fail-closed read-back, HEIF and JPEG development, and Content
Credentials signing are merged and tested in the Simulator, **but not yet checked on a
device**. There is no settings screen and no Honesty screen yet. **Every claim below must be
shipped and verified, on a device where the table says so, before the listing is submitted;
remove any sentence whose feature isn't in the release.**

| # | Claim in the description | Depends on | Verified by |
|---|---|---|---|
| C1 | Single-frame Bayer RAW (DNG), never ProRAW or merged frames | Capture core and saving to Photos (merged; device check pending) | Tag check on a device; `docs/PRIVACY.md` |
| C2 | A lens without unprocessed RAW is labeled before and after the shot | Fallback badge (merged); how the saved file and signature record it (to confirm) | UI tests; signature check |
| C3 | Optional HEIF or JPEG developed by nope. from the same RAW, with no noise reduction, sharpening or local tone mapping | `NopeDevelop` (merged; device check pending) | Development tests; output review |
| C4 | No networking code, no network connections, no analytics, ads or accounts | Merged; the C2PA library is built without network features and CI checks the library and the linked app for networking code (`scripts/check-no-networking.sh`) | `docs/SECURITY_AUDIT.md` checks 3, 7 and 8 |
| C5 | App Privacy Report lists no domains for nope. | C4 | Audit check 8 on a device, over 7 days |
| C6 | Optional details removed by default; you choose what each photo keeps | Metadata allowlist and fail-closed read-back (merged; device check pending); the settings screen where you choose (not built) | Audit check 9 |
| C7 | Location off by default | No location is supplied today, so none is written; the location switch has no effect yet (not built) | Audit checks 9 and 16 |
| C8 | Add-only Photos access; can't see existing photos | Add-only saving (merged; device check pending) | Audit check 16 |
| C9 | Every photo signed with a new key; signatures can't link photos | `NopeSigning` with C2PA (merged; device check of Secure Enclave signing pending) | Audit check 10 |
| C10 | The Honesty screen lists the last photo's details, what the phone may still do, and what no app can remove | Honesty screen (not built) | UI tests; human review of `Honesty.xcstrings` |
| C11 | VoiceOver, Voice Control, the largest text sizes; volume buttons as a shutter | Volume and Camera Control shutter (merged); every 1.0 screen passing audits and the manual pass (not done) | `accessibility-label.md` |
| C12 | Free and open source under GPL-3.0 | True today | `LICENSE` |

The description deliberately leaves out features planned for 1.0 that are harder to verify or
not built yet (Siri and Shortcuts, lock-screen launch, self-timer, selfie framing), and manual
controls, which are merged but not yet device-checked. Add a sentence for each only after it ships and is verified.

## Other App Store Connect fields (maintainer)

- **Privacy policy URL:** required even with no data collected; the page the maintainer
  publishes from `privacy-policy-draft.md`.
- **Support URL:** required; for example the repository's issues page.
- **Copyright:** the copyright holder named in `NOTICE`.
- **Category:** Photo & Video.
- **Age rating:** the questionnaire answers are all "None" for an app with no user-generated
  content shown, no web access and no purchases (to confirm in App Store Connect).
- **Export compliance: No** (maintainer's decision, 2026-11-12). The app uses cryptography only
  to sign photos (authentication and integrity), through the operating system's CryptoKit and
  the C2PA library, and encrypts no data, so it is exempt. The app's Info.plist should set
  `ITSAppUsesNonExemptEncryption` to `NO` (not set yet), so App Store Connect doesn't ask for
  each build.
  Recheck if any release adds encryption of data. See Apple's
  [export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
  and [Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).
