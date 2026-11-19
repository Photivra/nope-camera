# Launch screen

Design version: 1.0.0, direction B · Reach. Proposed 2026-11-18 for release 1.0.0; accepted by the owner the same day with all eight recommendations of section 11 (option B, built on A). Built for 1.0.0; the Simulator results of section 9 are in [docs/TESTING.md](../TESTING.md), "Launch screen". Section 13, "Large text and the plate", was proposed 2026-11-18 after the build, accepted by the owner the same day with both recommendations of 13.4 (decisions 9 and 10), and built for 1.0.0; sections 4, 6.3 and 7 and figure `pair-largest` are in line with it.

For the implementer of release 1.0.0. The drawings are in [launch.html](launch.html); each figure named below is `screens/launch-<name>.html` with a PNG beside it. The mark's artwork is [launch-mark.svg](launch-mark.svg). Tokens are in [tokens.md](tokens.md), the rest of the build in [BUILD-SPEC.md](BUILD-SPEC.md).

## 1. Summary

The launch screen is what iOS draws from the tap on the icon until the app has drawn its first frame. Three options were drawn:

| Option | What it is | Verdict |
| --- | --- | --- |
| A · Black | The camera's black, in every appearance. Nothing else. | Built first. Ships alone if a check in section 9 fails. |
| B · Black with the mark | Option A with the icon's mark in the middle of the window. The app keeps the mark at the same point for its first start and fades it when the picture arrives. | Recommended. |
| C · The empty camera | The picture's frame and the shutter ring, from a launch storyboard. | Not recommended: right for one state on one kind of device. |

Option A is all of option B except the image and the view that holds it, so the work is in two steps and the first is useful by itself: it removes the white screen that release 0.3.0 shows before the camera in the light appearance.

## 2. What the app does today

Read from the code at `3f4f74e`; nothing here was measured on a device.

| Fact | Where |
| --- | --- |
| The app target sets `INFOPLIST_KEY_UILaunchScreen_Generation = YES` and nothing else for the launch screen. The built Info.plist holds an empty `UILaunchScreen` dictionary: no color, no image. | `App/NopeCamera.xcodeproj/project.pbxproj`, both configurations of the app target; `App/NopeApp-Info.plist` holds only the App Group key |
| With no color, iOS uses the system background, which follows the light or dark appearance. | Apple, `UIColorName` (section 3) |
| The app target has no asset catalog. The icon is `App/NopeApp/AppIcon.icon`. | `App/NopeApp/` |
| The camera screen is always dark; first run, camera access declined and no camera follow the system appearance. | `Sources/NopeUI/ScreenAppearance.swift` |
| The camera screen's background is the semantic `.background`. The window's dark style is set by a bridging view, on the next turn of the main actor after the view is updated. | `Sources/NopeUI/CameraScreen.swift` (`.background(.background)`); `App/NopeApp/Camera/SystemAppearance.swift` (`WindowAppearanceView.scheduleApply()`) |
| The model starts in `.starting` and leaves it when the camera permission has been read: to `.ready`, where the session then starts (`sessionStatus == .starting`), or to `.needsPermission`, `.permissionDenied` or `.unavailable`. | `Sources/NopeCore/CameraModel.swift` |
| In `.starting` the screen shows a spinner with "Starting the camera…" and the Settings button. With the session starting, the spinner and the same words are in the middle of the picture. | `CameraScreen.swift` (`content`, and the `if !isReady` row); `SessionStatusView.swift` |
| The figure `camera-starting` draws no Settings button. The code draws one. | `screens/camera-starting.html` |
| On iPhone the Info.plist lists portrait and both landscape orientations; the app delegate then keeps the camera's window in portrait. | `project.pbxproj`; `App/NopeApp/Camera/InterfaceOrientation.swift` |
| The status bar is not hidden. In Night Mode it stays white; the Night Mode screenshot check leaves it out. | `docs/TESTING.md`, "UI tests and accessibility audits" |
| The Lock Screen camera draws `Color.black` until the copy of the settings arrives, then the same `CameraScreen`. | `App/NopeCaptureExtension/NopeCaptureExtension.swift` |

Consequences:

- In the light appearance the launch screen is white and the camera after it is black, on every launch (figure `today`).
- Expected, not measured: in the light appearance the app's own first frame may also be white, because the dark style reaches the window one turn after the first update. Today a white launch screen hides this. With a black launch screen it would be a white flash between two black screens. Section 6.1 removes the dependency; check 3 in section 9 looks for it.

## 3. What iOS allows

From Apple's documentation, read 2026-11-18.

| Source | What it says | Used for |
| --- | --- | --- |
| Human Interface Guidelines, "Launching" | The launch screen should be nearly identical to the first screen. An app that shows a solid color before its first screen should use a launch screen of only that color. No text, because it can't be localized. It "isn't a branding opportunity": no logo unless it is a fixed part of the first screen. It should match the device's orientation and appearance. | Options A and B; why B needs the mark in the app's first frames |
| Xcode, "Specifying your app's launch screen" | Two ways: the `UILaunchScreen` dictionary in the Info.plist, or a launch storyboard with UIKit views only, no custom classes, no connections to code. | Section 5 |
| `UILaunchScreen` › `UIColorName` | The name of a color in the asset catalog. Without it, the system background. | Step 1 |
| `UILaunchScreen` › `UIImageName` | The name of an image in the asset catalog. The color shows through its transparent parts. | Step 2 |
| `UILaunchScreen` › `UIImageRespectsSafeAreaInsets` | Whether the image respects the safe area insets. Nothing more is documented. | Step 2 |
| `UIStatusBarStyle` | The style of the status bar as the app launches; `UIStatusBarStyleLightContent` is for dark backgrounds. | Step 1 |
| LockedCameraCapture, "Creating a camera experience for the Lock Screen" | Describes the extension's scene and life cycle. It describes no launch screen for an extension. | Section 6.4 |
| Human Interface Guidelines, "Launching" | watchOS does not require a launch screen. | Nothing is built for the watch app |

Not documented by Apple, so each is a check in section 9 and not a fact:

- how the launch image is placed and whether it is ever scaled;
- how the generated empty `UILaunchScreen` dictionary combines with one written in the Info.plist file;
- what an iPhone launched sideways shows between a landscape launch screen and a portrait window;
- how Smart Invert treats a launch image;
- that iOS keeps a copy of an app's launch screen and may show an old one after an update (widely reported by developers).

It follows from the first row of section 2 and from the nature of a launch screen that it cannot read a setting. Night Mode, the text size, the layout and whether camera access was granted are all unknown when it is drawn. So the design has one launch screen that is right, or at least harmless, in every one of those states.

## 4. The options

Figures: `a`, `b`, `c`, `handoff-a`, `handoff-b`, `handoff-c`.

| | A · Black | B · Black with the mark | C · The empty camera |
| --- | --- | --- | --- |
| Built with | A color set, three Info.plist keys | A, an image set, one more key pair, one view in `NopeUI`, one property in `NopeCore` | A launch storyboard with size-class variants |
| Camera ready | Black to black | The mark stays; the controls appear around it; it fades when the picture arrives | Matches on an iPhone held upright at the default text size |
| First run, access declined, no camera | Black, then the screen | The mark, then the screen | A shutter ring and a picture frame that the next screen does not have |
| Night Mode | Nothing of the app's is lit | The mark, about 0.4% of the screen, for the length of the launch | A white ring, about 1% of the screen, that turns red |
| Largest text sizes (scrolling layout) | Black to black | The mark and its words over black, the pinned row drawn, everything that scrolls held back until the picture arrives (figure `pair-largest`, section 13) | The picture is elsewhere |
| iPad, iPhone Duo inner display | Black to black | The same point in the window | Needs a second layout, kept in step by hand |
| iPhone launched sideways | Black to black | The window's center is the same point; a turn may show (check 5) | The layout is drawn in landscape and then replaced |
| Apple's guidance | The stated case for a solid color | Met only because the mark is part of the first screen | Met in one state |

The area figures: the mark's shapes cover 15.2% of its 96 pt square, 1,400 square points; a 402 × 874 pt screen has 351,348; the home indicator, which iOS draws white on the same screen, is 140 × 5 pt. The shutter is a 4 pt ring of 76 pt and a 60 pt disc, 3,730 square points.

## 5. The design

Figures: `b`, `mark`, `appearance`, and for each device `b-sideways`, `b-small`, `b-ipad-portrait`, `b-ipad-landscape`, `b-duo-outer`, `b-duo-inner`.

**Color.** Pure black, sRGB 0, 0, 0, the same in the light and the dark appearance and with Increase Contrast. It is the camera's background and Night Mode's.

**Mark.** The app icon's artwork without its ground: the four corners of the frame, the "n" and the period, from the same three paths as `App/NopeApp/AppIcon.icon/Assets`, in the icon's colors (frame and "n" `#EDEDEE`, period `#40C8E0`). The image is 96 × 96 pt, which makes the frame 78 × 54 pt, the stroke 6 pt and the period 9 pt across. One size on every device. It is shapes, not text, and uses no font (AGENTS.md, "Name and wordmark").

**Place.** The center of the image is the center of the window: not of the safe area, and not of the picture. That point is the same in every orientation of the same window, which is what keeps the mark still on an iPhone launched sideways. It is 52 pt to the trailing side of the picture's middle in the column layout and 42 pt on the iPhone Duo's outer display, where the status strip takes the trailing edge. On the icon's grid the frame sits 4 units above the center, so on screen the frame's own center is 3 pt above the window's, as in the icon.

**Nothing else.** No name, no version, no "loading", no spinner, no motion.

## 6. Build specification

Two steps. Step 1 is option A and is complete by itself. Step 2 adds the mark.

### 6.1 Step 1: the launch color and a black first frame

| File | Change |
| --- | --- |
| `App/NopeApp/Assets.xcassets/` (new), in the app target's resources | `Contents.json`, and the color set `LaunchBackground.colorset` |
| `App/NopeApp-Info.plist` | Add the `UILaunchScreen` dictionary |
| `App/NopeCamera.xcodeproj/project.pbxproj`, app target, both configurations | Remove `INFOPLIST_KEY_UILaunchScreen_Generation`; add `INFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleLightContent`; add the catalog |
| `Sources/NopeUI/CameraScreen.swift` | The background and the `.starting` state, below |
| `Sources/NopeUI/DesignTokens.swift`, [tokens.md](tokens.md) | `NopeColor.launchBackground` = black, named so the launch color and the first frame are the same token |
| `scripts/check-launch-screen.sh`, `scripts/test-check-launch-screen.sh` (new) | Section 8 |
| `docs/TESTING.md` | The checks of section 9 |

`LaunchBackground.colorset/Contents.json` has one color and no `appearances` entry, so no appearance can give another value:

```json
{
  "colors": [
    {
      "idiom": "universal",
      "color": {
        "color-space": "srgb",
        "components": { "red": "0.000", "green": "0.000", "blue": "0.000", "alpha": "1.000" }
      }
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

In `App/NopeApp-Info.plist`:

```xml
<key>UILaunchScreen</key>
<dict>
	<key>UIColorName</key>
	<string>LaunchBackground</string>
</dict>
```

The generated empty dictionary is turned off because how Xcode combines it with a dictionary in the file is not documented. The check script reads the Info.plist of the built app, so a wrong merge fails the build's checks instead of reaching a device.

The icon stays in `AppIcon.icon`; `ASSETCATALOG_COMPILER_APPICON_NAME` is unchanged. Confirm in the built app that the icon is still the Icon Composer one after a catalog is added.

**Status bar.** In the light appearance the default status bar has dark content, which can't be seen on black; the clock would then appear when the app's dark window takes over. `UIStatusBarStyle` is the documented key for the status bar during launch. Expected to be enough; check 1 confirms it.

**The first frame is black.** In `CameraScreen`, replace `.background(.background)` so that the background is `NopeColor.launchBackground` whenever `ScreenAppearance.of(model.state) == .camera` or Night Mode is on, and the semantic background otherwise. The color no longer depends on the window's style having been applied. The screens that follow the system keep the system background.

**Nothing in the first frame is drawn and then removed.** In the `.starting` state, draw no Settings button and no spinner: only the background. The state lasts as long as reading the camera permission; a spinner there appears and is gone within a frame or two. VoiceOver still gets one element with the existing label "Starting the camera…". The Settings button stays on first run, camera access declined and no camera, as BUILD-SPEC.md 3.8 says. With step 1 alone, the spinner in the picture while the session starts stays as it is (figure `handoff-a`).

No strings change.

### 6.2 Step 2: the mark on the launch screen

| File | Change |
| --- | --- |
| `App/NopeApp/Assets.xcassets/LaunchMark.imageset/` (new) | `LaunchMark.svg`, a copy of [launch-mark.svg](launch-mark.svg), and `Contents.json` |
| `App/NopeApp-Info.plist` | Two more keys in `UILaunchScreen` |

Built: Xcode's asset compiler reads an SVG's colors as Display P3, so with `#40C8E0` in the file the launch screen's period was `#00CBE4` (measured on the Simulator). `launch-mark.svg` therefore writes the period as `#6AC5DD`, the Display P3 value of the icon's sRGB `#40C8E0`, and the launch screen shows `#40C8E0`; the paths are unchanged.

`LaunchMark.imageset/Contents.json`: one universal image, rendered as the original, with no appearance variants:

```json
{
  "images": [ { "idiom": "universal", "filename": "LaunchMark.svg" } ],
  "info": { "author": "xcode", "version": 1 },
  "properties": { "template-rendering-intent": "original" }
}
```

The dictionary becomes:

```xml
<key>UILaunchScreen</key>
<dict>
	<key>UIColorName</key>
	<string>LaunchBackground</string>
	<key>UIImageName</key>
	<string>LaunchMark</string>
	<key>UIImageRespectsSafeAreaInsets</key>
	<false/>
</dict>
```

Expected, to be confirmed by check 2: iOS draws the image at 96 × 96 pt with its center at the window's center, unscaled. If it is scaled or placed anywhere else on any device of section 9, replace the two image keys with a launch storyboard, which is documented: `UILaunchStoryboardName` = `LaunchScreen`, one `UIView` with a black background and one `UIImageView` of `LaunchMark`, 96 × 96, with its center constrained to the center of the root view (not the safe area layout guide). A storyboard and the `UILaunchScreen` dictionary are not used together.

### 6.3 Step 2: the mark in the app's first frames

Apple's guidance allows a mark on the launch screen only if it is a fixed part of the first screen. So the app draws the same mark at the same point until the picture arrives. This is what makes option B a launch screen and not a splash screen; without it, build option A.

| File | Change |
| --- | --- |
| `Sources/NopeCore/CameraModel.swift` | New `public private(set) var isFirstStart: Bool`, with unit tests |
| `Sources/NopeUI/StartIndicator.swift` (new) | `StartMark` (the shapes) and `StartIndicator` (the mark, the words, the plate) |
| `Sources/NopeUI/CameraScreen.swift` | Shows `StartIndicator` over the whole screen |
| `Sources/NopeUI/SessionStatusView.swift` | Draws no spinner while the indicator is shown |
| `Sources/NopeUI/DesignTokens.swift`, [tokens.md](tokens.md) | `NopeSize.startMark` = 96; `NopeColor.mark` = `#EDEDEE`; `NopeColor.markPeriod` = `#40C8E0` |
| `App/NopeApp/DebugTools/SimulatedCameraLaunch.swift` | A scenario whose session stays starting until released, for the UI tests |
| `App/NopeAppUITests/LaunchHandOffUITests.swift` (new) | Section 8 |
| `docs/api`, `docs/ARCHITECTURE.md` | The new property |

**`isFirstStart`.** `true` from creation. It becomes `false`, and never `true` again, the first time either happens: `state` becomes `.needsPermission`, `.permissionDenied` or `.unavailable`; or `sessionStatus` becomes anything other than `.stopped` or `.starting` (running, failed, interrupted, paused for heat, no picture). It is in `NopeCore` because it is camera state that the app, the Lock Screen camera and any other interface read the same way, and so that it is covered by unit tests.

**`StartMark`.** The three shapes on the icon's 128-unit grid, scaled to `NopeSize.startMark`: corners `M36 28H16V48 M92 28H112V48 M16 72V92H36 M92 92H112V72` and the "n" `M48 76V40 M48 57A17 17 0 0 1 82 57V76`, both stroked 8 units wide with square caps, and a circle of radius 6 at (97, 72). The colors are the fixed `NopeColor.mark` and `NopeColor.markPeriod`, not `NopeColor.label` or `NopeColor.fact`: the system teal changes with Increase Contrast and the launch image cannot, and white is brighter than the icon's `#EDEDEE`. In Night Mode both are white, so that `NightModeStyle` turns the whole mark the night red; the teal would multiply to a red too dark to see. Hidden from VoiceOver; ignores nothing for Smart Invert, so it follows the controls around it.

**`StartIndicator`.** The mark with its center at the center of the window, ignoring the safe area. While `state` is `.ready`, the words "Starting the camera…" (the existing key and comment; no new string) are centered under it, their top edge 40 pt under the mark's center, in `.subheadline` and `NopeColor.labelSecondary`, wrapping within the window's width less `NopeSpace.l` on each side. Behind both, a plate of `NopeMaterial.solid` with `NopeRadius.large` and `NopeSpace.m` of padding: it can't be seen on the black picture, and it keeps the words readable over a picture that arrives before the fade ends. Nothing is drawn under it: in the scrolling layout everything that scrolls waits for the first start to end, and where the plate would come within `NopeSpace.s` of the pinned row the words and the plate are left out (section 13, figure `pair-largest`). In the `.starting` state there are no words and no plate edge to see: that frame is the launch screen again. The indicator takes no touches. It turns with `cameraUprightRotation` about the mark's center, so on an iPhone held sideways it is upright as the launch screen's was.

**When.** `CameraScreen` shows the indicator while `model.isFirstStart`, and removes it with `NopeMotion.fade` (opacity only, the same with Reduce Motion). While it is shown, `SessionStatusView` draws no spinner. Every message of `SessionStatusView` is unchanged, and since each of them ends the first start, the mark is never shown with one. After the first start the spinner in the picture is used as today: on return from the background, a lens change and a restart of the camera. If the camera is slow to start, the mark and the words stay; there is no timer.

**VoiceOver.** One element, labeled "Starting the camera…", in both states. No announcement is posted.

### 6.4 The Lock Screen camera and the watch app

Nothing is added to either target.

- The Lock Screen camera is an extension. `UILaunchScreen` belongs to an app's Info.plist, and Apple's LockedCameraCapture documentation describes no launch screen for the extension. Its first frame is its own `Color.black`, kept until the settings arrive, so Night Mode is right from the first thing it draws. It then shows the same `CameraScreen`, so with step 2 it shows the indicator for its first start, red in Night Mode from the start (figure `handoff-lock`). What iOS itself shows before the extension's first frame is not documented; check 7 records it.
- The watch app needs no launch screen.

## 7. What the first frame must match

The app's first frame, in every case of the table, compared with the launch screen:

1. Every pixel outside the mark, the status bar and the home indicator is `#000000`, in the light and the dark appearance, in the safe areas too.
2. The status bar's content is white in both.
3. Step 2: the mark's bounding box is the same rectangle, to the pixel, and its two colors are the same values.
4. Nothing is in the first frame that is gone a moment later: no spinner, no Settings button.
5. Nothing is added in the first frame that the launch screen could have had: only text (the words) and controls appear.

| Starting state | Launch screen | First frames | Then | Figure |
| --- | --- | --- | --- | --- |
| Camera access granted | Black, the mark | The same; then the controls around the mark, and the words under it | The picture; the indicator fades | `handoff-b` |
| First run | The same | The mark alone, while the permission is read | The statements, in the system appearance | `handoff-first-run` |
| Camera access declined, no camera | The same | The mark alone | The message, in the system appearance | – |
| Night Mode on | The same | Red from the first frame, the mark included | The picture | `handoff-night` |
| The camera fails to start or is paused | The same | The mark and the words | The message replaces them at once | – |
| Start in Clean View on | The same | As the first row, with the clean view's controls | The picture | – |
| Largest text sizes | The same | The scrolling layout's pinned row, and the indicator over black; everything that scrolls waits (section 13) | The picture and the scrolling content, in the indicator's fade | `pair-largest` |
| iPhone held sideways | The same, in landscape | The indicator turned upright in the portrait window | The picture | `pair-sideways` |
| iPad, iPhone Duo | The same | The same point in the window | The picture | `pair-ipad-*`, `pair-duo-*` |
| Lock Screen camera | None | Black; then as the first row | The picture | `handoff-lock` |

On first run in the light appearance the screen changes once from black to white (decision 5). It is one change, not a flash between two like screens, and it stops when camera access is granted.

## 8. Acceptance criteria and automated checks

AC, step 1:

- The Info.plist of the built app has `UILaunchScreen` with `UIColorName` = `LaunchBackground` and, for step 1, no other key; `UIStatusBarStyle` is `UIStatusBarStyleLightContent`.
- `LaunchBackground` has one color, black, and no appearance variant.
- With the system in the light appearance, the first screenshot a UI test can take of the camera has a black background, and so has every later one.
- In the `.starting` state the screen has no spinner and no Settings button, and VoiceOver reads "Starting the camera…".
- No string is added or changed. No dependency is added. The app's size grows by less than 10 kB; say by how much.

AC, step 2:

- `LaunchMark.svg` is byte for byte [launch-mark.svg](launch-mark.svg), and its three paths are the paths of the three files in `AppIcon.icon/Assets`.
- While the first start lasts, the indicator's mark is 96 × 96 pt with its center at the window's center, within half a point, in every layout; no spinner is on screen; the audit passes.
- When the session runs, fails or is interrupted, or the state is first run, declined or no camera, the indicator is gone, and it does not come back after the app goes to the background and returns, or after a lens change.
- In Night Mode the screenshot check finds no white, green or blue pixel outside the viewfinder and the status bar while the indicator is shown.
- At the largest text size the words wrap and are not cut off; right to left changes nothing about the indicator's place.
- `isFirstStart` has unit tests for each way it ends and for staying `false`; coverage of non-UI code stays at 100%.

Automated:

| Check | What it does | When |
| --- | --- | --- |
| `scripts/check-launch-screen.sh` | Reads the color set (one color, black, no appearances), compares `LaunchMark.svg` with `docs/design/launch-mark.svg` and its paths with the icon's, and, given a built app, reads its Info.plist with `plutil` for exactly the keys above. Its test script has a passing and a failing case for each. | With the other fast checks, on every pull request; the Info.plist part where a build exists |
| `LaunchHandOffUITests` | With the slow-start scenario: the indicator's frame and label, no spinner, a black screenshot outside the mark and the controls, the audit; the same in the light appearance (`XCUIDevice.shared.appearance = .light`), Night Mode, the largest text size and right to left; then released: the indicator is gone and stays gone. One more test for first run: no indicator once the statements show. | In an existing UI test shard |
| `CameraModelTests` | `isFirstStart`. | Unit tests |

A UI test cannot capture the launch screen. iOS draws it, not the app, and it is gone before the test's first query returns. The launch screen is checked as section 9 describes.

## 9. Checks by hand

Each is run once for the release, and again when a file of section 6 changes. Record the results in `docs/TESTING.md`.

**On the Simulator.** For each of: an iPhone with a 402 × 874 pt screen, a 4.7-inch iPhone, an iPad in portrait, in landscape and in Split View, and the iPhone Duo closed and open; each in the light and the dark appearance (`xcrun simctl ui <device> appearance light`).

1. **The launch screen's pixels.** Remove the app first (`xcrun simctl uninstall`), so no kept copy of an older launch screen is shown, and install it. Start it held for the debugger: `xcrun simctl launch --wait-for-debugger <device> <bundle id>`. Expected: the app's process waits before its first line of code and the launch screen stays up. Take `xcrun simctl io <device> screenshot`. If the launch screen does not stay up this way, record the launch with `xcrun simctl io <device> recordVideo` and take the frames before the app's first. Pass: every pixel outside the status bar and the home indicator is `#000000`; the status bar's content is white in both appearances.
2. **The mark's place** (step 2). In the same screenshots, the bounding box of the pixels that are not black is the 78 × 54 pt frame, centered on the screen across and 3 pt above its center down, at the screen's scale; nothing is scaled. Pass on every device, or use the storyboard of section 6.2.
3. **The first frame.** Record a launch in the light appearance and step through it. Pass: no frame between the launch screen and the camera is lighter than the launch screen; the mark is in every frame until it fades and is in the same pixels in all of them.

**On a device.** An iPhone, an iPad, and an iPhone Duo. Record the screen, and for check 4 also film the phone with a second camera at 240 frames a second, since a single bright frame is what the check is for.

4. **Cold start.** Restart the device, wait a minute, open the app; then close it from the app switcher and open it again. In the light appearance and in the dark one. Pass: as check 3. Note how long the launch screen and the first start last; no time is promised anywhere.
5. **Held sideways** (iPhone, step 2). Start the app with the phone on its side, both ways round. Pass: the mark stays upright and in place, with no turn that can be seen. If a turn shows, option A ships (decision 1).
6. **Night Mode.** Turn Night Mode on, close the app, open it in a dark room. Pass: nothing white but the status bar and, with step 2, the mark, before the red camera; the mark turns from the icon's colors to red in one frame and does not move.
7. **Lock Screen camera.** Open the app's camera from the Lock Screen control, with Night Mode off and on. Record what iOS shows before the extension's first frame. Pass: nothing brighter than black before the camera, and red from the first frame in Night Mode.
8. **Smart Invert and Classic Invert** (step 2). Pass: the launch screen and the first frame agree. If iOS leaves the launch image as it is but inverts the app's mark, or the other way round, option A ships.
9. **First run.** Install fresh, open, in each appearance. Pass: the mark, then the statements, with no third thing between them.
10. **iPhone Duo.** Open the app closed, open and half open. Pass: checks 1 to 3 on each display. The position of the outer display's status strip is as the Simulator shows it.
11. **After an update.** Install release 0.3.0, open it, install the new build over it, open it. Record whether the old launch screen is shown once. If it is, it is the system's and nothing in the app changes it; say so in the release notes for testers.

## 10. Order of work

One chunk, after chunk A of BUILD-SPEC.md section 8 (it edits `CameraScreen.swift`) and chunk E (`SessionStatusView.swift`). Step 1 can be merged without step 2. Step 2 is merged only with section 6.3; never the launch image without the indicator.

## 11. Decisions for the owner

| | Decision | Recommendation |
| --- | --- | --- |
| 1 | Which launch screen | B, built on A. A alone ships if check 2 can't be met even with the storyboard, or check 5 or check 8 fails. |
| 2 | The mark's colors | The icon's: `#EDEDEE` with the teal period. In the app teal means a verified fact; the period is the icon's, as decided for the icon, and is not a status. The alternatives are one color, or the whole mark at half brightness to light less at night. |
| 3 | The mark's size | 96 pt on every device. |
| 4 | The mark takes the spinner's place for the first start | Yes. This changes one thing that 0.3.0 does. Later starts keep the spinner; the words are the same. |
| 5 | First run in the light appearance changes from black to white | Accept it. A launch screen that follows the system would bring the white screen back before the camera on every launch; making first run always dark would undo the rule that it follows the system. |
| 6 | No Settings button while the camera state is not yet known | Yes, as the figure `camera-starting` already draws it. It stays on first run, access declined and no camera. |
| 7 | The indicator on the Lock Screen camera's first start | Yes. It is the same screen. |
| 8 | A slow start | The mark and the words stay until the camera starts or fails. No timer. |

## 12. Not known

Stated here so that no wording, test or release note depends on them until they are checked:

- how long the launch screen and the first start last on any device;
- whether the app's first frame is white in the light appearance today (section 2);
- where iOS places the launch image and whether it scales it;
- whether `--wait-for-debugger` keeps the launch screen up on the Simulator;
- what shows between a landscape launch screen and the portrait window;
- what iOS shows before the Lock Screen camera's first frame;
- how Smart Invert treats the launch image;
- whether an update shows the old launch screen once.

## 13. Large text and the plate

Proposed 2026-11-18, after the build. Accepted by the owner the same day with both recommendations of 13.4 (decision 9: everything that scrolls waits, the pinned row is drawn from the start; decision 10: where the words would come within `NopeSpace.s` of the pinned row, the words and the plate are left out, the mark alone, VoiceOver unchanged). Built for 1.0.0 as 13.3 describes.

### 13.1 The finding

At accessibility text sizes the camera uses the scrolling layout (BUILD-SPEC.md 3.12). Section 6.3 lets the plate lie over that layout's rows, as figure `pair-largest` draws it. On iPad at the largest text size the plate covers most of the title of the Ultra Wide lens row, and the contrast audit of `testFirstStartAtTheLargestTextSizeAndRightToLeft` then fails on that row (docs/TESTING.md, "UI tests and accessibility audits"). Which row is under the plate depends on the window's height and the text size, so the finding comes and goes.

The plate is doing what section 6.3 says. The fault is in the design: a control that is drawn and can be pressed has its name covered. Making the plate only as wide as the words (`StartWordsWidth`) removed the band across the window, not the overlap.

### 13.2 The rule

**While the indicator is shown, nothing is drawn under its plate.** The mark, the words and the plate do not move or change: the mark's center stays the window's center, which the hand-off depends on (sections 5 and 7). The scrolling layout gives way instead.

1. **The scrolling content waits.** In the scrolling layout, while `model.isFirstStart`, everything that scrolls (format status, pills, warnings, the picture's frame, the mode card and every row) is laid out but not drawn, takes no touches and is hidden from VoiceOver. When the first start ends it appears with `NopeMotion.fade`, in the same animation that removes the indicator. The pinned row (Last Photo, shutter, Q) is drawn from the start, as in the other layouts, so the shutter and Settings (through Q) are in reach during a slow start.
2. **The words give way to the pinned row.** If the plate's bottom edge (the window's center, plus 40 pt, plus the height of the wrapped words, plus `NopeSpace.m`) would come within `NopeSpace.s` of the pinned row's top edge, the words and the plate are left out and the mark is shown alone, as in the `.starting` state. This is decided from the layout, once per size of the window, and not from a list of devices. It is for short windows: a small iPhone, a short Stage Manager or Split View window, a language whose words wrap to more lines.

What follows:

- The first frames in the scrolling layout are the launch screen, then the pinned row and the words, then the camera. Rules 4 and 5 of section 7 hold: nothing is drawn and then removed, and only text and controls appear.
- The plate is over black in every layout again, so it cannot be seen, and the result no longer depends on the window's height.
- VoiceOver is unchanged: one element, "Starting the camera…", with or without the words, and no announcement. The rows are read once they are drawn.
- A warning that applies during the first start is shown when the first start ends. A camera that fails or is paused ends the first start, so its message is never held back (section 6.3, "When").
- The stacked and column layouts are unchanged. So are Night Mode, right to left, the Lock Screen camera and every string.

No figure is added. The right half of figure `pair-largest` is redrawn without the rows (status line, picture frame and rows gone; the pinned row, the mark and the words stay), and its caption, the "Largest text sizes" rows of sections 4 and 7 and the plate's sentence in section 6.3 are brought in line.

Considered and not chosen:

| Alternative | Why not |
| --- | --- |
| Leave out the words and the plate at every accessibility size | The mark alone would then lie over a row's title with nothing behind it, and the people who chose large text would be the ones without the words. |
| Move the words above the mark | They would cover the picture's frame or the status line instead, and the plate would still reach the rows under the mark. |
| Move the indicator clear of the rows | The mark would leave the window's center and the hand-off from the launch image would show a jump. |
| Hide only the rows the plate touches | Depends on the window's height, which is what made the finding come and go; rows would appear in two steps. |
| Hold back the controls in every layout | Changes the accepted hand-off of section 7 (the controls appear around the mark) where nothing is covered. |

### 13.3 Build and checks

| File | Change |
| --- | --- |
| `Sources/NopeUI/CameraReadyView.swift` (`scrolling`) | The scrolling content is not drawn, takes no touches and is hidden from VoiceOver while `showsStartIndicator` is set; it fades in when it clears. The pinned row is unchanged. |
| `Sources/NopeUI/StartIndicator.swift` | The words and the plate are left out when part 2 of the rule applies. The room under the mark's center is given by `CameraScreen`, which knows the pinned row's top edge; without it the indicator behaves as today. |
| `App/NopeAppUITests/LaunchHandOffUITests.swift` | Below. |
| `docs/TESTING.md`, [launch.html](launch.html), `screens/launch-pair-largest` | The open finding is closed; the figure and its caption are redrawn. |

AC:

- At every accessibility text size, in every window of section 9, no control that is drawn intersects the plate while the indicator is shown, and the mark's frame is the same as at the default size.
- In the scrolling layout during the first start, the lens rows do not exist for a UI test or for VoiceOver; Take Photo and Quick Menu exist, are whole and can be pressed. When the session runs, the rows exist and the indicator is gone.
- In a window too short for the words, the indicator has no words and no plate, and its label is still "Starting the camera…".
- `testFirstStartAtTheLargestTextSizeAndRightToLeft` passes its audit on iPhone and iPad with no finding set aside, in portrait and landscape on iPad.
- No string is added or changed.

Tests: `testFirstStartAtTheLargestTextSizeAndRightToLeft` also asserts the second point above, before and after the slow start is released. `testFirstStartKeepsTheControlsWhole` runs at the largest text size as well. One new test for the short window, where the UI tests can make one (an iPad window at its smallest size, or the 4.7-inch iPhone with a launch language whose words wrap to three lines); otherwise the fit rule is a unit test of the layout's arithmetic and the short window is a check by hand, recorded in docs/TESTING.md.

### 13.4 Decisions for the owner

| | Decision | Recommendation |
| --- | --- | --- |
| 9 | In the scrolling layout, what waits for the first start to end | Everything that scrolls; the pinned row is drawn from the start. The result is the same in every window height. The alternative is to hold back only the rows under the picture and keep the status line and warnings, as figure `pair-largest` has them; it keeps one line of status on screen for the length of the start, and wrapped warnings in a short window can still reach the plate. |
| 10 | Where the words do not fit above the pinned row | Leave out the words and the plate; the mark alone, VoiceOver unchanged. The alternative, a smaller or single-line text, would not follow the text size. |
