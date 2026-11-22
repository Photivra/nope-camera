# The last designs for 1.0.0

Status: proposed 2026-11-21 for release 1.0.0 and built in 1.0.0 with the owner's decisions of 2026-11-21; the "As built" notes in sections 1 and 2 record where the build differs. Not in the screen counts of [README.md](README.md). The owner's decisions already recorded on each issue are taken as fixed and marked "decided"; everything else is a proposal, and the open choices are collected in [docs/plans/1.0.0-finish.md](../plans/1.0.0-finish.md), section 6. All wording is a draft until the Honesty review. Figures are in [finish-1.0.html](finish-1.0.html); each is `screens/<name>.html` with a PNG beside it.

This document covers the user-facing parts of seven issues:

| Section | Issue | What |
| --- | --- | --- |
| 1 | 116 | More space between the camera's control rows |
| 2 | 117 | A how-to-use guide that can be dismissed |
| 3 | 118 | The summary card of What's in This Photo |
| 4 | 119 | Dim After, under Keep Screen On |
| 5 | 121 | Burst Limit |
| 6 | 122 | The self-timer counts to a fixed deadline |
| 7 | 123 | Interval photos are spaced start to start |
| 8 | | Every draft string, for the Honesty review |

Evidence note: everything about today's behavior was read from the code on `int-1.0.0` at `1119915`. Nothing here was measured on a device or run on a simulator. Screen sizes and safe-area insets in section 1 are the nominal values for each screen size and must be confirmed on the simulators before the numbers are relied on. Each statement that needs a device is listed as a device check in the plan.

The Q menu is not changed by anything here. The guide describes Q in one sentence and shows its button; no tile, order or behavior of Q is touched.

## 1. Space between the control rows (issue 116)

### 1.1 What exists

In the stacked layout (an iPhone in portrait, also when it is held sideways) the screen is, from the top: the status line (44 pt), the picture (the window's width, 4:3), the lens row (56 pt), the drive strip (44 pt) and the shutter row (88 pt at least). `CameraReadyView.stacked` gives every spare point to the shutter row, which centers the shutter in it; the lens row and the drive strip always sit edge to edge.

So on a 440 × 956 pt iPhone, where the request was made, the three spaces between the shapes are 12 pt (lens group to drive words), 33 pt (drive words to shutter) and 27 pt (under the shutter). The first is the crowded one. The touch targets are closer still: the lens controls end 6 pt above the drive strip's 44 pt targets, less than the design's own smallest gap between targets (`NopeSize.targetGap`, 8 pt).

### 1.2 The rule

The picture keeps its size and place. Only the spare height is shared differently.

- **Spare height** is what is left of the window, inside the safe area, after the status line, the whole 4:3 picture, the lens row, the drive strip and the shutter row at its smallest. It is zero when the rows overlay the picture (`CameraLayout.bandsOverlayPicture`).
- **The gap between the lens row and the drive strip** takes the first 2 pt of the spare height, then a third of the rest, rounded down to a whole point, and never more than 24 pt (`NopeSpace.l`).
- **The shutter row** takes what is left, and keeps centering the shutter, so the space is split above and below it.
- The 6 pt between the picture and the lens row stays: the lens controls belong to the picture's edge.

The first 2 pt bring the lens controls and the drive strip's targets to the 8 pt target gap on every screen that has 2 pt to spare. The third after that makes the three spaces close to equal on a tall screen.

As a pure function for `CameraLayout`, so it can be unit tested:

```
rowGap(spare) = 0                                         when spare <= 0
              = min(floor(min(spare, 2) + max(spare - 2, 0) / 3), 24)
```

### 1.3 Each screen size

Insets are top / bottom, in points. The three spaces are lens group to drive words · drive words to shutter · shutter to the bottom of the safe area.

| Screen (pt) | Insets | Picture | Spare | Row gap | Spaces today | Spaces proposed |
| --- | --- | --- | --- | --- | --- | --- |
| 375 × 667 (4.7-inch) | 20 / 0 | 375 × 500 | none | 0 | rows overlay the picture | unchanged |
| 375 × 812 (5.4-inch) | 50 / 34 | 375 × 500 | none | 0 | rows overlay the picture | unchanged |
| 393 × 852 | 59 / 34 | 393 × 524 | 3 | 2 | 12 · 14 · 8 | 14 · 12 · 6 |
| 402 × 874 | 62 / 34 | 402 × 536 | 10 | 4 | 12 · 17 · 11 | 16 · 15 · 9 |
| 390 × 844 | 47 / 34 | 390 × 520 | 11 | 5 | 12 · 18 · 12 | 17 · 15 · 9 |
| 414 × 896 | 48 / 34 | 414 × 552 | 30 | 11 | 12 · 27 · 21 | 23 · 22 · 16 |
| 430 × 932 | 59 / 34 | 430 × 573 | 34 | 12 | 12 · 29 · 23 | 24 · 23 · 17 |
| 440 × 956 | 62 / 34 | 440 × 587 | 41 | 15 | 12 · 33 · 27 | 27 · 25 · 19 |
| 428 × 926 | 47 / 34 | 428 × 571 | 42 | 15 | 12 · 33 · 27 | 27 · 26 · 20 |

Figures: `spacing-pro-max` (440 × 956) and `spacing-standard` (402 × 874).

What this means, plainly:

- **The large iPhones get the room that was asked for.** The crowded gap more than doubles, and the three spaces come out nearly equal.
- **The 6.1 to 6.3-inch iPhones change by 2 to 5 pt.** They have 3 to 11 spare points in total. More could only come from the picture, which the issue rules out, or from laying the rows over the picture, which the smallest iPhones already do for lack of room. Neither is proposed (decision 1 in the plan).
- **The smallest iPhones do not change.** On a 4.7-inch or 5.4-inch screen the rows already overlay the lower edge of the picture; there is no spare height.

The space under the shutter gets smaller by a third of the spare height (27 to 19 pt on the largest iPhone). The home indicator's 34 pt are below that, so the shutter is still at least 40 pt from the screen's edge.

### 1.4 Other layouts

- **Held sideways.** An iPhone on its side keeps the stacked layout and turns its controls upright, so the same rule and the same numbers apply. The drive strip shows symbols there; its row height is the same.
- **Largest text.** At accessibility sizes the camera uses the scrolling layout: the rows scroll under a 280 pt picture, and the shutter row is pinned. Nothing there is short of room and nothing changes. The existing test of that layout stays.
- **Q open, a dial open, a drive card.** These sit on the picture or cover the rows as today. Q's panel still covers the lens row and the drive strip and never the shutter row; the gap is part of what it covers. Q itself does not change.
- **Clean view.** The rows are hidden; the shutter row takes all the spare height, as today.
- **iPad and the iPhone Duo's inner display (the column layout).** The picture is beside a column of controls, so space there costs the picture nothing. In the column, Q, the shutter and the last photo are 8 pt apart (`NopeSpace.xs`). Proposal: 16 pt (`NopeSpace.m`) above and below the shutter when the column is at least 600 pt tall; a shorter window, such as the Duo's inner display held like a book, keeps 8 pt. The issue names the iPhone only, so this is decision 2 in the plan.
- **Right to left, night mode.** Vertical spacing only; no difference.

### 1.5 Build notes and tests

- `CameraLayout.rowGap(spareHeight:)`, pure, with unit tests for each row of the table, zero and negative spare height, and the cap.
- The spare height must be worked out from the rows' heights without the gap (measure the lens row and the drive strip, not the stack that contains the gap), or the layout feeds its own result back into `bandsHeight`.
- `tokens.md` gains the rule under Sizes; `NopeSize.shutterRowMin`'s note ("takes the remaining height") changes to match.
- `CameraSpacingUITests`: on the largest and the standard iPhone simulators, the picture's frame is `width × 4/3` exactly as before, the three spaces match the table within 1 pt, and the lens controls and the drive strip's targets are at least 8 pt apart wherever the spare height is 2 pt or more. The sideways, iPad and largest-text tests stay.
- Design figures `camera-*` are drawn on a 402 × 874 pt frame with a 59 pt top inset; they move by 4 or 5 pt. Redrawing them is part of the build's design refresh, not of this proposal.

### 1.6 As built

Built for 1.0.0 (wave 1, group D) with the owner's decisions 1 and 2 of 2026-11-21: mid-size iPhones gain only 2 to 5 pt and the smallest none, and the iPad column gets 16 pt around the shutter. Measured on the iOS 27.2 Simulators, the picture's frame is unchanged on every screen, and the insets of the table in 1.3 are confirmed for 375 × 667, 375 × 812, 393 × 852, 402 × 874 and 440 × 956. Two additions to the rule above, both found by measuring, keep every pair of rows' targets 8 pt apart (`NopeSize.targetGap`) without covering more of the picture:

- **Less than 2 pt of spare height** (the 4.7 and 5.4-inch iPhones, where the rows overlay the picture): the lens controls move up by what is missing, inside the rows, which keep their height. On a 4.7-inch iPhone they are 4 pt below the backing's top edge instead of 6; on a 5.4-inch iPhone, where the backing covers 4 pt of the picture, they now start at the picture's lower edge (2 pt below it before). Figure `spacing-small`.
- **A short shutter row** (under 92 pt): its contents move down so the shutter is 8 pt below the drive strip's targets. That is 4 pt on a 4.7-inch iPhone, where the shutter was 6 pt from the strip's targets, and 3 pt on a 393 × 852 pt iPhone (7.7 pt before); the shutter is then 4 and 5 pt above the safe area's lower edge.

The iPhone Duo's inner display held like a book is 635 pt tall inside the safe area ([duo.html](duo.html)), so at the 600 pt threshold it gets 16 pt too, not 8 as 1.4 says; this was not checked on the Duo Simulator.

The figures are redrawn to the build (2026-11-22). A figure of a 402 × 874 pt iPhone now has the 62 pt top inset the Simulator measures and the rows of the table in 1.3: the status line from 62 pt, the picture from 106 to 642 pt, the lens row from 642 pt, the 4 pt gap, the drive strip from 702 pt and a 94 pt shutter row from 746 pt. Q's panel keeps its place 8 pt above the shutter row, so it ends at 738 pt; its tiles are unchanged. This covers the 25 `camera-*` figures, first redrawn at integration of wave 1 with a 59 pt inset and a 5 pt gap, and the figures that were left then with the old rows. The build's own screenshot `guide-invite.png` (iPhone 18 Pro Simulator, iOS 27.2) measures the same: the picture from 106 to 642 pt, the lens group from 648 to 692 pt, the selected drive word from 708 to 740 pt and the shutter from 755 to 831 pt.

Redrawn with them, from the layout code and not from a measurement:

- **Where the rows overlay the picture** (the 4.7-inch figures, the iPhone Duo's outer display, iPad at half of Split View): the lens controls 2 pt higher and the shutter 2 pt lower, as in `spacing-small`.
- **iPad at a third of Split View and in Slide Over** (`ipad-split-third`, `ipad-slide-over`): 65 spare points give a 23 pt gap and a 130 pt shutter row; 1 spare point gives a 1 pt gap, with the lens controls 1 pt higher.
- **The Last Photo viewer** on the 402 × 874 pt frame: the 62 pt inset, and its caption and actions in the place of the drive strip and the 94 pt shutter row, as [viewer.html](viewer.html) specifies. `PhotoViewer.swift` gives the actions `shutterRowMin` (88 pt) as their smallest height and no share of the spare height, so on a device Close may sit 3 pt lower than Last Photo; this was not measured.
- **The first-run and camera-access screens**: the Settings button at the 62 pt inset.

Not redrawn, and still different from the build:

- **Largest text.** The pinned shutter row is drawn 101 pt tall; the code gives it the shutter and 8 pt above and below, 92 pt. Only the top inset changed in these figures.
- **Clean view** (`camera-clean`). The figure keeps the shutter where it is with the rows shown. In the code the hidden rows leave their height to the shutter row; not measured.
- **The column layout** (iPad, the iPhone Duo's inner display). The figures draw Q, the shutter and Last Photo 24 pt apart with 20 pt above and below the column; the build has 16 pt for both in a column at least 600 pt tall.
- **The drive strip's words.** Many figures still show five words; the build has Bracket as the sixth ([drive.html](drive.html) says so).
- **The App Store mockups** (`store-*`) that show a camera figure have the redrawn figure inside; their captions were not re-rendered.

## 2. The how-to-use guide (issue 117)

Decided by the owner: the camera opens ready to shoot with a small card, "How to use nope.", that can be opened or dismissed; it never covers the shutter or blocks a photo; the guide can be opened any time from Settings and About; dismissing is stored on the device only; iPhone and iPad only, with one page about the Apple Watch remote; a few short screens, one idea each; the two key ideas in one sentence each with a link for more; only shipped behavior; built last.

### 2.0 As built (group H, 2026-11-21)

Built on `n100-H` with the owner's decisions of 2026-11-21, which change the page list below: seven pages, one idea each, as the owner listed them (shooting, lenses, Auto and manual, drive modes, Q, unprocessed photos, privacy), with the two key ideas kept right after shooting as the issue asks. Lenses and Auto get a page each, and the Apple Watch page is not built. The pages as built: 1 Take a photo; 2 Photos as the camera took them (link About processing); 3 Private by design (link Details in Each Photo); 4 Lenses ("Tap a lens to switch to it. Switch Camera turns to the front camera and back.", one of four sentences by the device's lenses); 5 Auto and manual ("Tap Auto to set the exposure and focus yourself. Tap Manual to go back to full auto."); 6 One photo or a series ("Single, Timer, Burst and the other modes choose what a press does: one photo, a timer or a series.": "above the shutter" is not true in the column layout); 7 Q and Settings ("Tap Q to open the Quick Menu. Everything else is in Settings.": Q described as it is, a button that opens the menu). The card stays until Open or Dismiss (decision 3), Factory Defaults keeps it away (decision 4), and both rows are "How to Use nope." (decision 6). The `guide-*` PNGs are screenshots of the build; their HTML carries the same words. Pictures are drawn by the camera's own views (shutter, lens buttons, Switch Camera, Auto, drive words, Q) or a symbol (RAW seal, lock); the audit's "Potentially inaccessible text" finding for that decorative text is set aside while the guide is open (`docs/TESTING.md`). The page number shows "2 of 7" and VoiceOver reads it as "Page, 2 of 7" (the label "Page" with the number as its value, 2026-11-22): a shown "2 of 7" labelled "Page 2 of 7" was reported as clipped text by the accessibility audit on iPad. Strings 19 and 20 (Apple Watch) are not used; string 1, the card's name, uses the key "Guide card: How to use nope." (it and string 4 would otherwise make the same catalog symbol).

### 2.1 The invitation card

Figures `guide-invite`, `guide-invite-night`.

- **Where.** On the lower edge of the picture, in the stack that holds the drive cards and hints (`pictureBottomStack`), with the same backing and radius as those cards. It covers no control. In the column layout it sits in the same stack on the picture.
- **What it has.** The name "How to use nope.", a capsule button Open, and a round Dismiss button with an ✕. Both buttons are 44 pt targets.
- **When it shows.** After the first-run screen and the camera permission, once the picture is live. Not during the start indicator, not in clean view, not while a countdown or a series runs, not in the Lock Screen camera, and not over the permission or paused messages.
- **It gives way.** A drive card, a dial, a hint or a warning shown in the same stack takes its place while it shows; the card returns afterwards. Taking a photo does not put it away.
- **How it leaves.** Open or Dismiss. Either one is final: the card is not shown again on this device. Nothing leaves on a timer. Proposal: it stays until one of the two is pressed, however many launches that takes (decision 3).
- **What is stored.** One true-or-false value in the app's own settings on the device, with the other settings. It is not a count, not a date, and nothing is sent. Factory Defaults does not bring the card back; the guide stays in Settings (decision 4).
- **People updating from an earlier build** see the card once too.

### 2.2 The guide

A sheet over the camera with seven pages, one idea each. Figures `guide-page-1` to `guide-page-7`, `guide-page-night`, `guide-page-largest`.

| # | Title | Text | Link | Picture |
| --- | --- | --- | --- | --- |
| 1 | Take a photo | Press the shutter or a volume button. Photos are saved to the Photos app. | | The shutter |
| 2 | Photos as the camera took them | nope. saves each photo with as little processing as the camera allows, so it can look flatter or noisier at first. | About processing → Settings › Honesty | The RAW status |
| 3 | Private by design | nope. never connects to the internet, and you choose which details each photo keeps. | Details in Each Photo → Settings › Details in Each Photo | A lock symbol |
| 4 | Lenses and manual controls | Tap a lens to switch. Tap Auto to set the exposure and focus yourself. | | The Manual Controls button and the lens group |
| 5 | One photo or a series | The words above the shutter choose what a press does: one photo, a timer or a series. | | The drive strip |
| 6 | Q and Settings | Q opens the settings you change most. Everything else is in Settings. | | The Q button |
| 7 | Apple Watch | With nope. on an Apple Watch, the watch is a remote shutter. | | A watch symbol |

Rules for the content:

- **The two key ideas are pages 2 and 3,** right after the one page that says how to take a photo. Each is one sentence and one link. The sentences claim no more than the first-run statements and the Honesty screen do; they go in `Honesty.xcstrings`.
- **Nothing a device may lack is named.** Page 1 does not name Camera Control; page 5 does not list Astro or any other mode; page 4 leaves out its first sentence on a device with one rear lens. Page 5 says "above the shutter", which the builder checks against every layout (section 8).
- **Pictures are the controls themselves.** Each page shows the control it talks about, drawn by the same view the camera uses (the shutter, the format status, the lens group, the drive strip, the Q button), not a screenshot. So no picture carries baked-in text, the guide follows night mode, text size and language by itself, and it cannot drift from the camera. The pictures are decoration: hidden from VoiceOver, and not buttons.
- **Seven pages** is the upper end of "a few". A five-page version would drop pages 6 and 7 and leave Q and the watch to be found (decision 5).

Moving and closing:

- **Next** and **Back** buttons on every page (Back is absent on page 1; Next reads **Done** on page 7), the page as "2 of 7" in words, and a Close button in the bar. A swipe moves between pages too; the buttons are the visible alternative.
- Close, Done, or dragging the sheet down closes the guide. Opening the guide once counts as having seen the invitation.
- A link closes the guide and opens Settings at its page.
- Nothing advances by itself.
- A volume button or Camera Control press while the guide is open does what it does over any other sheet; the guide adds no rule.

### 2.3 Where it is reopened

Figure `guide-settings-row`.

- **Settings › More › How to Use nope.**, first in the group. Search keywords: help, guide, how, instructions, tutorial, start.
- **About** gets a row that opens the same guide. The About screen uses the app's full name elsewhere; the row keeps the guide's own title so the two rows read the same (decision 6).
- Both open at page 1, whether or not the card was dismissed.

### 2.4 Devices and accessibility

- **iPhone and iPad.** The guide is the system's sheet: a card on iPhone, a form sheet on iPad and the Duo's inner display, with the text at a readable width. No guide on Apple Watch (decided).
- **VoiceOver.** The card is one group after the picture's own elements: "How to use nope.", then Open ("Opens the guide") and Dismiss ("Hides this card"). It does not take focus when it appears. In the guide each title is a heading; a page reads title, text, link, then Back, "Page 2 of 7", Next. Moving to a page announces its number and title.
- **Voice Control** names are the visible words: Open, Dismiss, Next, Back, Done, Close, and each link's text.
- **Switch Control and a keyboard** reach every button; the arrow keys move between pages and Escape closes.
- **Largest text.** The page scrolls; Back, the page number and Next stay pinned under it, as Continue does on the first-run screen. On the camera the card's name wraps and its buttons move under it.
- **Reduce Motion.** Pages cross-fade instead of sliding.
- **Night mode.** Red on black; a link is underlined, so it is not marked by color alone.
- **Right to left.** Back and Next swap sides and the pages run the other way.

### 2.5 Tests

Unit tests for when the card shows and what puts it away (each state of 2.1), and that the stored value survives a relaunch and Factory Defaults. UI tests, each with `performAccessibilityAudit()`: the card on first launch and its two buttons; every page; both links; the Settings and About rows; night mode; the largest text size; right to left; iPad. A test that the camera's shutter takes a photo while the card shows.

## 3. The summary card of What's in This Photo (issue 118)

### 3.1 What exists

`PhotoSummaryCard` is one cell: the formats in a large weight with the lens and time pushed to the trailing edge, the pixels and file size under them, then four lines, each a symbol and a sentence. The symbols are drawn at their own widths, so the sentences start at different places; the signing line, "Saved. Not signed: signing is off in Settings.", is two thoughts in one line and wraps; and the whole card is one VoiceOver element that reads everything in one go.

### 3.2 The new card

Figures `summary-raw`, `summary-processed`, `summary-night`, `summary-largest`, `summary-rtl`.

One group, built like the groups under it:

- **The head.** The format (or formats) as the title, then two lines in the secondary style and one size, all on the leading edge: lens and time, then pixels and total file size.
- **One row for each fact,** with a separator between rows as in every other group, always in this order:
  1. what kind of file it is;
  2. the signature;
  3. the optional details;
  4. the location.
- **One symbol column.** Every symbol is centered in a column of one width that grows with the text size, so every row's words start on the same line.
- **Color as today:** amber with a triangle for a warning (a processed photo, a failed signature, a location in the files), teal for the one verified fact (signed), secondary for the rest.

Order of importance is what the issue asks for: the format and whether it is RAW first, then signing, then what the file keeps.

### 3.3 Wording

| Fact | Today | Proposed |
| --- | --- | --- |
| RAW only | RAW: one frame of sensor data | unchanged |
| RAW with copies | RAW: one frame of sensor data, and a HEIF copy developed by nope. | unchanged |
| Processed by the phone | (the Processing group's sentence) | **Processed by this iPhone** / second line: This lens can't save RAW |
| Signed | (the camera's message after a photo) | **Signed** |
| Signing off | Saved. Not signed: signing is off in Settings. | **Not signed** / second line: Signing is off in Settings |
| Signing failed | (the camera's message) | **Not signed** / second line: The signature couldn't be made |
| Details | No optional details in the files · N optional details in the files | unchanged |
| Location | No location in the files · Location is in the files | unchanged |

"Saved." goes: every photo in this sheet was saved. The signing row becomes a state and, under it in the secondary style, the reason. The full explanation stays in the Content Credentials group, which is unchanged. "iPhone" reads "iPad" on an iPad. All of these are Honesty wording.

### 3.4 Range

- **VoiceOver.** The head is one element ("RAW, DNG. 1×, 2:41 PM. 4032 by 3024 pixels, 24.1 megabytes"); each row is one element, read once, in order, with its second line as part of it; a warning row begins with "Warning".
- **Largest text.** The symbol column grows, each row wraps under its own first word, the head's lines stack (figure `summary-largest`).
- **Right to left.** The symbol column is on the right; "1× · 2:41 PM" and the pixel size keep their order.
- **Night mode.** Red on the night row color; warnings are told by the triangle and the words.
- **iPad.** The same group at the sheet's width.

An all-rows version, with Format, Lens, Taken, Size and File Size as label and value rows, was considered and not proposed: it puts five rows before the first fact and loses the order of importance.

### 3.5 Tests

`PhotoDetailsTextTests` and `PhotoDetailsUITests` updated: each row's text for each state of the table; the rows' order; one accessibility element for each row; the audits at the largest text size, right to left and in night mode. The identifier `PhotoDetails.summary` stays on the head.

## 4. Dim After (issue 119)

Decided by the owner: a Dim After choice under Keep Screen On replaces the fixed 2 minutes; choices such as 1, 2 (the default) and 5 minutes and Never; with Never, Low Power Mode still dims after its own delay, Battery Low still ends Keep Screen On, the 30-minute limit stays and the thermal state is respected; a short note under the choice gives the cost; stored like the switch, and found by search.

### 4.1 The row

Figures `dim-after-row`, `dim-after-menu`, `dim-after-never`, `dim-after-night`.

- **Place.** Settings › Screen, directly under Keep Screen On.
- **Form.** A menu row, as Pinch is in the Camera group: **1 Minute, 2 Minutes, 5 Minutes, Never.** 2 Minutes is the default, so nothing changes for anyone who does not open the menu.
- **Always shown and always usable,** whether Keep Screen On is on or off, in keeping with the Settings rule that no row appears or disappears when a switch changes. Its note begins with where it is used.
- **Not in the Lock Screen camera's Settings,** as Keep Screen On is not.

### 4.2 The notes

Keep Screen On's explanation loses its words about dimming, which move to the new row:

> While the camera is showing, the screen stays on for 30 minutes after your last touch or photo. Uses more battery. Not used while Battery Low shows.

Under Dim After, always:

> With Keep Screen On, the screen dims after this long without a touch or photo.

With Never chosen, the note continues:

> Never uses more battery and can warm the phone. The screen still dims in Low Power Mode and when the phone is hot.

The owner's sentence is kept nearly whole; "Never" is put in front so the cost is tied to the choice that has it. The 30-minute limit and Battery Low are already in the row above and are not repeated. VoiceOver reads the note with the row.

### 4.3 Behavior

| Case | With 1, 2 or 5 minutes | With Never |
| --- | --- | --- |
| No touch or photo for the chosen time | Dims to 10% with the Brighten Screen cover | Stays at its brightness |
| Low Power Mode | Dims after 30 seconds | Dims after 30 seconds |
| The phone is hot (heat level serious) | Dims after 30 seconds (proposed, decision 7) | Dims after 30 seconds |
| Heat level critical | The camera pauses, so Keep Screen On is not used | the same |
| Battery Low shows | Keep Screen On is not used | the same |
| 30 minutes without a touch or photo | Keep Screen On ends; Auto-Lock applies | the same |
| The screen is already at 10% or darker | Not dimmed, no cover | the same |

"The thermal state is respected" is given a meaning here: at the serious heat level the screen dims after 30 seconds whatever is chosen, as in Low Power Mode. Today heat changes nothing about dimming until the camera pauses at critical.

**Series are not affected.** An interval series or an Astro run dims the screen at once when it starts, as today, whatever Dim After says. The setting belongs to Keep Screen On only (decision 8).

### 4.4 Storage, presets, search, Honesty

- Stored with the other settings as a named choice (`oneMinute`, `twoMinutes`, `fiveMinutes`, `never`); an unknown stored value reads as 2 Minutes. In presets and reset by Factory Defaults.
- Search keywords: dim, brightness, bright, never, battery, heat, warm.
- The Honesty screen's Keep Screen On entry gains the sentence about Never and the two cases where the screen still dims.
- No Q tile, no pill, nothing new on the camera. No Shortcuts action.

### 4.5 Tests and device checks

`KeepScreenOnTests` with the fake screen and clock: each choice dims at its time; Never does not dim; Never in Low Power Mode and at the serious heat level dims after 30 seconds; Battery Low and the 30-minute limit end it under every choice; an unknown stored value; presets and Factory Defaults. `KeepScreenOnUITests`: the row, the menu, the note for each choice, search, the largest text size, right to left, night mode, each with the audit. On a device: each choice with a stopwatch; Never for 30 minutes with the battery and temperature noted before and after, which is the evidence for "uses more battery and can warm the phone".

## 5. Burst Limit (issue 121)

Decided by the owner: a Burst Limit setting, Off (the default), 3, 5, 10, 20 or 50, stored and in presets; with a limit, a tap or a hold starts a burst that runs to the count even after the finger lifts; a second tap, or a hardware button press, stops after the photo being taken, and every photo taken is saved; VoiceOver and Switch Control get a Stop action; Siri and Shortcuts are unchanged; a new end reason for reaching the count; the card shows the count against the limit.

### 5.1 The setting

Figure `burst-count-setting`.

- **Place.** Settings › Camera, the last row, after Pinch.
- **Form.** A menu row: **Off, 3, 5, 10, 20, 50.**
- **Explanation:** "In Burst, one press takes this many photos; press again to stop early. Off: a tap takes one photo, and holding takes photos until you let go." It begins with where the setting is used, as the scope rule asks.
- Search keywords: burst, limit, count, frames, series, continuous.
- It applies in the Lock Screen camera too, since settings are shared.

### 5.2 On the camera

Figures `burst-count-idle`, `burst-count-running`, `burst-count-summary`.

| State | With the limit Off (today) | With a limit of 10 |
| --- | --- | --- |
| Idle card, title | Fast burst | Fast burst · 10 photos |
| Idle card, second line | Hold the shutter. A tap takes one photo. | A press takes 10 photos. Press again to stop. |
| Idle card, button | Start Burst | none: a press already starts the burst |
| Running, title | Photos taken: 12 | 3 of 10 |
| Running, second line | 2.6 a second · Release to stop | 2.6 a second · Press to stop |
| Running, shutter | The held disc | The stop square, as during a series |
| Running, bar | none | A bar, by photos taken |
| After | 12 photos saved | 10 of 10 photos saved |
| After, stopped early | 4 photos saved | 4 of 10 photos saved, with the reason |

- The waiting-to-save row and the saving line of the burst card are unchanged.
- A limit of 50 ends as "50 of 50 photos saved", by the count, not as the cap being reached.
- Low storage, the camera stopping and a failed photo still end a burst early, with their sentences of today.
- The burst speed menu is unchanged; the limit works with Fast and Slow.
- The Apple Watch remote is unchanged; the builder records what the watch's shutter does in Burst today and keeps it (decision 9).

### 5.3 Accessibility

- **VoiceOver.** The shutter's value: "Burst, fast, 10 photos." Its hint: "Double tap to take 10 photos. Double tap again to stop." While the burst runs the shutter's action is **Stop**, and the card is one element that reads "3 of 10" when focused. The count is not spoken for every photo, which would talk over itself at several photos a second; VoiceOver hears "Burst started, 10 photos." and the summary at the end.
- **Switch Control and Voice Control** get the same Stop action; the Start Burst action stays, with the same result as a press.
- Largest text, right to left and night mode follow the burst card as designed in [BURST.md](BURST.md).

### 5.4 Tests

As listed on the issue. In addition: a limit above what storage allows; the limit changed by a preset while Burst is selected; the Lock Screen camera.

## 6. The self-timer counts to a fixed deadline (issue 122)

Nothing looks different. What a person can notice:

- A 10-second timer takes its photo 10 seconds after it was started, not a little later. Today each second's tick adds the time the app takes to wake, so the photo is late by the sum of those delays.
- The number shown is the whole seconds left until that moment, rounded up. If the app is held up for more than a second, a number can be skipped; the photo is still on time. Today the number never skips and the photo is late instead.
- The haptic tick and VoiceOver's count follow the number shown, so they can skip with it.
- Stopping the timer works as today.

The same countdown runs the Astro start delay and the delays of the Take Photo and Take Bracket actions, so they gain the same accuracy. No string changes.

## 7. Interval photos are spaced start to start (issue 123)

Decided by the owner: each photo starts one interval after the last one started; if a photo takes longer than the interval, the next starts as soon as the camera is ready, with no catch-up photos, and the card says the interval is shorter than the photo takes; a paused series takes its next photo right away when it resumes if its time has passed, and the schedule continues from that photo; "Next photo in" counts to the next scheduled start; the "At most N" estimate stays.

What a person sees:

- **Interval Shooting, the sentence under the rows** (figure `interval-start-settings`). Today: "Takes 10 photos, 10 seconds apart." Proposed: "Takes 10 photos, starting one every 10 seconds." The same change for the sentence of a series that stops after a time.
- **The running card.** "Next photo in 6s" counts to the moment the next photo starts. With a 2-second exposure every 10 seconds it now reads 8 when the photo is saved, not 10.
- **When photos take longer than the interval** (figure `interval-start-behind`): the second line reads "Each photo takes longer than the interval" in place of the countdown, from the first photo that overran until one fits its interval again. It is plain text, not a warning chip: the series keeps going and loses nothing but pace. VoiceOver hears it once, when it first applies.
- **A series that stops after a number of photos** now ends when its estimate says, as long as each photo fits the interval.
- **The Live Activity** is unchanged: it shows counts and the time left, not the next photo.

Proposal beyond the issue: when the shutter time is set by hand and is longer than the interval, Interval Shooting says so before the series starts, in the same sentence's place: "The shutter time is longer than the interval, so photos follow one another." The app knows this in advance only with a manual shutter (decision 10).

## 8. Draft strings for the Honesty review

Every new or changed string above, in one place. "Honesty" marks the strings that belong in `Honesty.xcstrings` because they make a claim about processing, privacy, signing or cost; the rest go in `Localizable.xcstrings`. None is final.

| # | String | Where | Honesty |
| --- | --- | --- | --- |
| 1 | How to use nope. | Card on the camera | |
| 2 | Open | Card button | |
| 3 | Dismiss | Card button's name | |
| 4 | How to Use nope. | Guide title; Settings and About rows | |
| 5 | Take a photo | Guide 1, title | |
| 6 | Press the shutter or a volume button. Photos are saved to the Photos app. | Guide 1 | |
| 7 | Photos as the camera took them | Guide 2, title | Honesty |
| 8 | nope. saves each photo with as little processing as the camera allows, so it can look flatter or noisier at first. | Guide 2 | Honesty |
| 9 | About processing | Guide 2, link | |
| 10 | Private by design | Guide 3, title | Honesty |
| 11 | nope. never connects to the internet, and you choose which details each photo keeps. | Guide 3 | Honesty |
| 12 | Details in Each Photo | Guide 3, link (the existing page name) | |
| 13 | Lenses and manual controls | Guide 4, title | |
| 14 | Tap a lens to switch. Tap Auto to set the exposure and focus yourself. | Guide 4 | |
| 15 | One photo or a series | Guide 5, title | |
| 16 | The words above the shutter choose what a press does: one photo, a timer or a series. | Guide 5 | |
| 17 | Q and Settings | Guide 6, title | |
| 18 | Q opens the settings you change most. Everything else is in Settings. | Guide 6 | |
| 19 | Apple Watch | Guide 7, title | |
| 20 | With nope. on an Apple Watch, the watch is a remote shutter. | Guide 7 | |
| 21 | Next · Back · Done · Close · %lld of %lld | Guide buttons and page number | |
| 22 | Processed by this iPhone (iPad) | Summary row | Honesty |
| 23 | This lens can't save RAW | Summary row, second line | Honesty |
| 24 | Signed | Summary row | Honesty |
| 25 | Not signed | Summary row | Honesty |
| 26 | Signing is off in Settings | Summary row, second line | Honesty |
| 27 | The signature couldn't be made | Summary row, second line | Honesty |
| 28 | While the camera is showing, the screen stays on for 30 minutes after your last touch or photo. Uses more battery. Not used while Battery Low shows. | Keep Screen On, changed | Honesty |
| 29 | Dim After | Row | |
| 30 | 1 Minute · 2 Minutes · 5 Minutes · Never | Menu | |
| 31 | With Keep Screen On, the screen dims after this long without a touch or photo. | Dim After, note | |
| 32 | Never uses more battery and can warm the phone. The screen still dims in Low Power Mode and when the phone is hot. | Dim After, note with Never | Honesty |
| 33 | Burst Limit | Row | |
| 34 | In Burst, one press takes this many photos; press again to stop early. Off: a tap takes one photo, and holding takes photos until you let go. | Burst Limit, explanation | |
| 35 | Fast burst · %lld photos (and Slow) | Burst card, idle | |
| 36 | A press takes %lld photos. Press again to stop. | Burst card, idle | |
| 37 | %lld of %lld | Burst card, running | |
| 38 | Press to stop | Burst card, running | |
| 39 | %lld of %lld photos saved | Burst summary | Honesty |
| 40 | Burst, fast, %lld photos. · Double tap to take %lld photos. Double tap again to stop. · Burst started, %lld photos. | VoiceOver | |
| 41 | Takes %lld photos, starting one every %@. | Interval Shooting | Honesty |
| 42 | Each photo takes longer than the interval | Interval card | Honesty |
| 43 | The shutter time is longer than the interval, so photos follow one another. | Interval Shooting, if decision 10 is yes | Honesty |

String 16 says "above the shutter"; the builder checks it against each layout and, if it is not true in one, the sentence loses those three words. String 32 depends on decision 7: without it, the sentence ends at "Low Power Mode".
