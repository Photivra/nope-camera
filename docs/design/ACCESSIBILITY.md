# Accessibility and Siri specification

Design version: 1.0.0, direction B · Reach (2026-11-17; the Last Photo viewer and What's in This Photo added 2026-11-18).

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
| 7 | Mode card | Idle: Interval Settings, Astro Settings or Bracket Settings; in Burst, the card's text, then Start Burst | The card's sentence | Button. Running: static progress ("Frame 7 of 20"; in Burst "Photos taken: 12. 2.6 a second."; an interval series that stops after a time, "12 photos taken · 1 hour, 12 minutes left", the units in words though the card shows "1 hr, 12 min"), updated politely, then Stop, Stop Burst, Stop Frames or Cancel Timer. Burst: [BURST.md](BURST.md) section 4.2 |
| 8 | Manual readouts (container "Manual Controls") | Exposure Compensation, ISO, Shutter, Aperture, Focus, White Balance | "Auto, 200" or "Manual, 400" | Adjustable: swipe up or down changes the value without opening the dial. Double tap opens the dial. More Manual Controls is a menu |
| 9 | Dial | The control's name | Its value | Slider (adjustable), Decrease, Increase, Auto (selected when automatic). White balance adds Tint and Presets |
| 10 | Manual Controls button | Manual Controls | On or Off | Button, selected trait when on. Voice Control: "Manual Controls", "Auto", "Manual". Large Content Viewer |
| 11 | Lenses (container "Lens") | Ultra Wide, Wide, Telephoto, Front | "0.6×", plus "No RAW" where it applies | Button, selected trait |
| 12 | Switch Camera | Switch Camera | none | Button |
| 13 | Drive strip (container "Drive") | Single Photo, Self-Timer, Burst, Bracket, Interval Shooting, Astro | Self-Timer: "3 seconds"; Burst: "Fast" or "Slow" | Button, selected trait. The selected one has the hint "Double tap for options" when it has options. Voice Control accepts the short word and the long name |
| 14 | Last Photo | Last Photo | "Saved and signed.", or the other save sentences; "Saving…" while busy | Button. Opens the Last Photo viewer; hint "Shows the photo." Actions: Open in Photos, Photo Details |
| 15 | Shutter | Take Photo | "Self-timer, 3 seconds", "Burst, fast." with the hint "Double tap for one photo. Double tap and hold for a burst." and the action Start Burst, "Start interval shooting", "Start Astro frames", "Bracket, exposure, 3 frames"; "Stop" while running | Button. The volume buttons, the Camera Control and Space do the same |
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
- Night Mode search (issues 88 and 98, [night-search-field.md](night-search-field.md)): the red field is one element, "Search Settings, search field" in Settings and "Search, search field" on Every Tag, with the typed text as its value; Clear text and Cancel are buttons of at least 44 points, and Cancel goes under the field at accessibility sizes. Escape on a hardware keyboard and the VoiceOver escape gesture cancel the search. Focus is shown by a wider outline and the cursor, not by color. The Accessibility page says that the keyboard and menus are drawn by iOS and are not red.
- Keep Screen On (issue 97, [keep-screen-on.md](keep-screen-on.md)): one explained switch. The dimmed screen has the series' Brighten Screen cover and announcements; the controls under it stay reachable with VoiceOver. Moving VoiceOver's focus and every control used by any means count as activity, so the screen doesn't dim while someone is reading the controls. Dimming and the time limit only return the phone to its normal behavior.
- A row with a note of where it is used (Fast Shutter, BUILD-SPEC.md 3.16) is one element and reads the title, the value, then the note: "Fast Shutter, Standard, Used only while Manual Controls are off. Button." The note is part of the label, never the hint. Voice Control answers to the title alone. On the Fast Shutter page the line shown while Manual Controls are on is the first element.
- A value that does not fit beside its title wraps under it at every text size; nothing is truncated in any launch language (figures `settings-long-language`, `settings-largest`, `settings-details-largest`).
- Details in Each Photo: the section headers Location, Other Details and Always Saved are headings. Turning Remove All Optional Details on or off announces nothing extra: the switches below keep their places.
- HEIF and JPEG Copies: with no copy saved the opening line is read first, and every control stays enabled.
- Voice Control names are the row titles. "Focus on Faces" is the name of the switch and of the Shortcuts action.
- Sheets open with focus on the title. Done is the first toolbar item for the keyboard and closes with Escape.
- Formats and the processing note: the opening statement is read first. The processing note sentences are plain static text in reading order.
- What's in This Photo has its own section below.
- Presets: each preset is a button ("Astro, preset. Double tap to apply."). The More menu has the label "More for Astro" and the actions Rename and Delete; both are also VoiceOver custom actions on the row. Delete asks for confirmation; Cancel is the default.
- Settings search: the system search field. Each result reads the setting and its page, in whole localized names: "Location, in Privacy, Details in Each Photo"; in right-to-left languages the order follows the language. A pointer to a camera control reads its name and the place in words, "Manual Controls. On the camera, beside the lenses.", and has no button trait, because it does not navigate; the camera symbol is decorative. Result headers (On the Camera, In Settings) are headings. No result: the system's "No Results" text is read.
- Honesty and Accessibility: headings and paragraphs in order.

## Last Photo viewer

Figures and rules are in [viewer.html](viewer.html); the build steps are in BUILD-SPEC.md, section 3.14.

### Input

| Input | Result |
| --- | --- |
| Tap on the photo | Hides or shows the controls. Nothing hides by itself |
| Double tap on the photo | Zooms in at that point, to the limit; again, back to fit |
| Pinch | Zooms between fit and the limit. A pinch in below fit springs back; it does not close the viewer |
| Drag on a zoomed photo | Moves the photo. At its edge the drag does nothing; it does not change the page |
| Swipe left or right, not zoomed | The next or the previous photo, in the layout direction. The first and last photo spring back |
| Swipe down, not zoomed | Closes the viewer; the photo follows the finger and closes on release past a third of the height, otherwise it returns. With Reduce Motion it closes on release without following |
| Close | Closes the viewer |
| Escape; VoiceOver two-finger scrub | Closes the sheet if Photo Details is open, otherwise the viewer |
| Left and Right Arrow | The previous or the next photo |
| Tab | Photo, Photo Details, Open in Photos, Close; Space or Return activates the focused one |
| Volume buttons, Camera Control, Space with nothing focused | Recommended (BUILD-SPEC.md, section 7): close the viewer and return to the camera without taking a photo. The next press takes a photo |
| Take Photo from Apple Watch or Siri, or a running series | The photo is taken. The viewer stays on its photo and shows New Photo |

Zoom returns to fit when the page changes, when the window changes size, and when the viewer closes.

### VoiceOver

Opening moves focus to the photo. Closing returns it to Last Photo and posts a screen change. Order, in every arrangement:

| # | Element | Label | Value | Traits, actions, hint |
| --- | --- | --- | --- | --- |
| 1 | Photo | "Photo", or "Photo 3 of 5" | The formats, the save sentence, the lens and the time: "RAW and HEIF. Saved and signed. Wide. 2:41 PM." With "Zoomed in. A screen-size preview, not the full photo." while zoomed. For the fallback: "Preview not kept." and its sentence | Image, adjustable: swipe up or down for the next or the previous photo. Actions: Photo Details; Open in Photos; Zoom In; Zoom Out; Hide Controls or Show Controls. Double tap hides or shows the controls |
| 2 | Photo Not Saved | Photo Not Saved | none | Button. Closes the viewer. Announced when it appears, as the failure is today |
| 3 | New Photo | New Photo | none | Button. Goes to the newest photo |
| 4 | Close | Close | none | Button |
| 5 | Photo Details | Photo Details | none | Button. Opens What's in This Photo for this photo |
| 6 | Open in Photos | Open in Photos | none | Button. Not present from the Lock Screen camera |

- The status line and the caption are not separate elements: their content is the photo's value, so one swipe reads everything about the photo. The save sentence is the existing one (`CaptureMessages.message(forSaved:)`), so the viewer, the thumbnail and Siri say the same thing.
- The app does not describe what a photo shows. The element has the image trait, so the system's own image descriptions work where a person has them on.
- A change of page announces the new label and value. A photo that arrives while the viewer is open is announced with its save sentence, as on the camera; the photo's label then reads the new count.
- With the controls hidden the photo is still the first element, and its action reads Show Controls. Close, Photo Details and Open in Photos are not reachable until the controls are shown; Escape still closes.
- Last Photo on the camera: label Last Photo, value the save sentence, hint "Shows the photo." Actions Open in Photos and Photo Details stay, so both are one action away without opening the viewer. The touch and hold menu is removed.

### Voice Control

Names match the visible words: "Close", "Photo Details", "Open in Photos", "New Photo", "Photo Not Saved". The photo is "Photo". In the column arrangement the two actions show their names under their symbols, so no input label is needed. "Swipe left", "swipe right", "zoom in" and "zoom out" are the system's commands and work on the photo.

### Switch Control and Full Keyboard Access

- Scanning groups, in order: the photo (its menu offers Next Photo and Previous Photo from the adjustable trait, then the actions above), the items on the photo (Photo Not Saved, New Photo), the actions (Close, Photo Details, Open in Photos; in the column: Photo Details, Open in Photos, Close).
- Every result of a gesture is reachable from the photo's actions or a button, so no gesture is needed.
- The focus ring is the system's. On the photo it is drawn inside the photo's edge.

### Text size

- Up to the largest non-accessibility size the two action capsules stay in one row while they fit, then stack, trailing. The status line wraps to two lines, formats first.
- At accessibility sizes: the facts are lines above the photo (formats, the signature, then position, lens and time), the photo takes the remaining height and never less than 280 pt, and Photo Details, Open in Photos and Close are full-width rows. In a window too short for all of it, the rows scroll under the photo.
- Close in the stacked and column arrangements is a symbol, so it has a Large Content Viewer label.

### Motion, transparency, contrast, night mode

- Reduce Motion: the viewer fades in and out; pages crossfade in place; zoom changes without animation; the swipe down does not move the photo.
- Reduce Transparency and Increase Contrast: the backing under the facts in the column arrangement, the hint and New Photo is solid black; Increase Contrast outlines Close and the two actions.
- Contrast: text and symbols are on black or on the backing, never directly on the photo, so contrast does not depend on the photo.
- Night mode: red on black, and the photo is drawn in red, like everything outside the live viewfinder. Signed and Not signed differ by their symbol and words. The photo is excluded from Smart Invert.

### Siri and Shortcuts

No action is added. Take Photo from Siri or Apple Watch works while the viewer is open, and its answer is unchanged. No action opens the viewer in 1.0.0.

## What's in This Photo

Figures and the organization are in [photo-details.html](photo-details.html); the build steps are in BUILD-SPEC.md, section 3.15. A system list in a sheet: every row is a system row, and nothing needs a gesture.

### VoiceOver

Opening moves focus to the title. Done or the two-finger scrub closes the sheet and returns focus to Photo Details in the viewer, or to Last Photo when it was opened from there. Order:

| # | Element | Read as | Traits, actions |
| --- | --- | --- | --- |
| 1 | Title | "What's in This Photo" | Heading |
| 2 | Done | "Done" | Button |
| 3 | Photo picker, for a bracket only | "Photo, Photo 2 of 3" | The system picker |
| 4 | Summary | One element, read top to bottom: "RAW (DNG) and HEIF. 1×, 2:41 PM. 4032 × 3024 pixels, 26.9 MB. RAW: one frame of sensor data, and a HEIF copy developed by nope. Saved and signed. 7 optional details in the files. Location is in the files." | Static text. The symbols are hidden; the words carry the state |
| 5 | Each group header | "Exposure", "Lens and Camera", "RAW Sensor Data", "Files", "Processing", "Details in This Photo", "Content Credentials", "Every Tag" | Heading |
| 6 | A value row | Title, then value, then the note: "Shutter, 1/125 s"; "Shutter, 1/125 s, Not in the files"; "Size, 4032 × 3024 pixels, 12 megapixels" | One element for each row |
| 7 | A disclosure row | "More Exposure Details, collapsed"; "Left Out, 5, collapsed"; "In the Files, 7, expanded" | Button; the system's Collapsed and Expanded. Its rows follow it directly when open |
| 8 | A file row in Files | "RAW (DNG), 24.1 MB, 4032 × 3024 pixels, 12-bit, lossless" | One element |
| 9 | Location, hidden | "Location, Hidden, In the files" | Static text with the action Show Value; the Show Value button follows as its own element, labelled "Show Value, Location" |
| 10 | Location, shown | "Location, 45.5231° north, 122.6765° west, altitude 312 meters, In the files" | The system reads the formatted coordinates |
| 11 | Signature line | "Saved and signed.", or the other save sentences | Static text. No extra word for the symbol: the sentence says it |
| 12 | A manifest | "RAW (DNG). Claim generator: Photivra Nope Camera 1.0.0." and the manifest's words | One element. The manifest's words are in English in every language and are marked as English for the speech voice |
| 13 | Manifest SHA-256 | "Manifest SHA-256, collapsed"; open, the hash is one element read in groups of four characters | Button |
| 14 | A file under Every Tag | "RAW (DNG), 94, button" | Opens the page |
| 15 | Timing | "Timing, collapsed" | Button |
| 16 | Footer, then Open in Photos | The sentence; "Open in Photos, button" | |

- Footers ("As written in the files.", the Exposure Settings sentence) are read after their group's last row.
- The headings rotor moves between the eight groups; the summary is reached from the title with one swipe. No custom rotor is added on the sheet.
- A change made by a disclosure row announces nothing extra; focus stays on the row.
- Every Tag page: the title (the file's format) is a heading; then the search field; the count sentence; then each group, a disclosure row with the heading trait, so the headings rotor moves between TIFF, EXIF, GPS, DNG, XMP, File Structure and Content Credentials. A tag reads its name, its value and the setting: "ExposureTime, 0.008, Exposure Settings". The tag number is custom content (More Content rotor: "Tag number, 0x829A"), so it does not slow the list. Names are spelled by the system's rules for mixed-case words; no phonetic respelling is added. A hidden value reads "Hidden"; Show Hidden Values is the first row of its group and announces "Values shown." once.
- Search results announce the system's count. No result reads the system's "No Results".

### Voice Control

Names are the visible words: "Done", "More Exposure Details", "More Sensor Details", "In the Files", "Left Out", "Always Saved", "Manifest SHA-256" (two on a photo with two files: the system numbers them, and each also answers to "Manifest SHA-256, RAW" or "Manifest SHA-256, HEIF" through `accessibilityInputLabels`), "Timing", "Open in Photos", "Show Value" (input labels "Show Value" and "Show Location"), "Show Hidden Values", "Search", "Back". File rows under Every Tag answer to their format: "RAW", "HEIF", "JPEG".

### Switch Control and Full Keyboard Access

- Tab order is the reading order. Space or Return opens and closes a disclosure row, activates Show Value and opens a file's page. Escape closes the page's search first, then goes back, then closes the sheet.
- Each group is a scanning group; rows without an action are skipped by scanning.

### Text size

- Up to the largest non-accessibility size a value sits beside its title while both fit (`ViewThatFits`), otherwise under it. At accessibility sizes every value is under its title (`sheet-photo-details-largest`), the summary's caption is under the formats, and nothing is truncated: tag names and the hash break anywhere.
- Closed disclosure rows keep the sheet short at the largest size, and it is moved through by heading.

### Motion, transparency, contrast, night mode

- Disclosure rows use the system's animation, which is a fade with Reduce Motion.
- Color is never the only sign: teal comes with the seal and "signed", amber with the triangle and its sentence. Secondary text is the system's secondary label on the system's grouped background; the audit checks its contrast.
- Night mode: red on black (`sheet-photo-details-night`); the three signature states differ by symbol and sentence.
- The sheet's contents are covered while the app is not active, so a revealed location is not in the app switcher.

## Bracketing

From [BRACKETING.md](BRACKETING.md), section 6. Exposure and focus bracketing are both in 1.0.0 (focus bracketing moved from 1.1.0, issue #90); the focus forms follow the exposure ones.

| Input | Result |
| --- | --- |
| Shutter, volume buttons, Camera Control, Space | Takes the bracket, after the start delay. During the delay: cancels. Holding adds nothing |
| Escape | Closes Bracket Settings |
| Apple Watch | Take Photo takes what the strip says, so the bracket; "Photos saved and signed" and "Photos saved, not all signed" exist. No watch screen changes |
| Siri and Shortcuts | Take Bracket, once, without changing the bracket set in the app; it has Order |

| Element | Label, value, hint |
| --- | --- |
| Strip word | "Bracket", selected. Hint when selected: "Opens Bracket Settings." |
| Idle card | "Bracket Settings", button. Value: "Exposure bracket: 3 frames, 1 EV apart, −1, 0, +1 EV" |
| Shutter | "Take Photo". Value: "Bracket, exposure, 3 frames" |
| The Frames rows | "Frame 1, −1 EV, 1/250, ISO 200"; a limited frame adds its sentence ("This lens can't go brighter than frame 3.") |
| Announcements | The countdown's seconds, as the self-timer's; "Taking 3 frames"; "3 photos saved and signed." (existing) |
| Viewer chip | Part of the page's label: "Exposure bracket, frame 2 of 3, 0 EV." |

- Voice Control and Switch Control: every control has a visible name that is its spoken name (Bracket, Bracket Settings, Frames, Step, Order, Start Delay, Cancel). Nothing needs a hold, a drag or timing.
- Largest text sizes: the scrolling layout; Bracket is a full-width row, the card is full-width text, and each value in Bracket Settings wraps under its title.
- Right to left: rows mirror; exposure values and shutter speeds keep their order.
- Night mode: red on black; the limit warning keeps its triangle and words.
- Differentiate Without Color, Increase Contrast: the amber triangle always has words.
- Reduce Motion: the progress bar changes without animation.
- Sideways, iPad, iPhone Duo: the card on the picture's lower edge; Bracket Settings is a sheet.

Focus bracketing:

| Input | Result |
| --- | --- |
| Shutter, volume buttons, Camera Control, Space | Takes the focus bracket after its start delay; during the delay cancels; while it runs or is paused, stops it after the current frame |
| Escape | Closes the focus dial (as Cancel) |
| Apple Watch | During a focus bracket the watch reports the camera busy |
| Siri and Shortcuts | Take Bracket with Type Focus, Focus Frames and Range (As Set in nope., Whole Range) |
| Live Activity | The series activity: "Frame 4 of 12" |

| Element | Label, value, hint |
| --- | --- |
| Type | A segmented control (Exposure, Focus); at accessibility sizes a row that opens the two choices, as the sheet's other pickers do. Dimmed, with its sentence, where the lens takes only one type |
| Idle card | "Bracket Settings", button. Value: "Focus bracket: 12 frames, Focus 0.12 to 0.80, nearest first" |
| Nearest, Farthest (card) | "Nearest Focus", value "0.12"; "Farthest Focus", value "0.80". Buttons |
| Focus dial | The slider is adjustable in steps of 0.01, with Decrease and Increase buttons; a tap on the picture focuses there once |
| The track | Hidden; the words carry it |
| Shutter | "Take Photo". Value: "Bracket, focus, 12 frames"; while it runs "Taking a focus bracket. Press to stop." |
| Announcements | "Frame 4 of 12" at each frame at low priority, so VoiceOver isn't interrupted; the end sentence |
| Viewer chip | Part of the page's label: "Focus bracket, frame 4 of 12, focus 0.31." |

- Largest text sizes: the card's buttons stack and the track is left out; the Type control becomes a row that opens its choices.
- Right to left: the track runs from the lens's closest focus on the leading edge; positions keep their order.
- Night mode: red on black; frames taken are filled marks and frames to come outlined, so the count never depends on color.
- Reduce Motion: the track's marks change without animation.

## System surfaces

- Live Activity: reads the title, the status, the signing line, then Stop ("Stop. Every photo already taken is saved.").
- Controls: "Open nope."; "Night Mode, On" or "Night Mode, Off".
- Apple Watch: status, result, Take Photo or Cancel Timer, Delay with its value. Haptics on each countdown second and on the result. The view scrolls at large text sizes and on the 40 mm case; nothing is cut. Every status has a symbol and words. In Always On the system dims the app and VoiceOver is unchanged.
- Popovers and centered sheets on iPad and the iPhone Duo inner display: focus moves into them on opening and returns to the control that opened them; Escape closes them. A page pushed inside the Settings popover has Settings as its back button.
- Folding or unfolding the iPhone Duo: what is open stays open, so VoiceOver focus stays on the same element where the system keeps it; nothing is announced by the app.

## Siri and Shortcuts

One action is added in 1.0.0, Open Assistant Access, and one is renamed, Set Focus on Faces. Every other action now goes through the Assistant Access check (issue 82, [assistant-access.md](assistant-access.md), sections 5 and 13): off by default, it answers that access is off; with Every Action the system asks before each action. All ten App Shortcut places are in use today and stay as they are.

| App Shortcut | Phrase (English) | Matches in the interface |
| --- | --- | --- |
| Take Photo | "Take a photo with nope." / "Take a picture with nope." / "Take a photo in 3 seconds with nope." | Shutter; Timer |
| Take Bracket | "Take a bracket with nope." | Drive strip › Bracket |
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

VoiceOver, Voice Control, Switch Control, Full Keyboard Access and the largest text size, on the flows: first run; a RAW photo; Manual Controls and a dial; Q and a menu tile; Timer; Interval; Astro in night mode; the Processed marker and its note; Settings with search by keyword and a pointer result; Details in Each Photo and HEIF and JPEG Copies at the largest text size; the Settings popover on iPad, in both orientations and in Split View; folding and unfolding an iPhone Duo with Settings open; the watch at 40 mm; Presets with rename and delete; the Last Photo viewer with three photos (paging, zoom, Photo Details, closing and the return of focus), with a photo taken from the watch while it is open, and on the fallback.
