# Accessibility Nutrition Label answers

Status: **draft, needs human review.** No feature may be declared yet. As of 2026-11-18 the
permission and camera screens, saving, manual controls, settings, the Honesty screen, About, the
Last Photo viewer and What's in This Photo are merged and audited in UI tests (settings, the
viewer and the details also at the largest text size, and settings right to left), but no manual
assistive-technology pass has been done, and the five items added to 1.0.0 on 2026-11-18 are built but
not device-checked; the Spanish translation (#87) moved to the backlog (see "Items added to 1.0.0"). This page lists the answer the project aims for at 1.0 and the evidence each
answer needs. Declare a feature in App Store Connect only when every item in its evidence column
is done for that device.

## Apple's rule

Apple lets an app declare a feature only if people can complete **all of the app's common
tasks** with it, on each device type, answered separately per device. Common tasks include the
app's primary function, the first launch experience and settings
([Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)).
For Photivra Nope Camera the common tasks are:

1. First launch: the welcome screen and the camera permission.
2. Take a photo, including the first save (the Photos add-only permission) and the result
   ("Saved and signed", or what went wrong).
3. Switch lens, and understand a lens without RAW.
4. Change privacy settings: the master switch, each item, signing, formats.
5. Read the Honesty screen and the last photo's details.

## Answers

Same answers for iPhone and iPad, each tested on its own device.

| Feature | Target at 1.0 | Evidence required before declaring | Evidence as of 2026-11-18 |
|---|---|---|---|
| VoiceOver | Yes | Labels, values and hints on every element; tasks 1 to 5 done with VoiceOver only in the manual release pass; viewfinder and result announcements tested | UI tests run `performAccessibilityAudit()` on every camera state; UI tests with audits for every settings screen, the Last Photo viewer (`PhotoViewerUITests.swift`) and What's in This Photo (`PhotoDetailsUITests.swift`); no manual pass |
| Voice Control | Yes | Every control reachable by its visible name ("Take photo", "Settings"); tasks 1 to 5 done by voice in the manual pass | Not tested |
| Larger Text | Yes | Every screen at the largest accessibility size with no clipped or truncated essential text; UI tests at that size for every screen | UI tests at the largest accessibility size for some camera states and every settings screen; not yet every screen |
| Dark Interface | Yes | Every screen dark by default or following Dark Mode, checked in light and dark in UI tests | Camera screen not yet checked in both appearances by a test |
| Differentiate Without Color Alone | Yes | Every status has text or a symbol (RAW badge, fallback badge, switch states, warnings); tested with the setting on | Badges use text; not tested with the setting on |
| Sufficient Contrast | Yes | Text 4.5:1 and icons 3:1, including over the viewfinder; audits pass with Increase Contrast on | Audits include the contrast check; Increase Contrast not tested |
| Reduced Motion | Yes | Crossfades instead of slides, no animated badges, with Reduce Motion on; tested | Not tested |
| Captions | Not applicable | The app has no video or audio content | |
| Audio Descriptions | Not applicable | The app has no video content | |

An accessibility failure is a release blocker (AGENTS.md, "Accessibility"), so the target at
1.0 is every applicable feature. If a feature misses its evidence at release, the answer for
that feature is left undeclared, never "Yes".

## Items added to 1.0.0 on 2026-11-18

None is built yet. Each adds evidence to the table above before any feature is declared:

| Issue | Effect on the answers | Evidence to add |
|---|---|---|
| #82 Assistant Access | No change to the common tasks; Siri and Shortcuts are an extra route, not a replacement for any control. The new Settings › Privacy › Assistant Access page is part of task 4. Confirmations are the system's `requestConfirmation` sheet; the line under it ("You can change this in nope › Settings › Privacy.") must be read by VoiceOver | UI tests with audits for the page at the largest text size, in dark mode and right to left (as the issue lists); VoiceOver and Voice Control on the page in the manual pass; a confirmation read by VoiceOver on a device |
| #87 Spanish (in the backlog) | Every answer holds in each language that ships. Longer Spanish text is the main risk for Larger Text | UI tests in Spanish at the largest accessibility size for the camera and every settings screen; the manual pass repeated for tasks 1 to 5 in Spanish on one device |
| #88 Red search field in Night Mode | Sufficient Contrast and VoiceOver: the field is drawn by the app, so it must keep the search field trait, the "Search Settings" label, Dynamic Type and right to left | Audits in Night Mode with search shown; the all-red pixel check; Increase Contrast with Night Mode on |
| #90 Focus bracketing | Part of task 2 when used. Its card and Bracket Settings follow `docs/design/BRACKETING.md`, section 6 | UI tests with audits (largest text, right to left, Night Mode); VoiceOver announces each frame and the end of the series |
| #95 Pinch to switch lenses | No change: a gesture only, with no VoiceOver action, and the lens buttons stay the accessible route for task 3. Pinch is off at the largest text sizes | A UI test that task 3 is done with the lens buttons with Pinch set to Off; Voice Control names the lens buttons |
| #97 Keep the screen on | No change to the answers. A new switch on a Settings page (task 4) | UI tests with audits for the row; the row is found by Settings search; VoiceOver reads its footer |
| Rate or Review row (`docs/store/STORE-PAGE-PLAN.md`, section 12) | No change to the answers. One link at the end of About (part of settings), shown once the app has an App Store ID; it opens the App Store, which is outside the app's declared features | UI tests with audits (`RateOrReviewUITests.swift`): default and largest text sizes, right to left, night mode (all red), search; on iPad the same tests. Its VoiceOver hint and Voice Control name in the manual pass |

## Accessibility URL

Optional. When the 1.0 pass is done, a short page describing support for each feature (for
example in the repository) can be linked.
