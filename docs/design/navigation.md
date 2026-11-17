# Navigation map

Design version: 1.0.0, direction B · Reach (2026-11-17). Planned design for release 1.0.0; the app is built to match it.

Every option, where it lives, the path to it from the camera, and the number of taps in 0.3.0 and in this design. A dash means the option did not exist in 0.3.0.

## On the camera screen

| Option | Lives in | Path from the camera | Taps, 0.3.0 | Taps, this design | Notes |
| --- | --- | --- | --- | --- | --- |
| Take Photo | Shutter row | Shutter | 1 | 1 | Also the volume buttons, the Camera Control, Space, Apple Watch and Siri. |
| Lens | Lens row | Lens button | 1 | 1 |  |
| Switch Camera | Lens row | Switch Camera | 1 | 1 |  |
| Manual Controls on or off | Lens row | Manual Controls button | 3 | 1 | Was Settings › Camera › Manual Controls (issue 77). The Settings switch and the M pill are removed. |
| Single Photo | Drive strip | Single | 3 | 1 | Was Quick Controls › Drive › Single Photo. |
| Self-timer, 3 seconds | Drive strip | Timer | 3 | 1 |  |
| Self-timer, 10 seconds | Drive strip | Timer › Timer › 10 seconds | 3 | 3 | The delay is remembered while the app is open. |
| Burst | Drive strip | Burst | 3 | 1 |  |
| Interval Shooting | Drive strip | Interval | 3 | 1 | The shutter starts the series. |
| Interval and number of photos | Interval card | Interval › Interval Settings | 3 | 2 | Also in Pro Tools. |
| Astro | Drive strip | Astro | 2 | 1 | Was a Quick Controls item, often after scrolling the tray. |
| Astro frames and start delay | Astro card | Astro › Astro Settings | 3 | 2 |  |
| Photo format, what the next photo will be | Status line | Format status | 1 | 1 | Opens the Formats sheet. |
| Save HEIF or JPEG copies | Formats sheet | Format status › HEIF | 2 | 2 | Also Settings › Formats. |
| Processing note for a lens without RAW | Formats sheet | Processed marker | – | 1 | New disclosure (issue 80). |
| Last Photo in Photos | Shutter row | Last Photo | 1 | 1 |  |
| What’s in This Photo | Shutter row | Last Photo (touch and hold) › Photo Details | 2 | 2 | Also a VoiceOver action on Last Photo. |
| Focus and exposure point | Picture | Tap the picture | 1 | 1 |  |
| Lock focus and exposure | Picture | Touch and hold, or the lock button by the focus square | 1 | 1 |  |
| Undo a changed setting | Status line | Its pill | 1 | 1 | Light, Flash, locks, Exposure, Fast Shutter, Close-Up, Far Focus, Magnify, Compare. |
| Explanation of a warning | Picture, top edge | Its chip | 1 | 1 |  |

## In Q

| Option | Lives in | Path from the camera | Taps, 0.3.0 | Taps, this design | Notes |
| --- | --- | --- | --- | --- | --- |
| Flash | Q tile | Q › Flash › value | 3 | 3 | Only on lenses with a flash. |
| Light | Q tile | Q › Light | 2 | 2 | Brightness: the Light pill, 2 taps. |
| Exposure compensation | Q tile | Q › Exposure | 2 | 2 | Full auto only; in manual it is the EV readout, 1 tap. |
| Close-Up | Q tile | Q › Close-Up | 2 | 2 | Kept as its own tile, so it stays at two taps. |
| Far Focus | Q tile | Q › Far Focus | 2 | 2 | With Manual Controls on, as today. |
| Fast Shutter | Q tile | Q › Fast Shutter › value | 3 | 3 | Its page is Settings › Fast Shutter. |
| Magnify | Q tile | Q › Magnify | 2 | 2 |  |
| Grid and its style | Q tile | Q › Grid › style | 3 | 3 | Thirds, 4 × 4, Square (issue 76). |
| Level | Q tile | Q › Level | 2 | 2 |  |
| Live Camera Readout | Q tile | Q › Readout › value | 3 | 3 | Off, On, Keep Readout in Clean View. |
| Night Mode | Q tile | Q › Night Mode | 2 | 2 | Also Settings, Control Center and Siri. |
| Compare | Q tile | Q › Compare | 2 | 2 | Where the device supports it. |
| Apply a preset | Q tile | Q › Presets › preset | 3 | 3 |  |
| Save, rename or delete a preset | Presets | Q › Presets › Save Current Settings, or a preset’s More menu | 4 | 3 | The Rename or Delete page is gone. |
| Hide Controls (clean view) | Q foot | Q › Hide Controls | 2 | 2 | Or swipe down on the picture, 1. |
| Settings | Q foot | Q › Settings | 1 | 2 | One tap more than before. On iPad, and before the camera is ready, Settings keeps its own button: 1. |

## With Manual Controls on

| Option | Lives in | Path from the camera | Taps, 0.3.0 | Taps, this design | Notes |
| --- | --- | --- | --- | --- | --- |
| ISO, shutter, aperture, focus, white balance, exposure | Readout row | Its readout | 1 | 1 | Opens the dial. |
| One control back to automatic | Dial | Readout › Auto | 2 | 2 |  |
| All Auto | Readout row | More › All Auto | 2 | 2 |  |
| Pro Tools | Readout row | More › Pro Tools | 2 | 2 |  |
| Exposure Mode, Metering | Pro Tools | More › Pro Tools › row › value | 4 | 4 |  |
| Exposure Lock (AE-L), Focus Lock (AF-L) | Pro Tools | More › Pro Tools › switch | 3 | 3 |  |
| Bracketing, Frames, Step | Pro Tools | More › Pro Tools › Bracketing | 3 | 3 |  |
| Focus Peaking, Histogram | Pro Tools | More › Pro Tools › switch | 3 | 3 | Also Settings › Viewfinder Overlays. |

## In Settings (set once)

| Option | Lives in | Path from the camera | Taps, 0.3.0 | Taps, this design | Notes |
| --- | --- | --- | --- | --- | --- |
| Sign Each Photo | Settings › Privacy | Q › Settings › switch | 2 | 3 | Set once. Off by default (issue 80). |
| Remove All Optional Details | Settings › Privacy | Q › Settings › switch | 2 | 3 | Set once. |
| Location and the other details in each photo | Settings › Choose Details | Q › Settings › Choose Details › switch | 3 | 4 | Set once. Search finds each by name. |
| Standard File Tags | Settings › Choose Details | Q › Settings › Choose Details › switch | 3 | 4 | Set once. |
| Look | Settings › Photos | Format status › Look › value | 3 | 3 | Shown once a copy is on. |
| File Options (compression, bit depth, color space, copy size) | Settings › File Options | Q › Settings › File Options › row › value | 4 | 5 | Set once. Also Format status › All Photo Settings. |
| Photo Size | Settings › Photo Size | Q › Settings › Photo Size › lens › value | 4 | 5 | Set once. Also the Set Photo Size shortcut. |
| Start in Clean View | Settings › Camera | Q › Settings › switch | 2 | 3 | Set once. |
| Face Detection | Settings › Camera | Q › Settings › switch | 2 | 3 | Set once. Off by default (issue 80). Also a shortcut. |
| Show Processed Marker | Settings › Camera | Q › Settings › switch | – | 3 | New switch (issue 80). Also at the foot of the processing note: 2. |
| Viewfinder Overlays (all in one place) | Settings › Viewfinder Overlays | Q › Settings › Viewfinder Overlays › switch | 3 | 4 | Each is also a Q tile or in Pro Tools. |
| Mirror Front Camera | Settings › Camera | Q › Settings › switch | 2 | 3 | Set once. |
| Red Viewfinder | Settings › Screen | Q › Settings › switch | 2 | 3 | Shown while Night Mode is on. |
| Live Activity | Settings › Screen | Q › Settings › switch | 2 | 3 | Set once. |
| Accessibility, Honesty, About and Licenses | Settings › More | Q › Settings › row | 2 | 3 | Reference pages. |
| License text, Notices and Trademarks | About and Licenses | Q › Settings › About and Licenses › row | 3 | 4 | Deepest page: two levels below Settings. |

## Outside the app

| Option | Lives in | Path from the camera | Taps, 0.3.0 | Taps, this design | Notes |
| --- | --- | --- | --- | --- | --- |
| Open the camera | Control Center, Lock Screen, Action button | Open nope. | 1 | 1 |  |
| Night Mode | Control Center | Night Mode | 1 | 1 |  |
| Stop a series | Live Activity | Stop | 1 | 1 | Interval and Astro. |
| Take a photo, with a delay | Apple Watch | Take Photo; Delay | 1 | 1 |  |
| Every Siri and Shortcuts action | Siri, Shortcuts | See ACCESSIBILITY.md | 0 | 0 | Unchanged set. |

## Common tasks

| Task | Taps, 0.3.0 | Taps, this design |
| --- | --- | --- |
| Turn on HEIF copies | 2 | 2 |
| Set a 3-second self-timer | 3 | 1 |
| Start Astro | 2 | 1 |
| Turn on Manual Controls | 3 | 1 |
| Switch to night mode | 2 | 2 |
| Turn on Close-Up | 2 | 2 |
| Turn on the Thirds grid | 3 | 3 |
| Find where location is written | 3 | 4 |
| Open Settings | 1 | 2 |
| Change the interval of a series | 3 | 2 |

## Rules

- Used while shooting: on the camera screen or in Q, never only in Settings.
- Set once: in Settings, at most two levels below it, and found by search.
- Each option has one home. A second way in (a pill, a card button, a Q tile) changes the same value and behaves the same.
- Settings is two taps on iPhone (Q, Settings). That is one more than before; it buys a status line with no button on it and a Q that is always under the thumb.
- Options reachable only through Settings are the set-once ones: privacy and signing, file options and photo size, Start in Clean View, Face Detection, the Processed marker switch, Mirror Front Camera, Red Viewfinder, Live Activity, and the reference pages.
