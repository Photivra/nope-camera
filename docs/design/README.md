# Design

The design of nope. for release 1.0.0, in direction B (Reach), chosen from the options of issue 74. Static HTML mockups with a PNG of each screen, plus the specifications the app is built from. Open [overview.html](overview.html) in a browser to start; nothing here is part of the app build.

**Design version: 1.0.0 (2026-11-17; the Last Photo viewer and the Photo Details redesign added 2026-11-18), planned.** This set is ahead of the app: release 1.0.0 is built to match it. Labels and behavior come from the code as of 0.3.0, except where a change is stated. Sample values (file sizes, lens ranges, timings) are examples. 334 screens are drawn (187 for iPhone, 83 for iPad, 33 for the iPhone Duo, 31 for Apple Watch), 44 of them for bracketing, 19 of those for focus bracketing in 1.1.0; the PNG files total 14 MB. A screen is drawn for a device where its layout, presentation or reach differs from the iPhone drawing; [layouts.html](layouts.html) states the rule for the rest.

| File | What it covers |
| --- | --- |
| [overview.html](overview.html) | The entry page: links to everything, the principles, the decisions on the open points, and what is beyond interface work. |
| [design-system.html](design-system.html), [tokens.md](tokens.md) | Spacing, radii, sizes and hit targets, type, color, materials over the picture, button types, motion and haptics. Token names map one to one to Swift constants. |
| [camera.html](camera.html) | The camera screen in full auto and every state: pills, warnings, capture feedback, failures, close-up, the Processed marker, the front camera, clean view, night mode, the smallest iPhone, first run and the permission states. |
| [drive.html](drive.html) | The drive strip: Single, Timer, Burst, Interval and Astro, idle and running, and the five words in the eleven launch languages. Bracket, the sixth word of 1.0.0, is drawn in [bracketing.html](bracketing.html); this page's figures still show five words. |
| [quick-menu.html](quick-menu.html) | Q, the quick menu: its tiles (with Focus Peaking), states, a menu, night mode and a long language. |
| [manual-controls.html](manual-controls.html) | The Manual Controls button, the readout row, each dial and Pro Tools (without Interval). |
| [sheets.html](sheets.html) | Formats and the processing note, Interval and Astro settings, Presets, Compare and the one confirmation. |
| [viewer.html](viewer.html) | The Last Photo viewer (2026-11-18): the photo just taken, full screen inside the app, for this session's photos: paging, zoom, Photo Details and Open in Photos, a new photo arriving, the fallback when only the thumbnail is left, night mode, the largest text size, right to left, sideways, and opening and closing. It replaces the Last Photo menu. |
| [photo-details.html](photo-details.html) | Photo Details (2026-11-18): the What's in This Photo sheet, redesigned to show everything the app holds about a photo it just saved: the summary, the groups and what is behind disclosure rows, a RAW and a processed photo, the three signature states, location, Every Tag, night mode, the largest text size, right to left and sideways; and where each value comes from. |
| [bracketing.html](bracketing.html), [BRACKETING.md](BRACKETING.md) | Bracketing (accepted 2026-11-18, all nineteen recommendations; exposure bracketing built in 1.0.0, focus bracketing for 1.1.0): Bracket as a word on the drive strip, its card and Bracket Settings with exposure bracketing for 1.0.0; focus bracketing, designed for 1.1.0; the build specification for each release, the strings, the device checks and the owner's decisions. 44 figures, `screens/bracket-*`. |
| [settings.html](settings.html) | Settings as accepted on 2026-11-17: the list in five groups, search with keywords and pointers to the camera, and every page: Formats, HEIF and JPEG Copies, Photo Size, Details in Each Photo, Fast Shutter, Viewfinder Overlays, Accessibility, Honesty, About and Licenses; light, night mode, the largest text size, right to left and German. |
| [SETTINGS-PLAN.md](SETTINGS-PLAN.md), [settings-tree.html](settings-tree.html) | The record of the Settings review, accepted 2026-11-17: the inventory, the problems found, the tree, the device coverage gaps, and the twelve decisions with their outcomes. |
| [layouts.html](layouts.html) | The rule that gives each window its layout, which screens are drawn for each device and what applies to the rest; iPhone held sideways (with a sheet open), the largest text size, right to left, and the Lock Screen camera. |
| [ipad.html](ipad.html) | iPad: both orientations, camera states, first run and permissions, drive modes, Q, dials, popovers and sheets, Settings, the largest text size, right to left, Split View, Slide Over and Stage Manager. |
| [duo.html](duo.html) | iPhone Duo: the outer and inner displays at their measured sizes, before and after pairs for folding and unfolding, half-open, and the Live Activity with the phone closed. |
| [system.html](system.html) | The Live Activity and Dynamic Island, the Control Center controls, and Siri and Shortcuts results. |
| [watch.html](watch.html) | The Apple Watch remote shutter: every status and result, the smallest and largest case, the largest text size, right to left, German, Always On, and what the watch app does not have. |
| [navigation.html](navigation.html), [navigation.md](navigation.md) | Every option, where it lives, the path to it from the camera, and tap counts in 0.3.0 and in this design. |
| [ACCESSIBILITY.md](ACCESSIBILITY.md) | VoiceOver labels, values and order; Voice Control; Switch Control and the keyboard; text size; motion, transparency and contrast; Siri and Shortcuts. |
| [BUILD-SPEC.md](BUILD-SPEC.md) | The build specification: each screen's component tree mapped to the Swift files, what changes and what stays, acceptance criteria, new strings, work beyond the interface, and the order of work in parallel chunks. |
| [icon.html](icon.html) | The "n." app icon, the options for the color of its period and the choice (teal). The built icon is `App/NopeApp/AppIcon.icon` and `App/NopeWatch/AppIcon.icon`. The final icon is a brand asset; see [TRADEMARKS.md](../../TRADEMARKS.md). |
| `screens/` | One self-contained HTML mockup and one PNG for each screen. Key screens are rendered at 2x, the rest at 1x. |

## Rules for this folder

- Only the current design is kept here. When a release changes the UI, update these files in the same release and set the version line above. Older versions stay in git history.
- Colors: teal only for verified facts, amber only for warnings (always with a symbol and words), filled white for the selected item, and no yellow. Night mode is the app's pure red on black.
- The files are self-contained: inline CSS and SVG, with no scripts, fonts or other external requests. Gallery pages show the PNG files from `screens/`. Placeholder pictures are drawn in SVG; there are no photos or device captures.
- Until 1.0.0 is released, this set is the plan and the app follows it. After that, when a mockup and the app disagree, the app is right; fix the mockup.
