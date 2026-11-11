# AGENTS.md

Photivra Nope Camera™ is a free, open-source (GPLv3) camera app for iPhone and iPad, with
Android planned. It captures a photo with as little processing as the device allows, signs it
with C2PA Content Credentials, and saves it to Photos. Neither the app nor its files track the
user. The full design is in issue #1.

## Rules that always apply

1. **Evidence-based.** Every change and every suggestion must be backed by evidence: Apple or
   Android documentation, or a cited specification (DNG, EXIF, C2PA), for platform behavior; and
   a test, measurement or reproduction on a real device for any bug fix, behavior change,
   performance claim or privacy claim. Label assumptions as assumptions. Never present a guess,
   an untested API behavior or an unmeasured result as fact. If the evidence isn't there, say so
   instead of changing the code.
2. **Full test coverage.** Every feature and every fix ships with tests that cover it. This
   includes:
   - unit tests for all logic;
   - UI tests for every user flow and every state (permissions, no-RAW fallback, each privacy
     switch);
   - metadata tests asserting the exact tags written for each switch combination.

   CI enforces 100% line and branch coverage of non-UI code, and coverage may never drop. Code
   that can only run on hardware is isolated behind a protocol, tested with a fake, and verified
   on a device before release.
3. **Honesty.** These rules are not traded away for convenience:
   - As little processing as the device allows: single-frame Bayer RAW, never ProRAW or
     multi-frame capture.
   - Every photo is signed, with a fresh key per photo.
   - Nothing in the app or its files can track the user.
   - User-facing wording never claims more than is true. Say "as little processing as your phone
     allows", never "zero processing".
4. **No network, no analytics.**
   - The app makes no network calls of any kind: no server, remote configuration, update check,
     downloaded asset or certificate check.
   - Android has no `INTERNET` permission; iOS links no networking code.
   - No analytics, crash-reporting, advertising or other SDKs.
5. **The maintainer approves releases.** Get explicit approval before any action that reaches
   users: an App Store, Google Play or F-Droid submission, a release tag, or a change to signing.
   Ask for each one separately; an earlier approval does not carry over.

## Code

- **Swift and SwiftUI, iOS and iPadOS 18+.** Use native frameworks first:
  - AVFoundation for capture and DNG metadata;
  - Core Image for RAW development;
  - ImageIO with the system HEIF encoder;
  - PhotoKit, with add-only access;
  - CryptoKit with the Secure Enclave;
  - LockedCameraCapture, WidgetKit and App Intents for launch;
  - Accelerate for the histogram.
- **The only non-platform dependency is the C2PA library.** Adding a dependency needs the
  maintainer's approval, and it must be GPLv3-compatible.
- **Progressive enhancement.** Detect each capability at run time; show a feature only where
  the device supports it.
- **Prevention first:**
  - no web views, URL schemes, clipboard access or file import;
  - no code loaded at run time;
  - no private APIs;
  - no background modes;
  - least-privilege entitlements;
  - no homemade cryptography;
  - remove metadata through system APIs, never by editing bytes, and fuzz any byte-level code
    that can't be avoided;
  - strict concurrency, and no `unsafe` code outside tested, isolated spots.
- **Photos never linger.** They go from memory to Photos. Any temporary file uses complete file
  protection and is deleted immediately. Logs mark every value private, and never contain photo
  data or metadata.
- **Encoders.** Use the system HEIF/HEVC encoder only; never bundle an encoder.

## Pull requests and releases

- Work on a branch and open a pull request; merge when CI is green and coverage holds.
- Sign off commits (`git commit -s`).
- Contributions from anyone other than the maintainer are merged only after the contributor
  signs the project's contributor license agreement.
- **Before any release, a full security audit must pass:**
  - network traffic capture;
  - a metadata dump for every format and switch;
  - signature and tamper tests;
  - checks of local data, permissions, the privacy manifest, the supply chain and secrets.
- **Keep the repository clean:**
  - Never commit secrets, certificates, provisioning profiles or signing keys.
  - CI uses GitHub-hosted runners only, with Actions pinned by commit SHA.
- The name, icon, logo and wordmark are trademarks and are not covered by the GPL.

## Writing in this repository

This repository is public.
- Issues, pull requests, comments and commit messages are professional and straightforward:
  goal, scope, decisions, and when it's done. No taglines, hype or asides.
- Keep personal, business, legal and cost details out of the repository.
- Responses are concise, neutral and evidence-based.
