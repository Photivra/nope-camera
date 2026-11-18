# Keep Screen On

Status: proposed 2026-11-18 for release 1.0.0 (issue 97); not yet accepted, and not yet part of [BUILD-SPEC.md](BUILD-SPEC.md), [SETTINGS-PLAN.md](SETTINGS-PLAN.md) or the screen counts in [README.md](README.md). The wording is a draft until the Honesty review. Figures named below are `screens/<name>.html`, each with a PNG beside it.

The request: a setting, off by default, that keeps the screen awake while the camera is open, for tripod work with long gaps between photos.

Sources: issue 97, issues 48 and 60; the code on branch `fix-review-100` (`Sources/NopeCore/SeriesScreenKeeper.swift`, `DeviceStatus.swift`, `HeatLevel.swift`, `SettingsPresets.swift`, `Sources/NopeUI/SeriesScreen.swift`, `SettingsScreen.swift`, `SettingsSearch.swift`, `ResourceWarnings.swift`, `AccessibilitySettingsView.swift`, `App/NopeApp/NopeApp.swift`, `App/NopeApp/Camera/DeviceStatusReader.swift`, `App/NopeCaptureExtension`); AGENTS.md, "Battery"; [SETTINGS-PLAN.md](SETTINGS-PLAN.md); [SETTING-SCOPE.md](SETTING-SCOPE.md); [level-haptic.md](level-haptic.md), section 4.

Evidence note: everything about the code was read from the code. Nothing here was measured or looked at on a device: not the battery cost, not what iOS does with the idle timer and the brightness in each state. Each such statement is a device check in section 11. The times (2 minutes, 30 seconds, 30 minutes) are proposals, not measurements.

Contents: 1. What exists today · 2. The setting · 3. When it is used · 4. Dimming · 5. The 30-minute limit · 6. Battery and heat · 7. Night Mode, series, the Lock Screen camera, devices · 8. Presets, search, Shortcuts · 9. Accessibility · 10. Wording · 11. Device checks · 12. Build notes and tests · 13. Decisions for the owner

## 1. What exists today

| Fact | Where |
| --- | --- |
| The app turns the system's idle timer off only while an interval series or an Astro run is going in the foreground. Otherwise the phone's Auto-Lock applies, and locking stops the camera | `SeriesScreenKeeper`, `SeriesScreen` |
| When the series starts, the screen is dimmed at once to 10% (never raised: a darker screen is left as it is), and the brightness is put back when the series ends, the camera screen goes away or the app leaves the foreground | `SeriesScreenKeeper.update`, `dimmedBrightness` |
| While dimmed, a cover is over the whole camera screen: a tap anywhere brightens the screen and does nothing else. A card in the middle reads "Screen dimmed to save battery. Tap to brighten it." and "Brighten Screen", which is the button's name. VoiceOver hears the sentence when the screen dims and "Screen brightness restored." when it is put back | `BrightenScreenButton`, `SeriesScreen` |
| The cover is shown whenever a series dims, also when the screen was already darker than 10% and nothing changed | `SeriesScreenKeeper.update` sets `isDimmed` in every case |
| `SeriesScreenKeeper` is the only place that changes the idle timer or the brightness | Its own comment; `SystemScreen` |
| The Lock Screen camera is given no keeper, so it never changes the idle timer or the brightness | `NopeCaptureExtension`; `seriesScreenKeeper` is set only in `NopeApp` |
| Battery Low shows at 3% or less while not charging. An Astro run stops at 10% | `DeviceStatus.lowBatteryLevel`, `AstroHelper.stopBatteryLevel` |
| At the critical heat level the app pauses the camera | `HeatLevel.requiresPause` |
| Low Power Mode is read already; the live aids run at a reduced rate in it | `DeviceStatus`, `FrameAnalysis.interval` |
| A preset stores every stored setting | `SettingsPreset`, `NopeSettingsSnapshot` |
| Two sentences say "nope. doesn't change the screen's brightness.": the Night Mode explanation in Settings and the Night Mode entry on the Accessibility page | `SettingsScreen.swift`, `AccessibilitySettingsView.swift` |

AGENTS.md, "Battery", says the camera session runs only while the camera screen is in use and stops after an idle pause, and that the app respects Low Power Mode and the thermal state. Today the idle pause is the phone's Auto-Lock. A setting that turns Auto-Lock off has to bring its own end, or a camera left open runs until the battery is empty. Sections 4 to 6 are that end.

## 2. The setting

**Keep Screen On**, a switch, off by default.

- **Name.** "Keep Screen On". Three words, the name people look for, and it fits beside a switch at every text size. The issue's "Keep Screen On While Camera Is Open" puts the scope in the name; here the scope is the first words of the explanation, as on Red Viewfinder ("In Night Mode, …") and as [SETTING-SCOPE.md](SETTING-SCOPE.md), section 6, sets for a switch.
- **Place.** Settings › Screen, after Red Viewfinder and before Live Activity (figure `keep-screen-row`; night mode `keep-screen-row-night`). Screen is the group for what the screen does; the three Night Mode rows stay together; the last two rows are then the two that are about the phone being left alone. The list has 17 to 20 rows, depending only on the device.
- **Shown** on every iPhone and iPad. Not in the Lock Screen camera's Settings (section 7, decision 9). The row never appears or disappears as another setting changes.
- **No Q tile, no pill, nothing new on the camera.** It is set once, before a session. A pill is for what changes the photo.
- **Path:** Q › Settings › switch, 3 taps; search "auto-lock" or "awake".

Explanation under the switch (draft):

> While the camera is showing, the screen stays on for 30 minutes after your last touch or photo, and dims after 2 minutes. Uses more battery. Not used while Battery Low shows.

It is three short sentences where the plan asks for one or two. Each is there because leaving it out would let the row promise more than the app does: the limit, the cost, and the one state where the switch is on and not used.

## 3. When it is used

The idle timer is off only while all of these hold. When any stops holding, the idle timer is turned on again at once and the brightness is put back.

| Condition | Why |
| --- | --- |
| The switch is on | |
| The app is active in the foreground | iOS allows nothing else; the side button still locks the phone and stops the camera |
| The camera screen is in front: no sheet, popover or full-screen cover over it (Settings, Formats, Photo Details, Presets, Compare, the Last Photo viewer) | The setting is for watching the picture. A sheet is in use while it is open, so Auto-Lock is rarely reached there; and the dimming cover belongs to the camera screen |
| The camera is running: not starting, paused, interrupted, without permission, or in first run | There is no picture to keep on |
| Battery Low is not showing | Section 6 |
| Less than 30 minutes since the last touch or photo | Section 5 |

Q open, clean view, Magnify, the dials and Pro Tools are all the camera screen; the setting is used.

What counts as "a touch or photo" (activity), for dimming and for the limit:

- any touch on the camera screen;
- any control changed by any means: VoiceOver, Voice Control, Switch Control, a keyboard, Siri or a shortcut;
- any photo, however it was taken: the shutter, the volume buttons, Camera Control, the Apple Watch, Siri, a shortcut, the end of a self-timer;
- while VoiceOver is on, VoiceOver's focus moving to another control.

The device being moved is not activity: the app starts no sensor for this.

## 4. Dimming

**Yes: after 2 minutes without activity the screen dims to 10%, with the Brighten Screen cover the series has** (figures `keep-screen-dimmed`, `keep-screen-dimmed-night`). Same level, same cover, same words, same VoiceOver announcements. Nothing new to learn and no new string on the camera.

| Rule | Value |
| --- | --- |
| Dims after | 2 minutes without activity; 30 seconds in Low Power Mode |
| Dims to | 10% (`SeriesScreenKeeper.dimmedBrightness`). Never raises the brightness |
| Already at 10% or darker | Not dimmed and no cover: nothing would change, and a person working in the dark at the lowest brightness is not interrupted. New for this setting; the series keeps its behavior |
| A touch while dimmed | Brightens the screen and does nothing else: the cover takes the touch, as during a series. The count starts again |
| A hardware shutter press, a photo from the watch, Siri or a shortcut while dimmed | The photo is taken. The count starts again. The screen stays dimmed |
| Dims again | 2 minutes after the last activity, as often as needed |
| Brightness put back | When the setting stops being used for any reason in section 3, when the screen is brightened, and when the phone locks |

Why dim at all: the screen is the part of the cost the app can cut without stopping the camera, and the series already does it. Why not at once, as the series does: a series needs no framing, but here the person may be composing; 2 minutes without a touch is taken to mean they have stepped back.

The cost of this choice: the first touch on a dimmed screen only brightens it, so a shutter tap on the dimmed screen takes no photo. The hardware buttons and the watch still do. The other choices are in decision 4.

At 10% the picture is visible in the dark and hard to see in daylight. That is the same during a series today.

## 5. The 30-minute limit

Thirty minutes after the last activity the app turns the idle timer on again. The phone then locks after its own Auto-Lock time, as if the setting were off. The screen stays dimmed until it locks or is touched; nothing is announced, as nothing is announced when a phone locks. A touch or a photo before the lock starts a new 30 minutes.

Why a limit: with the setting on, a phone left on a table with the camera open would otherwise run the camera until the battery is empty, and stay unlocked the whole time. Thirty minutes covers a long wait for light; a longer wait is kept alive by one touch or one photo. An interval series or an Astro run has no such limit, as today: there the app is taking photos.

The limit is the same when the phone is charging (decision 6).

## 6. Battery and heat

| State | Rule | Why |
| --- | --- | --- |
| Low Power Mode on | The setting is used; the screen dims after 30 seconds, not 2 minutes | The person asked for the screen to stay on, and Low Power Mode is common on a long tripod session. The app respects it by cutting the cost sooner. iOS's own Auto-Lock in Low Power Mode is 30 seconds (device check 5) |
| Battery Low showing (3% or less, not charging) | The setting is not used: the idle timer is on, the brightness is put back, Auto-Lock applies. It is used again when the warning goes away (charging, or above 3%) | The charge that is left goes to taking photos. The reason is on the screen: the Battery Low warning. Its explanation gains a sentence (wording 4) |
| Charging | No change to any rule | One set of rules |
| Heat: serious | No rule of the app's own | The system manages it; the app has no rule at this level elsewhere |
| Heat: critical | The camera is paused, so the setting is not used (section 3) | Existing behavior covers it |

"Uses more battery" is in the explanation without a number. AGENTS.md asks for energy to be measured with Instruments before each release; the number, when measured, goes to the Honesty page, not into the row.

## 7. Night Mode, series, the Lock Screen camera, devices

- **Night Mode.** The same rules. The cover is red on black (existing). Astro users who have set the screen to its lowest brightness are at or under 10% and get no dimming and no cover.
- **The sentence "nope. doesn't change the screen's brightness."** It is meant to say that Night Mode does not dim. It is already not true during a series, and with this setting it is untrue more often. Both places change to "Night Mode doesn't change the screen's brightness." (wording 5 and 6, decision 8).
- **Interval and Astro.** While a series runs, the series' rule applies as today: the screen dims at once and there is no limit. When the series ends, the brightness is put back and this setting starts counting from zero.
- **Self-timer, Burst, Bracket.** Each photo is activity. No other change.
- **Lock Screen camera.** Not used, and the row is left out of its Settings. The extension is given no keeper, so today it leaves the idle timer and the brightness alone, and this design adds nothing there. What iOS does with the screen in the Lock Screen camera is its own rule (device check 6).
- **iPad.** The same. In Split View, Slide Over and Stage Manager the setting is used while the app's window is active; the idle timer belongs to the whole device.
- **iPhone Duo.** The same on both displays; folding or unfolding is not activity.
- **Apple Watch.** Nothing new on the watch. A photo from the watch is activity on the phone.
- **Live Activity.** No change.

## 8. Presets, search, Shortcuts

- **Presets.** Stored in a preset, like every stored setting: a preset for tripod work is the plain use. Factory Defaults turns it off. A preset saved before this release has no value for it and applies as off.
- **Settings search.** The row is found by its name and by keywords: "awake, auto-lock, sleep, lock, dim, tripod, battery" (not shown on screen; translators list the words people use). Result: "Keep Screen On", in Screen; choosing it scrolls the Settings list to the row, as for the other switches.
- **Siri and Shortcuts.** No action in 1.0.0 (decision 10). Of the Screen switches only Night Mode has one today.
- **Control Center, Live Activity, the watch:** nothing.

## 9. Accessibility

| Topic | Design |
| --- | --- |
| The row | One element, as every explained switch: "Keep Screen On", the explanation, switch, on or off. Voice Control: "Keep Screen On" |
| Dimming | VoiceOver hears "Screen dimmed to save battery. Tap to brighten it." and, when it is put back, "Screen brightness restored." (existing strings and behavior) |
| The cover with VoiceOver | "Brighten Screen, button", with the sentence as its value. The controls under it stay reachable, so Take Photo works while dimmed (as during a series; device check 7) |
| VoiceOver exploring | Moving VoiceOver's focus is activity, so the screen does not dim, and nothing is announced, while someone is reading the controls |
| Switch Control, Voice Control, keyboard | Every control used is activity. Brighten Screen is a named button, never only a gesture |
| Text size, right to left | The row is an explained switch like the others; the cover's card wraps and scales (existing) |
| Night mode | Row and cover red on black (`keep-screen-row-night`, `keep-screen-dimmed-night`) |
| Reduce Motion | The brightness change is the system's; the cover appears with `NopeMotion.fade` |
| Time limits | Dimming and the limit only return the phone to its normal behavior; no content or input is lost when they happen |

## 10. Wording

US English. Drafts for the Honesty review; none ships until reviewed.

| # | Where | Today | Proposed |
| --- | --- | --- | --- |
| 1 | The switch | (new) | Keep Screen On |
| 2 | Its explanation | (new) | While the camera is showing, the screen stays on for 30 minutes after your last touch or photo, and dims after 2 minutes. Uses more battery. Not used while Battery Low shows. |
| 3 | Search keywords, not shown | (new) | awake, auto-lock, sleep, lock, dim, tripod, battery |
| 4 | Battery Low, the explanation, when Keep Screen On is on | Battery at 3%. Charge the device soon to keep taking photos. | Battery at 3%. Charge the device soon to keep taking photos. Keep Screen On is not used now. |
| 5 | Settings › Night Mode, explanation | Red on black, to keep your eyes used to the dark. nope. doesn't change the screen's brightness. | Red on black, to keep your eyes used to the dark. Night Mode doesn't change the screen's brightness. |
| 6 | Settings › Accessibility › Night Mode | nope. doesn't change the screen's brightness. Dim it in Control Center, or with Reduce White Point in the Accessibility settings. | Night Mode doesn't change the screen's brightness. Dim it in Control Center, or with Reduce White Point in the Accessibility settings. |
| 7 | Honesty, a new entry | (new) | Keep Screen On stops the screen from locking by itself while the camera is showing, so the camera keeps running and uses more battery. The screen dims to 10% after 2 minutes without a touch (30 seconds in Low Power Mode). After 30 minutes without a touch or a photo, the phone's Auto-Lock applies again. While the screen is on, the phone is unlocked. The side button always locks it. |
| 8 | The cover | Screen dimmed to save battery. Tap to brighten it. / Brighten Screen | Unchanged. Only the translators' comments change: they say "when interval shooting starts" |

What each sentence rests on:

- "While the camera is showing": section 3. "Showing", not "open": with a sheet over the camera the setting is not used.
- "stays on for 30 minutes after your last touch or photo": the limit. Without it the sentence would say the screen never locks, which is not true.
- "dims after 2 minutes": true outside Low Power Mode. In Low Power Mode it is sooner; the Honesty entry says so. If the Honesty review wants the row exact in every state, "dims after 2 minutes" becomes "dims when it isn't touched".
- "Uses more battery": the screen and the camera run for longer than they would. No amount is given; none has been measured.
- "Not used while Battery Low shows": section 6. It names the warning the person sees.
- "While the screen is on, the phone is unlocked": a fact people should have before leaving a phone on a tripod.
- The Battery Low sentence with Low Power Mode on ("Battery at 3%. Low Power Mode is on.") gains the same last sentence.

## 11. Device checks

1. Turning the idle timer on again after the limit: the phone locks after its Auto-Lock time, and with Auto-Lock set to Never it stays on.
2. Setting the brightness with Auto-Brightness on: whether iOS moves it again while dimmed, and whether it is put back correctly.
3. The brightness is back to the person's level after: brightening, opening a sheet, leaving the app, locking with the side button, locking by Auto-Lock after the limit.
4. A touch is seen as activity everywhere on the camera screen, including on the picture, in Q and on system menus opened from Q.
5. Low Power Mode: the idle timer can still be turned off, and iOS's own Auto-Lock time.
6. The Lock Screen camera: what iOS does with the screen when it is not touched.
7. VoiceOver with the cover shown: Take Photo is reachable and works; focus moving counts as activity.
8. Energy, with Instruments: the camera showing for 30 minutes at the person's brightness and at 10%, for the Honesty page.
9. 10% in daylight and in the dark: whether the card and the picture can be seen.

## 12. Build notes and tests

`SeriesScreenKeeper` stays the one place that changes the idle timer and the brightness. It gains a second reason to keep the screen awake.

- `NopeSettings.keepsScreenOn` (stored, default off, in the snapshot and so in presets).
- The rule is a small pure type in `NopeCore`, beside the keeper: given the switch, the conditions of section 3, Low Power Mode, the time of the last activity and the time now, it answers whether to keep awake and whether to dim. It is under the coverage gate; the keeper applies its answer to the screen.
- The keeper's `update` takes the new inputs beside `isSeriesRunning`; a series wins while it runs. It gains `noteActivity()` and a clock that tests can replace. It schedules one wake-up for the next change (dim, or the limit); no polling.
- "Already at 10% or darker: no cover" applies to this reason only.
- `SeriesScreen` (NopeUI) passes the conditions and calls `noteActivity()` for control changes and photos; the app passes touches on the camera screen without taking them, and VoiceOver focus changes.
- The row: `ExplainedToggle` in `SettingsScreen.screenSection`; `SettingsID.keepScreenOn`; left out in the Lock Screen camera through a new value of `SettingsSearch.Availability`, which also keeps it out of search there.
- Strings in all eleven launch languages.
- No new permission, no background mode, no sensor.

Acceptance:

- Off: the app never changes the idle timer outside a series, as today.
- On: the idle timer is off exactly while every condition of section 3 holds, and on again within one update after any stops holding.
- The screen dims after 2 minutes (30 seconds in Low Power Mode) without activity, not when it is already at 10% or darker, and is put back in every case of device check 3.
- After 30 minutes without activity the idle timer is on.
- With Battery Low showing, the idle timer is on and the screen is not dimmed by this setting.
- A series behaves exactly as before, with the setting on or off.
- Toggling the switch does not change the number of rows on the Settings list.

Unit tests: the rule for every condition and both timings; the keeper with a fake screen and clock, including series and setting together, and brightness put back on each exit. UI tests, with launch arguments that shorten the times: `testKeepScreenOnRow` (place, default off, explanation, accessibility audit in light, dark, night mode, largest text size, right to left), `testKeepScreenOnDimsAndBrightens`, `testKeepScreenOnNotUsedUnderASheet`, `testSettingsSearchFindsKeepScreenOn`, `testSettingsRootRowsDoNotChange` updated, a preset round trip.

When accepted: SETTINGS-PLAN.md 3.1 and 3.2, BUILD-SPEC.md 3.10 and its strings, ACCESSIBILITY.md, the Settings figures that reach the Screen group, and the README counts are updated with the build.

## 13. Decisions for the owner

| # | Decision | Recommendation | The other choice |
| --- | --- | --- | --- |
| 1 | The name | "Keep Screen On", with the scope as the first words of the explanation | "Keep Screen On While Camera Is Open", the issue's example: the scope is in the name, but it wraps to two or three lines beside the switch |
| 2 | The place | Settings › Screen, after Red Viewfinder, before Live Activity | Settings › Camera, after Focus on Faces |
| 3 | Where it is used | Only while the camera screen is in front and the camera is running; not under a sheet or the Last Photo viewer | Whenever the app is in the foreground: simpler to say, but the screen then stays on over Settings and Photo Details, where the dimming cover cannot be shown |
| 4 | Dimming | Dim to 10% after 2 minutes without a touch, with the Brighten Screen cover of the series. The first touch only brightens | (a) No dimming: the simplest, at the highest battery cost. (b) Dim, and let the first touch also do what it touched: no lost shutter tap, but a second kind of dimmed screen to build and explain |
| 5 | The limit | Auto-Lock applies again 30 minutes after the last touch or photo | (a) No limit: the screen stays on until the battery is low. (b) Another time: 15 or 60 minutes |
| 6 | While charging | The same rules | No limit while charging, for use on external power; one more state to explain |
| 7 | Low Power Mode and Battery Low | Low Power Mode: used, dims after 30 seconds. Battery Low: not used, and the warning says so | (a) Not used in Low Power Mode either. (b) Not used from 10%, the level at which Astro stops, with no warning on screen at that level |
| 8 | "nope. doesn't change the screen's brightness." | Change both sentences to "Night Mode doesn't change…" (wording 5 and 6). They are not true during a series today | Leave them |
| 9 | The Lock Screen camera | Not used; the row is left out of its Settings | Show the row there with a sentence that it is not used |
| 10 | Shortcuts | No action in 1.0.0 | A Set Keep Screen On action, like Set Night Mode |
| 11 | The series' cover when the screen was already at 10% or darker | Leave the series as it is in 1.0.0; a separate issue to give it the same "no cover" rule | Change the series in this work too |
| 12 | The explanation's length | The three sentences of wording 2, and the Honesty entry for the rest | Two sentences: drop "Uses more battery." from the row and keep it on the Honesty page |
