# Pinch to switch lenses

Design version: 1.0.0, direction B · Reach. Proposed 2026-11-18. Owner request: pinching on the picture switches between the device's lenses, with a setting that controls what a pinch does; the default is to switch lenses. This document becomes part of the plan when the decisions in section 12 are made. Nothing is drawn yet; the figures to draw are listed in section 13. Tokens are in [tokens.md](tokens.md). The wording is a draft until the Honesty review.

Contents: 1. Summary · 2. What the code does today · 3. Pinch behavior · 4. What is shown and felt · 5. Where a pinch does nothing · 6. Other touches and Magnify · 7. The setting · 8. Devices · 9. Accessibility · 10. Strings · 11. Build notes and tests · 12. Decisions for the owner · 13. When this is accepted

## 1. Summary

| | Today | Proposed |
| --- | --- | --- |
| Pinch on the picture | Nothing | Moves to the next rear lens: spread two fingers for the next longer lens, pinch them together for the next wider one |
| One pinch | – | One lens for a short pinch; a longer pinch passes further lenses, one step at a time |
| Shown during a pinch | – | The lens's existing label ("0.5×", "1×", "5×") with its name, on the picture; the lens row follows |
| Felt | A tick when the lens changes | The same tick, once for each lens step |
| The picture | – | Never enlarged, cropped or animated between lenses. It changes when the next camera has started, as it does after a lens button |
| Setting | – | Settings › Camera › Pinch: Switch Lenses (default) or Off |
| Lens buttons, Siri, Shortcuts, keyboard | | Unchanged. They remain the way to choose a lens without a gesture |

Principles kept:

- **No digital zoom.** The decision in issue 1 stands. Every lens is one of the device's cameras at zoom 1.0. A pinch chooses between them and does nothing else. No text says "zoom"; the gesture is described as switching or changing lenses.
- **A gesture is never the only way** (ACCESSIBILITY.md). The lens buttons, the lens rows at the largest text sizes, Switch Lens in Siri and Shortcuts and the arrow keys do the same.
- **No surprise.** A pinch does nothing while a photo is being taken, and nothing where a lens change would end a mode.

## 2. What the code does today

Read in the code on 2026-11-18. Nothing here was measured on a device for this document.

| Fact | Where |
| --- | --- |
| The lenses are the device's physical cameras, ordered rear ultra wide, wide, telephoto by magnification, then front | `LensCatalog` in `Sources/NopeCapture` |
| A lens's label is its magnification compared with the rear wide camera, such as "0.5×" or "5×", computed from the field of view and approximate. The front camera has none | `Lens.magnification`, `LensButton.title` |
| A lens without Bayer RAW stays selectable and says "No RAW"; the Processed marker appears on the camera | `LensButton`, BUILD-SPEC.md 3.2 |
| Choosing a lens sets the selected lens at once and restarts the camera for it. How long the restart takes is not recorded | `CameraModel.selectLens`, `startSession` |
| `selectLens` itself does not refuse while a photo is being taken or a series runs | `CameraModel.selectLens` |
| A lens change plays `NopeHaptic.lensChanged` (`.selection`) and VoiceOver speaks the lens | `LensButtons`, ACCESSIBILITY.md "Announcements" |
| The picture has one gesture today: a tap focuses and exposes, a press of 0.5 s locks, a vertical swipe of 60 pt or more toggles clean view. A movement of more than 10 pt is no longer a tap or hold | `ViewfinderTouches` in `FocusAids.swift` |
| In the scrolling layout (accessibility text sizes) only the tap is on | `ViewfinderTouches.allowsDrags` |
| Magnify draws the viewfinder 3 times larger around the focus point. It is a switch in Q with a pill, and changes neither the photo nor the camera | `FocusMagnifier`, `CameraModel.isMagnifying`, `QuickControls.magnifier` |
| A lens change leaves Magnify as it is, and clears a tapped focus point and the lock | `CameraModel.selectLens`, ARCHITECTURE.md |
| The close-up hint suggests the ultra wide lens with a button; the app never switches lenses itself | `CameraModel.closeUpLens`, `FocusAids.swift` |
| With Astro on, a lens Astro can't use turns Astro off | `CameraModel.astroLensDidChange` |
| Compare has its own pinch, on its own screen, which enlarges the two saved pictures | `ComparisonScreen.pinchGesture` |
| The Apple Watch remote has no lens choice | watch.html |

The request named a level-haptic design on a branch `design-level-haptic`. No such branch was found, so the feedback here follows the haptics table in tokens.md as it stands.

## 3. Pinch behavior

### 3.1 Direction and order

- Spreading two fingers moves to the next **longer** lens (toward "5×"). Pinching them together moves to the next **wider** lens (toward "0.5×"). This is the direction the system camera uses, and it matches the order of the lens row.
- The order is the rear lenses of the lens row. A pinch stops at the first and at the last lens; it does not wrap around.
- A pinch never crosses between the rear and front cameras. That stays with Switch Camera.
- A lens without RAW is part of the order, as it is in the lens row (decision 4).

### 3.2 Steps

A lens is a separate camera, not a point on a scale, so the steps are equal and do not follow the magnifications. With lenses at 0.5×, 1× and 5×, a scale that followed the numbers would need a far larger movement for the second step than for the first.

| Value | Starting figure | Meaning |
| --- | --- | --- |
| First step | Scale 1.25 spreading, 0.80 pinching | The fingers must move a quarter further apart, or a fifth closer, before anything happens |
| Each further step in the same pinch | A further factor of 1.35 (0.74 pinching) | Scale 1.69 is the second lens, 2.28 the third |
| Going back within the same pinch | The scale must return 10% inside the threshold just crossed | A hand resting at a threshold does not flip between two lenses |
| Ignored | Any pinch that ends before the first step | The picture and the lens stay as they were |

- A short pinch moves one lens. A long pinch passes further lenses one at a time, each with its own tick and label, so three lenses can be crossed in one movement and the person always knows where they are.
- There is nothing to snap: the position is always a whole lens. Lifting the fingers keeps the lens the label shows.
- The figures are starting values. They are assumptions until tried on a small iPhone, a large iPhone and an iPad, with one hand and with two (AGENTS.md, rule 1).

### 3.3 When the camera switches

Restarting the camera for a lens takes time that has not been measured, so a long pinch must not restart it for every lens passed.

- Each step sets the **target** lens at once: the label, the lens row and the tick follow the fingers.
- The camera is asked to switch when the fingers lift, or when the target has not changed for 0.25 s, whichever comes first. Only the latest target is sent; a switch already running finishes first.
- Until the camera has restarted, the picture is that of the previous lens, as it is today for a moment after a lens button. Nothing is drawn enlarged or reduced in between.
- If the pinch returns to the lens it started on, nothing is sent.

## 4. What is shown and felt

- **The label.** While a pinch is past its first step, the target lens's label is shown in the middle of the picture: the same text as its button ("0.5×", "1×", "5×", from `Lens.magnification`) with the lens's name under it ("Telephoto"), and "No RAW" where its button says so. It sits on `NopeMaterial.backing` with `NopeRadius.large`, in the lens font at the dial-value size, and stays upright when the phone is held sideways. The label is the multiplier the app already uses; no focal length is added.
- **Appearing and leaving.** `NopeMotion.fade` in at the first step; out 0.8 s after the fingers lift. The label repeats what the lens row shows, so nothing is lost when it goes. In clean view the lens row is hidden; there the label is the confirmation, and the Viewfinder's VoiceOver value still carries the lens.
- **At an end.** Pushing further at the first or last lens changes nothing: the label stays, and no tick is played, because nothing changed.
- **The lens row** moves its selection with `NopeMotion.select`, as after a tap.
- **Haptic.** `NopeHaptic.lensChanged` (`.selection`) once for each step, the existing lens rule. No new haptic is added. The level's `.alignment` is a different feedback and is not used here.
- **The picture.** No scale animation, no crossfade between lenses and no blur. A picture that grew under the fingers would look like digital zoom.
- **Announcement.** The existing sentence for a lens change, once, when the camera is asked to switch.

## 5. Where a pinch does nothing

In each case the pinch is ignored completely: no label, no tick, no message. The lens buttons keep whatever behavior they have there today.

| State | Pinch | Why |
| --- | --- | --- |
| A photo is being taken or saved | Nothing | A lens change restarts the camera |
| A self-timer countdown, a burst, a bracket, an interval series or an Astro run is going | Nothing | The same; a series must not change lens by a stray touch |
| Astro is on, idle | Nothing | A lens Astro can't use would turn Astro off, and Astro is used in the dark by touch (decision 6) |
| The camera is starting, paused, too hot or unavailable | Nothing | There is no camera to switch |
| The front camera is selected | Nothing | It is one lens; Switch Camera returns to the rear |
| The device has one rear lens | Nothing | Section 8 |
| Q, a dial, the exposure dial, a mode card's menu or a sheet is open | Nothing | The touch belongs to what is open; a tap on the picture closes Q, as today |
| Compare is open | Its own pinch | Compare is its own screen over the camera |
| The scrolling layout (accessibility text sizes) | Nothing | The picture is inside a scrolling page, and the lens rows are full width there |
| Pinch is set to Off | Nothing | Section 7 |

These modes are not blocked for lenses in general:

- **Night Mode** (outside Astro): the pinch works; the label is red on black through `NightModeStyle`.
- **Manual Controls on, no dial open:** the pinch works. Manual values are moved into the new lens's range and reported as today.
- **Burst, Timer, Interval or bracketing chosen but not running:** the pinch works.
- **Clean view:** the pinch works (decision 7).
- **Close-Up and Far Focus:** unchanged by a lens change today; unchanged by a pinch.

Found while checking: `CameraModel.selectLens` has no check of its own for a photo being taken or a series running. Whether the lens buttons can be pressed in those moments, and what happens, should be checked on a device and filed separately. The pinch must not rely on it: its own availability check is specified in section 11.

## 6. Other touches and Magnify

### 6.1 Tap, hold and swipe

- The pinch is added beside the existing gesture, not in place of it.
- When a second finger lands, the pending hold is cancelled, and the touch ends without a tap, a lock or a clean-view swipe. One movement is one thing.
- A pinch whose fingers do not move apart or together (two fingers resting, or sliding together) does nothing.
- The focus square's lock button and every control drawn on the picture keep their own touches; a pinch must start on the picture itself.
- A pinch changes the lens, so a tapped focus point and an AE/AF lock are cleared, as after a lens button.

### 6.2 Accidental pinches

- The first step needs a quarter more or a fifth less distance between the fingers; a brush of a second finger does not reach it.
- A pinch is ignored in every state of section 5.
- A wrong step is undone by the opposite pinch or one tap on the lens row; the label and the tick say that it happened.
- People who do not want it turn it off (section 7).

### 6.3 Close-up hint

The app still never switches lenses by itself. The hint keeps its button. A pinch to the ultra wide lens while the hint is shown has the same effect as the button and removes the hint the same way.

### 6.4 Magnify

Magnify is the existing way to check focus: a switch in Q, a pill with Turn Off Magnifier, a Settings search entry, and a place in the Astro tips. It enlarges the viewfinder 3 times around the focus point; the photo is unchanged.

**What a pinch does while Magnify is on.** Four possibilities:

| | Pinch while Magnify is on | For | Against |
| --- | --- | --- | --- |
| A | Switches lenses; Magnify stays on | One rule: a pinch does what the lens buttons do, in every state. The lens buttons already work this way | The enlarged picture changes to another lens, still enlarged |
| B | Nothing | No change of lens while checking focus | The gesture seems broken in one state, with nothing to explain it |
| C | Changes the magnifier's size | Feels natural | A picture that grows under the fingers is what digital zoom looks like. It is also a new capability: the magnifier has one size today |
| D | Switches lenses and turns Magnify off | The new lens is seen whole | A side effect the lens buttons do not have; focus checking is interrupted |

Recommended: **A**. The pill stays visible and still says Magnify, so the state is clear. A lens change clears the tapped focus point, so the enlargement returns to the center, as it does today after a lens button (decision 8).

**Whether "Check Focus" belongs as a pinch option.** A pinch that enlarges only the viewfinder would be Magnify under a second name: the same enlargement, the same promise that the photo is unchanged, but with a different way in, no pill of its own and a different word. It is not proposed. If a pinch for checking focus is wanted later, it should be a third value of the same setting, named **Magnify**, that turns the existing Magnify on (spread) and off (pinch): one state, one pill, one name (decision 9).

**Magnify itself** does not change: its name, its tile and pill, Turn Off Magnifier, its Settings search entry and the Astro tips stay as they are. Its search keywords already include "zoom", which finds it for people who use that word; the result's own text says the photo is not changed.

### 6.5 Manual Controls dials

While a dial is open, a pinch does nothing (section 5): a hand turning a dial often rests a second finger on the picture. With Manual Controls on and no dial open, the pinch works.

## 7. The setting

### 7.1 Name, place and control

- **Place:** Settings › Camera, after Focus on Faces. The Camera group is how the camera behaves; Screen is what the screen shows. Path from the camera on iPhone: Q › Settings › Pinch › value, 4 taps, no new level.
- **Name:** **Pinch**. The value names what it does.
- **Control:** a picker that opens as a menu on its row, as the other pickers do.
- **Values:** **Switch Lenses** (default) and **Off**.
- **Shown** only on a device with two or more rear lenses, as Photo Size and Live Activity are shown only where the device offers them. No row appears or disappears as another setting changes.
- **Stored** in `NopeSettings` and in presets. Factory Defaults returns it to Switch Lenses.
- Not in Q: it is set once.

Two values could be a switch ("Pinch to Switch Lenses"). A picker is proposed because the request was for a setting that says what a pinch does, and a third value (6.4) can then be added without replacing the control. The switch is the alternative in decision 2.

### 7.2 Wording

US English. Drafts for the Honesty review; none ships until reviewed.

| # | Where | Text |
| --- | --- | --- |
| 1 | Row title | Pinch |
| 2 | Values | Switch Lenses · Off |
| 3 | Explanation under the row | Spread two fingers on the picture for the next longer lens, or pinch for the next wider one. nope. never enlarges or crops the picture. |
| 4 | Scope note, a line of its own under the explanation | Used only on the rear cameras. Not used in Astro, while photos are being taken, or at the largest text sizes. |
| 5 | Settings search keywords (not shown) | zoom, lens, lenses, gesture, two fingers |
| 6 | Accessibility page, one added fact | Pinching to switch lenses is optional. The lens buttons do the same. |
| 7 | Honesty page | No change. "No digital zoom" is already stated; a pinch does not alter it |

What the sentences rest on:

- "the next longer lens", "the next wider one": the lens row's order by magnification. "Longer" and "wider" describe lenses, not a zoom range.
- "never enlarges or crops the picture": the capture stays at zoom 1.0 and the viewfinder is not scaled by a pinch. The sentence is about the pinch; Magnify enlarges the viewfinder, and says so itself.
- The scope note follows the pattern of the Fast Shutter note ("Used only while…"): "used", because the choice is always stored and can always be changed.
- "zoom" appears only as a search keyword, so that people who look for it find the setting and read what it does. It is not in any visible text.

## 8. Devices

| Device | Pinch | Settings row |
| --- | --- | --- |
| iPhone with three rear lenses | Up to two steps in one pinch | Shown |
| iPhone with two rear lenses | One step each way | Shown |
| iPhone with one rear lens | Nothing | Not shown |
| iPhone Duo, outer and inner display | As the iPhone, on whichever display is in use. Folding or unfolding during a pinch ends it and keeps the lens the camera has. The picture must stay clear of the hinge as it does today. Which lenses the device has is read at run time | By its lenses |
| iPad with two rear lenses | One step each way. A pinch on a trackpad is delivered as the same gesture and should behave the same; to be checked | Shown |
| iPad with one rear lens | Nothing. No hint is shown: a message that explains why nothing happened would be shown to people who did not mean to pinch | Not shown |
| Front camera, every device | Nothing | – |
| Apple Watch remote | No change. The watch has no lens choice and no viewfinder (watch.html). Lens choice by the crown or by buttons would be a new capability of the remote and is not proposed (decision 10) | – |
| Lock Screen camera | As the camera in the app | As Settings there |
| Split View, Slide Over, Stage Manager | By the layout the window gets: on in the stacked and column layouts, off in the scrolling layout | – |
| External keyboard | Unchanged: arrow keys move within the lens group | – |

## 9. Accessibility

- **VoiceOver.** A pinch is not delivered to the app while VoiceOver is on. Nothing is lost: the lens buttons are elements with the selected trait, and the lens is spoken on change. No new action is added to the Viewfinder element, which would duplicate the buttons beside it.
- **Voice Control.** "Tap Telephoto", "Tap 5×", as today. No new name.
- **Switch Control and Full Keyboard Access.** The lens group, as today. AssistiveTouch can perform a pinch, and it then behaves as any pinch.
- **Largest text.** The scrolling layout has one full-width row for each lens; the pinch is off there. The Settings row wraps its value under its title; the explanation and scope note are footnote text that grows with the text size.
- **Right to left.** The picture is laid out left to right in every language, and a pinch has no side. The label's text follows the language; the number uses the person's locale, as the lens buttons do. The Settings row mirrors as every row.
- **Night Mode.** The label is red on black; nothing else is added. The pinch is off in Astro (section 5).
- **Reduce Motion.** The label fades (`NopeMotion.fade` is the same with Reduce Motion); the lens row's selection switches without sliding, as today. Nothing else moves.
- **Reduce Transparency and Increase Contrast.** The label's backing becomes solid black, as `NopeMaterial.backing` does everywhere.
- **Contrast.** The label is white on the backing, the same pair as the pills.
- **Not color alone.** The label is text.
- **Timing.** The label leaves after 0.8 s; the lens row and the Viewfinder's value keep the same information.
- **Cognitive.** One pinch, one visible and felt result; a setting to turn it off.

## 10. Strings

New, all drafts: the row title, the two values, the explanation, the scope note, the search keywords and the Accessibility sentence (section 7.2). The label on the picture uses existing strings only: the lens names, the multiplier and "No RAW". No new announcement. Every new string is needed in each launch language.

## 11. Build notes and tests

No code is part of this document. Notes for the builder:

- **Step logic** as a value type in `NopeCore`, with no SwiftUI: given the lenses in order, the lens at the start of the pinch and the current scale, it returns the target lens, with the thresholds and the 10% return margin of 3.2.
- **Availability** as one function in `NopeCore` over the model's state, returning whether a pinch is used now (section 5). The interface adds the states only it knows: Q, a dial or a sheet open, and the layout.
- **The gesture:** `MagnifyGesture` added to `ViewfinderTouches` as a simultaneous gesture; when it begins, the hold task is cancelled and the drag's ending is ignored.
- **The switch** goes through the existing `CameraIntent.selectLens`, once for each settled target (3.3).
- **The setting:** an enum in `NopeSettings` (`switchLenses`, `off`), in presets and in Factory Defaults, with a Settings search entry and a stable identifier.
- **Tokens:** the thresholds, the settle time and the label's time on screen are named constants, listed in tokens.md when this is accepted.

Tests to add.

Unit:

1. Steps: below the first threshold no change; at 1.25 one lens longer; at 0.80 one wider; at 1.69 two longer; the reverse figures pinching.
2. Ends: at the last lens a larger scale stays there; at the first lens a smaller scale stays there; no wrap.
3. Return margin: hovering at a threshold does not alternate; passing 10% back returns one lens.
4. Order: the front camera is never a target; a lens without RAW is a target (or is skipped, by decision 4); one rear lens gives no target; a lens with no magnification keeps its place in the catalog's order.
5. Starting on the front camera gives no target.
6. Availability: false for each state of section 5 (capturing, saving, countdown, burst, bracket, interval, Astro on, Astro running, starting, paused, hot, failed, front camera, one rear lens, setting Off); true in Night Mode, with Manual Controls on, in clean view and with each drive mode chosen and idle.
7. Settling: several targets in one pinch send one `selectLens`; returning to the starting lens sends none; a target reached while a switch runs is sent after it.
8. Settings: the default is Switch Lenses; the value is stored and read back; a preset stores and applies it; Factory Defaults restores it; a file from an earlier version without the value reads as the default.
9. Search: "pinch", "zoom", "lens" and "gesture" find the row; the row's entry exists only with two or more rear lenses.
10. Magnify: a lens change by pinch leaves `isMagnifying` as it was (by decision 8).

UI, with the simulated backend set to one, two and three rear lenses:

1. Pinch out on the Viewfinder selects the next longer lens: the lens button has the selected trait and the Viewfinder's value names the lens. Pinch in selects the next wider.
2. One long pinch on three lenses ends on the third.
3. With Pinch set to Off, a pinch changes nothing.
4. A pinch changes nothing on the front camera, with one rear lens, during a countdown, during a burst and an interval series, with Astro on, with Q open and with a dial open.
5. After a pinch: the controls are still shown (no clean view), focus and exposure are not locked, and a following tap still focuses.
6. With Magnify on, a pinch changes the lens and the Magnify pill is still shown (by decision 8).
7. At the largest text size, a pinch changes nothing and the lens rows work.
8. Settings: the row is under Camera with the value Switch Lenses; the menu changes it; it is absent with one rear lens; search finds it.
9. `performAccessibilityAudit()` with the label showing: default, Night Mode, right to left, Increase Contrast; and on the Settings list with the new row at the largest text size and right to left.
10. iPad column layout and iPhone sideways: tests 1 and 5 again.

On a device before release: the thresholds with one hand and two on the smallest and largest iPhone and an iPad; the time a lens switch takes on each lens pair, recorded in `docs/TESTING.md`; that haptic ticks play during a pinch; a trackpad pinch on iPad; AssistiveTouch's pinch; the iPhone Duo on both displays.

## 12. Decisions for the owner

1. **Which release?** Recommended: **1.1.0**. Release 1.0.0 is limited to bug fixes and the interface of features that already exist. This adds a gesture, a stored setting, a row in Settings and in presets, new strings in every launch language, and thresholds that must be tuned on devices. It also needs the design set redrawn, which is otherwise settled for 1.0.0. The alternative is to count it as interface work on the existing lens choice and take it into 1.0.0; the cost is the translation, the Honesty review and the device tuning before release.
2. **The setting's form.** Recommended: a picker named **Pinch** with the values **Switch Lenses** (default) and **Off**, in Settings › Camera after Focus on Faces. Alternative: a switch named "Pinch to Switch Lenses", on by default; simpler today, but it must be replaced if a third value is ever added.
3. **One lens for each pinch, or several?** Recommended: several. A short pinch moves one lens; a longer one passes further lenses with a tick and label for each, with the thresholds of 3.2 as starting values to tune on devices. Alternative: exactly one lens for each pinch, however far the fingers move; fewer accidents, but two pinches to cross three lenses.
4. **Is a lens without RAW part of the pinch order?** Recommended: yes. The pinch follows the lens row exactly; the label says "No RAW" and the Processed marker appears. Alternative: skip such lenses, so a pinch can never lead to a processed photo; the cost is a gesture that no longer matches the row.
5. **The label during a pinch.** Recommended: the existing multiplier ("0.5×", "1×", "5×") with the lens's name and "No RAW" where it applies, in the middle of the picture, leaving 0.8 s after the fingers lift. No focal length is added, and the picture is never animated between lenses.
6. **Astro.** Recommended: a pinch does nothing while Astro is on, idle or running. A stray touch in the dark could otherwise change the lens and turn Astro off. The lens buttons stay as they are.
7. **Clean view.** Recommended: the pinch works in clean view, with the label as the confirmation. Alternative: off in clean view, where the lens row is not shown.
8. **Pinch while Magnify is on.** Recommended: it switches lenses and Magnify stays on, exactly as a lens button does today (A in 6.4). Not recommended: doing nothing (B), changing the magnifier's size (C, which looks like digital zoom and is a new capability), or switching lenses and turning Magnify off (D).
9. **A "Check Focus" value for the pinch.** Recommended: no. It would duplicate Magnify under a second name. If a pinch for checking focus is wanted later, add a third value named **Magnify** to this setting, which turns the existing Magnify on and off; not before the lens pinch has been used on devices.
10. **Magnify's name, wording and Settings search entry.** Recommended: unchanged.
11. **Apple Watch.** Recommended: no lens choice on the watch, by the crown or by buttons. The remote has no viewfinder to show the result, and it would be a new capability of the watch app.
12. **One rear lens (most iPads, some iPhones).** Recommended: a pinch does nothing, the Settings row is not shown, and no hint explains it.
13. **A new VoiceOver action on the Viewfinder (Next Lens, Previous Lens).** Recommended: none. The lens buttons are beside it and already carry the names and the selected state.
14. **Wording.** Recommended: the drafts of 7.2, sent to the Honesty review; "zoom" appears only as a search keyword, never in visible text.

## 13. When this is accepted

- Draw the figures: the camera during a pinch (label on the picture, lens row following) in full auto, at an end of the range, on a lens without RAW, in Night Mode, in clean view, with Magnify on, sideways, on iPad and on the iPhone Duo inner display; Settings › Camera with the Pinch row, its menu open, the largest text size, right to left and a long language.
- Move sections 3 to 6 and 11 into [BUILD-SPEC.md](BUILD-SPEC.md), section 9 into [ACCESSIBILITY.md](ACCESSIBILITY.md), and the setting into the tree of [SETTINGS-PLAN.md](SETTINGS-PLAN.md) and [settings.html](settings.html); record the decisions; remove them from this file.
- [navigation.md](navigation.md): Lens gains "or pinch on the picture"; Pinch, home Settings › Camera, path Q › Settings › Pinch › value, 4 taps.
- [tokens.md](tokens.md): the pinch constants; no new haptic.
- Add this page to [README.md](README.md) and [overview.html](overview.html).
- `docs/ARCHITECTURE.md`: the viewfinder's touches and the new setting, when it is built.
