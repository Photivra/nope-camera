# Bracketing: the menu, exposure bracketing and focus bracketing

Design version: 1.0.0, direction B · Reach. Proposed 2026-11-18. The menu and exposure bracketing are for release 1.0.0; focus bracketing is designed here and built in release 1.1.0. This document becomes part of the plan when the decisions in section 10 are made; until then [BUILD-SPEC.md](BUILD-SPEC.md) sections 3.4 and 3.5 stand. The drawings are in [bracketing.html](bracketing.html); each figure named below is `screens/<name>.html` with a PNG beside it. Tokens are in [tokens.md](tokens.md).

Contents: 1. Summary · 2. What the iPhone supports · 3. Where bracketing lives · 4. Exposure bracketing · 5. Focus bracketing · 6. Interaction and accessibility · 7. Build specification, 1.0.0: menu redesign with exposure bracketing · 8. Build specification, 1.1.0: focus bracketing · 9. Device checks · 10. Decisions for the owner · 11. When this is accepted

## 1. Summary

| | Today (0.3.0 and the 1.0.0 plan) | 1.0.0, proposed | 1.1.0, proposed |
| --- | --- | --- | --- |
| Where | Pro Tools › Bracketing, only with Manual Controls on; three taps | Bracket, the fourth word of the drive strip; one tap; in full auto and with Manual Controls on | The same |
| What shows it is on | Nothing on the camera screen | The selected word, and a card on the picture's lower edge that says what one press takes | The same card, naming the type |
| Options | A switch, Frames (3, 5, 7), Step (1/3, 2/3, 1, 2 EV) | Bracket Settings: Frames, Step, Order, Start Delay, and a list of the frames that will be taken | A Type control above them (Exposure, Focus); for Focus: the range, Frames, Order, Start Delay, Return Focus When Done |
| While it is taken | The shutter is dimmed | A card: "Taking 3 frames", then "Saving: 2 of 3 photos saved" | Focus: "Frame 4 of 12", the focus, Stop Bracket |
| After | "3 photos saved and signed." | The card "3 photos saved" and the frames; each frame a page in the viewer, named as part of its bracket | The same |
| With Timer | Combine Timer with the Pro Tools switch | Start Delay in Bracket Settings | The same |
| With Interval | Each interval photo is a bracket | Not offered (decision 3) | Not offered |
| Pro Tools | Holds the Bracketing section | The section is removed | |
| Siri and Shortcuts | Take Bracket: Frames, Step, Delay, Lens | Adds Order | Adds Type; for Focus, Frames and Range |
| Each frame | One single-frame Bayer RAW photo, saved on its own; allowlist, read-back, signing when on; no flash | Unchanged | The same for every focus frame. The app never stacks, aligns or merges |

Principles kept: least processing (every frame is one photo; nothing is merged); honest wording (no distance, time or rate that the phone does not report or the project has not measured); one home for each option; nothing is shown before it is built; no gesture is the only way.

## 2. What the iPhone supports

Verified means read in the code or in Apple's headers and documentation. Everything else is an assumption until checked on a device (section 9), and must not be quoted in the app, the store listing or the README (AGENTS.md, rule 1). Header quotations are from `AVCaptureDevice.h` and `AVCapturePhotoOutput.h` in the iOS 27.2 SDK.

| Subject | Status | What is known |
| --- | --- | --- |
| Exposure bracket | Verified, in the code | One `AVCapturePhotoBracketSettings` request with one `AVCaptureManualExposureBracketedStillImageSettings` for each frame (`PhotoSettingsFactory.makeBracketSettings`). The delegate is called once for each frame with that frame's settings. The frames are requested in the order of the array, so an order is a matter of the array |
| Frame limit | Verified | `maxBracketedCapturePhotoCount` depends on the format and can be 0. The app reads it for each lens (`Lens.maxBracketedPhotoCount`) and offers 3, 5 and 7 up to it |
| Stopping an exposure bracket | Verified by absence | AVFoundation has no call that cancels a photo request in progress. Stop is offered only before the request (the start delay) |
| Flash | Verified, in the code | Not supported in a bracket; `CapturePolicy` turns it off |
| A bracket in full auto | Verified, in the code | `ManualControlsModel.bracketFrames(once:)` plans a bracket around the camera's last reading with Manual Controls off; Take Bracket uses it today and a UI test covers it |
| Setting focus | Verified | `setFocusModeLocked(lensPosition:completionHandler:)` where `isLockingFocusWithCustomLensPositionSupported` is true (`ManualCapabilities.supportsManualFocus`). The handler runs when the position has been applied |
| What a lens position means | Verified | "0.0 being the shortest distance at which the lens can focus and 1.0 the furthest. Note that 1.0 does not represent focus at infinity." and "a given lens position value does not correspond to an exact physical distance, nor does it represent a consistent focus distance from device to device." |
| Focus distance | Verified by absence | The iOS 27.2 SDK has no property that gives the focus distance of a lens position, and none that states how well focus is calibrated. Names such as a lens position distance or a calibration quality do not exist in it |
| Minimum focus distance | Verified | `minimumFocusDistance`, in millimeters, or −1 when unknown. For a virtual camera it is the smallest of its cameras. This is the only distance the system reports |
| Focal length and aperture | Verified | `nominalFocalLengthIn35mmFilm` (iOS 26) and `lensAperture`. Without a focus distance these do not give a depth of field at a lens position |
| A system focus bracket | Verified by absence | None. A focus bracket is separate requests: set the position, wait for the handler, take one photo |
| Time for a focus move, and for a RAW photo after it | Not measured | Unknown for every lens. The design promises no time |
| Whether the lens reaches the position asked for, and repeats it | Not measured | `lensPosition` can be read back after the handler. Tolerance unknown |
| Whether even steps of lens position are even steps of sharpness | Not measured | An assumption that they are roughly even. No wording depends on it |
| Whether the picture's scale shifts as focus changes | Not measured | Expected for most lenses. The advice says only that nothing should move and to use a tripod |
| Whether the system changes lens (the close-focus switch) at a position | Not applicable | The app selects one physical camera for each lens; a focus bracket never changes it |

## 3. Where bracketing lives

Bracket is a word on the drive strip, between Burst and Interval: Single, Timer, Burst, Bracket, Interval, Astro. The comparison with the other places is in [bracketing.html](bracketing.html).

- The strip is the answer to "what does one press take". A bracket is such an answer, and so is a focus series. Interval and Astro already use the pattern this needs: a word, an idle card that is the settings button, the shutter to start, a running card.
- Bracket is offered where the selected lens can take a bracket (`ManualControlsModel.bracketFrameCounts` is not empty); in 1.1.0, also where it can only take a focus bracket. Otherwise the strip has no Bracket word, as it has no Astro word where Astro can't be used. Switching to a lens that can't, with Bracket selected, selects Single and VoiceOver says "Single".
- It needs no Manual Controls. In full auto the bracket is planned around the exposure the camera reads when the shutter is pressed. With Manual Controls on, a value set by hand stays as set and the other one changes from frame to frame, as today.
- Tapping the selected word, or the card, opens Bracket Settings. Choosing Bracket does not open the sheet by itself.
- Six words fit a 402 pt and a 375 pt wide screen in English at the strip's tighter spacing (figures `bracket-idle`, `bracket-small`). In a longer language the strip scrolls and keeps the selected word visible; that rule exists today.
- Sideways the strip shows symbols; Bracket's is `square.3.layers.3d`.
- The Bracketing section leaves Pro Tools (figure `bracket-pro-tools`).
- No Q tile and no pill: the strip and the card already show the state.

In the core nothing new is needed for the place: Bracket is the bracket that exists (`ManualControlsModel.bracket`) with the drive mode Single, or Timer when a start delay is set. Choosing another word turns the bracket off first, as choosing another word turns Astro off.

## 4. Exposure bracketing (1.0.0)

### Options

| Option | Choices | At first | Notes |
| --- | --- | --- | --- |
| Frames | 3, 5, 7, up to the lens's limit | 3 | As today |
| Step | 1/3, 2/3, 1, 2 EV | 1 EV | As today |
| Order | Darkest First (−, 0, +); Metered First (0, −, +, then outward); Brightest First (+, 0, −) | Darkest First | Darkest First is today's order |
| Start Delay | Off, 3 seconds, 10 seconds | Off | The self-timer's delays and its countdown |
| The Frames | Read-only: each frame's number, offset, shutter speed and ISO | | From `BracketFrame.plan` with the values in use. A frame beyond the lens's limits shows the offset it will really have, an amber triangle and "This lens can't go brighter than frame 3." (or darker) |

The values are kept for the session, as today, and a preset stores them. Nothing is added to Settings.

### The card and the shutter

| State | Title | Detail | Button | Shutter |
| --- | --- | --- | --- | --- |
| Idle | "Exposure bracket: 3 frames, 1 EV apart" | The offsets in order, "−1, 0, +1 EV"; with a delay, "· after 3 seconds" | The whole card is Bracket Settings | Plain; shows "3" or "10" with a delay |
| Start delay | "Bracket in 3s" | "3 frames, −1, 0, +1 EV" | Cancel | Stop square; cancels |
| Taking | "Taking 3 frames" | The offsets | None | Dimmed |
| Saving | "Saving: 2 of 3 photos saved" | A progress bar | None | Dimmed |
| Saved | "3 photos saved" | The offsets | None; stays until the next action, then the idle card returns | Plain |
| A frame not saved | The banner "Bracket stopped: 2 of 3 photos saved." and the reason | | Dismiss | Plain |

The card names the type from 1.0.0 on, so it does not change when a second type arrives. While frames are taken and saved the other drive words are dimmed and the readout row is hidden, as during any series.

### The result

- Each frame is one page of the Last Photo viewer (BUILD-SPEC.md, decision V12). A chip on the picture's lower edge names the bracket and the frame: "Exposure bracket · frame 2 of 3 · 0 EV" (figure `bracket-viewer`). It hides with the other controls.
- What's in This Photo keeps its Photo row for the frames of a bracket and gains a Bracket group after the summary: Type, This Frame, Planned Exposure, The Bracket (figure `bracket-details`).
- These values are the session's, held in memory with each saved photo until the app closes. They are not written to any file, so the metadata allowlist does not change. In Photos each frame is a separate photo; the footer says so.

## 5. Focus bracketing (1.1.0)

A series of single photos, each at the next focus position, for stacking in other software. The app takes the frames and nothing else.

### Options

| Option | Choices | At first | Notes |
| --- | --- | --- | --- |
| Type | Exposure, Focus | Exposure | A segmented control above the rows of 1.0.0. Focus is dimmed, with one sentence, on a lens whose focus can't be set |
| Nearest Focus, Farthest Focus | A position from 0 to 1, set on the picture | 0 and 1 | Use the Whole Range sets both back |
| Frames | 3, 5, 7, 10, 12, 15, 20, 30, 40, 50 | 10 | 50 is the most one burst takes today |
| Focus Step | Read-only: (farthest − nearest) ÷ (frames − 1) | | Shown to two decimals, with the sentence that it is the lens's own scale and not a distance |
| Order | Nearest First, Farthest First | Nearest First | |
| Start Delay | Off, 3 seconds, 10 seconds | 3 seconds | |
| Return Focus When Done | On, off | On | Back to automatic focus, or to the position set by hand before the bracket |
| Closest Focus of This Lens | Read-only, "About 15 cm" | | Only where `minimumFocusDistance` is not −1 and a device check has confirmed it for that lens |
| Storage, at Most | Read-only | | The estimate Astro Settings shows, for the chosen frames |

Not options: the exposure and white balance, which are locked at the first frame so the frames match (values set by hand are used as set); the flash, which never fires; the wait after a focus move, which is the system's signal plus a margin set from the device check.

### Setting the range on the picture

Nearest and Farthest are two buttons on the idle card, and two rows of the sheet that close it and do the same (figure `bracket-focus-set-nearest`). A dial opens on the picture's lower edge, titled Nearest Focus or Farthest Focus, with the value, Decrease, a slider, Increase, the hint, Cancel and Set Nearest Focus. A tap on the picture focuses there once and the value follows the lens. Focus Peaking shows while the dial is open whatever its switch says; Magnify stays in Q. If the nearest value is set beyond the farthest, the two swap.

### Running

| State | Title | Detail | Button | Shutter |
| --- | --- | --- | --- | --- |
| Idle | "Focus bracket: 12 frames" | "Focus 0.12 to 0.80, nearest first"; the track; Nearest and Farthest | The chevron opens Bracket Settings | Plain |
| Start delay | "Bracket in 3s" | "12 frames, focus 0.12 to 0.80" | Cancel | Stop square |
| Running | "Frame 4 of 12" | "Focus 0.31", as the lens reports it; the track with a mark for each frame, filled when taken | Stop Bracket | Stop square |
| Paused | "Paused: 4 of 12 frames" | "Continues when the camera is back" | Stop Bracket | Dimmed |
| Finished | "12 photos saved" | "Focus is back to Auto" (or "Focus stays at 0.80") | None | Plain |
| Stopped early | "Bracket stopped: 4 of 12 photos saved" and, when the app stopped it, why (storage, battery, the camera) | Where the focus is | None | Plain |

For each frame: set the position, wait for the system's handler, take one photo through the ordinary single-photo path, save it, go on. Stop takes effect after the current frame; every photo taken is kept. The series pauses and continues as Interval and Astro do. Storage and battery are checked before each frame, as in a burst. The screen dims during the series as it does for Interval.

If the lens reports a position that differs from the one asked for by more than the tolerance (section 9), the frame is still saved, and What's in This Photo shows both values. The end card then adds "2 frames were not at their planned focus".

### The result

As for an exposure bracket. The chip reads "Focus bracket · frame 4 of 12 · focus 0.31"; the Bracket group shows Focus (reported by the lens), Planned Focus and The Bracket (figures `bracket-focus-viewer`, `bracket-focus-details`).

## 6. Interaction and accessibility

| Input | Result |
| --- | --- |
| Shutter, volume buttons, Camera Control, Space | Takes the bracket, after the start delay. During the delay: cancels. During a focus bracket: stops after the current frame. Holding adds nothing |
| Escape | Closes Bracket Settings or the focus dial (as Cancel) |
| Apple Watch | Take Photo takes what the strip says, so the bracket; the results "Photos saved and signed" and "Photos saved, not all signed" exist. During a focus bracket the watch reports the camera busy. No watch screen changes |
| Siri and Shortcuts | Take Bracket, once, without changing the bracket set in the app. 1.0.0 adds Order. 1.1.0 adds Type; with Focus: Frames and Range (As Set in nope., Whole Range) |
| Live Activity | None for an exposure bracket. A focus bracket uses the series activity: "Frame 4 of 12" |

VoiceOver:

| Element | Label, value, hint |
| --- | --- |
| Strip word | "Bracket", selected. Hint when selected: "Opens Bracket Settings." |
| Idle card | "Bracket Settings", button. Value: "Exposure bracket: 3 frames, 1 EV apart. Minus 1, 0, plus 1 EV." |
| Shutter | "Take Photo". Value: "Bracket, exposure, 3 frames" or "Bracket, focus, 12 frames" |
| Nearest, Farthest (focus card) | "Nearest Focus", value "0.12"; "Farthest Focus", value "0.80". Buttons |
| Focus dial | An adjustable element, steps of 0.01; the picture's tap-to-focus stays a VoiceOver action, Focus Here |
| The track | Hidden; the words carry it |
| The Frames rows | "Frame 1, minus 1 EV, 1/250 second, ISO 200"; a limited frame adds its sentence |
| Announcements | "Bracket in 3 seconds" and each second; "Taking 3 frames"; "3 photos saved and signed." (existing); for focus, "Frame 4 of 12" at each frame while VoiceOver is not speaking, and the end sentence |
| Viewer chip | Part of the page's label: "Photo 6 of 7. Exposure bracket, frame 2 of 3, 0 EV." |

- Voice Control and Switch Control: every control has a visible name that is its spoken name (Bracket, Bracket Settings, Frames, Step, Order, Start Delay, Cancel, Stop Bracket, Nearest Focus, Farthest Focus, Set Nearest Focus, Use the Whole Range). Nothing needs a hold, a drag or timing.
- Largest text sizes: the scrolling layout. The card is full-width text; Stop Bracket, Nearest Focus and Farthest Focus are full-width rows; the track is left out; in the sheet each value wraps under its title and the Type control becomes a two-row picker (figures `bracket-largest`, `bracket-settings-largest`, `bracket-focus-largest`).
- Right to left: rows mirror, and the focus track runs from the lens's closest focus on the leading edge. Exposure values, shutter speeds and positions keep their order (`bracket-rtl`, `bracket-settings-rtl`, `bracket-focus-rtl`).
- Night mode: red on black. Frames taken are filled marks and frames to come are outlined, so the count never depends on color; the limit warning keeps its triangle and words.
- Differentiate Without Color, Increase Contrast: the amber triangle always has words; marks differ by fill.
- Reduce Motion: the progress bar and the track change without animation.
- Sideways, iPad, iPhone Duo: the card on the picture's lower edge; Bracket Settings is a sheet on a compact width and a centered sheet on iPad and the Duo inner display.
- Haptics: selection on choosing the word; the capture haptic once for an exposure bracket and once for each focus frame; the series-end haptic Astro uses.

## 7. Build specification, 1.0.0: menu redesign with exposure bracketing

Figures: every `bracket-*` figure whose name has no `focus` in it, except `bracket-settings-type`.

### Core

| File | Change |
| --- | --- |
| `Sources/NopeCore/Bracketing.swift` | New `BracketOrder` (`darkestFirst`, `meteredFirst`, `brightestFirst`). `BracketSettings` gains `order`, default `darkestFirst`; `offsets` returns them in that order. New `BracketFramePlan`: for each frame the offset asked for, the offset reached and the `BracketFrame`, from `BracketFrame.plan`, so an interface can list the frames and mark a limited one |
| `Sources/NopeCore/ManualControlsModel.swift` | A bracket no longer needs Manual Controls on: `setBracket` and `bracketFrames()` drop the `isEnabled` condition and plan as `bracketFrames(once:)` does. New `bracketPlan`, observable, for the list. `lensWillStart` keeps dropping a bracket the lens can't take |
| `Sources/NopeCore/CameraModel.swift` | `captureBracket` publishes progress (`BracketProgress`: taken, saved, total) while it saves, and reports how many frames were saved when one fails (`CaptureStatus` gains the count on that failure). Each `SavedPhoto` of a bracket gets a `BracketPlace` (type, index, count, offset, order) |
| `Sources/NopeCore/CameraModel+Drive.swift` | Setting the drive mode to Burst or Interval turns the bracket off (decision 3). A start delay is the existing `.timer(delay)` with the bracket on; no new drive mode |
| `Sources/NopeCore/SavedPhoto.swift` | Optional `bracket: BracketPlace?`. In memory only |
| `Sources/NopeCore/CameraSetup.swift` | `BracketValue` gains `order`, decoded as `darkestFirst` when absent, so stored presets keep working |
| `Sources/NopeCore/ShortcutRequest.swift` | `BracketShortcut` gains `order` |
| `Sources/NopeCore/SimulatedCaptureBackend.swift` | Returns the frames in the order asked for, so UI tests can check it |
| `Sources/NopeCapture/*` | No change. The order is the order of the frames passed to `captureBracket` |

No new stored setting, no new metadata, no change to the allowlist or to signing.

### Interface

| Component | File | Notes |
| --- | --- | --- |
| The Bracket word | `DriveStrip.swift` | Shown when `manual.bracketFrameCounts` is not empty. Selected when a bracket is on and the mode is Single or Timer. Choosing it sends `.manual(.setBracket(…))` with the session's last bracket (3 frames, 1 EV at first) and the mode for its delay; choosing another word sends `.manual(.setBracket(nil))` first. The selected word opens `BracketSheet`. Symbol `square.3.layers.3d`. Timer is not shown selected while a bracket is on |
| The cards | `DriveControls.swift` (`ModeCard`, `DriveText`) | The states of section 4. The idle card is one button. The countdown reuses the Timer card with the bracket's title |
| `BracketSheet` | New `BracketControls.swift`, modeled on `IntervalControls.swift` | `NavigationStack`, `Form`; medium and large detents on a compact width, a centered sheet otherwise; dark, with `.nightModeStyle`. Section 1: `Picker` Frames, Step, Order (`.pickerStyle(.navigationLink)`). Section 2: `Picker` Start Delay with its footer. Section 3, "The Frames": one row for each `BracketFramePlan`. Section 4: the Honesty sentence. Done as the other sheets have it. A place above section 1 is left for the Type control of 1.1.0; nothing is drawn there |
| Pro Tools | `ProToolsSheet.swift` | Remove `bracketSection` |
| Shutter | `ShutterButton.swift` | Value "Bracket, exposure, 3 frames"; the delay digit as for Timer |
| Feedback | `CaptureFeedback.swift` and the failure banner | The banner for a bracket that stopped while saving |
| Viewer chip | `PhotoViewer.swift` (BUILD-SPEC.md 3.14) | Shown when the page's photo has a `BracketPlace` |
| Bracket group | `PhotoDetailsSheet.swift` (BUILD-SPEC.md 3.15) | After the summary; the footer string is in the Honesty table |
| Take Bracket | `App/NopeApp/Intents/TakeBracketIntent.swift` | New optional parameter Order (`BracketOrderChoice`), default Darkest First; the summary is unchanged |
| Documents | `docs/design/navigation.md`, `ACCESSIBILITY.md`, `BUILD-SPEC.md`; `docs/research/capture-and-file-settings.md`; `docs/TESTING.md`; `CHANGELOG.md` | Section 11 |

Tokens: the card and sheet use the tokens of the other mode cards and sheets; none is added. The frame number badge is `NopeSize.badge` if it exists, else a text label "1" in secondary color.

### Acceptance criteria

1. With a lens that can bracket, Bracket is one tap from the default screen in full auto and with Manual Controls on, and one press of the shutter then saves 3 separate photos.
2. The idle card always states the type, the frames, the step and the offsets in the order they will be taken.
3. Pro Tools has no bracketing control. No other place turns a bracket on or off, except a preset and Take Bracket (once).
4. Each of the three orders saves the frames in that order; Darkest First gives the files today's build gives.
5. The Frames list equals what is taken: same offsets, shutter speeds and ISO as the requests (checked in a unit test against the simulated backend). A frame beyond the lens's limits is marked before the photo.
6. Start Delay counts down as Timer does; the shutter, Cancel and a hardware button cancel it and nothing is taken.
7. Every frame is a single-frame RAW photo with the allowlist, the read-back and the signature state of any photo; the flash never fires.
8. A bracket that fails while saving says how many photos were saved.
9. Choosing Burst, Interval, Timer, Single or Astro turns the bracket off; choosing a lens that can't bracket selects Single.
10. An idle card covers no more than an eighth of the picture on a 402 × 874 pt screen; the strip never truncates a word.
11. Presets saved by earlier versions with a bracket apply and show Bracket selected.
12. VoiceOver, Voice Control, Switch Control and a keyboard can do all of the above; the accessibility audit passes on every state.

### Tests

Unit (`Tests/NopeCoreTests`): `BracketOrderTests` (offsets for 3, 5 and 7 frames in each order); `BracketFramePlanTests` (limited frames, both directions, shutter first and ISO first); `ManualControlsModelTests` (a bracket in full auto; the lens change); `CameraModelBracketTests` (progress values; the saved count on a failure; `BracketPlace` on each photo; Burst and Interval turn the bracket off); `SettingsPresetsTests` (a preset without `order`); `ShortcutTests` (the order parameter). Coverage of non-UI code stays at 100%.

UI (`App/NopeAppUITests`, each with an accessibility audit): `testBracketFromStripInFullAuto`, `testBracketCardOpensSettings`, `testBracketSettingsOrderAndFrames`, `testBracketLimitedFrameIsMarked`, `testBracketStartDelayCountsDownAndCancels`, `testBracketSavedCardAndViewerChip`, `testBracketDetailsGroup`, `testBracketNotOfferedOnALensWithout`, `testProToolsHasNoBracketing` (replaces the `switches["Bracketing"]` checks in `ManualControlsUITests` and `AppearanceUITests`), `testBracketAtTheLargestTextSize`, `testBracketRightToLeft`, `testBracketNightMode` (with the all-red check), `testBracketSideways`, `testBracketOnIPad`; `ShortcutUITests`: the order parameter. Pseudo-language run for the six-word strip.

### Strings (English), 1.0.0

New, in `Localizable.xcstrings` unless marked:

| String | Where |
| --- | --- |
| Bracket | Drive strip word; the pill sideways |
| Bracket Settings | Sheet title; the card's VoiceOver label |
| Exposure bracket: %lld frames, %@ apart | Idle card title; %@ is the step, "1 EV" |
| %@ · after %@ | Idle card detail with a delay: the offsets, "3 seconds" |
| Order | Sheet row; Take Bracket parameter |
| Darkest First · Metered First · Brightest First | Order choices |
| The Frames | Sheet section header |
| Frame %lld, %@, %@, ISO %@ | VoiceOver label of a frame row |
| +2 EV, not +4 | Pattern "%@, not %@" for a limited frame |
| This lens can't go brighter than frame %lld. · This lens can't go darker than frame %lld. | Limited frame |
| Waits before the first frame, so touching the phone doesn't shake it. | Start Delay footer |
| From the exposure the camera reads now; it is read again when you press the shutter. The shutter speed changes from frame to frame. ISO changes only where the shutter can't go further. | The Frames footer; a second form names ISO first when the shutter is set by hand |
| Bracket in %llds | Countdown card |
| Taking %lld frames | Card |
| %lld photos saved | Card (shared with Burst if BURST.md is accepted) |
| Bracket stopped: %lld of %lld photos saved. | Banner, followed by the existing reason sentence |
| Bracket, exposure, %lld frames | Shutter value |
| Opens Bracket Settings. | Hint |
| Exposure bracket · frame %lld of %lld · %@ | Viewer chip |
| Type · Exposure · This Frame · Planned Exposure · The Bracket · %lld of %lld | Bracket group |
| A bracket never fires the flash. | Honesty table; sheet |
| Kept by nope. until it closes, to group the frames here. Not written to the files; in Photos each frame is a separate photo. | Honesty table; Bracket group footer |

Kept: "Frames", "Step", "Start Delay" (its translator comment is widened to cover a bracket), "Cancel", "Saving: %lld of %lld photos saved", "Each frame is a separate single-frame photo. Nothing is merged.", "%lld photos saved and signed." Removed: "Bracketing" (the Pro Tools switch). App Shortcuts: the phrase "Take a bracket with nope." is unchanged.

Honesty review: the two Honesty strings above and the limited-frame sentences are drafts until reviewed.

## 8. Build specification, 1.1.0: focus bracketing

Figures: `bracket-settings-type` and every `bracket-focus-*` figure. Nothing here is built, promised or shown in 1.0.0. Section 9 comes first: the build starts only when the device checks support it.

### Core

| File | Change |
| --- | --- |
| `Sources/NopeCore/Bracketing.swift` | `BracketType` (`exposure`, `focus`). `FocusBracketSettings`: nearest, farthest (0…1, ordered), frameCount (one of `frameCounts`), order, returnsFocus; `positions` gives each frame's lens position, evenly spaced; `step`. `FocusBracketProgress` (frame, total, position reported, isPaused) |
| New `Sources/NopeCore/BracketModel.swift` | Observable, modeled on `AstroModel`: the type, the focus settings, the progress, the range being set. Intents: set type, set nearest, set farthest, use whole range, set frames, set order, set returns focus, begin and end setting an end of the range |
| New `Sources/NopeCore/CameraModel+Bracket.swift` | The run, modeled on `CameraModel+Astro.swift` and using `takeFrames`: lock exposure and white balance at their current values (or use the manual ones); for each position: `backend.setFocus(position)` and await it, read back the position, take one photo with `capturePhoto`, save, publish progress; stop on request, storage, battery or the camera; pause and continue with the foreground and interruptions; at the end restore focus, exposure and white balance as they were. Each saved photo gets a `BracketPlace` with the planned and reported positions |
| `Sources/NopeCore/ManualCaptureBackend.swift` | `setFocus(lensPosition:) async throws(CaptureError) -> Double`: sets the position and returns the position the lens reports when the system's handler has run. `lockWhiteBalance(_:)` if the existing manual path can't hold the current gains |
| `Sources/NopeCore/Lens.swift`, `Sources/NopeCapture/CameraDeviceDescription.swift`, `LensCatalog.swift` | `minimumFocusDistanceMillimeters: Int?` from `minimumFocusDistance` (`nil` for −1) |
| `Sources/NopeCapture/SystemCaptureHardware.swift` | `setFocus`: `lockForConfiguration`, `setFocusModeLocked(lensPosition:completionHandler:)`, continue on the handler, read `lensPosition`. Guarded by `isLockingFocusWithCustomLensPositionSupported`. Behind the `CaptureHardware` protocol, with a fake in the tests |
| `Sources/NopeCore/SimulatedCaptureBackend.swift` | `setFocus` returns the position asked for, or a scripted one, so the tests cover a lens that stops short |
| `Sources/NopeCore/CameraSetup.swift` | A preset stores the bracket type and the focus settings; absent in older presets |
| `Sources/NopeCore/ShortcutRequest.swift`, `CameraModel+Shortcuts.swift` | `BracketShortcut` gains the type and, for focus, the frames and the range choice; new outcomes for a lens without manual focus and for a stopped series |
| `Sources/NopeCore/LiveActivity.swift`, `App/Shared/SeriesActivity.swift` | A focus bracket as a series: "Frame 4 of 12" |
| `Sources/NopeCore/CameraModel+Watch.swift` | A running focus bracket counts as a running series (busy) |

Each frame goes through the single-photo capture and the saver that exist, so the allowlist, the read-back and signing apply with no change. No file gets a new tag: the positions are session values.

### Interface

| Component | File | Notes |
| --- | --- | --- |
| Type | `BracketControls.swift` | A segmented `Picker` in the place left above section 1. With Focus, the sections of figure `bracket-focus-settings` replace Frames, Step, Order and The Frames. Dimmed with its sentence where `supportsManualFocus` is false |
| Focus idle card | `DriveControls.swift` | `ModeCard` with a second row (the track, custom drawing, hidden from VoiceOver) and a third (two `NopeCapsuleStyle` buttons). `ViewThatFits`: the buttons side by side, else stacked |
| Range dial | `ControlDial.swift` | The focus dial with a title, Cancel and Set; turns Focus Peaking on while shown; the picture's tap focuses once |
| Running, paused and end cards | `DriveControls.swift` | As section 5 |
| Bracket word | `DriveStrip.swift` | Also shown where only a focus bracket can be taken; selected while `BracketModel` is on |
| Viewer chip, Bracket group | `PhotoViewer.swift`, `PhotoDetailsSheet.swift` | The focus forms |
| Take Bracket | `TakeBracketIntent.swift`, `ShortcutDialog.swift` | Parameter Type (Exposure, the default; Focus). With Focus: Frames (a number, moved to the nearest offered) and Range (As Set in nope., Whole Range); Step and Order apply to Exposure only. The parameter summary switches on Type |
| Live Activity | `App/NopeControls/SeriesLiveActivity.swift` | The focus series |

### Acceptance criteria

1. On a lens whose focus can be set, Focus takes exactly the chosen number of separate single-frame RAW photos, at evenly spaced positions from the nearest to the farthest value, in the chosen order.
2. No photo is taken before the system reports the focus position applied.
3. No frame is merged, aligned, stacked or dropped; stopping keeps every photo taken.
4. Exposure and white balance do not change during the series, and are as they were afterwards. With Return Focus When Done on, so is the focus.
5. The interface shows no focus distance, depth of field, time remaining or rate. The one distance, Closest Focus of This Lens, appears only for lenses listed after the device check.
6. The position shown for a frame, on the card, in the viewer and in What's in This Photo, is the one the lens reported.
7. The series pauses and continues as an Astro run does, and stops before a frame that storage can't hold.
8. On a lens whose focus can't be set, Focus can't be chosen and the reason is stated; Exposure is unaffected.
9. The sheet, card and strip of 1.0.0 are unchanged apart from the added Type control and the focus forms.
10. An idle focus card covers no more than 30% of the picture on a 402 × 874 pt screen and a running one no more than a fifth.
11. Take Bracket with Type Focus takes one focus bracket and leaves the app's own bracket as it was.
12. VoiceOver, Voice Control, Switch Control and a keyboard can set the range, start, stop and review; the audit passes on every state.

### Tests

Unit: `FocusBracketSettingsTests` (positions, step, order, swapped ends, the frame choices); `BracketModelTests`; `CameraModelFocusBracketTests` with the scripted backend (the order of set focus, wait, capture; exposure, white balance and focus restored; stop, pause, storage, battery, a camera failure; a lens that stops short); `LensCatalogTests` (minimum focus distance, −1); `ShortcutTests`; `LiveActivityTests`; `WatchTests` (busy). Capture: `SystemCaptureHardware` focus behind its protocol with a fake. Metadata tests: the exact tag set of a focus frame equals a single photo's for every switch combination.

UI, each with an accessibility audit: `testBracketTypeFocus`, `testFocusRangeSetOnThePicture`, `testFocusBracketRunsAndStops`, `testFocusBracketPausesAndContinues`, `testFocusBracketEndCards`, `testFocusNotOfferedWithoutManualFocus`, `testFocusBracketViewerAndDetails`, `testFocusBracketAtTheLargestTextSize`, `testFocusBracketRightToLeft`, `testFocusBracketNightMode`, `testFocusBracketOnIPad`; `ShortcutUITests`: Type Focus; `LiveActivityUITests`: the series.

### Strings (English), 1.1.0

| String | Where |
| --- | --- |
| Type · Exposure · Focus | The control; Take Bracket parameter |
| Focus bracketing needs a lens whose focus can be set. This lens's focus can't. | Under the control |
| Focus Range · Nearest Focus · Farthest Focus · Set on the picture · Use the Whole Range | Sheet |
| Focus Step | Sheet row |
| Even steps on this lens's own focus scale, from 0 (its closest focus) to 1 (far). iPhone doesn't report focus as a distance, so nope. shows none. | Honesty table; footer |
| Nearest First · Farthest First | Order choices |
| Return Focus When Done | Switch |
| Exposure and white balance are locked at the first frame, so every frame matches. | Footer |
| Closest Focus of This Lens · About %@ | Row |
| Use a tripod. Nothing in the picture should move between frames. | Sheet |
| Each frame is a separate single-frame photo. Nothing is merged. Stack them in other software. | Honesty table; sheet |
| Focus bracket: %lld frames | Idle card |
| Focus %@ to %@, nearest first · Focus %@ to %@, farthest first | Idle card detail |
| Nearest: %@ · Farthest: %@ | Card buttons |
| Tap the nearest thing you want sharp, or move the slider. · Tap the farthest thing you want sharp, or move the slider. | Dial |
| Set Nearest Focus · Set Farthest Focus | Dial |
| Frame %lld of %lld · Focus %@ · Stop Bracket | Running card |
| Paused: %lld of %lld frames · Continues when the camera is back | Paused card |
| Focus is back to Auto · Focus is back to %@ · Focus stays at %@ | End cards |
| %lld frames were not at their planned focus | End card |
| Bracket, focus, %lld frames | Shutter value |
| Focus bracket · frame %lld of %lld · focus %@ | Viewer chip |
| Reported by the lens · Planned Focus | Bracket group |
| Focus is a position on this lens's own scale from 0 to 1, not a distance. Kept by nope. until it closes; not written to the files. | Honesty table; Bracket group footer |
| Range · As Set in nope. · Whole Range | Take Bracket |

All are drafts for the Honesty review. The store listing and README describe focus bracketing only after it ships and the device checks are recorded.

## 9. Device checks

To be run on a device for each back lens of each supported phone, and recorded in `docs/TESTING.md` under a new heading "Bracketing on a device". The 1.0.0 items gate 1.0.0; the rest gate the start of the 1.1.0 build.

| # | Check | Gates | Decides |
| --- | --- | --- | --- |
| D1 | Each order (Darkest, Metered, Brightest First) with 3, 5 and 7 frames: the saved files' exposure times and ISO, in capture order, match The Frames | 1.0.0 | Whether Order ships |
| D2 | A bracket in full auto in bright and dim light: the frames are planned from the reading at the press | 1.0.0 | The footer sentence |
| D3 | The limited-frame mark: at the longest shutter and highest ISO, the frame taken has the offset the list states | 1.0.0 | The mark's wording |
| D4 | Whether the per-frame delegate calls arrive while later frames are still exposing | 1.0.0, optional | Whether "Taking 3 frames" can count frames; not needed to ship |
| D5 | `isLockingFocusWithCustomLensPositionSupported` and `minimumFocusDistance` for each lens, and the real closest focus measured with a ruler | 1.1.0 | Which lenses offer Focus; whether Closest Focus of This Lens is shown for a lens |
| D6 | For positions 0 to 1 in steps of 0.05: the position reported after the handler, twice in each direction | 1.1.0 | The tolerance; whether a direction rule is needed |
| D7 | Time from the request to the handler, and whether a photo taken at once after it is sharp where expected (a slanted ruler); the same with a margin of 50, 100 and 200 ms | 1.1.0 | The wait after a move; go or no-go for the feature on a lens |
| D8 | Time for each frame of a 12-frame series at 12 MP and at 48 MP, with a RAW and with a RAW and a HEIF | 1.1.0 | Nothing shown; whether the frame limit of 50 stands |
| D9 | A 20-frame series over the whole range on a slanted ruler: whether the sharp zones of neighboring frames overlap, by lens and step | 1.1.0 | The default frame count; whether a note on small steps is needed |
| D10 | The shift of the picture's scale between the two ends of the range | 1.1.0 | The tripod advice wording |
| D11 | Exposure and white balance read from each file of a series in changing light: constant | 1.1.0 | Acceptance criterion 4 |
| D12 | Battery and heat over a 50-frame series; the pause and continue on a call | 1.1.0 | The stop rules |
| D13 | The frames of one series stacked in two stacking programs: they load and align | 1.1.0 | That the feature serves its purpose. No program is named in the app |

## 10. Decisions for the owner

Each has a recommendation, and the drawings show it.

| # | Point | Recommendation | Other choice |
| --- | --- | --- | --- |
| 1 | Where bracketing lives | Bracket, a sixth word on the drive strip, between Burst and Interval, with a card and Bracket Settings. This sets aside the note in SETTINGS-PLAN.md that kept it in Pro Tools for 1.0.0 | A Q tile with a pill; or leave it in Pro Tools |
| 2 | Bracketing without Manual Controls | Yes: Bracket works in full auto, as Take Bracket already does | Offer the word only with Manual Controls on |
| 3 | A bracket with Interval or Burst | Not offered: choosing either turns the bracket off. Today an interval series with the Pro Tools switch on takes a bracket at each interval; that combination ends, and the changelog says so | Keep it as a hidden combination, or add a bracket choice to Interval Settings in a later release |
| 4 | Focus in the 1.0.0 sheet | Hidden until built. No "coming later" row: the feature depends on device checks | Show Focus dimmed, marked for 1.1.0 |
| 5 | The card names the type from 1.0.0 ("Exposure bracket: …") | Yes, so nothing changes when Focus arrives | "3 frames, 1 EV apart" in 1.0.0, renamed in 1.1.0 |
| 6 | Order | Three orders, Darkest First at first (today's order) | Metered First at first; or no Order option in 1.0.0 |
| 7 | Start Delay | In Bracket Settings (Off, 3, 10 seconds), Off at first for exposure and 3 seconds for focus | No delay option; use Take Bracket's Delay |
| 8 | The Frames list and the limit mark | In 1.0.0: it shows existing behavior that is invisible today | Leave it out; keep the sheet to four rows |
| 9 | Focus steps by depth of field | Not offered. The phone reports no focus distance for a position, so a depth of field can't be computed honestly. Frames and even steps on the lens's scale only. To be reopened only if check D9 shows a stable relation for a lens | A suggested frame count from aperture and focal length, labeled an estimate |
| 10 | Focus shown as a number from 0 to 1 | Yes, to two decimals, with the sentence that it is not a distance. The words Near, Middle and Far are too coarse for steps | Percent; or words only |
| 11 | Closest Focus of This Lens | Shown only for lenses confirmed by check D5 | Never shown |
| 12 | Most frames in a focus bracket | 50, as a burst | 100 or more, after check D12 |
| 13 | Exposure and white balance in a focus bracket | Locked at the first frame, not a choice | A switch to let them follow the light |
| 14 | A frame whose focus missed its plan | Save it, show both values, and count it on the end card | Stop the series; or retry the move once |
| 15 | The frames grouped in the viewer and in What's in This Photo | A chip and a Bracket group, from session values that no file holds | No grouping; or write the bracket into the files, which would change the allowlist and is not recommended |
| 16 | Apple Watch | No change in either release | Stop Bracket on the watch during a focus series, in 1.1.0 |
| 17 | Take Bracket | Order in 1.0.0; Type, Frames and Range in 1.1.0; one action | A separate Take Focus Bracket action |
| 18 | The names | Bracket (strip), Bracket Settings (sheet), Frames, Step, Order, Start Delay, Nearest Focus, Farthest Focus | Bracketing for the strip word; Photos in place of Frames |
| 19 | The draft wording (sections 7 and 8) | After the Honesty review | |

## 11. When this is accepted

Changes to make in the shared documents, in the release that builds each part:

- [BUILD-SPEC.md](BUILD-SPEC.md): section 2 gains the row "Bracketing: a Pro Tools section → Bracket on the drive strip"; 3.4 drops bracketing from the Pro Tools list; 3.5 lists six words, the Bracket mapping and the card states; 3.14 and 3.15 gain the chip and the Bracket group; section 4 takes the strings; section 6 takes the core changes of section 7 above; section 7 records the decisions.
- [navigation.md](navigation.md): "Bracketing, Frames, Step: Drive strip › Bracket, then the card; 1 tap to turn on, 3 to change a value" in place of the Pro Tools row.
- [ACCESSIBILITY.md](ACCESSIBILITY.md): the tables of section 6; Take Bracket "matches in the interface" becomes Drive strip › Bracket.
- [SETTINGS-PLAN.md](SETTINGS-PLAN.md): the two notes that keep bracketing in Pro Tools are marked as superseded.
- [drive.html](drive.html), [manual-controls.html](manual-controls.html) and the figures `manual-pro-tools`, `drive-strip-languages` and the iPad and Duo strips are redrawn with six words; the screen counts in [README.md](README.md) are updated.
- `docs/research/capture-and-file-settings.md`: bracket order (1.0.0); the focus series, lens position and minimum focus distance (1.1.0). `docs/PRIVACY.md`: one line that a bracket's place in its series is kept in memory until the app closes and is in no file.
- `docs/TESTING.md`: "Bracketing on a device" (section 9).
