# Where a setting applies: Fast Shutter

Design version: 1.0.0, direction B · Reach. Owner request of 2026-11-18: "Add note beside setting option to what it only applies to." The drawings are in [setting-scope.html](setting-scope.html); each figure named below is `screens/<name>.html` with a PNG beside it. The build steps are in [BUILD-SPEC.md](BUILD-SPEC.md), section 3.16. The wording is a draft until the Honesty review. Release 1.0.0 changes the interface of features that exist: nothing here changes what Fast Shutter does.

Contents: 1. What the code does · 2. The design · 3. The wording · 4. VoiceOver and other access · 5. Each place Fast Shutter appears · 6. One pattern, and the other settings · 7. Found while checking · 8. Decisions for the owner · 9. When this is accepted

## 1. What the code does

Read in the code on 2026-11-18. Nothing here was measured on a device for this document.

| Fact | Where |
| --- | --- |
| Fast Shutter has three choices: Standard, Freeze Motion (1/500 s), Freeze Fast Motion (1/1000 s). The choice is stored in `NopeSettings.fastShutter` | `FastShutter` in `Sources/NopeCore/AutoControls.swift` |
| With Manual Controls off, the app sets the longest shutter the camera's own auto exposure may use: the shorter of the choice and the handheld rule, 1/(2 × the 35 mm-equivalent focal length). The camera still chooses shutter and ISO | `AutoShutter.limits`, `AutoShutter.longestShutter` |
| When the scene is too dark for a limit at the lens's highest ISO, the next limit is tried, then the limit is lifted, and "Hold it steady or use a tripod" is shown | `AutoShutter.longestShutter`, `updateSteadyHint` |
| With Manual Controls on, no limit is sent, whatever the choice: `longestShutter: isEnabled ? nil : longestAutoShutter`. This holds when every control is on Auto too | `ManualControlsModel.assist` in `ManualControlsModel+Auto.swift` |
| With Manual Controls on, the steady hint uses the handheld rule only, never the choice | `updateSteadyHint`, `AutoShutter.risksBlur` |
| The Q tile and the pill are built only while Manual Controls are off | `QuickControls.fastShutter`, `StatePills.fastShutter` |
| The Settings row and page, Settings search and the Shortcuts action are there whether Manual Controls are on or off | `SettingsScreen.cameraSection`, `FastShutterSettingsView`, `SettingsSearch.swift`, `SetFastShutterIntent` |
| All Auto returns every manual control to Auto and leaves Manual Controls on; VoiceOver then says "Full auto" | `ManualControlsModel` (`.allAuto`), `ManualControlsView.swift` |

So the condition is one switch: Manual Controls. Astro turns Manual Controls on, so the choice is not used in Astro either.

## 2. The design

Three changes, all text.

1. **The row.** Settings › Camera › Fast Shutter gains a note under its title and value: "Used only while Manual Controls are off." It is a line of its own, as wide as the row, in the footnote size and secondary color the switch explanations have. No symbol and no color: it is neither a warning (amber) nor a verified fact (teal). It is always the same, so the list never moves; the row is 18 pt taller at the default text size (figures `scope-camera`, `scope-settings-root`, `scope-camera-long`).
2. **The page.** The one paragraph becomes two. The first begins with the note, then says what the choice does in words that hold in low light. The second says what happens with Manual Controls on (figure `scope-page`).
3. **The page, while Manual Controls are on.** One line above the choices, with the information symbol: "Manual Controls are on, so this choice is not used now." The choices stay enabled; the choice is stored and is used again when Manual Controls are turned off. HEIF and JPEG Copies does the same when no copy is saved (figure `scope-page-manual`). This is decision 2.

Q and the camera do not change. The tile and the pill are shown only where the choice is used, which says the same thing without words (figures `scope-q-auto`, `scope-q-manual`, `scope-camera-auto`, `scope-camera-manual`). With Manual Controls on, Q shows nothing about Fast Shutter: the rule of the Q design is that a tile that can't be offered is left out, never shown disabled, and the Shutter readout on the picture is the control that does the job. A dimmed tile was considered and not proposed (decision 3).

Why "Manual Controls" and not "full auto":

- The control that decides it is named Manual Controls: for VoiceOver and Voice Control, in Settings search ("Manual Controls. On the camera, beside the lenses."), and in the app's other sentences ("…while Manual Controls are on"). Its visible label on the camera is Auto or Manual.
- "Full auto" is not the name of any control. After All Auto, VoiceOver says "Full auto" while Manual Controls are still on, and there the choice is not used. A note that said "Full auto only" would be wrong in that state.
- "Auto" alone is taken: each manual readout is Auto or Manual, and Flash has Auto.

## 3. The wording

US English. Drafts for the owner's Honesty review; none ships until reviewed.

| # | Where | Today | Proposed |
| --- | --- | --- | --- |
| 1 | The row, under the title and value | (nothing) | Used only while Manual Controls are off. |
| 2 | The page, first paragraph | In full auto, the camera prefers the fastest shutter that still exposes well, so photos blur less. Standard aims for a speed you can hold by hand. Manual controls are never changed. | Used only while Manual Controls are off. The camera keeps the shutter at least as fast as your choice while there is enough light, and uses a higher ISO to do it. In low light the shutter can be slower. Standard aims for a speed you can hold by hand. |
| 3 | The page, second paragraph | (nothing) | With Manual Controls on, this choice is not used. A shutter you set is used as set. A shutter on Auto is chosen by the camera. |
| 4 | The page, top line while Manual Controls are on | (nothing) | Manual Controls are on, so this choice is not used now. |
| 5 | Shortcuts, the description of Set Fast Shutter | Chooses how fast a shutter nope.'s full auto prefers, to avoid blur. | Chooses how fast a shutter nope. prefers while Manual Controls are off, to avoid blur. |

What each sentence rests on:

- "Used only while Manual Controls are off": `ManualControlsModel.assist`. "Used", not "works" or "applies": the choice is always stored and can always be changed; it is only left unused.
- "at least as fast as your choice while there is enough light": the limit is the shorter of the choice and the handheld rule, and it is lifted when the lens's highest ISO can't expose the scene at it. Today's "prefers the fastest shutter that still exposes well" describes the camera choosing the fastest shutter, which is not what happens: the app sets a limit and the camera chooses within it.
- "uses a higher ISO to do it": with the shutter limited, the camera's auto exposure raises ISO. The sentence does not say what a higher ISO does to the picture; nothing about noise has been measured.
- "In low light the shutter can be slower": the lifted limit. The steady hint says so on the camera when it happens.
- "A shutter on Auto is chosen by the camera": with Manual Controls on, the app sends no limit.
- Nothing promises a sharp photo. "so photos blur less" is dropped: it is a result the app does not check.

Not changed: the names of the three choices, the tile's short values (Standard, 1/500, 1/1000), the pill and its action Use Standard Shutter, Siri's answer "Fast Shutter is set."

## 4. VoiceOver and other access

- **The row is one element.** VoiceOver reads the title, the value, then the note, then the trait: "Fast Shutter, Standard, Used only while Manual Controls are off. Button." (figure `scope-camera-voiceover`). The note is part of the row's label, after the value, as the explanation of a switch is part of the switch's label. It is not the hint: hints can be switched off in VoiceOver's settings and are read after a pause, and where a setting is used is information, not a way to operate the row. It is not the value: the value stays the choice alone.
- **Voice Control** answers to "Fast Shutter": the row sets the title as its input label, so the longer label does not become the name.
- **The page.** While Manual Controls are on, the top line is the first element and is read first, as static text. The three choices follow, each with the selected trait where it applies, then the two paragraphs as static text in order. Nothing is announced when the page opens beyond what focus reads.
- **Text size.** At accessibility sizes the value is under the title and the note under the value; nothing is truncated (figures `scope-camera-largest`, `scope-page-largest`). At every size a value that does not fit beside the title sits under it, with the note last (`scope-camera-long`).
- **Right to left.** The row mirrors; the note starts under the title at the leading edge; fractions keep their direction (`scope-camera-rtl`, `scope-page-rtl`).
- **Night mode.** Red on black (`scope-camera-night`, `scope-page-night`). **Contrast.** The note uses the secondary text color of the explanations: #98989F on #1C1C1E (5.9:1) in dark, #6D6D72 on white (5.1:1) in light.
- **Switch Control and the keyboard.** No new target. The row and the choices are reached as today.
- **Siri and Shortcuts.** The action's description changes (wording 5). Its name, its choices and its answer do not.

## 5. Each place Fast Shutter appears

| Place | Change | Why |
| --- | --- | --- |
| Settings › Camera › Fast Shutter | The note | The one place the choice is shown where it may not be in use |
| The Fast Shutter page | Two paragraphs; the top line while Manual Controls are on | The explanation, and the answer to "why does it do nothing now" |
| Q, Manual Controls off | None | The tile is shown only where the choice is used |
| Q, Manual Controls on | None; nothing takes the tile's place | Q shows only what works now |
| The pill | None | Shown only while the choice is used and is not Standard |
| Settings search | None | The result names Fast Shutter and Camera and opens the page, which begins with the note |
| Shortcuts: Set Fast Shutter | The description | It said "full auto" |
| Presets | None | A preset stores the choice with Manual Controls on or off, as today |

## 6. One pattern, and the other settings

A setting that is used only in some state of the camera says so on the list, in words that name the control that decides the state (figure `scope-pattern`):

- **A switch:** its explanation begins with the condition. Exists: Red Viewfinder, "In Night Mode, shows the live picture in red too."
- **A row that opens a page:** a note of one sentence under the title and value. New, and used once.
- **A page whose choices are not in use now:** one line at the top says so, and every control stays enabled. Exists: HEIF and JPEG Copies, "No HEIF or JPEG copy is saved now. Turn one on in Formats."
- **A control on the camera or in Q:** no note. It is shown only where it works.

A note is plain secondary text. It never changes with the state, and it is never a reason to add or remove a row.

Every setting and Q control was checked against this. Only Fast Shutter changes.

| Setting or control | Used only | Says so today | Change |
| --- | --- | --- | --- |
| Fast Shutter | Manual Controls off | Only in the last sentence of its page | The note and the page text |
| Red Viewfinder | Night Mode on | Yes, its first words | None |
| Focus on Faces | While focus or exposure is automatic | Yes: "Autofocus and auto exposure follow faces the camera finds." | None |
| Show Processed Marker | A lens that can't save RAW | Yes; the row is shown only on a device with such a lens | None |
| Mirror Front Camera | The front camera | Yes, in its name | None |
| Live Activity | While a series runs | Yes | None |
| HEIF and JPEG Copies | While a HEIF or JPEG copy is saved | Yes: "Not Saved" on the row and the first line of the page | None |
| Night Mode | The app's own screens | Yes: "nope. doesn't change the screen's brightness." | None |
| Exposure (Q) | Manual Controls off | The tile is left out with Manual Controls on; the EV readout takes its place | None |
| Far Focus, Close-Up (Q) | Autofocus | The tiles are shown where the lens can limit focus (Far Focus only with Manual Controls on) | None here; section 7 |
| Flash (Q) | A lens with a flash; never a burst or a bracket | The tile is left out on a lens without a flash | None here; section 7 |

## 7. Found while checking

Read from the code; each needs a look on a device before anything is decided. None is designed here.

1. **Close-Up and Far Focus with Focus set by hand.** The limits are sent only while autofocus is in use (`DeviceControls`), but the tile and the pill follow the stored switch, so they can read On while they do nothing.
2. **Flash with Burst.** A burst never fires the flash (`CameraModel+Drive.swift`). The Flash pill follows the flash choice and the torch only, so it can read On or Auto while Burst is selected.
3. **"Full auto" after All Auto.** VoiceOver says "Full auto" while Manual Controls stay on. With the proposed wording the phrase no longer appears beside Fast Shutter, so this is a smaller matter; it is decision 4.

## 8. Decisions for the owner

| # | Decision | Recommendation | The other choice |
| --- | --- | --- | --- |
| 1 | The words of the note | "Used only while Manual Controls are off." It names the control that decides it and is true in every state | "Full auto only." Shorter and the owner's own phrase, but untrue after All Auto unless decision 4 changes that announcement, and "full auto" is not written on any control |
| 2 | The line on the Fast Shutter page while Manual Controls are on | Add it. It answers the question at the moment it is asked, costs one row, and follows HEIF and JPEG Copies | Leave it out: the two paragraphs already say it, and the page is then the same in every state |
| 3 | Q with Manual Controls on | Show nothing, as today | A dimmed Fast Shutter tile reading Not Used: the first disabled tile in Q, and a fifth row over the picture |
| 4 | VoiceOver's "Full auto" after All Auto | Change it to "All controls on Auto", a new draft string, so "full auto" is never said while Manual Controls are on | Leave it |
| 5 | The page text | Replace it with wording 2 and 3. Today's first sentence describes the camera choosing the fastest shutter, which the code does not do | Keep today's paragraph and change only its last sentence to "Used only while Manual Controls are off." |
| 6 | Findings 1 and 2 of section 7 | One issue for each, checked on a device, outside this change | Fold them into this change |
| 7 | Search keywords for Fast Shutter (it has none today) | Add "blur, motion, freeze, action, sports", not shown on screen | None |

## 9. When this is accepted

- The figures of the set that show the Fast Shutter row or page are redrawn with the note, and `settings-fast-shutter` with the new page: `settings-root`, `settings-light`, `settings-night`, `settings-rtl`, `settings-changed`, `settings-largest`, `ipad-settings`, `ipad-portrait-settings`, `ipad-settings-light`, `ipad-settings-night`, `ipad-settings-night-on`, `ipad-ax-settings`, `ipad-rtl-settings`, `ipad-split-half-settings`, `ipad-stage-small-settings`, `duo-outer-settings`, `duo-inner-settings`, `landscape-settings`, `lock-settings`. Done with the build (accepted 2026-11-18): each is redrawn from the same generator with only the note added and the new page, so the rest of each figure is unchanged; five of them (`ipad-ax-settings`, `ipad-stage-small-settings`, `duo-outer-settings`, `duo-inner-settings`, `landscape-settings`) do not reach the Camera group in their frame, so only their HTML changed.
- [SETTINGS-PLAN.md](SETTINGS-PLAN.md) 3.7 gains the rule of section 6, and its length for the largest text size is measured again. Done with the build: the rule is in 3.7, with the length of `settings-largest`.
- The `scope-*` figures that only compare (the Camera group and the page as they were, and the dimmed Q tile) are removed. Done with the build.
