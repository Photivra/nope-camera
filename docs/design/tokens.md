# Design tokens

Design version: 1.0.0, direction B · Reach (2026-11-17).

The tokens of the design, as a list for the build. [design-system.html](design-system.html) shows the same tokens drawn. Each name maps one to one to a Swift constant in a new file, `Sources/NopeUI/DesignTokens.swift`. No view uses a literal spacing, radius, size, color or duration once this file exists; a test or lint check fails on new literals outside the scales (issue 74).

## Spacing: `enum NopeSpace` (`CGFloat`)

| Token | Value | Typical use |
| --- | --- | --- |
| `xxs` | 4 | Symbol-to-text gap in pills; gaps inside the lens group and between readouts |
| `xs` | 8 | Gap between controls and between tiles; inset of items from the picture edge; pill and capsule gaps |
| `s` | 12 | Inner padding of pills and small capsules; padding of dials |
| `m` | 16 | Screen margin; panel padding; capsule padding |
| `l` | 24 | Section spacing; column-layout gaps |
| `xl` | 32 | Shutter row side margin |
| `xxl` | 48 | Large separations in first run and the message screens |

Replacing 0.3.0 literals: 2 → 4, 6 → 8, 9 → 8, 10 → 12, 20 → 24. Values 0, 4, 8, 12, 16, 24 and 32 keep their value.

## Radii: `enum NopeRadius` (`CGFloat`)

| Token | Value | Use |
| --- | --- | --- |
| `small` | 12 | Tiles, readouts, the thumbnail, hints, the magnifier |
| `large` | 24 | The Q panel, cards, dials, the failure banner, pause messages |
| capsule | `Capsule()` | Buttons, pills, chips, the lens group, drive words |

Replacing 0.3.0 literals: 8 → 12, 10 → 12, 12 → 12, 20 → 24. System sheets, forms, menus and alerts keep the system radii.

## Sizes: `enum NopeSize` (`CGFloat`)

| Token | Value | Use |
| --- | --- | --- |
| `minTarget` | 44 | Smallest hit target of any control |
| `targetGap` | 8 | Smallest gap between two targets |
| `shutter` | 76 | Take Photo (`shutterRing` 4, `shutterDisc` 60) |
| `quick` | 52 | The Q button |
| `thumbnail` | 52 | Last Photo |
| `iconButton` | 44 | Round symbol buttons |
| `capsule` | 36 | Capsule buttons (`capsuleLarge` 44 in the Q foot) |
| `lensItem` | 36 high, 40 wide at least | One lens inside the 44 pt lens group |
| `driveWord` | 32 | Visible height of a drive word; target 44 |
| `pill` | 28 | Pills and warning chips; target 44 |
| `tileMin` | 56 | Minimum tile height |
| `readout` | 48 | Manual readouts |
| `statusRow` | 44 | Status line |
| `lensRow` | 56 | Lens row |
| `driveRow` | 44 | Drive strip |
| `shutterRowMin` | 88 | Shutter row; takes the remaining height (101 on a 402 × 874 pt screen) |
| `column` | 104 | Width of the trailing column in the column layout |
| `scrollingPicture` | 280 | Picture height in the scrolling layout (unchanged) |
| `panelMaxWidth` | 372 | Q panel width in the column layout and sideways |
| `focusSquare` | 60 | Focus square (unchanged) |

## Type: `enum NopeFont` (`Font`)

System font, Dynamic Type text styles. Sizes are at the default setting.

| Token | Definition | Size | Use |
| --- | --- | --- | --- |
| `status` | `.subheadline.weight(.semibold)` | 15 | Format status, drive words, capsule labels, card titles |
| `pill` | `.footnote.weight(.semibold)` | 13 | Pills, chips, small capsules, card detail |
| `tileName` | `.caption.weight(.medium)` | 12 | Tile names, readout values |
| `tileValue` | `.subheadline.weight(.semibold)` | 15 | Tile values |
| `readoutMode` | `.caption2.weight(.bold)` | 11 | A or M on a readout |
| `dialValue` | `.body.weight(.semibold).monospacedDigit()` | 17 | Dial values |
| `lens` | `.footnote.weight(.semibold).monospacedDigit()` | 13 | Lens labels |
| `q` | `.title3.weight(.bold)` | 20 | The letter Q |
| `countdown` | `.system(size: 96, weight: .bold)` with `@ScaledMetric` | 96 | Countdown |

Forms, sheets, menus and alerts use the system styles unchanged.

## Color: `enum NopeColor` (`Color`)

| Token | Definition | Mockup value | Meaning |
| --- | --- | --- | --- |
| `fact` | `Color.teal` | `#40C8E0` | Verified facts only |
| `warning` | `Color.orange` | `#FF9F0A` | Warnings only, with a triangle and words |
| `controlFill` | `Color(white: 0.2)` | `#333333` | Buttons on the black rows |
| `selectedFill` | `Color.white` | `#FFFFFF` | Selected or on; its label is black |
| `label` | `Color.white` | `#FFFFFF` | Text and symbols on the camera |
| `labelSecondary` | `Color(white: 0.69)` | `#AEAEB2` | Secondary text on the camera |
| `stripIdle` | `Color(white: 0.83)` | `#D1D1D6` | Unselected drive words |
| `destructive` | `Color.red` | `#FF6961` | Stop labels |
| `night` | `Color(red: 1, green: 0, blue: 0)` | `#FF0000` | Night mode foreground |
| `nightOutline` | `Color(red: 0.70, green: 0.125, blue: 0.10)` | `#B3201A` | Night mode outline of an off control (3.1:1) |
| `peaking` | `Color(red: 1, green: 0.2, blue: 0.85)` | `#FF33D9` | Focus peaking only |

Rules: one meaning for each color; never color alone; no yellow; brand color reaches system controls only through `tint`. Night mode keeps the existing `NightModeStyle` (everything multiplied by pure red); `night` and `nightOutline` are for the custom-drawn parts.

## Materials: `enum NopeMaterial`

| Token | Definition | Use |
| --- | --- | --- |
| `backing` | `.ultraThinMaterial` under black at 86%; solid black with Reduce Transparency or Increase Contrast (today's `darkBacking()`, renamed) | Everything on the picture |
| `solid` | Black | Failure banner, pause messages |
| `tile` | `Color(.systemGray).opacity(0.3)` over `backing` | Tiles and buttons inside panels and dials |
| `rowOverlay` | Black at 72% | Lens row and drive strip where they overlay the picture |

## Motion: `enum NopeMotion` (`Animation`)

| Token | Definition | Use | Reduce Motion |
| --- | --- | --- | --- |
| `panel` | `.snappy(duration: 0.3)` | Q panel, cards, dials appear | `.easeInOut(duration: 0.2)` opacity only |
| `select` | `.snappy(duration: 0.2)` | Selection fill moving | none; state switches |
| `fade` | `.easeInOut(duration: 0.2)` | Pills, chips, hints, clean view | the same |

Pressed state of every custom button: opacity 0.7 and scale 0.97; opacity only with Reduce Motion.

## Haptics

All through `sensoryFeedback`. Existing: shutter `.impact`; saved `.impact(weight: .light)`; not saved `.error`; lens change `.selection`; countdown second `.impact(weight: .light)`; level reached `.alignment` (`NopeHaptic.levelReached`, the horizon or the top-down level becoming level; [level-haptic.md](level-haptic.md)); All Auto `.success`. Added: `.selection` when the drive mode or Manual Controls changes.

## Button types

| Type | Swift | Notes |
| --- | --- | --- |
| Primary | `ShutterButton` (kept) | Ring and disc; stop square while a series runs; the timer delay as a number on the disc |
| Icon | `NopeIconButtonStyle(size:)` | 44 pt circle; 52 pt for Q |
| Capsule | `NopeCapsuleStyle(isSelected:role:size:)` | Replaces `SelectableCapsuleStyle`; `role: .destructive` gives the red label |
| Tile | `NopeTileStyle(isOn:)` | Q tiles and manual readouts |
| Pill | `NopePillStyle(isSelected:)` | Replaces `pillShape()` |
| Warning chip | `WarningChip` (kept, restyled with tokens) | Amber outline, triangle, words |
| System | `.borderedProminent`, plain rows | Forms and sheets |

States for every custom type: normal, pressed, selected, disabled (opacity 0.4), night mode (on filled red with black label; off outlined in `nightOutline`), Increase Contrast (outline added to every unselected control), Button Shapes (already shapes; no change), and the largest text sizes (the label wraps or the Large Content Viewer shows it).
