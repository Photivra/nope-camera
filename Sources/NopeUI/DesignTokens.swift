import SwiftUI

// The design tokens of release 1.0.0 (direction B, "Reach"): every spacing, radius, size, type
// style, color, material, animation and haptic the interface uses. Each name maps one to one to
// a row of docs/design/tokens.md, which docs/design/design-system.html draws; the unit tests read
// tokens.md and fail when a name or value differs. Views use these constants instead of literals
// (docs/design/BUILD-SPEC.md, section 1, "Tokens only").
//
// This file imports SwiftUI only and uses nothing else from NopeUI, so a target that doesn't
// link NopeUI (the widget extension, the Apple Watch app) can compile it too.

/// The spacing scale, in points: one scale on a 4-point grid (docs/design/tokens.md, "Spacing").
///
/// Use it for padding and stack spacing. The 0.3.0 values map to it as 2 → 4, 6 → 8, 9 → 8,
/// 10 → 12 and 20 → 24.
///
/// ```swift
/// HStack(spacing: NopeSpace.xs) { … }
///     .padding(.horizontal, NopeSpace.m)
/// ```
enum NopeSpace {
    /// 4 points: the gap between a symbol and its text in a pill, inside the lens group, and
    /// between manual readouts.
    static let xxs: CGFloat = 4

    /// 8 points: the gap between controls and between tiles, the inset of items from the
    /// picture's edge, and the gap between pills and capsules.
    static let xs: CGFloat = 8

    /// 12 points: the inner padding of pills and small capsules, and of dials.
    static let s: CGFloat = 12

    /// 16 points: the screen margin, panel padding and capsule padding.
    static let m: CGFloat = 16

    /// 24 points: the spacing between sections, and the gaps of the column layout.
    static let l: CGFloat = 24

    /// 32 points: the side margin of the shutter row.
    static let xl: CGFloat = 32

    /// 48 points: large separations on the first-run and message screens.
    static let xxl: CGFloat = 48

    /// Every spacing token with its name in docs/design/tokens.md, smallest first, for the tests
    /// and the button gallery.
    static var all: [(name: String, value: CGFloat)] {
        [("xxs", xxs), ("xs", xs), ("s", s), ("m", m), ("l", l), ("xl", xl), ("xxl", xxl)]
    }
}

/// The corner radii, in points: two radii and the capsule (docs/design/tokens.md, "Radii").
///
/// Buttons, pills, chips, the lens group and drive words use `Capsule()` and need no value.
/// System sheets, forms, menus and alerts keep the system's radii. The 0.3.0 radii map as
/// 8, 10 and 12 → 12, and 20 → 24.
enum NopeRadius {
    /// 12 points: tiles, readouts, the thumbnail, hints and the magnifier.
    static let small: CGFloat = 12

    /// 24 points: the Q panel, mode cards, dials, the failure banner and pause messages.
    static let large: CGFloat = 24

    /// Every radius token with its name in docs/design/tokens.md, for the tests and the gallery.
    static var all: [(name: String, value: CGFloat)] {
        [("small", small), ("large", large)]
    }
}

/// Sizes and hit targets, in points (docs/design/tokens.md, "Sizes").
///
/// Every control's hit target is at least ``minTarget`` (44 × 44 points, AGENTS.md "Touch
/// targets"), with ``targetGap`` between targets. A control drawn smaller (a 28-point pill, a
/// 36-point capsule, a 32-point drive word) extends its target with `nopeHitTarget()`.
enum NopeSize {
    /// 44 points: the smallest hit target of any control (Apple Human Interface Guidelines,
    /// "Accessibility"; WCAG 2.2, 2.5.8).
    static let minTarget: CGFloat = 44

    /// 8 points: the smallest gap between two targets; 4 points (``NopeSpace/xxs``) inside the
    /// lens group.
    static let targetGap: CGFloat = 8

    /// 76 points: the diameter of Take Photo.
    static let shutter: CGFloat = 76

    /// 4 points: the width of the shutter's ring.
    static let shutterRing: CGFloat = 4

    /// 60 points: the diameter of the shutter's disc, inside the ring.
    static let shutterDisc: CGFloat = 60

    /// 50 points: the disc while the shutter is held in burst mode (docs/design/BURST.md, 5.3).
    static let shutterDiscHeld: CGFloat = 50

    /// 52 points: the Q button.
    static let quick: CGFloat = 52

    /// 52 points: Last Photo, and Close in the Last Photo viewer, in its place.
    static let thumbnail: CGFloat = 52

    /// 160 points: the largest side of the thumbnail in the Last Photo viewer when the preview is
    /// released (docs/design/BUILD-SPEC.md, 3.14).
    static let viewerFallback: CGFloat = 160

    /// 44 points: round symbol buttons (``NopeIconButtonStyle``).
    static let iconButton: CGFloat = 44

    /// 36 points: the visible height of capsule buttons (``NopeCapsuleStyle``); their target is
    /// still 44.
    static let capsule: CGFloat = 36

    /// 44 points: the large capsule buttons in the Q panel's foot.
    static let capsuleLarge: CGFloat = 44

    /// 36 points: the height of one lens inside the 44-point lens group.
    static let lensItem: CGFloat = 36

    /// 40 points: the smallest width of one lens inside the lens group.
    static let lensItemMinWidth: CGFloat = 40

    /// 32 points: the visible height of a drive word; its target is 44.
    static let driveWord: CGFloat = 32

    /// 28 points: the visible height of pills and warning chips; their target is 44.
    static let pill: CGFloat = 28

    /// 56 points: the smallest height of a tile; it grows when the name wraps.
    static let tileMin: CGFloat = 56

    /// 48 points: the height of a manual readout.
    static let readout: CGFloat = 48

    /// 44 points: the status line of the stacked layout.
    static let statusRow: CGFloat = 44

    /// 56 points: the lens row of the stacked layout.
    static let lensRow: CGFloat = 56

    /// 44 points: the drive strip of the stacked layout.
    static let driveRow: CGFloat = 44

    /// 88 points: the smallest height of the shutter row; it takes the remaining height
    /// (101 points on a 402 × 874-point screen).
    static let shutterRowMin: CGFloat = 88

    /// 104 points: the width of the trailing column in the column layout.
    static let column: CGFloat = 104

    /// 280 points: the picture's height in the scrolling layout (unchanged from 0.3.0).
    static let scrollingPicture: CGFloat = 280

    /// 372 points: the Q panel's width in the column layout and on a sideways iPhone.
    static let panelMaxWidth: CGFloat = 372

    /// 60 points: the focus square (unchanged from 0.3.0).
    static let focusSquare: CGFloat = 60

    /// 96 points: the side of the launch screen's mark and of the same mark in the app's first
    /// frames (``StartIndicator``), on every device (docs/design/LAUNCH-SCREEN.md, 5).
    static let startMark: CGFloat = 96

    /// 64 points: Q and Last Photo in the scrolling layout's pinned shutter row
    /// (docs/design/BUILD-SPEC.md, 3.12). Not in tokens.md; named here so the layout needs no
    /// literal.
    static let scrollingRowButton: CGFloat = 64

    /// 480 points: the widest the bottom stack on the picture gets in the column layout
    /// (docs/design/BUILD-SPEC.md, 3.11). Not in tokens.md.
    static let pictureStackMaxWidth: CGFloat = 480

    /// 1 point: the outline of an unselected control with Increase Contrast, of an off control in
    /// night mode, and of cards and dials (docs/design/design-system.html). Not in tokens.md.
    static let outline: CGFloat = 1

    /// 1.5 points: the amber outline of a warning chip and the failure banner
    /// (docs/design/design-system.html). Not in tokens.md.
    static let warningOutline: CGFloat = 1.5

    /// Every size token whose name is a row of docs/design/tokens.md, with its value, in the order
    /// of the table, for the tests and the gallery. The values named only in the table's notes
    /// (``shutterRing``, ``shutterDisc``, ``capsuleLarge``, ``lensItemMinWidth``) and those not in
    /// tokens.md are listed in ``additional``.
    static var all: [(name: String, value: CGFloat)] {
        [
            ("minTarget", minTarget), ("targetGap", targetGap), ("shutter", shutter), ("quick", quick),
            ("thumbnail", thumbnail), ("viewerFallback", viewerFallback), ("iconButton", iconButton), ("capsule", capsule), ("lensItem", lensItem),
            ("driveWord", driveWord), ("pill", pill), ("tileMin", tileMin), ("readout", readout),
            ("statusRow", statusRow), ("lensRow", lensRow), ("driveRow", driveRow),
            ("shutterRowMin", shutterRowMin), ("column", column), ("scrollingPicture", scrollingPicture),
            ("panelMaxWidth", panelMaxWidth), ("focusSquare", focusSquare), ("startMark", startMark),
        ]
    }

    /// The size tokens that aren't a row of their own in docs/design/tokens.md: those named in a
    /// row's notes, and those this file adds for values the build specification names.
    static var additional: [(name: String, value: CGFloat)] {
        [
            ("shutterRing", shutterRing), ("shutterDisc", shutterDisc), ("shutterDiscHeld", shutterDiscHeld),
            ("capsuleLarge", capsuleLarge), ("lensItemMinWidth", lensItemMinWidth),
            ("scrollingRowButton", scrollingRowButton), ("pictureStackMaxWidth", pictureStackMaxWidth),
            ("outline", outline), ("warningOutline", warningOutline),
        ]
    }
}

/// The type ramp: the system font through Dynamic Type text styles, so every token scales with
/// the person's text size, up to the largest accessibility sizes (docs/design/tokens.md, "Type").
///
/// Forms, sheets, menus and alerts use the system styles unchanged. A font set on a button's own
/// label wins over the one a button style sets, so a lens label can use ``lens`` inside a
/// ``NopeCapsuleStyle``.
enum NopeFont {
    /// Subheadline, semibold (15 points at the default size): format status, drive words,
    /// capsule labels and card titles.
    static var status: Font { .subheadline.weight(.semibold) }

    /// Footnote, semibold (13 points): pills, chips, small capsules and card details.
    static var pill: Font { .footnote.weight(.semibold) }

    /// Caption, medium (12 points): tile names and readout values.
    static var tileName: Font { .caption.weight(.medium) }

    /// Subheadline, semibold (15 points): tile values.
    static var tileValue: Font { .subheadline.weight(.semibold) }

    /// Caption 2, bold (11 points): the A or M on a readout.
    static var readoutMode: Font { .caption2.weight(.bold) }

    /// Body, semibold, monospaced digits (17 points): dial values.
    static var dialValue: Font { .body.weight(.semibold).monospacedDigit() }

    /// Footnote, semibold, monospaced digits (13 points): lens labels.
    static var lens: Font { .footnote.weight(.semibold).monospacedDigit() }

    /// Title 3, bold (20 points): the letter Q.
    static var q: Font { .title3.weight(.bold) }

    /// The countdown number at its default size, 96 points, bold, without scaling. Use
    /// `nopeCountdownFont()`, which scales it with Dynamic Type; this value is the
    /// font at the default text size, for comparison and previews.
    static var countdown: Font { countdown(size: countdownSize) }

    /// 96 points: the countdown number's size at the default text size.
    static let countdownSize: CGFloat = 96

    /// The text style the countdown scales with: Large Title, the largest system style.
    static let countdownTextStyle: Font.TextStyle = .largeTitle

    /// The countdown font at a size, bold.
    ///
    /// - Parameter size: The size in points, usually scaled with `@ScaledMetric`.
    /// - Returns: The system font at that size, bold.
    static func countdown(size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }

    /// Every type token with its name in docs/design/tokens.md, for the tests and the gallery.
    static var all: [(name: String, font: Font)] {
        [
            ("status", status), ("pill", pill), ("tileName", tileName), ("tileValue", tileValue),
            ("readoutMode", readoutMode), ("dialValue", dialValue), ("lens", lens), ("q", q),
            ("countdown", countdown),
        ]
    }
}

/// Scales the countdown font with Dynamic Type (docs/design/tokens.md, "Type", `countdown`).
struct NopeCountdownFont: ViewModifier {
    /// The countdown's size, scaled with the person's text size from 96 points.
    @ScaledMetric(relativeTo: NopeFont.countdownTextStyle) private var size = NopeFont.countdownSize

    /// Creates the modifier. It holds no state of its own.
    init() {}

    /// The content, in the scaled countdown font.
    ///
    /// - Parameter content: The countdown text.
    func body(content: Content) -> some View {
        content.font(NopeFont.countdown(size: size))
    }
}

extension View {
    /// Sets the countdown font, 96 points bold at the default text size, scaled with Dynamic Type.
    func nopeCountdownFont() -> some View {
        modifier(NopeCountdownFont())
    }
}

/// The colors of the camera, one meaning each (docs/design/tokens.md, "Color").
///
/// The camera is always dark. Teal is for verified facts only, amber for warnings only, and a
/// white fill for the selected item; there is no yellow, and no state is shown by color alone
/// (AGENTS.md, "Vision settings"). Brand color reaches system controls only through `tint`.
///
/// Night mode keeps `NightModeStyle`, which multiplies everything by pure red: a view under it
/// draws white for the night red and uses ``nightOutlineUnderMultiply`` for an outline. ``night``
/// and ``nightOutline`` are the final colors, for parts drawn outside that multiply.
enum NopeColor {
    /// System teal (`#40C8E0` in the dark appearance, 10.6:1 on black): verified facts only, such
    /// as the RAW seal and the signed seal.
    static var fact: Color { .teal }

    /// System orange (`#FF9F0A`, 10.2:1 on black): warnings only, always with a triangle and words.
    static var warning: Color { .orange }

    /// A 20% gray (`#333333`): the fill of buttons on the camera's black rows.
    static var controlFill: Color { Color(white: 0.2) }

    /// White: the fill of a selected or on control. Its label is ``selectedLabel``.
    static var selectedFill: Color { .white }

    /// White (21:1 on black): text and symbols on the camera.
    static var label: Color { .white }

    /// A 69% gray (`#B0B0B0`, 9.7:1 on black, 5.8:1 on ``controlFill``): secondary text on the
    /// camera. The mockups draw it as `#AEAEB2`.
    static var labelSecondary: Color { Color(white: 0.69) }

    /// An 83% gray (`#D4D4D4`, 14.1:1 on black): unselected drive words and tile names. The
    /// mockups draw it as `#D1D1D6`.
    static var stripIdle: Color { Color(white: 0.83) }

    /// A light red (`#FF7169`, 4.7:1 on ``controlFill``): the labels of Stop buttons.
    ///
    /// tokens.md defines it as `Color.red` with the mockup value `#FF6961`. The system red in the
    /// dark appearance is `#FF453A`, 3.7:1 on ``controlFill``, and `#FF6961` is 4.48:1; both fall
    /// below the 4.5:1 WCAG 2.2 asks for text (1.4.3) at 15 points semibold, so this is the
    /// nearest red that passes.
    static var destructive: Color { Color(.sRGB, red: 1, green: 0x71 / 255, blue: 0x69 / 255) }

    /// Pure sRGB red (`#FF0000`, 5.25:1 on black): night mode's one color.
    static var night: Color { Color(.sRGB, red: 1, green: 0, blue: 0) }

    /// A dark red (`#B3201A`, 3.1:1 on black): the outline of an off control in night mode, for
    /// parts drawn outside `NightModeStyle`'s multiply. tokens.md writes it as red 0.70, green
    /// 0.125, blue 0.10; this is the same color as the exact bytes of its mockup value.
    static var nightOutline: Color { Color(.sRGB, red: 0xB3 / 255, green: 0x20 / 255, blue: 0x1A / 255) }

    /// An 80% gray that becomes the night-mode outline under `NightModeStyle`'s multiply by pure
    /// red: `#CC0000`, 3.6:1 on black and 3.5:1 on ``controlFillNight`` (WCAG 2.2, 1.4.11, asks
    /// 3:1). ``nightOutline`` would lose its green and blue there and fall to 2.9:1. Not in
    /// tokens.md.
    static var nightOutlineUnderMultiply: Color { Color(white: 0.8) }

    /// An 8% gray, shown as `#140000` under the night multiply: the fill of an off control in
    /// night mode. The night red is 5.1:1 on it; on ``controlFill`` it would be 4.6:1, which the
    /// 0.3.0 audit reported for small text. Not in tokens.md (design-system.html, `--fill`).
    static var controlFillNight: Color { Color(white: 0.08) }

    /// Black: the label on ``selectedFill``.
    static var selectedLabel: Color { .black }

    /// A dark gray (`#3A3A3C`, 11.4:1 on white): a tile's name on a selected tile. Not in
    /// tokens.md (design-system.html, `.tile.sel small`).
    static var selectedLabelSecondary: Color { Color(.sRGB, red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255) }

    /// A bright magenta (`#FF33D9`, 6.7:1 on black): focus peaking only.
    static var peaking: Color { Color(.sRGB, red: 1, green: 0.2, blue: 0.85) }

    /// Black (`#000000`): the launch screen's color, `LaunchBackground` in the app's asset
    /// catalog, and the camera screen's background, so the app's first frame is the launch
    /// screen in the light and the dark appearance (docs/design/LAUNCH-SCREEN.md, 6.1).
    static var launchBackground: Color { Color(.sRGB, red: 0, green: 0, blue: 0) }

    /// The app icon's `#EDEDEE`: the frame and the "n" of the launch mark (``StartMark``). Fixed,
    /// like the launch image, which can't follow Increase Contrast.
    static var mark: Color { Color(.sRGB, red: 0xED / 255, green: 0xED / 255, blue: 0xEE / 255) }

    /// The app icon's `#40C8E0`: the period of the launch mark. Fixed: the system teal of
    /// ``fact`` changes with Increase Contrast, and the launch image can't. The icon's color,
    /// not a verified fact.
    static var markPeriod: Color { Color(.sRGB, red: 0x40 / 255, green: 0xC8 / 255, blue: 0xE0 / 255) }

    /// Every color token whose name is a row of docs/design/tokens.md, for the tests and the
    /// gallery. The colors this file adds are in ``additional``.
    static var all: [(name: String, color: Color)] {
        [
            ("fact", fact), ("warning", warning), ("controlFill", controlFill), ("selectedFill", selectedFill),
            ("label", label), ("labelSecondary", labelSecondary), ("stripIdle", stripIdle),
            ("destructive", destructive), ("night", night), ("nightOutline", nightOutline), ("peaking", peaking),
            ("launchBackground", launchBackground), ("mark", mark), ("markPeriod", markPeriod),
        ]
    }

    /// The color tokens that aren't in docs/design/tokens.md.
    static var additional: [(name: String, color: Color)] {
        [
            ("nightOutlineUnderMultiply", nightOutlineUnderMultiply), ("controlFillNight", controlFillNight),
            ("selectedLabel", selectedLabel), ("selectedLabelSecondary", selectedLabelSecondary),
        ]
    }
}

/// The backgrounds of things drawn over the picture (docs/design/tokens.md, "Materials").
///
/// Apply one with `nopeBackground(_:in:)`:
///
/// ```swift
/// card.nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.large))
/// ```
enum NopeMaterial: CaseIterable, Sendable {
    /// The system's ultra-thin material under black at ``backingDimming``; solid black with
    /// Reduce Transparency or Increase Contrast. Everything on the picture: cards, the readout
    /// row, dials, hints, the Q panel and the status on iPad.
    case backing

    /// Solid black: the failure banner and pause messages, which must be readable over any scene.
    case solid

    /// A 30% system gray over ``backing``: tiles and buttons inside the Q panel and dials.
    case tile

    /// Black at ``rowOverlayOpacity``: the lens row and drive strip where they overlay the
    /// picture on the smallest iPhones.
    case rowOverlay

    /// The opacity of the black over the material in ``backing``: 90%.
    ///
    /// tokens.md says 86%. The 0.3.0 iPad accessibility audit reported text on a 75% backing as
    /// low contrast, and 0.3.0 ships 90%, which passed; this keeps the value that passed
    /// (docs/design/BUILD-SPEC.md, section 1: existing behavior wins and is flagged). Over a pure
    /// white frame the backing is at most a 10% gray, which white text passes with a wide margin
    /// (WCAG 2.2, 1.4.3).
    static let backingDimming: Double = 0.9

    /// The opacity of the system gray in ``tile``: 30%.
    static let tileFillOpacity: Double = 0.3

    /// The opacity of the black in ``rowOverlay``: 72%.
    static let rowOverlayOpacity: Double = 0.72

    /// The material's name in docs/design/tokens.md.
    var name: String {
        switch self {
        case .backing: "backing"
        case .solid: "solid"
        case .tile: "tile"
        case .rowOverlay: "rowOverlay"
        }
    }

    /// Whether the material is drawn as solid black instead of a translucent material: with
    /// Reduce Transparency or Increase Contrast, for ``backing`` and the backing under ``tile``;
    /// always for ``solid``; never for ``rowOverlay``, which is a fixed 72% black.
    ///
    /// - Parameters:
    ///   - reduceTransparency: Whether Reduce Transparency is on.
    ///   - increaseContrast: Whether Increase Contrast is on.
    /// - Returns: `true` when the material is solid black.
    func isSolid(reduceTransparency: Bool, increaseContrast: Bool) -> Bool {
        switch self {
        case .solid: true
        case .rowOverlay: false
        case .backing, .tile: reduceTransparency || increaseContrast
        }
    }

    /// The system gray of ``tile``. On watchOS, which has no `UIColor.systemGray`, SwiftUI's gray.
    static var tileGray: Color {
        #if os(watchOS)
        Color.gray
        #else
        Color(uiColor: .systemGray)
        #endif
    }
}

/// Draws a ``NopeMaterial`` behind content, in a shape, following Reduce Transparency and
/// Increase Contrast.
struct NopeMaterialBackground<S: Shape>: ViewModifier {
    /// The material.
    let material: NopeMaterial

    /// The background's shape.
    let shape: S

    /// Whether Reduce Transparency is on.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Whether Increase Contrast is on.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the background.
    ///
    /// - Parameters:
    ///   - material: The material.
    ///   - shape: The background's shape.
    init(material: NopeMaterial, shape: S) {
        self.material = material
        self.shape = shape
    }

    /// Whether the material is solid black in this environment.
    private var isSolid: Bool {
        material.isSolid(reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased)
    }

    /// Puts the material behind the content.
    ///
    /// - Parameter content: The content.
    func body(content: Content) -> some View {
        content.background {
            switch material {
            case .backing:
                backing
            case .solid:
                shape.fill(.black)
            case .tile:
                backing.overlay(shape.fill(NopeMaterial.tileGray.opacity(NopeMaterial.tileFillOpacity)))
            case .rowOverlay:
                shape.fill(.black.opacity(NopeMaterial.rowOverlayOpacity))
            }
        }
    }

    /// The backing: the dimmed material, or solid black.
    @ViewBuilder private var backing: some View {
        if isSolid {
            shape.fill(.black)
        } else {
            shape.fill(.ultraThinMaterial).overlay(shape.fill(.black.opacity(NopeMaterial.backingDimming)))
        }
    }
}

extension View {
    /// Puts a ``NopeMaterial`` behind the view, in a shape.
    ///
    /// - Parameters:
    ///   - material: The material.
    ///   - shape: The background's shape, for example `Capsule()` or a rounded rectangle with
    ///     ``NopeRadius/large``.
    func nopeBackground<S: Shape>(_ material: NopeMaterial, in shape: S) -> some View {
        modifier(NopeMaterialBackground(material: material, shape: shape))
    }

    /// Makes the view's hit target at least ``NopeSize/minTarget`` (44 points) in each direction,
    /// with the whole frame tappable, without changing how large it is drawn.
    func nopeHitTarget() -> some View {
        frame(minWidth: NopeSize.minTarget, minHeight: NopeSize.minTarget)
            .contentShape(.rect)
    }
}

/// Animations and their Reduce Motion forms (docs/design/tokens.md, "Motion").
///
/// Nothing moves by itself, pulses or blinks. Ask for the form that fits the person's setting:
///
/// ```swift
/// @Environment(\.accessibilityReduceMotion) private var reduceMotion
/// …
/// .animation(NopeMotion.panel(reduceMotion: reduceMotion), value: isOpen)
/// .transition(NopeMotion.panelTransition(reduceMotion: reduceMotion))
/// ```
enum NopeMotion {
    /// Snappy, 0.3 seconds: the Q panel, cards and dials appearing.
    static var panel: Animation { .snappy(duration: 0.3) }

    /// Snappy, 0.2 seconds: the selection fill moving between lenses or drive words.
    static var select: Animation { .snappy(duration: 0.2) }

    /// Ease in and out, 0.2 seconds: pills, chips, hints and clean view. The same with Reduce
    /// Motion, since a fade doesn't move.
    static var fade: Animation { .easeInOut(duration: 0.2) }

    /// The panel's animation for the person's setting: ``panel``, or with Reduce Motion a 0.2-second
    /// crossfade (``fade``); pair it with ``panelTransition(reduceMotion:)``.
    ///
    /// - Parameter reduceMotion: Whether Reduce Motion is on.
    /// - Returns: The animation.
    static func panel(reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : panel
    }

    /// How a panel, card or dial enters and leaves: rising from the bottom edge with a fade, or with
    /// Reduce Motion only a fade.
    ///
    /// - Parameter reduceMotion: Whether Reduce Motion is on.
    /// - Returns: The transition.
    static func panelTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    /// The selection's animation for the person's setting: ``select``, or with Reduce Motion none,
    /// so the fill switches without sliding.
    ///
    /// - Parameter reduceMotion: Whether Reduce Motion is on.
    /// - Returns: The animation, or `nil` for none.
    static func select(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : select
    }

    /// The opacity of a custom button while it is pressed: 70%.
    static let pressedOpacity: Double = 0.7

    /// The scale of a custom button while it is pressed: 97%; none with Reduce Motion.
    static let pressedScale: CGFloat = 0.97

    /// The opacity of a disabled custom button, and of the other drive words while the drive is
    /// busy: 40%.
    static let disabledOpacity: Double = 0.4

    /// A button's scale for its press state.
    ///
    /// - Parameters:
    ///   - isPressed: Whether the button is pressed.
    ///   - reduceMotion: Whether Reduce Motion is on.
    /// - Returns: ``pressedScale`` while pressed without Reduce Motion, otherwise 1.
    static func scale(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
        isPressed && !reduceMotion ? pressedScale : 1
    }

    /// A button's opacity for its press and enabled states.
    ///
    /// - Parameters:
    ///   - isPressed: Whether the button is pressed.
    ///   - isEnabled: Whether the button is enabled.
    /// - Returns: ``disabledOpacity`` when disabled, ``pressedOpacity`` while pressed, otherwise 1.
    static func opacity(isPressed: Bool, isEnabled: Bool) -> Double {
        if !isEnabled { return disabledOpacity }
        return isPressed ? pressedOpacity : 1
    }

    /// Every animation token with its name in docs/design/tokens.md, for the tests.
    static var all: [(name: String, animation: Animation)] {
        [("panel", panel), ("select", select), ("fade", fade)]
    }
}

/// The haptics, all played through `sensoryFeedback`, each paired with something seen and a
/// VoiceOver announcement (docs/design/tokens.md, "Haptics").
///
/// ```swift
/// .sensoryFeedback(NopeHaptic.driveModeChanged, trigger: driveMode)
/// ```
enum NopeHaptic {
    /// The shutter is pressed.
    static var shutter: SensoryFeedback { .impact }

    /// A photo was saved.
    static var saved: SensoryFeedback { .impact(weight: .light) }

    /// A photo wasn't saved.
    static var notSaved: SensoryFeedback { .error }

    /// The lens changed.
    static var lensChanged: SensoryFeedback { .selection }

    /// One second of a countdown passed.
    static var countdownSecond: SensoryFeedback { .impact(weight: .light) }

    /// The level reached flat.
    static var levelFlat: SensoryFeedback { .alignment }

    /// All Auto returned every manual control to auto.
    static var allAuto: SensoryFeedback { .success }

    /// The drive mode changed (new in 1.0.0, extending the lens rule).
    static var driveModeChanged: SensoryFeedback { .selection }

    /// Manual Controls turned on or off (new in 1.0.0, extending the lens rule).
    static var manualControlsChanged: SensoryFeedback { .selection }

    /// Each photo of a burst after the first: one light tap, beside the count on the card and
    /// the system's shutter sound (docs/design/BURST.md, 4.3).
    static var burstFrame: SensoryFeedback { .impact(weight: .light, intensity: 0.6) }
}
