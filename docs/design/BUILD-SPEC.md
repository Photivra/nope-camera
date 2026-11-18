# Build specification: direction B · Reach

Design version: 1.0.0 (2026-11-17; sections 3.14 and 3.15 added 2026-11-18). For the implementer of release 1.0.0 (issue 74, with issues 76, 77 and 80). Includes the Settings structure and the device coverage accepted on 2026-11-17; the decisions are recorded in [SETTINGS-PLAN.md](SETTINGS-PLAN.md).

This document says what to build, in which files, and how to tell it is done. The drawings are the mockups in this folder ([overview.html](overview.html)); each figure named below is `screens/<name>.html` with a PNG beside it. Tokens are in [tokens.md](tokens.md), accessibility in [ACCESSIBILITY.md](ACCESSIBILITY.md), paths in [navigation.md](navigation.md).

Bracketing on the drive strip is part of this plan (owner decision, 2026-11-18, all nineteen recommendations of [BRACKETING.md](BRACKETING.md), section 10): its section 7 is the build specification for 1.0.0, and sections 3.4, 3.5, 3.14, 3.15, 4, 6 and 7 below take its changes. Focus bracketing (its section 8) is for 1.1.0 and is not built in 1.0.0.

Also proposed and not yet part of this plan: the launch screen, specified in [LAUNCH-SCREEN.md](LAUNCH-SCREEN.md). It adds an asset catalog and Info.plist keys to the app target and changes the first frames of `CameraScreen` (3.8).

## 1. Ground rules

- **Scope.** 1.0.0 changes the interface of features that exist. Add no capability. If a step seems to need one, stop and flag it. One exception, by the owner's decision of 2026-11-18: the Last Photo viewer (3.14).
- **Architecture.** `NopeUI` reads state from `NopeCore` and sends intents. It holds no business rules. Everything here except section 6 is inside `NopeUI`, the app targets' views, and the string catalogs.
- **Native first.** `Menu`, `Toggle`, `Picker`, `Form`, sheets, popovers, `confirmationDialog`, `searchable`, `sensoryFeedback`. Custom drawing only for the shutter, viewfinder overlays, tiles, readouts and the drive strip.
- **Tokens only.** No literal spacing, radius, size, color or duration outside `DesignTokens.swift`.
- **Every string** goes in a catalog with a translator comment. Version 1.0.0 ships in English only (issue #86), so no translations are added. Honesty wording goes in `Honesty.xcstrings` and is a draft until reviewed.
- **Every screen and state** has a UI test with an accessibility audit; coverage of non-UI code stays at 100%.
- **Layouts.** The three arrangements and the rule that chooses them stay as they are (`CameraLayout.arrangement`): stacked, column, scrolling.
- **When the mockup and this text disagree, this text is right.** When this text and the code's existing behavior disagree on something not listed as a change, keep the behavior and flag it.

## 2. What changes, in one table

| Area | 0.3.0 | 1.0.0 |
| --- | --- | --- |
| Top bar | State pills, format chip, Settings button | Status line: format status leading, pills trailing. No Settings button (stacked and scrolling layouts) |
| Lens row | Lenses, then the "⋯" Quick Controls button | Manual Controls button, lenses, Switch Camera |
| Drive | A menu in the tray; Astro a separate tray switch | Drive strip of six words above the shutter |
| Shutter row | Last Photo, shutter, Switch Camera | Last Photo, shutter, Q |
| Quick controls | Sideways-scrolling tray that replaces the lens buttons | Q panel of tiles above the shutter row |
| Manual Controls | Settings switch; M pill turns it off | Camera button; Settings switch and M pill removed |
| Manual readouts | A row in the bands | A row on the lower edge of the picture |
| Mode feedback | Progress rows and AstroPanel at the top of the picture | Mode cards on the lower edge of the picture |
| Processed fallback | "No RAW on This Lens" chip | "Processed" marker, its note, a Settings switch |
| Settings | Opens from the gear | Opens from Q (gear kept in the column layout and before the camera is ready); search with keywords; five groups; Details in Each Photo and HEIF and JPEG Copies as merged pages; no conditional rows (3.10) |
| Face Detection | Switch and Shortcuts action of that name | Renamed Focus on Faces, switch and action |
| Focus Peaking | Pro Tools and Settings | Also a Q tile |
| Interval in Pro Tools | A section with its own Start | Removed; the drive strip is the one home |
| Bracketing | A Pro Tools section, only with Manual Controls on | Bracket on the drive strip, in full auto and with Manual Controls on, with a card and Bracket Settings ([BRACKETING.md](BRACKETING.md)) |
| Presets | Rename or Delete page (three levels) | More menu on each preset (two levels); delete asks first |
| Last Photo | A tap opens the Photos app; touch and hold opens a menu | A tap opens the Last Photo viewer inside the app, with Photo Details and Open in Photos (3.14); the menu is removed |

## 3. Screens

Each screen lists the component tree, the Swift files and types it maps to, what changes and what stays, the tokens, and the acceptance criteria. "AC" items are testable; "UI test" names the test to add or update.

### 3.1 Camera, stacked layout

Figures: `camera-auto`, `camera-manual`, `camera-small`, `camera-clean`, `camera-night`, `camera-bright`.

```
CameraReadyView (stacked)
├─ StatusLine                      new view in StatePills.swift        height NopeSize.statusRow
│  ├─ FormatStatus                 FormatChip.swift (FormatChip, restyled)
│  └─ StatePillRow                 StatePills.swift (kept; max 3, then +n)
├─ ViewfinderFrame (4:3)           CameraReadyView.swift (kept)
│  ├─ ViewfinderOverlays, FocusSquareLayer, FocusMagnifier, LiveAidsPanel   (kept, tokens only)
│  ├─ top stack: WarningChips, FailureBanner                               (kept, tokens only)
│  ├─ center: SessionStatusView, CountdownNumber                           (kept)
│  └─ bottom stack (new container `PictureBottomStack`, in CameraReadyView.swift), from the top:
│        CameraHints, ControlDial / AutoExposureDial, ModeCard, ManualReadoutRow
├─ LensRow                         LensRow.swift                        height NopeSize.lensRow
│  ├─ ManualControlsButton         new file ManualControlsButton.swift
│  ├─ LensButtons                  kept
│  └─ CameraFlipButton             kept; moves here from the shutter row
├─ DriveStrip                      new file DriveStrip.swift            height NopeSize.driveRow
└─ ShutterRow                                                           height ≥ NopeSize.shutterRowMin
   ├─ ThumbnailSlot                CaptureFeedback.swift (kept)
   ├─ ShutterButton                ShutterButton.swift (kept; two additions below)
   └─ QuickButton                  replaces QuickControlsButton in LensRow.swift
QuickPanel (overlay above the shutter row)   new file QuickPanel.swift
```

Change:
- `CameraReadyView.stacked`: new row order. Remove `SettingsButton` from the top bar in this layout. Remove the code path where the tray replaces the lens buttons.
- Margins: status line and lens row `NopeSpace.m`; shutter row `NopeSpace.xl`; items on the picture inset `NopeSpace.xs`.
- `bandsOverlayPicture` (small iPhones): the lens row and the drive strip overlay the lower edge of the picture on `NopeMaterial.rowOverlay`; the bottom stack sits above them.
- Sideways iPhone (`UprightUnit`): the status line's content moves onto the picture's top edge (as pills and the chip do today). `ManualControlsButton` shows "A" or "M" in a 44 pt circle. `DriveStrip` shows symbols, and the selected mode's name is a pill in the status content. `QuickPanel` opens upright over the trailing part of the picture, `NopeSize.panelMaxWidth` wide.
- Clean view: hides the lens row, the drive strip and Q; Last Photo becomes Show Controls (as today). The status line keeps only the Processed marker and the Light pill.

Keep: the viewfinder, gestures (`ViewfinderTouches`), `CameraLayout` rules, capture events, haptics, `ScreenAppearance`, `NightModeStyle`.

AC:
- In full auto with defaults, nothing is drawn on the picture.
- The shutter's center is on the screen's vertical center line; Last Photo and Q are the same distance from it.
- Every control has a 44 pt target; no two targets are closer than 8 pt (4 pt inside the lens group).
- On a 375 × 667 pt screen the rows overlay the picture and nothing is clipped.
- Audits pass in: default, night mode, sideways, the smallest iPhone, right to left.
- UI tests: update `testFullAutoDefaults…`, the landscape tests and the clean-view tests in `NopeAppUITests.swift`; "Quick Controls" becomes "Quick Menu"; add `testStackedLayoutRowOrder`.

### 3.2 Format status and the Processed marker

Figures: `camera-processed`, `camera-processed-hidden`, `camera-front`, `sheet-format`, `sheet-format-copy`, `sheet-processing-note`; `ipad-format`, `ipad-processing-note`, `duo-inner-format` (popovers).

Files: `FormatChip.swift` (`FormatChip`, `FormatDetailsSheet`), `FormatsSettingsView.swift`, `LensRow.swift` (the "No RAW" caption, kept).

Change:
- `FormatChip` loses its capsule fill in the status line: a symbol and words, `NopeFont.status`, 44 pt target. In the column layout and sideways it sits on the picture and keeps a `NopeMaterial.backing` capsule.
- Bayer RAW: teal seal, then the saved formats ("RAW", "RAW + HEIF"), as today.
- No Bayer RAW, marker shown: amber triangle and "Processed". VoiceOver value "Processed: no RAW on this lens", then the format.
- No Bayer RAW, marker hidden (`settings.showsProcessedMarker == false`): the format name with no symbol. Never the teal seal.
- `FormatDetailsSheet` on a lens without RAW shows the processing note first: the existing fallback sentence; "What the Phone Does on This Lens"; the per-lens distortion line only when `NopeCore` reports it for that lens; "What nope. Does"; then the formats list and the "Show Processed Marker" switch.
- `FormatDetailsSheet` gains a row "All Photo Settings", which closes the sheet and opens Settings at the Photos group (by the identifier of 3.10). Its Look row, shown while a HEIF or JPEG copy is on as today, opens the HEIF and JPEG Copies page (figure `sheet-format-copy`). The Show Processed Marker explanation has no default note.
- Sheet detents: medium and large, so the picture stays visible.

AC: the marker is visible before the shot on every lens without RAW, in every layout and in clean view; the note opens in one tap; the switch hides the marker but never the "No RAW" lens caption; audits pass at the largest text size, in night mode and right to left.
UI tests: update the no-RAW device tests; add `testProcessedMarkerAndNote`, `testProcessedMarkerSwitch`.

### 3.3 State pills and warnings

Figures: `camera-pills`, `camera-light`, `camera-flash`, `camera-warnings`, `camera-saved-unsigned`.

Files: `StatePills.swift`, `CameraWarnings.swift`, `ResourceWarnings.swift`.

Change:
- Remove three builders from `StatePills.builders`: Manual (the button shows it), Drive and Astro (the strip shows them). Their turn-off actions move to the button and the strip.
- `pillShape()` becomes `NopePillStyle`. Pills are trailing-aligned in the status line.
- "Not Signed": not shown when signing is off in Settings. Shown when signing is on and a photo could not be signed. This needs the owner's agreement (section 7); if it is refused, keep today's rule.

Keep: every other pill and its actions, the +n menu, the warning order, the chip popover, announcements.

AC: no pill duplicates what the strip or the Manual Controls button shows; the Light pill stays in clean view; audits pass with three pills and +n.

### 3.4 Manual Controls button, readouts and dials

Figures: `camera-manual`, `manual-iso`, `manual-shutter`, `manual-wb`, `manual-focus`, `manual-aperture`, `manual-more`, `manual-night`, `manual-pro-tools`, `camera-exposure`.

Files: new `ManualControlsButton.swift`; `ManualControlsView.swift` (`ManualReadoutRow`, `ManualOptionsMenu`, `ControlReadout`); `ControlDial.swift`; `ManualControlsList.swift`; `ProToolsSheet.swift`; `FocusAids.swift` (`AutoExposureDial`); `SettingsScreen.swift` (remove the switch).

Change:
- `ManualControlsButton`: `NopeCapsuleStyle(isSelected: manual.isEnabled)`, the slider symbol and "Auto" or "Manual". One tap switches. Label "Manual Controls", value On or Off. Shown whenever controls are shown; hidden in clean view (issue 77). It calls the same intent the Settings switch calls today (`settings.setShowsManualControls`), which the app forwards to `.manual(.setEnabled)`. See section 6, item 5.
- `ManualReadoutRow` moves into the picture's bottom stack: six `NopeTileStyle` readouts of equal width and the More button (44 pt), `NopeSpace.xxs` apart, height `NopeSize.readout`. Each readout: the mode letter on top ("M" in a filled badge, "A" plain), the value below. The open readout is filled white.
- `ControlDial` and `AutoExposureDial`: `NopeRadius.large`, `NopeMaterial.backing`, placed directly above the readout row (or alone on the lower edge in full auto). Content unchanged: name, value, meter, Decrease, slider, Increase, Auto, the range line, the notes; white balance keeps Tint and Presets.
- While a series runs (burst, interval, Astro, a countdown) the readout row and any dial are hidden.
- `ProToolsSheet`: remove the Interval Shooting section (Interval, Photos, Start) and its `IntervalProgressView` use; the drive strip and its card are the one home of Interval. The sheet keeps exposure mode, metering, the two locks and Live Aids. The Bracketing section is removed too: Bracket on the drive strip is its one home ([BRACKETING.md](BRACKETING.md), figure `bracket-pro-tools`). Otherwise tokens only. It stays a full-screen cover in every window.
- Remove the Manual Controls row from Settings › Camera, and the first-row test expectations for it.

AC: Pro Tools has no control that starts or sets up an interval series, and no bracketing control; one tap turns manual on and one tap turns it off, from full auto and from manual; the button is absent in clean view; VoiceOver reads "Manual Controls, On"; each readout is adjustable with VoiceOver without opening the dial; presets and shortcuts still set manual as before.
UI tests: `testManualControlsButtonInAuto`, `testManualControlsButtonInManual`, `testCleanViewHidesManualControlsButton`; update every test that turned manual on through Settings.

### 3.5 Drive strip and mode cards

Figures: every `drive-*` figure; `landscape-manual`, `landscape-astro`.

Files: new `DriveStrip.swift`; `DriveControls.swift` (`DriveProgressView`, `CountdownNumber`, `DriveText`); `IntervalControls.swift`; `AstroControls.swift` (`AstroPanel`, `AstroSheet`); `ProToolsSheet.swift` (`IntervalProgressView`, which moves to `DriveControls.swift` in chunk D when chunk F removes the Interval section); `SeriesScreen.swift`; `ShutterButton.swift`.

`DriveStrip`:
- Six words: Single, Timer, Burst, Bracket, Interval, Astro. `NopeCapsuleStyle(isSelected:)` at `NopeSize.driveWord`, target 44 pt, `NopeFont.status`. Exactly one is selected.
- Mapping to existing intents: Single → `DriveMode.single`; Timer → `.timer(delay)`, where `delay` is the last delay chosen in this session, 3 seconds at first; Burst → `.burst`; Interval → `.interval`; Astro → the existing Astro on intent. Choosing any other word while Astro is on turns Astro off first, then sets the mode. Astro is offered only where `canUseAstro` is true or Astro is on. Bracket → `.manual(.setBracket(bracketToTurnOn))`, then `bracketDriveMode` (Single, or `.timer(delay)` for its start delay); it is selected while `isBracketOn`, Timer is then not shown selected, and choosing any other word sends `.manual(.setBracket(nil))` first. Bracket is offered where `manual.bracketFrameCounts` is not empty or a bracket is on ([BRACKETING.md](BRACKETING.md), section 7).
- Tapping the selected word: Timer opens a `Menu` (3 seconds, 10 seconds); Burst opens a `Menu` of speeds (Fast, Slow); Bracket opens `BracketSheet`; Interval opens `IntervalSheet`; Astro opens `AstroSheet`; Single does nothing.
- Burst: the shutter, the cards, the speed and the accessibility rules are specified in [BURST.md](BURST.md) (accepted 2026-11-18), which replaces the Burst parts of this section.
- Choosing Interval no longer opens the sheet by itself; the card shows the series and the shutter starts it.
- Fit: `ViewThatFits` with word padding `NopeSpace.s`, then `NopeSpace.xs`, then a horizontal `ScrollView` that keeps the selected word visible. At the default text size all eleven languages fit at `NopeSpace.xs` (figure `drive-strip-languages`).
- While the drive is busy the other words are disabled at 0.4 opacity.
- Sideways: symbols only (`square`, `clock`, `square.stack.3d.down.right`, `square.3.layers.3d`, `timer`, `moon.stars`), with Large Content Viewer labels.
- Column layout: the strip sits in a `NopeMaterial.backing` capsule on the lower edge of the picture.
- `.sensoryFeedback(.selection)` on change; VoiceOver announces the new mode.

Mode cards (one view, `ModeCard`, in `DriveControls.swift`, used by all modes; `NopeRadius.large`, `NopeMaterial.backing`):

| Mode | Idle | Running | Paused or ended |
| --- | --- | --- | --- |
| Single | none | none | none |
| Timer | none; the shutter shows "3" or "10" | Countdown number in the picture; "Photo in 3s" and Cancel Timer | none |
| Burst | "Fast burst", "Hold the shutter. A tap takes one photo." and Start Burst | "Photos taken: 12", the measured rate, and "Release to stop" or Stop Burst | "Saving: 9 of 12 photos saved", then the summary until the next action ([BURST.md](BURST.md)) |
| Bracket | "Exposure bracket: 3 frames, 1 EV apart" and "−1, 0, +1 EV" (with a delay, "· after 3 seconds"); the whole card is the button Bracket Settings | "Bracket in 3s" and Cancel during a start delay; "Taking 3 frames"; "Saving: 2 of 3 photos saved", progress bar; no Stop | "3 photos saved" until the next action; a frame not saved: the banner "Bracket stopped: 2 of 3 photos saved." with the reason |
| Interval | "Every 10 seconds, 10 photos", or with Stop After: Time "Every 10 seconds, for 1 hour, 30 minutes" (with "Choose an interval shorter than the time." while it isn't); the whole card is the button Interval Settings | "3 of 10 photos taken", progress bar, Stop; for a time, "12 photos taken · 1 hr, 12 min left", progress bar by time, Stop (figure `drive-interval-time-running`) | "Paused: 3 of 10 photos taken", Stop; for a time, "Paused: 12 photos taken · 1 hr, 12 min left" and "Ends at 9:41 PM", Stop |
| Astro | "Astro frames: 20" and "After 10 seconds · 20 s in all · at most 486 MB"; the whole card is the button Astro Settings | Countdown, then "Frame 7 of 20", progress bar, Stop Frames | "Paused: 7 of 20 frames", Stop Frames |

- `AstroPanel`, `DriveProgressView` and `IntervalProgressView` become uses of `ModeCard` and move from the top of the picture to the bottom stack.
- `ShutterButton`: while a series or countdown runs, the disc is a stop square; with Timer selected and idle, the disc shows the delay in black. Its label stays "Take Photo"; the value says the mode.
- `IntervalSheet` and `AstroSheet`: content unchanged; medium and large detents. Added on 2026-11-18 (owner decision): Interval Settings' Stop After picker, Number of Photos (the default) or Time, with Hours and Minutes and "At most N" photos (figure `sheet-interval-time`).
- Astro keeps today's behavior: it turns on Manual Controls and night mode, and hides the Light tile. Leaving Astro turns each off again only if Astro turned it on (owner decision, 2026-11-18): night mode the person had on, or changed while Astro was on, stays as it is, and Keep Night Mode After Astro (Settings › Screen, off by default) keeps it on.

AC: each mode is one tap from the default screen; the mode's name is always visible; an idle Astro screen covers no more than a quarter of the picture and a running one no more than a sixth; no white element appears at any point in Astro with night mode on; the strip never truncates a word in any launch language.
UI tests: `testDriveStripSelectsEachMode`, `testTimerDelayMenu`, `testIntervalCardOpensSettings`, `testAstroFromStrip`; update the self-timer, burst, interval and `AstroUITests` flows that used the tray; pseudo-language test for the strip.

### 3.6 Q

Figures: every `q-*` figure; `landscape-q`, `ipad-q`, `ipad-portrait-q`, `ipad-q-manual`, `ipad-q-menu`, `ipad-q-night`, `ipad-rtl-q`, `ipad-ax-q`, `duo-outer-q`, `duo-inner-q`, `ax-q`, `rtl-q`.

Files: `QuickControls.swift` (`QuickControlItem`, `QuickControls.builders`, `QuickControlsTray`, `QuickControlButton`, `WrappingRows`); new `QuickPanel.swift`; `LensRow.swift` (`QuickControlsButton` → `QuickButton`).

Change:
- `QuickButton`: `NopeIconButtonStyle(size: NopeSize.quick)`, the letter Q in `NopeFont.q`; filled white while the panel is open. Label "Quick Menu".
- `QuickPanel` replaces `QuickControlsTray`: a `LazyVGrid` of three flexible columns, gap `NopeSpace.xs`, padding `NopeSpace.m`, `NopeRadius.large`, `NopeMaterial.backing`. In the stacked layout it spans the width less `NopeSpace.xs` each side, its bottom `NopeSpace.xs` above the shutter row, and it covers the lens row and the drive strip. If it would be taller than the space up to the status line, it scrolls.
- Tile (`NopeTileStyle`): the name on top (`NopeFont.tileName`, up to two lines), then the symbol and the value (`NopeFont.tileValue`). Minimum height `NopeSize.tileMin`. On: filled white.
- `QuickControlItem` keeps its three kinds. `.toggle` → a tile button; `.menu` → a tile `Menu`; `.button` → a tile button that closes the panel.
- `QuickControls.builders` order: Flash, Light, Exposure, Close-Up, Far Focus, Fast Shutter, Magnify, Focus Peaking, Grid, Level, Readout, Night Mode, Compare, Presets. Remove Drive, Astro and Hide Controls from the list.
- Focus Peaking is a new `.toggle` item for the existing switch (`OverlayOptions`, the value Settings › Viewfinder Overlays and Pro Tools change). It is shown in full auto and with manual on. Its builder lives in `OverlaySettingsView.swift` beside the Grid and Level builders (chunk G owns the file; chunk B consumes it). No new stored value. Each builder's existing visibility rule stays (for example Far Focus only with manual on; Exposure and Fast Shutter only in full auto).
- Foot: two `NopeCapsuleStyle` buttons at `capsuleLarge`: Hide Controls, Settings. `ViewThatFits`: side by side, else stacked.
- Values shown: Flash Off/Auto/On; Light Off or its percentage; Exposure as a number; Close-Up, Far Focus, Magnify, Focus Peaking, Level, Night Mode, Compare On/Off; Fast Shutter Standard, 1/500, 1/1000; Grid Off or the style; Readout Off, On, Pinned; Presets "n Saved" or "None Saved".
- Closing: Q again, the shutter, a lens, the picture, Escape, a `.button` tile, Exposure, Settings, Hide Controls.
- Scrolling layout: Q presents the same items as a full-height list (`List`), one row per tile, with a Done button.
- No editing or reordering of tiles.

AC: every tile is reachable in two taps from the default screen; the shutter row is never covered; with four rows of tiles (twelve or fewer) the panel covers less than half the picture on a 402 × 874 pt screen, and with all thirteen (five rows) no more than 58%, with the status line and the shutter row clear; a tile's name is never truncated in any launch language; focus moves into the panel on open and back to Q on close.
UI tests: replace the tray tests with `testQuickMenuTiles`, `testQuickMenuTogglesStayOpen`, `testQuickMenuMenuTile`, `testQuickMenuLargestText`, `testQuickMenuRightToLeft`, `testQuickMenuNightMode`.

### 3.7 Capture feedback, hints and pause messages

Figures: `camera-capturing`, `camera-saved-signed`, `camera-saved-unsigned`, `camera-failure`, `camera-failure-photos`, `camera-paused`, `camera-first-photo`, `camera-closeup`, `camera-too-close`, `camera-focus-lock`, `camera-overlays`. The Last Photo button opens the viewer of 3.14.

Files: `CaptureFeedback.swift`, `SessionStatusView.swift`, `FocusAids.swift`, `LiveAidsPanel.swift`, `ViewfinderOverlays.swift`.

Change: tokens only, plus two placements. `CameraHints` and `CloseUpSuggestion` move to the bottom stack. The thumbnail badge is not drawn when signing is off in Settings (see 3.3). All sentences stay as they are.

AC: a failure stays until dismissed; each failure offers its one action; audits pass for each state.

### 3.8 Before the camera is ready

Figures: `first-run`, `first-run-light`, `permission-camera`, `permission-photos`, `permission-location`, `camera-denied`, `camera-unavailable`, `camera-starting`.

Files: `FirstRunView.swift`, `StatusMessageView.swift`, `CameraScreen.swift`.

Change: Continue and Open Settings become `.borderedProminent`, large, full width at the bottom; spacing tokens. The second first-run statement is reworded for signing off by default (draft; see section 5). The Settings button stays on these screens.

AC: the explanation precedes the system prompt; audits pass in light, dark, largest text and right to left.

### 3.9 Sheets

Figures: `sheet-interval`, `sheet-interval-time`, `sheet-astro`, `sheet-presets`, `sheet-presets-applied`, `sheet-preset-save`, `sheet-preset-delete`, `sheet-compare`.

Files: `PresetsScreen.swift`, `ComparisonScreen.swift`.

Change:
- `PhotoDetailsSheet`: redesigned; see 3.15.
- `PresetsScreen`: each saved preset row gets a trailing `Menu` ("More for NAME": Rename, Delete), and the same two as swipe and VoiceOver actions. Rename pushes the existing Rename Preset page, without its Delete button. Remove the Rename or Delete page. Delete presents a `confirmationDialog`: title "Delete “NAME”?", message "Deleting a preset doesn't change your current settings.", buttons Delete Preset (destructive) and Cancel.
- `ComparisonScreen`: tokens and button types only.

AC: no page is more than two levels below Settings; deleting a preset needs a confirmation and Cancel leaves it; Factory Defaults still applies at once with Undo.
UI tests: update `PresetsUITests` (rename and delete paths), add `testDeletePresetAsksFirst`.

### 3.10 Settings

Figures: every `settings-*` figure; `ipad-settings`, `ipad-portrait-settings`, `ipad-settings-page`, `ipad-settings-search`, `ipad-settings-light`, `ipad-settings-night`, `ipad-settings-night-on`, `ipad-ax-settings`, `ipad-rtl-settings`, `ipad-split-half-settings`, `ipad-stage-small-settings`, `duo-outer-settings`, `duo-inner-settings`, `duo-fold-settings-unfold`, `duo-fold-settings-fold`, `landscape-settings`, `lock-settings`. The tree is in [settings-tree.html](settings-tree.html).

Files: `SettingsScreen.swift`, new `SettingsSearch.swift`, `FormatsSettingsView.swift`, new `CopiesSettingsView.swift` (replaces `LookSettingsView.swift` and `FileOptionsSettingsView.swift`, which are deleted), `PhotoSizeSettingsView.swift`, `PrivacySettingsView.swift`, `OverlaySettingsView.swift`, `AccessibilitySettingsView.swift`, `HonestyScreen.swift`, `AboutScreen.swift`, `ExplainedToggle.swift`, `CameraScreen.swift` (presentation).

Root, in order. A row is shown or not by the device only; no row appears or disappears when a setting changes.

| Section | Rows | Kind | Value shown on the row |
| --- | --- | --- | --- |
| (none) | Presets | Page | "%lld Saved" or "None Saved". Always shown |
| Photos | Formats | Page | The saved formats, for example "RAW (DNG)" |
| | HEIF and JPEG Copies | Page | The look ("Standard", "Flat") while a copy is saved; "Not Saved" otherwise. Always shown |
| | Photo Size | Page | "Default" or "Custom". When a lens offers sizes |
| | Mirror Front Camera | Switch | When there is a front camera |
| Privacy | Details in Each Photo | Page | "All Optional Removed", "Custom", or "Custom, Location On" |
| | Sign Each Photo | Switch | |
| Camera | Fast Shutter | Page | Its value |
| | Focus on Faces | Switch | |
| Screen | Start in Clean View | Switch | |
| | Viewfinder Overlays | Page | "Off"; the names when one or two are on ("Grid, Level"); a count from three ("3 On") |
| | Show Processed Marker | Switch | When the device has a lens without RAW |
| | Night Mode | Switch | |
| | Keep Night Mode After Astro | Switch | Where the device offers Astro (added 2026-11-18) |
| | Red Viewfinder | Switch | Always shown, whether Night Mode is on or off |
| | Live Activity | Switch | Where the device offers it |
| More | Accessibility; Honesty; About and Licenses | Pages | |

Change:
- Remove the Manual Controls switch and the Remove All Optional Details switch from the root. Add Show Processed Marker. Regroup as in the table: Mirror Front Camera moves to Photos; Start in Clean View, Viewfinder Overlays and Show Processed Marker move to the new Screen section with Night Mode, Red Viewfinder and Live Activity; Camera keeps Fast Shutter and Focus on Faces.
- Rename Face Detection to Focus on Faces: the row title and its string. The stored value (`followsFaces`) and its intent are unchanged. The Shortcuts action is renamed with it; that is outside `NopeUI` (section 6, item 9).
- Presets is always shown. Remove the condition on saved presets, if any remains.
- Red Viewfinder is always shown. Remove its condition on Night Mode. Its explanation begins "In Night Mode,".
- **Details in Each Photo** (`PrivacySettingsView`, figures `settings-details`, `settings-details-default`, `settings-location-denied`, `settings-details-largest`): retitled from Choose Details. Sections in order: Remove All Optional Details with its explanation; "Location" (the Location switch, with the access notice and Open Settings under it when access is refused); "Other Details" (the eleven other switches); Standard File Tags; Always Saved. The header "In Each Photo" is replaced by the two headers. `PrivacySettingsView.summary(of:)` gains the third value, "Custom, Location On".
- **HEIF and JPEG Copies** (`CopiesSettingsView`, figures `settings-copies`, `settings-copies-none`): one page. Sections in order: when no HEIF or JPEG copy is saved, one row of text, "No HEIF or JPEG copy is saved now. Turn one on in Formats."; "Look" (Standard, Flat, each with its sentence); "Files" (HEIF Compression, HEIF Bit Depth, JPEG Compression, Color Space, Copy Size, each a `Picker` shown as a menu on its row); Restore Defaults (when anything is changed), with the footer "This changes only the HEIF and JPEG copies. The RAW is never changed." Every control stays enabled when no copy is saved. Restore Defaults keeps its present scope (the five file settings).
- Values wrap: a value that does not fit beside its title is laid out under it at every text size (`ViewThatFits`, or `LabeledContent` with a custom style), not only at accessibility sizes (figures `settings-root`, `settings-long-language`).
- Explanations: one sentence on the root, two where issue 80 or honesty needs it; no "by default" notes anywhere in Settings or on the processing note. The sentences are in section 4 and are drafts (section 5). The dimming advice leaves the Night Mode explanation and becomes a Night Mode entry on the Accessibility page.
- Every explained switch uses `ExplainedToggle`.
- Search: `.searchable` on the root. `SettingsSearch` holds a static index with three kinds of entry:
  1. one per setting on any page: its localized title, its keywords, its page path, and its destination;
  2. keywords, as localized strings beside each title (section 4), matched like the title;
  3. pointers to the camera for controls that are not in Settings: Manual Controls, Self-Timer, Burst, Interval Shooting, Astro, Flash, Light, Exposure, Close-Up, Far Focus, Magnify, Grid, Level, Compare. A pointer shows the control's name and where it is, in words, under a header "On the Camera", with a camera symbol and no chevron; it is not a button and does not navigate (figure `settings-search-camera`).
  In Night Mode Settings has no search field (owner decision, 2026-11-18): iOS draws the field as gray glass outside the app's views, where the red filter can't reach it; every row stays reachable from the list, and the field returns when Night Mode is off.
  Results replace the list while searching; choosing a setting pushes its page. No match shows `ContentUnavailableView.search` (figure `settings-search-empty`). Page paths are whole localized names, joined by a localized format, never built from fragments.
- Identifiers: one stable identifier for each page and each row (an enum in `SettingsSearch.swift`, for example `.photos`, `.copies`, `.details`, `.detailsLocation`). Search uses them as destinations; `FormatDetailsSheet`'s All Photo Settings opens `.photos` and its Look row opens `.copies`; the Location warning's explanation opens `.details`. They are also the accessibility identifiers of the rows, and leave room for links into Settings later (issue 82). Not a URL scheme in 1.0.0.
- Presentation: sheet in compact width, popover (480 × 720 at most, single column) in regular width in both orientations, sheet in night mode, as today. In the stacked and scrolling layouts it is presented from Q's Settings button; in the column layout from the Settings button in the column. No split view. The style chosen when Settings opens is kept until it closes (`AdaptivePresentation`, unchanged): through rotation, resizing, a fold, and Night Mode turned on inside it (figures `ipad-settings-night-on`, `duo-fold-settings-unfold`, `duo-fold-settings-fold`).
- Lock Screen camera: Settings is offered as today, with every row; changes last until the extension closes (figure `lock-settings`). No change in 1.0.0.
- Viewfinder Overlays: Grid Style lists Thirds, 4 × 4, Square; remove Turn Spiral (issue 76).
- Accessibility page: the Self-Timer and Burst text names the drive strip; the Night Mode entry is added.
- Honesty: the entries of section 5.
- Night mode: `NightModeSwitchStyle` draws on as filled with a dark knob and off as an outline.

AC:
- `auditSettingsScreens` passes on every page in light, dark and night mode, at the largest text size and right to left.
- The root has the rows of the table in that order, and toggling any switch on the root or on a page does not change the number of rows on the root.
- Remove All Optional Details exists once, on Details in Each Photo; the root row's value changes with it and with Location.
- HEIF and JPEG Copies opens and is editable with RAW only saved.
- Search finds every row of every page by its title and by each of its keywords, in every launch language; "manual" shows the pointer and no result navigates to a missing page; a search with no match shows the system's empty state.
- No value or title is truncated in any launch language at the default size or the largest size.
- The popover on iPad follows the system appearance while it is open (a 0.3.0 finding: it follows only when it opens).
- VoiceOver reads a page row as title, value, "button" ("Details in Each Photo, All Optional Removed, button").

UI tests: update `auditSettingsScreens` for the new order and pages; add `testSettingsRootRowsDoNotChange`, `testDetailsInEachPhotoPage`, `testCopiesPageWithRAWOnly`, `testSettingsSearchFindsLocationByKeyword`, `testSettingsSearchPointsToCamera`, `testSettingsSearchNoResults`, `testShowProcessedMarkerSwitch`, `testRedViewfinderAlwaysShown`; update `CaptureSettingsUITests` for Focus on Faces; remove the Golden Spiral tests.

### 3.11 Column layout (iPad, iPhone Duo inner display)

Figures: every `ipad-*` figure ([ipad.html](ipad.html)) and every `duo-*` figure ([duo.html](duo.html)). The rule for which screens are drawn per device, and what applies to the rest, is in [layouts.html](layouts.html).

Files: `CameraReadyView.swift` (`column`), `CameraLayout.swift`.

- Trailing column, `NopeSize.column` wide, top to bottom: Settings, lenses (vertical), Manual Controls button; then Q, shutter, Last Photo, vertically centered on the shutter; Switch Camera at the bottom.
- On the picture: format status (with backing) and warnings at the top leading corner, pills at the top trailing corner; at the bottom, centered and at most 480 pt wide: dial, mode card, readout row, drive strip.
- `QuickPanel`: `NopeSize.panelMaxWidth` wide, beside the column, bottom-aligned near Q.
- A window taller than wide shows the picture 3:4 and a wider one 4:3 (`CameraLayout.pictureAspectRatio`, unchanged); the column is on the trailing edge in both.
- Clean view in the column: only the shutter and Show Controls remain in the column.
- Presentations in a regular-width window: Settings, Photo Format and the processing note are popovers (sheets in night mode); What's in This Photo, Interval Settings, Astro Settings and Presets are centered sheets; Pro Tools and Compare cover the window; the delete confirmation is a popover anchored to the preset's More button (`confirmationDialog` does this by itself).
- Compact-width windows on iPad (Split View at half or less, Slide Over) use the stacked layout, with the rows over the picture when the window is too short (`bandsOverlayPicture`), and sheets. A window wider than tall uses the column layout whatever its size; a popover taller than the window is shortened by the system and scrolls.
- The iPhone Duo inner display uses this layout through the existing size-class rule, in both orientations; the outer display uses the stacked layout with the rows over the picture (382 × 644 pt for the app). No posture handling is added: half-open shows the column layout unchanged (`duo-half-open`).
- Folding and unfolding (the `duo-fold-*` pairs): nothing new is built. The pairs state the expected result of existing behavior: the camera model keeps its state, the layout follows the new window, and a presentation keeps its style. They are a manual test list (docs/TESTING.md, iPhone Duo), because a UI test cannot fold the device.
- iPhone sideways with a sheet open (`landscape-sheet`, `landscape-settings`): the sheet rotates, and the camera behind it is in the column layout while it is open, as today.

AC: audits pass on iPad in both orientations, in split view at half and one third, in a window wider than tall and shorter than the Settings popover, and right to left (the 0.3.0 finding on pill contrast in right-to-left on iPad must pass: pills on the picture always have the backing).

### 3.12 Scrolling layout (accessibility text sizes)

Figures: `ax-camera`, `ax-q`, `ipad-ax-camera`, `ipad-ax-q`, `ipad-ax-settings`, `duo-inner-ax`, `settings-largest`, `settings-details-largest`.

Files: `CameraReadyView.swift` (`scrolling`), `ManualControlsList.swift`.

The scrolling layout is the same in every window. It has no Settings button; Settings opens from the Settings row that ends the Q list, as a popover in a regular-width window and a sheet otherwise.

Order: format status; pills; warnings; the 280 pt picture; mode card; a "Manual Controls" row (toggle); one row per lens; one row per drive mode (selected filled); the manual controls list when manual is on. Pinned below: Last Photo, shutter, Q (Q and Last Photo at 64 pt).

AC: `auditScrollingScreen` passes; nothing essential is truncated at the largest size in any launch language. Not specified: the scrolling layout on an iPhone held sideways; check it on a device and record the result before release.

### 3.13 Live Activity, controls and Apple Watch

Figures: `live-activity-lock`, `live-activity-night`, `live-activity-island`, `controls`, `siri-results`, every `watch-*` figure.

Files: `App/Shared/SeriesActivity.swift`, `App/NopeControls/*.swift`, `App/NopeWatch/RemoteShutterView.swift`, `App/NopeWatch/WatchText.swift`.

Change: spacing, radius and type tokens only. The watch figures cover every status and result string in `WatchText.swift`, the 40 mm and 49 mm cases, the largest text size, right to left, German and Always On; none needs new code, and [watch.html](watch.html) states what the watch app does not have. On iPad the Live Activity shows on the Lock Screen only (`ipad-live-activity`). On the watch, the result "Saved, not signed" is plain (primary color, info symbol) when signing is off in Settings; it needs the phone to say why the photo is unsigned, see section 6, item 6. Until then keep today's styling.

AC: `LiveActivityUITests` and `NopeWatchUITests` pass their audits, the watch ones at 40 mm and at the largest text size; the largest Live Activity row is no taller than today. To check by hand: the watch countdown in Always On.

### 3.14 Last Photo viewer (owner decision, 2026-11-18)

Figures: every `viewer-*` figure ([viewer.html](viewer.html)); `ipad-viewer`, `ipad-viewer-portrait`, `ipad-viewer-fallback`, `duo-inner-viewer`, `duo-fold-viewer`. The Last Photo menu figures are removed.

A tap on Last Photo opens the viewer in place of the Photos app. This is the one capability added in 1.0.0. The data it shows is specified separately (the session's photos and their previews); this section assumes, for each photo saved since the app opened, its `SavedPhoto`, the lens, the time taken, and a screen-size preview that is either held in memory or already released. Names below that belong to that data are placeholders until its specification lands.

Rules that come from `AGENTS.md` (Photos never linger): the viewer shows only what is in memory; it writes nothing to disk, logs nothing, and caches no decoded picture beyond the page shown and its two neighbors. Its contents are hidden while the scene is not active, as in `ComparisonScreen`, so the app switcher's snapshot holds no photo. It closes when the app goes to the background.

Component tree, new file `Sources/NopeUI/PhotoViewer.swift`:

| Component | Maps to | Notes |
| --- | --- | --- |
| `PhotoViewerCover` (modifier) | Modeled on `ComparisonCover` in `ComparisonScreen.swift` | `fullScreenCover` in every window, with `.nightModeStyle(isNightMode)`. Opens from the thumbnail with the system zoom transition (`matchedTransitionSource` on `ThumbnailSlot`, `navigationTransition(.zoom)` on the cover), which also gives the swipe down to close and the Reduce Motion crossfade. If the system transition cannot be used on a cover, use `NopeMotion.panel` for the frame and `NopeMotion.fade` for the rows, opacity only with Reduce Motion. Posts `ScreenChanged` on dismissal and returns focus to Last Photo |
| `PhotoViewerScreen` | New | Chooses the arrangement with the existing rule (`CameraLayout.arrangement`): stacked, column, or scrolling at accessibility text sizes. Holds the page shown, whether the controls are hidden, and whether a newer photo is waiting |
| `PhotoViewerPager` | New; a paging `ScrollView` (`scrollTargetBehavior(.paging)`) | One page for each saved photo, oldest first; opens on the newest. `NopeSpace.m` between pages. Follows the layout direction |
| `PhotoViewerPage` | New | The preview, aspect fit, with pinch, double tap and drag. Zoom from fit up to the preview's own pixels, and at least 2 × fit. Not mirrored right to left. `accessibilityIgnoresInvertColors()` |
| `PhotoViewerFallback` | New | When the preview is released: the thumbnail no larger than `NopeSize.viewerFallback` and never above twice its pixel size, `NopeRadius.small`, the thumbnail's ring; then the title and sentence of section 4. No zoom |
| `PhotoViewerStatus` | Reuses the look of `FormatStatus` (`FormatChip.swift`) and the rules of `ThumbnailSlot.badge(for:)` | Formats from `SavedPhoto.formats`; the Processed marker from `isProcessedFallback`; Signed, Not signed (warning) or Not signed (plain) from `signature`. `NopeFont.status`; `CameraStyle.fact` and `CameraStyle.warning`, each with its symbol and words |
| `PhotoViewerCaption` | New | Position (only with more than one photo), lens label as in `LensRow`, time taken with the system's short time style. `NopeFont.pill`, `NopeColor.labelSecondary`, monospaced digits |
| `PhotoViewerActions` | `NopeIconButtonStyle(size: NopeSize.thumbnail)` for Close; `NopeCapsuleStyle(isCompact: true)` for the two actions | Stacked: Close leading in the shutter row's place (`NopeSpace.xl` side margin), the actions trailing; they stack when they do not fit. Column: 44 pt icon buttons with their names below (`NopeFont.tileName`), then Close, centered in the `NopeSize.column` column. Scrolling: three full-width rows. Open in Photos is left out when `openPhotosApp` is `nil` (the Lock Screen camera) |
| Hint, New Photo, Photo Not Saved | `CameraHints` look; `NopeCapsuleStyle(isCompact: true)` on `NopeMaterial.backing`; `WarningChip` | On the photo's lower edge (hint, New Photo) and top edge (chip), only while they apply |

Changes to existing files:

- `CaptureFeedback.swift` (`ThumbnailSlot`): the tap opens the viewer. Remove the `contextMenu`; keep Open in Photos and Photo Details as accessibility actions. The comment about the Large Content Viewer and the long press no longer applies.
- `CameraReadyView.swift`: present the cover; pass the session's photos; the Photo Details sheet is presented from the viewer for the photo shown (it is still presented from the camera for the accessibility action).
- `PhotoDetailsSheet.swift`: take the photo to show first, so the sheet opens on the viewer's photo. Its redesign is 3.15.
- `CameraEnvironment.swift`, `docs/BUILDING-AN-INTERFACE.md`, `docs/PRIVACY.md`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`: the text that says a tap opens Photos.

Behavior:

- The camera keeps running under the viewer, as under a sheet: a running series continues, and Apple Watch and Siri can take photos. `canCapture` is not changed.
- A new photo while the viewer is open is added as the last page. The page shown does not change. New Photo appears until the newest page is shown. The save sentence is announced as today.
- A failure while the viewer is open shows the Photo Not Saved chip and is announced as today. The chip closes the viewer; the failure banner is on the camera.
- Hardware shutter (volume buttons, Camera Control) and Take Photo (Space with nothing focused): recommended to close the viewer and take no photo (section 7). This needs the camera model to know the viewer is open, as it knows the compare view is; that is core work and belongs to the data specification.
- Fold, unfold, rotate, resize: the viewer stays open on the same photo, zoom returns to fit, and the arrangement follows the window.
- Night mode: everything is red on black, the photo included, so the all-red check of the night-mode tests holds on this screen with no exception.

Tokens: `NopeSpace.m`, `xl`, `xs`; `NopeRadius.small`; `NopeSize.thumbnail`, `iconButton`, `capsule`, `column`, `statusRow`, `driveRow`, `shutterRowMin`, `scrollingPicture`, and the new `viewerFallback` (160); `NopeFont.status`, `pill`, `tileName`; `NopeColor.fact`, `warning`, `label`, `labelSecondary`; `NopeMaterial.backing`; `NopeMotion.panel`, `fade`. No literal values.

AC:

- A tap on Last Photo opens the viewer on the newest photo; it never opens another app. Close, a swipe down, Escape and the two-finger scrub close it, and focus returns to Last Photo.
- The status line shows only facts from the saved photo. Teal appears only with Signed; amber only with Processed or a failed signature, each with its symbol and words.
- Each saved photo of the session is one page, a bracket's frames included. The position is correct after a photo arrives while the viewer is open, and the page shown does not change.
- A bracket's frame shows the chip "Exposure bracket · frame 2 of 3 · 0 EV" on the photo's lower edge (`BracketChip` in `BracketControls.swift`, from `SavedPhoto.bracket`); it hides with the other controls, and the page's VoiceOver label adds "Exposure bracket, frame 2 of 3, 0 EV." ([BRACKETING.md](BRACKETING.md), figure `bracket-viewer`).
- A zoomed photo shows the preview hint whenever the preview has fewer pixels than the saved photo. No picture is drawn above the zoom limit.
- A photo whose preview is released shows the fallback, never an enlarged thumbnail filling the screen.
- Nothing is written to disk; the snapshot taken when the app leaves the screen shows no photo; after the app returns from the background the viewer is closed.
- Every gesture has the other way listed in ACCESSIBILITY.md. Every target is at least 44 pt.
- In night mode no pixel on the screen is non-red. With Reduce Motion nothing moves or scales.
- The Lock Screen camera's viewer has no Open in Photos.

UI tests, in a new `PhotoViewerUITests.swift` (an extension of `NopeAppUITests`), each with `performAccessibilityAudit()` through the existing helpers:

| Test | Covers |
| --- | --- |
| `testViewerOpensFromLastPhoto` | One photo; the status and caption; Close returns focus to Last Photo; Photos is not brought to the front |
| `testViewerPagesThroughSessionPhotos` | Three photos; swipe, the adjustable action and the arrow keys; the position text |
| `testViewerStatusForProcessedAndUnsigned` | `noRAW`, `signingFails` and signing off: the three status variants |
| `testViewerZoomShowsPreviewHint` | Double tap, pinch, Zoom In and Zoom Out; the hint; swipe down does not close while zoomed |
| `testViewerHidesAndShowsControls` | Tap, and the Hide Controls and Show Controls actions |
| `testViewerActions` | Photo Details opens What's in This Photo on the photo shown; Open in Photos brings Photos to the front |
| `testViewerNewPhotoWhileOpen` | A photo taken through the Siri or watch test hook: the page stays, New Photo goes to the newest |
| `testViewerFailureWhileOpen` | The chip, and the banner after closing |
| `testViewerFallbackWhenPreviewReleased` | A launch argument that releases previews; also after a background and return, the viewer is closed |
| `testViewerLargestText`, `testViewerRightToLeft`, `testViewerNightModeIsAllRed`, `testViewerSideways` | The audits at the largest size (with `auditScrollingScreen`), right to left, night mode (with `nonRedPixels` equal to 0 over the whole screen) and sideways |
| `testViewerEscapeAndHardwareShutterClose` | Escape; the hardware shutter rule of section 7, as far as the Simulator can press it |
| `testViewerOnIPad` (iPad shard) | The column arrangement in both orientations, and the fallback |
| `testLockScreenViewerHasNoOpenInPhotos` | The capture extension |

Update the tests that expect a tap to open Photos or that use the long-press menu (`docs/TESTING.md`, the Last Photo rows), and add the new tests to `scripts/ui-test-shards.txt`. By hand: the fold pair `duo-fold-viewer`; the hardware buttons on a device; VoiceOver, Voice Control and Switch Control on the flows in ACCESSIBILITY.md.

### 3.15 What's in This Photo (owner request, 2026-11-18)

Figures: every `sheet-photo-details*` figure ([photo-details.html](photo-details.html)); `viewer-details`, `ipad-photo-details`, `duo-inner-photo-details`, `duo-fold-photo-details`. This section replaces the `PhotoDetailsSheet` line of 3.9.

The owner asked for as much as the app can say about the photo and its metadata, organized cleanly. The sheet keeps its title, What's in This Photo, and its two ways in: Photo Details in the Last Photo viewer, and the Photo Details action on Last Photo. It shows only values the app already holds in memory for a photo of this session: the read-back of each saved file (`SavedPhoto.metadata`, `SavedPhoto.details`), the settings the photo was saved with, and what the camera reported. It reads nothing from Photos, writes nothing to disk, logs nothing, and has no copy or share action (`AGENTS.md`: no clipboard access; the text stays unselectable, as today).

Rules for every row:

- A value is shown only when the app holds it. A missing value has no row; nothing is estimated.
- A value is as written in the files unless its row says "Not in the files". Only three values can say that: the shutter and ISO the camera reported, when the files hold no exposure, and the lens that was selected, when the files hold no lens name.
- Enumerated EXIF values use the app's own word where the app has a control for the same thing (Auto, Manual, the metering names), otherwise the EXIF standard's term; a code the core does not name shows the number.
- An identifying value (`MetadataComparison.Entry.isIdentifying`: location, maker notes, IDs and serial numbers) with a readable value reads "Hidden" until the person asks, as in Compare. What was revealed is forgotten when the sheet closes. The sheet's contents are hidden while the scene is not active, as in `ComparisonScreen`, so the app switcher's snapshot holds no value.
- Numbers, dates, sizes and lists use the system formatters. Specification names (tags, blocks, properties) and the manifest's own words are not translated.

Order of groups, fixed for every photo. A group with nothing to show is left out only where the table says so.

| # | Group (header) | Rows shown at once | Behind a disclosure row | Data |
| --- | --- | --- | --- | --- |
| 0 | Summary (no header) | Formats, as a list ("RAW (DNG) and HEIF"); lens and time; pixel size and total size; then four lines with symbols: kind, signature, optional details, location | none | `SavedPhoto.formats`; the session's lens and time (section 6, item 15), left out when the session has none; `files[].pixelWidth`, `pixelHeight`, the sum of `byteCount`; `files[].processing`; `signature`; the count of `items` in state `written`, without location; the location item's state |
| 1 | Exposure | Shutter, ISO, Aperture, Focal Length, 35 mm Equivalent, Exposure Compensation, White Balance, Flash. Footer "As written in the files." | More Exposure Details: Exposure Mode, Program, Metering, Scene Brightness, Largest Aperture, Subject Area | `PhotoDetails.exposure`, extended (item 16). With no exposure in the files: Shutter and ISO from the capture, each "Not in the files", and the footer of section 4; with neither, the existing sentence "The files don't record the exposure." |
| 2 | Lens and Camera | Lens, Lens Maker, Camera. Footer "As written in the files." | none | `LensModel`, `LensMake`, `Make` and `Model` from the read-back (item 16). With none: Lens, from the session, "Not in the files", and the footer of section 4. Left out when there is neither |
| 3 | RAW Sensor Data | Size (with megapixels), Bit Depth, Color Filter Pattern, Clipped Highlights, Clipped Shadows, Lens Corrections | More Sensor Details: Red, Green, Blue (clipping); Black Level, White Level, Active Area, Default Crop, Compression, DNG Version, Baseline Exposure, As-Shot Neutral; then the existing clipping definition | The RAW file of `files`, `rawClipping`, and DNG tags from the read-back (item 16). Left out for a photo without RAW. When clipping was not measured, the existing reason replaces the two rows |
| 4 | Files | One row for each file: format and size; under them pixels, bit depth and, for a developed copy, color space and quality. In Photos, when a RAW and a copy were saved | none | `files`; `DevelopedFileOptions` and `RAWPairing` of the save (item 17). Color space and quality are left out for the processed fallback and until item 17 exists |
| 5 | Processing | One row for each file with the existing sentence; a developed copy adds what its look does. A processed fallback: the warning line, the distortion line (`ProcessingNote.distortion`), and what the app did | none | `files[].processing`, `distortionCorrection` |
| 6 | Details in This Photo | Location; In the Files (open), each written item with its value; Standard File Tags. The footer of section 4 | Left Out: each item with "Off in Settings" or "On, but there was nothing to write". Always Saved: the locked items, "Always kept" | `items`, `lockedItems`; the values from the read-back (item 16); `MetadataSettings.writesStandardFileTags` (item 17) |
| 7 | Content Credentials | The signature sentence with its symbol (`signatureSymbol`, `signatureStyle`, unchanged). Signed: what the signature shows; for each file the claim generator and the manifest's words; how to check. Not signed: the reason | Manifest SHA-256, for each file | `signature`, `files[].contentCredentials` |
| 8 | Every Tag | One row for each file, with its count; opens the page below | the page | `files[].entries` (item 16); until then `files[].contents`, names only |
| 9 | (no header) | Timing | The five steps, as today | `timings` |

After the groups: the existing footer "Only for photos taken since nope. opened…", then Open in Photos (left out when `openPhoto` is `nil`). The bracket picker stays above the summary. A bracket's frame has a Bracket group after the summary: Type, This Frame, Planned Exposure, The Bracket, with the Honesty footer that these are session values in no file (`BracketDetailsSection` in `BracketControls.swift`; [BRACKETING.md](BRACKETING.md), figure `bracket-details`).

The Every Tag page (one file): title, the file's format name; the system search field, which filters by name and opens the groups that match; one disclosure row for each place that has entries, closed at first, with its count: TIFF, EXIF, GPS, DNG, XMP, File Structure, Content Credentials. TIFF is IFD0 below tag `0xC612`; DNG is IFD0 from `0xC612` up, without the manifest tag; File Structure is the container blocks. A row is the name in the monospaced body font, the value (`ComparisonText.describe`: the text, the numbers, "Count: n", or "Present, no readable value"), and a footnote with the tag number and the setting that controls it, "Always saved", or "nope.'s Content Credentials signature." A group with hidden values starts with one Show Hidden Values row.

Component tree. `PhotoDetailsSheet.swift` keeps the sheet and is split, because it grows:

| Component | File | Notes |
| --- | --- | --- |
| `PhotoDetailsSheet` | `PhotoDetailsSheet.swift` (kept) | `NavigationStack`, `List`, Done, the bracket picker, Open in Photos, the footer. Holds the revealed identifiers (`@State`), cleared on dismissal. Hides its contents while the scene is not active |
| `PhotoDetailsSections` | same (kept, rewritten) | The ten groups in order |
| `PhotoSummaryCard` | new `PhotoDetailsSummary.swift` | One `Section` with one row; a `VStack` with `NopeSpace.xs` between lines. Head: formats in `.title3.weight(.semibold)`, caption in `.subheadline.monospacedDigit()` secondary; `ViewThatFits` puts the caption under the formats when they do not fit. Lines: `Label` with the symbol in `CameraStyle.fact`, `CameraStyle.warning` or secondary. Symbols: `camera` (kind), `exclamationmark.triangle.fill` (processed, location in the files, failed signature), `checkmark.seal.fill`, `info.circle`, `list.bullet`, `location.slash`. One accessibility element |
| `DetailRow` | `PhotoDetailsSheet.swift` (kept) | Gains an optional note under the value ("Not in the files", megapixels), in `.footnote` |
| `ExposureSection`, `LensSection`, `SensorSection`, `FilesSection`, `ProcessingSection` | new `PhotoDetailsGroups.swift` | `DisclosureGroup` for More Exposure Details and More Sensor Details. `RAWClippingSection`'s rows and reasons move into `SensorSection`; its strings are kept |
| `MetadataItemsSection` | new `PhotoDetailsPrivacy.swift` | Location row (`HiddenValueRow`), three `DisclosureGroup`s (In the Files open, the others closed), Standard File Tags |
| `HiddenValueRow` | same | Title, "Hidden" or the value, and a borderless Show Value button of `NopeSize.minTarget` height; reuses the Compare strings "Hidden" and "Show Value" |
| `ContentCredentialsSection` | new `PhotoDetailsSignature.swift` | The existing row and manifest block; the hash moves into a `DisclosureGroup` |
| `EveryTagSection`, `EveryTagPage` | new `PhotoDetailsTags.swift` | `NavigationLink` for each file; the page is a `List` with `searchable` and a `DisclosureGroup` for each place |

Core additions this design needs are section 6, items 16 and 17. `NopeUI` decodes nothing: names of EXIF values, the grouping of tags and the megapixel figure come from `NopeCore`.

Presentation: a sheet with the large detent in a compact-width window; a centered sheet in a regular-width window (3.11, unchanged), also over the viewer. The Every Tag page is pushed inside the sheet. Sheets rotate with an iPhone held sideways (`sheet-photo-details-sideways`). Night mode: `.nightModeStyle`, red on black, no exception.

Tokens: `NopeSpace.xxs`, `xs`, `m`; `NopeSize.minTarget`; `CameraStyle.fact`, `warning`, `secondaryText`. System list metrics otherwise. No literal values.

AC:

- The summary is the first element. Its four lines are true for the photo shown: the kind line names a processed fallback with the warning symbol; the signature line is the save sentence; the details line counts the optional items written, location not included; the location line says "Location is in the files" with the warning symbol only when the files hold GPS tags.
- No row shows a value the app does not hold. With Remove All Optional Details on, Exposure shows at most Shutter and ISO, each "Not in the files", and Lens and Camera at most Lens.
- Teal appears only with "Saved and signed."; amber only with a processed fallback, a location in the files or a failed signature, each with its symbol and words. Signing off by choice has the information symbol and no amber.
- A location value is never on screen until Show Value (or Show Hidden Values) is activated; it is hidden again the next time the sheet opens; it is not in the snapshot taken when the app leaves the screen.
- Every disclosure row opens and closes with a tap, Space, and the VoiceOver double tap, and announces Collapsed or Expanded. In the Files is open at first; the others are closed.
- Every Tag lists exactly the entries of the file's read-back: the count on the row equals the rows of the page. Search filters by name and is cleared by Cancel.
- Nothing is selectable or copyable; no share action exists.
- At the largest text size no text is truncated; each value is under its title. Right to left, rows mirror and numbers keep their direction. In night mode no pixel is non-red.
- The sheet opens on the photo the viewer shows; Done and Escape return to it.

UI tests, in `PhotoDetailsUITests.swift` (an extension of `NopeAppUITests`; the existing photo details tests move here), each with `performAccessibilityAudit()` through the existing helpers:

| Test | Covers |
| --- | --- |
| `testDetailsSummaryForDefaultPhoto` | RAW only, signing off, all optional removed: the four lines; Not in the files on Shutter, ISO and Lens |
| `testDetailsGroupsInOrder` | RAW and HEIF with details kept: the headers in order; Files has two rows and In Photos |
| `testDetailsDisclosureRows` | Each disclosure row opens and closes; In the Files starts open |
| `testDetailsProcessedPhoto` | `noRAW`: the warning lines, the distortion line, no RAW Sensor Data |
| `testDetailsSignatureStates` | Signed, signing off, `signingFails`: symbol, sentence and reason; the hash behind its row |
| `testDetailsLocationHiddenUntilShown` | Simulated location: Hidden, Show Value, hidden again after reopening; location off; on with nothing to write |
| `testDetailsEveryTagPage` | The page for each format: groups and counts, a tag's value, Show Hidden Values, search |
| `testDetailsHiddenInAppSwitcher` | The scene made inactive: the contents are covered |
| `testDetailsLargestText`, `testDetailsRightToLeft`, `testDetailsNightModeIsAllRed`, `testDetailsSideways` | The audits at the largest size (with `auditScrollingScreen`), right to left, night mode (`nonRedPixels` equal to 0) and sideways |
| `testDetailsOnIPad` (iPad shard) | The centered sheet over the viewer; the pushed page |

Unit tests (100% coverage) for everything added to `NopeCore` by items 16 and 17: every decoded value and its fallback to the number, the grouping of entries, the megapixel figure, the "Not in the files" cases, and each item's value text. By hand: VoiceOver, Voice Control and Switch Control on the flows in ACCESSIBILITY.md; the values against an exiftool dump of the same photo on a device (`docs/TESTING.md`).

### 3.16 Fast Shutter: where it is used (owner request, 2026-11-18)

Figures: every `scope-*` figure ([setting-scope.html](setting-scope.html)). The reasons, the wording and the open decisions are in [SETTING-SCOPE.md](SETTING-SCOPE.md). This section adds to 3.10; where they differ on the Fast Shutter row or page, this section is right. The wording is a draft (section 5).

Fast Shutter is used only while Manual Controls are off (`ManualControlsModel.assist`). The Settings list and the Fast Shutter page say so. Nothing in `NopeCore` or `NopeCapture` changes, and what Fast Shutter does is unchanged.

Files: `SettingsScreen.swift` (`SettingsValueLabel`, `pageRow`, `cameraSection`; chunk G); `FocusAids.swift` (`FastShutterSettingsView`; chunk F); `Honesty.xcstrings` and `App/Shared/Localizable.xcstrings` (chunk S); `App/NopeApp/Intents/FocusAndSizeIntents.swift` (one string; chunk C); `SettingsUITests.swift`. No change to `QuickControls.swift`, `StatePills.swift` or `SettingsSearch.swift` (keywords aside, SETTING-SCOPE.md decision 7).

Change:
- `SettingsValueLabel` gains `note: Text? = nil`. With a note the label is a `VStack(alignment: .leading, spacing: NopeSpace.xxs)`: the existing title and value (side by side or stacked, `ViewThatFits`, unchanged), then the note in `.font(.footnote)` and `CameraStyle.secondaryText`, with `fixedSize(horizontal: false, vertical: true)`. The note is as wide as the label, under both the title and the value. Without a note nothing changes.
- The label stays one accessibility element (`.accessibilityElement(children: .combine)`), so VoiceOver reads the title, the value, then the note. No hint is added. With a note, add `.accessibilityInputLabels([title])` so Voice Control keeps the name "Fast Shutter".
- `pageRow(_:value:note:)`: `note` defaults to `nil`. `cameraSection` passes the note for `.fastShutter` only. The note is the same whatever the choice and whether Manual Controls are on or off. The row's identifier (`settings.fastShutter`) is unchanged; the note has none of its own.
- `FastShutterSettingsView`, sections in order:
  1. only while Manual Controls are on: one row, `Label` with `info.circle` in `CameraStyle.secondaryText` and the sentence of the table; identifier `settings.fastShutter.notUsedNow`. Whether Manual Controls are on is read from the source the tile and the pill use (`CameraModel.manual.isEnabled`; `NopeSettings.showsManualControls` where the page has no model). `SettingsScreen` passes it in; the view takes no model;
  2. the inline `Picker`, unchanged and always enabled;
  3. two rows of text, `.font(.footnote)`, in place of today's one. Rows, not a footer, as today, so they follow the text size.
- `SetFastShutterIntent.description`: the sentence of the table. Its title, parameter, choices and answer are unchanged.
- Remove the string "In full auto, the camera prefers the fastest shutter…" from the catalog.

Strings. All in `Honesty.xcstrings` (`tableName: "Honesty"`) except the last, which is in the app's catalog. Each translator comment says that Manual Controls is the name of nope.'s button and takes its translation, and "Must not claim more than the English."

| String | Where |
| --- | --- |
| Used only while Manual Controls are off. | The Fast Shutter row, its note |
| Used only while Manual Controls are off. The camera keeps the shutter at least as fast as your choice while there is enough light, and uses a higher ISO to do it. In low light the shutter can be slower. Standard aims for a speed you can hold by hand. | The Fast Shutter page, first paragraph |
| With Manual Controls on, this choice is not used. A shutter you set is used as set. A shutter on Auto is chosen by the camera. | The page, second paragraph. "Auto" is the word on a manual readout; use its translation |
| Manual Controls are on, so this choice is not used now. | The page, top row while Manual Controls are on |
| Chooses how fast a shutter nope. prefers while Manual Controls are off, to avoid blur. | Shortcuts, the description of Set Fast Shutter. Keep "nope." unchanged |

Tokens: `NopeSpace.xxs`; `CameraStyle.secondaryText`. System list metrics and text styles otherwise. No literal values. No amber and no teal: the note is neither a warning nor a verified fact.

AC:
- The Fast Shutter row shows its title, its value and the note, with each of the three choices, and with Manual Controls off and on. The note's text is the same in all six cases.
- Changing the choice, or any switch on the root, does not change the number of rows on the root (3.10). The Fast Shutter row is the only root row with a note.
- VoiceOver reads the row as title, value, note, "button": "Fast Shutter, Standard, Used only while Manual Controls are off. Button." Voice Control's "Tap Fast Shutter" opens the page.
- The value "Freeze Fast Motion (1/1000 s)" sits under the title when it does not fit beside it, with the note under the value. Nothing is truncated at the default size or the largest size, in any launch language.
- The page has the top row exactly while Manual Controls are on. With it shown, every choice can still be selected, and the root row's value follows.
- With Manual Controls on and a choice other than Standard, Q has no Fast Shutter tile and the status line has no Fast Shutter pill (as today). With Manual Controls off both are there.
- In night mode no pixel of the row or the page is non-red.

UI tests, in `SettingsUITests.swift`, each with `performAccessibilityAudit()` through the existing helpers. `auditSettingsScreens` already visits the root and the Fast Shutter page in light, dark and night mode, at the largest text size and right to left; it now also runs once with `-NopeSettings.showsManualControls YES`.

| Test | Covers |
| --- | --- |
| `testFastShutterRowSaysWhereItIsUsed` | The row `settings.fastShutter`: its label begins with the title, holds the value and ends with the note, for each choice (`-NopeSettings.fastShutter`), with Manual Controls off and on |
| `testFastShutterPageExplainsWhereItIsUsed` | Manual Controls off: the two paragraphs; no `settings.fastShutter.notUsedNow` |
| `testFastShutterPageWithManualControlsOn` | `-NopeSettings.showsManualControls YES`: the top row exists and comes before the choices; choosing Freeze Motion changes the root row's value; the row count of the root is unchanged |
| `testFastShutterNoteLargestTextAndRightToLeft` | The root and the page at the largest size (`auditScrollingScreen`) and right to left; no truncated text |
| `testFastShutterNoteNightModeIsAllRed` | The Camera group and the page in night mode, `nonRedPixels` equal to 0 |
| `testFastShutterLeavesCameraWithManualControlsOn` (`QuickMenuUITests.swift`) | `-NopeSettings.fastShutter freezeMotion`: tile and pill with Manual Controls off; neither with Manual Controls on. Extends the existing checks if they already cover it |

No unit test is added: no code outside `NopeUI` and one intent string changes. By hand: VoiceOver and Voice Control on the row and the page; the Shortcuts description in the Shortcuts app.

## 4. New and changed strings

Add to `Sources/NopeUI/Resources/Localizable.xcstrings` unless marked Honesty. All need a translator comment; 1.0.0 ships in English only (issue #86).

| String | Where | Note |
| --- | --- | --- |
| Single, Timer | Drive strip | New keys, with comments saying they are drive-mode words. "Burst", "Astro" exist. "Interval" needs its own key as a drive word (the existing one is a picker label) |
| Quick Menu | Q button, large-text list title | Replaces "Quick Controls" |
| Auto, Manual | Manual Controls button | New keys with their own comments (existing "Auto" is a control state) |
| Processed | Format status (Honesty) | |
| Processed: no RAW on this lens | VoiceOver value (Honesty) | |
| What the Phone Does on This Lens; What nope. Does | Processing note headings (Honesty) | |
| The phone's camera processes this file before nope. receives it. nope. can't turn that processing off. | Processing note (Honesty) | Draft |
| Distortion correction stays on for this lens, even though nope. asks for it to be off. | Processing note, What's in This Photo (Honesty) | Draft; shown only with device evidence |
| Nothing more to this lens's file. HEIF and JPEG copies that nope. develops from a RAW get the %@ look: … | Processing note (Honesty) | Draft; two variants, Standard and Flat |
| Show Processed Marker; Shows Processed on the camera when a lens can't save RAW. | Settings, processing note | Draft. No default note |
| All Photo Settings | Formats sheet | |
| Screen | Settings section | |
| Search results: "%@ › %@" page paths | Settings search | Use whole localized page names; do not concatenate fragments |
| Details in Each Photo | Settings row and page title (Honesty) | Replaces "Choose Details" |
| Location; Other Details | Section headers on that page (Honesty) | Replace "In Each Photo". "Location" exists as a switch title; the header needs its own key |
| Custom, Location On | Value of the Details in Each Photo row (Honesty) | A whole string, not "Custom" joined to a fragment |
| HEIF and JPEG Copies | Settings row and page title | Replaces "Look" and "File Options" as row titles. "Look" stays as a section header and on the Photo Format sheet |
| Files | Section header on that page | |
| Not Saved | Value of the HEIF and JPEG Copies row | |
| No HEIF or JPEG copy is saved now. Turn one on in Formats. | First row of that page with RAW only | |
| Focus on Faces | Settings switch | Replaces "Face Detection" |
| Set Focus on Faces; Focus on Faces; Set focus on faces to %@; Focus on Faces is on.; Focus on Faces is off. | Shortcuts action title, parameter, summary and answers, in `App/Shared/Localizable.xcstrings` | Replace the "Face Detection" strings of `SetFaceDetectionIntent`. Not interface work: section 6, item 9 |
| %@, %@ (two overlay names); %lld On | Value of the Viewfinder Overlays row | Whole formats with plural rules; "Off" exists |
| On the Camera; In Settings | Search result headers | |
| On the camera, beside the lenses; On the camera, above the shutter; In Q | Search pointers | One whole sentence per place. Names of the controls are the existing strings |
| Search keywords, one string per setting: for example "metadata, EXIF, GPS" (Details in Each Photo, Location); "Content Credentials, C2PA, signature" (Sign Each Photo); "reset, restore, defaults" (Presets, Restore Defaults); "resolution, megapixels" (Photo Size); "quality, compression, resize" (HEIF and JPEG Copies); "selfie" (Mirror Front Camera); "red, dark" (Night Mode, Red Viewfinder) | Settings search | Translators list the words people use in that language; not shown on screen |
| Saves front camera photos mirrored, as the viewfinder shows them. | Mirror Front Camera (Honesty) | Draft; replaces the three-sentence explanation |
| Red on black, to keep your eyes used to the dark. nope. doesn't change the screen's brightness. | Night Mode (Honesty) | Draft; the dimming advice moves to the Accessibility page |
| nope. doesn't change the screen's brightness. Dim it in Control Center, or with Reduce White Point in the Accessibility settings. | Accessibility page, Night Mode | Draft |
| In Night Mode, shows the live picture in red too. Only the screen changes; photos keep their colors. | Red Viewfinder (Honesty) | Draft |
| When Astro turns Night Mode on, it stays on after you leave Astro instead of turning off again. | Keep Night Mode After Astro | Draft (2026-11-18) |
| Shows a series' progress on the Lock Screen and in the Dynamic Island when you leave nope. Counts only; nothing is sent. | Live Activity (Honesty) | Draft; replaces the longer explanation |
| Fixed values the file standard asks for, such as version numbers and the color space. Nothing in them identifies you or your phone. | Standard File Tags (Honesty) | Draft; replaces "They say nothing about you, your phone or the photo." |
| iOS may detect faces in the viewfinder to decide where to focus. Focus on Faces in nope.'s settings decides only whether nope.'s autofocus and auto exposure follow them. | Honesty, Faces and Autofocus | Draft |
| Location is off unless you turn it on under Details in Each Photo in nope.'s settings. | Honesty | Draft; names the renamed page |
| Every %@, %lld photos | Interval card | Uses the existing duration formatting and plural rules |
| After %@ · %@ in all · at most %@ | Astro card | |
| Astro on. Manual controls and night mode are on. | VoiceOver announcement | |
| More for %@; Rename; Delete; Delete “%@”? | Presets | "Delete Preset" exists |
| Pinned; %lld Saved; None Saved | Q tile values; the Presets row in Settings | |
| Focus Peaking | Q tile | Exists as a switch title; reuse it |
| You can sign each photo, so changes can be detected. Signing is off until you turn it on. | First run (Honesty) | Draft; replaces "Each photo is signed, so changes can be detected." |
| A signed photo shows that it was taken with nope., and which version. | Sign Each Photo explanation (Honesty) | Draft |
| Signing Is Your Choice; Lenses Without RAW (with their sentences) | Honesty screen (Honesty) | Draft |
| Timer, above the shutter, sets a self-timer of 3 or 10 seconds. Burst is beside it. … | Accessibility page | Replaces the Quick Controls wording |
| Close | Last Photo viewer | Button that closes the viewer and returns to the camera |
| Signed; Not signed | Viewer status line (Honesty) | Draft. Short forms of the save sentences; the full sentence stays the VoiceOver value |
| %lld of %lld | Viewer caption | Position of the photo among this session's photos |
| Photo; Photo %lld of %lld | Viewer, VoiceOver label | |
| A screen-size preview, not the full photo. | Viewer, while zoomed in (Honesty) | Draft |
| Preview Not Kept; nope. keeps previews in memory only and has released this one. The photo is saved in Photos. | Viewer fallback (Honesty) | Draft |
| New Photo | Viewer | Button that goes to a photo taken while the viewer was open |
| Photo Not Saved | Viewer | Warning chip; closes the viewer to show the failure |
| Shows the photo. | Last Photo, VoiceOver hint | |
| Zoomed in. | Viewer, VoiceOver value | Zoom In, Zoom Out, Hide Controls and Show Controls exist |
| Exposure; Lens and Camera; RAW Sensor Data; Details in This Photo; Content Credentials; Every Tag | What's in This Photo, headers (3.15) | "Files", "Processing" and "Timing" exist. "Exposure as Written", "Clipping in the RAW", "Signature", "Details Kept", "Details Left Out" and "Read Back from the Files" are removed. Details in This Photo and Content Credentials: Honesty |
| %@ · %@ (lens, time); %@ · %@ (pixels, size) | Summary | Whole formats; the parts are formatted by the system |
| RAW: one frame of sensor data; RAW: one frame of sensor data, and a %@ copy developed by nope.; RAW: one frame of sensor data, and %@ copies developed by nope. | Summary, kind line (Honesty) | Draft. The placeholder is a format name or a list of two |
| No optional details in the files; %lld optional details in the files | Summary (Honesty) | Draft; plural rule. Location is not counted: it has its own line |
| No location in the files; Location is in the files | Summary (Honesty) | Draft |
| Not in the files | Under a value the files do not hold (Honesty) | Draft |
| Exposure Settings is off, so the files don't hold the exposure. These are the values the camera reported for this photo. nope. keeps them only until it closes. | Exposure footer (Honesty) | Draft; replaces "Not in the files: exposure settings are off in Settings." when the capture's values are shown |
| Lens and camera names are off in Settings, so the files don't hold them. | Lens and Camera footer (Honesty) | Draft |
| As written in the files. | Exposure and Lens and Camera footers (Honesty) | Draft |
| 35 mm Equivalent; More Exposure Details; Exposure Mode; Program; Scene Brightness; Largest Aperture; Subject Area | Exposure | "Metering" exists. The EXIF terms for program and metering values (for example "Normal program", "Pattern") are new keys, one each |
| Lens; Lens Maker; Camera | Lens and Camera | |
| Size; %@ MP; Bit Depth; Color Filter Pattern; Lens Corrections; Stored, not applied; Not stored; More Sensor Details; Black Level; White Level; Active Area; Default Crop; %@ at %@; Compression; Lossless JPEG; DNG Version; Baseline Exposure; As-Shot Neutral | RAW Sensor Data | Titles and values as separate keys; the joined forms "Bit depth: %lld", "Color filter pattern: %@", "Black level: %@", "White level: %@" and the two "Lens corrections: …" strings are removed. "Clipped Highlights", "Clipped Shadows" and the color names exist |
| %@ · %lld-bit · lossless; %@ · %lld-bit · %@ · %@ quality; %@ · %lld-bit | Files, under a format | Pixels, bit depth, color space, quality. Whole formats |
| In Photos; One photo: the RAW with its %@; One photo: the RAW with its %@. The %@ is a photo of its own. | Files (Honesty) | Draft. States what the app asked Photos to do |
| One overall tone curve, and no noise reduction, sharpening or local tone mapping.; No contrast curve, and no noise reduction, sharpening or local tone mapping. | Processing, under a developed copy (Honesty) | Draft; the same claims as the processing note |
| nope. didn't change this file's picture. | Processing, processed fallback (Honesty) | Draft |
| In the Files; Left Out; Always Saved; In the files; Shown under Exposure | Details in This Photo (Honesty) | "Off in Settings", "On, but there was nothing to write", "Always kept", "Hidden" and "Show Value" exist |
| To change what the next photos hold, open Details in Each Photo in Settings. The files of this photo stay as they are. | Details in This Photo footer (Honesty) | Draft |
| %@, altitude %@ | Location, after Show Value | Coordinates and altitude formatted by the system |
| The signature lets anyone check that a file hasn't changed since nope. saved it. It doesn't show who took the photo or on which device. | Content Credentials (Honesty) | Draft |
| To check a file, open it in a Content Credentials checker. Each photo is signed with its own one-time key, so a checker reports the file as valid and the signer as untrusted. | Content Credentials (Honesty) | Draft |
| Sign Each Photo is off in Settings, so these files have no signature. | Content Credentials (Honesty) | Draft |
| Signing was on, but nope. couldn't create the signature for this photo. The files were saved without one. The camera shows Not Signed until a photo is signed again. | Content Credentials (Honesty) | Draft. Variants for the other reasons (`unavailable`, `signedFileFailedCheck`) follow the same pattern and their existing save sentences |
| Claim generator: %@ %@; Manifest SHA-256 | Content Credentials (Honesty) | The first exists. The second becomes a row title; "Manifest SHA-256: %@" is removed |
| Every tag, block and property nope. read back from each file before saving it, with its value. | Every Tag footer (Honesty) | Draft |
| %lld tags, blocks and properties in this file, as nope. read them back before saving it. Names are the standards' own. | Every Tag page (Honesty) | Draft; plural rule |
| TIFF; EXIF; GPS; DNG; XMP; File Structure; Show Hidden Values; Always saved | Every Tag page | Names of standards are not translated. "Count: %lld", "Present, no readable value" and "nope.'s Content Credentials signature." exist |
| Show Value, %@ | VoiceOver label of a Show Value button | The placeholder is the row's title |

Bracketing (1.0.0): the strings of [BRACKETING.md](BRACKETING.md), section 7, "Strings (English), 1.0.0", including the removal of "Bracketing" (the Pro Tools switch).

Remove: "Choose Details"; "In Each Photo" (the header); "File Options"; "Face Detection" and the action strings that use it; every "On by default." and "Off by default." sentence in Settings; the 0.3.0 explanations replaced above; the Interval Shooting section strings of Pro Tools once nothing uses them; "Golden Ratio", "Golden Spiral", "Turn Spiral" and its value (issue 76); "Quick Controls"; "No RAW on This Lens" once nothing uses it; "Rename or Delete"; "Turn Off Manual Controls", "Back to Single Photo", "Turn Off Astro" when their pills go.

## 5. Wording that needs the Honesty review

These are drafts. None ships until reviewed in every language (`AGENTS.md`, Localization):

- the first-run signing statement; the Sign Each Photo explanation; the three processing-note sentences; the Honesty entries Signing Is Your Choice and Lenses Without RAW;
- from the Settings decisions of 2026-11-17: the explanations of Mirror Front Camera, Focus on Faces, Show Processed Marker, Night Mode, Red Viewfinder and Live Activity; the Standard File Tags sentence; the Night Mode entry on the Accessibility page; the Honesty entries Faces and Autofocus and Location Only If You Turn It On; the names Details in Each Photo, HEIF and JPEG Copies and Focus on Faces;
- from the Last Photo viewer (3.14): Signed and Not signed on its status line, the preview hint, and the Preview Not Kept title and sentence. The hint must stay true for the preview size the data specification chooses, and is shown only when the preview has fewer pixels than the saved photo;
- from What's in This Photo (3.15): every string marked Honesty in section 4 under that screen. Four need particular care. "RAW: one frame of sensor data" must not be read as "no processing"; it says only what the file is. "Not in the files" and the two footers must stay true if the capture's values stop being kept. "One photo: the RAW with its HEIF" states what the app asked Photos to do, which the device check in `docs/PRIVACY.md` confirms. The sentence about a checker reporting the file as valid and the signer as untrusted follows `docs/PRIVACY.md` (Content Credentials) and c2patool 0.28.6; it must be checked against the checker people are most likely to use before it ships, and it names no product;
- from bracketing ([BRACKETING.md](BRACKETING.md), section 7): "A bracket never fires the flash.", the Bracket group footer and the limited-frame sentences;
- from Fast Shutter (3.16): the note, the two paragraphs of the page, the line shown while Manual Controls are on, and the Shortcuts description. "Used only" must stay true: if Fast Shutter ever applies with Manual Controls on, these change in the same release;
- from the level haptic design of 2026-11-18 ([level-haptic.md](level-haptic.md), section 5): the Level explanation's added sentence "On iPhone, you feel a tap when it's level." and the Accessibility page's Feedback row ending "…and marks the moment the level is level."; the Level search keywords gain "tap, haptic, vibration";
- to check against the real-device tag dump (issue 79) before it is kept as written: the Always Saved footer, "None of them identify you or link your photos."

The processing note must not name specific processing steps the phone applies unless they are verified; the draft says only that the phone processes the file and that the app cannot turn it off. Focus on Faces must not be described as turning face detection off: the switch decides only whether the app's autofocus and auto exposure follow faces.

## 6. Work beyond the interface (flagged, not designed around)

| # | Item | Why it is not interface work | Design depends on it for |
| --- | --- | --- | --- |
| 1 | Defaults (issue 80): formats `[.raw]`, `followsFaces` false, `signsPhotos` false; Factory Defaults; preset decoding; tests | `NopeCore/NopeSettings`, `MetadataSettings` | The default screens as drawn |
| 2 | New stored setting `showsProcessedMarker` (default true), in presets and the Lock Screen snapshot | `NopeCore/NopeSettings`, `App/Shared/SharedSettings.swift` | 3.2, 3.10 |
| 3 | Per-lens forced distortion correction (issue 80): device verification, and a per-lens value in the capability data | `NopeCapture`, `NopeCore`, device tests | The distortion line. Hide the line until this exists |
| 4 | Golden-ratio grids removed from the model, with stored values decoding to Thirds (issue 76) | `NopeCore/OverlayOptions`, `GridGeometry` | 3.6, 3.10 |
| 5 | Manual Controls off while Astro turned them on: `settings.setShowsManualControls(false)` may not change anything if the stored setting was already false, so manual and Astro may stay on. Confirm with a test and fix in the core so one call always turns both off | `NopeCore/CameraModel+Astro`, `NopeSettings` | 3.4: the camera button must always work |
| 6 | The reason a photo is unsigned, in the watch status and the "Not Signed" rule (signing off by choice versus a failure) | Watch message format; `NopeCore` capture result already has the reason for the phone | 3.3, 3.13 |
| 7 | Light requests applied or reported (issue 75) | `NopeCapture` | The Light tile and "Light Unavailable" |
| 8 | Remembering the last timer delay beyond the session | Would be a new stored setting. Not in 1.0.0: the strip keeps it for the session only | none |
| 9 | Focus on Faces in Shortcuts: rename the action Set Face Detection to Set Focus on Faces (title, description, parameter title, summary, and the two spoken answers) in `App/NopeApp/Intents/FocusAndSizeIntents.swift`, with its strings in `App/Shared/Localizable.xcstrings`. Keep the type name `SetFaceDetectionIntent`, so shortcuts people have saved keep working. The parameter default follows the new setting default (off) | App Intents and the app's catalog, not `NopeUI` | 3.10; ACCESSIBILITY.md. Chunks C (code) and S (strings) |
| 13 | Device checks with no code change planned: what the Lock Screen camera offers while locked; each `duo-fold-*` pair and the half-open posture; the watch countdown in Always On; iPhone sideways at the largest text size. Record the results in docs/TESTING.md; a difference from the drawings is a finding for the owner, not a reason to add layout code in 1.0.0 | Needs devices | 3.10 to 3.13 |
| 14 | Night Mode turned on while the Settings popover is open on iPad: the popover keeps the system material, not black, until it is closed (today's behavior, drawn in `ipad-settings-night-on`). Closing and reopening Settings by itself would be a behavior change | `CameraStyle.swift` (`AdaptivePresentation`) | Owner decision if the red-on-material state is not acceptable |
| 15 | The Last Photo viewer's data (owner decision, 2026-11-18): the list of this session's photos with the lens and time of each; a screen-size preview for each, in memory only, released in the background and under memory pressure; how many are kept; whether the viewer is open, so the hardware shutter can close it | `NopeCore`, `NopeDevelop` (`ImageIOThumbnailer`), the app target's capture events. Specified separately | 3.14 |
| 16 | What's in This Photo: values the read-back already holds but `PhotoDetails` does not expose. (a) `PhotoDetails.File.entries`: every tag, block and XMP property with its value, the setting that controls it, whether it identifies, and its place (TIFF, EXIF, GPS, DNG, XMP, file structure, signature), built as `MetadataComparison.items(in:)` builds them. (b) `PhotoDetails.Exposure` gains the 35 mm equivalent, exposure mode, program, metering, brightness, largest aperture and subject area, with named cases and the raw number for an unknown code. (c) A lens and camera value (lens model, lens make, make, model). (d) For the RAW file: megapixels, active area, default crop, compression, DNG version, baseline exposure, as-shot neutral. (e) For each written item, its value as text (the date parsed and formatted by the interface from a `Date`; the location as coordinates) | `NopeCore/PhotoDetails.swift`, with unit tests to 100%. No new reading: the data is `SavedPhoto.metadata`. Scope: presentation of existing data, so 1.0.0 if the owner agrees (section 7, P1) | 3.15, groups 1, 2, 3, 6 and 8. Without it the sheet shows today's values in the new order, and Every Tag lists names only |
| 17 | What's in This Photo: values the save knows and does not pass on. (a) The developed copies' color space, quality and size (`DevelopedFileOptions`) and the pairing (`RAWPairing`). (b) Whether Standard File Tags were written (`MetadataSettings`). (c) The shutter and ISO the camera reported (`CapturedPhoto.exposureDuration`, `iso`), kept with the details in memory for the session | `NopeCore/PhotoSaver.swift`, `PhotoDetails.swift`; `docs/PRIVACY.md` (Last photo and its details) must list (c). Scope: 1.0.0 if the owner agrees (P1, P2) | 3.15, groups 1, 4 and 6 |
| 19 | Bracketing on the drive strip ([BRACKETING.md](BRACKETING.md), section 7, "Core"): `BracketOrder`, `BracketFramePlan`, a bracket in full auto, `CameraModel.bracketProgress` and `failedBracket`, `BracketPlace` on `SavedPhoto` (in memory only), Burst and Interval turning the bracket off, an interval series never taking a bracket, the preset's order and Take Bracket's Order | `NopeCore` | 3.5, 3.14, 3.15 |
| 18 | Not in 1.0.0, new capability: the bytes of tags the reader does not decode (EXIF version, component configuration, maker notes, the lens correction lists) and of tags with more than 16 values, which needs a change to the fail-closed reader (`TIFFReader`); the name of the color profile; which processing switches the device offered and the app turned off for this photo (`ProcessingSwitches`); focus distance, white balance in kelvin, drive mode and bracket step; a check of the signature by the app; the manifest's other fields (instance ID, certificate serial number). File names are not available to an app with add-only access | `NopeCore`, `NopeCapture`, `NopeSigning` | Nothing drawn. Rows for these read "Present, no readable value" or do not exist |
| 10 | Deployment targets (issue 78) | Project settings | none; do first if `#available` fallbacks in `CameraStyle.swift` are to be removed with the token work |
| 11 | App icon assets and the `TRADEMARKS.md` entry | Brand asset; owner decision on the period color | icon.html |
| 12 | A check that fails on literal spacing or radius values (issue 74) | Script or test under `scripts/` | tokens.md |

One interface-only addition can be dropped without affecting anything else: the delete confirmation (3.9). Settings search is kept (decided 2026-11-17); the root no longer depends on it to reach any row, since no row is conditional.

## 7. Decisions

Made on 2026-11-17 (the twelve decisions of [SETTINGS-PLAN.md](SETTINGS-PLAN.md), section 7, all accepted):

1. Remove All Optional Details and Choose Details are one row and page.
2. It is named Details in Each Photo.
3. Look and File Options are one page, HEIF and JPEG Copies, always shown.
4. Regrouping: Mirror Front Camera in Photos; Start in Clean View, Viewfinder Overlays and Show Processed Marker in Screen; Camera holds Fast Shutter and Focus on Faces.
5. Face Detection is renamed Focus on Faces, the switch and the Shortcuts action.
6. One-sentence explanations, no default notes, Red Viewfinder always shown; the wording goes to the Honesty review.
7. Focus Peaking has a Q tile.
8. The Interval section leaves Pro Tools.
9. Settings on iPad stays a single-column popover.
10. Settings from the Lock Screen camera is drawn as it is; no behavior change.
11. Search is kept, with keywords and pointers to the camera.
12. Device coverage: drawn where presentation differs, a written rule in layouts.html for the rest.

Still needing the owner:

1. "Not Signed" is not a warning when signing is off by choice (3.3).
2. The period of the icon stays teal ([icon.html](icon.html)).
3. The preset delete confirmation is in or out.
4. The draft wording in section 5, after the Honesty review.
5. The spacing scale (4, 8, 12, 16, 24, 32, 48), the radius scale (12, 24, capsule) and the seven button types.
6. Q with thirteen tiles has five rows and covers about 57% of the picture while it is open on a 402 × 874 pt screen (45% with four rows). Accept, or say which tile should give way.
7. Section 6, item 14: the Settings popover when Night Mode is turned on inside it.

Made on 2026-11-18: Burst as continuous shooting, all thirteen recommendations of [BURST.md](BURST.md) section 7. A tap takes one photo and holding the shutter takes photos until release; Start Burst for a burst without holding; Fast and Slow (up to 2 a second) for the session, with Slow hidden where Fast measures under about 3 a second; no deeper saving buffer until measured; at most 50 photos; the rate shown is measured from the burst; focus and exposure follow what is set; the count, a light tap and the system sound for each photo, no blink; no new burst while the last is saving; Apple Watch, Siri and Shortcuts, Interval and Astro unchanged; the speed is not remembered.

Made on 2026-11-18: bracketing ([BRACKETING.md](BRACKETING.md), section 10, all nineteen recommendations): Bracket is a sixth word of the drive strip, in full auto and with Manual Controls on; Burst and Interval turn it off and an interval series no longer takes a bracket; focus bracketing waits for 1.1.0 and its device checks; the frames are grouped in the viewer and in What's in This Photo from session values only.

Made on 2026-11-18: a tap on Last Photo shows the photo full screen inside the app, with Open in Photos and Photo Details, for this session's photos (3.14).

Last Photo viewer, still needing the owner. Each has a recommendation, and the drawings show it:

| # | Point | Recommendation | Other choice |
| --- | --- | --- | --- |
| V1 | A volume button or the Camera Control pressed while the viewer is open | Close the viewer and take no photo; the next press takes one. A photo is never taken while its framing is hidden | Take the photo at once and close the viewer, as a camera with a shutter button does during review; or leave the buttons to the system |
| V2 | A photo taken while the viewer is open (Apple Watch, Siri, a series) | Stay on the photo shown and offer New Photo | Jump to the new photo |
| V3 | The touch and hold menu on Last Photo | Remove it. The viewer holds both actions, and both stay as VoiceOver actions on Last Photo. Open in Photos becomes two taps | Keep it as a shortcut |
| V4 | The photo in night mode | Red, like everything outside the live viewfinder; the all-red check stays without an exception | Natural colors, as the viewfinder has without Red Viewfinder |
| V5 | Zoom | From fit to the preview's own pixels and at least 2 × fit, with the hint that it is a preview | No zoom at all; or a larger preview, which costs memory |
| V6 | How many previews are held | The newest 20, as compressed data decoded for the page shown and its neighbors; older photos show the fallback. To be set by the data specification | Every photo of the session, or only the last |
| V7 | Leaving the app with the viewer open | The viewer closes and the previews are released; the camera is what returns | Reopen the viewer on the fallback |
| V8 | A tap on the photo hides the controls | In | Out: the rows always show |
| V9 | iPad and the iPhone Duo inner display | The full window, as Compare | A centered sheet |
| V10 | Closing | Close, an X where Last Photo is | Done, the checkmark the sheets use, in the same place |
| V11 | Signing off by choice | The words Not signed in secondary text, no symbol | Nothing, as the thumbnail shows no badge |
| V12 | A bracket or a burst | Every saved photo is its own page | One page for each press of the shutter |
| V13 | The draft wording (section 5) | After the Honesty review | |

What's in This Photo (3.15), needing the owner. Each has a recommendation, and the drawings show it:

| # | Point | Recommendation | Other choice |
| --- | --- | --- | --- |
| P1 | Scope of 1.0.0. The new values are already in memory (the read-back), but showing them needs additions to `PhotoDetails` in the core (section 6, items 16 and 17) | In 1.0.0: it is the presentation of existing data, with unit tests, and no new reading, capture or storage | Interface only in 1.0.0: the new order, the summary and the disclosure rows with today's values; the rest in 1.1.0 |
| P2 | With Exposure Settings off (the default), the files hold no exposure. The app knows the shutter and ISO the camera reported | Show the two, each marked "Not in the files", with the footer that says they are kept only until the app closes. `docs/PRIVACY.md` gains one line | Show only the sentence that the files hold no exposure |
| P3 | The lens and the time in the summary come from the session, not the file, and show even when the files hold neither | Show them, as the viewer's caption does; Details in This Photo says whether the files hold the date | Leave them out of the sheet unless the files hold them |
| P4 | A location in the files, in the summary | "Location is in the files" with the warning triangle, as the camera's Location On chip | Plain text with a location symbol |
| P5 | Identifying values | Hidden until Show Value, forgotten when the sheet closes, never in the app switcher | Shown at once; or never shown |
| P6 | Every Tag | A page for each file, its groups closed at first, with search | Everything inline on the sheet in nested disclosure rows; no search |
| P7 | Copy or share of values | None: the app has no clipboard access and no share action, and the text is not selectable | A Share action for the list would be a new capability and needs a privacy review |
| P8 | How to check a signed file | One sentence that names no product and says what a checker reports | No guidance; or name a tool, which the Honesty review would have to keep current |
| P9 | The title | Keep What's in This Photo; the button stays Photo Details | Title it Photo Details, so the button and the title match |
| P10 | The order | Summary, Exposure, Lens and Camera, RAW Sensor Data, Files, Processing, Details in This Photo, Content Credentials, Every Tag, Timing | Privacy and the signature before the exposure |
| P11 | Timing | Kept, as one closed row at the end | Removed from the sheet |
| P12 | The draft wording (section 5) | After the Honesty review | |

## 8. Implementation order

Chunks are sized to be built in parallel after chunk 0. No two parallel chunks edit the same file. Three kinds of file are shared by nature and each has one owner: the string catalogs (chunk S), the UI test shard list `scripts/ui-test-shards.txt` and `docs/api` (chunk Z), and `CameraReadyView.swift` (chunk A).

| Chunk | After | Owns (files) | Delivers |
| --- | --- | --- | --- |
| 0 · Tokens and button styles | – | New `DesignTokens.swift`, `NopeButtonStyles.swift`; `CameraStyle.swift` | Every token; the seven button types; `SelectableCapsuleStyle`, `pillShape()`, `darkBacking()` kept as thin deprecated wrappers so nothing else has to change yet; unit tests for the tokens; a gallery view for the button states behind the existing debug tools |
| C · Core prerequisites | – | `Sources/NopeCore/**`, `Sources/NopeCapture/**`, `App/Shared/SharedSettings.swift`, `App/NopeApp/Intents/FocusAndSizeIntents.swift`, their tests | Section 6 items 1, 2, 4, 5, 7, and the code of item 9 (the Focus on Faces action rename and its parameter default) |
| S · Strings | 0 | `Sources/NopeUI/Resources/*.xcstrings`, `App/**/*.xcstrings` | Section 4, added up front so other chunks only reference keys, including the Focus on Faces action strings in `App/Shared/Localizable.xcstrings` (section 6, item 9) and the search keywords; removals at the end, in chunk Z |
| A · Camera shell | 0 | `CameraReadyView.swift`, `CameraLayout.swift`, `LensRow.swift`, `ShutterButton.swift`, `CameraScreen.swift`, new `ManualControlsButton.swift`, new `DriveStrip.swift` | 3.1, 3.11, 3.12, the button of 3.4, the strip of 3.5. Uses placeholders for the panel and the cards until B and D land |
| B · Q | 0 | `QuickControls.swift`, new `QuickPanel.swift` | 3.6, with Focus Peaking in the builder order. Item builders that live in other files keep their `QuickControlItem` signature, so B does not edit those files; the Focus Peaking builder is written by chunk G |
| D · Drive cards | 0 | `DriveControls.swift`, `IntervalControls.swift`, `AstroControls.swift`, `SeriesScreen.swift` | `ModeCard` and the rest of 3.5; removes the Drive and Astro pill builders' sources; takes over `IntervalProgressView` from `ProToolsSheet.swift` if the card still needs it |
| E · Status line | 0, C | `StatePills.swift`, `FormatChip.swift`, `FormatsSettingsView.swift`, `CameraWarnings.swift`, `ResourceWarnings.swift`, `CaptureFeedback.swift`, `SessionStatusView.swift`, `StatusMessageView.swift`, `FirstRunView.swift` | 3.2, 3.3, 3.7, 3.8 |
| F · Manual | 0 | `ManualControlsView.swift`, `ManualControlsList.swift`, `ControlDial.swift`, `ControlText.swift`, `ProToolsSheet.swift`, `FocusAids.swift`, `LiveAidsPanel.swift`, `ViewfinderOverlays.swift` | The rest of 3.4, including the removal of the Interval Shooting section from `ProToolsSheet`; hint placement of 3.7 |
| G · Settings and sheets | 0, C | `SettingsScreen.swift`, new `SettingsSearch.swift` (the index, keywords, camera pointers and the page and row identifiers), `PresetsScreen.swift`, `PrivacySettingsView.swift` (Details in Each Photo), `OverlaySettingsView.swift` (with the new Focus Peaking Q item builder), new `CopiesSettingsView.swift` (merges and deletes `LookSettingsView.swift` and `FileOptionsSettingsView.swift`), `PhotoSizeSettingsView.swift`, `AccessibilitySettingsView.swift`, `HonestyScreen.swift`, `AboutScreen.swift`, `ExplainedToggle.swift`, `PhotoDetailsSheet.swift`, `ComparisonScreen.swift` | 3.9, 3.10 |
| H · System and watch | 0 | `App/Shared/SeriesActivity.swift`, `App/NopeControls/*.swift`, `App/NopeWatch/*.swift` (not catalogs) | 3.13. These targets need the token values: add `DesignTokens.swift` to their target membership, or keep a copy checked by a test; choose one and say which |
| V · Last Photo viewer | A, E, G, and section 6 item 15 | New `PhotoViewer.swift`, new `PhotoViewerUITests.swift`; small edits to `CaptureFeedback.swift`, `CameraReadyView.swift`, `PhotoDetailsSheet.swift` | 3.14 |
| P · What's in This Photo | G, V, and section 6 items 16 and 17 | `PhotoDetailsSheet.swift`; new `PhotoDetailsSummary.swift`, `PhotoDetailsGroups.swift`, `PhotoDetailsPrivacy.swift`, `PhotoDetailsSignature.swift`, `PhotoDetailsTags.swift`, `PhotoDetailsUITests.swift`; `NopeCore/PhotoDetails.swift` and `PhotoSaver.swift` with their tests | 3.15 |
| Z · Integration | A–H | `App/NopeAppUITests/*`, `App/NopeWatchUITests/*`, `scripts/ui-test-shards.txt`, `docs/api`, `docs/ARCHITECTURE.md`, `docs/BUILDING-AN-INTERFACE.md`, `CHANGELOG.md`, catalog removals, deletion of the deprecated wrappers | Each chunk writes its UI tests in a new file named after it (`QuickMenuUITests.swift`, `DriveStripUITests.swift`, …) as an extension of `NopeAppUITests`; Z updates the tests in existing files, assigns shards, regenerates the API docs and removes dead strings |

Notes:
- Chunk E's `FormatChip.swift` opens Settings at an identifier that chunk G defines in `SettingsSearch.swift`. G lands the identifier enum first (it has no dependencies), so E only references it.
- `OverlaySettingsView.swift`, `ComparisonScreen.swift`, `PresetsScreen.swift`, `FocusAids.swift`, `DriveControls.swift` and `AstroControls.swift` each also hold a Q item builder. The builder stays in its file and belongs to that file's chunk; chunk B only consumes it.
- One branch for the release, with each chunk on its own branch merged into it, and one CI run on the integration branch.
- A chunk is done when its figures match, its acceptance criteria hold, its audits pass at the default size, the largest size, right to left and night mode, and coverage has not dropped.

## 9. Checks from issue 74, by source

| Source | Result in this design |
| --- | --- |
| HIG accessibility | ACCESSIBILITY.md; 44 pt targets; Large Content Viewer on fixed-size controls |
| HIG color and Dark Mode | One meaning per color; never color alone; camera dark, forms follow the system; night mode kept as a stated departure (red on black) |
| HIG typography and SF Symbols | Text styles only; symbols paired with words, except the sideways strip, which names the selection in a pill |
| HIG layout | Safe areas respected; three arrangements; 4.7-inch, iPad in both orientations and in Split View, Slide Over and a small window, both iPhone Duo displays with folding, sideways, right to left drawn; the rule for the rest written in layouts.html |
| HIG motion | Three short animations, all off or reduced with Reduce Motion |
| HIG privacy and permissions | Explanation before each prompt; prompts at the moment of need |
| HIG writing | Sentence case in sentences, title case on controls (as today); errors say what happened and what to do |
| HIG patterns and components | System menus, sheets, popovers, forms; one confirmation for the one irreversible action |
| Inputs | Each gesture has a button or action; volume buttons, Camera Control, Space unchanged |
| Technologies | Live Activity, controls, App Intents and watchOS restyled, content unchanged |
| WCAG 2.2 | Contrast values in tokens.md; target size; focus order; no timing traps |
| Fitts, Hick, Jakob | Large shutter in reach; five modes and up to thirteen tiles, each visible at once; the familiar camera layout of modes above the shutter |
| Deceptive patterns, privacy by default | Most private option is the default; no warning used to push a setting on |
| Plain language | Labels are existing ones; new ones are listed in section 4 |
| 0.3.0 findings | Night-mode switches (fixed, 3.10); iPad Settings appearance while open (AC in 3.10); right-to-left pill contrast on iPad (AC in 3.11); Live Activity row height (AC in 3.13); Astro start delay after a pause, Light at 25%, burst cap, dim level: unchanged, they are behavior and not layout |
