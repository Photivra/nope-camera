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
- **Native interface elements:** use standard SwiftUI controls and system styling wherever one
  exists:
  - **Controls:** `Toggle`, `Picker`, `Slider`, `Stepper`, `Button`, `Menu`.
  - **Structure:** `Form` and `List` for settings, `NavigationStack`, sheets, alerts and
    confirmation dialogs.
  - **Styling:** SF Symbols, system fonts with Dynamic Type, semantic system colors and
    materials, and standard haptics (`sensoryFeedback`).
  - **Custom drawing** is allowed only where no system element exists (the viewfinder overlays,
    shutter button, histogram and focus peaking). It must still support VoiceOver, Dynamic Type,
    Reduce Motion, Increase Contrast, and light and dark appearance.
  - Brand color is applied only through `tint`. Don't restyle system controls.
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

## Accessibility

Nope aims to be fully usable by everyone, including blind, low-vision, deaf, and motor- and
cognitively-impaired photographers. The baseline is Apple's Human Interface Guidelines for
accessibility and WCAG 2.2 AA. Nope must qualify for every App Store Accessibility Nutrition
Label that applies to it: VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate
Without Color Alone, Sufficient Contrast and Reduced Motion.

- **VoiceOver.**
  - Every element has a label, a value and a hint where needed, and controls are grouped
    logically.
  - The viewfinder announces the lens, the format (RAW or the HEIF fallback), and exposure
    warnings.
  - Capture results are announced: "Photo saved and signed", or what went wrong.
  - Manual controls are adjustable elements (swipe up or down to change them).
  - The Honesty screen and settings read in a sensible order.
- **Taking photos without seeing the screen.**
  - The shutter works with the volume buttons and the Camera Control button.
  - Haptics confirm the shutter and signal a lens or mode change.
  - A self-timer (off, 3 s, 10 s) is available.
  - For selfies, optional on-device spoken framing guidance ("one face, slightly left") uses
    Vision. It is analyzed in memory only: never stored, never written to the photo, and
    disclosed on the Honesty screen.
- **Voice Control, Switch Control and Full Keyboard Access.** Every action is reachable. Voice
  Control names match the visible labels ("Take photo", "Settings"). App Intents provide "Take a
  photo with Nope" for Siri and Shortcuts.
- **Larger Text.**
  - All text uses Dynamic Type, up to the largest accessibility sizes, with no clipping or
    truncation of essential text.
  - Camera controls reflow, or move into a scrolling panel, at accessibility sizes.
  - The Large Content Viewer covers controls that can't grow.
- **Vision settings.**
  - Text and icons meet WCAG contrast (4.5:1 for text, 3:1 for icons and controls), including
    over the viewfinder, where they get a solid backing.
  - Respect Increase Contrast, Bold Text, Button Shapes, Reduce Transparency, Smart Invert
    (the viewfinder and photos are excluded from inversion) and Differentiate Without Color.
    Every status has text or a symbol, never color alone.
- **Motion and timing.** Respect Reduce Motion (crossfades instead of slides, no animated
  badges). Nothing important disappears on a timer; a confirmation stays until it has been
  announced.
- **Touch targets** are at least 44 × 44 points. The shutter is larger and reachable one-handed
  in both orientations.
- **Hearing.** No information is conveyed by sound alone. The shutter sound follows the system.
- **Cognitive.** Plain language, a predictable layout, one primary action per screen, and no
  surprise modes. Manual controls stay hidden unless turned on.
- **Testing is part of full coverage.**
  - UI tests run `performAccessibilityAudit()` on every screen and state.
  - Tests cover VoiceOver labels, the largest accessibility text size and right-to-left layout.
  - Before each release, a manual pass with VoiceOver, Voice Control, Switch Control and the
    largest text size is part of the release audit.
  - An accessibility failure is a release blocker.

## Localization

The app is localized from the first release in English (`en`, the development language),
Japanese (`ja`), Spanish (`es`), French (`fr`), German (`de`), Korean (`ko`), Chinese
Traditional (`zh-Hant`), Chinese Simplified (`zh-Hans`), Portuguese (Brazil) (`pt-BR`),
Italian (`it`) and Dutch (`nl`).
- **Every user-facing string** goes in a String Catalog (`Localizable.xcstrings`), with a comment
  that gives translators context. This includes accessibility labels, alerts, permission prompts
  (`InfoPlist.xcstrings`) and the lock-screen and Control Center controls. No hard-coded
  user-facing text.
- **Use system formatting** for numbers, units, dates and plurals (`FormatStyle`, plural
  variants in the catalog). Never concatenate translated fragments; use whole sentences with
  placeholders.
- **The layout adapts:**
  - no fixed widths for text, and text expands for long languages;
  - right-to-left ready, with leading and trailing rather than left and right, even though no
    right-to-left language ships yet;
  - tested with the pseudo-language and right-to-left pseudo-language launch arguments.
- **Translations may start as AI translations.** Mark every AI-translated string "needs review"
  in its catalog, never "translated", until a fluent human has checked it.
- **Honesty wording is kept apart.** The Honesty screen, privacy settings, signature and
  processing claims go in their own catalog table, `Honesty.xcstrings`; store listings go in
  `store/metadata/<locale>/`.
  - These texts must not claim more in translation than the English does.
  - Before a release, every string in `Honesty.xcstrings` and every store listing file in every
    language must be reviewed by a fluent human.
  - Other interface strings may ship AI-translated and are reviewed when a reviewer is available.
- **A pull request that adds or changes a user-facing string** adds the translations (AI or
  human) and marks them "needs review". No string ships untranslated.
- **Store listings** (name, subtitle, description, keywords, screenshots) are localized for
  every app language.

## Security checks

Fast checks run on every pull request inside the required `repo-checks` job. They take seconds
and need no build.
- **`scripts/check-security.sh` fails the pull request** when app code:
  - uses networking, web views, or analytics, crash-reporting or advertising SDKs;
  - uses `print`, `NSLog` or `debugPrint` (use `Logger` with private values);
  - uses `Unsafe` pointer APIs outside the files listed in `security/allowed-unsafe.txt`;
  - adds a dependency not in `security/allowed-dependencies.txt`;
  - adds an entitlement not in `security/allowed-entitlements.txt`;
  - has a privacy manifest that declares tracking or tracking domains, or no privacy manifest
    once an Xcode project exists.
- **Allowlists are reviewed decisions.** A pull request that edits a file in `security/`
  explains why in its description. Never work around a check; change the allowlist openly or
  change the code.
- **Changes to the checks are tested.** `scripts/test-check-security.sh` covers each one, and
  a new check gets a passing and a failing case.
- **Security self-check.** A pull request that touches privacy-relevant code (metadata,
  signing, files, permissions) answers the self-check questions in the pull request template.
- **Slower scans stay off the pull request path.** CodeQL code scanning for Swift runs weekly
  once app code exists. The full security audit runs before each release.

## Readable, documented code

Code is written for the next person to read it, whether a human contributor or an agent.

- **Clear before clever.**
  - Descriptive names that say what a thing is or does. No abbreviations beyond common
    platform ones (RAW, DNG, ISO, EXIF).
  - Small types and functions with one job each.
  - Early returns instead of deep nesting.
  - No unexplained magic numbers: name them, and cite where each value comes from.
- **Documentation comments on every type, and on every non-private function and property.**
  These are DocC `///` comments, saying what it does, its parameters, what it returns or
  throws, and any device or OS requirement.
- **Comments explain why, not what.**
  - Explain a decision, a platform quirk, or a privacy or honesty constraint.
  - Link the Apple documentation or the specification section behind it (DNG, EXIF, C2PA).
  - Delete comments that only restate the code.
- **Privacy-relevant code says so.** Code that writes or removes metadata, signs, or touches
  files carries a short comment naming the privacy rule it enforces, so reviewers and auditors
  can find it.
- **Human documentation lives in `docs/`,** created with the first app code. Keep it current
  in the same pull request that changes behavior:
  - `docs/ARCHITECTURE.md`: modules and data flow from capture to Photos.
  - `docs/PRIVACY.md`: every metadata item and how it's handled.
  - `docs/TESTING.md`: how to run the tests, and the on-device checks.

  Write in plain English for a developer new to the project.
- **Agent support.** `AGENTS.md` is the canonical agent instruction file, and `CLAUDE.md`
  imports it. `llms.txt` is the index for language models, following the llms.txt format:
  - Add every new document in `docs/` to `llms.txt` in the same pull request.
  - The repository checks fail if a link in `llms.txt` points to a missing file.

## Pull requests and releases

- Work on a branch and open a pull request; merge when CI is green and coverage holds.
- Sign off commits (`git commit -s`).
- **Versioning:** semantic versioning ([semver.org](https://semver.org)), `MAJOR.MINOR.PATCH`.
  - MAJOR for changes that break what users rely on (formats, metadata defaults, signature
    format). MINOR for new features. PATCH for fixes.
  - The first public release is `1.0.0`; development before it uses `0.x.y`.
  - A release is tagged `vMAJOR.MINOR.PATCH`, and every release has a `CHANGELOG.md` entry.
  - The iOS marketing version (`CFBundleShortVersionString`) and the Android `versionName` are
    the plain `MAJOR.MINOR.PATCH`.
  - Pre-releases (for example `1.1.0-beta.1`) appear only in tags and TestFlight or test-track
    notes, because store version fields don't accept them.
  - The build number (`CFBundleVersion`, Android `versionCode`) is a separate integer that
    increases with every uploaded build.
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
