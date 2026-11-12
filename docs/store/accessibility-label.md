# Accessibility Nutrition Label answers

Status: **draft, needs human review.** No feature may be declared yet. As of 2026-11-12 the
permission and camera screens, saving and manual controls are merged and audited in UI tests,
but the settings and Honesty screens aren't built and no manual assistive-technology pass has
been done. This page lists the answer the project aims for at 1.0 and the evidence each
answer needs. Declare a feature in App Store Connect only when every item in its evidence column
is done for that device.

## Apple's rule

Apple lets an app declare a feature only if people can complete **all of the app's common
tasks** with it, on each device type, answered separately per device. Common tasks include the
app's primary function, the first launch experience and settings
([Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)).
For nope. the common tasks are:

1. First launch: the welcome screen and the camera permission.
2. Take a photo, including the first save (the Photos add-only permission) and the result
   ("Saved and signed", or what went wrong).
3. Switch lens, and understand a lens without RAW.
4. Change privacy settings: the master switch, each item, signing, formats.
5. Read the Honesty screen and the last photo's details.

## Answers

Same answers for iPhone and iPad, each tested on its own device.

| Feature | Target at 1.0 | Evidence required before declaring | Evidence as of 2026-11-12 |
|---|---|---|---|
| VoiceOver | Yes | Labels, values and hints on every element; tasks 1 to 5 done with VoiceOver only in the manual release pass; viewfinder and result announcements tested | UI tests run `performAccessibilityAudit()` on every camera state; no manual pass; tasks 4 and 5 not built |
| Voice Control | Yes | Every control reachable by its visible name ("Take photo", "Settings"); tasks 1 to 5 done by voice in the manual pass | Not tested |
| Larger Text | Yes | Every screen at the largest accessibility size with no clipped or truncated essential text; UI tests at that size for every screen | UI test at the largest accessibility size for the interrupted state only |
| Dark Interface | Yes | Every screen dark by default or following Dark Mode, checked in light and dark in UI tests | Camera screen not yet checked in both appearances by a test |
| Differentiate Without Color Alone | Yes | Every status has text or a symbol (RAW badge, fallback badge, switch states, warnings); tested with the setting on | Badges use text; not tested with the setting on |
| Sufficient Contrast | Yes | Text 4.5:1 and icons 3:1, including over the viewfinder; audits pass with Increase Contrast on | Audits include the contrast check; Increase Contrast not tested |
| Reduced Motion | Yes | Crossfades instead of slides, no animated badges, with Reduce Motion on; tested | Not tested |
| Captions | Not applicable | nope. has no video or audio content | |
| Audio Descriptions | Not applicable | nope. has no video content | |

An accessibility failure is a release blocker (AGENTS.md, "Accessibility"), so the target at
1.0 is every applicable feature. If a feature misses its evidence at release, the answer for
that feature is left undeclared, never "Yes".

## Accessibility URL

Optional. When the 1.0 pass is done, a short page describing support for each feature (for
example in the repository) can be linked.
