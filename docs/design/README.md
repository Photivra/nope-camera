# Design

The design of nope. for release 1.0.0, in direction B (Reach), chosen from the options of issue 74. Static HTML mockups with a PNG of each screen, plus the specifications the app is built from. Open [overview.html](overview.html) in a browser to start; nothing here is part of the app build.

**Design version: 1.0.0 (2026-11-17), planned.** This set is ahead of the app: release 1.0.0 is built to match it. Labels and behavior come from the code as of 0.3.0, except where a change is stated. Sample values (file sizes, lens ranges, timings) are examples. 122 screens are drawn; the PNG files total 4.3 MB.

| File | What it covers |
| --- | --- |
| [overview.html](overview.html) | The entry page: links to everything, the principles, the decisions on the open points, and what is beyond interface work. |
| [design-system.html](design-system.html), [tokens.md](tokens.md) | Spacing, radii, sizes and hit targets, type, color, materials over the picture, button types, motion and haptics. Token names map one to one to Swift constants. |
| [camera.html](camera.html) | The camera screen in full auto and every state: pills, warnings, capture feedback, failures, close-up, the Processed marker, the front camera, clean view, night mode, the smallest iPhone, first run and the permission states. |
| [drive.html](drive.html) | The drive strip: Single, Timer, Burst, Interval and Astro, idle and running, and the five words in the eleven launch languages. |
| [quick-menu.html](quick-menu.html) | Q, the quick menu: its tiles, states, a menu, night mode and a long language. |
| [manual-controls.html](manual-controls.html) | The Manual Controls button, the readout row, each dial and Pro Tools. |
| [sheets.html](sheets.html) | Formats and the processing note, What's in This Photo, Interval and Astro settings, Presets, Compare and the one confirmation. |
| [settings.html](settings.html) | Settings, its search and every page: Formats, Look, File Options, Photo Size, Choose Details, Fast Shutter, Viewfinder Overlays, Accessibility, Honesty, About and Licenses; light, night mode, the largest text size and right to left. |
| [SETTINGS-PLAN.md](SETTINGS-PLAN.md), [settings-tree.html](settings-tree.html) | A proposal for review, not yet decided or drawn: the Settings inventory, the problems found, a proposed tree, device coverage gaps, and the decisions it needs. |
| [layouts.html](layouts.html) | iPhone held sideways, iPad (with the Settings popover), the iPhone Duo inner display, the largest text size and right to left. |
| [system.html](system.html) | The Live Activity and Dynamic Island, the Control Center controls, and Siri and Shortcuts results. |
| [watch.html](watch.html) | The Apple Watch remote shutter and its states. |
| [navigation.html](navigation.html), [navigation.md](navigation.md) | Every option, where it lives, the path to it from the camera, and tap counts in 0.3.0 and in this design. |
| [ACCESSIBILITY.md](ACCESSIBILITY.md) | VoiceOver labels, values and order; Voice Control; Switch Control and the keyboard; text size; motion, transparency and contrast; Siri and Shortcuts. |
| [BUILD-SPEC.md](BUILD-SPEC.md) | The build specification: each screen's component tree mapped to the Swift files, what changes and what stays, acceptance criteria, new strings, work beyond the interface, and the order of work in parallel chunks. |
| [icon.html](icon.html) | The "n." app icon and the options for the color of its period. The final icon is a brand asset; see [TRADEMARKS.md](../../TRADEMARKS.md). |
| `screens/` | One self-contained HTML mockup and one PNG for each screen. Key screens are rendered at 2x, the rest at 1x. |

## Rules for this folder

- Only the current design is kept here. When a release changes the UI, update these files in the same release and set the version line above. Older versions stay in git history.
- Colors: teal only for verified facts, amber only for warnings (always with a symbol and words), filled white for the selected item, and no yellow. Night mode is the app's pure red on black.
- The files are self-contained: inline CSS and SVG, with no scripts, fonts or other external requests. Gallery pages show the PNG files from `screens/`. Placeholder pictures are drawn in SVG; there are no photos or device captures.
- Until 1.0.0 is released, this set is the plan and the app follows it. After that, when a mockup and the app disagree, the app is right; fix the mockup.
