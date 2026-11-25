# Level haptic

Status: accepted 2026-11-18, all ten decisions in section 11 as recommended; built for release 1.0.0. No drawing changes: a haptic has no picture, and the level is drawn as it is in [camera.html](camera.html).

The request: a tap you can feel when the level becomes level.

Sources: issue 40 (grid and level), the code as of release branch 1.0.0 (`Sources/NopeCore/Level.swift`, `Sources/NopeUI/ViewfinderOverlays.swift`, `Sources/NopeUI/DesignTokens.swift`, `App/NopeApp/Camera/MotionGravitySource.swift`, `App/NopeWatch/RemoteShutterView.swift`), [tokens.md](tokens.md), [ACCESSIBILITY.md](ACCESSIBILITY.md), [SETTINGS-PLAN.md](SETTINGS-PLAN.md), Apple's SwiftUI documentation for `SensoryFeedback`, and Apple's Human Interface Guidelines (Playing haptics).

Evidence note: everything below about the code was read from the code. Nothing here was felt on a device. Each statement about how a haptic feels, or whether it plays in a given state, is marked as a device check in section 10.

## 1. What exists today

The app already plays a haptic when the level becomes level. It was built with the level (issue 40, release 0.2.0).

| Part | Today | Where |
| --- | --- | --- |
| Feedback | `NopeHaptic.levelFlat`, which is `.alignment` | `DesignTokens.swift`; [tokens.md](tokens.md), "Haptics" |
| When | The level's `isLevel` changes from false to true. Nothing on leaving level | `LevelOverlay`, `.sensoryFeedback(..., trigger: state?.isLevel ?? false)` |
| Becomes level | Tilt of 1.0° or less | `LevelTracker.levelTolerance` |
| Stops being level | Tilt above 1.5° | `LevelTracker.releaseTolerance` |
| Horizon level | One angle: how far the device is turned from the nearest upright or sideways position. Pointing the lens up or down is not measured | `LevelTracker.horizonState` |
| Top-down level | Two angles, pitch and roll. Level when the larger is within the tolerance. Starts within 25° of straight down, ends beyond 35° | `LevelTracker.flatState`, `flatEntryAngle`, `flatExitAngle` |
| Readings | 20 a second, only while the level is shown | `MotionGravitySource.updateInterval` |
| Switch | Level is off by default (Q tile, or Settings › Viewfinder Overlays) | `OverlayOptions.showsLevel` |
| VoiceOver | Reads "Level" or "Tilted 3° clockwise" as the level's value on request. Nothing is announced when it changes | `LevelText` |
| Apple Watch | The watch does not know the phone's level | `WatchRemote` |

Why the tap may go unnoticed today, in the order to check:

1. **Level is off by default,** and nothing in the app says the level gives a tap. The Level switch's explanation and the Accessibility page do not mention it.
2. **`.alignment` may be faint on iPhone.** Apple documents it as playing on iOS and macOS, for a dragged item coming into alignment. How strong it feels in the hand on an iPhone has not been measured for this app.
3. **System Haptics is off** on the device (iOS Settings › Sounds & Haptics).
4. **The device is an iPad,** which has no Taptic Engine.

So this design keeps the feature, makes it known, and tightens its rules. Sections 2 to 9 state the full behavior; "new" marks what is not in the code today.

## 2. When it fires

One event: **the level becomes level.** In the code's terms, `LevelState.isLevel` goes from false to true.

| Rule | Value | Status |
| --- | --- | --- |
| Enter level | Tilt ≤ 1.0° | Existing |
| Leave level | Tilt > 1.5° | Existing |
| Once per entry | One tap as the level is entered. None while it is held, however long | Existing |
| Leaving level | No tap | Existing |
| Re-arm | The level must be left (tilt above 1.5°) before another tap | Existing |
| Minimum time between taps | 1.0 second. An entry sooner than that after the last tap gives no tap; it is dropped, not played late | New |
| First reading | No tap for the first reading after the level appears, even if it is level. The tap marks a change the person made, not the level being switched on | New |
| Passing through | Turning quickly through level gives a tap. No hold time is required, so the tap arrives at the moment of alignment | Existing |

Why 1.0° and 1.5° stay: the tap and the bar must agree. The bar turns solid and thicker at the same moment as the tap, and the 0.5° band keeps both from flickering at the edge. A bar within 1° of the horizon looks level on a phone screen (the reason given in `LevelTracker`).

Why the minimum time is added: a hand held near 1.2° can drift past 1.5° and back under 1.0° several times in a few seconds. Each return is a real entry, so today each gives a tap. One second between taps keeps a steady hand from producing a run of them. The bar is not rate-limited; it always shows the true state.

### Roll and pitch

- **Horizon level** (the device held up): one angle, the rotation about the lens. The tap marks that angle reaching level in any of the four positions (upright, either side, upside down). Tilting the lens up or down is not shown by the horizon level, so it has no tap.
- **Top-down level** (pointing straight down): pitch and roll together. One tap when both are within the tolerance. No separate tap for each axis: the inner circle meeting the ring is one event on screen, so it is one event in the hand.
- **Changing between the two:** the rule is unchanged, false to true gives a tap. Going from a level horizon to a level top-down view gives none, because level never ended.

## 3. Which feedback

**Keep `.alignment`, the same for the horizon and the top-down level.** Rename the token from `NopeHaptic.levelFlat` to `NopeHaptic.levelReached`, because "flat" now also names the top-down level.

| Candidate | Verdict | Reason |
| --- | --- | --- |
| `.alignment` | Use | Its documented meaning is an item coming into alignment, which is this event. Documented as playing on iOS. No other event in the app uses it, so it cannot be mistaken for another |
| `.levelChange` | No | Despite the name, it means discrete pressure levels, and Apple documents it as playing only on macOS |
| `.selection` | No | Means a value changing. The app uses it for the lens, the drive mode and Manual Controls |
| `.impact(weight: .light)` | No | The app's "photo saved" and "countdown second" tap. A level tap that feels like a saved photo misleads someone not looking at the screen |
| `.impact` | No | The shutter press |
| `.success` | No | All Auto. A notification pattern is also too long for an event that can repeat |
| `.impact(flexibility: .rigid, intensity: 0.6)` | Fallback | A short, crisp tap unlike the others in the app. Use it only if the device check finds `.alignment` cannot be felt on iPhone (section 10, check 1). Built and unit-tested as `NopeHaptic.LevelTap.rigidFallback`; switching is the one line `NopeHaptic.levelTap` in `DesignTokens.swift` (owner decision, 2026-11-18) |

The same feedback for both levels: one meaning, one feel. Two feels would need to be learned, and the screen already shows which level is in use.

Each haptic in the design system is paired with something seen and something VoiceOver says. Seen: the bar turns solid and thicker, or the inner circle fills (existing). Said: section 7.

## 4. When it must not fire

New, except where marked. A tap that is held back is dropped, never played later.

| Situation | Rule | Reason |
| --- | --- | --- |
| A photo is being captured (`captureStatus == .capturing`), including a bracket and a long exposure | No tap | The Taptic Engine moves the phone. Assumed able to blur an exposure; not measured |
| Burst running, self-timer counting down (`drive.isBusy`) | No tap | Vibration between frames; and during a countdown the tap would be mistaken for a countdown second |
| Interval series in progress, running or paused (`manual.intervalProgress != nil`) | No tap | The phone is usually on a support; a tap can shift the framing between frames |
| Astro running (`astro.isRunning`) | No tap | Long exposures on a support |
| The camera is not running (`sessionStatus` is not `.running`: paused, interrupted, starting) | No tap | The picture is not live, so there is nothing to level |
| A sheet, popover or full-screen cover is over the camera (Settings, Formats, What's in This Photo, Compare, Presets) | No tap | The level is not what the person is looking at |
| The app is not active (`scenePhase` is not `.active`) | No tap | Same |
| Level is off | No tap, no motion updates | Existing: the overlay and its readings do not exist |
| Device without motion sensors | No level, no tap | Existing |
| Clean view | The level stays, and so does the tap | Existing: guides stay in clean view |
| Q open | The tap stays | The picture is still visible, and Level is switched there. The first-reading rule means switching Level on gives no tap |
| Magnify, Night Mode, Red Viewfinder | The tap stays | They change what is drawn, not the event |

The app has no silent or discreet mode, so there is nothing else to follow. The shutter sound follows the system; the haptics follow the system haptics setting (section 5).

After a held-back period ends (the exposure finishes, the sheet closes), the next tap needs a new entry: if the device is already level, nothing plays.

Where the rule lives: `NopeCore`, as a small pure type beside `LevelTracker` that takes the level state, the time and whether taps are held back, and answers whether to tap. `NopeUI` only plays it. This keeps the rule under the 100% coverage gate and out of the view.

## 5. Settings

**No new switch.** Recommended for these reasons:

- Level is already a switch, off by default. Whoever turns it on has asked for the level's feedback.
- None of the app's other haptics has a switch.
- iOS has the switch: Settings › Sounds & Haptics › System Haptics. Feedback played through `sensoryFeedback` is expected to follow it (device check 3). The app must not play this tap by any means that goes around that setting.
- The accepted Settings structure removes rows rather than adding them, and release 1.0.0 adds no setting that is not required.

**Low Power Mode:** the app adds no rule of its own. The system decides whether haptics play. The tap costs no extra sensor work: the motion updates already run for the bar.

**Wording changes** (existing strings, reworded; drafts for the Honesty review):

| Where | Now | Proposed |
| --- | --- | --- |
| Settings › Viewfinder Overlays › Level, explanation | "A horizon bar, or a top-down level when you point straight down. Uses the motion sensors only while it shows." | "A horizon bar, or a top-down level when you point straight down. On iPhone, you feel a tap when it's level. Uses the motion sensors only while it shows." |
| Settings › Accessibility › Feedback, first row | "On iPhone, a tap you can feel confirms each press of the shutter and each saved photo." | "On iPhone, a tap you can feel confirms each press of the shutter and each saved photo, and marks the moment the level is level." |
| Settings search, Level keywords | "horizon, straight" | "horizon, straight, tap, haptic, vibration" |

"On iPhone" is said because iPad gives no tap; the sentence must not promise one there.

**If a switch is wanted anyway** (decision 3), it is a new setting and belongs in release 1.1.0:

- Place: Settings › Screen › Viewfinder Overlays, in Guides, directly under Level. Always shown, so no row appears or disappears when Level changes; it has no effect while Level is off.
- Name: "Tap When Level". Explanation: "On iPhone, you feel a tap when the level is level."
- Default: on. Saved with presets, reset by Factory Defaults, found by search. No Q tile.

## 6. Devices

| Device | Behavior |
| --- | --- |
| iPhone | As above |
| iPhone Duo, outer display | As iPhone |
| iPhone Duo, inner display | As iPhone: the level and the tap do not depend on the layout. Half-open: the level shows what the motion sensors report, and the tap follows the level shown. No special rule. Which half holds the sensors, and so what "level" means half-open, is a device check (section 10, check 6) |
| iPad | No tap: no Taptic Engine. The app adds no sound or flash in its place. The bar and the VoiceOver sentence (section 7) carry the event. An Apple Pencil or trackpad that plays system feedback may play this one; the app neither relies on it nor prevents it |
| Lock Screen camera | The same camera screen, so the same rule. Whether haptics play in the capture extension is a device check (check 5) |
| Apple Watch | No tap on the watch. See below |

**Apple Watch:** not recommended.

- The remote is for a phone that is set down or on a support. A supported phone does not change its tilt, and while someone adjusts it they are holding the phone, which taps.
- The watch does not receive the phone's level. Sending it means streaming motion state between the devices for as long as the level shows, which is a new capability, more radio use, and a delay that makes "the moment it becomes level" late.
- The device's attitude is used on screen only (issue 40). Sending it to another device needs its own review.

If it is wanted later, it is a release 1.1.0 feature with its own design.

## 7. Accessibility

- **VoiceOver, new:** with VoiceOver on, the app says "Level" once at each event that gives a tap (same rules: once per entry, 1 second apart, held back in the same situations). For the top-down level it says "Pointing straight down, level". Both strings exist. The announcement is queued at low priority, so it never interrupts a capture result, a countdown second or a warning.
- Nothing is announced on leaving level, and the tilt is not announced as it changes. The level's value on request is unchanged. This keeps issue 40's rule: no continuous speech.
- Why add speech: the design system pairs each haptic with an announcement, and this one has none today. On iPad the announcement is the only signal for someone who cannot see the bar.
- The tap and the announcement come together on iPhone. VoiceOver's own haptics are separate and unchanged.
- **Hearing:** nothing is sound only. **Deaf-blind use with a braille display:** the announcement reaches the display as other announcements do.
- **Reduce Motion:** no effect; the tap is not animation. The bar's change of thickness is not animated today and stays so.
- **Differentiate Without Color:** the level state is thickness and fill, not color. Unchanged.
- **Largest text sizes:** the level is drawn in the picture in every layout, so the rule is the same in the scrolling layout.
- **Switch Control, Voice Control, Full Keyboard Access:** nothing to operate; the level takes no input.
- **Cognitive:** one meaning for one feel. No new mode, no new setting.

## 8. Night Mode

- Night Mode and Red Viewfinder change colors only. The tap and the announcement are the same.
- In the dark the bar is dim by design, so the tap is the main cue when setting up a tripod. This is the case the tap serves best.
- Once Astro is running, no tap (section 4). Before the series starts, while framing, the tap plays.
- The tap makes a faint sound on a hard surface. No rule is added for it; the System Haptics setting turns it off.

## 9. What changes, in one table

| # | Change | Kind | Files |
| --- | --- | --- | --- |
| 1 | Device check that the existing tap can be felt; fallback feedback if not | Verification, possible fix | `DesignTokens.swift`, `docs/TESTING.md` |
| 2 | Level explanation and Accessibility page say the level gives a tap; search keywords | Rewording | `OverlaySettingsView.swift`, `AccessibilitySettingsView.swift`, `SettingsSearch.swift`, string catalogs |
| 3 | No tap while capturing, in a burst, countdown, interval series or Astro, with the camera not running, under a sheet, or inactive | Fix | New rule type in `NopeCore/Level.swift`; `ViewfinderOverlays.swift` |
| 4 | At least 1 second between taps; no tap for the first reading | Fix | Same |
| 5 | VoiceOver says "Level" at each tap | Accessibility fix (pairing rule) | `ViewfinderOverlays.swift` |
| 6 | Token renamed `levelReached`; event named "Level becomes level" | Naming | `DesignTokens.swift`, `DesignTokensTests.swift`, [tokens.md](tokens.md), [design-system.html](design-system.html) |
| 7 | Documents | Docs | [ACCESSIBILITY.md](ACCESSIBILITY.md) (Announcements), [BUILD-SPEC.md](BUILD-SPEC.md) (strings, Honesty review), `docs/ARCHITECTURE.md`, `docs/TESTING.md`, `CHANGELOG.md`, the generated API pages |

Not changed: the tolerances, the reading rate, the drawing, the Level switch and its default, presets, the watch app, Siri and Shortcuts.

## 10. Tests

### Unit tests (`NopeCore`, full line and branch coverage)

The rule type takes its time from the caller, so tests use fixed times.

1. Not level, then level: one tap.
2. Level held for many readings: no further tap.
3. First reading already level: no tap. Leaving and returning after 1 second: tap.
4. Leaving (above 1.5°) and returning (at or under 1.0°) after 1.0 second: tap. After 0.9 second: no tap, and no late tap on later readings while level is held.
5. Moving between 1.0° and 1.5° without passing 1.5°: no tap (hysteresis).
6. Held back (each cause in section 4 that the rule type sees): entering level gives no tap; when the cause ends while still level, no tap; leaving and entering again gives a tap.
7. Top-down: pitch within tolerance and roll outside gives no tap; both within gives one tap, not two.
8. Horizon level to top-down level while level throughout: no tap. Not level in one, level in the other: one tap.
9. Each of the four horizon positions gives a tap on entry.
10. The readings ending (Level switched off) resets the rule: the next first reading gives no tap.
11. `CameraModel`: the "taps held back" value is true for capturing, a burst, a countdown, an interval series (running and paused), Astro, and each session status other than running; false otherwise.

### Token test (`DesignTokensTests.hapticsMatchTheDesign`)

`NopeHaptic.levelReached == .alignment` (or the fallback, if check 1 chooses it).

### UI tests

A haptic cannot be observed in a UI test, so these cover what can be: the path runs, the words are right, and the audits pass.

1. `SimulatedGravity` gains a reading sequence, tilted then level (`-NopeSimulatedGravity becomesLevel`). The Level element's value changes from "Tilted 5° clockwise" to "Level". Accessibility audit in both states.
2. The same with `flat`: "Pointing down, not level" to "Pointing straight down, level".
3. The same sequence with a sheet open over the camera and during a simulated capture: the app does not crash and the value still updates when the picture is visible again.
4. Settings › Viewfinder Overlays: the Level explanation shows the new sentence; audit at the default size, the largest accessibility size, right to left and in Night Mode.
5. Settings › Accessibility: the Feedback row shows the new sentence; the same four audits.
6. Settings search: "haptic" and "tap" find Level.
7. iPad and the iPhone Duo inner display: tests 1 and 4 on those shards.

### Device checks (`docs/TESTING.md`, "Viewfinder overlays on a device")

1. iPhone: the tap can be felt in the hand, in portrait and on its side, with and without a case, and cannot be mistaken for the saved-photo tap. If it cannot be felt, switch to the fallback in section 3 and repeat.
2. One tap per entry; none while held; none within 1 second of the last; none when Level is switched on while level.
3. With System Haptics off in iOS Settings: no tap. With Low Power Mode on: record what the system does.
4. No tap during a 1 second or longer exposure, a bracket, a burst, a countdown, an interval series or Astro; a photo taken as the device comes level is as sharp as one taken with Level off.
5. Lock Screen camera: record whether the tap plays.
6. iPhone Duo: outer display, inner display and half-open; record what the level reads half-open.
7. iPad: no tap and no error; with VoiceOver on, "Level" is spoken.
8. VoiceOver on iPhone: "Level" is spoken once per entry and does not cut off "Saved." or a countdown second.
9. Instruments: no motion updates while Level is off (existing check), and none added by this change.

## 11. Decisions for the owner

Each with the recommendation.

1. **Release.** Recommended: **1.0.0** for changes 1 to 7 of section 9. The tap is an existing feature (issue 40, shipped in 0.2.0). Making it known, checking that it can be felt, keeping it out of exposures and adding the missing VoiceOver sentence are fixes and interface work on an existing feature, which is the 1.0.0 scope. Two items would be new features and go to **1.1.0** if wanted: a switch (decision 3) and a tap on Apple Watch (decision 7).
2. **Feedback.** Recommended: keep `.alignment`, the same for the horizon and the top-down level; use the rigid impact only if the device check finds `.alignment` cannot be felt on iPhone.
3. **A switch for the tap.** Recommended: none. Level is already a switch and iOS has System Haptics. If one is wanted: "Tap When Level", under Level in Viewfinder Overlays, on by default, in 1.1.0.
4. **Wording.** Recommended: accept the two reworded sentences in section 5 as drafts for the Honesty review, and the added search keywords.
5. **When the tap is held back.** Recommended: accept the table in section 4, including no tap during a self-timer countdown and for the whole of an interval series.
6. **Timing.** Recommended: keep 1.0° to enter and 1.5° to leave; add 1 second between taps; no tap for the first reading; no hold time before the tap.
7. **Apple Watch.** Recommended: no tap on the watch.
8. **iPad.** Recommended: no substitute for the tap (no sound, no flash). The bar and, with VoiceOver, the spoken "Level" carry it.
9. **VoiceOver.** Recommended: say "Level" once at each tap, at low priority, as well as the tap; nothing on leaving level.
10. **Token name.** Recommended: rename `levelFlat` to `levelReached`.
