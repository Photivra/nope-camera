# Designs for 1.1.0

Status: proposed 2026-11-21 for release 1.1.0. Not built, not yet accepted, and not in the screen counts of [README.md](README.md). Decisions already recorded on an issue are taken as fixed and marked "decided"; everything else is a proposal, and the open choices are collected in [docs/plans/1.1.0.md](../plans/1.1.0.md), section 8. All wording is a draft until the Honesty review. The figures are SVG files in [release-1.1/](release-1.1/); they are sketches of layout, states and wording, not pixel-exact screens. The full screen set (`screens/`) is redrawn when each design is accepted and built.

This document covers the user-facing parts of three issues. Issue 85 (CI) has no interface; its diagram is here because the figures are kept together. Issue 114 (Apple Vision Pro) and issue 127 (the usability test) have no screens: see the plan, sections 3.1 and 3.7, and [docs/research/usability-test-plan.md](../research/usability-test-plan.md).

| Section | Issue | What |
| --- | --- | --- |
| 1 | 120 | The Show Controls button in clean view, made quieter |
| 2 | 128 | Shutter Sound |
| 3 | 129 | Capture feedback and save status |
| 4 | 83 | Moved to release 1.2.0: [release-1.2.md](release-1.2.md) |
| 5 | 85 | Which CI jobs a change runs (diagram only) |
| 6 | | Every draft string, for the Honesty review |

Evidence note: everything about today's behavior was read from the code on branch `n100-H` at `9cef00d`. Nothing here was measured on a device or run on a simulator. Contrast ratios are calculated from the color values with the WCAG 2.2 formula (the same one `MeasuredContrast` uses in the UI tests); they are not measured from a screen. Each statement that needs a device is listed as a device check in the plan, section 7.

Q, the quick menu, is not changed by anything here: no tile is added, removed, moved or made editable, and Q still opens only from its button. The new settings are in Settings.

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

Moved to release 1.2.0 on 2026-11-21, with its figures and its strings (13 to 56, numbers unchanged): [release-1.2.md](release-1.2.md). What the saving state of section 3 shows with Lock Captures on is designed there.

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

Strings 13 to 56 are for issue 83 and moved with it to [release-1.2.md](release-1.2.md), section 9, with their numbers unchanged.
