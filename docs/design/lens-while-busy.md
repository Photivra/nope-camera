# Lens controls while the camera is busy

Status: proposed 2026-11-18. Not accepted yet; the decisions are in section 8. No drawing changes: the disabled state of every button type is already in [design-system.html](design-system.html) and [tokens.md](tokens.md) ("Button types").

The problem (issue 96): the lens can be changed while a photo or a series is being taken. The model gets one rule, `CameraModel.canChangeLens`, false while a photo is taken or saved, during a countdown, a burst, a bracket, an interval series, an Astro run and while the compare view is open. This file says what the interface does while that rule is false.

Sources: issue 96, the code as of release branch 1.0.0 (`Sources/NopeUI/CameraReadyView.swift`, `LensRow.swift`, `FocusAids.swift`, `DriveStrip.swift`, `NopeButtonStyles.swift`, `Sources/NopeCore/CameraModel+Shortcuts.swift`, `App/NopeApp/Intents/ShortcutDialog.swift`), [tokens.md](tokens.md), [ACCESSIBILITY.md](ACCESSIBILITY.md).

Evidence note: everything below about the code was read from the code. Nothing here was tried on a device; section 7 lists the device checks.

## 1. The controls

| Control | Where | Layouts |
| --- | --- | --- |
| Lens buttons (`LensButtons`) | Lens row; top of the control column | Stacked, sideways iPhone, column (iPad, iPhone Duo inner display, wide windows) |
| Lens rows (`LensRows`), Front included | Scrolling layout | Accessibility text sizes |
| Switch Camera (`CameraFlipButton`) | End of the lens row; bottom of the column | All but the scrolling layout |
| "Switch to Ultra Wide" (`CloseUpSuggestion`) | The close-up hint on the picture | All |

In clean view the lens controls are already hidden; that does not change. The compare view is a full-screen cover, so no lens control can be reached while it is open; the rule still applies underneath.

## 2. The rule: dimmed, never hidden

While `canChangeLens` is false, every control in section 1 is **disabled and stays where it is**. Nothing is hidden or moved, in any state.

- **The lens in use stays full strength.** The selected lens keeps its white fill at full opacity, as the selected drive word does while the drive is busy (`DriveStrip`). It shows which lens the photo or series is using. Pressing it does nothing, as today.
- **The other lenses and Switch Camera** are disabled: `NopeMotion.disabledOpacity` (40%), the existing disabled state.
- **The close-up hint stays.** Its sentence and Dismiss are unchanged; only "Switch to Ultra Wide" is disabled. The hint is not removed and shown again, so VoiceOver does not repeat it.
- **Nothing is announced** when the controls become unavailable or available again. It would be spoken on every photo.

Why not hidden: the lens row sets the height of the control band and the column, so hiding it moves the drive strip, Manual Controls or the picture; a control that vanishes takes VoiceOver, Switch Control and keyboard focus with it; and the lens in use would no longer be shown during a series. The dials and readouts are hidden during a series because they give the picture to the running mode's card. The lens row gives nothing back by leaving.

### When the dimming is drawn

The controls are disabled at the same moment in every state. Only the drawing differs, so that a normal photo does not make the lens row blink.

| | State | Disabled | Drawn dimmed |
| --- | --- | --- | --- |
| a | One photo in flight | At once | Only if the photo is still being taken or saved after 0.5 s |
| b | Long exposure, saving | At once | After 0.5 s, until the photo is saved |
| c | Countdown | At once | At once |
| d | Burst | At once | At once |
| d | Bracket | At once | After 0.5 s (it is one capture) |
| e | Interval series, Astro run | At once | At once, for the whole run, the waits between frames included |
| f | Compare view | At once | Covered; not seen |

Countdown, burst, interval and Astro already change the shutter to Stop and dim the other drive words in the same frame, so the lens controls change with them. The change uses `NopeMotion.fade` (0.2 s, opacity only), both ways. The 0.5 s delay is new: add it to `NopeMotion` and [tokens.md](tokens.md) when this is built. A suggested build: `.disabled` follows `canChangeLens` directly, and the group animates that change with `fade` delayed by 0.5 s when the cause is a photo; a change back before the delay ends draws nothing.

## 3. A press on a dimmed control

**Nothing.** No hint, no sound, no haptic.

- The screen already says why: the Stop square on the shutter, the running mode's card, the countdown number, or "Saving…" on Last Photo.
- A haptic moves the device during an exposure.
- A hint over the picture during a series covers what is being photographed, and would have to leave on a timer, which the app does not do.
- No new string is needed.

## 4. Accessibility

| | Behavior |
| --- | --- |
| VoiceOver | Disabled controls read with the system's "dimmed": "Telephoto, 5×, dimmed, button". The lens in use reads as today: "Wide, 1×, selected, button". Focus stays on a control that becomes dimmed. Hint on dimmed lenses, Switch Camera and "Switch to Ultra Wide" during a countdown, burst, interval series or Astro run: the existing sentence "The camera is taking photos. Try again when it's done." (already used for presets, already translated). No hint for a single photo or a bracket. A "No RAW" lens keeps its own hint when not dimmed |
| Large Content Viewer | Unchanged: a long press on a dimmed lens button still shows its label. Device check |
| Voice Control | Names are unchanged. "Tap Telephoto" on a dimmed button does nothing, as for any disabled button |
| Switch Control, Full Keyboard Access | Dimmed controls are skipped by the system; the lens in use stays in the group, so the group and the scanning order stay. Device check |
| Largest text sizes | Scrolling layout: the lens rows stay in the list, dimmed, the row in use full strength. No row is added or removed, so nothing moves under a finger or under focus |
| Column, iPad | The same rule for the vertical lens group and for Switch Camera at the bottom of the column |
| iPhone Duo | The same on both displays. Folding or unfolding during a series keeps the dimmed state |
| Night mode | The dimmed controls are the red outline at 40%; the lens in use stays filled red. No other color is used |
| Increase Contrast | Dimmed controls keep their outline, at 40% |
| Reduce Motion | The same 0.2 s fade; it is opacity only |
| State not by color alone | Dimmed is opacity plus the disabled trait; the reason is in words on the shutter, the card or Last Photo |

## 5. Siri and Shortcuts

After the fix, a request never changes the lens while `canChangeLens` is false.

| Request | Busy answer today | Change |
| --- | --- | --- |
| Switch Lens | "nope. is already taking a photo." | New: **"nope. is busy. The lens didn't change."** True in every busy state, the compare view included, and it says what happened to the request. One new string in the launch languages |
| Take Photo or Take Bracket with a lens | "nope. is already taking a photo." | No wording change. The lens is no longer switched first, so the answer is now true: nothing changed and no extra photo is taken |
| Set Photo Size, Apply Preset | Unchanged | None |

The Apple Watch cannot change the lens; nothing changes there.

## 6. Not in this change

- The lens controls while Astro is on but idle, and a lens change turning a bracket off: unchanged.
- The pinch between lenses (`pinch-lens.md` on branch `design-pinch-lens`, proposed separately) must use the same `canChangeLens` rule if it is built.

## 7. Tests

Unit (`NopeCoreTests`), with the gated simulated backend:

1. `canChangeLens` is false in each state: capturing, saving, countdown, burst, bracket, interval series (during a frame and during a wait), Astro run, compare view; true again after each ends, is stopped or fails.
2. `selectLens` in each of those states changes nothing: the same lens, no session restart, the photo or series completes with one lens.
3. Shortcuts: Switch Lens returns busy in each state; Take Photo and Take Bracket with a lens return busy without switching; a preset with a lens is refused.

UI (`NopeAppUITests`), iPhone, iPad and iPhone Duo shards:

4. During a self-timer countdown: every lens button and Switch Camera exists; the lens in use is enabled and selected; the others and Switch Camera are not enabled; after Cancel Timer all are enabled. The lens row's frame is the same before, during and after.
5. The same during an interval series, at the default text size and at the largest (lens rows), in night mode and right to left, each with `performAccessibilityAudit()`.
6. The close-up hint during a countdown: the sentence and Dismiss are there, "Switch to Ultra Wide" is not enabled.
7. A press on a dimmed lens during the countdown: the selected lens is unchanged and the photo is taken.
8. Shortcut: Switch Lens during an interval series gives the new answer and the lens is unchanged.

Device checks (`docs/TESTING.md`):

1. A 1/60 s photo: the lens row does not blink. A 10 s exposure: the row dims after about half a second and returns when the photo is saved.
2. A lens press during a long exposure, a burst and an interval series: nothing changes, and the photo or series ends normally.
3. VoiceOver reads "dimmed" and the hint; focus stays put. Switch Control and Full Keyboard Access skip the dimmed controls. The Large Content Viewer shows a dimmed lens.
4. Night mode in the dark: the dimmed outline is still visible, and clearly weaker than the lens in use.

## 8. Decisions for the owner

Each with the recommendation.

1. **Dimmed or hidden.** Recommended: dimmed and in place, in every state, for the lens buttons, the lens rows, Switch Camera and "Switch to Ultra Wide". Never hidden.
2. **The lens in use.** Recommended: it stays full strength and selected while the others are dimmed, as the drive strip does.
3. **A single photo.** Recommended: disabled at once, drawn dimmed only if the photo is still being taken or saved after 0.5 s, so a normal photo does not blink the row. Countdown, burst, interval and Astro dim at once.
4. **A press on a dimmed control.** Recommended: nothing. No hint, sound or haptic.
5. **The close-up hint.** Recommended: it stays, with only its "Switch to Ultra Wide" button dimmed.
6. **VoiceOver hint.** Recommended: reuse "The camera is taking photos. Try again when it's done." on dimmed lens controls during a countdown, burst, interval series or Astro run; no hint for a single photo. Alternative: no hint, "dimmed" only.
7. **Siri answer for Switch Lens.** Recommended: the new sentence "nope. is busy. The lens didn't change." Alternative: keep "nope. is already taking a photo." and add no string.
8. **Take Photo and Take Bracket with a lens.** Recommended: no wording change.
