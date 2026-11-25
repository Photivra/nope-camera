# Burst: continuous shooting

Design version: 1.0.0, direction B · Reach. Proposed and accepted 2026-11-18 for release 1.0.0: the owner accepted all thirteen recommendations of section 7. This document is the specification of Burst; [BUILD-SPEC.md](BUILD-SPEC.md) section 3.5 points here. Part E (the saving buffer, decision 4) is not built until the device measurement; where this document describes the buffer, it describes that later option. The drawings are in [burst.html](burst.html); each figure named below is `screens/<name>.html` with a PNG beside it. Tokens are in [tokens.md](tokens.md).

The request: make Burst work as continuous shooting does on a dedicated camera with interchangeable lenses. Conventions of such cameras are described here in general terms.

Contents: 1. Summary · 2. What the iPhone supports · 3. Behavior · 4. Interaction · 5. Build specification · 6. Strings · 7. Decisions for the owner · 8. When this is accepted

## 1. Summary

| | Today (0.3.0 and the 1.0.0 plan) | Proposed |
| --- | --- | --- |
| Tap the shutter in Burst | Starts a burst; the next tap stops it | Takes one photo |
| Hold the shutter in Burst | Same as a tap (the burst starts on release) | Takes photos while held; stops on release |
| Start without holding | The tap | Start Burst: a button on the card, a VoiceOver action, a Voice Control and Switch Control name |
| Hardware buttons | Hold for a burst; stops on release | The same. A short press takes one photo, as it does today |
| Speed | As fast as the camera is ready | Fast (the same) or Slow (at most 2 a second), from the Burst word's menu |
| While it runs | "Photos taken: 12", Stop Burst | The count, the measured rate, the photos waiting to be saved, and a sentence when saving is behind |
| After it ends | A sentence only when it stopped by itself | "Saving: 9 of 12 photos saved", then a summary: photos saved, time, measured rate |
| Idle | No card | A card: the speed, what the shutter does, Start Burst |
| Each frame | One single-frame Bayer RAW photo, saved on its own, allowlist, read-back, signing when on | Unchanged |
| Flash, limit, storage check, Siri count, Apple Watch, Live Activity | | Unchanged |

Principles kept: least processing (no frame is merged, nothing is dropped); honest wording (no rate is promised, the rate shown is measured from the burst itself); no gesture is the only way; nothing blinks or moves by itself; one home for each option.

## 2. What the iPhone supports

Verified means read in the code or in Apple's documentation. Everything else is an assumption until checked on a device, and must not be quoted in the app, the store listing or the README (AGENTS.md, rule 1).

| Subject | Status | What is known |
| --- | --- | --- |
| A burst mode for RAW | Verified: none | The photo output takes one request for each photo. The app sends the next request when the output reports it is ready (`CaptureReadiness.waitUntilReady`). The system's own burst feature is a processed-photo feature and is not used |
| What a burst is in the code | Verified | `CameraModel.takeFrames`: `capturePhoto`, then the frame is saved while the next is taken. The rate is the slower of taking and saving. At most two frames are in memory |
| Frames a second, RAW | Not measured | `docs/TESTING.md`, "Burst rate", has no figures. Assumption: a few a second at 12 MP; about one a second or fewer at 48 MP and with HEIF or JPEG copies, because each copy is developed and encoded while saving. Measure on each lens for RAW, RAW + HEIF and HEIF |
| Taking time and saving time, separately | Not measured | Needed for decision 4. `SavedPhoto` already carries the capture duration; the saving time needs a signpost |
| Live picture between frames | Assumption | The preview layer is its own output and keeps running during a photo request. Record whether it stutters at each RAW photo |
| Focus and exposure between frames | Assumption | In full auto the device stays in continuous autofocus and auto exposure, so each frame can differ. With AE/AF lock or manual values the device holds them. Record whether exposure visibly lags over a burst |
| Shutter sound | System behavior | Played by the system for each photo; it follows the system setting and the region. The app adds none and cannot silence it |
| Haptic taps during capture | Assumption | The app takes photos without an audio session, so taps should play. Check on a device |
| Memory for waiting frames | Not measured | The estimate is 2 bytes a pixel (`PhotoSizeEstimate`, an upper bound): about 24 MB at 12 MP and 97 MB at 48 MP for each waiting frame |
| Time to finish saving after leaving the app | Verified in part | The app asks for background time to finish saving (`SystemLiveActivities`, "Finish saving photos"). With more frames waiting this must be checked again |
| Heat | Not measured | The camera pauses at the existing heat level; a burst then ends with "the camera stopped". Record the heat level after three bursts of 50 |

The measured figures go in `docs/TESTING.md`, "Burst rate", before any wording here is treated as final. The numbers in the drawings (2.6 a second, 8 waiting places) are samples.

## 3. Behavior

### 3.1 The shutter in Burst

- The first photo is taken when the shutter goes down, not when it comes up. There is no delay to tell a tap from a hold: a tap is a short hold, and yields one photo because the finger lifts before the camera is ready for a second.
- While the shutter stays down, photos are taken at the chosen speed. Lifting the finger, sliding it off the shutter, or the system cancelling the touch ends the burst after the photo being taken.
- Every photo taken is saved. Nothing is discarded to keep up.
- Start Burst starts a burst that needs no holding. It ends when the shutter is pressed, when Stop Burst is pressed, or at a limit. This is today's tap-to-start behavior under its own button.
- A burst of one photo is a photo: it is announced and shown as any single photo, with no summary.
- No flash in Burst, for one photo or many, so a tap and a hold behave the same.

### 3.2 Speed

| Speed | Rule | Words |
| --- | --- | --- |
| Fast (default) | The next photo is requested as soon as the camera is ready | "As fast as the camera is ready" |
| Slow | The same, and at least 0.5 s between the starts of two photos | "Up to 2 photos a second" |

- The speed is chosen from the menu of the selected Burst word, as Timer's delay is. It is held for the session and not stored: each launch starts at Fast, as each launch starts in Single.
- "Up to" is the only claim a paced speed makes. If the camera needs longer than half a second, Slow and Fast run the same, and the card shows the same measured rate.
- Siri and Shortcuts bursts always run at Fast, so "as fast as the camera allows" in the action's description stays true.

### 3.3 The rate shown

- The card shows the rate of the burst that is running: photos a second over the most recent five photos, from the third photo on, to one decimal place.
- The summary shows the rate of the whole burst: the photos taken less one, divided by the time from the first photo to the last.
- No rate is shown before a burst, in Settings, or anywhere as a property of the device.

### 3.4 Saving, and slowing when it falls behind

Today each photo is saved while the next is taken, so one photo waits at most. Decision 4 asks whether to let more wait:

- With a buffer: up to N photos taken and not yet saved are held in memory. While places are free, the camera sets the pace. When all are in use, the next photo is taken when one has been saved, so the burst runs at the saving speed. The card shows the places as marks, filled for waiting photos, with the words "Waiting to save: 3 of 8", and adds "Slower while photos save" when all are filled.
- Without a buffer: the code stays as it is. The card shows no waiting row (`burst-holding-no-buffer`), and "Slower while photos save" is never shown, because the burst always runs at the slower of the two.
- Either way, after the burst ends the photos still waiting are saved, the card reads "Saving: 9 of 12 photos saved" with a bar, and the shutter is dimmed until they are saved.

### 3.5 Picture, focus and exposure

- The picture stays live. No blackout is drawn and the screen does not blink for each photo: several flashes a second over most of the screen would break the flashing limit of WCAG 2.2 (2.3.1) and the rule that nothing blinks.
- Each photo is marked three ways: the count on the card, a light tap, and the system's shutter sound. None of the three is the only signal.
- Focus and exposure are whatever is set. In full auto they keep adjusting between photos. With AE/AF lock, or with values set in Manual Controls, every photo uses them. No setting is added.

### 3.6 Limits and what stops a burst

| Cause | Result | Words (existing unless marked new) |
| --- | --- | --- |
| Release, Stop Burst, the shutter | Ends after the photo being taken | Summary (new) |
| 50 photos (`DriveModel.maximumBurstFrames`) | Ends | "Burst stopped at 50 photos, the most one burst takes." |
| The next photo would not fit in storage | Ends before it is taken | "Burst stopped: storage is full." |
| The camera stops: another app, a call, heat, the app leaves the screen | Ends | "Burst stopped: the camera stopped." |
| A photo cannot be taken or saved | Ends; the photos before it are saved | The failure banner, as for any photo |
| Low battery | Does not stop a burst | The Battery Low chip, as today |
| Low Power Mode | No change | |

After a burst that stopped by itself, the card's detail line adds the time and the rate, or the photos saved (`burst-limit`, `burst-storage-full`).

## 4. Interaction

### 4.1 Inputs

| Input | In Burst, idle | While a burst runs |
| --- | --- | --- |
| Shutter, touch down | Starts taking photos | Nothing |
| Shutter, touch up, slide off, cancelled touch | Ends the burst | Ends the burst (also one started with Start Burst) |
| Start Burst (card) | Starts a burst that needs no holding | Not shown; Stop Burst takes its place |
| Stop Burst (card) | Not shown | Ends the burst. Shown only for a burst started with Start Burst, Siri or the keyboard; while the shutter is held the card says "Release to stop" |
| Volume buttons, Camera Control, headphone remote | Down: starts. Up: ends. Unchanged | Up: ends the burst |
| Space bar (with nothing focused) | One photo | Ends the burst |
| Pointer on iPad | Press and hold as a finger | As a finger |
| Apple Watch remote | One photo for each tap, with or without its delay | The watch shows "The camera was busy. No photo taken." |
| Siri and Shortcuts, Take Photo | Number of Photos 1: one photo. 2 to 50: exactly that many, at Fast | "nope. is already taking a photo.", as today |
| Drive strip | The selected word opens the speed menu | The other words are dimmed; the menu does not open |
| Lens, Manual Controls, Q | As in any mode | Unchanged from today's burst |

### 4.2 Without holding: VoiceOver, Voice Control, Switch Control, keyboard

Holding a button is never required.

| Aid | One photo | A burst | Stop |
| --- | --- | --- | --- |
| VoiceOver | Double tap the shutter | Double tap and hold the shutter (the system passes the hold through), or the action Start Burst on the shutter, or the Start Burst button | Lift the finger; or double tap the shutter; or Stop Burst |
| Voice Control | "Tap Take Photo" | "Tap Start Burst" | "Tap Stop Burst" or "Tap Take Photo" |
| Switch Control | Select Take Photo | Select Start Burst | Select Stop Burst or Take Photo |
| Full Keyboard Access, a keyboard | Space, or Return on the shutter | Tab to Start Burst, then Space or Return | Space |
| AssistiveTouch, Touch Accommodations | A tap | Start Burst | Stop Burst |

VoiceOver:

- The shutter keeps the name Take Photo. Its value in Burst: "Burst, fast." or "Burst, slow.", and the hint "Double tap for one photo. Double tap and hold for a burst." It has the action Start Burst while idle.
- While a burst runs, the value is today's "Taking a burst. Press to stop."
- Announcements: "Burst started." when a burst starts with Start Burst (existing sentence). None at the start of a held burst: the shutter sound and the tap for each photo carry it, and speech would lag behind the photos. At the end, the existing save sentence is spoken once for the burst ("12 photos saved and signed." or its unsigned forms). A burst that stopped by itself speaks its sentence first.
- The card is one element while running, updated politely: "Photos taken: 12. 2.6 a second. Waiting to save: 3 of 8." The marks are hidden from VoiceOver; the words carry the count.
- The drive strip's Burst word: label Burst, value the speed, selected trait, and no hint beyond the menu's own, as the selected Timer has none.
- Order: status, pills, picture, card (text, then its button), Manual Controls, lenses, Switch Camera, drive strip, Last Photo, shutter, Q. Start Burst is reached just before the lens row, and the shutter's action reaches it without moving.

Switch Control and scanning: Start Burst and Stop Burst are ordinary buttons in the scan. Nothing needs a hold or a timed press. A burst started this way has no time limit other than the 50 photos.

### 4.3 Haptics and sound

| Moment | Feedback | Token |
| --- | --- | --- |
| Shutter down | The shutter impact, as today | `NopeHaptic.shutter` |
| Each photo after the first | One light tap | new `NopeHaptic.burstFrame` |
| The burst's photos are all saved | One light impact, once | `NopeHaptic.saved` |
| A photo was not saved | The error haptic, as today | `NopeHaptic.notSaved` |
| Speed chosen | Selection | `NopeHaptic.driveModeChanged` |

The shutter sound is the system's. The app plays no sound. No information is carried by sound or by a tap alone: the count is on the card and the result is spoken.

### 4.4 Text size, direction, orientation, night mode

- Largest text sizes (`burst-largest`, `burst-largest-idle`): the scrolling layout. The card's lines are full-width text, Start Burst and Stop Burst are full-width rows, and the Burst row shows the speed as its value. The marks are left out.
- Right to left (`burst-rtl`): the card mirrors; the marks fill from the leading edge; numbers keep their order.
- Sideways (`burst-sideways`): the card sits on the picture's lower edge as seen sideways; the strip shows symbols; the pill on the picture names the mode.
- Night mode (`burst-night`): red on black; a filled mark and an outlined mark differ by shape, not color.
- iPad and the iPhone Duo inner display (`burst-ipad-*`): the column layout. The Duo outer display and compact iPad windows follow the iPhone drawings. Folding or unfolding during a held burst ends the touch, so the burst ends and its photos are saved.
- Reduce Motion: the pressed shutter changes without animation. Nothing else moves.

### 4.5 Interruptions

| Event | Result |
| --- | --- |
| A call, another app takes the camera, the camera pauses for heat | The burst ends ("the camera stopped"); photos taken are saved |
| The app goes to the background (Home, the app switcher, the lock button) | The burst ends. The Live Activity shows "Saving: n of m photos saved" while the waiting photos are saved in the time the system gives |
| Control Center or Notification Center pulled over the camera | The touch is cancelled, so a held burst ends. A burst started with Start Burst continues, as the camera does |
| A system alert (low battery, the Photos prompt on the first save) | The touch is cancelled: a held burst ends |
| The device rotates | Nothing; the burst continues |
| The Last Photo viewer, a sheet or Settings is open | The on-screen shutter is not there. Hardware buttons follow section 3.14 of BUILD-SPEC.md |
| Storage runs out | The burst ends before the photo that would not fit |

## 5. Build specification

For the implementer. The ground rules of [BUILD-SPEC.md](BUILD-SPEC.md) section 1 apply. Names below are proposals; keep the existing naming style.

### 5.1 Scope

Release 1.0.0 changes the interface of features that exist. Each part is marked.

| Part | Kind | Needs |
| --- | --- | --- |
| A. Hold on the on-screen shutter; a tap takes one photo; Start Burst | Interface of the existing burst. The hold exists for hardware buttons; Start Burst is today's tap | Decisions 1 and 2 |
| B. Idle card, running card with the measured rate, saving row, summary | Interface. Small additions to the state the model publishes (times, who started the burst) | Decision 6 |
| C. Per-photo tap, VoiceOver action and wording | Interface | none |
| D. Speed: Fast and Slow | New capability: pacing in the capture loop | Decision 3 |
| E. Saving buffer deeper than one photo | New capability: changes the memory bound stated in `AGENTS.md` ("Release RAW buffers as soon as each photo is saved" still holds) and in ARCHITECTURE.md | Decision 4, after the device measurement |

Parts A to C can ship without D and E. The figures marked for the buffer apply only with E.

### 5.2 Core (`Sources/NopeCore`)

`DriveMode.swift`

- `ShutterPhase`: rename `HardwareButtonPhase` (keep a deprecated `typealias`), since the on-screen shutter now reports the same three phases.
- `BurstSpeed: CaseIterable, Sendable` with `.fast` and `.slow`; `minimumFrameInterval: Duration?` is `nil` and 0.5 s. (Part D.)
- `BurstStart`: `.held`, `.started`, `.counted`. Who began the burst, so the interface knows whether to show Stop Burst or "Release to stop".
- `DriveIntent`: add `.shutter(ShutterPhase)` for the on-screen shutter in Burst, `.startBurst`, and `.setBurstSpeed(BurstSpeed)`. `.hardwareButton` stays and uses the same handler.
- `BurstProgress`: add `start: BurstStart`, `rate: Double?` (section 3.3; `nil` before the third photo), `waitingCapacity: Int`, `isSaving: Bool` (no more photos will be taken; the waiting ones are being saved). Computed: `waiting = taken - saved`, `isSlowed = waitingCapacity > 1 && waiting >= waitingCapacity`.
- `BurstResult`: add `taken: Int`, `duration: Duration` (first photo to last) and `rate: Double?` (whole burst; `nil` under three photos).
- `DriveModel`: `burstSpeed` (session only, `.fast` at launch; `setBurstSpeed` ignored while busy); `recordTaken(at:)` keeps the times of the most recent five photos and the first.

`CameraModel+Drive.swift`

- `pressShutter()` in `.burst` with nothing running: `takeBurst(frames: 1)`. This is the path for `.capture`: assistive activation, Space, and any interface that does not report phases. A running burst is stopped, as today.
- `handleHardwareButton` becomes `handleShutterPhase`, used by `.hardwareButton` and `.shutter`. Its Burst branch is today's: `.pressed` starts `takeBurst(start: .held)` unless busy; `.released` and `.cancelled` request the stop, or cancel a countdown. Outside Burst, `.hardwareButton` keeps acting on release; `.shutter` is not sent outside Burst.
- `.startBurst`: `takeBurst(start: .started)` when the mode is Burst, a photo can be taken and nothing runs.
- `takeBurst(frames:start:)`: passes the speed's interval (always `nil` for `.counted`) and the buffer depth to `takeFrames`.
- `takeFrames`: two new parameters, both defaulting to today's behavior so the astro run is unchanged.
  - `minimumInterval: Duration?` (part D): before each photo after the first, wait until the previous photo's start plus the interval, using the injected sleep and `now()`. Check `stopReason` again after the wait.
  - `waitingFrames: Int = 1` (part E): keep the saves in a first-in, first-out list; each save starts when the one before it ends, so photos reach Photos in order and one save runs at a time. Take the next photo without waiting while the list is shorter than `waitingFrames`; when it is full, await the oldest. With 1 this is today's code. After the loop, set `isSaving` and collect the rest in order. At most `waitingFrames + 1` frames are in memory.
- `canPressShutter`: false while `burstProgress?.isSaving == true`.
- `DriveModel.waitingFrames(bytesPerFrame:)` (part E): `min(8, max(1, memoryBudget / bytesPerFrame))`, with `bytesPerFrame` from `PhotoSizeEstimate` for the RAW alone and `memoryBudget` 256 MB. Both constants are assumptions to be set from the Instruments measurement; with the estimate they give 8 places at 12 MP and 2 at 48 MP.

Unchanged: `stopReason`, `finishRun`, `maximumBurstFrames`, the Siri count (`CameraModel+Shortcuts.swift`), the watch (`CameraModel+Watch.swift`, `WatchCommandServer.swift`), `LiveActivity.swift` (its saving phase already reads `taken` and `saved`).

`SimulatedCaptureBackend.swift` and `App/NopeApp/DebugTools/SimulatedCameraLaunch.swift`: a capture delay for the simulated camera, so the rate and the waiting row can be shown in the Simulator; a launch state `slowSavingFastCamera` beside `slowSaving`.

### 5.3 Interface (`Sources/NopeUI`, app targets)

| File | Change |
| --- | --- |
| `ShutterButton.swift` | A `ButtonStyle` that reports `configuration.isPressed` through a new `onPressChange` closure, and draws the pressed disc at `NopeSize.shutterDiscHeld` (no animation with Reduce Motion). The closure is given only in Burst. The button's action still runs for a touch that ends inside and for assistive activation: it is skipped when the same touch already reported a press, so a tap takes one photo, not two. `Face` is unchanged: a held burst keeps the disc, a started burst shows the stop square |
| `CameraReadyView.swift` | In Burst, pass `onPressChange`: pressed sends `.drive(.shutter(.pressed))` and closes Q; not pressed sends `.released`. The action sends `.capture` as today. Add the accessibility action Start Burst to the shutter while Burst is idle. `shutterFace`: `.stop` only for a burst whose `start` is not `.held` |
| `DriveStrip.swift` | The selected Burst is a `Menu` with a `Picker` of `BurstSpeed`, each row a title and a subtitle, as the selected Timer is. Value: the speed. In the scrolling layout the Burst row shows the speed as its value. `choose(_:)` needs no Burst case |
| `DriveControls.swift` | `ModeCardState`: add `.burstIdle(BurstSpeed)` and `.burstSaving(saved:taken:)`; `.burstRunning` carries the `BurstProgress`; `.burstEnded` is used for every burst of two photos or more that was not a Siri count and did not fail. Resolve order: running, saving, ended (until the next action, as today), idle. `ModeCard` gains an optional second row: `BurstWaitingRow` (marks and words) or the progress bar it already has. `DriveText.shutterValue` and the new hint; `DriveFeedback`: the per-photo haptic on `burstProgress.taken` above 1, "Burst started." only for `.started` |
| `DesignTokens.swift` | `NopeSize.shutterDiscHeld` (50), `NopeSize.bufferMark` (14 × 10, radius `NopeRadius.small` / 4, outline `NopeSize.outline`), `NopeHaptic.burstFrame` (`.impact(weight: .light, intensity: 0.6)`). Add them to [tokens.md](tokens.md) |
| `AccessibilitySettingsView.swift` | The Self-Timer and Burst text (section 6) |
| `SettingsSearch.swift` | The Burst entry's keywords: add "continuous", "speed" |
| `App/NopeApp/NopeApp.swift` | Type name only (`ShutterPhase`) |
| `App/NopeApp/Intents/TakePhotoIntent.swift`, `App/Shared/SeriesActivity.swift`, `App/NopeWatch/*` | No change |

Card layout (`burst-idle`, `burst-holding`, `burst-saving`, `burst-summary`): `ModeCard` as built for Interval and Astro: `NopeRadius.large`, `NopeMaterial.backing`, title `NopeFont.status`, detail `NopeFont.pill` in `NopeColor.labelSecondary`, monospaced digits. The second row is `NopeSpace.xs` below the first; marks are `NopeSpace.xxs` apart. The card never takes the warning color. In the column layout it sits above the strip at the width the other cards use. Running, it must cover no more than a sixth of the picture, as the Astro card.

### 5.4 Acceptance criteria

- In Burst, a tap on the shutter saves exactly one photo; holding saves two or more on the simulated camera and stops within one photo of the release; sliding off the shutter stops it.
- The first photo is requested on touch down.
- Start Burst starts a burst that continues with no touch; the shutter, Stop Burst, Space and a hardware button each stop it.
- Hardware buttons behave as before the change, in every drive mode.
- Outside Burst the shutter behaves exactly as before: it acts on release, and nothing is sent on touch down.
- A burst of one photo shows no summary and no "Burst started." announcement, and reads as a single photo to VoiceOver and to the watch.
- The rate shown is computed from the burst's own photo times. No rate appears before the third photo or outside a burst. No string states a rate as a property of the device. Slow is worded "up to".
- With Slow, no two photo starts are less than 0.5 s apart (unit test with the injected clock).
- Every photo taken is saved after any stop; the saved count in the summary equals the photos added to Photos.
- Part E: the photos held in memory never exceed the waiting places plus one; photos reach Photos in the order taken; the astro run still holds one.
- While the waiting photos are saved, the shutter is disabled and the card shows saved of taken; the summary appears only when all are saved.
- No element blinks; with Reduce Motion nothing animates; in night mode no pixel of the card is non-red.
- VoiceOver: the shutter's value, hint and Start Burst action as in section 4.2; a burst can be started and stopped with no hold. Every new control is at least 44 pt and passes the audit.
- The card covers no more than a sixth of the picture while running and no more than a quarter idle, on a 402 × 874 pt screen at the default text size.
- Coverage of non-UI code stays at 100%.

### 5.5 Unit tests (`Tests/NopeCoreTests/DriveTests.swift`, `Tests/NopeUITests`)

| Test | Covers |
| --- | --- |
| `testCaptureInBurstTakesOnePhoto` | `.capture` in Burst: one frame, end `.countReached`, status `.savedBurst` of one |
| `testShutterPhasesRunABurstWhileHeld` | `.shutter(.pressed)` then `.released` on the simulated camera with a capture delay: two or more frames, end `.stopped`, start `.held` |
| `testShutterReleaseBeforeTheSecondFrameSavesOne` | The tap case |
| `testCancelledShutterStopsTheBurst` | `.cancelled` |
| `testStartBurstRunsUntilStopped` | `.startBurst`, then `.capture`, `.stopBurst` and a hardware release each stop it; ignored outside Burst and while busy |
| `testHardwareButtonsUnchangedOutsideBurst` | Existing tests keep passing under the renamed type |
| `testBurstSpeedDefaultsToFastAndIsNotStored` | The session rule; ignored while busy |
| `testSlowBurstSpacesFrameStarts` | Injected clock: starts at least 0.5 s apart; a stop during the wait takes no further photo |
| `testCountedBurstIgnoresSlow` | Siri count runs at Fast |
| `testBurstRateUsesTheLastFivePhotos`, `testBurstRateIsNilBeforeThreePhotos`, `testBurstResultDurationAndRate` | Section 3.3, with fixed times |
| `testWaitingFramesNeverExceedCapacity`, `testSavesFinishInOrder`, `testFullBufferWaitsForASave`, `testAstroRunStillHoldsOneFrame`, `testWaitingFramesForPhotoSize` | Part E |
| `testBurstIsSavingAfterStopUntilAllSaved`, `testShutterDisabledWhileBurstSaves` | The saving state |
| `testFailureKeepsEarlierFrames` | A failed frame with photos waiting: the earlier ones are saved, the end is `.failed` |
| `ModeCardState` tests | Each new case and the resolve order; a one-photo burst has no ended card; a Siri count has none |
| `DriveText` tests | The shutter's value and hint for each speed; the rate and duration formats in English and in a right-to-left locale |

### 5.6 UI tests (new `BurstUITests.swift`, an extension of `NopeAppUITests`; each with `performAccessibilityAudit()` through the existing helpers)

| Test | Covers |
| --- | --- |
| `testBurstIdleCardShowsSpeedAndStart` | The idle card; replaces the "no idle card" assertion in `testBurstCardShowsCountAndStops` |
| `testBurstTapTakesOnePhoto` | `tap()`: one photo in the viewer's count, no summary |
| `testBurstHoldTakesPhotosUntilRelease` | `press(forDuration:)`: the count rises, "Release to stop", no Stop Burst button; after release the saving row, then the summary |
| `testBurstStartButtonRunsAndStops` | Start Burst, the stop square, Stop Burst; replaces `testBurstRunsUntilStoppedAndSavesEachFrame`'s tap flow |
| `testBurstSpeedMenu` | The selected word opens the menu; Slow changes the card's title; the value on the strip |
| `testBurstWaitingRowAndSlowed` (part E) | `slowSavingFastCamera`: the row, and the sentence when full |
| `testBurstSummaryStaysUntilNextAction` | A lens change clears it |
| `testBurstStopsAtLimitAndForStorage` | The two sentences with their detail lines |
| `testBurstVoiceOverValueHintAndAction` | The shutter's value and hint; the Start Burst action through `accessibilityCustomActions`; activation takes one photo |
| `testBurstLargestText`, `testBurstRightToLeft`, `testBurstNightModeIsAllRed`, `testBurstSideways` | The audits, with `auditScrollingScreen` and `nonRedPixels` as the drive card tests use them |
| `testBurstOnIPad` (iPad shard) | The column layout, a pointer press, Space for one photo |

Update `DriveCardsUITests.testBurstCardShowsCountAndStops`, `NopeAppUITests.testBurstRunsUntilStoppedAndSavesEachFrame`, and `ShortcutUITests.testACountTakesABurstThenSaysThePhotosWereSaved` (unchanged behavior; confirm it still passes). Add the new tests to `scripts/ui-test-shards.txt`.

### 5.7 On a device, before release

Add to `docs/TESTING.md` and record the results there:

- "Burst rate": for each lens, at each Photo Size, for RAW, RAW + HEIF, RAW + HEIF + JPEG and HEIF, with signing on and off: frames a second at Fast over 20 photos, and the taking time and the saving time of one photo. These settle decision 4 and whether Slow at 2 a second is below Fast on every lens (if it is not, Slow is hidden on that lens or its figure is lowered; decision 3).
- Hold the shutter, the volume buttons and the Camera Control: the first photo on press, the stop within one photo of release, a tap gives one photo.
- The picture between photos: live, or the stutter seen. Focus and exposure following a moving subject in full auto; held with AE/AF lock.
- The per-photo tap is felt; the shutter sound follows the system.
- Memory over three bursts of 50 at 12 MP and at 48 MP (Instruments, Allocations): flat, and under the budget of part E.
- Leave the app during a burst with photos waiting: all are saved, and the Live Activity counts them.
- VoiceOver: double tap, double tap and hold, the Start Burst action. Voice Control and Switch Control: start and stop with no hold.
- Heat level after three bursts of 50.

### 5.8 Documents to update with the build

`docs/ARCHITECTURE.md` ("Drive modes: single, self-timer, burst"), `docs/TESTING.md` (the burst rows and "Burst rate"), `docs/BUILDING-AN-INTERFACE.md` (the shutter phases), `docs/design/ACCESSIBILITY.md` (rows 7, 13 and 15 of the camera table), `docs/design/BUILD-SPEC.md` (3.5, section 4), `docs/design/tokens.md`, `CHANGELOG.md`, and `AGENTS.md` only if part E changes a stated bound.

## 6. Strings (English; version 1.0.0 ships in English only)

New, in `Localizable.xcstrings` of `NopeUI`, each with a translator comment:

| String | Where | Note for translators |
| --- | --- | --- |
| Fast burst | Idle card title | The speed in use: photos are taken as fast as the camera is ready |
| Slow burst: up to %lld a second | Idle card title | The number is the most photos a second, 2 |
| Hold the shutter. A tap takes one photo. | Idle card detail | What the shutter does in Burst |
| Start Burst | Card button; VoiceOver action on the shutter; Voice Control name | Starts a burst that runs without holding the shutter |
| Burst Speed | Menu title | |
| Fast | Menu row | |
| As fast as the camera is ready | Menu row detail | Makes no claim about a rate |
| Slow | Menu row | |
| Up to %lld photos a second | Menu row detail | "Up to": it can be fewer |
| %@ a second | Card detail | A measured rate with one decimal place, such as 2.6 |
| Release to stop | Card detail while the shutter is held | |
| Slower while photos save | Card detail when every waiting place is in use | Not a warning |
| Waiting to save: %lld of %lld | Card second row | Photos taken and not yet saved, of the most that can wait |
| Saving: %lld of %lld photos saved | Card after the burst ends | The Live Activity has the same sentence |
| %lld photos saved | Summary title | At least 2; with plural forms |
| %@ · %@ | Summary detail | A duration ("4.2 seconds") and a rate ("2.6 a second") |
| Burst, fast. / Burst, slow. | VoiceOver value of the shutter | Replaces "Burst. Press to start, press again to stop." |
| Double tap for one photo. Double tap and hold for a burst. | VoiceOver hint of the shutter | |

Changed:

| Today | Proposed | Where |
| --- | --- | --- |
| Burst. Press to start, press again to stop. | Removed (see above) | Shutter value |
| Timer, above the shutter, sets a self-timer of 3 or 10 seconds. Burst is beside it. VoiceOver says each second of the countdown. | Timer, above the shutter, sets a self-timer of 3 or 10 seconds. Burst is beside it: hold the shutter for a burst, or use Start Burst so nothing has to be held. VoiceOver says each second of the countdown. | Settings › Accessibility |
| Comment of "Burst" (drive word): "holding the shutter takes a rapid run of separate photos" | Keep; it is now true of the on-screen shutter too | Translator comment |

Kept as they are: "Photos taken: %lld", "Stop Burst", "Burst started.", "Taking a burst. Press to stop.", the three "Burst stopped…" sentences, the save sentences in `Honesty.xcstrings`, the Take Photo action's "More than one takes a burst: separate photos, as fast as the camera allows, up to 50.", and every watch and Live Activity string.

Nothing here is Honesty wording about processing or signing. The rate and "up to" wording should still get the Honesty review, since it is the kind of claim rule 3 covers.

## 7. Decisions for the owner

All thirteen recommendations were accepted on 2026-11-18. Decision 3: Slow is hidden on a lens where Fast has been measured under about 3 a second; the app measures this from the bursts it takes at Fast on that lens. Decision 4: no buffer in 1.0.0; the card is `burst-holding-no-buffer`.

| # | Question | Recommendation | Kind |
| --- | --- | --- | --- |
| 1 | In Burst, does a tap take one photo, with holding for a burst? Or does a tap keep starting a burst? | A tap takes one photo; holding takes a burst. It is what a dedicated camera does and what the hardware buttons already do | Interface |
| 2 | Keep a way to run a burst without holding? | Yes: Start Burst on the idle card, as a VoiceOver action and by name. The cost is an idle card on the picture in Burst (52 pt). Without it, people who cannot hold a button lose the feature | Interface |
| 3 | Which speeds, and the default? | Two: Fast (default) and Slow at up to 2 a second, session only. Three tiers are not recommended: the gap between them is likely smaller than the camera's own variation. If the measurement shows Fast is under about 3 a second on a lens, offer no Slow there. Alternative: no speed choice in 1.0.0 | New capability (small) |
| 4 | Let more than one photo wait to be saved (a buffer)? | Decide after the device measurement. Build it only if taking is at least one and a half times as fast as saving on the main lens at 12 MP; otherwise it adds memory use and nothing visible. If built: up to 8 places, fewer for large photos, saves in order | New capability |
| 5 | The most photos in one burst | Keep 50 for 1.0.0: it matches the Siri range, and heat and memory beyond it are not measured. Revisit after the measurement | Existing |
| 6 | Show the measured rate on the card and in the summary? | Yes. It is the honest form of a frames-a-second figure. Alternative: the count and time only | Interface |
| 7 | Focus and exposure for each photo: follow, or lock at the first? | Follow what is set, with no new option. AE/AF lock and Manual Controls already hold both. A "lock at the first photo" option would be a new capability | Existing |
| 8 | A cue for each photo | The count, a light tap and the system's sound. No screen blink | Interface |
| 9 | May a new burst start while the last one is still saving? | No in 1.0.0: the shutter is dimmed until the waiting photos are saved (a second or two). Allowing it needs the buffer to be shared across bursts | New capability if yes |
| 10 | Should the Apple Watch remote start or hold a burst? | No in 1.0.0. One photo for each tap, as today | New capability if yes |
| 11 | Siri and Shortcuts | No change. Number of Photos runs at Fast. A speed setting for the action is not recommended | Existing |
| 12 | Do Interval and Astro share anything new? | Only what they share already: the mode card and the capture loop. The waiting buffer and the pacing are off for Astro. Giving Interval and Astro the same end summary is a separate, later change | Existing |
| 13 | Is the speed remembered between launches? | No, as the drive mode and the timer's delay are not | Interface |

## 8. When this is accepted

Done on 2026-11-18, with one change: sections 3 to 6 stay in this file as the one specification of Burst, and BUILD-SPEC.md section 3.5 and ACCESSIBILITY.md point here, so the rules are not kept in two places.

- The figures `drive-burst`, `drive-burst-running`, `ipad-burst` and `ipad-burst-running` are replaced by the `burst-*` figures; remove them and point [drive.html](drive.html) and [ipad.html](ipad.html) at [burst.html](burst.html).
- Add Burst to the page navigation of the set, to [overview.html](overview.html) and to the table in [README.md](README.md); update the screen counts.
- Move sections 3 to 6 into [BUILD-SPEC.md](BUILD-SPEC.md) (3.5, section 4) and [ACCESSIBILITY.md](ACCESSIBILITY.md), with the decisions recorded in BUILD-SPEC.md section 7, and remove them from this file.
- [navigation.md](navigation.md): Burst speed, home "Drive strip", path "Burst, Burst", 2 taps.
