# Designs for 1.1.0

Status: proposed 2026-11-21 for release 1.1.0. Not built, not yet accepted, and not in the screen counts of [README.md](README.md). Decisions already recorded on an issue are taken as fixed and marked "decided"; everything else is a proposal, and the open choices are collected in [docs/plans/1.1.0.md](../plans/1.1.0.md), section 8. All wording is a draft until the Honesty review. The figures are SVG files in [release-1.1/](release-1.1/); they are sketches of layout, states and wording, not pixel-exact screens. The full screen set (`screens/`) is redrawn when each design is accepted and built.

This document covers the user-facing parts of five issues. Issue 85 (CI) has no interface; its diagram is here because the figures are kept together. Issue 114 (Apple Vision Pro) and issue 127 (the usability test) have no screens: see the plan, sections 3.1 and 3.7, and [docs/research/usability-test-plan.md](../research/usability-test-plan.md).

| Section | Issue | What |
| --- | --- | --- |
| 1 | 120 | The Show Controls button in clean view, made quieter |
| 2 | 128 | Shutter Sound |
| 3 | 129 | Capture feedback and save status |
| 4 | 83 | Save Photos To, the Captures library, export, Share clean, Lock Captures |
| 5 | 85 | Which CI jobs a change runs (diagram only) |
| 6 | | Every draft string, for the Honesty review |

Evidence note: everything about today's behavior was read from the code on branch `n100-H` at `9cef00d`. Nothing here was measured on a device or run on a simulator. Contrast ratios are calculated from the color values with the WCAG 2.2 formula (the same one `MeasuredContrast` uses in the UI tests); they are not measured from a screen. Each statement that needs a device is listed as a device check in the plan, section 7.

Q, the quick menu, is not changed by anything here: no tile is added, removed, moved or made editable, and Q still opens only from its button. The new settings are in Settings; the Captures library opens from the Last Photo spot and from Settings.

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
- **Haptic and sound at the same moment** (owner): when the sound will play, the shutter haptic is given on the capture's "will capture" event, where the system plays the sound, instead of on the press, so the two land together for every photo. With the sound off, the haptic stays on the press.

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

One rule for every surface: **feedback at capture says a photo was taken; only a confirmed save says it was saved.** "Confirmed" means what `.saved` means today: the files passed the metadata read-back and the destination (Photos, or the app's store with issue 83) accepted them.

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

Figures: [release-1.1/save-photos-to.svg](release-1.1/save-photos-to.svg), [release-1.1/captures-library.svg](release-1.1/captures-library.svg), [release-1.1/export-share-clean.svg](release-1.1/export-share-clean.svg).

Issue 83 is the specification, including its ten owner decisions of 2026-11-18. This section adds the screens, the entry points and the wording, and does not repeat the issue. Where the two differ, the issue is right.

### 4.1 Settings › Privacy

The group gets the two rows `SETTINGS-PLAN.md` reserved, above Assistant Access: **Save Photos To** (value: Photos, or nope only) and **Lock Captures** (value: Off, or On). Five rows in the group.

**Save Photos To** (a page):

1. The choice: Photos, nope only. Footer: what the choice covers and does not (strings 20, 21).
2. "Kept in nope.": a **Captures** row with the count and size, which opens the library. Shown whenever the app holds captures, whichever choice is selected. With Lock Captures on and locked, the row shows no count or size.
3. **Leave Out of Backups** and **Neutral File Names**, both off by default, each with its trade-off.
4. **Delete All Captures…**, shown when the app holds captures.
5. When the device has no passcode: a notice at the top that captures are not protected at rest (string 24).

**Lock Captures** (a page): the switch; "Lock Again" (Immediately, After 1 Minute, After 5 Minutes); Passcode Only; the limits in the footer. The switch is unavailable, with the reason, when the device has no passcode.

In the Lock Screen camera both rows are read only (decided).

### 4.2 The Captures library

- **Entry points:** the Last Photo spot, and the Captures row on the Save Photos To page. Not Q.
  - While the app holds captures, the Last Photo spot opens the viewer for this session's photos as today; the viewer's Open in Photos becomes **Show in Captures** for a photo kept in the app.
  - Before the first photo of a session, where the spot today holds Open Photos, it holds **Captures** (a stack symbol) when the app holds captures.
  - With Lock Captures on: a neutral marker in the spot (the stack symbol, no thumbnail), which opens the library after authentication (decided).
- **Layout:** a grid of square thumbnails, newest first, in sections by day; an adaptive grid (three columns on an iPhone upright, more on wider windows). Each cell shows the format chip (RAW, HEIF, JPEG, or RAW + HEIF as one item) and the signed seal where it applies. At the largest text sizes the grid becomes a list: thumbnail, date, format, size.
- **One capture:** opens in the existing Last Photo viewer (paging, zoom, Photo Details), with Share, Save to Files, Save to Photos and Delete in its menu.
- **Select:** Select, Select All, and a section's "Select" for a whole day; then Share…, Save to Files…, Save to Photos, Delete. Progress and a summary for several ("9 exported. 1 could not be exported: …").
- **Empty:** "No Captures" with one sentence on what appears here.
- **Locked:** the lock symbol, "Captures Are Locked", Unlock. No thumbnails, counts, dates or sizes are drawn behind it.
- **Privacy cover:** while the library, a capture or Photo Details is on screen and the scene becomes inactive, the cover replaces the content (the viewer's existing cover, extended).
- A session, for "export a whole session", is a day's section in 1.1.0. The manifest stores no session identifier.

### 4.3 Getting captures out

- **Share…** first asks As Saved or Share Clean (figure, panel A), then opens the system share sheet with Copy removed. Share Clean shows its summary first (panel B), read back from the copy. If the read-back fails, nothing is shared and the screen says why.
- **Save to Files…** opens the system's folder picker. A note before it, every time: the copy is outside the app's protection (string 30).
- **Save to Photos** makes a copy in Photos (add-only), keeping a RAW pair as one asset.
- With Lock Captures on, each export asks for authentication first unless the library was unlocked within the re-lock time.

### 4.4 Delete

- One capture or a selection: a confirmation that states the count and that there is no Recently Deleted (decision 15 asks whether a single delete needs it).
- **Delete All Captures…**: the confirmation states the count, that it cannot be undone, and what it does not reach (figure, panel C).

### 4.5 Saved wording

With nope only, the saved sentence names the place: "Saved in nope." and its signed and unsigned forms (strings 16 to 18; decision 14). The Photos sentences are unchanged.

### 4.6 Accessibility

- VoiceOver: each capture is one element, "Photo, 21 November, 2:14 PM, RAW, signed", with actions Share, Save to Files, Save to Photos, Delete. Selecting is a trait, not a color. The locked screen reads its title, sentence and Unlock, nothing else.
- Dynamic Type to the largest sizes: the list layout above; export and delete actions wrap, never truncate.
- Night Mode: thumbnails drawn red like the viewer; settings rows `#1C0000` on black as elsewhere.
- Voice Control names match the visible labels. Switch Control and Full Keyboard Access reach every action; Escape closes the library.
- Authentication prompts are the system's.

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
| 13 | Settings › Privacy, row | Save Photos To | |
| 14 | Its choices | Photos · nope only | |
| 15 | Settings › Privacy, row | Lock Captures | |
| 16 | Saved, nope only, signed | Saved in nope. and signed. | H |
| 17 | Saved, nope only, signing off | Saved in nope. Not signed: signing is off in Settings. | H |
| 18 | Saved, nope only, other unsigned reasons | Saved in nope. Not signed: (the existing reason) | H |
| 19 | Library title; Last Photo spot button | Captures | |
| 20 | Save Photos To footer, nope only | New photos are kept in nope. and are not added to Photos. Photos already in Photos stay there: nope. can add photos but can't read or move them. | H |
| 21 | Save Photos To footer, Photos, while captures are held | New photos go to Photos. The captures already in nope. stay here until you export or delete them. | H |
| 22 | Under the Captures row | Deleting the app deletes these. Export the ones you want to keep. | H |
| 23 | Leave Out of Backups, explanation | Captures are in iPhone and iCloud backups unless left out. Left out, they are lost if the phone is lost and do not move to a new phone. | H |
| 24 | Notice with no passcode | This iPhone has no passcode, so captures kept in nope. are not protected when it is locked. | H |
| 25 | Neutral File Names, explanation | Exported and shared copies, and photos saved to Photos, get a random name without the date and time. | H |
| 26 | Lock Captures, explanation | Viewing, sharing and deleting captures kept in nope. asks for Face ID or the passcode. Taking photos never asks. | H |
| 27 | Lock Captures footer | A gate inside the app, not encryption. Anyone with the iPhone's passcode can open it. It does not cover copies in Photos or already shared. | H |
| 28 | Lock Again footer | Always locked after the app is closed or the iPhone locks. | H |
| 29 | Locked library | Captures Are Locked · Use Face ID or the passcode to see them. · Unlock | |
| 30 | Before Save to Files and the share sheet | The copy leaves nope.'s protection. The capture in nope. is not changed. | H |
| 31 | Share choices | As Saved: every detail in the file, and its signature. · Share Clean: optional details removed from the copy. | H |
| 32 | Share Clean summary, signature | The copy is not signed: a signature does not survive a change to the file. | H |
| 33 | Share Clean summary, what stays | Color and size data that the file needs to open can point to the phone model. The picture itself is not changed. | H |
| 34 | Share Clean, check failed | Not shared: nope. couldn't confirm that the copy holds only the details listed. | H |
| 35 | Delete All, title and button | Delete %lld Captures? · Delete %lld Captures | |
| 36 | Delete All, message | This deletes every capture kept in nope., now. It can't be undone. It does not reach copies in Photos, in iCloud, in backups or already shared. | H |
| 37 | Delete, one or several | There is no Recently Deleted. This can't be undone. | H |
| 38 | Empty library | No Captures · Photos you keep in nope. appear here. | |
| 39 | Face ID usage text (Info.plist) | nope. uses Face ID to unlock the captures you keep in the app. | H |
| 40 | Viewer, for a photo kept in the app | Show in Captures | |

The limits issue 83 lists under "Limits to state plainly" (what stays in a file, the sensor pattern, screenshots, that the app cannot hide that it is installed) are Honesty screen entries and `docs/PRIVACY.md` text, written with part 6 of the issue once the device checks are in; they are not drafted here.
