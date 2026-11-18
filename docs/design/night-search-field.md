# Settings search in Night Mode: the red search field

Status: proposed 2026-11-18 for release 1.0.0 (issue 88); not yet accepted, and not yet part of [BUILD-SPEC.md](BUILD-SPEC.md) or of the screen counts in [README.md](README.md). The wording is a draft until the Honesty review. Figures named below are `screens/<name>.html`, each with a PNG beside it.

The request: Settings has no search field while Night Mode is on. Draw the app's own field, red on black, so search works in Night Mode too.

Sources: issue 88; the code on branch `fix-review-100` (`Sources/NopeUI/SettingsScreen.swift`, `SettingsSearch.swift`, `CameraStyle.swift`, `PhotoDetailsTags.swift`, `PresetsScreen.swift`, `App/NopeAppUITests/LightAndNightModeUITests.swift`, `SettingsUITests.swift`); [BUILD-SPEC.md](BUILD-SPEC.md) 3.10; [SETTINGS-PLAN.md](SETTINGS-PLAN.md) 3.6; [tokens.md](tokens.md); [ACCESSIBILITY.md](ACCESSIBILITY.md).

Evidence note: everything about the code was read from the code. Nothing here was looked at on a device. Each statement about what iOS draws, and where night mode's red filter reaches, is a device check in section 9.

Contents: 1. What exists today · 2. The design · 3. Typing, the keyboard and the cursor · 4. Switching Night Mode while Settings is open · 5. iPad and iPhone Duo · 6. Accessibility · 7. Wording · 8. Build notes and tests · 9. Device checks · 10. Found while checking · 11. Decisions for the owner

## 1. What exists today

| Fact | Where |
| --- | --- |
| Settings search is the system field, `.searchable` in the navigation bar's drawer, always shown under the title | `SettingsSearchField` in `SettingsScreen.swift` |
| In Night Mode the field is left out (owner decision, 2026-11-18): iOS draws it as gray glass outside the app's views, where the red filter can't reach it | `SettingsSearchField`, `isHidden` |
| When Night Mode changes while Settings is open, the search text is cleared and, on the Settings list, the list scrolls to the Night Mode row | `SettingsScreen`, `onChange(of: settings.isNightModeOn)` |
| Night mode multiplies everything the app draws by pure red: white becomes the full red, grays become darker reds, black stays black. Every text level is drawn at the full red, because a dimmer red is below 4.5:1 on black | `NightModeStyle`, `NightStyle` |
| The keyboard, system menus and alerts are drawn by iOS outside the app's views. They keep the dark appearance and are not red | The comment on `NightModeStyle` |
| The app already has a text field that is used in Night Mode: the name on Rename Preset. It is inside the app's views; its keyboard is the system's | `PresetsScreen.swift` |
| The night-mode UI tests count sampled pixels that are not black or red; the count must be 0 | `nonRedPixels` in `LightAndNightModeUITests.swift` |
| In Night Mode Settings is always a sheet, on iPad too; a popover that is open when Night Mode turns on becomes the sheet at once | `AdaptivePresentation`, `switchesToSheet` |
| Results, keywords, pointers to the camera and the empty state are the app's own views | `SettingsSearchResults`, `SettingsSearch` |

## 2. The design

In Night Mode the app draws its own search field in the place of the system field. Outside Night Mode nothing changes: the system field stays (decision 1). Search results, keywords, pointers and the empty state are not changed in either mode.

The field is a plain text field inside the app's views, so night mode's red filter covers it like every other row. Nothing in it is glass.

| Part | Drawing | Tokens |
| --- | --- | --- |
| Place | Under the Settings title, above the list, where the system field is. It stays there while the list scrolls. Black behind it, so rows do not show through. Only on the Settings list, never on a page | `NopeSpace.m` at each side, `NopeSpace.xs` above and below |
| Shape | A capsule, at least 44 pt high. It grows with the text size | `NopeSize.minTarget` |
| At rest | Black fill, 1 pt outline in the outline red | `NopeColor.nightOutline` (3.1:1 on black) |
| Focus | 2 pt outline in the full red, and the cursor. The outline grows inward, so nothing moves | `NopeColor.night` |
| Symbol | The magnifying glass at the leading edge, full red, decorative | `NopeSpace.xs` to the text |
| Placeholder | "Search", body text, full red | `.body` |
| Typed text | Body text, full red, one line; longer text scrolls sideways | `.body` |
| Clear Text | A filled red disc with a black cross at the trailing edge, shown only while there is text. Its target is 44 × 44 pt | `NopeColor.night`, `NopeSize.minTarget` |
| Cancel | The word "Cancel" in the full red beside the field, shown while the field has focus or holds text. Target at least 44 pt high | `NopeSpace.s` from the field |
| Increase Contrast | The outline at rest is the full red too; focus is still the 2 pt outline and the cursor | |
| Pressed | Clear Text and Cancel: opacity 0.7, as every custom button | |
| Motion | Cancel and Clear Text appear and leave with `NopeMotion.fade`; nothing slides | |

Figures: `night-search-rest` (the Settings list with the field), `night-search-states` (the five states), `night-search-typing` (focus, text, results and the keyboard), `night-search-empty` (no result), `night-search-largest`, `night-search-rtl`.

Why these choices:

- **Outlined, not filled.** The rule for custom controls in night mode is: on is filled red with a black label, off is an outline. A search field is not "on", so it is an outline, and it does not look like a selected button. A filled dark-red box was the other option; its edge against the dark red rows is under 3:1.
- **A capsule.** The system field is expected to be a capsule in the same place (device check 5), so the shape under the title does not change when Night Mode is switched. Capsule is also the shape of the app's own buttons and pills.
- **The placeholder in the full red.** Night mode has one red for all text. A dimmer placeholder would be below 4.5:1. The placeholder is told from typed text without color: it is the word "Search", it leaves at the first character, and Clear Text shows only when there is text.
- **Focus without color alone.** The outline gets wider and the cursor appears.
- **The word Cancel, not a second cross.** Clear Text is already a cross. Two crosses side by side would need to be learned.

## 3. Typing, the keyboard and the cursor

Behavior matches the system field unless stated.

| Action | Result |
| --- | --- |
| Tap the field | Focus; the keyboard opens; Cancel appears |
| Type | Results replace the list from the first character, as today |
| Clear Text | Empties the field. Focus and the keyboard stay; the list returns |
| Return (the key reads "Search") | Closes the keyboard. Text and results stay |
| Cancel | Empties the field, closes the keyboard, returns to the list |
| Scroll the results | Closes the keyboard. Text and results stay |
| Choose a result | Opens its page, as today. The search is still there on going back |
| Escape on a hardware keyboard | Cancels the search |
| Tab on a hardware keyboard | Reaches the field in reading order: after Done, before the list |

**The keyboard is not red.** iOS draws the keyboard, with its suggestions, the dictation button and the language key, outside the app's views. The app asks for the dark keyboard; it cannot draw it in red. This is already the case on Rename Preset. So with the keyboard open, part of the screen shows gray and white light. This design accepts that and says so (decision 5, wording in section 7). An in-app red keyboard was considered and is not proposed: it would not support the languages, input methods, dictation and accessibility features the system keyboard has.

To keep the non-red part small, the red field turns off autocorrection, suggestions and capitalization, so the bar above the keys has less in it (decision 6). Search matches titles and keywords whatever their case, so nothing is lost. Whether the bar goes away entirely is a device check.

**Cursor and selection.** The cursor and the selection highlight take the tint, which night mode sets to white and the filter turns red. Selection handles, the magnifier shown while moving the cursor, and the edit menu (Paste, Select All) may be drawn by iOS above the app's views. If they are, they are dark and not red, like the keyboard and like the menus on other screens. Device check 3.

## 4. Switching Night Mode while Settings is open

Night Mode can change with Settings open: from its own row, from Control Center, from Siri or a shortcut.

| Change | Result |
| --- | --- |
| Night Mode turns on, no search in progress | The red field takes the system field's place. The list scrolls to the Night Mode row, as today |
| Night Mode turns off, no search in progress | The system field returns. Same scroll |
| Either change while a search is in progress | The search text and the results are kept. The keyboard closes; a tap in the field opens it again (decision 7) |
| Either change while a page is open | Nothing to show; the Settings list has the right field when the person goes back |

Today the text is cleared on a change because the field goes away. With a field in both modes there is no reason to throw the search away. Focus is not carried from one field to the other: one is drawn by iOS and the other by the app, and handing focus between them at the moment the screen changes color is likely to flicker. Closing the keyboard is the predictable result.

The two fields have the same place and nearly the same height. If the heights differ on a device, the list under the field moves by that difference when the mode changes; device check 5 measures it.

## 5. iPad and iPhone Duo

- **Sheet, not popover.** In Night Mode Settings is always a sheet, so the red field is only ever drawn in a sheet. It is as wide as the list rows, with the same side margins.
- **Night Mode turned on inside the popover:** the popover becomes the sheet (existing behavior) and the sheet shows the red field. A search in progress is kept, as in section 4.
- **Night Mode turned off inside the sheet:** the sheet stays a sheet until it closes (existing behavior) and shows the system field.
- **Hardware keyboard:** no on-screen keyboard, so the screen is all red while typing. The floating and split keyboards are the system's.
- **iPhone Duo:** the same field on the outer and inner displays. Folding with a search in progress keeps the text, as `SettingsNavigation` keeps the rest of Settings.
- **Split View, Slide Over, Stage Manager, iPhone sideways:** the field follows the width of the list. No separate drawing; the layout rule of [layouts.html](layouts.html) applies.

## 6. Accessibility

| Topic | Design |
| --- | --- |
| VoiceOver, the field | One element. Name "Search Settings", value the typed text, trait search field. No hint. The magnifying glass is hidden |
| VoiceOver, Clear Text | "Clear text, button", present only while there is text. After it, focus is on the field |
| VoiceOver, Cancel | "Cancel, button". After it, focus is on the field |
| Order | Settings (heading), Done, the field, Clear Text, Cancel, then the results or the list |
| Results | Read as today: the setting and its page; pointers in words; headers are headings; the empty state is read as text. Whatever VoiceOver says when results change with the system field, the red field matches (device check 6) |
| Escape gesture | Cancels the search when one is in progress; otherwise as today |
| Voice Control | The field answers to "Search" and "Search Settings"; "Clear text"; "Cancel". The visible word is part of each name |
| Switch Control, Full Keyboard Access | Three targets while searching: the field, Clear Text, Cancel. The focus ring is the system's |
| Text size | The field, its symbol and Clear Text scale with the text. At accessibility sizes Cancel moves to a line of its own under the field (`night-search-largest`). Nothing is truncated: the typed text scrolls |
| Right to left | Mirrored: symbol at the leading edge, Clear Text and Cancel at the trailing edge. The magnifying glass is not flipped. Typed text follows its own direction (`night-search-rtl`) |
| Contrast | Text and the focus outline 5.3:1; the outline at rest 3.1:1; the black cross on the red disc 5.3:1 |
| Targets | Field, Clear Text and Cancel at least 44 pt, at least 8 pt apart |
| Reduce Motion | Fades only; there is no movement to remove |
| Reduce Transparency | No change: the field has no material |
| Color alone | Nothing depends on color: night mode has one |

## 7. Wording

US English. Drafts for the Honesty review.

| # | Where | Today | Proposed |
| --- | --- | --- | --- |
| 1 | The field's placeholder | (the system's "Search") | Search |
| 2 | The field's VoiceOver and Voice Control name | (the system's) | Search Settings |
| 3 | Clear Text, VoiceOver and Voice Control name | (the system's) | Clear text |
| 4 | Cancel | (the system's) | Cancel |
| 5 | Settings › Accessibility › Night Mode, a second entry | (nothing) | The keyboard and menus are drawn by iOS and are not red. |

Wording 5 is new information the app should give: with search available in Night Mode, more people will open the keyboard in the dark. It states only what the app does not do. Strings 1 to 4 need all eleven launch languages; where the system's own words for these controls are known for a language, use them.

## 8. Build notes and tests

- A new view, `NightSearchField` (text binding, prompt, accessibility name), in `NopeUI`. It holds no search logic. `SettingsSearchField` shows it in Night Mode and the system field otherwise; `isHidden` goes away.
- The view is not tied to Settings, so another screen can use it later (section 10).
- `SettingsScreen` shows results whenever the query has words, in both modes; the line that clears the text when Night Mode changes is removed, and the scroll to the Night Mode row is kept for the case with no search.
- Tokens only; no literal sizes or colors.
- The doc comments that say Settings has no search in Night Mode are updated, and BUILD-SPEC.md 3.10.

Acceptance:

- In Night Mode the Settings list shows the field; typing finds every row by title and keyword, as outside Night Mode.
- With the keyboard closed, the all-red pixel count is 0 on the Settings list with the field at rest, with text and results, and with no result.
- With the keyboard open, the count is 0 outside the keyboard's frame.
- Switching Night Mode with a search in progress keeps the text and the results.
- The accessibility audit passes with the field shown: default and largest text size, right to left, Increase Contrast.

UI tests: `testNightSearchFieldIsRed` (the three states above), `testNightSearchFindsByKeyword`, `testNightSearchCancelAndClear`, `testNightSearchKeptWhenNightModeChanges`, `testNightSearchAtLargestTextSize`, `testNightSearchRightToLeft`; `testSettingsRedesignInNightMode` is updated, since it expects no field.

## 9. Device checks

Before the wording ships, on an iPhone and an iPad:

1. The field, the cursor and the selection highlight are red; no glass, gray or white shows in or around the field.
2. The keyboard is the dark one. With autocorrection off, what remains in the bar above the keys.
3. Selection handles, the cursor magnifier and the edit menu: red, or dark and not red. If not red, wording 5 covers them ("menus").
4. Dictation and a hardware keyboard work in the field; Escape cancels the search.
5. Switching Night Mode with Settings open: the two fields' shapes and heights side by side; how far the list moves, if at all; no flicker; the popover-to-sheet change on iPad keeps the search.
6. VoiceOver with the system field and with the red field, side by side: names, traits, and what is said when results change. The same comparison for what scrolling the results and Return do to the keyboard.
7. The largest text size on the smallest iPhone: the field, Cancel under it, and at least one result visible above the keyboard.

## 10. Found while checking

Read from the code; not looked at on a device.

1. **Every Tag in Photo Details has a system search field too** (`PhotoDetailsTags.swift`, `.searchable`), with no Night Mode handling. If iOS draws it as it draws the Settings field, that page shows a gray field in Night Mode today. `NightSearchField` could replace it there in the same way (decision 9).
2. **The figure `settings-night` still draws a search field** in the old style, from before the field was hidden. It is redrawn with this design when it is accepted.

## 11. Decisions for the owner

| # | Decision | Recommendation | The other choice |
| --- | --- | --- | --- |
| 1 | Where the red field is used | Night Mode only. Outside it the system field stays, as the issue asks | The app's own field in every appearance: one field to test, but the system's look is lost in light and dark |
| 2 | The field's look | A capsule 44 pt high, black with a red outline; 2 pt outline and the cursor for focus | A filled dark-red box with no outline: closer to older iOS, but under 3:1 against the rows |
| 3 | The placeholder's color | The full red, like all night-mode text | A dimmer red: looks more like a placeholder, but is below 4.5:1 |
| 4 | Cancel | The word "Cancel" beside the field while searching; under the field at accessibility text sizes | No Cancel: Clear Text and the keyboard only. One target fewer, but no single way out of a search |
| 5 | The keyboard | Accept the system's dark keyboard, which is not red, and say so on the Accessibility page (wording 5) | Keep search hidden in Night Mode, so no keyboard opens from Settings |
| 6 | Autocorrection and suggestions in the red field | Off, so less of the screen is not red | On, as in the system field |
| 7 | Night Mode changes during a search | Keep the text and results; close the keyboard | Clear the search, as today |
| 8 | The field's VoiceOver name | "Search Settings", as the issue asks; the system field keeps the system's name | "Search" in both, so the two modes sound the same |
| 9 | Every Tag in Photo Details (section 10, item 1) | A device look first; if its field is not red, a separate issue that reuses `NightSearchField` | Do it in this change |
| 10 | Wording 5 on the Accessibility page | Add it | Leave it out; the keyboard is not mentioned anywhere today |
