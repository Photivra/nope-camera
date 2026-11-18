import SwiftUI

// The custom button types of release 1.0.0 (docs/design/tokens.md, "Button types"). Seven types
// cover every button in the app:
//
// | Type          | Swift                                         |
// | ------------- | --------------------------------------------- |
// | Primary       | `ShutterButton` (ShutterButton.swift)         |
// | Icon          | `NopeIconButtonStyle(size:isSelected:)`       |
// | Capsule       | `NopeCapsuleStyle(isSelected:role:size:…)`    |
// | Tile          | `NopeTileStyle(isOn:minHeight:alignment:)`    |
// | Pill and chip | `NopePillStyle(isSelected:isOnPicture:)`, `WarningChip` |
// | Destructive   | `NopeCapsuleStyle(role: .destructive)`        |
// | System        | `.borderedProminent` and plain rows in forms  |
//
// Every custom type has the same states: normal; pressed (70% opacity and 97% scale, opacity only
// with Reduce Motion); selected (filled white with a black label); disabled (40% opacity); night
// mode (on filled red with a black label, off outlined); Increase Contrast (an outline on every
// unselected control); and a hit target of at least 44 × 44 points. Button Shapes needs no change:
// each type already has a shape. Labels use Dynamic Type; a control that can't grow (the icon
// buttons) shows its label in the Large Content Viewer.

/// What a custom control is filled with when it isn't selected.
enum NopeIdleFill: Equatable, Sendable {
    /// ``NopeColor/controlFill``, or ``NopeColor/controlFillNight`` in night mode: buttons on the
    /// camera's black rows.
    case control

    /// ``NopeMaterial/tile``, or ``NopeColor/controlFillNight`` in night mode: tiles and buttons
    /// in panels and dials.
    case tile

    /// ``NopeMaterial/backing``: a pill or chip drawn over the picture.
    case backing

    /// No fill: the unselected drive words, which sit on the black strip.
    case none
}

/// The colors of a custom control in one state, resolved from the tokens. It is plain data, so
/// the rules are tested without drawing.
///
/// Night mode is drawn by `NightModeStyle`, which multiplies everything by pure red: white here is
/// shown as the night red, black stays black, and ``NopeColor/nightOutlineUnderMultiply`` is
/// shown as the night outline.
struct NopeControlAppearance: Equatable {
    /// How a control is filled.
    enum Fill: Equatable {
        /// A solid color.
        case color(Color)
        /// A material over the picture.
        case material(NopeMaterial)
        /// No fill.
        case none
    }

    /// The fill.
    let fill: Fill

    /// The label's primary color: its symbol and main text.
    let label: Color

    /// The label's secondary color, for a tile's name or a readout's mode letter.
    let secondaryLabel: Color

    /// The outline, or `nil` for none. Its width is ``NopeSize/outline``.
    let outline: Color?

    /// Creates an appearance. Use ``resolve(isSelected:idleFill:isDestructive:isNightMode:increaseContrast:)``
    /// to get the one the design gives a state.
    ///
    /// - Parameters:
    ///   - fill: The fill.
    ///   - label: The label's primary color.
    ///   - secondaryLabel: The label's secondary color.
    ///   - outline: The outline, or `nil` for none.
    init(fill: Fill, label: Color, secondaryLabel: Color, outline: Color?) {
        self.fill = fill
        self.label = label
        self.secondaryLabel = secondaryLabel
        self.outline = outline
    }

    /// The appearance of a control.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the control is selected or on.
    ///   - idleFill: What the control is filled with when it isn't selected.
    ///   - isDestructive: Whether the label is a destructive action, such as Stop.
    ///   - isNightMode: Whether night mode is on.
    ///   - increaseContrast: Whether Increase Contrast is on.
    /// - Returns: The fill, label colors and outline.
    static func resolve(
        isSelected: Bool, idleFill: NopeIdleFill, isDestructive: Bool = false, isNightMode: Bool,
        increaseContrast: Bool
    ) -> NopeControlAppearance {
        if isSelected {
            return NopeControlAppearance(
                fill: .color(NopeColor.selectedFill), label: NopeColor.selectedLabel,
                secondaryLabel: isNightMode ? NopeColor.selectedLabel : NopeColor.selectedLabelSecondary, outline: nil)
        }
        if isNightMode {
            // On is filled and off is outlined; every label is the full night red, because a
            // dimmer red falls below 4.5:1 (docs/design/ACCESSIBILITY.md, "Motion, transparency,
            // contrast").
            let fill: Fill = idleFill == .none ? .none : .color(NopeColor.controlFillNight)
            return NopeControlAppearance(
                fill: fill, label: NopeColor.label, secondaryLabel: NopeColor.label,
                outline: NopeColor.nightOutlineUnderMultiply)
        }
        let fill: Fill =
            switch idleFill {
            case .control: .color(NopeColor.controlFill)
            case .tile: .material(.tile)
            case .backing: .material(.backing)
            case .none: .none
            }
        let label = isDestructive ? NopeColor.destructive : (idleFill == .none ? NopeColor.stripIdle : NopeColor.label)
        return NopeControlAppearance(
            fill: fill, label: label, secondaryLabel: NopeColor.stripIdle,
            outline: increaseContrast ? NopeColor.labelSecondary : nil)
    }
}

/// Draws a ``NopeControlAppearance``'s fill and outline behind content, in a shape.
struct NopeControlBackground<S: InsettableShape>: ViewModifier {
    /// The appearance.
    let appearance: NopeControlAppearance

    /// The shape.
    let shape: S

    /// Creates the background.
    ///
    /// - Parameters:
    ///   - appearance: The appearance.
    ///   - shape: The shape.
    init(appearance: NopeControlAppearance, shape: S) {
        self.appearance = appearance
        self.shape = shape
    }

    /// The content, with the fill behind it and the outline over its edge.
    ///
    /// - Parameter content: The content.
    func body(content: Content) -> some View {
        filled(content)
            .overlay {
                if let outline = appearance.outline {
                    shape.strokeBorder(outline, lineWidth: NopeSize.outline)
                }
            }
    }

    /// The content with the fill behind it.
    ///
    /// - Parameter content: The content.
    @ViewBuilder private func filled(_ content: Content) -> some View {
        switch appearance.fill {
        case .color(let color): content.background(color, in: shape)
        case .material(let material): content.nopeBackground(material, in: shape)
        case .none: content
        }
    }
}

/// The press and enabled states every custom button shares: 70% opacity and 97% scale while
/// pressed (opacity only with Reduce Motion), and 40% opacity when disabled.
struct NopePressEffect: ViewModifier {
    /// Whether the button is pressed.
    let isPressed: Bool

    /// Whether the button is enabled.
    @Environment(\.isEnabled) private var isEnabled

    /// Whether Reduce Motion is on.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the effect.
    ///
    /// - Parameter isPressed: Whether the button is pressed.
    init(isPressed: Bool) {
        self.isPressed = isPressed
    }

    /// The content, faded and scaled for its state.
    ///
    /// - Parameter content: The styled button.
    func body(content: Content) -> some View {
        content
            .opacity(NopeMotion.opacity(isPressed: isPressed, isEnabled: isEnabled))
            .scaleEffect(NopeMotion.scale(isPressed: isPressed, reduceMotion: reduceMotion))
    }
}

/// A round symbol button: 44 points across by default, 52 for Q (docs/design/tokens.md, "Icon").
///
/// Use it for Switch Camera, Q, minus and plus, close, Show Controls and More. Selected (Q while
/// its panel is open) is filled white with a black symbol. The button can't grow with the text
/// size, so its label is shown in the Large Content Viewer; give the button an accessibility
/// label.
///
/// ```swift
/// Button(action: toggleQuickMenu) {
///     Text(verbatim: "Q").font(NopeFont.q)
/// }
/// .buttonStyle(NopeIconButtonStyle(size: NopeSize.quick, isSelected: isOpen))
/// ```
struct NopeIconButtonStyle: ButtonStyle {
    /// The diameter, in points.
    let size: CGFloat

    /// Whether the button is selected.
    let isSelected: Bool

    /// Whether night mode is on.
    @Environment(\.isNightMode) private var isNightMode

    /// Whether Increase Contrast is on.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the style.
    ///
    /// - Parameters:
    ///   - size: The diameter, in points: ``NopeSize/iconButton`` (44) by default, ``NopeSize/quick``
    ///     (52) for Q. The hit target is never smaller than ``NopeSize/minTarget``.
    ///   - isSelected: Whether the button is selected, as Q is while its panel is open.
    init(size: CGFloat = NopeSize.iconButton, isSelected: Bool = false) {
        self.size = size
        self.isSelected = isSelected
    }

    /// The styled button.
    ///
    /// - Parameter configuration: The button's label and press state.
    func makeBody(configuration: Configuration) -> some View {
        let appearance = NopeControlAppearance.resolve(
            isSelected: isSelected, idleFill: .control, isDestructive: configuration.role == .destructive,
            isNightMode: isNightMode, increaseContrast: contrast == .increased)
        configuration.label
            .foregroundStyle(appearance.label)
            .environment(\.nopeSecondaryLabel, appearance.secondaryLabel)
            .frame(width: size, height: size)
            .modifier(NopeControlBackground(appearance: appearance, shape: Circle()))
            .nopeHitTarget()
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.highlight)
            .modifier(NopePressEffect(isPressed: configuration.isPressed))
            .accessibilityShowsLargeContentViewer()
    }
}

/// A capsule button with a symbol and words (docs/design/tokens.md, "Capsule", "Toggle" and
/// "Destructive").
///
/// - Secondary: Manual Controls, card buttons, Auto on a dial, Try Again.
/// - Selectable (`isSelected`): filled white with a black label when on; Manual Controls,
///   lenses, drive words, the Compare view buttons.
/// - Destructive (`role: .destructive`, or a `Button(role: .destructive)`): the red label of Stop,
///   Stop Burst and Stop Frames.
///
/// It is ``NopeSize/capsule`` (36 points) high with a 44-point target; ``NopeSize/capsuleLarge``
/// in the Q panel's foot. The label is ``NopeFont/status``, or ``NopeFont/pill`` when compact; a
/// font set on the label itself wins, as for the lens labels (``NopeFont/lens``).
///
/// ```swift
/// Button(action: stop) { Label(stopTitle, systemImage: "stop.fill") }
///     .buttonStyle(NopeCapsuleStyle(role: .destructive))
/// ```
struct NopeCapsuleStyle: ButtonStyle {
    /// Whether the button is selected or on.
    let isSelected: Bool

    /// The button's role; `.destructive` gives the red label.
    let role: ButtonRole?

    /// The visible height, in points.
    let size: CGFloat

    /// Whether the button is a small capsule: ``NopeFont/pill`` and ``NopeSpace/s`` padding.
    let isCompact: Bool

    /// What the button is filled with when it isn't selected.
    let idleFill: NopeIdleFill

    /// Whether night mode is on.
    @Environment(\.isNightMode) private var isNightMode

    /// Whether Increase Contrast is on.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the style.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the button is selected or on.
    ///   - role: The button's role; `.destructive` gives the red label. A `Button(role:)` role
    ///     does the same.
    ///   - size: The visible height in points: ``NopeSize/capsule`` (36) by default,
    ///     ``NopeSize/capsuleLarge`` (44) in the Q panel's foot, ``NopeSize/driveWord`` (32) for
    ///     drive words, ``NopeSize/lensItem`` (36) for a lens. The hit target is at least 44.
    ///   - isCompact: Whether the button is a small capsule, with the pill font and less padding.
    ///   - idleFill: What the button is filled with when not selected: ``NopeIdleFill/control`` on
    ///     the black rows, ``NopeIdleFill/tile`` in panels and dials, ``NopeIdleFill/none`` for
    ///     drive words.
    init(
        isSelected: Bool = false, role: ButtonRole? = nil, size: CGFloat = NopeSize.capsule,
        isCompact: Bool = false, idleFill: NopeIdleFill = .control
    ) {
        self.isSelected = isSelected
        self.role = role
        self.size = size
        self.isCompact = isCompact
        self.idleFill = idleFill
    }

    /// The space on each side of the label, in points.
    var horizontalPadding: CGFloat {
        isCompact ? NopeSpace.s : NopeSpace.m
    }

    /// The styled button.
    ///
    /// - Parameter configuration: The button's label and press state.
    func makeBody(configuration: Configuration) -> some View {
        let appearance = NopeControlAppearance.resolve(
            isSelected: isSelected, idleFill: idleFill,
            isDestructive: role == .destructive || configuration.role == .destructive,
            isNightMode: isNightMode, increaseContrast: contrast == .increased)
        configuration.label
            .font(isCompact ? NopeFont.pill : NopeFont.status)
            .foregroundStyle(appearance.label)
            .environment(\.nopeSecondaryLabel, appearance.secondaryLabel)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: size)
            .modifier(NopeControlBackground(appearance: appearance, shape: Capsule()))
            .nopeHitTarget()
            .contentShape(.hoverEffect, .capsule)
            .hoverEffect(.highlight)
            .modifier(NopePressEffect(isPressed: configuration.isPressed))
    }
}

/// A tile: a name over a symbol and value, in a rounded rectangle (docs/design/tokens.md, "Tile").
/// Use it for the Q tiles and the manual readouts; ``NopeTileLabel`` lays out a tile's content.
///
/// Off, it is a 30% gray over the backing (``NopeMaterial/tile``); on, filled white with a black
/// label. The label's foreground style is the value's color; the name's color is in the
/// environment, as `nopeSecondaryLabel`.
///
/// ```swift
/// Button(action: toggleGrid) {
///     NopeTileLabel(name: gridTitle, value: gridValue, systemImage: "grid")
/// }
/// .buttonStyle(NopeTileStyle(isOn: isGridOn))
/// ```
struct NopeTileStyle: ButtonStyle {
    /// Whether the tile is on.
    let isOn: Bool

    /// The smallest height, in points.
    let minHeight: CGFloat

    /// Where the content sits inside the tile.
    let alignment: Alignment

    /// Whether night mode is on.
    @Environment(\.isNightMode) private var isNightMode

    /// Whether Increase Contrast is on.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the style.
    ///
    /// - Parameters:
    ///   - isOn: Whether the tile is on.
    ///   - minHeight: The smallest height in points: ``NopeSize/tileMin`` (56) for a Q tile,
    ///     ``NopeSize/readout`` (48) for a manual readout. The tile grows when its name wraps.
    ///   - alignment: Where the content sits: leading for a Q tile, centered for a readout.
    init(isOn: Bool, minHeight: CGFloat = NopeSize.tileMin, alignment: Alignment = .leading) {
        self.isOn = isOn
        self.minHeight = minHeight
        self.alignment = alignment
    }

    /// The styled tile.
    ///
    /// - Parameter configuration: The tile's label and press state.
    func makeBody(configuration: Configuration) -> some View {
        let appearance = NopeControlAppearance.resolve(
            isSelected: isOn, idleFill: .tile, isNightMode: isNightMode, increaseContrast: contrast == .increased)
        let shape = RoundedRectangle(cornerRadius: NopeRadius.small)
        configuration.label
            .foregroundStyle(appearance.label)
            .environment(\.nopeSecondaryLabel, appearance.secondaryLabel)
            .padding(.vertical, NopeSpace.xs)
            .padding(.leading, alignment.horizontal == .leading ? NopeSpace.s : NopeSpace.xs)
            .padding(.trailing, NopeSpace.xs)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: alignment)
            .modifier(NopeControlBackground(appearance: appearance, shape: shape))
            .nopeHitTarget()
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
            .modifier(NopePressEffect(isPressed: configuration.isPressed))
    }
}

extension EnvironmentValues {
    /// The color of secondary text inside a custom button, such as a tile's name or a readout's
    /// mode letter, for the button's state: set by the button styles from
    /// ``NopeControlAppearance/secondaryLabel``. A view inside the button's label reads it; the
    /// hierarchical `.secondary` style would instead fade the primary color, which the
    /// accessibility audit reported as low contrast on a selected tile.
    @Entry var nopeSecondaryLabel: Color = NopeColor.stripIdle
}

/// A tile's content: the name on top (``NopeFont/tileName``, up to two lines, in the secondary
/// style), then the symbol and the value (``NopeFont/tileValue``). Inside a button, VoiceOver
/// reads the name, then the value ("Grid, Thirds").
struct NopeTileLabel: View {
    /// The tile's name, such as "Grid".
    let name: Text

    /// The tile's value, such as "Thirds" or "Off".
    let value: Text

    /// The SF Symbol before the value, or `nil` for none.
    let systemImage: String?

    /// The color of the name, set by the button style for its state.
    @Environment(\.nopeSecondaryLabel) private var secondaryLabel

    /// Creates a tile's content.
    ///
    /// - Parameters:
    ///   - name: The tile's name.
    ///   - value: The tile's value.
    ///   - systemImage: The SF Symbol before the value, or `nil` for none.
    init(name: Text, value: Text, systemImage: String? = nil) {
        self.name = name
        self.value = value
        self.systemImage = systemImage
    }

    /// The name over the symbol and value.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
            name
                .font(NopeFont.tileName)
                .foregroundStyle(secondaryLabel)
            HStack(spacing: NopeSpace.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                value
            }
            .font(NopeFont.tileValue)
        }
    }
}

/// A pill: a small capsule for a changed setting (docs/design/tokens.md, "Pill").
///
/// It is ``NopeSize/pill`` (28 points) high with a 44-point target, in ``NopeFont/pill``, with
/// ``NopeSpace/xxs`` between symbol and text. Over the picture (the column layout, a sideways
/// iPhone) it has the backing, so its contrast doesn't depend on the scene.
struct NopePillStyle: ButtonStyle {
    /// Whether the pill is selected.
    let isSelected: Bool

    /// Whether the pill is drawn over the picture.
    let isOnPicture: Bool

    /// Whether night mode is on.
    @Environment(\.isNightMode) private var isNightMode

    /// Whether Increase Contrast is on.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the style.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the pill is selected.
    ///   - isOnPicture: Whether the pill is drawn over the picture, where it gets the backing
    ///     (``NopeMaterial/backing``) instead of ``NopeColor/controlFill``.
    init(isSelected: Bool = false, isOnPicture: Bool = false) {
        self.isSelected = isSelected
        self.isOnPicture = isOnPicture
    }

    /// The styled pill.
    ///
    /// - Parameter configuration: The pill's label and press state.
    func makeBody(configuration: Configuration) -> some View {
        let appearance = NopeControlAppearance.resolve(
            isSelected: isSelected, idleFill: isOnPicture ? .backing : .control, isNightMode: isNightMode,
            increaseContrast: contrast == .increased)
        configuration.label
            .labelStyle(NopePillLabelStyle())
            .font(NopeFont.pill)
            .foregroundStyle(appearance.label)
            .environment(\.nopeSecondaryLabel, appearance.secondaryLabel)
            .padding(.horizontal, NopeSpace.s)
            .frame(minHeight: NopeSize.pill)
            .modifier(NopeControlBackground(appearance: appearance, shape: Capsule()))
            .nopeHitTarget()
            .contentShape(.hoverEffect, .capsule)
            .hoverEffect(.highlight)
            .modifier(NopePressEffect(isPressed: configuration.isPressed))
    }
}

/// A pill's label: the symbol and the title, ``NopeSpace/xxs`` apart.
struct NopePillLabelStyle: LabelStyle {
    /// Creates the style. It holds no state.
    init() {}

    /// The symbol, then the title.
    ///
    /// - Parameter configuration: The label's icon and title.
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: NopeSpace.xxs) {
            configuration.icon
            configuration.title
        }
    }
}

#if DEBUG
/// Debug builds only: every custom button type in each of its states, on the camera's black, for
/// review and for the UI tests' accessibility audits (docs/design/BUILD-SPEC.md, section 8,
/// chunk 0). The app shows it instead of the camera when launched with `-NopeButtonGallery`;
/// `-NopeButtonGallery.night YES` draws it in night mode. Its words are fixed English sample
/// labels, not interface text.
public struct NopeButtonGallery: View {
    /// Whether the gallery is in night mode.
    let isNightMode: Bool

    /// The person's text size.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates the gallery.
    ///
    /// - Parameter isNightMode: Whether to draw it in night mode.
    public init(isNightMode: Bool = false) {
        self.isNightMode = isNightMode
    }

    /// The button types, one section each.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NopeSpace.l) {
                section("Tile") {
                    // Three across as in the Q panel, or one column at accessibility text sizes,
                    // where the camera shows Q as a list.
                    flow(sideBySide: true) {
                        Button {} label: { NopeTileLabel(name: Text(verbatim: "Grid"), value: Text(verbatim: "Off"), systemImage: "grid") }
                            .buttonStyle(NopeTileStyle(isOn: false))
                        Button {} label: { NopeTileLabel(name: Text(verbatim: "Grid"), value: Text(verbatim: "Thirds"), systemImage: "grid") }
                            .buttonStyle(NopeTileStyle(isOn: true))
                        Button {} label: { NopeTileLabel(name: Text(verbatim: "Close-Up"), value: Text(verbatim: "Off")) }
                            .buttonStyle(NopeTileStyle(isOn: false))
                            .disabled(true)
                    }
                    flow(sideBySide: true) {
                        readout(mode: "A", value: "ISO 100", isOpen: false)
                        readout(mode: "M", value: "1/250", isOpen: true)
                    }
                }
                section("Pill") {
                    flow {
                        Button {} label: { Label { Text(verbatim: "25%") } icon: { Image(systemName: "flashlight.on.fill") } }
                            .buttonStyle(NopePillStyle())
                        Button {} label: { Label { Text(verbatim: "Close-Up") } icon: { Image(systemName: "camera.macro") } }
                            .buttonStyle(NopePillStyle(isOnPicture: true))
                    }
                }
                section("Icon") {
                    HStack(spacing: NopeSize.targetGap) {
                        Button {} label: { Image(systemName: "arrow.triangle.2.circlepath.camera") }
                            .buttonStyle(NopeIconButtonStyle())
                            .accessibilityLabel(Text(verbatim: "Switch Camera"))
                        Button {} label: { Text(verbatim: "Q").font(NopeFont.q) }
                            .buttonStyle(NopeIconButtonStyle(size: NopeSize.quick))
                            .accessibilityLabel(Text(verbatim: "Quick Menu closed"))
                        Button {} label: { Text(verbatim: "Q").font(NopeFont.q) }
                            .buttonStyle(NopeIconButtonStyle(size: NopeSize.quick, isSelected: true))
                            .accessibilityLabel(Text(verbatim: "Quick Menu open"))
                        Button {} label: { Image(systemName: "plus") }
                            .buttonStyle(NopeIconButtonStyle())
                            .disabled(true)
                            .accessibilityLabel(Text(verbatim: "Increase, disabled"))
                    }
                }
                section("Capsule") {
                    flow {
                        Button {} label: { Label { Text(verbatim: "Auto") } icon: { Image(systemName: "slider.horizontal.3") } }
                            .buttonStyle(NopeCapsuleStyle())
                        Button {} label: { Label { Text(verbatim: "Manual") } icon: { Image(systemName: "slider.horizontal.3") } }
                            .buttonStyle(NopeCapsuleStyle(isSelected: true))
                        Button {} label: { Text(verbatim: "Interval Settings") }
                            .buttonStyle(NopeCapsuleStyle(isCompact: true))
                        Button {} label: { Text(verbatim: "Stop") }
                            .buttonStyle(NopeCapsuleStyle(role: .destructive))
                        Button {} label: { Text(verbatim: "Try Again (disabled)") }
                            .buttonStyle(NopeCapsuleStyle())
                            .disabled(true)
                        Button {} label: { Text(verbatim: "Settings") }
                            .buttonStyle(NopeCapsuleStyle(size: NopeSize.capsuleLarge, idleFill: .tile))
                    }
                }
                section("Drive words") {
                    flow {
                        ForEach(["Single", "Timer", "Burst", "Interval", "Astro"], id: \.self) { word in
                            Button {} label: { Text(verbatim: word) }
                                .buttonStyle(
                                    NopeCapsuleStyle(isSelected: word == "Timer", size: NopeSize.driveWord, idleFill: .none))
                        }
                    }
                }
                section("Lenses") {
                    HStack(spacing: NopeSpace.xxs) {
                        ForEach(["0.6×", "1×", "5×"], id: \.self) { lens in
                            Button {} label: { Text(verbatim: lens).font(NopeFont.lens).frame(minWidth: NopeSize.lensItemMinWidth) }
                                .buttonStyle(
                                    NopeCapsuleStyle(isSelected: lens == "1×", size: NopeSize.lensItem, isCompact: true))
                        }
                    }
                }
            }
            .padding(NopeSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(NopeColor.label)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .nightModeStyle(isNightMode)
    }

    /// One titled section.
    ///
    /// - Parameters:
    ///   - title: The section's title.
    ///   - content: The buttons.
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: NopeSpace.xs) {
            Text(verbatim: title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// Buttons side by side or stacked: side by side only when asked and below the accessibility
    /// text sizes.
    ///
    /// It doesn't use `ViewThatFits`: in the accessibility audit, a row that switched between its
    /// two forms while the audit enlarged the text was reported as "Dynamic Type font sizes are
    /// partially unsupported". A tile fills its width, so `ViewThatFits` also chose the row for
    /// tiles whose values then broke inside a word.
    ///
    /// - Parameters:
    ///   - sideBySide: Whether the buttons go side by side below accessibility text sizes.
    ///   - content: The buttons.
    @ViewBuilder private func flow(sideBySide: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        if sideBySide && !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: NopeSpace.xs, content: content)
        } else {
            VStack(alignment: .leading, spacing: NopeSpace.xs, content: content)
        }
    }

    /// A manual readout: the mode letter over the value.
    ///
    /// - Parameters:
    ///   - mode: "A" or "M".
    ///   - value: The value.
    ///   - isOpen: Whether its dial is open.
    private func readout(mode: String, value: String, isOpen: Bool) -> some View {
        Button {} label: { GalleryReadoutLabel(mode: mode, value: value) }
            .buttonStyle(NopeTileStyle(isOn: isOpen, minHeight: NopeSize.readout, alignment: .center))
    }
}

/// A sample manual readout's content in the gallery: the mode letter over the value.
struct GalleryReadoutLabel: View {
    /// "A" or "M".
    let mode: String

    /// The value.
    let value: String

    /// The color of the mode letter, set by the tile style.
    @Environment(\.nopeSecondaryLabel) private var secondaryLabel

    /// Creates the readout's content.
    ///
    /// - Parameters:
    ///   - mode: "A" or "M".
    ///   - value: The value.
    init(mode: String, value: String) {
        self.mode = mode
        self.value = value
    }

    /// The mode letter over the value.
    var body: some View {
        VStack(spacing: NopeSpace.xxs) {
            Text(verbatim: mode).font(NopeFont.readoutMode).foregroundStyle(secondaryLabel)
            Text(verbatim: value).font(NopeFont.tileName)
        }
    }
}
#endif
