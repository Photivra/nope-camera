# Device feedback for 1.0.0

Design version: 1.0.0, direction B · Reach. Proposed 2026-11-18; not yet part of the plan or of the screen counts in [README.md](README.md). Nothing here is built.

Five changes asked for after Photivra Nope Camera 1.0.0 was used on an iPhone 16 Pro Max, designed as one batch. The figures are in [device-feedback-1.0.html](device-feedback-1.0.html) (`screens/feedback-*`, 13 figures). Wording is US English and every new sentence is a draft for the Honesty review. The owner's decisions, each with a recommendation, are in section 7.

Rules that hold for all of it: Q's tiles stay as they are and Q opens only from its button; nothing is read from the photo library and no photo or preview is stored ([PRIVACY.md](../PRIVACY.md)); no number is shown that the device does not report and a device check has not confirmed; thresholds marked provisional are set by the device checks listed with them.

| # | Item | Change, in one line |
| --- | --- | --- |
| 1 | The empty Last Photo spot | Before the first photo since the app opened, the spot holds a button that opens the Photos app |
| 2 | Use the Whole Range | Never dimmed. While the whole range is in use the row shows a check mark and is selected |
| 3 | Close-up focus | A new Honesty entry, reachable from the close-up hint |
| 4 | "Hold it steady or use a tripod." | Never with Manual Controls on. With them off, only when the shutter in use is slower than the lens can be held at, counting its stabilization |
| 5 | The focus square and Lock | Fade three seconds after a tap. A locked square never fades |

## 1. The empty Last Photo spot

### Current behavior

- The app has add-only access to Photos (`PHPhotoLibrary.requestAuthorization(for: .addOnly)`, `PhotoKitLibrary.swift`). It cannot read the library.
- The thumbnail and the viewer's previews are made from the file just saved and kept in memory until the app quits (`SessionPhotos`; PRIVACY.md, "Last photo and its details").
- `ThumbnailSlot` (`CaptureFeedback.swift`) draws nothing until the first photo of a session. Figure `camera-first-photo` draws an empty outline; the build draws nothing at all.
- So each time the app starts, the place beside the shutter is empty, and nothing says why.

### Design

Before the first photo since the app opened, the spot holds a button, Open Photos, that opens the Photos app (figures `feedback-photos-button`, `-night`, `-ipad`).

- **Look.** The thumbnail's size and corner (`NopeSize.thumbnail`, `NopeRadius.small`), the fill of a control on the black rows (`NopeColor.controlFill`), and the symbol `photo.on.rectangle`, the one Open in Photos already uses. No ring: the ring belongs to a photo. The pressed, night mode and Increase Contrast states are those of every icon button; the only difference from `NopeIconButtonStyle` is the rounded square in place of the circle. No new token.
- **Press.** It calls `openPhotosApp`, the action Open in Photos in the viewer already uses. It never opens the viewer: there is nothing to show.
- **When it shows.** While all of these hold: no photo has been saved since the app opened; no photo is being taken or saved (the spinner has the spot then); no countdown or series is running or paused (leaving the app would interrupt it); the controls are shown (clean view has Show Controls there); and `openPhotosApp` is not `nil`.
- **When a photo is saved.** The thumbnail takes the spot with today's transition, and from then on a press opens the viewer, as today. Open Photos does not come back in that session; Open in Photos is in the viewer.
- **Lock Screen camera.** `openPhotosApp` is `nil` there, because a locked iPhone cannot open another app, so the spot stays empty as it is today (figure `feedback-photos-button-lock`). No button is drawn that does nothing.
- **Photos access declined.** The button is still shown: opening the Photos app needs no access. Saving is covered by the failure banner, as today.
- **iPad and iPhone Duo.** The same button in the same spot: under the shutter in the column layout, beside it in the stacked layout. At accessibility text sizes it grows to 64 pt with Last Photo. Folding and unfolding change nothing about it.
- **What it must not promise.** The app opens Photos with the `photos-redirect://` URL (`NopeApp.swift`), which Apple does not document and which cannot name a photo. Photos opens where the person left it. No label, hint or sentence says it shows the last photo.

Why the spot starts empty is said in two places: the button's hint for VoiceOver, and a new Honesty entry (wording below; figure `feedback-honesty`). Nothing is added beside the button; the shutter row has no room for a sentence, and the app has no coach marks.

Not proposed: keeping a small picture on the device between sessions, or asking for read access to the library. Both break the privacy rules this item must keep.

### Wording (drafts)

| String | Where | Catalog |
| --- | --- | --- |
| Open Photos | The button's name for VoiceOver, Voice Control and the Large Content Viewer | Localizable |
| Photos | Second Voice Control name | Localizable |
| Opens the Photos app. | The button's hint | Localizable |
| Your Photo Library Is Never Read | Honesty heading, under What nope. Never Does, after No Data Collected | Honesty |
| nope. asks only for permission to add photos. With that permission, iOS doesn't let nope. see or change what is in your library. The small pictures nope. shows of the photos you just took are kept in memory only, until nope. closes. So each time nope. opens, the Last Photo spot starts with a button that opens the Photos app. | Honesty statement | Honesty |

For the Honesty review: "see or change" must match Apple's description of add-only access, cited as a new claim in `docs/research/privacy-claims.md` (`PHAccessLevel.addOnly`). "In memory only" repeats PRIVACY.md and must change with it if that ever changes. The statement says nothing about files kept for Try Again after a failed save; it must not be widened to "keeps no copy" without checking that path.

### Accessibility

- VoiceOver: "Open Photos, button", hint "Opens the Photos app." It takes Last Photo's place in the order (row 14 of the table in [ACCESSIBILITY.md](ACCESSIBILITY.md)). If VoiceOver's focus is on it when the first photo is saved, focus stays on the spot, now Last Photo, and the save sentence is announced as today.
- Voice Control: "Open Photos" or "Photos". Large Content Viewer: the symbol with "Open Photos".
- Switch Control and the keyboard: first item of the shutter row group; Tab reaches it; Space or Return presses it.
- Target 52 × 52 pt. Sideways, the symbol turns upright with the other controls. Right to left, the row mirrors and the symbol does not.
- Night mode: an off control, outlined in `nightOutline` (3.1:1) with the symbol in `night` (5.2:1). Default: the symbol is white on `controlFill`, 12.6:1.
- Reduce Motion: the change to the thumbnail is a crossfade, as today.

### Tests

- Unit: the rule for what the spot holds as a pure function (nothing, Open Photos, the spinner, Last Photo) over photos, busy, series state, clean view and whether Photos can be opened; every branch.
- UI, each with the accessibility audit: Open Photos is there at launch with its name and hint, and Photos comes to the front when it is pressed; after one photo, Last Photo is there and Open Photos is not; relaunch shows Open Photos again; the Lock Screen camera has neither before a photo; a running Interval or Astro series and a countdown before the first photo show neither; night mode is all red; the largest text size; right to left; the iPad shard.
- Update: the tests and docs that expect an empty spot before the first photo (`docs/TESTING.md`, `docs/BUILDING-AN-INTERFACE.md`, PRIVACY.md "Last photo and its details", ACCESSIBILITY.md row 14, BUILD-SPEC.md 3.7). On acceptance figure `camera-first-photo` is replaced by `feedback-photos-button`.

### Device checks

- **P1** On iPhone 16 Pro Max and an iPad, on the iOS version released with 1.0.0: Open Photos opens the Photos app from the camera, from a cold start and after a relaunch.
- **P2** What Photos shows when opened this way, so no wording promises more.
- **P3** Take a photo, quit the app, open it: Open Photos is there; take a photo: the thumbnail replaces it.
- **P4** The Lock Screen camera before its first photo: the spot is empty and nothing there can be pressed.
- **P5** iPhone Duo: fold and unfold with Open Photos showing.

## 2. Use the Whole Range

### Current behavior

Bracket Settings, Focus, has the button Use the Whole Range under Nearest Focus and Farthest Focus (`FocusBracketSections`, `FocusBracketControls.swift`). It was meant to be disabled while the range is already 0 to 1. The disabled row is drawn at 40% opacity; in night mode that is red at 40% on the row's near-black, about 1.6:1 against the 4.5:1 the audit asks for, and the audit failed on iPad. The build therefore never disables it: the row looks the same in both states, and pressing it with the whole range set changes nothing.

### Design

The row keeps its place, its words and its full contrast in both states. While the whole range is in use it shows a check mark at its trailing edge and has the selected trait (figures `feedback-whole-range`, `feedback-whole-range-night`).

- It is never disabled and never dimmed. Pressing it while selected changes nothing, as pressing the selected choice of a picker does.
- With another range set there is no check mark, as in figure `bracket-focus-settings`. Pressing it sets Nearest Focus to 0.00 and Farthest Focus to 1.00, and the check mark appears.
- The state is said three ways, none of them color or opacity: the check mark, the two values above it, and the trait and value for VoiceOver.
- This is the manner the camera already uses for a control with nothing left to do: Reset on the exposure dial and Auto on a manual dial are shown selected, not dimmed (`AutoExposureDial`: "a dimmed button fails the contrast audit over the picture").

Contrast, measured from the token values: in night mode the words and the check mark are `night` on the row, 5.2:1 (text needs 4.5:1, a symbol 3:1). The dimmed row this replaces was 1.6:1. In the dark form they are white on the row; in the light form, black on white.

A rule for the folder follows from it, proposed for [tokens.md](tokens.md) (Button types): a control that has nothing to do because its result is already in place is shown selected; dimming is kept for a control that cannot be used now, and is never the only sign.

### Wording (drafts)

| String | Where | Catalog |
| --- | --- | --- |
| Use the Whole Range | Unchanged | Localizable |
| In use | VoiceOver value while the whole range is set | Localizable |

### Accessibility

- VoiceOver: "Use the Whole Range, button" with another range set; "Selected, Use the Whole Range, In use, button" with the whole range. Focus stays on the row when it is pressed, and the new value is read.
- Voice Control and Switch Control: the name is the same in both states, and the row is always there, so nothing moves.
- Largest text sizes: the check mark stays at the trailing edge of the first line. Right to left: it moves to the other edge.
- Differentiate Without Color, Increase Contrast: nothing depends on color.

### Tests

- Unit: `FocusBracketSettings.isWholeRange` at 0 and 1, and just inside each end (exists; keep).
- UI (`FocusBracketUITests`): with the whole range the row is enabled, selected and has the value "In use"; after an end is set on the picture it is not selected; pressing it returns both values to 0.00 and 1.00 and selects it. The accessibility audit of Bracket Settings, Focus, in night mode with the whole range set, on the iPhone and the iPad shards, with no contrast finding skipped; the same at the largest text size and right to left.

### Device checks

- **W1** Night mode on an iPad, Bracket Settings as a sheet at its regular width: the check mark and the words are easy to read in a dark room.
- **W2** VoiceOver reads the two states as written above.

## 3. Close-up focus

### Current behavior

- The app never changes lenses by itself. Each lens button selects one camera, and the photo comes from that camera's sensor. When autofocus stays at the lens's nearest position, the hint "The subject may be too close to focus. Try Ultra Wide." offers Switch to Ultra Wide and Dismiss (`CloseUpSuggestion`, `CameraModel.closeUpLens`, figure `camera-too-close`).
- Nothing in the app explains why it does not switch, as other camera apps do, or why a close subject stays soft on 1× or 5×.
- iOS reports focus as a lens position from 0 to 1, not as a distance (`AVCaptureDevice.lensPosition`). `minimumFocusDistance` exists, and [BRACKETING.md](BRACKETING.md) (decision 11, check D5) shows it only for a lens a device check has confirmed; none is confirmed.

### Design

One Honesty entry, and one button on the hint that opens it.

- **The entry** is under What nope. Never Does, after The RAW Is Never Changed (figure `feedback-honesty`). It gives no distance.
- **From the hint.** The hint gains an information button, About Close-Up Focus, at its leading edge, 44 pt, on the tile fill (figure `feedback-too-close`). It opens Settings on the Honesty page, scrolled to the entry, with VoiceOver's focus on it. The sentence, Dismiss and Switch to Ultra Wide are unchanged. The button is not disabled while the lens is busy; only Switch to Ultra Wide is.
- **From search.** The Honesty row in Settings search gains the keywords "close-up, macro, close, near, blurry, soft, lens", not shown on screen.
- **Two forms of the last sentence.** The entry names the Ultra Wide lens, with the label the lens row shows for it on that device (0.6× in the figure), only on a device whose Ultra Wide lens can focus. Otherwise the last sentence is only "move back".

### Wording (drafts)

| String | Where | Catalog |
| --- | --- | --- |
| Lenses Never Switch on Their Own | Honesty heading | Honesty |
| nope. never changes lenses for you, not even for a close-up. Each lens is a separate camera with its own sensor, so the photo comes from the lens you chose. Every lens has a closest distance it can focus at. Nearer than that, the picture stays soft. For a close-up, try the Ultra Wide lens (%@), or move back until the picture is sharp. | Honesty statement on a device whose Ultra Wide lens can focus; the value is that lens's label | Honesty |
| nope. never changes lenses for you, not even for a close-up. Each lens is a separate camera with its own sensor, so the photo comes from the lens you chose. Every lens has a closest distance it can focus at. Nearer than that, the picture stays soft. For a close-up, move back until the picture is sharp. | Honesty statement on every other device | Honesty |
| About Close-Up Focus | The hint's information button: name for VoiceOver, Voice Control and the Large Content Viewer | Localizable |

For the Honesty review: "a separate camera with its own sensor" must be true of every lens button on every supported device; if a button is ever a crop of another lens's sensor, the sentence changes in the same release. "Try" promises nothing about how close the Ultra Wide lens focuses. No sentence names another app. No distance appears until check D5 of BRACKETING.md confirms one, and then only by its own decision.

### Accessibility

- The entry is one element, heading then statement, as every Honesty statement is.
- About Close-Up Focus: "About Close-Up Focus, button". In the hint's order: the sentence, About Close-Up Focus, Dismiss, Switch to Ultra Wide. Closing Settings returns focus to the button if the hint is still shown, otherwise to the viewfinder.
- The hint's buttons wrap under one another when they do not fit (largest text sizes, long languages), in the same order.
- Night mode: the information button is an off control, outlined.

### Tests

- UI: the Honesty page has the entry in each form (a simulated device with and without an Ultra Wide lens that can focus), with the audit, at the largest text size, right to left and in night mode; the hint shows About Close-Up Focus, and pressing it opens Settings on Honesty with the entry on screen; the hint's audit with three buttons at the default and largest sizes; Settings search for "macro" finds Honesty.
- Unit: the choice between the two forms from the device's lenses.

### Device checks

- **C1** With the detector fixed: on 1× and 5×, a subject nearer than the lens can focus brings up the hint, and About Close-Up Focus opens the entry.
- **C2** On iPhone 16 Pro Max, 0.6× focuses nearer than 1× and 5×, so "try the Ultra Wide lens" is good advice there. No distance is recorded in the app.

### Found while checking

`CameraModel.closeUpLens` offers the Ultra Wide lens on any device that has one. On a device whose Ultra Wide lens cannot focus, the hint's advice may not help. The hint should be offered under the same condition as the first form of the entry. This is for the builder of the detector fix; it needs no design.

## 4. "Hold it steady or use a tripod."

### Current behavior

`ManualControlsModel.updateSteadyHint` (`ManualControlsModel+Auto.swift`), with `AutoShutter` (`AutoControls.swift`):

- **Manual Controls on:** the hint shows whenever the shutter that is set, or the camera's own shutter while Shutter is on Auto, is slower than 1/(2 × the lens's 35 mm-equivalent focal length). With Shutter on Auto no limit is sent to the camera, so indoors the camera's own choice is often slower than that, and the hint is on most of the time.
- **Manual Controls off:** the hint shows whenever the Fast Shutter limit had to be lifted, whatever shutter the camera then uses.
- Astro hides it (`CameraModel.showsSteadyHint`).
- The rule takes no account of lens stabilization. With equivalent focal lengths of 13, 24 and 120 mm, the limits are about 1/26, 1/48 and 1/240 s.

### Design

**Manual Controls on: nothing.** No hint, for a shutter that is set or one on Auto, at any speed. The Shutter readout shows the speed in use, and the person has chosen to decide. Astro is unchanged: nothing.

**Manual Controls off:** the hint shows while the shutter the camera is using is slower than the steady limit of the lens (figure `feedback-steady-hint`).

- **The steady limit** is the handheld rule moved by the lens's stabilization: `1/(2 × focal length) × 2^allowance`, inside the lens's shutter range. The allowance is 2 stops for a stabilized lens and 0 for any other. Both numbers are provisional and are set by check S2.
- **Which lenses are stabilized** is read from the device for each lens, never from a list of models. The public signal found is `AVCapturePhotoOutput.isLensStabilizationDuringBracketedCaptureSupported` with that lens selected. Whether it is true for each lens of iPhone 16 Pro Max, and whether a single RAW photo is in fact taken with stabilization active, are not confirmed; checks S1 and S2 settle them. Apple's published specifications for iPhone 16 Pro Max, as read for this design, list sensor-shift stabilization for the main and the 5× cameras and none for the Ultra Wide camera. If S1 finds no usable signal, the allowance is 0 for every lens and only the rest of this section changes anything.
- **With the example focal lengths**, a 2-stop allowance gives about 1/12 s on a stabilized 24 mm lens and 1/60 s on a stabilized 120 mm lens, and leaves an unstabilized 13 mm lens at 1/26 s.
- The Fast Shutter limit itself is unchanged. While that limit holds, the shutter is never slower than the handheld rule, so the hint can show only after the limit was lifted, and then only if the camera's shutter passes the steady limit.

**Hysteresis.** The hint turns on at the first reading whose shutter is slower than the steady limit. It turns off only at a reading at least half a stop faster than the limit (`AutoShutter.returnMargin`, the margin the Fast Shutter limit already uses). Between the two it keeps its state. Readings taken before the camera applied the limit are still ignored (`AutoShutter.predatesLimit`), and a lens change or turning Manual Controls on or off starts again from off (`resetReadingAids`).

**How long it stays.** While its cause lasts, and at least 2 seconds once shown, so it can be read; it leaves with `NopeMotion.fade`. It does not time out while the cause lasts: the folder's rule is that a message does not leave on a timer, and with the new limit the cause is rare. VoiceOver hears it once when it appears, and not again within 10 seconds if it returns.

**Not used in 1.0.0:**

- The phone's motion. The level's motion source runs only while the level is on; using it to hide the hint on a tripod would add a sensor use for one hint. Decision 14.
- The system camera's own behavior. When it asks for a steady hand is not documented, so it is not a threshold here. Check S4 compares the two side by side.

### Wording

"Hold it steady or use a tripod." is unchanged. Its translator comment changes to: "Hint on the camera while Manual Controls are off and the shutter in use is slower than the lens can be held at by hand." The Fast Shutter page is unchanged; its sentence "In low light the shutter can be slower." stays true.

### Accessibility

- Announced once on appearing, queued, as today. No announcement when it leaves.
- It is static text in the bottom stack; it takes no focus and no input.
- The 2-second minimum is the only timer, and it only keeps the hint longer.
- Night mode, Reduce Transparency, Increase Contrast: as every hint.

### Tests

- Unit (`SteadyHintTests`, `AutoShutter`): the steady limit for a stabilized and an unstabilized lens, at the edges of the shutter range, and without a focal length; on at a reading just slower than the limit and not at one just faster; stays on until half a stop faster; off after a lens change and after Manual Controls turn on or off; a reading that predates the limit changes nothing; Manual Controls on never shows it, for a set shutter of 1 s and for Shutter on Auto with a slow reading; Astro never shows it. `AutoShutter.risksBlur` is removed with its tests.
- Unit, interface: the 2-second minimum and the 10-second announcement gap, with an injected clock.
- UI (`SteadyHintUITests`): the dim scene shows the hint with Manual Controls off; turning Manual Controls on removes it and it stays away while a 1 s shutter is set; turning them off brings it back after the next reading. The simulated lenses gain a stabilized flag, with one stabilized and one unstabilized lens in the dim scene.
- Docs: `BuildingAnInterface.md` ("show … while `showsSteadyHint`"), `docs/TESTING.md`, the comment on `CameraHints`.

### Device checks

- **S1** On iPhone 16 Pro Max, an iPad and one iPhone with an unstabilized lens: the value of the stabilization signal for each lens. Record it in `docs/TESTING.md`.
- **S2** For each lens of iPhone 16 Pro Max, handheld, a flat target with fine text: ten photos at each shutter from the handheld rule to 3 stops slower, one stop apart, by two people. The allowance for that lens is the slowest step at which at least eight of ten are sharp at 100%. Set the two constants from the result; if lenses differ, keep an allowance for each kind.
- **S3** Walking between a bright and a dim room on each lens: the hint does not flicker.
- **S4** An evening indoors on each lens, Manual Controls off: note when the hint shows, beside the system camera in the same light.
- **S5** Manual Controls on, Shutter on Auto and set to 1 s: no hint.

## 5. The focus square and Lock

### Current behavior

A tap on the picture aims focus and exposure at that point and shows the focus square with the Lock button under it (`FocusSquareLayer`, `FocusLockButton`, `FocusAids.swift`). Both stay until the scene changes (`subjectAreaDidChange` clears the target), the lock is released, or Magnify is on. On a tripod, or with a still subject, they can stay for minutes. Touch and hold, or Lock, locks both; the button then reads AE/AF with a closed lock, and an AE/AF pill is on the status line.

### Design

- **After a tap** the square and Lock appear as today (figure `feedback-focus-tap`). Three seconds after the tap, both fade with `NopeMotion.fade`. The length is a new constant, `NopeMotion.focusAidLinger`, 3 s, provisional (check F1).
- **What does not change:** where the camera focuses and exposes. The tapped point stays in use until the scene changes, exactly as today. Only the drawing leaves.
- **Locked never fades.** Once locked, the square and AE/AF stay until the lock is released, with the status line's pill (figure `feedback-focus-locked`). Releasing the lock returns focus and exposure to the center and removes both at once, as today.
- **Getting Lock back.** Tap the picture again: the square and Lock are back for three seconds. Or touch and hold the picture for half a second: that locks at once, with no need for the button. Both exist today.
- **The clock starts again** at each tap. It does not run while a finger is on Lock, while Lock has the keyboard's or VoiceOver's focus, or while VoiceOver or Switch Control is on (below).
- **During the fade** Lock no longer takes a press; a touch there is a tap on the picture.
- **Magnify:** the square and Lock are not drawn while Magnify is on, as today. The clock keeps running; they come back only if time is left.
- **The scene changes first:** both leave at once, as today.
- Nothing scales or moves. The square has no pulse.

This needs a change to one rule of ACCESSIBILITY.md, "Nothing leaves on a timer." Proposed text: "No message, failure or warning leaves on a timer. One marker does: the focus square with Lock, three seconds after a tap, and never while VoiceOver or Switch Control is on, while it has focus, or while it is locked. Its action always has a way that needs no timing: touch and hold, and the viewfinder's VoiceOver action."

### Wording (drafts)

Lock, AE/AF, Lock Focus and Exposure and Unlock Focus and Exposure are unchanged. The Accessibility page in Settings, which is facts and no switches, gains one group (figure `feedback-accessibility`):

| String | Where | Catalog |
| --- | --- | --- |
| Focus and Exposure Lock | Section header on the Accessibility page, before Feedback | Honesty |
| Tap the picture to focus there. Lock appears under the focus square for a few seconds. Touch and hold the picture to lock right away. | First row | Honesty |
| With VoiceOver or Switch Control on, the focus square and Lock stay until the scene changes. VoiceOver also has the action Lock Focus and Exposure on the viewfinder. | Second row | Honesty |

For the review: "a few seconds" stays true if check F1 changes the constant within 2 to 5 seconds.

### Accessibility

- **VoiceOver on** (`UIAccessibility.isVoiceOverRunning`): no fade. The square and Lock behave as they do today, so a control is never removed while VoiceOver's focus is on it or on its way to it. The viewfinder keeps its actions Lock Focus and Exposure and Focus on Center, which need neither the button nor timing. Locking and unlocking are announced as today.
- **Switch Control on** (`UIAccessibility.isSwitchControlRunning`): no fade, so scanning can reach Lock at any scanning speed.
- **Full Keyboard Access:** Lock does not fade while it has the keyboard's focus.
- **Voice Control** cannot be detected, as far as was found (an assumption for the builder to confirm), so the fade applies. "Tap Lock" works while Lock shows; "Long press Viewfinder" locks at the center at any time (check F4).
- **Reduce Motion:** the fade is opacity only, already the definition of `NopeMotion.fade`.
- **Night mode:** the square and Lock in red (figure `feedback-focus-tap-night`); nothing else differs.
- **Text size, sideways, right to left, iPad, iPhone Duo:** no difference. In the scrolling layout touch and hold is not available on the picture (`ViewfinderTouches.allowsDrags`), so there the square and Lock do not fade.

### Tests

- Unit: the visibility rule as a value with an injected clock: shown at a tap; hidden when the linger has passed; a second tap starts it again; never hidden while locked; held while Lock is pressed or focused, and while VoiceOver or Switch Control is on; hidden at once when the target is cleared; no fade in the scrolling layout.
- UI: tap, Lock exists; after the linger Lock does not exist and the viewfinder still offers Lock Focus and Exposure; tap again, Lock exists; touch and hold, wait past the linger, AE/AF still exists; with the launch argument that simulates VoiceOver or Switch Control, Lock stays; night mode with Lock showing is all red; the audits of the tapped and the locked state. Existing tests that tap and then press Lock either press within the linger or lock by touch and hold.
- `DesignTokensTests`: `focusAidLinger` is 3 s.

### Device checks

- **F1** Beside the system camera on iPhone 16 Pro Max: three seconds is long enough to press Lock with one hand and short enough to be out of the way. Adjust within 2 to 5 seconds.
- **F2** VoiceOver on: the square and Lock stay; focus on Lock is never lost; the viewfinder's actions work after a tap.
- **F3** Switch Control with automatic scanning at its slowest: Lock can be reached.
- **F4** Voice Control: "Tap Lock" in time; "Long press Viewfinder" locks.
- **F5** iPad with a keyboard: Tab to Lock holds it.
- **F6** Touch and hold after the fade locks at the held point.
- **F7** On a tripod with a still subject: after the fade, focus and exposure stay at the tapped point.

## 6. Noted for the build

Two changes are being built without a design. What they need from this one:

- **The close-up hint's detector** is being fixed so the hint appears on real devices. Its sentence and buttons are unchanged, apart from About Close-Up Focus (section 3) and the condition in "Found while checking".
- **Stop on a focus bracket's Live Activity.** The same Stop button, in the same place, as for Interval and Astro (`SeriesStopButton`); figure `live-activity-lock` shows it for those two. The visible word stays "Stop". Its VoiceOver name is "Stop Bracket", the name of the button on the camera's card. Pressing it stops after the current frame and keeps every photo taken, as on the card; the activity then reads as the card does, "Bracket stopped: 4 of 12 photos saved". The description of the action behind the button becomes "Stops nope.'s interval shooting, astro frames or focus bracket. Every photo already taken is saved." (a draft). Stop is offered during the start delay and while frames are taken, and not once the bracket has finished. Night mode: outlined, as today.

## 7. Decisions for the owner

### 1. The empty Last Photo spot

| # | Decision | Recommendation | The other choice |
| --- | --- | --- | --- |
| 1 | What the spot holds before the first photo | The Open Photos button. It gives the spot a use and breaks no privacy rule | Leave it empty, as today; or a symbol that is not a button |
| 2 | The symbol | `photo.on.rectangle`, the one Open in Photos uses | Another photo symbol |
| 3 | The Honesty entry Your Photo Library Is Never Read | Add it. It is the one place that says why the spot starts empty | The VoiceOver hint only |
| 4 | Before the first photo, while a countdown or series runs | Hide Open Photos, so a press can't interrupt the series | Show it always |
| 5 | The Lock Screen camera | Leave the spot empty: a locked iPhone can't open Photos | A symbol that can't be pressed |

### 2. Use the Whole Range

| # | Decision | Recommendation | The other choice |
| --- | --- | --- | --- |
| 6 | How "already in use" is shown | A check mark and the selected trait, at full contrast, never dimmed | Replace the row with the sentence "The whole range is in use." while it applies; the row then changes kind under the finger |
| 7 | The rule in tokens.md | Add it: a control whose result is already in place is shown selected; dimming is for a control that can't be used, and never the only sign | Leave it as a one-off |

### 3. Close-up focus

| # | Decision | Recommendation | The other choice |
| --- | --- | --- | --- |
| 8 | The entry's place | Under What nope. Never Does, after The RAW Is Never Changed | Its own group about lenses, with Lenses Without RAW |
| 9 | Reaching it from the hint | The About Close-Up Focus button | No button; the Honesty page and search only |
| 10 | Naming the system camera in the entry | Don't. The entry says only what this app does | Add "as some camera apps do" |
| 11 | A hint on the Ultra Wide lens itself, "…Move back until it's sharp." | Not in 1.0.0: at the lens's closest focus a sharp subject would also raise it | Add it with the detector fix |

### 4. "Hold it steady or use a tripod."

| # | Decision | Recommendation | The other choice |
| --- | --- | --- | --- |
| 12 | The starting allowance for a stabilized lens, until check S2 | 2 stops | 3 stops: fewer hints, more risk of a soft photo with no hint |
| 13 | How long the hint stays | While its cause lasts, at least 2 seconds | Fade after 5 seconds and return only after the cause has ended and come back |
| 14 | Hiding the hint when the phone is still (on a tripod), from its motion | Not in 1.0.0 | Add it; the motion source then also runs while the level is off |
| 15 | Making the Fast Shutter limit of Standard itself count stabilization | Not in 1.0.0. It changes the exposure (a slower shutter at a lower ISO), not a hint, and needs its own device data and Fast Shutter wording | Do it with this change |
| 16 | If check S1 finds no usable stabilization signal | Ship with the allowance at 0: the hint still leaves Manual Controls and follows the shutter in use | Hold the change |

### 5. The focus square and Lock

| # | Decision | Recommendation | The other choice |
| --- | --- | --- | --- |
| 17 | How long they stay after a tap | 3 seconds, adjusted by check F1 | 2 seconds, nearer the system camera; or 5 |
| 18 | What fades | The square and Lock together | The square only; Lock stays until the scene changes |
| 19 | VoiceOver and Switch Control | No fade while either is on | Fade for everyone |
| 20 | A switch to keep them until the scene changes | None. The Accessibility page is facts, and touch and hold needs no timing | A switch, Keep Focus Square, on the Accessibility page, for Voice Control users |
| 21 | The change to the rule "Nothing leaves on a timer." | Accept the text in section 5 | Keep the rule as written, and do not fade |

### 6. Noted for the build

| # | Decision | Recommendation | The other choice |
| --- | --- | --- | --- |
| 22 | The Live Activity's Stop for a focus bracket | The visible word "Stop", the VoiceOver name "Stop Bracket" | "Stop Bracket" as the visible word, if it fits beside the progress |

## 8. When this is accepted

- Sections 1 to 5 move into BUILD-SPEC.md (3.7, 3.10, section 4 and section 5), ACCESSIBILITY.md (the rule, row 14, the Bracketing table), BRACKETING.md (the Focus Range row) and tokens.md (`focusAidLinger`, the rule of decision 7).
- Figures: `feedback-photos-button` replaces `camera-first-photo`; the focus figures replace `camera-focus-lock` and `ipad-focus-lock`; `feedback-too-close` replaces `camera-too-close` and `ipad-too-close`; `feedback-honesty` and `feedback-accessibility` replace `settings-honesty` and `settings-accessibility`; the whole-range figures join the bracketing set. The screen counts in README.md are updated then.
- The device checks join `docs/TESTING.md` and gate release 1.0.0 where a provisional value depends on them (S1, S2, F1).
