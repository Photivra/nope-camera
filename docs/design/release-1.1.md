# Designs for 1.1.0

Status: proposed 2026-11-21 for release 1.1.0. Not built, not yet accepted, and not in the screen counts of [README.md](README.md). Decisions already recorded on an issue are taken as fixed and marked "decided"; everything else is a proposal, and the open choices are collected in [docs/plans/1.1.0.md](../plans/1.1.0.md), section 8. All wording is a draft until the Honesty review. The figures are SVG files in [release-1.1/](release-1.1/); they are sketches of layout, states and wording, not pixel-exact screens. The full screen set (`screens/`) is redrawn when each design is accepted and built.

This document covers the user-facing parts of three issues, and of six more that the owner split out of issue 83 (release 1.2.0) into this release on 2026-11-22: issues 132 to 137, sections 7 to 12. Their designs and strings were moved here from [release-1.2.md](release-1.2.md); the moved strings keep their numbers. Issue 85 (CI) has no interface; its diagram is here because the figures are kept together. Issue 114 (Apple Vision Pro) and issue 127 (the usability test) have no screens: see the plan, sections 3.1 and 3.7, and [docs/research/usability-test-plan.md](../research/usability-test-plan.md).

Sections 13 to 23 were added on 2026-11-22 for the 24 other issues of the milestone, all kept in 1.1.0 by the owner. The largest is the Appearance themes (issue 138, section 13), with a figure for every theme.

| Section | Issue | What |
| --- | --- | --- |
| 1 | 120 | The Show Controls button in clean view, made quieter |
| 2 | 128 | Shutter Sound |
| 3 | 129 | Capture feedback and save status |
| 4 | 83 | Moved to release 1.2.0: [release-1.2.md](release-1.2.md) |
| 5 | 85 | Which CI jobs a change runs (diagram only) |
| 6 | | Every draft string, for the Honesty review |
| 7 | 132 | Sharing a copy, and the When Sharing setting |
| 8 | 133 | File names without a date unless the file holds one |
| 9 | 134 | The Lock Screen camera's settings copy |
| 10 | 136 | The privacy cover in the app switcher |
| 11 | 135 | Leaving less behind (no screens) |
| 12 | 137 | Limits on the Honesty screen |
| 13 | 138 | Appearance themes: two colors, the themes, the tile in Q and the sheet |
| 14 | 144 | Send Feedback, and Report a Problem on GitHub |
| 15 | 152 | Level: pointing straight up |
| 16 | 139 | "Cryptographically signed" |
| 17 | 143 | The viewer's Close, where Last Photo was |
| 18 | 142 | Disabled controls and contrast (options) |
| 19 | 131 | A preview inside RAW files |
| 20 | 140 | Photo Details on iPad |
| 21 | 148, 149, 150 | Small changes to words and states |
| 22 | 141, 146, 147, 151, 153 to 155, 157 to 162 | Changes without a screen (pointers to the plan, and the CI diagram) |
| 23 | | Draft strings 122 to 151 |

Evidence note: everything about today's behavior was read from the code on branch `n100-H` at `9cef00d`. Nothing here was measured on a device or run on a simulator. Contrast ratios are calculated from the color values with the WCAG 2.2 formula (the same one `MeasuredContrast` uses in the UI tests); they are not measured from a screen. Each statement that needs a device is listed as a device check in the plan, section 7.

Q, the quick menu, gains one tile: Appearance, fixed and last, a button that opens a sheet (issue 138, section 13; decided by the owner on 2026-11-22). Nothing else here adds, removes or moves a tile; no tile is made editable, reorderable or swipeable; and Q still opens only from its button. The new settings are in Settings, and Share… is in the Last Photo viewer.

Names: the interface says "nope."; documents and the About screen say "Photivra Nope Camera" (AGENTS.md, "Name and wordmark").

## 1. The Show Controls button (issue 120)

Figure: [release-1.1/eye-button.svg](release-1.1/eye-button.svg).

### 1.1 What exists

In clean view the Last Photo spot holds Show Controls: `ShowControlsButton` in `CameraReadyView.swift`, the `eye` symbol in `NopeIconButtonStyle(size: NopeSize.thumbnail)`, 52 pt across. Its colors come from `NopeControlAppearance.resolve`:

| State | Fill | Symbol | Outline | Symbol on black | Circle on black |
| --- | --- | --- | --- | --- | --- |
| Normal | `#333333` | `#FFFFFF` | none | 21:1 | 1.66:1 |
| Increase Contrast | `#333333` | `#FFFFFF` | `#B0B0B0` | 21:1 | 9.68:1 (the outline) |
| Night Mode | `#140000` | `#FF0000` | `#CC0000` | 5.25:1 | 3.57:1 (the outline) |

So today the symbol is as strong as the shutter, and the circle itself is below 3:1 against the black row: the symbol alone identifies the button.

### 1.2 The design

A new quiet look for this one button: no fill, and a ring and symbol in one dim color.

| State | Fill | Ring (1.5 pt) and symbol | Contrast on black `#000000` |
| --- | --- | --- | --- |
| Normal | none | `#767676` | 4.62:1 |
| Increase Contrast | `#333333` | symbol `#FFFFFF`, outline `#B0B0B0` (today's look) | 21:1 and 9.68:1 |
| Night Mode | none | `#CC0000` | 3.57:1 |
| Night Mode with Increase Contrast | none | `#FF0000` | 5.25:1 |
| Pressed | the existing press effect (opacity and scale) on the look above | | brief; not a resting state |

- **Why a ring and not a darker fill.** The issue asks that the icon and its circle each keep 3:1 against the black bar. A filled circle dark enough to be quiet cannot reach 3:1 on black (today's is 1.66:1). A ring in the symbol's color can, so both parts pass, which today's button does not.
- **Why `#767676`.** It is the darkest common gray that still passes 4.5:1 on black, so the measured value in a screenshot keeps a margin above 3:1 after anti-aliasing. Against the shutter's white (21:1) the button reads as secondary.
- **Night Mode is red only.** Pure red on black tops out at 5.25:1, so there is little room: `#CC0000` is the red the night outline already uses (`nightOutlineUnderMultiply`, drawn as `Color(white: 0.8)` under the night multiply). The fill `#140000` is dropped. The existing rule that night labels use the full red was written for text (4.5:1); the eye is a symbol, where 3:1 applies (WCAG 2.2, 1.4.11). Whether to dim the night symbol at all is decision 2 of the plan.
- **Only on solid black.** The quiet look applies where the button sits on the solid black shutter row or control column. The builder checks each layout (`stacked`, `rows`, `controlColumn`, the Lock Screen camera, iPhone Duo outer display). In any layout where the spot is drawn over the picture or over a material, the button keeps today's look there.
- **Nothing else changes:** the 52 pt size, the hit target (`nopeHitTarget`), the place, the label "Show Controls", the Large Content Viewer, the VoiceOver action on the shutter, the Voice Control name, Switch Control and keyboard access, and the swipe that toggles clean view.
- Other icon buttons (Switch Camera, Q, close, More) are not changed.

### 1.3 Build notes

- `NopeButtonStyles.swift`: a `prominence` value on `NopeIconButtonStyle` (`.standard`, `.quiet`), resolved in `NopeControlAppearance.resolve` so the four states above are one pure function with unit tests.
- `DesignTokens.swift` and `tokens.md`: `NopeColor.quietControl` (`Color(white: 0x76 / 255)`), `NopeSize.quietOutline` (1.5). The night value reuses `nightOutlineUnderMultiply`.
- `CameraReadyView.swift`: `ShowControlsButton` only.
- Redraw `screens/camera-clean` and the clean-view figures for iPad, Duo and Night Mode when accepted.

### 1.4 Accessibility

- Contrast as in 1.2. Differentiate Without Color: the button is a shape and a symbol, never color alone.
- Increase Contrast returns the button to full strength, as the issue allows.
- Reduce Transparency: no material is used.
- VoiceOver, Voice Control, Switch Control, Full Keyboard Access, Large Content Viewer: unchanged, and covered by the existing audits.

## 2. Shutter Sound (issue 128)

Figure: [release-1.1/shutter-sound.svg](release-1.1/shutter-sound.svg).

### 2.1 What exists

The app plays no sound and sets nothing about sound: there is no `isShutterSoundSuppressionEnabled`, `AudioServices` or audio session code in `Sources/` or `App/`. The system decides whether a capture makes its shutter sound. The documents say so in several places ("The shutter sound follows the system": AGENTS.md "Hearing", `BURST.md`, `level-haptic.md`; `docs/research/capture-and-file-settings.md` lists shutter sound suppression as "Not offered").

Not confirmed on a device (plan, research step R2): when the system plays the sound for the app's single-frame RAW and HEIF captures, whether it follows the ringer switch and volume, what a burst and a bracket sound like, and where the sound goes with headphones connected.

### 2.2 The design

- **Decided (issue 128, 2026-11-21):** the setting is off by default; where the system or regional rules require a shutter sound, that sound still plays, and the setting's description says so.
- **Name and place:** Settings › Camera › **Shutter Sound**, a switch with its explanation under it (`ExplainedToggle`), after Face Detection. Search keywords: sound, shutter, silent, quiet, mute, click, noise.
- **Off:** each capture asks the system not to play the shutter sound (`AVCapturePhotoSettings.isShutterSoundSuppressionEnabled`, only where `AVCapturePhotoOutput.isShutterSoundSuppressionSupported` is true).
- **On:** the app asks for nothing, so the system's own sound plays by the system's rules (today's behavior). The app ships no sound of its own, starts no audio session and never changes the volume.
- **Where the system does not allow silence** (`isShutterSoundSuppressionSupported` is false): the row is a value, "Always On", not a switch, with the reason under it. The row is not hidden: a person should be able to find out why the camera makes a sound.
- **The sound carries no information of its own** (AGENTS.md, "Hearing"): the shutter haptic, the picture's dimming (section 3) and the saved sentence still mark every photo.

| Where | Behavior |
| --- | --- |
| Single, Timer | One sound per photo when on |
| Burst | The system's sound for each photo when on; the app cannot make it one sound for the run. Device check: whether this is acceptable at Fast; if not, the choice is decision 6 |
| Bracket, focus bracket | The setting applies to every frame. Device check: what the system plays for a bracket |
| Interval, Astro | The setting applies to every photo. No special case at night: a person who wants silence has the switch off |
| Apple Watch remote, Siri and Shortcuts, headphone remote, volume buttons, Camera Control | The same setting; the sound comes from the phone (or where the system routes it) |
| Lock Screen camera | The same setting, read from the settings snapshot the extension already receives. With no snapshot: off, the default |
| Compare (the system-processed comparison photo) | The same setting |
| Presets | Not stored in presets and not changed by applying one (decision 5). Factory Defaults sets it to off |
| Siri and Shortcuts | No action changes it in 1.1.0 |

### 2.3 Wording

Strings 1 to 7 in section 6. The Honesty screen gains one entry under "What iOS May Still Do". The sentence about the ringer and volume (string 3) is used only if the device check confirms it; otherwise string 3b.

### 2.4 Accessibility

- A sound can help a person who cannot see the picture dim. The Accessibility page gets a pointer row, "Shutter Sound", that opens the Camera setting (one value, one switch; decision 4).
- VoiceOver reads the row as title, value, then the explanation. The "Always On" row is read as a value with the reason, not as a dimmed switch.
- Largest text sizes, right to left, Night Mode: the row is the existing `ExplainedToggle` pattern.

## 3. Capture feedback and save status (issue 129)

Figure: [release-1.1/capture-status.svg](release-1.1/capture-status.svg).

### 3.1 What exists

- A press gives the shutter haptic at once (`ShutterButton`, `NopeHaptic.shutter`).
- `CameraModel.capture` sets `captureStatus` to `.capturing`, then `.saving`, then `.saved` or `.failed`. The shutter is disabled through both `.capturing` and `.saving`, so the next single photo cannot start until the save has finished.
- The Last Photo spot shows a spinner for both (`LastPhotoSpot.saving`); the new photo's thumbnail appears only after the save, made from the saved files.
- The saved haptic, the status sentence ("Saved and signed." and its unsigned forms) and a low-priority VoiceOver announcement come after the save. Nothing on the picture marks the moment of capture.
- Bursts already take photos while earlier ones save, with their own card and limits.

No timing has been measured. The plan's research step R3 measures first; the numbers decide how much of this section is built (decision 8).

### 3.2 The rule

One rule for every surface: **feedback at capture says a photo was taken; only a confirmed save says it was saved.** "Confirmed" means what `.saved` means today: the files passed the metadata read-back and the destination accepted them (Photos; from release 1.2.0 also the app's own store, issue 83).

| Moment | Picture | Haptic and sound | Last Photo spot | Words and VoiceOver |
| --- | --- | --- | --- | --- |
| Press | | Shutter haptic (exists) | Unchanged | |
| The camera starts the exposure | Dims for 0.1 s | The system's sound, if Shutter Sound is on | Unchanged | |
| The camera returns the photo | | | The new photo's own preview, dimmed 60%, with a ring; not a button | "Photo taken. Saving." only if the save is still running after 1 second (decision 11) |
| Save confirmed | | Saved haptic (exists) | The preview at full strength, with the seal or mark as today; opens the viewer | The existing saved sentence |
| Save failed | | Not-saved haptic (exists) | The preview with an amber mark while the message shows; then the last saved photo, or Open Photos, returns (decision 9) | The existing "Not saved: …" sentence, with Try Again |

Details:

- **The dimming** is a black overlay on the picture only, 0 to 75% and back in 0.1 s, started by a new capture event from the camera (the system's "will capture" callback), not by the press, so it marks the real exposure. Reduce Motion: the same dimming without animation steps (one 0.1 s hold); it is a brightness change, not movement. Night Mode: black on red, unchanged. Bursts and series: one dimming per photo at Slow and in series; at Fast, where photos are less than 0.3 s apart, no dimming (the card's count carries it), to avoid a flicker. Long exposures (Astro, 1 s and longer): the dimming is at the start, and the existing progress display covers the rest.
- **The early preview** is the photo's own preview delivered with the capture. It is never a frame of the viewfinder: a viewfinder frame is not the photo. If the camera delivers no preview, or asking for one slows the capture measurably (R3), the spot shows the ring on a neutral tile instead. The preview stays in memory only, as today, and is dropped at once when the save fails the metadata check.
- **Saving is not openable.** A photo that is not saved yet cannot be opened in the viewer or in Photo Details; the spot is not a button, and VoiceOver reads it as "Last photo, saving".
- **The shutter** stays disabled while a single photo saves, as today, unless step 3 of the plan is built. With step 3, the next photo can start as soon as the camera can take it, while earlier photos save in order; the spot shows how many are still saving (panel 3b), and the shutter is disabled again when the pending photos reach the limit (decision 10). Each photo still gets its own result; a failure names how many of the pending photos were not saved.
- **Leaving the app while photos save:** unchanged from bursts: each pending photo is saved or reported.
- **Apple Watch, Live Activity, Siri and Shortcuts:** no change of meaning. They report saved only after the save; the watch's "Saving" stays.
- **Nothing here changes a file.** No capture setting that changes what is recorded (responsive capture, zero shutter lag, deferred delivery) is turned on; `CapturePolicy` keeps them off.

### 3.3 Accessibility

- VoiceOver: no announcement at capture for a quick save, so the usual photo has one announcement, as today. When a save takes longer than 1 second, "Photo taken. Saving." is spoken once, then the result. Bursts and series stay as designed in `BURST.md`: no per-photo speech.
- The ring is not the only signal: the spot's label says "saving", and the status line is unchanged.
- The amber mark comes with the failure sentence and symbol; never color alone.
- Reduce Motion, Increase Contrast and Night Mode as above. The ring is white on the dimmed preview (at least 4.5:1 by construction: the preview is under 60% black); in Night Mode, red.

## 4. Protection for high-risk use (issue 83)

Moved to release 1.2.0 on 2026-11-21, with its figures and its strings (13 to 56, numbers unchanged): [release-1.2.md](release-1.2.md). What the saving state of section 3 shows with Lock Captures on is designed there. Six parts of it came back to this release on 2026-11-22 as issues 132 to 137: sections 7 to 12, with strings 25, 31 to 34 and 51.

## 5. Which CI jobs a change runs (issue 85)

Figure: [release-1.1/ci-scope.svg](release-1.1/ci-scope.svg). The design is in the plan, section 3.4.

## 6. Draft strings

For the Honesty review. "H" marks a sentence that states what is or is not protected, saved or processed; it goes in `Honesty.xcstrings`. English (U.S.) only in 1.1.0; Spanish follows with issue 87.

| # | Where | Text | H |
| --- | --- | --- | --- |
| 1 | Settings › Camera, row | Shutter Sound | |
| 2 | Its explanation, off | Off: nope. asks iOS to take photos silently. iOS still plays the sound where it is required. | H |
| 3 | Its explanation, on (if confirmed on a device) | On: iOS plays its shutter sound for each photo. It follows the iPhone's ringer and volume. | H |
| 3b | Its explanation, on (otherwise) | On: iOS plays its shutter sound for each photo. | H |
| 4 | The value where silence is not allowed | Always On | |
| 5 | Its explanation | On this iPhone, iOS always plays the shutter sound. nope. can't turn it off. | H |
| 6 | Honesty, What iOS May Still Do | The shutter sound belongs to iOS. nope. asks for silence unless you turn on Shutter Sound, but in some countries and regions iOS always plays it. | H |
| 7 | Accessibility page, pointer row | Shutter Sound | |
| 8 | Last Photo spot, VoiceOver, while saving | Last photo, saving | H |
| 9 | VoiceOver, a save longer than 1 second | Photo taken. Saving. | H |
| 10 | Last Photo spot, several saving, VoiceOver | Saving %lld photos | H |
| 11 | Last Photo spot, VoiceOver, after a failure | Last photo, not saved | H |
| 12 | Failure with several pending | %1$lld of %2$lld photos were not saved: | H |
| 25 | Neutral File Names, explanation | A copy's name includes the date and time only when the file itself holds them. With this on, every shared copy, and every photo saved to Photos, gets a random name. | H |
| 31 | Share step, the two options (Ask Each Time) | Share Without Optional Details: a copy with the optional details removed. It has no date and no signature. · As Saved: every detail in the file, and its signature. | H |
| 31b | As Saved, when the file holds a location | This file includes its location. · Share · Cancel | H |
| 32 | Summary, signature (when the saved file was signed) | The copy is not signed: a signature does not survive a change to the file. | H |
| 33 | Summary, What Stays in the File | Color and size data that the file needs to open can point to the phone model, and possibly to the individual phone. Every camera sensor also leaves a faint, unique noise pattern in the picture. With enough of your photos, forensic tools can match them to the same camera. No app can fully remove it. The picture itself is not changed. | H |
| 34 | Without Optional Details, check failed | Not shared: nope. couldn't confirm that the copy holds only the details listed. | H |
| 51 | Share step and summary | File name · (the name the copy will have) · The name holds the date and time only when the file itself holds them. | H |
| 101 | Settings › Privacy, row; page title | When Sharing | |
| 102 | Its choices | As Saved · Without Optional Details · Ask Each Time | |
| 103 | When Sharing, footer | As Saved shares the file as it is, with every detail in it and its signature. Without Optional Details shares a copy with those details removed. The copy has no date and no signature, so it suits publishing, not a record. Every camera sensor also leaves a faint, unique noise pattern in the picture. With enough of your photos, forensic tools can match them to the same camera. No app can fully remove it. This applies to Share in nope., not to sharing from the Photos app. | H |
| 104 | Viewer, button | Share… | |
| 105 | Share step and summary, note | The app or place you send it to keeps its own copy. The photo in Photos is not changed. | H |
| 106 | Viewer, Share… unavailable | nope. no longer holds this photo's file. Share it from Photos; When Sharing does not apply there. | H |
| 107a | Summary, a RAW pair while a RAW copy can't be made | Only the HEIF copy is shared. nope. can't make a RAW copy without optional details. | H |
| 107b | Share step, a RAW-only photo while a RAW copy can't be made | A RAW photo can only be shared as saved. | H |
| 108 | Share step, title and button | Share a Copy · Continue | |
| 109 | Summary, title, headings and values | Without Optional Details · In the Copy · Removed · Not in the file · What Stays in the File | H |
| 110 | Details in Each Photo, row (by the plan's decision 40) | Neutral File Names | |
| 111 | Settings, notice while a change has not arrived | The Lock Screen camera hasn't received this change. It is still using your earlier settings. · Try Again | H |
| 112 | The same, when the copy is too large | The Lock Screen camera can't receive these settings: together they are too large for iOS to pass on. It is still using your earlier settings. · Try Again | H |
| 113 | VoiceOver, when a hand-off is confirmed after a notice | The Lock Screen camera has your settings. | H |
| 114 | Settings, notice, only if the copy can't be read back (R8) | nope. sent this change to the Lock Screen camera but can't confirm that it arrived. | H |
| 115 | Honesty, What No App Can Remove | Deleting Is Not Erasing · Deleting a photo removes the file. It does not overwrite the iPhone's storage, which can keep deleted data for a time. nope. can't erase storage. | H |
| 116 | Honesty, What No App Can Remove | Copies Outside nope. · A copy you shared, or saved somewhere else, is held by the person, app or service that has it. nope. can't reach, change or delete it. | H |
| 117 | Honesty, What No App Can Remove | Backups to a Computer · A backup of this iPhone to a Mac or PC is not encrypted unless you select Encrypt local backup. Without it, anyone who can open the computer's files can read the backup. | H |
| 118 | Honesty, What No App Can Remove | Updates to nope. · An update to nope. can read everything nope. can read, and could add a network connection this version does not have. nope. can't protect against its own updates. | H |
| 119 | Honesty, an entry on sharing (after device check 15) | Sharing from nope. · Share in nope. sends the file as saved, or a copy without optional details, as you choose in When Sharing. The app you send it to may rename it or add its own details. | H |
| 120 | Honesty, an entry on the Lock Screen camera (only if R8 passes) | The Lock Screen Camera's Settings · The Lock Screen camera uses a copy of your settings. nope. checks that each change arrived, and Settings tells you when one has not. | H |
| 121 | Honesty, an entry on what the app leaves (after device check 16; each part only if its check passed) | What nope. Leaves on This iPhone · nope. keeps your settings. It adds nothing about your photos to system search or the clipboard, and removes its temporary files after each save and share. | H |

Notes on strings 25, 31 to 34, 51 and 101 to 121:

- **Numbers.** 25, 31, 31b, 32, 33, 34 and 51 keep the numbers they had in the 1.2.0 design, which now points here for them. 101 to 121 are new, numbered after the 1.2.0 design's last string (100) so that no number is used twice across the two documents.
- **Changed in the move:** 25 ("exported or shared copy" became "shared copy"; "and every photo saved to Photos" stays only if R7 shows Photos keeps the app's name). 31 (Share Without Optional Details is first, and its second sentence is new; the owner's decision of 2026-11-22). 31b (now a confirmation's text, by the plan's decision 39; as first written it was the As Saved row's text). 32 and 34 ("stored file" and the option's name follow the setting). 51 (shown in the share step and the summary; Save to Files is release 1.2.0's). 33 is unchanged.
- **Reviewed before building.** Strings 31, 32 and 33 were in the owner's first review list for issue 83 (review decision 14). They are reviewed from this table before group G starts, and again in the built app with every other string (the plan's decision 26).
- **String 33.** "And possibly to the individual phone" stays unless a comparison of the locked values across two phones of one model shows they do not differ (device check 15); with no second phone, it stays. The sensor sentences are the wording of `docs/research/privacy-claims.md`, claim 9, as on the Honesty screen.
- **String 103** repeats the sensor sentences of claim 9 word for word, so one review covers both.
- **Strings 107a and 107b** are used only if R9 does not pass the DNG copy. 107a names the copy's format ("HEIF" or "JPEG") through a catalog variant, not by joining fragments.
- **Strings 111 to 114** follow R8. 114 is used only if the app cannot read the copy back.
- **Strings 115 to 118** each wait for their claim and source (section 12). "For a time" in 115 is kept only if the source supports it.
- **Strings 119 to 121** are written last, by group K, from what the device checks recorded; the text here is the most that can be said if every check passes.
- **"Share Clean" is not used** in the interface.

The other strings from 13 to 100 are for issue 83 and are in [release-1.2.md](release-1.2.md), section 9, with their numbers unchanged. Strings 122 to 151, for the issues added on 2026-11-22, are in section 23.

## 7. Sharing a copy, and When Sharing (issue 132)

Figure: [release-1.1/share-copy.svg](release-1.1/share-copy.svg). Moved here from [release-1.2.md](release-1.2.md), section 3, when the owner split the issue out of issue 83 on 2026-11-22, and changed the same day by the owner's decision that sharing without optional details is a setting. In 1.1.0 it works on photos saved to Photos in this session; release 1.2.0 uses the same setting, step and summary for captures kept in the app.

### 7.1 What exists

The app has no share action. The Last Photo viewer has Close, Photo Details and Open in Photos. After a save the app holds a thumbnail, a compressed preview and the details in memory; it does not hold the saved file, and it cannot read Photos. Where the file to share comes from is the plan's decision 36; this section draws the recommended option, in which the saved files of the newest photos stay in memory until the app leaves the foreground.

### 7.2 The setting

- **Decided (owner, 2026-11-22):** Settings › Privacy › **When Sharing**, with three choices: **As Saved** (the default, and what a file shared from Photos is today), **Without Optional Details**, **Ask Each Time**.
- **Place:** the third row of the Privacy group, after Sign Each Photo and before Assistant Access. The row shows the current choice as its value and opens a page with the three choices and the footer (figure, panel A). Four rows in the group in 1.1.0.
- **The footer** (string 103) says what each choice shares and the limits: a copy without optional details has no date and no signature, so it suits publishing and not a record; the sensor's noise pattern stays in the picture, in the wording already on the Honesty screen; and the setting applies to Share… in the app, not to sharing from the Photos app.
- **Search keywords:** share, sharing, send, export, details, metadata, location, strip, remove, clean, AirDrop. The search result reads "When Sharing, in Privacy".
- **Factory Defaults** sets it to As Saved. **Presets** do not store it, and applying one does not change it. No Siri or Shortcuts action changes it.
- **The Lock Screen camera** reads it from the settings copy, which section 9 makes reliable, and shows the row like the other Privacy rows. It offers Share… only if a device check shows a share sheet can be presented there; if not, there is no Share… there and the row's footer is unchanged.
- **People who update** from 1.0.0 get As Saved, and nothing changes for them until they open Share….

### 7.3 Share… in the viewer

The viewer's controls gain **Share…** (string 104) between Photo Details and Open in Photos. It acts on the photo shown. Q is not involved.

| When Sharing | What Share… does |
| --- | --- |
| As Saved | Opens the share sheet with the saved file, or both files of a RAW pair. When the file holds a location, the share says so first (string 31b); how is the plan's decision 39, drawn as a confirmation |
| Without Optional Details | Makes the copy, shows its summary (7.4), then opens the share sheet from the summary's Continue |
| Ask Each Time | Shows the share step (figure, panel B): **Share Without Optional Details** first, **As Saved** second, neither selected, and Continue unavailable until one is chosen (string 31). Then as the chosen row above |

- **The note** under the choices and on the summary says where the copy goes and that the photo in Photos is not changed (string 105).
- **The name** the copy will have is shown in the step and in the summary (string 51; section 8).
- **The share sheet** is the system's. The actions removed from it are the plan's decision 38; Copy is removed in every option, because the app has no clipboard action (issue 83, decision 4 of 2026-11-18). The sheet is not red in Night Mode, like the system keyboard; the step and the summary before it are.
- **Not available:** when the app no longer holds the photo's file, Share… is dimmed in place with the reason and a pointer to Photos (string 106). A photo that is still saving (section 3) is not in the viewer and has no Share….
- **The copy on disk:** the share sheet is handed a temporary file with complete file protection, in the app's own share folder. It is removed when the share ends or is canceled, when the app next starts, and it is never in Caches or the App Group (section 11).

### 7.4 The copy without optional details, and its summary

- **What the copy holds:** exactly the tag set of "Remove All Optional Details" for its format, with the person's Standard File Tags choice. The image data is the saved file's, byte for byte: the picture is not decoded or encoded again. The saved photo in Photos is not touched.
- **Read back before sharing.** The copy is read with the app's own reader. If anything outside that tag set is found, nothing is shared and the screen says why (string 34).
- **The summary** (figure, panel C) lists each optional detail as "Removed" only when the saved file held it, and "Not in the file" otherwise; the signature, with string 32 when the saved file was signed; the file's name; and "What Stays in the File" (string 33), which carries the sensor-pattern sentence.
- **Formats:** HEIF and JPEG. DNG only if research step R9 shows the rewrite can be verified (decided on issue 83, 2026-11-18). Until then: for a RAW pair, the copy without optional details is the HEIF or JPEG file alone and the summary says so (string 107a); for a RAW-only photo, Without Optional Details is unavailable with the reason and As Saved stays (string 107b).
- **The name "Share Without Optional Details"** replaced "Share Clean", which can be read as untraceable (review decision 8 on issue 83). It is a draft for the string review.

### 7.5 What the wording may say

- Nothing about what a share route does to a file (a new name, new dates, a smaller picture) until device check 15 records it for that route. The Honesty entry for sharing (string 119) is written after the check.
- "No date and no signature" is said of the copy, not of the photo in Photos.
- The sensor sentences are the wording of `docs/research/privacy-claims.md`, claim 9.

### 7.6 Accessibility

- VoiceOver: the row reads title, value, then the hint; on the page each choice is a button with the selected trait on the current one, and the footer is one element after them. In the share step neither option has the selected trait until chosen, and Continue is dimmed with the reason. Each summary row reads as label and value ("Location, not in the file").
- The step has no default action, so Return on a keyboard and the VoiceOver magic tap choose nothing.
- Largest text sizes: the choices and the option name "Share Without Optional Details" wrap and never truncate; the summary becomes label above value.
- Night Mode: rows `#1C0000` on black with red text, as on other settings pages. Selection is a checkmark and a trait, never color alone.
- Voice Control names match the visible labels; Switch Control and Full Keyboard Access reach every action; Escape goes back without sharing.
- The unavailable Share… is dimmed in place, not hidden, and its reason is read.

## 8. File names (issue 133)

Moved here from [release-1.2.md](release-1.2.md), section 3, "File names" (review decision 7 on issue 83; decision 29 of the 1.2.0 plan for photos saved to Photos).

- **The rule.** A name the app gives a file carries the date or time only when the Date and Time detail is in that file. Otherwise the name is random. The rule reads the file as written, not the settings. So a copy without optional details never has a dated name, and with the default details no name the app gives has one.
- **A random name is new each time,** so two copies of one photo cannot be matched by their names. The two files of a RAW pair share one name with their own extensions.
- **Where a name is shown:** in the share step and the summary (string 51).
- **Photos saved to Photos** follow the same rule only if research step R7 shows that Photos keeps the name the app gives. Today the app gives none. If Photos uses its own name whatever the app gives, nothing changes for saves and the documents record what name Photos keeps.
- **Neutral File Names** is an option that makes every name random, for people who keep the date in the file but not in its name (string 25). In 1.1.0 it is drawn under Date and Time on the Details in Each Photo page; its place is the plan's decision 40. It is off by default and not stored in presets.
- **The patterns** are the plan's decision 41. Drawn: `8F3K2QXD.heic` for a random name, and `2026-11-22 14.03.07.heic` for a dated one.
- **Accessibility:** a random name is read letter by letter by VoiceOver, which is slow and of no use; the row's label reads "File name, random" or "File name, with the date and time", and the name itself is available as the row's value.

## 9. The Lock Screen camera's settings copy (issue 134)

Figure: [release-1.1/settings-copy-and-cover.svg](release-1.1/settings-copy-and-cover.svg), panel A. Review finding A1 on issue 83.

### 9.1 What exists

The Lock Screen camera cannot read the app's shared settings. The app hands it a copy each time a setting changes. When that hand-off fails, or the copy is over the system's 4 KB limit, the failure is logged and nothing is shown; the Lock Screen camera goes on using the copy it had. That copy decides, among other things, which details go into a file and whether it is signed.

### 9.2 The design

- **Every change is confirmed.** After the hand-off the app reads the copy back and compares it with what it sent. That this read-back is possible, and reflects what the Lock Screen camera gets, is research step R8; the fallback is in the plan, 3.11.
- **A notice while a change has not arrived** (panel A): at the top of the Settings page the person is on and of the Settings list, an amber warning symbol, the sentence, and **Try Again** (strings 111, 112). Amber always comes with the symbol and words. It is not an alert: the person can keep changing settings.
- **Try Again** hands the copy over again. The app also tries again whenever it returns to the foreground and on each later change. When a hand-off is confirmed the notice goes, and VoiceOver says so once (string 113).
- **A copy that is too large** is the same state with its own sentence (string 112). What is sent in that case is the plan's decision 43.
- **Not on the camera screen and not in Q** in the recommended option (the plan's decision 42).
- **The Lock Screen camera itself** shows nothing about this: it cannot know that a newer copy exists. With no copy at all it uses the first-launch settings: every optional detail removed, signing off, When Sharing on As Saved, Shutter Sound off.
- **What the wording may say:** "hasn't received this change" only when the read-back showed it; if R8 shows the app cannot read the copy back, string 114 replaces it for the cases that cannot be confirmed.

### 9.3 Accessibility

- The notice is one element with the warning's label first ("Warning. The Lock Screen camera hasn't received this change…"), followed by the Try Again button. It is announced once when it appears, at low priority, and not again on each page.
- Largest text: the sentence wraps above the button. Night Mode: red on black, with the symbol; Differentiate Without Color: the symbol and the words carry it.
- Voice Control: "Try Again". Switch Control and the keyboard reach it first on the page.

## 10. The privacy cover (issue 136)

Figure: [release-1.1/settings-copy-and-cover.svg](release-1.1/settings-copy-and-cover.svg), panel B.

### 10.1 What exists

When the app stops being the active app, iOS keeps a picture of its last screen for the app switcher. Three screens cover themselves for that moment: the viewer (plain black), Photo Details (the system background) and the comparison view. The camera screen does not, so the viewfinder's last frame, the Last Photo thumbnail and, with section 3, a photo's early preview can be in that picture.

### 10.2 The design

- **One cover for every screen that can show a photo or its details:** the camera screen, the viewer, Photo Details, the comparison view, and the share step and summary of section 7. It replaces the three covers that exist.
- **The look** (the plan's decision 44; drawn as recommended): the app's black with its mark in the middle, as on the launch screen (`LAUNCH-SCREEN.md`), so the app switcher shows what a start shows. In Night Mode the mark is red. No text.
- **When:** whenever the scene is not active: in the app switcher, with Control Center or the notification list pulled over the app, and under a system alert. It goes as soon as the app is active again, with no animation, so nothing of the screen shows through a fade.
- **The viewfinder** is covered too in the recommended option (the plan's decision 45). The camera keeps running under the cover, and a running series continues; the cover is only drawn.
- **Sheets the system draws** (the share sheet, a confirmation) are above the app's views. Whether the cover hides them in the snapshot is research step R10. If it does not: the share sheet gets a neutral header (the app's icon and a count, no picture), and an open sheet is dismissed when the app stops being active.
- **iPad:** in Split View and Stage Manager a window can be visible without being the active one. R10 records when the cover shows there, and the design follows what it finds: the cover must be in the snapshot, and should not hide the camera while the person is using it beside another app.
- **The Lock Screen camera** gets the same cover.
- **Not covered:** Settings pages, which show no photo. Their notice and values are not photo content.

### 10.3 Accessibility

- The cover is hidden from assistive technologies and announces nothing (the plan's decision 46). It appears only while the app is not the one in use.
- When the app is active again, VoiceOver focus is where it was.
- Reduce Motion: the cover has no animation in either setting.
- Night Mode: no pixel of the cover is anything but black or red.

## 11. Leaving less behind (issue 135)

No screen changes. The plan, section 3.12, lists each place the issue names (system search, Siri suggestions, the clipboard, temporary files, logs, error messages, saved scene state, Handoff), what the code does today, the guard that is added and the check that proves it.

What the interface gains is one Honesty entry (string 121) and matching text in `docs/PRIVACY.md`. Both are written after device check 16, and name only what that check and the automated checks showed. A place that could not be checked is left out of the sentence, not described as clean.

## 12. Limits on the Honesty screen (issue 137)

The limits that issue 83's design listed for the Honesty screen, and that hold without the app's own store. Each is a title and one short paragraph, drawn in the screen's last section, "What No App Can Remove", after the two entries there (the plan's decision 47).

| String | Entry | Says | Source to record before it ships |
| --- | --- | --- | --- |
| (exists) | The Sensor's Noise Pattern | Unchanged: the verified wording of claim 9 | Claim 9 |
| 115 | Deleting Is Not Erasing | Deleting a photo removes the file; it does not overwrite the iPhone's storage | Apple Platform Security, on how files are deleted on flash storage; to be read and cited as a new claim |
| 116 | Copies Outside nope. | A copy shared or saved elsewhere is held by whoever has it; the app cannot reach it | Follows from add-only access (claim on the photo library) and from the app having no network code |
| 117 | Backups to a Computer | A backup to a Mac or PC is not encrypted unless Encrypt local backup is selected | Apple, "About encrypted backups on your iPhone, iPad, or iPod touch" (source H13 in [release-1.2.md](release-1.2.md), 10.9) |
| 118 | Updates to nope. | An update can read what the app can read and could add a network connection; the app cannot protect against its own updates | The hardening research's addendum on issue 83; pairs with the existing entry This Build and the Source (claim 15) |

Rules:

- **Each sentence is checked for accuracy and gets a numbered claim** in `docs/research/privacy-claims.md` with its source and the date read. A sentence whose source does not support it is cut back or left out.
- **No advice and no promise.** Each entry states a limit. The words "safe", "secure" and "guarantee" are not used.
- **Release 1.2.0 adds to these** for captures kept in the app (the lock, backups of the store, Advanced Data Protection, the High-Risk Checklist link); it does not rewrite them.
- Search finds the entries by "delete", "erase", "backup", "update" and "shared".
- Accessibility: the entries are the existing `HonestyStatement` pattern: a heading and a paragraph, one VoiceOver element each, wrapping at every text size.

## 13. Appearance themes (issue 138)

Figures: [release-1.1/themes-overview.svg](release-1.1/themes-overview.svg) (every theme on the camera), [release-1.1/appearance-sheet.svg](release-1.1/appearance-sheet.svg) (the tile and the sheet), and one file for each theme with the camera, Q, Settings and the viewer: [Standard](release-1.1/theme-standard.svg), [Hot Pink](release-1.1/theme-hot-pink.svg), [Green](release-1.1/theme-green.svg), [Red](release-1.1/theme-red.svg), [Blue](release-1.1/theme-blue.svg), [Orange](release-1.1/theme-orange.svg), [Purple and Yellow](release-1.1/theme-purple-and-yellow.svg), [White](release-1.1/theme-white.svg), [Gray](release-1.1/theme-gray.svg).

### 13.1 Decided

Decided by the owner on 2026-11-22, and taken as fixed:

- **Exactly two colors make a theme:** the background (black today), and one color for text and buttons, which replaces both today's white and today's aqua accent. Nothing else can be chosen.
- **The themes provided:** Standard (today's look, and the default), hot pink, earth-tone green, red, blue, orange, purple and yellow, white (a white background with dark text) and gray (a neutral gray background). The text and button color may be black, dark gray or white where a theme needs it.
- **Custom colors** are allowed. They are not checked for contrast, and the app shows no note about readability. Every provided theme must pass the app's contrast rule: 7:1, measured with `MeasuredContrast`.
- **Night Mode is not affected** in any way.
- **The theme and the custom colors are saved with presets.**
- **The entry point is a new fixed tile, last in Q,** that opens a sheet. Q's rule holds: tiles are fixed and opened from the Q button; no tile is edited in place, reordered or swiped.

### 13.2 What exists

Every color in the interface comes from `NopeColor` in `DesignTokens.swift` ([tokens.md](tokens.md)): black for the background, white for text and for a selected control, grays between them (`controlFill` `#333333`, `labelSecondary` `#AEAEB2`, `stripIdle` `#D1D1D6`), and aqua (`fact`, `#40C8E0`) for verified facts and, through `tint`, for links, switches and check marks. Settings pages are the system's dark appearance: rows `#1C1C1E` on black. Night Mode multiplies everything by pure red (`NightModeStyle`). The app has no light appearance and no color setting.

### 13.3 The two colors, and what is worked out from them

A theme is a background **B** and a text-and-buttons color **F**. Every other color of the interface is worked out from the two by one pure function, so there is nothing else to choose:

| Today | In a theme | Rule |
| --- | --- | --- |
| Black: the camera's rows, the viewer, pages | B | |
| White: text, symbols, the shutter, a selected control's fill | F | A selected control is filled with F and its label is B, as white and black are today |
| Aqua: links, switches, check marks, the RAW and Signed marks | F | Standard is the one question: decision 49 |
| Rows of settings pages (`#1C1C1E`), the fill of buttons (`#333333`), panels over the picture | B stepped away from F | So text on them keeps its contrast: lighter under dark text, darker under light text. A background with no room to step away (black under light text, white under dark text) steps toward F, which is what the app does today |
| Secondary text (`#AEAEB2`), idle drive words (`#D1D1D6`) | F mixed toward B | By the share today's grays have (0.69 and 0.83), raised until secondary text keeps 4.5:1 on the background and on rows |
| Separators and outlines | F mixed into the row color | Outlines added by Increase Contrast are F |

The shares and the stepping rule are in the build notes (13.9). With Standard's two colors the function returns today's values exactly, and a unit test holds every token to its 1.0.0 color.

**What a theme never changes:**

- **The picture.** The viewfinder, the Last Photo thumbnail, the photo in the viewer and in Compare are never tinted, in any theme. The guides drawn on the picture itself (grid, level, focus square, histogram, zebras, focus peaking's magenta) stay as they are; controls that sit on the picture with a backing (pills, readouts, the Q panel) follow the theme.
- **Warnings and Stop.** Amber still means a warning and red still means Stop, always with a symbol and words. On Standard they are drawn as today. On any other theme, amber text on the theme's background could not be relied on (amber on orange, on pink, on white), so the same mark is drawn as a filled chip: amber with black words, or red with black words, with a 1.5 pt outline in F. The colors inside the chip are fixed, so it reads the same on any background, including custom ones.
- **Night Mode.** While Night Mode is on, the app draws with Standard's colors under the red multiply, exactly as 1.0.0 does, whatever theme is chosen. The theme returns when Night Mode goes off.
- **What iOS draws:** the launch screen (black with the mark, as it is fixed in the app's bundle), the privacy cover of section 10 (the same look, so the app switcher still shows what a start shows), menus, alerts, the share sheet, the color picker, the keyboard, the Live Activity, the controls in Control Center and the Apple Watch app. System sheets and the keyboard take the light or the dark appearance, whichever suits the background: light when the text color is the darker of the two.
- **Photos.** No theme changes how a photo is captured, developed, signed or saved. The sheet says so (string 127).

### 13.4 The themes provided

The recommended variant of each, as drawn. Ratios are calculated with the WCAG 2.2 formula; the UI tests measure them on screen (13.8). "Text on buttons" is text on an unselected button's fill.

| Theme | Background | Text and buttons | Text on background | Text on rows | Text on buttons | Secondary text (least) |
| --- | --- | --- | --- | --- | --- | --- |
| Standard | `#000000` | `#FFFFFF` (accent `#40C8E0`, decision 49) | 21.00:1 | 17.04:1 | 12.63:1 | 7.86:1 |
| Hot Pink | `#FF69B4` | `#000000` | 7.93:1 | 10.47:1 | 12.79:1 | 4.94:1 |
| Green | `#46552C` | `#FFFFFF` | 8.09:1 | 11.69:1 | 14.85:1 | 4.85:1 |
| Red | `#A3120F` | `#FFFFFF` | 7.92:1 | 11.81:1 | 14.99:1 | 4.54:1 |
| Blue | `#0B3C8C` | `#FFFFFF` | 10.30:1 | 13.84:1 | 16.38:1 | 5.76:1 |
| Orange | `#FF8A1F` | `#000000` | 8.91:1 | 11.41:1 | 13.54:1 | 5.29:1 |
| Purple and Yellow | `#3F2378` | `#FFD60A` | 8.63:1 | 10.89:1 | 12.26:1 | 4.83:1 |
| White | `#FFFFFF` | `#1C1C1E` | 17.01:1 | 13.63:1 | 11.25:1 | 4.88:1 |
| Gray | `#4A4A4A` | `#FFFFFF` | 8.86:1 | 12.45:1 | 15.33:1 | 5.24:1 |

The rule each provided theme must pass, as a unit test on the values and as a measured UI test: text and symbols in F at least 7:1 on the background and on rows; at least 4.5:1 on a button's fill; secondary text at least 4.5:1; a selected control's label at least 7:1 on its fill.

How the list was read, and what else is drawn (decision 50):

- **The color is the background.** The owner's list names white and gray by their backgrounds and allows the text to be black, dark gray or white "where a theme needs it", so each color theme is drawn with the color as its background and a neutral text color. The shade is the brightest or deepest that passes 7:1 with black or with white: hot pink cannot pass with white text and stays hot, so it has black text; red has to be a deep red to carry white text.
- **"Purple and yellow" is drawn as one theme:** a purple background with yellow text and buttons, the one provided theme whose text is a color. Its file also draws Purple and Yellow as two separate themes, in case that was meant.
- **Each color theme's file draws an alternate:** black background with the color as text and buttons. These pass too (7.13:1 or more on rows), but they look like Night Mode in another color, and the red one sits close to Night Mode itself. They are not recommended.
- **Gray:** a mid gray (18% gray, `#777777`) cannot reach 7:1 with black or with white text (4.7:1 and 4.5:1), so a neutral gray theme has to be darker or lighter than that. Drawn: dark gray with white text (recommended, it keeps a dark interface), and light gray `#A6A6A6` with black text as the alternate.
- **White:** dark gray text `#1C1C1E` is drawn; black text is the alternate.
- **Standard** has three drawings: [theme-standard.svg](release-1.1/theme-standard.svg) and decision 49.

A photographer's note, for the owner's choice and not for the interface: a bright or saturated surround changes how the brightness and the colors of the picture beside it are judged. Standard stays the default; the themes are a person's own choice.

### 13.5 The tile and the sheet

Figure: [release-1.1/appearance-sheet.svg](release-1.1/appearance-sheet.svg).

- **The tile.** One new tile, **Appearance** (string 122), symbol `paintpalette`, after Presets: always the last tile. Its value is the theme's name. It is a button tile, like Presets: a tap closes Q and opens the sheet. It cannot be moved, removed or edited, and it has no long-press, drag or swipe action, like every other tile. In full auto on a device with every feature Q has fourteen tiles, still in five rows. At accessibility text sizes, where Q is a list, Appearance is its last row. In the Lock Screen camera the theme applies (it is in the settings copy of section 9) and the tile is left out, as tiles a device cannot offer are: the look is changed in the app.
- **The sheet,** titled Appearance, with Done.
  - **Themes:** ten tiles in two columns (one column at accessibility text sizes): the nine provided themes and Custom. Each tile is drawn in its own two colors, with its name in its own text color, so the list reads the same whatever colors the app has at the moment. A tap applies the theme at once; the camera behind the sheet and the sheet itself change with it. The current theme has a check mark, a 3 pt outline and the selected trait.
  - **Custom Colors:** two rows, **Background** and **Text and Buttons** (string 126), each a system color picker without an opacity control. Choosing a color in either selects Custom. The two colors are kept when another theme is chosen, so Custom can be returned to.
  - **The footer** (string 127) says that themes change the app's colors only, that photos are not changed, that Night Mode keeps its own colors, and that presets save the theme.
  - **While Night Mode is on** the sheet is red on black like every other sheet, and its first footer line says the theme shows when Night Mode is off (string 128). A theme can still be chosen.
- **Custom colors are not checked,** as decided: no contrast test, no warning, no note. They pass through the same function as the provided themes, so rows, fills and secondary text are still worked out from them. What stays readable whatever two colors are chosen, by construction and without any note: the theme tiles in the sheet (each drawn in its own colors), warnings and Stop (filled chips with fixed colors), and Night Mode, which can be turned on from Control Center.
- **Presets** store the theme, or the two custom colors, with their other values; applying a preset applies its look. A preset saved before 1.1.0 holds no theme and leaves the look as it is. **Factory Defaults** returns to Standard and resets the custom colors to Standard's two. People who update from 1.0.0 have Standard.
- **Not in Settings.** The tile is the entry point, as decided. Settings search does not list it in 1.1.0; the how-to guide's page on Q names it.

### 13.6 Standard: white and aqua

Today Standard has two foreground colors. The figure draws the three ways to settle that; the choice is decision 49.

- **(a) Recommended: Standard keeps today's look.** White for text and buttons, aqua for the accent. It is the one theme with a separate accent; every other theme, and Custom, has one color for both. Nothing changes for people who update, and the screen set of 1.0.0 stays true.
- **(b) White replaces aqua.** Links, switches, check marks and the Signed mark become white. A verified fact is still told by its seal and its words, which is already the rule (never color alone).
- **(c) Aqua replaces white.** All text and every button is aqua, 10.56:1 on black.

### 13.7 Accessibility

- **Contrast:** the provided themes by the rule of 13.4. Custom colors are the person's own choice and are not checked (decided).
- **Never color alone:** unchanged. Selection is a fill with a check mark or the selected trait; warnings keep their triangle and words; a signed photo keeps its seal and the word.
- **Increase Contrast:** every unselected control gets its outline, in F. **Reduce Transparency:** panels over the picture are solid. **Smart Invert:** the picture stays excluded, as today. **Differentiate Without Color:** nothing depends on the theme's colors.
- **VoiceOver:** the tile reads "Appearance, Standard, button" with the hint "Opens Appearance." (string 129). In the sheet each theme is a button with its name and the selected trait on the current one; the color rows are the system's pickers with their labels. Labels do not change with the theme.
- **Dynamic Type, right to left, Voice Control, Switch Control, Full Keyboard Access:** the sheet is a standard sheet with standard controls; theme tiles are at least 44 pt tall and wrap their names.
- **The store's accessibility statements.** Before 1.1.0 is described as supporting Sufficient Contrast and Dark Interface, Apple's criteria for those labels are read again and cited, because the app will offer a light theme and unchecked custom colors. What the label says is the owner's to decide; nothing in it is changed without the owner.

### 13.8 Tests

In the plan, section 3.16. In short: unit tests on the palette function (every provided theme against the rule; Standard equal to today's tokens; Night Mode resolving to Standard), storage, presets and the settings copy; UI tests that measure text with `MeasuredContrast` on the camera, Q, Settings and the viewer in every provided theme, that the picture's pixels are the same in every theme, and that Night Mode over a White theme has no non-red pixel; and the Q tests, extended to assert that Appearance is last and that no tile has an edit, reorder or swipe action.

### 13.9 Build notes

- `NopeCore`: new `NopeTheme.swift` (the two colors as 8-bit sRGB values, the provided themes, and the pure function from two colors to the full palette; `Foundation` only). Shares: rows 0.30 and button fills 0.50 toward the extreme away from F, panels 0.15, when that step is at least 1.12:1 from the background; otherwise 0.11, 0.20 and 0.06 toward F (today's `#1C1C1E`, `#333333` and the panel backing). Secondary text 0.69 of the way from B to F, raised in steps of 0.01 until it keeps 4.5:1; idle words 0.83 or the secondary share, whichever is higher.
- `NopeUI`: `NopeColor`'s constants become values read from the current theme, so call sites do not change; a sweep removes the color literals that bypass the tokens. This part is built first and changes nothing on screen (the plan, group T1).
- A color chosen outside sRGB is clamped to sRGB when stored.
- [tokens.md](tokens.md): the color table gains the theme column; the rule "no yellow" becomes "no yellow as a status color".

## 14. Send Feedback, and Report a Problem on GitHub (issue 144)

Figure: [release-1.1/feedback-about.svg](release-1.1/feedback-about.svg).

- **Decided (owner, 2026-11-22):** Send Feedback opens the mail app with a message to hello@photivra.com whose body holds the app's version and the iOS version, visible and editable; the app itself sends nothing. A second row links to the project's issues on GitHub. Rate or Review stays as it is.
- **Place:** a new section, **Feedback**, on the About screen between Source Code and App Store.
- **Send Feedback** (strings 135 to 137, 140) opens one `mailto:` link when the person taps it. The draft has the address, the subject "Photivra Nope Camera feedback", and two lines: the app's version and build, and the iOS or iPadOS version. Nothing else: no device model, identifier, setting, log, photo or attachment. The person edits or deletes the lines in Mail and decides whether to send. The app adds no network code and no mail framework.
- **When the mail link does not open** (no mail app, or none set up to take the link): iOS reports it, and the section shows the address as selectable text with one sentence (string 141). The app does not look for a mail account before the tap, and uses no clipboard code: copying is the system's own text selection, as on the license text.
- **Report a Problem on GitHub** (strings 138, 139) is a plain `https` link to `https://github.com/Photivra/nope-camera/issues`, like the Source Code row. Its footer is the support page's note: issues are public, a free GitHub account is needed, and personal information and photos should be left out.
- **How mail is handled** (string 136b) is the support page's sentence, word for word, so one review covers the site and the app.
- **Accessibility:** each row is a link with a hint that says it leaves the app ("Opens Mail.", "Opens in your browser."), and its address as the value. The footers wrap at every text size. Night Mode: red on black, like the rest of About.
- **Rule to update:** AGENTS.md, "Prevention first", allows an `https` link opened by a tap; the mail link needs the same sentence (decision 54).

## 15. Level: pointing straight up (issue 152)

Figure: [release-1.1/level-up.svg](release-1.1/level-up.svg).

- **Decided (owner):** the two-axis level also shows when the device points straight up, mirroring the top-down level: in within 25° of straight up, out beyond 35°; level when both axes are within 1.0°, released at 1.5°; the level tap; VoiceOver "Pointing straight up, level".
- **The figure is the top-down level's:** a fixed ring and an inner circle that moves toward the side that is raised. Seen from below, with the screen facing down, the circle must still move the way the tilt looks on the screen: tipping an edge toward the person moves the circle toward that edge of the screen. The signs of pitch and roll are set for that and held by unit tests; the device check confirms them by eye.
- **Between the three levels:** the horizon level shows between the two ranges. Each two-axis level has its own hysteresis, so near 30° from straight up or down the level that is showing stays.
- **The tap** (`LevelTapRule`, [level-haptic.md](level-haptic.md)) plays as the up level becomes level, with the same rules and hold-backs as the top-down level. Moving from one level to another never plays it by itself.
- **Words:** VoiceOver value "Pointing straight up, level" and "Pointing up, not level" (strings 142, 143); the Level explanation and the Accessibility page name straight up as well as straight down (string 144); search keywords gain "up", "ceiling", "sky".
- **Accessibility:** as the top-down level: an announcement at low priority when it becomes level, never color alone (the circles meet and thicken), white with a dark edge on the picture, red in Night Mode, no animation beyond the circle's movement, which follows the device.

## 16. "Cryptographically signed" (issue 139)

Figure: [release-1.1/welcome-signing.svg](release-1.1/welcome-signing.svg).

- **Decided (owner):** the Welcome screen says photos can be cryptographically signed, and so does the other text where it makes sense.
- **Welcome, statement 2** (string 130): "You can cryptographically sign each photo, so anyone can check that the file hasn't changed since it was signed. Signing is off until you turn it on."
- **Where else:** the first mention of signing on a screen says "cryptographically"; later mentions on the same screen say "sign" and "signed".
  - Sign Each Photo's explanation (string 131).
  - The Honesty screen's Signing Is Your Choice (string 132).
  - The how-to guide's page that mentions signing, and the store description's first sentence (string 133).
- **Not changed:** the short status words (Signed, Not Signed, Saved and signed.), the VoiceOver results, the watch and Siri answers, and Photo Details, which names Content Credentials and its parts already.
- **"Since it was signed", not "since it was taken".** The issue's sentence says "since it was taken". The signature is made when the file is written, a moment after the capture, and it shows whether the file changed after that. The existing explanation already says "since it was signed"; the new strings keep that.
- **What the word may claim:** that the signature is a cryptographic one (it is: a Content Credentials signature made with a new key for each photo). It does not say who took the photo, and "It is not proof: anyone could make a file that says the same" stays wherever it is today.

## 17. The viewer's Close, where Last Photo was (issue 143)

Figure: [release-1.1/viewer-close.svg](release-1.1/viewer-close.svg).

- **The rule:** in every layout, the frame of Close in the viewer equals the frame of Last Photo on the camera, to the point. Opening the viewer and closing it are then one tap in one place.
- **How:** the viewer's bottom row takes its height and top padding from the layout function that sizes the camera's shutter row (`CameraLayout`), and Close is placed by the rule that places Last Photo. Today the viewer gives the row an 88 pt minimum and none of the spare height. In the column layout (iPad, sideways, the iPhone Duo's inner display) Close takes Last Photo's place in the column the same way.
- **The other actions** stay trailing. When Photo Details, Share… (section 7) and Open in Photos do not fit on one line they wrap into two lines, centered on Close; two lines are 80 pt, inside the smallest row. Close never moves for them.
- **At accessibility text sizes** both screens use full-width rows and the rule does not apply.
- **Tests and figures:** a UI test compares the two frames on each size and layout; the viewer figures in `screens/` are redrawn.

## 18. Disabled controls and contrast (issue 142)

Figure: [release-1.1/disabled-contrast.svg](release-1.1/disabled-contrast.svg).

Today a disabled custom control is drawn at 40% opacity, and the audit helpers exempt disabled controls from the contrast check, as WCAG 2.2 does for inactive components. Calculated on black: a disabled white label is 3.66:1, a disabled secondary caption such as "No RAW" about 2.2:1 (2.96:1 was measured on iPad at the largest text size), and a disabled control in Night Mode about 1.6:1. The owner asked to revisit this so that people can read what is unavailable and why. The options (decision 51):

| Option | Disabled text and symbols | Normal | Night Mode | Cost |
| --- | --- | --- | --- | --- |
| (a) Recommended: a floor of 3:1 | One disabled color, at least 3:1 on what is directly behind it | `#6B6B6B`: 3.94:1 on black, 3.46:1 on its fill | `#C80000`: 3.46:1 | Disabled still looks clearly dimmer than enabled in both modes. With Increase Contrast, 4.5:1 outside Night Mode |
| (b) No exemption | 4.5:1 for text, 3:1 for symbols | `#7A7A7A`: 4.89:1 | `#F00000`: 4.71:1, against 5.25:1 for full red | In Night Mode disabled and enabled are nearly the same red, so disabled would need another sign there, such as a dashed outline |
| (c) As today | 40% opacity, exempt | 3.66:1 and about 2.2:1 | about 1.6:1 | Nothing to build; what is unavailable stays hard to read |

In every option a disabled control keeps what it has today: the not-enabled trait, and its reason in words where there is one (the "No RAW" caption, a footer, a hint). With (a) or (b):

- The disabled look stops being an opacity. Labels and symbols take the disabled color; the fill keeps a dimmed fill; an outline, where there is one, keeps 3:1.
- The audit helpers lose the exemption. Instead, each disabled state of each custom control is measured with `MeasuredContrast` in normal colors, Night Mode and Increase Contrast, against the option's floor.
- In a theme (section 13) the disabled color is worked out by the same function: F mixed toward B until the floor is left.
- [tokens.md](tokens.md) and [ACCESSIBILITY.md](ACCESSIBILITY.md) state the rule; AGENTS.md by decision 54.

## 19. A preview inside RAW files (issue 131)

Figure: [release-1.1/small-changes.svg](release-1.1/small-changes.svg), panel A.

- **Decided (owner):** a saved DNG holds a small embedded preview, so Finder and other file browsers show a thumbnail instead of a generic icon.
- **What exists:** the DNG holds the RAW image only. `docs/research/capture-and-file-settings.md` lists embedded thumbnails as "fixed off", for a reason that applies to developed files: a thumbnail is a second copy that can keep pixels after an edit. In a DNG the RAW data itself stays whole after any edit, so a preview made from it holds nothing the file does not already hold. HEIF and JPEG files are not changed: browsers already draw them from the image itself, and they keep no embedded thumbnail.
- **What the preview is:** one JPEG picture, made from the same RAW data as the file, upright, with no metadata of its own. Who makes it, the app's developer or the camera, is decision 52; its size and quality are set from measurements (research step R11), within about 300 KB.
- **Honesty.** The preview is a processed picture inside a file whose point is as little processing as the camera allows, so it is named wherever the file's contents are listed, and never called the photo:
  - Photo Details, What's in This Photo: a row "Preview for file browsers" with its format and size, and the file size line names the preview's share (strings 145, 146).
  - The Honesty screen: one entry (string 147).
  - `docs/PRIVACY.md`: the allowlist gains the preview's directory and its tags, with the exact set asserted by the metadata tests.
- **Signing:** the preview is in the file before the file is signed, so the signature covers it like the RAW data. A signed DNG whose preview is changed afterward no longer verifies.
- **Privacy:** the preview's directory holds only what a picture needs to open (size, compression, orientation). The read-back treats any other tag in it like any tag off the allowlist: removed, or the photo is not saved.
- **Sharing a copy (section 7):** the preview is image data, not an optional detail. A DNG copy without optional details, if research step R9 passes one, keeps it.
- **The gates** (whether browsers use a preview placed where the app can place it, and what it costs) are in the plan, section 4.2.

## 20. Photo Details on iPad (issue 140)

No change to how Photo Details looks.

- **The problem:** on iPad, with Photo Details open as a system sheet over the viewer, the viewer's elements stay in the accessibility tree beside the sheet, and the audit reports them. Hiding the presenter is ignored while a system sheet is up. 1.0.0 ships with a scoped audit exception.
- **The design:** where the width is regular (iPad, and the iPhone Duo's inner display if it shows the same), Photo Details is presented by the viewer itself, inside the viewer's own full-screen cover: a card of the system form sheet's size and corner radius over a dimmed viewer. The viewer behind is hidden from assistive technologies and cannot be touched. Where the width is compact (iPhone) the system sheet stays, because it has no such finding there and system elements are used wherever they work.
- **The card behaves as the sheet did:** Done closes it; so do a tap outside it, Escape and VoiceOver's escape gesture. Focus moves to its title when it opens and returns to Photo Details in the viewer when it closes. It is modal for VoiceOver, Switch Control and the keyboard. With Reduce Motion it fades; otherwise it rises like a sheet. The privacy cover of section 10 covers it like the sheet.
- **First step:** run the audit again on the current iPadOS releases. If the system sheet no longer leaves the viewer in the tree on any supported release, nothing is built and the exception is removed.

## 21. Small changes to words and states (issues 148, 149, 150)

Figure: [release-1.1/small-changes.svg](release-1.1/small-changes.svg), panels B and C.

- **Open in Photos (issue 148).** The buttons open Photos through an address Apple does not document. If iOS reports that it did not open, the viewer, or the camera for the Open Photos spot, says "Photos couldn't be opened." with the warning symbol (string 148), announced once to VoiceOver. The button stays: hiding it would leave no way to try again, and the message already says what happened.
- **Siri and Shortcuts (issue 149).** A self-timer that reaches zero while the photo cannot be taken answers that the timer finished and no photo was taken (string 149), not that it was canceled. A request that waits for a photo stops waiting after a limit and says that it cannot confirm the photo (string 150); the camera is then free for the next request. The limit is the exposure time plus a margin set from the timings of research step R3.
- **Live Activity (issue 150).** Each update carries a stale date a little after the next expected change: the next photo of an interval series, the end of a countdown. If the app's process has ended and the date passes, the activity stops saying "Running", stops counting down, and says that it may be out of date, with the last count it knew (string 151). Opening the app ends the leftover activity, as today. How iOS draws a stale activity in each place (the Lock Screen, the Dynamic Island, the Apple Watch's Smart Stack) is a device check; the wording is used only where the app draws the text.

## 22. Changes without a screen

These issues change tests, CI, the release steps or internal behavior. Their designs are in the plan.

| Issue | What | Plan |
| --- | --- | --- |
| 141, 153 | The Live Activity explanation reported as clipped text in Settings; the audit exception that covers it | 3.19 |
| 146, 147, 151 | UI tests that do not run, are skipped, or fail on iPad or iOS 26 | 3.23, 3.24, 3.28 |
| 154 | A late hardware button release after a canceled hold | 3.30 |
| 155 | The release steps for the App Store record | 3.31 |
| 157, 158, 159 | Shorter UI test shards, flaky tests, one retry | 3.32 to 3.34 |
| 160, 161, 162 | TestFlight and the store page from CI, and UI tests on demand | 3.35 to 3.37; figure [release-1.1/ci-release.svg](release-1.1/ci-release.svg) |

## 23. Draft strings added on 2026-11-22

For the Honesty review, as section 6. Numbers continue from 121.

| # | Where | Text | H |
| --- | --- | --- | --- |
| 122 | Q, tile | Appearance | |
| 123 | Sheet, title and button | Appearance · Done | |
| 124 | Sheet, theme names; the tile's value | Standard · Hot Pink · Green · Red · Blue · Orange · Purple and Yellow · White · Gray · Custom | |
| 125 | Sheet, headings | Themes · Custom Colors | |
| 126 | Sheet, color rows | Background · Text and Buttons | |
| 127 | Sheet, footer | Themes change nope.'s colors only. Your photos are not changed. Night Mode keeps its own colors. Presets save the theme. | H |
| 128 | Sheet, footer, while Night Mode is on | Night Mode is on. The theme you choose shows when Night Mode is off. | |
| 129 | Q, tile, VoiceOver hint | Opens Appearance. | |
| 130 | Welcome, statement 2 | You can cryptographically sign each photo, so anyone can check that the file hasn't changed since it was signed. Signing is off until you turn it on. | H |
| 131 | Sign Each Photo, explanation | Adds a cryptographic signature to each photo. It lets anyone check that the photo hasn't changed since it was signed. The signature names nope. and its version as the maker. It is not proof: anyone could make a file that says the same. | H |
| 132 | Honesty, Signing Is Your Choice | Photos aren't signed unless you turn on Sign Each Photo in nope.'s settings. A cryptographically signed photo lets anyone check that it hasn't changed since it was signed. The signature names nope. and its version as the maker. It is not proof: anyone could make a file that says the same. It doesn't identify you or your device. | H |
| 133 | Store description, first sentence | Photivra Nope Camera takes photos with as little processing as the camera allows, can cryptographically sign each one, and keeps nothing that tracks you. | H |
| 134 | About, section heading | Feedback | |
| 135 | About, row | Send Feedback | |
| 136 | Its footer | Opens Mail with a message to hello@photivra.com. It starts with the app's version and your iOS version; you can edit or delete them. Photivra Nope Camera sends nothing itself. | H |
| 136b | The same footer, second paragraph (the support page's sentence) | If you write, your message and your email address are forwarded to us by Cloudflare Email Routing and stored by our email provider. We use them only to answer you. We delete messages after 1 year, and sooner if you ask. | H |
| 137 | Send Feedback, VoiceOver hint | Opens Mail. | |
| 138 | About, row | Report a Problem on GitHub | |
| 139 | Its footer | Opens in your browser. Issues are public and need a free GitHub account. Don't include personal information, and attach a photo only if you're willing to make it public: a photo can carry its location and other details. | H |
| 140 | The mail draft: subject, and the two lines | Photivra Nope Camera feedback · Photivra Nope Camera %1$@ (%2$@) · iOS %@ (iPadOS %@ on iPad) | |
| 141 | About, when the mail link did not open | Mail didn't open. You can write to this address from any mail app. Touch and hold the address to copy it. | |
| 142 | Level, VoiceOver, pointing up and level | Pointing straight up, level | |
| 143 | Level, VoiceOver, pointing up and tilted | Pointing up, not level | |
| 144 | Level, explanation | A horizon bar, or a two-axis level when you point straight down or straight up. On iPhone, you feel a tap when it's level. Uses the motion sensors only while it shows. | |
| 145 | Photo Details, What's in This Photo, row and value | Preview for file browsers · JPEG, %lld px | H |
| 146 | Its explanation | The preview is a small processed picture that nope. makes from the same RAW data, so Finder and Files can show a thumbnail. The RAW data is not changed by it. | H |
| 147 | Honesty, an entry | A Preview Inside RAW Files · Each RAW file holds a small preview picture, made from the same RAW data, so file browsers can show a thumbnail. The preview is processed; the RAW data is not. The preview holds no details of its own, and a signature covers it with the rest of the file. | H |
| 148 | Viewer and camera, when Photos did not open | Photos couldn't be opened. | H |
| 149 | Siri and Shortcuts, the timer reached zero and the photo could not be taken | The timer finished, but the photo couldn't be taken. No photo was taken. | H |
| 150 | Siri and Shortcuts, the wait for a photo ran out | nope. didn't finish taking the photo in time. Open nope. to see whether it was saved. | H |
| 151 | Live Activity, out of date | May be out of date · %@ when last updated · Open nope. to see the series | H |

Notes:

- **122 to 129.** The theme names are plain color words. "Purple and Yellow" follows decision 50.
- **130 to 133** follow section 16. 133 changes `store/metadata/en-US/description.txt`; the promotional text ("Signing if you want it.") is short and stays.
- **136, 139, 136b** are the support page's wording (`site/content/support.json`). 136b names how mail to the address is handled; it is reviewed with the site's sentence. The About screen uses the full name.
- **140** is not shown in the app: it is the text of the draft. "iOS" or "iPadOS" comes from the system, not from joined fragments.
- **146 and 147** say "that nope. makes" only if decision 52 is (a). With (b) they say "made by the camera from the same capture".
- **149 and 150** replace "The timer was canceled. No photo was taken." only for the cases named; a canceled timer keeps that answer.
- **151** is used where the app draws the activity's text; what iOS adds to a stale activity is recorded in device check 23.
