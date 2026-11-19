# App Store listing drafts

Status: **draft, needs human review.** Nothing here is approved for submission. The English text
is a draft for the maintainer. Version 1.0.0 is listed in English (U.S.) only, `en-US` (issue
#86). The Spanish listings, `es-ES` and `es-MX` from the app's `es` and `es-419` strings, are in
the backlog with the Spanish strings (issue #87); they stay drafts on branch `spanish-1.1.0`, and
every Spanish file needs a native-speaker review before it ships (AGENTS.md, "Localization").

The listing text itself lives in [`store/metadata/<locale>/`](../../store/metadata/README.md)
(AGENTS.md, "Localization"), one file per App Store Connect field, with its review status in
that folder's README. This folder holds the rules, limits and claim table for that text, and
the other submission answers:

| File | What it holds |
|---|---|
| [`store/metadata/`](../../store/metadata/README.md) | Name, subtitle, promotional text, description and keywords: English (`en-US`) for 1.0.0; Spanish (`es-ES`, `es-MX`) in the backlog (issue #87) |
| [`app-privacy-label.md`](app-privacy-label.md) | App Store Connect App Privacy answers ("Data Not Collected") |
| [`accessibility-label.md`](accessibility-label.md) | Accessibility Nutrition Label answers, and the evidence each one needs |
| [`privacy-policy-draft.md`](privacy-policy-draft.md) | The privacy policy, for the maintainer to publish |
| [`STORE-PAGE-PLAN.md`](STORE-PAGE-PLAN.md) | The product page plan for 1.0.0 (proposal): each App Store page feature, screenshot and preview storyboards, the assets to make, the App Store Connect steps and the maintainer's decisions. Section 12 designs the Rate or Review row for the About screen (decided 2026-11-19, not built): a third About link, which opens the App Store's write-review page; the app shows no rating prompt |

## Field limits (App Store Connect)

| Field | Limit | Notes |
|---|---|---|
| Name | 30 characters | "Photivra Nope Camera" (20) in every language; never translated |
| Subtitle | 30 characters | "RAW photos. No tracking." (maintainer's choice, 24); translations keep the same meaning within 30 |
| Promotional text | 170 characters | Can be changed without a new build |
| Description | 4,000 characters | Plain text, no markup |
| Keywords | 100 characters | Comma separated, no spaces needed; words in the name are already indexed, so "camera", "Photivra" and "nope" are left out; no other apps' names |

Source: [App Store Connect: app information](https://developer.apple.com/help/app-store-connect/reference/app-information/)
and [platform version information](https://developer.apple.com/help/app-store-connect/reference/platform-version-information/).

## Rules the text follows

- Positioning from issue #1: easy, with no setup; as little processing as the phone allows; and
  privacy. No comparisons that name other apps.
- Wording from `docs/research/privacy-claims.md` and issue #1, "Wording rules": "as little
  processing as the camera allows" in the listing (owner decision, 2026-11-18), never "zero processing"; the signature "shows whether the
  file has been changed", never that the photo is real or who took it.
- The listing names the app "Photivra Nope Camera", then "the app". "nope." appears only in
  quoted interface text, lowercase with its period in every language; "Photivra" has no period.
- No "tested" or "verified" claims in the listing or the app. What was tested goes in the
  README, `docs/TESTING.md` and the App Review notes below.
- Translations claim no more than the English.
- **Names of other companies' features:** the text may use "Content Credentials", "App Privacy
  Report", "iOS" and "VoiceOver" as plain, factual names (maintainer's decision, 2026-11-12),
  never with their logos. ProRAW, Voice Control and Settings are used the same way.

## Claims and what they depend on

The description describes the planned 1.0 app. As of 2026-11-18, saving to Photos with the
metadata allowlist and fail-closed read-back, HEIF and JPEG development, and Content
Credentials signing, the settings screens (formats and Privacy), the Honesty screen, the Last
Photo viewer and What's in This Photo are merged and tested in the Simulator, **but the release
build is not yet checked on a device**, and the Honesty and privacy wording still needs fluent
human review. The last photo's details are on What's in This Photo, not on the Honesty screen.
**Every claim below must be shipped and verified, on a device where the table says so, before
the listing is submitted; remove any sentence whose feature isn't in the release.**

| # | Claim in the description | Depends on | Verified by |
|---|---|---|---|
| C1 | On a lens that can save RAW, single-frame Bayer RAW (DNG), never ProRAW or merged frames | Capture core and saving to Photos (merged; device check pending) | Tag check on a device; `docs/PRIVACY.md` |
| C2 | A lens without unprocessed RAW is labeled before the shot (unless the person turns the marker off) and after it | The "Processed" marker before the shot, on by default and hidden only if the person turns it off, and its processing note (issue #80); the photo's details and, when signed, its manifest after (to confirm) | UI tests (`ProcessedMarkerUITests.swift`); signature check |
| C3 | Optional HEIF or JPEG developed by the app from the same RAW, with no noise reduction, sharpening or local tone mapping | `NopeDevelop` (merged; device check pending) | Development tests; output review |
| C4 | No networking code, no network connections, no analytics, ads or accounts | Merged; the C2PA library is built without network features and CI checks the library and the linked app for networking code (`scripts/check-no-networking.sh`) | `docs/SECURITY_AUDIT.md` checks 3, 7 and 8 |
| C5 | App Privacy Report lists no domains for the app | C4 | Audit check 8 on a device, over 7 days |
| C6 | Optional details removed by default; you choose what each photo keeps | Metadata allowlist and fail-closed read-back (merged; device check pending); the Privacy settings screen where you choose (merged; device check pending) | Audit check 9 |
| C7 | Location off by default; Focus on Faces off by default, so autofocus and auto exposure don't follow faces (the listing doesn't say face detection is off: iOS may still detect faces in the viewfinder, as the Honesty screen says) | Location switch off by default; asks for "while using the app" access when turned on; writes latitude, longitude and altitude only (`LocationTagging`, issue #43; device check pending); Focus on Faces off by default (issue #80) | Audit checks 9 and 16; unit tests (`NopeSettingsTests`) |
| C8 | Add-only Photos access; can't see existing photos | Add-only saving (merged; device check pending) | Audit check 16 |
| C9 | Signing off by default; when it's on, every photo is signed with a new key, signatures can't link photos, and a signature names the app and its version as the maker, which is not proof (each file certifies its own key, so anyone could make a file that says the same) | Signing off by default (issue #80); `NopeSigning` with C2PA (merged; device check of Secure Enclave signing pending) | Audit check 10; unit tests (`MetadataSettingsTests`) |
| C10 | What's in This Photo lists the last photo's details; the Honesty screen says what the device may still do and what no app can remove | What's in This Photo, opened from the last photo (merged); Honesty screen in Settings (merged: what the app never does, what iOS may still do, what no app can remove) | UI tests; human review of `Honesty.xcstrings` |
| C11 | Designed to work with VoiceOver, Voice Control and the largest text sizes (a design aim, not a declared Accessibility Nutrition Label feature until the manual pass is done); volume buttons as a shutter | Volume and Camera Control shutter (merged); every 1.0 screen passing audits and the manual pass (not done) | `accessibility-label.md` |
| C12 | Free and open source under GPL-3.0 | True today | `LICENSE` |

The description deliberately leaves out features planned for 1.0 that are harder to verify or
not built yet (Siri and Shortcuts, lock-screen launch, self-timer, selfie framing), and manual
controls, which are merged but not yet device-checked. Add a sentence for each only after it ships and is verified.

### Added to 1.0.0 on 2026-11-18: pending, no claim yet

These issues joined milestone 1.0.0 on 2026-11-18; #87 has since moved to the backlog. The others are
built, none is checked on a device yet, so the listing (every language, the promotional text and
the keywords) says nothing about them. A sentence is added only after the feature is merged and
passes the checks in the last column; until then each row stays **pending**.

| Issue | Feature | State | Before any listing sentence |
|---|---|---|---|
| #82 | Siri, Shortcuts and assistant actions through App Intents, with Settings › Privacy › Assistant Access (off by default; Ask First: Every Action by default) | Pending: built, device checks not done | Unit tests of each Ask First level against each intent; the entry-point test; the device checks listed in the issue (locked phone, iPhone Mirroring, camera stops off screen); App Shortcuts phrases in English and Spanish; Honesty screen and `docs/PRIVACY.md` describe the setting. Any wording follows "what the app protects" and "what the system controls" in the issue, and never says assistants can't reach the camera |
| #87 | Spanish (`es`, with `es-419` overrides) in the app and the listing | Moved to the backlog: drafts on branch `spanish-1.1.0`, not in 1.0.0; strings added since need translating | `scripts/check-localization.sh` with English and Spanish; native-speaker review of `Honesty.xcstrings` and the `es-ES` and `es-MX` listings. Until then the listing doesn't mention languages |
| #88 | Settings search drawn in red in Night Mode | Pending: built, device checks not done | The all-red pixel check on Settings with search shown; audits in Night Mode |
| #90 | Focus bracketing, each frame a separate signed RAW, never merged | Pending: built (`docs/design/BRACKETING.md`, sections 5 and 8), device checks not done | Unit and UI tests; the per-lens device checks in the design. A sentence may say "never merged" only after the tag check and signature check on bracket frames |
| #95 | Pinch on the viewfinder to switch lenses, with no digital zoom | Pending: built (`docs/design/pinch-lens.md`), device tuning not done | Device tuning of the thresholds; any sentence says "switch lenses", never "zoom" (C1 and "no digital zoom" stay true) |
| #97 | Keep the screen on while the camera is open, off by default | Pending: built, device checks not done | UI tests; an energy profile with it on (`docs/TESTING.md`); any sentence says it is off by default |

Claims C1 to C12 don't change with these issues, with two notes: C4 and C5 must be rechecked
on the build that includes #82 (App Intents run on the device; Siri itself is Apple's, as the
Honesty screen and the privacy policy already say). C11 is rechecked in Spanish at the largest
text sizes when #87 ships.

## App Review notes (draft)

For the App Review Information notes field in App Store Connect, and for TestFlight's What to
Test. Draft, for the maintainer to review.

- **What was tested.** The real hardware for 1.0.0 is an iPhone 16 Pro Max (iOS 27.2.1) and an
  iPad Air (5th generation). Other iPhone and iPad models, iOS and iPadOS 26 and the Apple Watch
  app were tested only in Apple's Simulator (`docs/TESTING.md`, "What was tested on real
  hardware").
- **No network.** The app contains no networking code and opens no network connection. The two
  links in the app, the privacy policy and the source code on the About screen, open in the
  browser when the person taps them.
- **Photos access is add-only.** The app never asks to read the photo library. The Last Photo
  button can open the Photos app with the `photos-redirect://` address; it only brings Photos to
  the front and reads nothing. Apple doesn't document this address (`docs/TESTING.md`, "On-device
  checks").
- **Camera and location.** Camera access is asked for before the camera first opens. Location is off by
  default and asked for only when the person turns on Location in the app's settings.
- **Signing** is off by default; when turned on, each photo is signed with a new key made on the
  device.
- **TestFlight builds** (What to Test): TestFlight itself collects crash reports, usage and
  feedback with screenshots. The privacy statements in the app and the listing describe the App
  Store build.

## Other App Store Connect fields (maintainer)

- **Privacy policy URL:** required even with no data collected:
  `https://nope.photivra.com/privacy/`, the page the maintainer publishes from
  `privacy-policy-draft.md`. The app's About screen links to the same address (App Review
  Guideline 5.1.1(i)); it opens in the browser.
- **Support URL:** required: `https://nope.photivra.com/support/`, a page the maintainer publishes
  on the same site as the privacy policy.
- **Copyright:** "2026 Shackelford Creative, LLC" (`store/metadata/en-US/copyright.txt`), the copyright holder named in `NOTICE`.
- **Category:** Photo & Video.
- **Age rating:** the questionnaire answers are all "None" for an app with no user-generated
  content shown, no web access and no purchases (to confirm in App Store Connect).
- **Export compliance: No** (maintainer's decision, 2026-11-12). The app uses cryptography only
  to sign photos (authentication and integrity), through the operating system's CryptoKit and
  the C2PA library, and encrypts no data, so it is exempt. The app's Info.plist should set
  `ITSAppUsesNonExemptEncryption` to `NO`, so App Store Connect doesn't ask for
  each build.
  Recheck if any release adds encryption of data. See Apple's
  [export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
  and [Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).
