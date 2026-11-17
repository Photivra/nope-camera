# Build specification: direction B · Reach

Design version: 1.0.0 (2026-11-17). For the implementer of release 1.0.0 (issue 74, with issues 76, 77 and 80).

This document says what to build, in which files, and how to tell it is done. The drawings are the mockups in this folder ([overview.html](overview.html)); each figure named below is `screens/<name>.html` with a PNG beside it. Tokens are in [tokens.md](tokens.md), accessibility in [ACCESSIBILITY.md](ACCESSIBILITY.md), paths in [navigation.md](navigation.md).

## 1. Ground rules

- **Scope.** 1.0.0 changes the interface of features that exist. Add no capability. If a step seems to need one, stop and flag it.
- **Architecture.** `NopeUI` reads state from `NopeCore` and sends intents. It holds no business rules. Everything here except section 6 is inside `NopeUI`, the app targets' views, and the string catalogs.
- **Native first.** `Menu`, `Toggle`, `Picker`, `Form`, sheets, popovers, `confirmationDialog`, `searchable`, `sensoryFeedback`. Custom drawing only for the shutter, viewfinder overlays, tiles, readouts and the drive strip.
- **Tokens only.** No literal spacing, radius, size, color or duration outside `DesignTokens.swift`.
- **Every string** goes in a catalog with a translator comment and all eleven languages, marked "needs review". Honesty wording goes in `Honesty.xcstrings` and is a draft until reviewed.
- **Every screen and state** has a UI test with an accessibility audit; coverage of non-UI code stays at 100%.
- **Layouts.** The three arrangements and the rule that chooses them stay as they are (`CameraLayout.arrangement`): stacked, column, scrolling.
- **When the mockup and this text disagree, this text is right.** When this text and the code's existing behavior disagree on something not listed as a change, keep the behavior and flag it.

## 2. What changes, in one table

| Area | 0.3.0 | 1.0.0 |
| --- | --- | --- |
| Top bar | State pills, format chip, Settings button | Status line: format status leading, pills trailing. No Settings button (stacked and scrolling layouts) |
| Lens row | Lenses, then the "⋯" Quick Controls button | Manual Controls button, lenses, Switch Camera |
| Drive | A menu in the tray; Astro a separate tray switch | Drive strip of five words above the shutter |
| Shutter row | Last Photo, shutter, Switch Camera | Last Photo, shutter, Q |
| Quick controls | Sideways-scrolling tray that replaces the lens buttons | Q panel of tiles above the shutter row |
| Manual Controls | Settings switch; M pill turns it off | Camera button; Settings switch and M pill removed |
| Manual readouts | A row in the bands | A row on the lower edge of the picture |
| Mode feedback | Progress rows and AstroPanel at the top of the picture | Mode cards on the lower edge of the picture |
| Processed fallback | "No RAW on This Lens" chip | "Processed" marker, its note, a Settings switch |
| Settings | Opens from the gear | Opens from Q (gear kept in the column layout and before the camera is ready); search; regrouped |
| Presets | Rename or Delete page (three levels) | More menu on each preset (two levels); delete asks first |

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

Figures: `camera-processed`, `camera-processed-hidden`, `camera-front`, `sheet-format`, `sheet-processing-note`.

Files: `FormatChip.swift` (`FormatChip`, `FormatDetailsSheet`), `FormatsSettingsView.swift`, `LensRow.swift` (the "No RAW" caption, kept).

Change:
- `FormatChip` loses its capsule fill in the status line: a symbol and words, `NopeFont.status`, 44 pt target. In the column layout and sideways it sits on the picture and keeps a `NopeMaterial.backing` capsule.
- Bayer RAW: teal seal, then the saved formats ("RAW", "RAW + HEIF"), as today.
- No Bayer RAW, marker shown: amber triangle and "Processed". VoiceOver value "Processed: no RAW on this lens", then the format.
- No Bayer RAW, marker hidden (`settings.showsProcessedMarker == false`): the format name with no symbol. Never the teal seal.
- `FormatDetailsSheet` on a lens without RAW shows the processing note first: the existing fallback sentence; "What the Phone Does on This Lens"; the per-lens distortion line only when `NopeCore` reports it for that lens; "What nope. Does"; then the formats list and the "Show Processed Marker" switch.
- `FormatDetailsSheet` gains a row "All Photo Settings", which closes the sheet and opens Settings.
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
- `ProToolsSheet`: content unchanged; tokens only.
- Remove the Manual Controls row from Settings › Camera, and the first-row test expectations for it.

AC: one tap turns manual on and one tap turns it off, from full auto and from manual; the button is absent in clean view; VoiceOver reads "Manual Controls, On"; each readout is adjustable with VoiceOver without opening the dial; presets and shortcuts still set manual as before.
UI tests: `testManualControlsButtonInAuto`, `testManualControlsButtonInManual`, `testCleanViewHidesManualControlsButton`; update every test that turned manual on through Settings.

### 3.5 Drive strip and mode cards

Figures: every `drive-*` figure; `landscape-manual`, `landscape-astro`.

Files: new `DriveStrip.swift`; `DriveControls.swift` (`DriveProgressView`, `CountdownNumber`, `DriveText`); `IntervalControls.swift`; `AstroControls.swift` (`AstroPanel`, `AstroSheet`); `ProToolsSheet.swift` (`IntervalProgressView`); `SeriesScreen.swift`; `ShutterButton.swift`.

`DriveStrip`:
- Five words: Single, Timer, Burst, Interval, Astro. `NopeCapsuleStyle(isSelected:)` at `NopeSize.driveWord`, target 44 pt, `NopeFont.status`. Exactly one is selected.
- Mapping to existing intents: Single → `DriveMode.single`; Timer → `.timer(delay)`, where `delay` is the last delay chosen in this session, 3 seconds at first; Burst → `.burst`; Interval → `.interval`; Astro → the existing Astro on intent. Choosing any other word while Astro is on turns Astro off first, then sets the mode. Astro is offered only where `canUseAstro` is true or Astro is on; otherwise the strip has four words.
- Tapping the selected word: Timer opens a `Menu` (3 seconds, 10 seconds); Interval opens `IntervalSheet`; Astro opens `AstroSheet`; Single and Burst do nothing.
- Choosing Interval no longer opens the sheet by itself; the card shows the series and the shutter starts it.
- Fit: `ViewThatFits` with word padding `NopeSpace.s`, then `NopeSpace.xs`, then a horizontal `ScrollView` that keeps the selected word visible. At the default text size all eleven languages fit at `NopeSpace.xs` (figure `drive-strip-languages`).
- While the drive is busy the other words are disabled at 0.4 opacity.
- Sideways: symbols only (`square`, `clock`, `square.stack.3d.down.right`, `timer`, `moon.stars`), with Large Content Viewer labels.
- Column layout: the strip sits in a `NopeMaterial.backing` capsule on the lower edge of the picture.
- `.sensoryFeedback(.selection)` on change; VoiceOver announces the new mode.

Mode cards (one view, `ModeCard`, in `DriveControls.swift`, used by all modes; `NopeRadius.large`, `NopeMaterial.backing`):

| Mode | Idle | Running | Paused or ended |
| --- | --- | --- | --- |
| Single | none | none | none |
| Timer | none; the shutter shows "3" or "10" | Countdown number in the picture; "Photo in 3s" and Cancel Timer | none |
| Burst | none | "Photos taken: 12" and Stop Burst | The end message as text until the next action |
| Interval | "Every 10 seconds, 10 photos"; the whole card is the button Interval Settings | "3 of 10 photos taken", progress bar, Stop | "Paused: 3 of 10 photos taken", Stop |
| Astro | "Astro frames: 20" and "After 10 seconds · 20 s in all · at most 486 MB"; the whole card is the button Astro Settings | Countdown, then "Frame 7 of 20", progress bar, Stop Frames | "Paused: 7 of 20 frames", Stop Frames |

- `AstroPanel`, `DriveProgressView` and `IntervalProgressView` become uses of `ModeCard` and move from the top of the picture to the bottom stack.
- `ShutterButton`: while a series or countdown runs, the disc is a stop square; with Timer selected and idle, the disc shows the delay in black. Its label stays "Take Photo"; the value says the mode.
- `IntervalSheet` and `AstroSheet`: content unchanged; medium and large detents.
- Astro keeps today's behavior: it turns on Manual Controls and night mode, and hides the Light tile.

AC: each mode is one tap from the default screen; the mode's name is always visible; an idle Astro screen covers no more than a quarter of the picture and a running one no more than a sixth; no white element appears at any point in Astro with night mode on; the strip never truncates a word in any launch language.
UI tests: `testDriveStripSelectsEachMode`, `testTimerDelayMenu`, `testIntervalCardOpensSettings`, `testAstroFromStrip`; update the self-timer, burst, interval and `AstroUITests` flows that used the tray; pseudo-language test for the strip.

### 3.6 Q

Figures: every `q-*` figure; `landscape-q`, `ipad-q`, `ax-q`, `rtl-q`.

Files: `QuickControls.swift` (`QuickControlItem`, `QuickControls.builders`, `QuickControlsTray`, `QuickControlButton`, `WrappingRows`); new `QuickPanel.swift`; `LensRow.swift` (`QuickControlsButton` → `QuickButton`).

Change:
- `QuickButton`: `NopeIconButtonStyle(size: NopeSize.quick)`, the letter Q in `NopeFont.q`; filled white while the panel is open. Label "Quick Menu".
- `QuickPanel` replaces `QuickControlsTray`: a `LazyVGrid` of three flexible columns, gap `NopeSpace.xs`, padding `NopeSpace.m`, `NopeRadius.large`, `NopeMaterial.backing`. In the stacked layout it spans the width less `NopeSpace.xs` each side, its bottom `NopeSpace.xs` above the shutter row, and it covers the lens row and the drive strip. If it would be taller than the space up to the status line, it scrolls.
- Tile (`NopeTileStyle`): the name on top (`NopeFont.tileName`, up to two lines), then the symbol and the value (`NopeFont.tileValue`). Minimum height `NopeSize.tileMin`. On: filled white.
- `QuickControlItem` keeps its three kinds. `.toggle` → a tile button; `.menu` → a tile `Menu`; `.button` → a tile button that closes the panel.
- `QuickControls.builders` order: Flash, Light, Exposure, Close-Up, Far Focus, Fast Shutter, Magnify, Grid, Level, Readout, Night Mode, Compare, Presets. Remove Drive, Astro and Hide Controls from the list. Each builder's existing visibility rule stays (for example Far Focus only with manual on; Exposure and Fast Shutter only in full auto).
- Foot: two `NopeCapsuleStyle` buttons at `capsuleLarge`: Hide Controls, Settings. `ViewThatFits`: side by side, else stacked.
- Values shown: Flash Off/Auto/On; Light Off or its percentage; Exposure as a number; Close-Up, Far Focus, Magnify, Level, Night Mode, Compare On/Off; Fast Shutter Standard, 1/500, 1/1000; Grid Off or the style; Readout Off, On, Pinned; Presets "n Saved" or "None Saved".
- Closing: Q again, the shutter, a lens, the picture, Escape, a `.button` tile, Exposure, Settings, Hide Controls.
- Scrolling layout: Q presents the same items as a full-height list (`List`), one row per tile, with a Done button.
- No editing or reordering of tiles.

AC: every tile is reachable in two taps from the default screen; the shutter row is never covered; with all twelve tiles the panel covers less than half the picture on a 402 × 874 pt screen; a tile's name is never truncated in any launch language; focus moves into the panel on open and back to Q on close.
UI tests: replace the tray tests with `testQuickMenuTiles`, `testQuickMenuTogglesStayOpen`, `testQuickMenuMenuTile`, `testQuickMenuLargestText`, `testQuickMenuRightToLeft`, `testQuickMenuNightMode`.

### 3.7 Capture feedback, hints and pause messages

Figures: `camera-capturing`, `camera-saved-signed`, `camera-saved-unsigned`, `camera-failure`, `camera-failure-photos`, `camera-paused`, `camera-first-photo`, `camera-closeup`, `camera-too-close`, `camera-focus-lock`, `camera-overlays`, `sheet-thumbnail-menu`.

Files: `CaptureFeedback.swift`, `SessionStatusView.swift`, `FocusAids.swift`, `LiveAidsPanel.swift`, `ViewfinderOverlays.swift`.

Change: tokens only, plus two placements. `CameraHints` and `CloseUpSuggestion` move to the bottom stack. The thumbnail badge is not drawn when signing is off in Settings (see 3.3). All sentences stay as they are.

AC: a failure stays until dismissed; each failure offers its one action; audits pass for each state.

### 3.8 Before the camera is ready

Figures: `first-run`, `first-run-light`, `permission-camera`, `permission-photos`, `permission-location`, `camera-denied`, `camera-unavailable`, `camera-starting`.

Files: `FirstRunView.swift`, `StatusMessageView.swift`, `CameraScreen.swift`.

Change: Continue and Open Settings become `.borderedProminent`, large, full width at the bottom; spacing tokens. The second first-run statement is reworded for signing off by default (draft; see section 5). The Settings button stays on these screens.

AC: the explanation precedes the system prompt; audits pass in light, dark, largest text and right to left.

### 3.9 Sheets

Figures: `sheet-photo-details`, `sheet-photo-details-processed`, `sheet-interval`, `sheet-astro`, `sheet-presets`, `sheet-presets-applied`, `sheet-preset-save`, `sheet-preset-delete`, `sheet-compare`.

Files: `PhotoDetailsSheet.swift`, `PresetsScreen.swift`, `ComparisonScreen.swift`.

Change:
- `PhotoDetailsSheet`: with signing off in Settings, the Signature row uses the info symbol, not the warning triangle. Processing gains the per-lens distortion line when the core reports it. Everything else stays.
- `PresetsScreen`: each saved preset row gets a trailing `Menu` ("More for NAME": Rename, Delete), and the same two as swipe and VoiceOver actions. Rename pushes the existing Rename Preset page, without its Delete button. Remove the Rename or Delete page. Delete presents a `confirmationDialog`: title "Delete “NAME”?", message "Deleting a preset doesn't change your current settings.", buttons Delete Preset (destructive) and Cancel.
- `ComparisonScreen`: tokens and button types only.

AC: no page is more than two levels below Settings; deleting a preset needs a confirmation and Cancel leaves it; Factory Defaults still applies at once with Undo.
UI tests: update `PresetsUITests` (rename and delete paths), add `testDeletePresetAsksFirst`.

### 3.10 Settings

Figures: every `settings-*` figure; `ipad-settings`.

Files: `SettingsScreen.swift`, new `SettingsSearch.swift`, `FormatsSettingsView.swift`, `LookSettingsView.swift`, `FileOptionsSettingsView.swift`, `PhotoSizeSettingsView.swift`, `PrivacySettingsView.swift`, `OverlaySettingsView.swift`, `AccessibilitySettingsView.swift`, `HonestyScreen.swift`, `AboutScreen.swift`, `ExplainedToggle.swift`, `CameraScreen.swift` (presentation).

Root, in order:

| Section | Rows |
| --- | --- |
| (none) | Presets (when any are saved) |
| Photos | Formats; Look and File Options (when a copy is on); Photo Size (when a lens offers sizes) |
| Privacy | Remove All Optional Details; Choose Details; Sign Each Photo |
| Camera | Start in Clean View; Fast Shutter; Face Detection; Show Processed Marker (when the device has a lens without RAW); Viewfinder Overlays; Mirror Front Camera (when there is a front camera) |
| Screen | Night Mode; Red Viewfinder (while Night Mode is on); Live Activity (where offered) |
| More | Accessibility; Honesty; About and Licenses |

Change:
- Remove Manual Controls. Add Show Processed Marker. Move Night Mode, Red Viewfinder and Live Activity to the new Screen section.
- Every explained switch uses `ExplainedToggle`.
- Sign Each Photo explanation gains the sentence about what a signed photo shows (issue 80; draft wording in section 5). Face Detection reads "Off by default."
- `.searchable` on the root. `SettingsSearch` holds a static index: one entry per setting on any page (title, page path, destination). Results replace the list while searching; choosing one pushes its page. The index is built from the same localized titles the pages use.
- Presentation: sheet in compact width, popover (480 × 720) in regular width, sheet in night mode, as today. In the stacked and scrolling layouts it is presented from Q's Settings button; in the column layout from the Settings button in the column.
- Viewfinder Overlays: Grid Style lists Thirds, 4 × 4, Square; remove Turn Spiral (issue 76).
- Accessibility page: the Self-Timer and Burst text names the drive strip.
- Honesty: two new entries (section 5).
- Night mode: `NightModeSwitchStyle` draws on as filled with a dark knob and off as an outline.

AC: `auditSettingsScreens` passes on every page in light, dark and night mode, at the largest text size and right to left; search finds every row of every page by its title; the popover on iPad follows the system appearance while it is open (a 0.3.0 finding: it follows only when it opens).
UI tests: update `auditSettingsScreens` for the new order; add `testSettingsSearchFindsLocation`, `testShowProcessedMarkerSwitch`; remove the Golden Spiral tests.

### 3.11 Column layout (iPad, iPhone Duo inner display)

Figures: `ipad-auto`, `ipad-manual`, `ipad-q`, `ipad-astro`, `ipad-settings`, `ipad-rtl`, `duo-inner`.

Files: `CameraReadyView.swift` (`column`), `CameraLayout.swift`.

- Trailing column, `NopeSize.column` wide, top to bottom: Settings, lenses (vertical), Manual Controls button; then Q, shutter, Last Photo, vertically centered on the shutter; Switch Camera at the bottom.
- On the picture: format status (with backing) and warnings at the top leading corner, pills at the top trailing corner; at the bottom, centered and at most 480 pt wide: dial, mode card, readout row, drive strip.
- `QuickPanel`: `NopeSize.panelMaxWidth` wide, beside the column, bottom-aligned near Q.
- The iPhone Duo inner display uses this layout through the existing size-class rule; the outer display uses the stacked layout. No posture handling is added.

AC: audits pass on iPad in both orientations, split view widths that stay regular, and right to left (the 0.3.0 finding on pill contrast in right-to-left on iPad must pass: pills on the picture always have the backing).

### 3.12 Scrolling layout (accessibility text sizes)

Figures: `ax-camera`, `ax-q`, `settings-largest`.

Files: `CameraReadyView.swift` (`scrolling`), `ManualControlsList.swift`.

Order: format status; pills; warnings; the 280 pt picture; mode card; a "Manual Controls" row (toggle); one row per lens; one row per drive mode (selected filled); the manual controls list when manual is on. Pinned below: Last Photo, shutter, Q (Q and Last Photo at 64 pt).

AC: `auditScrollingScreen` passes; nothing essential is truncated at the largest size in any launch language.

### 3.13 Live Activity, controls and Apple Watch

Figures: `live-activity-lock`, `live-activity-night`, `live-activity-island`, `controls`, `siri-results`, every `watch-*` figure.

Files: `App/Shared/SeriesActivity.swift`, `App/NopeControls/*.swift`, `App/NopeWatch/RemoteShutterView.swift`, `App/NopeWatch/WatchText.swift`.

Change: spacing, radius and type tokens only. On the watch, the result "Saved, not signed" is plain (primary color, info symbol) when signing is off in Settings; it needs the phone to say why the photo is unsigned, see section 6, item 6. Until then keep today's styling.

AC: `LiveActivityUITests` and `NopeWatchUITests` pass their audits; the largest Live Activity row is no taller than today.

## 4. New and changed strings

Add to `Sources/NopeUI/Resources/Localizable.xcstrings` unless marked Honesty. All need a translator comment and eleven languages ("needs review").

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
| Show Processed Marker; Shows Processed on the camera when a lens can't save RAW. On by default. | Settings, processing note | |
| All Photo Settings | Formats sheet | |
| Screen | Settings section | |
| Search results: "%@ › %@" page paths | Settings search | Use whole localized page names; do not concatenate fragments |
| Every %@, %lld photos | Interval card | Uses the existing duration formatting and plural rules |
| After %@ · %@ in all · at most %@ | Astro card | |
| Astro on. Manual controls and night mode are on. | VoiceOver announcement | |
| More for %@; Rename; Delete; Delete “%@”? | Presets | "Delete Preset" exists |
| Pinned; %lld Saved; None Saved | Q tile values | |
| You can sign each photo, so changes can be detected. Signing is off until you turn it on. | First run (Honesty) | Draft; replaces "Each photo is signed, so changes can be detected." |
| A signed photo shows that it was taken with nope., and which version. | Sign Each Photo explanation (Honesty) | Draft |
| Signing Is Your Choice; Lenses Without RAW (with their sentences) | Honesty screen (Honesty) | Draft |
| Timer, above the shutter, sets a self-timer of 3 or 10 seconds. Burst is beside it. … | Accessibility page | Replaces the Quick Controls wording |

Remove: "Golden Ratio", "Golden Spiral", "Turn Spiral" and its value (issue 76); "Quick Controls"; "No RAW on This Lens" once nothing uses it; "Rename or Delete"; "Turn Off Manual Controls", "Back to Single Photo", "Turn Off Astro" when their pills go.

## 5. Wording that needs the Honesty review

These are drafts. None ships until reviewed in every language (`AGENTS.md`, Localization): the first-run signing statement; the Sign Each Photo explanation; the three processing-note sentences; the two Honesty entries. The processing note must not name specific processing steps the phone applies unless they are verified; the draft says only that the phone processes the file and that the app cannot turn it off.

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
| 9 | Set Face Detection shortcut: parameter default follows the new setting default | App Intents | ACCESSIBILITY.md |
| 10 | Deployment targets (issue 78) | Project settings | none; do first if `#available` fallbacks in `CameraStyle.swift` are to be removed with the token work |
| 11 | App icon assets and the `TRADEMARKS.md` entry | Brand asset; owner decision on the period color | icon.html |
| 12 | A check that fails on literal spacing or radius values (issue 74) | Script or test under `scripts/` | tokens.md |

Two interface-only additions can be dropped without affecting anything else: Settings search (3.10) and the delete confirmation (3.9).

## 7. Decisions that need the owner

1. "Not Signed" is not a warning when signing is off by choice (3.3).
2. The period of the icon stays teal ([icon.html](icon.html)).
3. Settings search and the preset delete confirmation are in or out.
4. The draft wording in section 5.
5. The spacing scale (4, 8, 12, 16, 24, 32, 48), the radius scale (12, 24, capsule) and the seven button types.

## 8. Implementation order

Chunks are sized to be built in parallel after chunk 0. No two parallel chunks edit the same file. Three kinds of file are shared by nature and each has one owner: the string catalogs (chunk S), the UI test shard list `scripts/ui-test-shards.txt` and `docs/api` (chunk Z), and `CameraReadyView.swift` (chunk A).

| Chunk | After | Owns (files) | Delivers |
| --- | --- | --- | --- |
| 0 · Tokens and button styles | – | New `DesignTokens.swift`, `NopeButtonStyles.swift`; `CameraStyle.swift` | Every token; the seven button types; `SelectableCapsuleStyle`, `pillShape()`, `darkBacking()` kept as thin deprecated wrappers so nothing else has to change yet; unit tests for the tokens; a gallery view for the button states behind the existing debug tools |
| C · Core prerequisites | – | `Sources/NopeCore/**`, `Sources/NopeCapture/**`, `App/Shared/SharedSettings.swift`, their tests | Section 6 items 1, 2, 4, 5, 7 |
| S · Strings | 0 | `Sources/NopeUI/Resources/*.xcstrings`, `App/**/*.xcstrings` | Section 4, added up front so other chunks only reference keys; removals at the end, in chunk Z |
| A · Camera shell | 0 | `CameraReadyView.swift`, `CameraLayout.swift`, `LensRow.swift`, `ShutterButton.swift`, `CameraScreen.swift`, new `ManualControlsButton.swift`, new `DriveStrip.swift` | 3.1, 3.11, 3.12, the button of 3.4, the strip of 3.5. Uses placeholders for the panel and the cards until B and D land |
| B · Q | 0 | `QuickControls.swift`, new `QuickPanel.swift` | 3.6. Item builders that live in other files keep their `QuickControlItem` signature, so B does not edit those files |
| D · Drive cards | 0 | `DriveControls.swift`, `IntervalControls.swift`, `AstroControls.swift`, `SeriesScreen.swift` | `ModeCard` and the rest of 3.5; removes the Drive and Astro pill builders' sources |
| E · Status line | 0, C | `StatePills.swift`, `FormatChip.swift`, `FormatsSettingsView.swift`, `CameraWarnings.swift`, `ResourceWarnings.swift`, `CaptureFeedback.swift`, `SessionStatusView.swift`, `StatusMessageView.swift`, `FirstRunView.swift` | 3.2, 3.3, 3.7, 3.8 |
| F · Manual | 0 | `ManualControlsView.swift`, `ManualControlsList.swift`, `ControlDial.swift`, `ControlText.swift`, `ProToolsSheet.swift`, `FocusAids.swift`, `LiveAidsPanel.swift`, `ViewfinderOverlays.swift` | The rest of 3.4; hint placement of 3.7 |
| G · Settings and sheets | 0, C | `SettingsScreen.swift`, new `SettingsSearch.swift`, `PresetsScreen.swift`, `PrivacySettingsView.swift`, `OverlaySettingsView.swift`, `LookSettingsView.swift`, `FileOptionsSettingsView.swift`, `PhotoSizeSettingsView.swift`, `AccessibilitySettingsView.swift`, `HonestyScreen.swift`, `AboutScreen.swift`, `ExplainedToggle.swift`, `PhotoDetailsSheet.swift`, `ComparisonScreen.swift` | 3.9, 3.10 |
| H · System and watch | 0 | `App/Shared/SeriesActivity.swift`, `App/NopeControls/*.swift`, `App/NopeWatch/*.swift` (not catalogs) | 3.13. These targets need the token values: add `DesignTokens.swift` to their target membership, or keep a copy checked by a test; choose one and say which |
| Z · Integration | A–H | `App/NopeAppUITests/*`, `App/NopeWatchUITests/*`, `scripts/ui-test-shards.txt`, `docs/api`, `docs/ARCHITECTURE.md`, `docs/BUILDING-AN-INTERFACE.md`, `CHANGELOG.md`, catalog removals, deletion of the deprecated wrappers | Each chunk writes its UI tests in a new file named after it (`QuickMenuUITests.swift`, `DriveStripUITests.swift`, …) as an extension of `NopeAppUITests`; Z updates the tests in existing files, assigns shards, regenerates the API docs and removes dead strings |

Notes:
- `OverlaySettingsView.swift`, `ComparisonScreen.swift`, `PresetsScreen.swift`, `FocusAids.swift`, `DriveControls.swift` and `AstroControls.swift` each also hold a Q item builder. The builder stays in its file and belongs to that file's chunk; chunk B only consumes it.
- One branch for the release, with each chunk on its own branch merged into it, and one CI run on the integration branch.
- A chunk is done when its figures match, its acceptance criteria hold, its audits pass at the default size, the largest size, right to left and night mode, and coverage has not dropped.

## 9. Checks from issue 74, by source

| Source | Result in this design |
| --- | --- |
| HIG accessibility | ACCESSIBILITY.md; 44 pt targets; Large Content Viewer on fixed-size controls |
| HIG color and Dark Mode | One meaning per color; never color alone; camera dark, forms follow the system; night mode kept as a stated departure (red on black) |
| HIG typography and SF Symbols | Text styles only; symbols paired with words, except the sideways strip, which names the selection in a pill |
| HIG layout | Safe areas respected; three arrangements; 4.7-inch, iPad, iPhone Duo, sideways, right to left drawn |
| HIG motion | Three short animations, all off or reduced with Reduce Motion |
| HIG privacy and permissions | Explanation before each prompt; prompts at the moment of need |
| HIG writing | Sentence case in sentences, title case on controls (as today); errors say what happened and what to do |
| HIG patterns and components | System menus, sheets, popovers, forms; one confirmation for the one irreversible action |
| Inputs | Each gesture has a button or action; volume buttons, Camera Control, Space unchanged |
| Technologies | Live Activity, controls, App Intents and watchOS restyled, content unchanged |
| WCAG 2.2 | Contrast values in tokens.md; target size; focus order; no timing traps |
| Fitts, Hick, Jakob | Large shutter in reach; five modes and twelve tiles, each visible at once; the familiar camera layout of modes above the shutter |
| Deceptive patterns, privacy by default | Most private option is the default; no warning used to push a setting on |
| Plain language | Labels are existing ones; new ones are listed in section 4 |
| 0.3.0 findings | Night-mode switches (fixed, 3.10); iPad Settings appearance while open (AC in 3.10); right-to-left pill contrast on iPad (AC in 3.11); Live Activity row height (AC in 3.13); Astro start delay after a pause, Light at 25%, burst cap, dim level: unchanged, they are behavior and not layout |
