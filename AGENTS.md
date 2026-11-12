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
  - no web views, custom URL schemes, clipboard access or file import; an `https` link may
    open in the system browser only when the person taps it, and nope. itself makes no network
    request;
  - no code loaded at run time;
  - no private APIs;
  - no background modes;
  - least-privilege entitlements;
  - no homemade cryptography;
  - remove metadata through system APIs, never by editing bytes, and fuzz any byte-level code
    that can't be avoided;
  - strict concurrency, and no `unsafe` code outside tested, isolated spots.
- **Metadata is allowlisted and verified, never blocklisted.**
  - Every saved file carries only metadata on the documented allowlist (`docs/PRIVACY.md`):
    the data required to open the RAW, plus the items the user's switches turn on. Anything
    else is dropped by default, including tags a future iOS version adds.
  - Build metadata from the allowlist rather than deleting known tags from what the system
    wrote.
  - **Fail closed:** after writing a file, read it back with the project's own tag reader. If
    any tag, IFD or embedded block isn't on the allowlist, remove it. If it can't be removed
    safely, don't save the photo, and tell the user plainly.
  - Metadata tests assert the exact tag set of every format for each switch combination; any
    unexpected tag fails the test.
  - Rerun the on-device tag check (`docs/TESTING.md`) on each new iOS and iPadOS beta and major
    release, and before every app release. Update the allowlist only by a reviewed pull
    request.
- **Photos never linger.** They go from memory to Photos. Any temporary file uses complete file
  protection and is deleted immediately. Logs mark every value private, and never contain photo
  data or metadata.
- **Battery.**
  - The camera session runs only while the camera screen is in use. Stop it in the background,
    on interruptions and after an idle pause.
  - No background modes, polling, timers that keep running, or work done ahead of need.
  - Cap the preview frame rate. Run the histogram, zebras and focus peaking on reduced frames
    at a reduced rate.
  - Respect Low Power Mode and the thermal state.
  - Release RAW buffers as soon as each photo is saved.
  - Measure energy with Instruments on real devices before each release. No telemetry.
- **Siri and Shortcuts.** Every user action is exposed as an App Intent, with App Shortcuts
  phrases localized in all launch languages. Intents call `NopeCore` like any other interface,
  and hold no business rules of their own.
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

## Third-party licenses

Every third-party license is respected in full: code, packages, fonts, icons, images, sample
files, data, specifications, documentation and tools.
- **Check before use.** Read the actual license before adding anything. Use only what is free to
  use for this project:
  - anything bundled in the app must be compatible with GPL-3.0-only;
  - nothing with fees, field-of-use limits, non-commercial terms or "no modification" terms
    that would apply to us;
  - if a license is unclear, don't use it, and ask the maintainer.
- **Keep every notice.** Preserve copyright and license notices exactly. Ship the required
  license texts in the app's Licenses screen, and record each item in `THIRD_PARTY.md` (name,
  version, license, source, use).
- **Follow each license's conditions,** including attribution, notice files, share-alike terms,
  trademark limits and usage terms. Specifically:
  - **Adobe DNG.** nope. writes DNG files, so it carries the notice required by Adobe's DNG
    specification patent license: "This product includes DNG technology under license by
    Adobe." It appears in `NOTICE`, the README and the Licenses screen.
  - **SF Symbols and system fonts.** They are used only in the app's interface on Apple
    platforms, as Apple's terms allow. Never in the icon, logos, the wordmark or marketing
    artwork.
  - **Apple design resources** (device frames, interface kits). Used only as their license
    allows, for example in store screenshots and mockups.
  - **Specifications** (C2PA, DNG, EXIF, XMP) are implemented from their published text. Quote
    them only within their licenses, with a citation.
- **No copying around a license.**
  - Never copy code, text or images from sources without a compatible license. That includes
    answers from forums or Q&A sites, unless their license is compatible and they're credited.
  - Never strip, alter or hide license or copyright notices.
  - Never trace, redraw or closely imitate restricted works.
  - Write from documentation, not from someone else's code.
- **Test files and samples** are our own captures or freely licensed, with their source and
  license recorded. Never use other people's photos without permission.
- **Reviewed with every dependency change.** A pull request that adds or updates a dependency
  states its license and any license changes, and updates `THIRD_PARTY.md`.

## Name and wordmark

- **Full name:** "Photivra Nope Camera", with capitals and no period. Use it in the store listing
  and anywhere the full product name is needed.
- **Standalone name:** when the name is used alone, it is always written "nope.", lowercase with
  a period, even at the start of a sentence. That covers the home screen label
  (`CFBundleDisplayName`), permission prompts, interface text and documentation.
- **Wordmark lockup:** "nope." set large, with "Photivra Nope Camera" beneath it.
- **The tagline is the exception:** in "Processing? Nope. Tracking? Nope. Network? Nope.",
  "Nope" is an answer, not the name, so it keeps its capital.
- Translations keep "nope." unchanged.
- **Fonts: only fonts that are free to use for everything we use them for.**
  - Interface text uses the system font, rendered by iOS, which Apple's terms allow. It isn't
    bundled.
  - Any other font (the wordmark, store artwork, screenshots, docs) must be under a license
    that allows commercial use, embedding and logos without fees, such as the SIL Open Font
    License.
  - The wordmark is Inter (SIL OFL), converted to outlines, matching the Photivra logo.
  - Never use SF or other Apple system fonts in logos, the icon or marketing artwork.
  - **No workarounds.** Never trace, redraw, vectorize or closely imitate the letterforms of a
    font whose license doesn't allow the use, to get around that license. Converting text to
    outlines is allowed only for a font whose license already allows the use, as with Inter.
    Shapes drawn from scratch (like the icon's "n.") must not be copied from a restricted font.
  - Record every font and its license in `THIRD_PARTY.md`, and ship the license text with any
    bundled font.

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

## Architecture: interface separate from logic

The interface is a replaceable layer. Anyone must be able to build a different interface
(minimal, accessibility-first, iPad-specific, or experimental) without touching capture,
privacy, signing or development code.

- **Modules** (Swift packages under `Sources/`):

  | Module | Holds | May import |
  |---|---|---|
  | `NopeCore` | Models, settings, camera state and the state machine, privacy and format policies, and the protocols for every capability | `Foundation` only |
  | `NopeCapture` | AVFoundation and PhotoKit adapters that implement `NopeCore` protocols | `NopeCore`, AVFoundation, Photos |
  | `NopeDevelop` | RAW development to HEIF and JPEG | `NopeCore`, Core Image, ImageIO |
  | `NopeSigning` | C2PA signing with Secure Enclave keys | `NopeCore`, CryptoKit, the C2PA package |
  | `NopeUI` | SwiftUI views | `NopeCore`, SwiftUI |
  | App target | Wires the adapters into `NopeCore` and hosts `NopeUI` | Everything |

- **One direction of flow.**
  - The interface reads state from `NopeCore` (observable models) and sends it intents, such as
    `capture()`, `setISO(_:)` or `selectLens(_:)`.
  - It never calls AVFoundation, PhotoKit, signing or development code directly, and holds no
    business rules: no privacy decisions, format choices, exposure maths or capability checks.
- **Logic is interface-free.** `NopeCore`, `NopeCapture`, `NopeDevelop` and `NopeSigning`
  never import SwiftUI, UIKit or AppKit.
- **Capabilities are data.** What the device supports (lenses, RAW, control ranges, aperture
  stops) is published by `NopeCore` as plain values. Any interface can render it without knowing
  the hardware.
- **Testability follows.** The logic modules are tested with fakes of the hardware protocols, to
  full coverage. `NopeUI` is tested with UI tests and accessibility audits against a fake
  `NopeCore`.
- **Enforced in CI.** `scripts/check-architecture.sh` fails if a module imports something outside
  its column. `docs/ARCHITECTURE.md` documents the public `NopeCore` API that interfaces use.

## Readable, documented code

Code is written for the next person to read it, whether a human contributor or an agent.

- **Clear before clever.**
  - Descriptive names that say what a thing is or does. No abbreviations beyond common
    platform ones (RAW, DNG, ISO, EXIF).
  - Small types and functions with one job each.
  - Early returns instead of deep nesting.
  - No unexplained magic numbers: name them, and cite where each value comes from.
- **Complete API documentation.** Every public and internal symbol in every module has a DocC
  `///` comment. The comment says:
  - what the symbol does, and when to use it;
  - each parameter and its units (ISO, seconds, EV, kelvin);
  - the return value, the errors it throws, and when;
  - side effects (files written, permissions requested), threading or actor isolation;
  - any device or OS requirement.

  A short example is included where usage isn't obvious.
- **The `NopeCore` API is the interface contract.** It is what any new interface builds on, so
  it is documented to the standard of a public framework:
  - every state, intent and capability value;
  - every error and how an interface should present it;
  - a DocC article, "Building an interface", that walks through a minimal working interface.
- **Each module has a DocC catalog** with an overview article, the module's role, and links to
  the related `docs/` pages. Code examples in articles are compiled snippets, so they can't go
  stale.
- **Agent-readable output.** CI builds the DocC documentation and exports it as Markdown to
  `docs/api/`, one file per module. Those files are indexed in `llms.txt`, so an agent can read
  the whole API without building the project.
- **Documentation is checked in CI,** once app code exists:
  - the DocC build treats warnings as errors (missing or broken symbol links, undocumented
    parameters);
  - documentation coverage of public and internal symbols must stay at 100%;
  - `docs/api/` must match the code.
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
  - `docs/BUILDING-AN-INTERFACE.md`: a plain-English guide to replacing `NopeUI`, linking the
    DocC article.

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
