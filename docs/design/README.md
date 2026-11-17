# Design

The current design of nope., as static HTML mockups. Open any file in a browser; none of them is part of the app build.

**Design version: 0.3.0 (2026-11-16).** Every file shows the same version, and each matches the app as of that release: labels, order and behavior come from the code. Sample values (file sizes, lens ranges, timings) are examples.

| File | What it covers |
| --- | --- |
| [camera.html](camera.html) | The camera screen in full auto and manual, landscape, iPad, the 4.7-inch overlay and right-to-left. Also covers the quick-controls tray, Flash and Light, and Drive (self-timer, burst, interval). Further sections: the thumbnail and What's in This Photo, save feedback, status chips, focus aids, Compare, Astro and Presets. The rest covers night mode, the Live Activity, the Apple Watch remote, and Siri and Shortcuts results. |
| [settings.html](settings.html) | Settings and every page in it: Presets, Photos, Camera, Viewfinder Overlays, Privacy, Accessibility, Honesty, About and Licenses. It also has first run and the permission states, plus the Lock Screen camera, Control Center, the Action button and the Camera Control. It ends with the camera pause messages. |
| [manual-controls.html](manual-controls.html) | The manual readout row and each control's dial (ISO, shutter, aperture, focus, white balance, exposure). Also Pro Tools with bracketing, largest text, VoiceOver, night mode and landscape. |
| [icon.html](icon.html) | App icon concepts in the current colors, with their default, dark, tinted and light versions. The final icon is a brand asset; see [TRADEMARKS.md](../../TRADEMARKS.md). |
| [redesign-options/overview.html](redesign-options/overview.html) | Options for the redesign (issue 74), not the current design: three directions (A · Bands, B · Reach, C · Strip), each as the camera screen, the Q quick menu and Astro on iPhone, with a PNG of every screen, the paths to common options, a comparison and a recommendation. Removed once a direction is chosen and drawn in the files above. |

## Rules for this folder

- Only the current design is kept here. When a release changes the UI, update these files in the same release and set the version line above. Older versions stay in git history.
- Colors: teal only for verified facts, amber only for warnings (always with a symbol and words), filled white for the selected item, and no yellow. Night mode is the app's pure red on black.
- The files are self-contained: inline CSS and SVG, with no scripts, fonts or other external requests.
- When a mockup and the app disagree, the app is right; fix the mockup.
