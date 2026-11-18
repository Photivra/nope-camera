# Accessibility and Siri specification

Design version: 1.0.0, direction B · Reach (2026-11-17).

What each screen of the design must do for VoiceOver, Voice Control, Switch Control, the keyboard, text size, motion, transparency and contrast, and which actions Siri and Shortcuts offer. The baseline is `AGENTS.md` (Accessibility), Apple's Human Interface Guidelines and WCAG 2.2 AA. The mockups are in this folder; the build steps are in [BUILD-SPEC.md](BUILD-SPEC.md).

## Rules for every screen

- Every control has a label, a value where it has one, and a hint only where the result is not obvious.
- Voice Control names match the visible words. A control drawn as a symbol or a letter gets `accessibilityInputLabels` with its spoken name first.
- Every target is at least 44 × 44 pt, with at least 8 pt between targets (4 pt inside the lens group).
- State is never color alone: on is filled and says On or its value; warnings have a triangle and words; verified facts have a seal and words.
- A gesture is never the only way: each has a button or a VoiceOver action.
- Nothing leaves on a timer. Failures stay until dismissed. Announcements are queued, not interrupted.
- The viewfinder and photos are excluded from Smart Invert.
- UI tests call `performAccessibilityAudit()` through the existing helpers on every screen and state listed in BUILD-SPEC.md, at the default size, at the largest accessibility size, right to left, and in night mode where the screen has one.

## Camera screen

### VoiceOver order

Top to bottom, leading to trailing, in every layout. Containers are named so the rotor can jump between them.

| # | Element | Label | Value | Traits, actions, hint |
| --- | --- | --- | --- | --- |
| 1 | Format status | Photo Format | "single-frame RAW, RAW", or "Processed: no RAW on this lens, HEIF" | Button. Opens Formats. Voice Control: "Photo Format", "RAW" or "Processed". Large Content Viewer |
| 2 | State pills (container "Changed Settings") | The setting's name, for example Light | Its value, for example 25% | Button, or a menu when it has several actions. The +n pill reads "n More Settings Changed" |
| 3 | Warning chips (container "Warnings") | The warning, for example Storage Low | none | Button. Opens the explanation. Announced once when it appears |
| 4 | Failure banner | The failure sentence | none | Static text, then its buttons: Try Again or Open Settings, Dismiss. Announced when it appears, with high priority |
| 5 | Viewfinder | Viewfinder | Lens, format, exposure warnings ("Wide, single-frame RAW") | Actions: Lock Focus and Exposure; Hide Controls or Show Controls. Tap is focus and expose |
| 6 | Live aids | Histogram; Live Camera Readout; Level | Their readings | Static |
| 7 | Mode card | Idle: Interval Settings or Astro Settings | The card's sentence | Button. Running: static progress ("Frame 7 of 20"), updated politely, then Stop, Stop Burst, Stop Frames or Cancel Timer |
| 8 | Manual readouts (container "Manual Controls") | Exposure Compensation, ISO, Shutter, Aperture, Focus, White Balance | "Auto, 200" or "Manual, 400" | Adjustable: swipe up or down changes the value without opening the dial. Double tap opens the dial. More Manual Controls is a menu |
| 9 | Dial | The control's name | Its value | Slider (adjustable), Decrease, Increase, Auto (selected when automatic). White balance adds Tint and Presets |
| 10 | Manual Controls button | Manual Controls | On or Off | Button, selected trait when on. Voice Control: "Manual Controls", "Auto", "Manual". Large Content Viewer |
| 11 | Lenses (container "Lens") | Ultra Wide, Wide, Telephoto, Front | "0.6×", plus "No RAW" where it applies | Button, selected trait |
| 12 | Switch Camera | Switch Camera | none | Button |
| 13 | Drive strip (container "Drive") | Single Photo, Self-Timer, Burst, Interval Shooting, Astro | Self-Timer: "3 seconds" | Button, selected trait. The selected one has the hint "Double tap for options" when it has options. Voice Control accepts the short word and the long name |
| 14 | Last Photo | Last Photo | "Saved and signed.", or the other save sentences; "Saving…" while busy | Button. Actions: Open in Photos, Photo Details |
| 15 | Shutter | Take Photo | "Self-timer, 3 seconds", "Burst", "Start interval shooting", "Start Astro frames"; "Stop" while running | Button. The volume buttons, the Camera Control and Space do the same |
| 16 | Q | Quick Menu | Open or Closed | Button. Voice Control: "Quick Menu", "Q". Large Content Viewer |

In clean view the order is: format status (only as a warning), Light pill, warnings, Viewfinder, progress, Show Controls, Take Photo.

### Announcements

Unchanged sentences, spoken at these moments: the lens on change; the drive mode on change ("Self-Timer, 3 seconds"); Manual Controls on or off; each second of a countdown; each capture result ("Saved and signed." and the others); each failure; each new warning; a series pausing, resuming and ending; Astro turning on, with what it changed ("Astro on. Manual controls and night mode are on."); the level becoming level ("Level", or "Pointing straight down, level" for the top-down level), once with each tap, at low priority, and held back in the same situations as the tap ([level-haptic.md](level-haptic.md), section 7). The last sentence is new and is listed with the new strings in BUILD-SPEC.md.

### Q

- Opening Q moves VoiceOver focus to the first tile; closing returns it to Q. The panel is a modal container: focus stays inside it, plus the shutter row, until it closes. Escape (two-finger scrub, or the Escape key) closes it.
- Each tile reads its name, then its value: "Grid, Thirds"; "Focus Peaking, Off". A two-state tile is a button with the selected trait and the value On or Off. A menu tile is a menu button.
- Order: tiles row by row from the leading edge, then Hide Controls, then Settings.
- At accessibility text sizes Q is a full-height list with one row per tile, ending with Hide Controls and Settings. In this layout Settings has no other button, on any device.

### Text size

- Up to the largest non-accessibility size the stacked layout holds. The drive strip uses 12 pt word padding, then 8 pt, then scrolls sideways and keeps the selected word visible. Tile names wrap to two lines and the row grows. The Q foot buttons stack when they do not fit.
- At accessibility sizes the camera uses the scrolling layout: status, warnings, a 280 pt picture, then full-width rows for Manual Controls, each lens, each drive mode and the manual controls list; the shutter row is pinned. Q and Last Photo grow to 64 pt.
- The shutter, lens labels, readouts and the letter Q cannot grow further, so each has a Large Content Viewer label.

### Sideways iPhone

Labels and values are the same. The Manual Controls button shows A or M and the drive strip shows symbols, so both have Large Content Viewer labels and the selected mode's name is shown in a pill on the picture.

### Switch Control and Full Keyboard Access

- Scanning groups, in order: status line, picture overlays, lens row, drive strip, shutter row. With Q open: the panel, then the shutter row.
- Tab moves through the same order; arrow keys move inside a group (lenses, drive words, tiles); Space or Return activates the focused control. With no control focused, Space takes a photo, as today. Escape closes Q, a menu or a sheet.
- The focus ring is the system's and must be visible over the picture (it sits on the dark backing).
- No new keyboard shortcuts are added in 1.0.0.

### Motion, transparency, contrast

- Reduce Motion: the Q panel, cards and dials crossfade; the selection fill switches without sliding; pressed states change opacity only.
- Reduce Transparency and Increase Contrast: the backing over the picture is solid black; Increase Contrast also outlines every unselected control.
- Bold Text: all text is system text and follows it. Button Shapes: every button already has a shape.
- Differentiate Without Color: no state uses color alone, so nothing changes.
- Contrast: text at least 4.5:1 and symbols and outlines at least 3:1, in dark, light (forms) and night mode. Values are in [tokens.md](tokens.md). Over the picture, every item has the backing, so contrast does not depend on the scene.
- Night mode: red on black, 5.3:1. On is filled, off is outlined, in the camera and in form switches.

## Sheets and Settings

- System forms: titles read first, then values, then the explanation as the hint. Switches are system switches. At accessibility sizes a switch moves below its text (`ExplainedToggle`, used for every explained switch).
- Settings list: no row is added or removed while a switch is changed, so focus never moves by itself (VoiceOver, Switch Control, Full Keyboard Access). Red Viewfinder is always in the list. Every row that opens a page reads its value: "Details in Each Photo, All Optional Removed, button"; "HEIF and JPEG Copies, Not Saved, button"; "Viewfinder Overlays, Grid, Level, button".
- A value that does not fit beside its title wraps under it at every text size; nothing is truncated in any launch language (figures `settings-long-language`, `settings-largest`, `settings-details-largest`).
- Details in Each Photo: the section headers Location, Other Details and Always Saved are headings. Turning Remove All Optional Details on or off announces nothing extra: the switches below keep their places.
- HEIF and JPEG Copies: with no copy saved the opening line is read first, and every control stays enabled.
- Voice Control names are the row titles. "Focus on Faces" is the name of the switch and of the Shortcuts action.
- Sheets open with focus on the title. Done is the first toolbar item for the keyboard and closes with Escape.
- Formats and the processing note: the opening statement is read first. The processing note sentences are plain static text in reading order.
- What's in This Photo: each section is a heading. Locked items read "Always kept". The signature row reads its sentence; with signing off by choice it has no warning symbol.
- Presets: each preset is a button ("Astro, preset. Double tap to apply."). The More menu has the label "More for Astro" and the actions Rename and Delete; both are also VoiceOver custom actions on the row. Delete asks for confirmation; Cancel is the default.
- Settings search: the system search field. Each result reads the setting and its page, in whole localized names: "Location, in Privacy, Details in Each Photo"; in right-to-left languages the order follows the language. A pointer to a camera control reads its name and the place in words, "Manual Controls. On the camera, beside the lenses.", and has no button trait, because it does not navigate; the camera symbol is decorative. Result headers (On the Camera, In Settings) are headings. No result: the system's "No Results" text is read.
- Honesty and Accessibility: headings and paragraphs in order.

## System surfaces

- Live Activity: reads the title, the status, the signing line, then Stop ("Stop. Every photo already taken is saved.").
- Controls: "Open nope."; "Night Mode, On" or "Night Mode, Off".
- Apple Watch: status, result, Take Photo or Cancel Timer, Delay with its value. Haptics on each countdown second and on the result. The view scrolls at large text sizes and on the 40 mm case; nothing is cut. Every status has a symbol and words. In Always On the system dims the app and VoiceOver is unchanged.
- Popovers and centered sheets on iPad and the iPhone Duo inner display: focus moves into them on opening and returns to the control that opened them; Escape closes them. A page pushed inside the Settings popover has Settings as its back button.
- Folding or unfolding the iPhone Duo: what is open stays open, so VoiceOver focus stays on the same element where the system keeps it; nothing is announced by the app.

## Siri and Shortcuts

The set of actions is unchanged in 1.0.0: no action is added or removed. One is renamed, Set Focus on Faces. All ten App Shortcut places are in use today and stay as they are.

| App Shortcut | Phrase (English) | Matches in the interface |
| --- | --- | --- |
| Take Photo | "Take a photo with nope." / "Take a picture with nope." / "Take a photo in 3 seconds with nope." | Shutter; Timer |
| Take Bracket | "Take a bracket with nope." | Pro Tools › Bracketing |
| Open the Camera | "Open the camera in nope." | The app; Open nope. control |
| Switch Lens | "Switch to telephoto in nope." | Lenses |
| Turn On the Light | "Turn on the light in nope." | Q › Light |
| Turn Off the Light | "Turn off the light in nope." | Light pill |
| Start Interval Shooting | "Start interval shooting in nope." | Drive strip › Interval, then the shutter |
| Stop Interval Shooting | "Stop interval shooting in nope." | Stop on the interval card |
| Night Mode On | "Turn on night mode in nope." | Q › Night Mode |
| Night Mode Off | "Turn off night mode in nope." | Q › Night Mode |

Actions in Shortcuts without a phrase: Apply Preset, Set Focus Range, Set Photo Size, Set Fast Shutter, and Set Focus on Faces. The last is Set Face Detection under a new name (decided 2026-11-17), with its parameter, its summary ("Set focus on faces to On") and its answers ("Focus on Faces is on.") renamed to match. It is the same action: shortcuts already saved keep working. The rename is listed in BUILD-SPEC.md, section 6, item 9.

Checks against the redesign:

- Names. The interface uses the same names as the actions: Light, Night Mode, Interval Shooting, Fast Shutter, Focus on Faces, Close-Up, Far Focus, Presets. The drive strip shows short words (Timer, Interval); their accessibility labels are the full names the actions use (Self-Timer, Interval Shooting).
- Set Focus Range keeps its three values (No Limit, Close-Up, Far Focus). In the interface these are the Close-Up and Far Focus tiles; both off is No Limit.
- Results. What Siri says is what the screen shows for the same action: "Photo saved and signed." matches the thumbnail's "Saved and signed."; "The photo wasn't saved. nope. shows why." matches the failure banner.
- Two results change with the defaults of issue 80, not with the layout: with signing off, Take Photo answers "Photo saved. It isn't signed." by default. No wording change is needed.
- "Astro is on. Turn it off to start interval shooting." stays true: Astro and Interval are separate words on the strip.
- Focus on Faces default (the action's parameter default is On) should be reviewed when its setting default changes to off; this is an intent change, not an interface change, and is listed in BUILD-SPEC.md.

## Manual pass before release

VoiceOver, Voice Control, Switch Control, Full Keyboard Access and the largest text size, on the flows: first run; a RAW photo; Manual Controls and a dial; Q and a menu tile; Timer; Interval; Astro in night mode; the Processed marker and its note; Settings with search by keyword and a pointer result; Details in Each Photo and HEIF and JPEG Copies at the largest text size; the Settings popover on iPad, in both orientations and in Split View; folding and unfolding an iPhone Duo with Settings open; the watch at 40 mm; Presets with rename and delete.
