# Settings plan

Status: accepted 2026-11-17. The owner accepted all twelve recommendations in section 7. The design set in this folder has been redrawn to match: Settings in [settings.html](settings.html), the device coverage in [layouts.html](layouts.html), [ipad.html](ipad.html), [duo.html](duo.html) and [watch.html](watch.html), and the build steps in [BUILD-SPEC.md](BUILD-SPEC.md).

This file is kept as the record of the review and of the decisions. Sections 1 to 6 are the review as written on 2026-11-17, before the decisions: they describe the set as it was then ("direction B as drawn", 122 screens) and use the names of that time, such as Choose Details and Face Detection. Where they say "proposed", read "accepted". Section 7 records each decision and its outcome.

A diagram of the tree is in [settings-tree.html](settings-tree.html).

Sources: issue 74 and its comments (menus and paths, no burying in Settings, two levels at most, accessibility, Siri names, Q), issues 75 to 81 (release 1.0.0), issues 82 and 83 (release 1.1.0, read only to leave room), the direction B set in this folder, and the code (`Sources/NopeUI/SettingsScreen.swift` and the pages it opens, `Sources/NopeCore/NopeSettings.swift`, `SaveSettings`, `MetadataSettings`, `OverlayOptions`, `DevelopedFileOptions`, `SettingsPresets`, the App Intents, the watch app, and the string catalogs).

Scope rule: release 1.0.0 changes only the interface of features that already exist. Every proposal below moves, renames, merges or rewords an existing setting. None adds a capability.

How taps are counted: from the camera screen on iPhone, as in [navigation.md](navigation.md). Settings is one tap in 0.3.0 (its own button) and two in direction B (Q, Settings). On iPad and the iPhone Duo inner display Settings keeps its own button, so every Settings path there is one tap shorter than the iPhone figure.

## 1. Inventory

Every stored setting, and every Settings row that is not a stored setting. "B" is the direction B set as drawn. Defaults are those for 1.0.0; a default changed by issue 80 is marked.

### 1.1 What each photo saves

| Setting | 0.3.0: place (taps) | B: place (taps) | Default in 1.0.0 | Also reachable from |
| --- | --- | --- | --- | --- |
| Formats: RAW (DNG), HEIF, JPEG | Settings › Formats (3); format chip (2) | Settings › Formats (4); Format status sheet (2) | RAW only (issue 80; was RAW and HEIF) | Format status sheet. Presets |
| Paired with RAW (HEIF or JPEG) | Settings › Formats › picker (4) | Same (5) | HEIF. Shown only when all three formats are saved | Presets |
| Look (Standard, Flat) | Settings › Look (3) | Settings › Look (4); Format status sheet › Look (3) | Standard. Row shown only when a copy is on | Format status sheet. Presets |
| HEIF Compression | Settings › File Options › picker (4) | Same (5) | System Default | Presets |
| HEIF Bit Depth | Same (4) | Same (5) | 10-bit | Presets |
| JPEG Compression | Same (4) | Same (5) | Maximum Quality | Presets |
| Color Space | Same (4) | Same (5) | Display P3 | Presets |
| Copy Size | Same (4) | Same (5) | Full Size | Presets |
| Restore Defaults (File Options) | Settings › File Options (3) | Same (4) | An action; shown when something is changed | – |
| Photo Size, one per lens without RAW | Settings › Photo Size › picker (4) | Same (5) | Each lens's default size. Row shown only when a lens offers sizes | Set Photo Size shortcut. Presets |
| Mirror Front Camera | Settings › Camera (2) | Settings › Camera (3) | Off. Shown when there is a front camera | Presets |

### 1.2 Privacy and signing

| Setting | 0.3.0: place (taps) | B: place (taps) | Default in 1.0.0 | Also reachable from |
| --- | --- | --- | --- | --- |
| Remove All Optional Details | Settings › Privacy (2), and again at the top of Choose Details (3) | Same two places (3 and 4) | On | Presets |
| Location | Settings › Choose Details (3) | Same (4) | Off; needs location access | Search. Presets (a preset with Location still asks for access) |
| Date and Time Taken | Choose Details (3) | Same (4) | Removed while the master switch is on. On once details are chosen one by one | Presets |
| Sub-Second Time | Same | Same | Off | Presets |
| Time Zone | Same | Same | Off | Presets |
| Camera Make and Model | Same | Same | On once details are chosen one by one | Presets |
| Lens Make and Model | Same | Same | On once chosen one by one | Presets |
| Exact Model for RAW Editors | Same | Same | On once chosen one by one | Presets |
| Lens Correction Instructions | Same | Same | On once chosen one by one | Presets |
| Exposure Settings | Same | Same | On once chosen one by one | Presets |
| iOS Version | Same | Same | Off | Presets |
| Maker Notes | Same | Same | Off | Presets |
| App Name and Version | Same | Same | On once chosen one by one | Presets |
| Standard File Tags | Choose Details (3) | Same (4) | On; outside the master switch | Presets |
| Your Name and Copyright (name, notice) | Stored, with strings, but not offered on any screen | Not drawn | Off, empty | – |
| Sign Each Photo | Settings › Privacy (2) | Same (3) | Off (issue 80; was on) | Presets |
| Always Saved (seven items) | Choose Details, read only | Same | Always on, locked | – |

### 1.3 Camera behavior and the camera screen

| Setting | 0.3.0: place (taps) | B: place (taps) | Default in 1.0.0 | Also reachable from |
| --- | --- | --- | --- | --- |
| Manual Controls | Settings › Camera (3); the M pill turns it off | Camera button (1). Removed from Settings (issue 77) | Off | Presets. Astro turns it on |
| Start in Clean View | Settings › Camera (2) | Same (3) | Off | Presets |
| Fast Shutter (Standard, 1/500 s, 1/1000 s) | Quick Controls (3); Settings › Fast Shutter (3) | Q tile (3); Settings › Fast Shutter (4) | Standard | Set Fast Shutter shortcut. Its pill. Presets |
| Face Detection | Settings › Camera (2) | Same (3) | Off (issue 80; was on) | Set Face Detection shortcut. Presets |
| Show Processed Marker | – | Settings › Camera (3); foot of the processing note (2) | On (new switch, issue 80) | Presets, Lock Screen camera |
| Grid | Quick Controls (3); Settings › Viewfinder Overlays (3) | Q tile (3); Settings › Viewfinder Overlays (4) | Off | Presets |
| Grid Style (Thirds, 4 × 4, Square) | Same | Same | Thirds (two styles removed, issue 76) | Presets |
| Level | Quick Controls (2); Viewfinder Overlays (3) | Q tile (2); Viewfinder Overlays (4) | Off | Presets |
| Focus Peaking | Pro Tools (3, with Manual Controls on); Viewfinder Overlays (3) | Same (3 and 4) | Off | Presets |
| Histogram | Same | Same | Off. Shown with the manual controls | Presets |
| Live Camera Readout | Quick Controls (3); Pro Tools (3); Viewfinder Overlays (3) | Q tile (3); Pro Tools (3); Viewfinder Overlays (4) | Off | Presets |
| Keep Readout in Clean View | Quick Controls menu (3); Viewfinder Overlays (3) | Q tile menu (3); Viewfinder Overlays (4) | Off | Presets |
| Night Mode | Quick Controls (2); Settings › Camera (2) | Q tile (2); Settings › Screen (3) | Off | Control Center. Siri (on and off). Set Night Mode. Presets |
| Keep Night Mode After Astro | – | Settings › Screen (3), where the device offers Astro (added 2026-11-18) | Off: leaving Astro turns night mode off again if Astro turned it on | Presets, Lock Screen camera |
| Red Viewfinder | Settings › Camera (2); row shown only while Night Mode is on | Settings › Screen (3); same condition | Off | Presets |
| Live Activity | Settings › Camera (2); where the device offers it | Settings › Screen (3) | Off | Presets |

### 1.4 Remembered values with no Settings row

| Value | Where it is set | Default |
| --- | --- | --- |
| Flash (Off, Auto, On) | Q tile; its pill | Off; remembered between launches |
| Light brightness | The Light pill | Its default level; remembered. The Light itself always starts off |
| Saved presets | Q › Presets; Settings › Presets | None saved |

Kept for the session only, so not settings: the self-timer delay, the interval and number of photos, Astro frames and start delay, bracketing, exposure mode, metering, the locks, Close-Up, Far Focus, Magnify, Compare, exposure compensation and every manual value. A preset stores them. On Apple Watch, the Delay (Off, 3 seconds, 10 seconds) is kept only while the watch app runs.

### 1.5 Rows that are not settings

| Row | 0.3.0 (taps) | B (taps) | Notes |
| --- | --- | --- | --- |
| Presets: apply, Save Current Settings, Factory Defaults, Undo | Settings › Presets (2 to open); Quick Controls (2) | Settings › Presets (3); Q › Presets (2) | Apply Preset shortcut |
| Presets: rename, delete | Presets › Rename or Delete › preset (three levels) | A More menu on each preset (two levels) | Delete asks first |
| Accessibility | Settings › More (2) | Same (3) | A page of facts; no switches |
| Honesty | Settings › More (2) | Same (3) | |
| About and Licenses; License; Notices and Trademarks | Settings › More (2; 3) | Same (3; 4) | Deepest pages: two levels |

### 1.6 Siri and Shortcuts actions that set a setting

Unchanged in number: Set Night Mode (with phrases), Set Fast Shutter, Set Face Detection, Set Photo Size, Apply Preset. Formats, privacy, signing and overlays have no action. Issue 82 covers more actions for 1.1.0.

## 2. Problems found

### 2.1 Duplicates

1. **Remove All Optional Details appears twice**, on the Settings list and at the top of Choose Details. Both change one value, but the Settings list shows the switch without its explanation and the page shows it with one. Two rows for one decision also makes the Privacy group look longer than it is.
2. **Interval Shooting has two homes that behave differently.** In direction B the drive strip selects Interval and the shutter starts the series. Pro Tools still has its own Interval section with its own Start button, reachable only with Manual Controls on. Issue 74 asks to avoid duplicates that behave differently.
3. **Three overlay switches are in three places**: Focus Peaking, Histogram and Live Camera Readout are in Pro Tools ("Live Aids"), in Settings › Viewfinder Overlays, and the Readout is also a Q tile. They change the same values, so this is acceptable, but the three places use two section names ("Live Aids" and "Viewfinder Overlays") and three words for one state: the Q tile says "Pinned", the menu and the page say "Keep Readout in Clean View".
4. **Look is in two places** (Format status sheet, and Settings), which is fine; but the Settings row is called only "Look" and the sheet's row leads to the same page with a different way back.

### 2.2 Settings in the wrong group

5. **Mirror Front Camera is under Camera, but it changes the saved photo**, not the camera screen (the viewfinder is mirrored either way). It is stored with the save settings and belongs with Photos.
6. **Camera mixes behavior and display.** Fast Shutter and Face Detection change how the camera exposes and focuses. Start in Clean View, Viewfinder Overlays and Show Processed Marker change what the camera screen shows. Night Mode and Red Viewfinder, which also change what the screen shows, are in a different group (Screen).
7. **The "More" group** holds a help page (Accessibility), the honesty statements and About. The name says nothing, but it is short in every language. Kept; see 3.4.

### 2.3 Unclear names

8. **Choose Details** does not say which details or of what. It is the page where location is written, which issue 74 names as a test task. The value beside it, "All Optional Removed", carries the meaning the title lacks.
9. **Look** and **File Options** do not say they apply only to HEIF and JPEG copies. Both pages need the same footer to explain it.
10. **Photo Size and Copy Size** are easy to confuse: Photo Size is for lenses without RAW; Copy Size is for HEIF and JPEG copies.
11. **"Standard"** is the default value of both Fast Shutter and Look, so "Standard" on a row or tile does not identify the setting by itself. Acceptable while each value always appears beside its name.
12. **Face Detection** names what the system does, not what the switch controls. The switch decides whether autofocus and auto exposure follow faces. The Honesty page says iOS may still detect faces to focus. With the switch off by default (issue 80), the name can be read as "no face detection happens", which the app has not verified. See 2.6.
13. **Viewfinder Overlays shows only "Off" or "On"** on the Settings list, for seven values.

### 2.4 Long paths, hidden rows and dead ends

14. **Every Settings path is one tap longer on iPhone** than in 0.3.0, because Settings opens from Q. The set accepts this for set-once options. It matters for the two tasks people look for by name: "find where location is written" goes from 3 taps to 4, and File Options and Photo Size go from 4 to 5.
15. **Rows appear and disappear on the Settings list.** Look and File Options exist only while a HEIF or JPEG copy is on; with RAW only as the new default, a fresh install shows neither, and search cannot find "JPEG Compression" or "Color Space". Red Viewfinder exists only while Night Mode is on, so it cannot be set before going out in the dark, and turning Night Mode on moves the rows below it.
16. **Factory Defaults is inside Presets**, and the build spec shows the Presets row only when a preset is saved. In the code the row is always shown. If it were hidden, Factory Defaults would be unreachable from Settings on a fresh install. People look for "reset" at the end of a settings list, and search has no entry for that word.
17. **Manual Controls leaves Settings** (issue 77) with nothing left behind. Someone who learned it in 0.3.0, or who looks in Settings first, finds no trace. The same applies to Self-Timer, Flash and Grid for people who look in Settings before the camera.
18. **Focus Peaking in full auto is only in Settings** (four taps). In Pro Tools it needs Manual Controls on. Issue 74 lists focus peaking as "easy to reach" for close-up work, and the rule in navigation.md says nothing used while shooting is only in Settings.
19. **Bracketing is only in Pro Tools**, so only with Manual Controls on, although "Take a bracket with nope." works by voice at any time. Noted; no change proposed for 1.0.0 (see 3.5). *Superseded on 2026-11-18: Bracket is a word on the drive strip in 1.0.0, in full auto too ([BRACKETING.md](BRACKETING.md), decisions 1 and 2).*

### 2.5 On the camera or in Q instead, or the reverse

20. Fast Shutter has both a Q tile and a Settings page. Its home is Q (it is changed while shooting, and has a pill). The Settings page is kept because it holds the explanation and gives search a destination; settings.html calls it "its one predictable place" and navigation.md says the same of the Q tile. The set should say one thing: Q is the home, the page is the second way in.
21. Night Mode is in Q, Settings, Control Center and Siri. All change one value. Kept.
22. Nothing in Settings needs to move to the camera screen apart from Focus Peaking (item 18). Start in Clean View, Face Detection, Show Processed Marker, Mirror Front Camera, Red Viewfinder, Live Activity, signing and the details are set once and belong in Settings.

### 2.6 Wording that may claim too much

23. **Face Detection** (item 12): rename, or verify on a device what Off does and say exactly that.
24. **Standard File Tags**: "They say nothing about you, your phone or the photo." The tags include the color space, which is a fact about the photo, and a GPS version tag is written when a location is. Proposed: "Nothing in them identifies you or your phone."
25. **Always Saved** footer: "None of them identify you or link your photos." The claim about the person holds. Whether image size and color data narrow down the device model while Camera Make and Model is off should be checked in the real-device tag dump (issue 79) before the sentence is kept as written.
26. **"On by default" and "Off by default"** end some explanations (Face Detection, Sign Each Photo, Show Processed Marker, Live Activity, Standard File Tags) and not others (Start in Clean View, Mirror Front Camera, Night Mode). They state a fact that Factory Defaults already shows, and add a sentence to every translation. Use them on all switches or on none.
27. **Sign Each Photo** in direction B has three sentences and a default note. Issue 80 requires the sentence about what a signed photo shows. The sentence "If off, the photo can't be checked for changes." in 0.3.0 was dropped in direction B; that is correct, since Off is now the default and the first sentence already implies it.

Every sentence in this group is in the Honesty catalog or next to it, so each change is a draft for the Honesty review, not a decision of this plan.

### 2.7 Accessibility

28. **Rows that appear while a switch is toggled** (item 15) move the list under VoiceOver and Switch Control focus, with no announcement.
29. **The Settings list is long at the largest text size.** Four explanations run to two or three sentences: Night Mode, Live Activity (a 0.3.0 finding: about one screen tall), Mirror Front Camera and Sign Each Photo. With the switch below each explanation, the list is many screens long before the reference pages.
30. **No heading says which rows are switches set once and which open pages**; this is standard for a settings list and needs no change, but each row that opens a page must show its value so the state reads without opening it (item 13 is the one exception today).
31. **Search results** read "Location, in Privacy, Choose Details" (ACCESSIBILITY.md). Page paths must be whole localized names, and a result that points to the camera (3.6) must say so in words, not only with a symbol.
32. **Night Mode from Settings on iPad** turns a popover red while it is open; the app keeps the presentation it opened with. The mockups show the sheet opened in Night Mode but not this case.

### 2.8 Largest text and long languages

33. **No Settings screen is drawn in a long language.** The longest current titles are 44 characters ("Kamerawerte in aufgeräumter Ansicht behalten", Keep Readout in Clean View, German), 40 ("Instrucciones de corrección del objetivo", Spanish) and 36 ("Rimuovi tutti i dettagli facoltativi", Italian). At 402 pt a title of that length beside a switch takes two lines, and beside a value such as "All Optional Removed" the value must wrap under the title at standard sizes too, not only at accessibility sizes.
34. **Values beside titles**: "RAW (DNG), HEIF, JPEG", "All Optional Removed", "Freeze Fast Motion (1/1000 s)" and "12 MP (4032 × 3024)" are the longest. Each needs the wrap rule drawn once.
35. **Search results with a path** ("Privacy › Choose Details") are built from two names; in right-to-left languages the separator and order must follow the language. The build spec already says not to join fragments.

## 3. Proposed structure

### 3.1 The tree

Five groups, as in direction B, with the changes marked. Nothing is deeper than two levels below Settings. Paths are from the camera on iPhone; on iPad and the Duo inner display, leave out "Q".

```
Settings                                             search field at the top
│
├─ Presets                         value: 2 Saved / None Saved      always shown
│    page: Factory Defaults, saved presets (More: Rename, Delete), Save Current Settings
│
├─ PHOTOS                          what each photo is saved as
│  ├─ Formats                      value: RAW (DNG)                 page
│  ├─ HEIF and JPEG Copies         value: Standard / Flat / Not Saved   page   (merges Look and File Options)
│  ├─ Photo Size                   value: Default / Custom          page   (when a lens offers sizes)
│  └─ Mirror Front Camera          switch                           (moved from Camera)
│
├─ PRIVACY                         what each photo says
│  ├─ Details in Each Photo        value: All Optional Removed / Custom / Custom, Location On   page
│  │    (renames Choose Details; holds Remove All Optional Details, Location, the other
│  │     details, Standard File Tags, Always Saved)
│  └─ Sign Each Photo              switch
│       room for 1.1.0: Save Photos To, Lock Captures, Assistant Access
│
├─ CAMERA                          how the camera focuses and exposes
│  ├─ Fast Shutter                 value: Standard                  page   (home: Q tile)
│  └─ Face Detection               switch                           (name under review, 7.5)
│
├─ SCREEN                          what the screen shows
│  ├─ Start in Clean View          switch                           (moved from Camera)
│  ├─ Viewfinder Overlays          value: Off / Grid, Level / 3 On  page   (moved from Camera)
│  ├─ Show Processed Marker        switch                           (moved from Camera)
│  ├─ Night Mode                   switch
│  ├─ Keep Night Mode After Astro  switch                           (where the device offers Astro; added 2026-11-18)
│  ├─ Red Viewfinder               switch                           always shown
│  └─ Live Activity                switch                           (where the device offers it)
│
└─ MORE
   ├─ Accessibility                page
   ├─ Honesty                      page
   └─ About and Licenses           page → License; Notices and Trademarks
```

Rows on the Settings list: 16 to 19, depending only on the device (Photo Size, Keep Night Mode After Astro and Live Activity are shown where the device offers them). Direction B has 14 to 20, depending also on which switches are on. Here no row appears or disappears as a switch is changed.

### 3.2 Path to every option

| Option | Path from the camera (iPhone) | Taps | Levels below Settings |
| --- | --- | --- | --- |
| A saved preset, Factory Defaults | Q › Presets › preset (home) or Q › Settings › Presets › preset | 3 or 4 | 1 |
| Rename or delete a preset | Q › Presets › More › Rename | 4 | 1 |
| Formats | Format status › format (home for the shortcut) or Q › Settings › Formats › format | 2 or 4 | 1 |
| Paired with RAW | Q › Settings › Formats › Paired with RAW › value | 5 | 1 |
| Look | Format status › Look › value, or Q › Settings › HEIF and JPEG Copies › value | 3 or 4 | 1 |
| HEIF Compression, HEIF Bit Depth, JPEG Compression, Color Space, Copy Size | Q › Settings › HEIF and JPEG Copies › row › value | 5 | 1 |
| Photo Size | Q › Settings › Photo Size › lens › value | 5 | 1 |
| Mirror Front Camera | Q › Settings › switch | 3 | 0 |
| Remove All Optional Details | Q › Settings › Details in Each Photo › switch | 4 | 1 |
| Location | Q › Settings › Details in Each Photo › switch | 4 | 1 |
| Each other detail, Standard File Tags | Same | 4 | 1 |
| Sign Each Photo | Q › Settings › switch | 3 | 0 |
| Fast Shutter | Q › Fast Shutter › value (home), or Q › Settings › Fast Shutter › value | 3 or 4 | 1 |
| Face Detection | Q › Settings › switch | 3 | 0 |
| Start in Clean View | Q › Settings › switch | 3 | 0 |
| Grid, Level, Live Camera Readout | Their Q tiles (home), or Q › Settings › Viewfinder Overlays › switch | 2 to 3, or 4 | 1 |
| Focus Peaking, Histogram | Pro Tools (with Manual Controls on), or Q › Settings › Viewfinder Overlays › switch; Focus Peaking also a Q tile if 7.7 is agreed | 3, 4, or 2 | 1 |
| Grid Style, Keep Readout in Clean View | Q tile menu, or Viewfinder Overlays | 3 or 4 | 1 |
| Show Processed Marker | Q › Settings › switch, or the foot of the processing note | 3 or 2 | 0 |
| Night Mode | Q › Night Mode (home), Control Center, Siri, or Q › Settings › switch | 2, 1, 0 or 3 | 0 |
| Keep Night Mode After Astro | Q › Settings › switch | 3 | 0 |
| Red Viewfinder | Q › Settings › switch | 3 | 0 |
| Live Activity | Q › Settings › switch | 3 | 0 |
| Accessibility, Honesty, About and Licenses | Q › Settings › row | 3 | 1 |
| License; Notices and Trademarks | Q › Settings › About and Licenses › row | 4 | 2 |

The only pages two levels down are License and Notices and Trademarks, as in direction B. Pickers on a page open as menus on their row, so they add a tap but not a level.

### 3.3 Common tasks, taps

| Task (from issue 74 and navigation.md) | 0.3.0 | Direction B | This plan |
| --- | --- | --- | --- |
| Turn on HEIF copies | 2 | 2 | 2 |
| Find where location is written | 3 | 4 | 4, or search "location"; 3 on iPad |
| Turn on Location | 3 | 4 | 4 |
| Remove every optional detail again | 2 | 3 | 4 (the value on the Settings list shows the state without opening the page) |
| Change JPEG compression | 4 | 5, and not shown at all with RAW only | 5, always shown |
| Change the look | 3 | 3 | 3 |
| Turn on signing | 2 | 3 | 3 |
| Switch to night mode | 2 | 2 | 2 |
| Set Red Viewfinder before dark | 4 (Night Mode on, the switch, Night Mode off) | 5 (the same) | 3 |
| Turn on Focus Peaking in full auto | 3 | 4 | 4; 2 with the Q tile (7.7) |
| Restore every setting | 3 | 4 (row hidden with no presets) | 4, or search "reset" |
| Turn on Manual Controls | 3 | 1 | 1; search "manual" in Settings points to the button |

One task gets longer than in direction B: turning Remove All Optional Details back on, from 3 taps to 4. It is the default, the Settings list shows its state as a value, and Factory Defaults restores it. See 7.1 for the alternative.

### 3.4 Group by group: what changes and why

**Presets.** Always shown, with its count as the value, so Factory Defaults is always reachable (item 16). Page content as in direction B. Search finds it for "reset", "restore" and "defaults". Rationale: one predictable place; error recovery.

**Photos.** The group is "what each photo is saved as".
- Look and File Options merge into one page, **HEIF and JPEG Copies** (items 9, 15). The page lists Look (Standard, Flat, each with its sentence), then HEIF Compression, HEIF Bit Depth, JPEG Compression, Color Space and Copy Size, then Restore Defaults, with one footer: "This changes only the HEIF and JPEG copies. The RAW is never changed." The row is always shown. When no copy is saved its value is "Not Saved" and the page starts with one line, "No HEIF or JPEG copy is saved now. Turn one on in Formats.", with the settings still editable so they can be prepared in advance. Rationale: names a group by what people want to do; no row appears or disappears; search always has a destination; one row fewer.
- **Mirror Front Camera** moves here from Camera (item 5).
- Photo Size keeps its name, because the Set Photo Size shortcut uses it. Search finds it for "resolution" and "megapixels", and Copy Size for "resize" (item 10).
- The Format status sheet keeps Look and "All Photo Settings"; the latter opens Settings scrolled to Photos, as drawn.

**Privacy.** The group is "what each photo says". The name stays "Privacy": issue 82 tells people "You can change this in nope › Settings › Privacy".
- Remove All Optional Details and Choose Details become one row, **Details in Each Photo** (items 1, 8). The master switch is the first row of the page, with its explanation. Location follows in a section of its own, with the access notice and Open Settings under it as drawn. Then "Other Details" (eleven switches), Standard File Tags, and Always Saved. The value on the Settings list is "All Optional Removed", "Custom", or "Custom, Location On", so the most asked question (is location being written?) is answered on the list.
- Sign Each Photo stays a switch on the Settings list. Signing is an authenticity feature, but what it adds to the file (the app's name and version) is a privacy fact, and issue 80 groups it so.
- Room for 1.1.0, in this order under Sign Each Photo: **Save Photos To** (Photos, nope only), **Lock Captures** (a page: the lock, re-lock time, passcode only), **Assistant Access** (a page: the switch and Ask First). The group then has five rows. Backup exclusion, neutral file names and deleting captures from issue 83 belong on the Save Photos To page or a Storage page one level down, not on the list. No restructuring is needed, and every page stays at one level. Each page gets a stable identifier now (3.6), so a link such as the one issue 82 describes can open it later.

**Camera.** Only behavior: Fast Shutter and Face Detection (item 6). Short on purpose: issue 82 and later work add camera behavior here, not display options. The Manual Controls switch is gone (issue 77).

**Screen.** Everything about what the screen shows, in the order of use: Start in Clean View, Viewfinder Overlays, Show Processed Marker, then Night Mode, Red Viewfinder, Live Activity.
- Viewfinder Overlays shows which overlays are on: "Off", the names when one or two are on ("Grid, Level"), or a count ("3 On") (item 13).
- **Red Viewfinder is always shown** (items 15, 28). Its explanation starts with the condition: "In Night Mode, shows the live picture in red too. Only the screen changes; photos keep their colors."
- The page sections keep their names. Pro Tools renames its "Live Aids" heading only if the owner wants one name for both; not proposed.

**More.** Kept as named. A descriptive name ("Help and About") would promise a Help page the app does not have; issue 82 mentions Help for 1.1.0, and the group can be renamed then.

### 3.5 Outside Settings, found by this review

- **Pro Tools: remove the Interval Shooting section** (item 2). The drive strip and its card are the one home. Pro Tools then holds exposure mode, metering, the locks, bracketing and the live aids. Decision 7.8. (Bracketing left Pro Tools too, on 2026-11-18: [BRACKETING.md](BRACKETING.md).)
- **Q: a Focus Peaking tile** (item 18), shown in full auto and manual. It changes the existing switch. Decision 7.7.
- **Q tile value for the readout**: "On" and "On, Kept" in place of "Pinned", or keep "Pinned" and add it to the page as the switch's value text. Minor; follows the wording review.
- **Bracketing** stays in Pro Tools for 1.0.0. Moving it to the drive strip would change the strip that was just chosen; recorded for the 1.1.0 list. *Superseded on 2026-11-18: the owner accepted Bracket on the drive strip for 1.0.0 ([BRACKETING.md](BRACKETING.md), decision 1).*

### 3.6 Search

Search stays in (the build spec lists it as optional). Three additions, all text:
1. **Other words for the same thing.** Each entry has keywords beside its title: metadata, EXIF, GPS (Details in Each Photo, Location); Content Credentials, C2PA, signature (Sign Each Photo); reset, restore, defaults (Presets); resolution, megapixels (Photo Size); quality, compression (HEIF and JPEG Copies); selfie (Mirror Front Camera); red, dark (Night Mode). Keywords are localized strings.
2. **Pointers to the camera.** A search for something that is not in Settings answers with where it is, in words, and does not navigate: "Manual Controls: on the camera, beside the lenses", "Self-Timer: on the camera, above the shutter", "Flash, Light, Grid, Level, Close-Up: in Q". This covers item 17. The wording uses the names in ACCESSIBILITY.md.
3. **A stable identifier for each page and row**, used by search, by "All Photo Settings" on the Format status sheet, and later by links (issue 82). The camera's own entry points open Settings at the right place: the Location warning's explanation opens Details in Each Photo; the processing note holds its switch.

If search is dropped, items 15 to 17 need the always-shown rows above and a one-line footer under Screen: "Manual Controls, the self-timer and the flash are on the camera screen."

### 3.7 Explanations on the Settings list

Rule: on the Settings list an explanation is one sentence, two where issue 80 or honesty needs it. Longer text goes to the Honesty page, which already has an entry for each of these. No "by default" notes (item 26). All drafts for the Honesty review:

| Switch | Draft |
| --- | --- |
| Mirror Front Camera | Saves front camera photos mirrored, as the viewfinder shows them. |
| Sign Each Photo | Lets anyone check that the photo hasn't changed since nope. saved it. A signed photo shows that it was taken with nope., and which version. |
| Face Detection | Autofocus and auto exposure follow faces the camera finds. |
| Start in Clean View | Unchanged. |
| Show Processed Marker | Shows Processed on the camera when a lens can't save RAW. |
| Night Mode | Red on black, to keep your eyes used to the dark. nope. doesn't change the screen's brightness. (The advice on dimming moves to Honesty or Accessibility.) |
| Red Viewfinder | In Night Mode, shows the live picture in red too. Only the screen changes; photos keep their colors. |
| Live Activity | Shows a series' progress on the Lock Screen and in the Dynamic Island when you leave nope. Counts only; nothing is sent. |
| Standard File Tags | Fixed values the file standard asks for, such as version numbers and the color space. Nothing in them identifies you or your phone. |

Where a setting applies ([SETTING-SCOPE.md](SETTING-SCOPE.md), section 6). A setting that is used only in some state of the camera says so on the list, in words that name the control that decides the state. A switch: its explanation begins with the condition (Red Viewfinder). A row that opens a page: a note of one sentence under the title and value, in the explanations' footnote size and secondary color (Fast Shutter: "Used only while Manual Controls are off."). A page whose choices are not in use now: one line at the top says so, and every control stays enabled (HEIF and JPEG Copies, Fast Shutter). A control on the camera or in Q: no note; it is shown only where it works. A note never changes with the state and is never a reason to add or remove a row.

Length at the largest text size, measured on the drawing `settings-largest` (402 pt wide, the whole list): 4,263 pt with the Fast Shutter note, 77 pt more than the 4,186 pt before it. Not measured on a device.

### 3.8 Accessibility of the proposed structure

- No row is added or removed while a switch is changed, so focus never moves by itself.
- Every row that opens a page reads its value: "Details in Each Photo, All Optional Removed, button".
- At accessibility sizes each switch sits below its title and explanation and each value wraps under its title, as drawn in settings-largest. The shorter explanations shorten the list at the largest size; by how much is measured when it is drawn.
- Search results read the setting and its page, or the setting and "on the camera".
- Voice Control names are the row titles. Siri action names keep matching: Night Mode, Fast Shutter, Photo Size, Presets, and Face Detection (or its new name in both places).
- Long languages: titles wrap to two lines; nothing is truncated; a value that does not fit beside its title wraps under it at every text size.

## 4. Settings on iPad, iPhone Duo and Apple Watch

### 4.1 How the app chooses today (from the code)

- The camera layout depends only on the window and the text size (`CameraLayout.arrangement`): accessibility sizes use the scrolling layout everywhere; a window wider than tall, or one regular in both size classes, uses the column layout; any other uses the stacked layout.
- Settings is presented by `AdaptivePresentation`: a popover when the horizontal size class is regular, otherwise a sheet; always a sheet in Night Mode. The style is chosen when Settings opens and kept until it closes.
- The iPhone Duo outer display is a compact-width window: stacked layout, sheet. The unfolded inner display is regular in both size classes: column layout, popover. The half-open posture has no handling.

### 4.2 iPad

- **One structure, one column.** The same list and pages as on iPhone, in a popover 480 × 720 pt from the Settings button in the control column, in both orientations. The camera stays visible beside it. A split view (groups in a sidebar, the page beside it) is not proposed: it would be a second structure to keep in step, and it would cover the picture. Decision 7.9.
- **Night Mode:** a sheet, as today. Opening in Night Mode and turning Night Mode on while the popover is open both need drawing (item 32).
- **Accessibility text sizes:** the camera uses the scrolling layout, which has no Settings button; Settings opens from Q, still as a popover because the width is regular. This case is not drawn.
- **Split View, Slide Over and Stage Manager:** a compact-width window uses the iPhone layout and a sheet. A regular-width window shorter than the popover makes the popover shorter, and it scrolls. A window resized while Settings is open keeps Settings open in the style it opened with.
- **Keyboard:** the Camera menu has one command (Take Photo, Space). No Settings command exists; none is added in 1.0.0.

### 4.3 iPhone Duo

- Outer display: the iPhone design, unchanged (Q › Settings, a sheet).
- Inner display: the iPad design (Settings button in the column, a popover; a sheet in Night Mode).
- **Folding or unfolding while Settings is open.** From the code, Settings stays open and keeps the page it was on, because the presentation is not replaced: a sheet opened on the outer display stays a sheet on the inner display, and a popover opened on the inner display is shown by the system as a sheet on the outer display. This is expected behavior, not verified on a device; it needs a test on the simulator's fold action and a drawing of both directions. The camera behind changes between the stacked and column layouts.
- Half-open: no special layout, as stated in layouts.html.

### 4.4 Apple Watch

- The watch app has no settings. Its one choice is **Delay** (Off, 3 seconds, 10 seconds), kept only while the watch app runs. It is separate from the phone's self-timer and is not mirrored either way.
- No phone setting is shown on the watch. The result line reflects one of them: "Saved, not signed" or "Saved and signed" follows Sign Each Photo on the phone. With signing off by default (issue 80), the unsigned result must read as plain status; the build spec already notes that the watch needs the phone to say why.
- Nothing is proposed for the watch in 1.0.0. If the Delay should survive a restart, that is a stored value, which the scope rule sends to 1.1.0.

### 4.5 Lock Screen camera

The Lock Screen capture extension shows the same camera screen with the shared settings. Which Settings rows are offered while the phone is locked, and whether privacy settings can be changed there, is not drawn anywhere in the set and should be confirmed on a device. Issue 83 plans to lock the privacy settings behind authentication in 1.1.0. Decision 7.10.

## 5. Changes against the current direction B set

### 5.1 Screens to redraw if every recommendation is accepted

| Screen (docs/design/screens) | Change |
| --- | --- |
| settings-root | New groups, order, rows and values; shorter explanations |
| settings-light, settings-night, settings-rtl, settings-largest | Same list in each appearance; settings-largest shows the whole list, not one group |
| settings-search | Keywords; a result that points to the camera; new page names |
| settings-choose-details | Becomes Details in Each Photo: master switch first, Location section, Other Details, Standard File Tags, Always Saved |
| settings-location-denied | Same notice in the new Location section |
| settings-look, settings-file-options | Replaced by one screen, HEIF and JPEG Copies |
| settings-formats | Unchanged unless the footer gains a link to HEIF and JPEG Copies |
| settings-honesty | Only if the wording drafts in 3.7 move text here |
| ipad-settings | New list in the popover |
| sheet-format | "Look" row and "All Photo Settings" keep their places; check names against the merged page |
| manual-pro-tools | Without the Interval Shooting section (7.8) |
| q-menu, q-auto, q-manual, q-night, q-states, q-fewer, q-long-language, ax-q, rtl-q, ipad-q, landscape-q | Only if the Focus Peaking tile is agreed (7.7) |

Unchanged: settings-photo-size, settings-fast-shutter, settings-overlays, settings-accessibility, settings-about, sheet-processing-note.

### 5.2 New screens

- settings-copies (HEIF and JPEG Copies), and the same page with no copy saved.
- settings-details at the largest text size.
- settings-long-language: the Settings list in German.
- settings-search-empty and a camera pointer result.
- The device screens in section 6 that concern Settings.

### 5.3 Documents

- settings.html: the gallery and the "Changed from 0.3.0" table.
- navigation.md and navigation.html: the "In Settings" table, the tap counts and the rules (Fast Shutter's home; no conditional rows).
- BUILD-SPEC.md: section 3.10 (the root table, the merged page, search keywords and identifiers), the strings table (new: Details in Each Photo, HEIF and JPEG Copies, Not Saved, Other Details, the overlay value forms, search keywords and pointers; removed: Look and File Options as row titles, Choose Details), section 7 decisions, and the chunk G file list (`LookSettingsView.swift` and `FileOptionsSettingsView.swift` merge).
- ACCESSIBILITY.md: the search result reading, and the Face Detection name if it changes (the Set Face Detection action title changes with it).
- README.md in this folder: the screen count.

## 6. Device coverage gaps

An audit of the whole direction B set, not only Settings. Today the set has 122 screens: iPad has six (auto, Manual Controls with a dial, Q, Astro, the Settings popover, right to left), the iPhone Duo has one (inner display), Apple Watch has ten, iPhone sideways has four, the largest text size has four (camera, Q, Settings, watch), and right to left has four. Everything else is drawn only for iPhone in portrait.

Not every iPhone screen needs three more versions. A screen needs its own drawing where the layout, the presentation or the reach differs; where it does not, one sentence in layouts.html should say that the iPhone drawing applies. The lists below are the screens where it differs.

### 6.1 iPad (column layout)

| Area | Missing |
| --- | --- |
| Orientation | Every iPad screen in the other orientation: at least auto, Manual Controls and Q in portrait and in landscape |
| Camera states | Status line with pills and warnings; capturing and the saved result at the Last Photo button; the failure banner; the Processed marker and its hidden state; front camera; clean view; Night Mode outside Astro; close-up and the too-close hint; focus lock; the exposure dial in full auto |
| Before the camera | First run, the three permission screens, access denied, camera unavailable, starting, paused: each with the Settings button that the column layout keeps |
| Drive modes | Timer (menu and countdown), Burst (idle and running), Interval (card, running, paused, dimmed), Astro (countdown and paused; running is drawn) |
| Q | Q with Manual Controls on; a tile menu open; Q in Night Mode |
| Manual Controls | Each dial type once (shutter or ISO, focus, white balance with Tint and Presets); the More menu; Pro Tools |
| Sheets | Format status and the processing note (a popover on iPad); What's in This Photo, Interval Settings, Astro Settings and Presets (sheets on iPad); Save Preset; the delete confirmation (anchored to its button); the Last Photo menu; Compare |
| Settings | A page inside the popover; search in the popover; the sheet in Night Mode; Night Mode turned on while the popover is open; Settings opened from Q at accessibility sizes |
| Largest text | Camera (scrolling layout on iPad), Q, and the Settings popover |
| Right to left | Q and Settings (the camera is drawn) |
| Multitasking | Split View at one half and one third, Slide Over, and a small Stage Manager window: which layout each gets, and Settings in each |
| Light appearance | Settings popover and Presets in light |

### 6.2 iPhone Duo

| Area | Missing |
| --- | --- |
| Outer display | One auto screen and Q at the outer display's real size, to confirm the iPhone design fits; the smallest-iPhone rule (bands over the picture) if it applies |
| Inner display | Manual Controls with a dial; Q; a drive mode running; Astro in Night Mode; the Settings popover; a sheet; the largest text size; right to left; both orientations (the inner display rotates) |
| Fold and unfold | A before and after pair for each of: the idle camera; Q open; a dial open; a sheet open (Format status, What's in This Photo); Settings open on a page; a countdown or series running (Timer, Interval, Astro); Compare; first run and a permission screen |
| Half-open | One drawing that confirms the column layout, the level and the controls relative to the hinge (a 0.3.0 finding), with the statement that no special layout is added |
| System | The Live Activity as shown on the outer display while a series runs with the phone closed |

### 6.3 Apple Watch

| Area | Missing |
| --- | --- |
| States | Connecting; the three other camera-unavailable messages (access refused, no camera, nope. not running on the phone); the phone busy with a series or still saving; several photos saved (a burst or bracket started on the phone); timer cancelled |
| Sizes | The smallest and the largest watch case (the set is drawn at one size) |
| Largest text | The countdown and the Delay list (Ready is drawn) |
| Right to left and a long language | Ready and the Delay list |
| Always On | The dimmed state while a countdown runs |
| Not present today | Night Mode on the watch, a complication and a Smart Stack widget do not exist in the app; layouts.html or watch.html should say so, so their absence is a statement and not a gap |

### 6.4 Across all three

- iPhone sideways is drawn for auto, Manual Controls with Interval, Q and Astro. Missing: a sheet opened while sideways (the code notes that a rotated sheet meets the column layout), Settings sideways, and the largest text size sideways.
- The Lock Screen camera (4.5) has no drawing on any device.
- Control Center controls, the Live Activity and Siri results are drawn for iPhone only; iPad needs the Live Activity on its Lock Screen, since it has no Dynamic Island.

## 7. Decisions

All twelve recommendations were accepted by the owner on 2026-11-17. Each is listed as it was put, with its outcome.

| # | Decision | Outcome (accepted 2026-11-17) |
| --- | --- | --- |
| 1 | One row for the details: merge Remove All Optional Details and Choose Details into one row whose page starts with the master switch | Accepted. Turning the master switch back on is 4 taps; its state shows on the Settings list |
| 2 | Its name | "Details in Each Photo" |
| 3 | One page for the copies: merge Look and File Options | "HEIF and JPEG Copies", always shown, with "Not Saved" when no copy is on |
| 4 | Regrouping | Mirror Front Camera to Photos; Start in Clean View, Viewfinder Overlays and Show Processed Marker to Screen; Camera keeps Fast Shutter and the faces switch |
| 5 | Face Detection's name | Renamed "Focus on Faces", the switch and the Shortcuts action. The action rename is outside the interface (BUILD-SPEC.md, section 6) |
| 6 | Explanations | One sentence on the list, two where issue 80 or honesty needs it; no "by default" notes; Red Viewfinder always shown. The drafts in 3.7, with the Standard File Tags sentence, go to the Honesty review |
| 7 | Focus Peaking in Q | A tile for the existing switch, in full auto and manual. With all thirteen tiles the panel has five rows |
| 8 | Interval in Pro Tools | Section removed; the drive strip is the one home |
| 9 | Settings on iPad | The single-column popover in both orientations, a sheet in Night Mode, no split view |
| 10 | Settings from the Lock Screen camera | Drawn as it is (layouts.html). No behavior change in 1.0.0; what is offered while locked is confirmed on a device, and any restriction is left to issue 83 |
| 11 | Search | Kept, with keywords and pointers to the camera (3.6) |
| 12 | Device coverage | Every screen whose presentation differs is drawn for iPad, the iPhone Duo (both displays, with fold and unfold pairs) and Apple Watch; layouts.html states the rule for the rest |

### What followed in the set

- Section 5: every screen listed in 5.1 was redrawn; `settings-look`, `settings-file-options` and `settings-choose-details` were replaced by `settings-copies` and `settings-details`; the new screens of 5.2 were added.
- Section 6: the gaps were closed by drawing, or by a written rule in layouts.html where the presentation does not differ. One item is left open and stated there: the iPhone held sideways at the largest text size.
- Still to do before release, outside the drawings: the Honesty review of every draft sentence; the device checks named in BUILD-SPEC.md, section 6.
