import SwiftUI

/// The camera screen's colors and backings, one meaning each (issue #68, "Colors").
///
/// - Teal marks a verified fact only, such as the seal on a single-frame RAW.
/// - Amber marks a warning only, always with a symbol and words.
/// - A filled white capsule with bold text marks the selected item.
///
/// There is no yellow. Every state also has a symbol or words, so nothing depends on color
/// alone (AGENTS.md, "Vision settings"). In night mode both teal and amber become the night
/// red (``NightStyle``); the symbols and words still tell them apart.
enum CameraStyle {
    /// A verified fact, such as the seal on a single-frame RAW.
    static var fact: CameraColor { CameraColor(.teal) }

    /// A warning: something that changes what the photo is, or a failure.
    static var warning: CameraColor { CameraColor(.orange) }

    /// Secondary text, such as an explanation under a setting: the system's secondary style,
    /// and in night mode the full night red, because a dimmer red falls below 4.5:1 contrast.
    static var secondaryText: SecondaryText { SecondaryText() }

    /// The corner radius of chips, pills and banners, in points.
    static var cornerRadius: CGFloat { 10 }

    /// The minimum size of every touch target, in points (AGENTS.md, "Touch targets").
    static var minimumTarget: CGFloat { 44 }

    /// The space between neighboring touch targets, in points (issue #68, "Point budget").
    static var targetSpacing: CGFloat { 8 }
}

/// A dark backing for anything drawn over the picture: a system material darkened so text and
/// icons keep their contrast over a white or yellow scene, and solid black with Reduce
/// Transparency or Increase Contrast (issue #68, "Contrast").
struct DarkBacking<S: Shape>: ViewModifier {
    /// The backing's shape.
    let shape: S

    /// Whether Reduce Transparency is on.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Whether Increase Contrast is on.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the backing.
    ///
    /// - Parameter shape: The backing's shape.
    init(shape: S) {
        self.shape = shape
    }

    /// The opacity of the black over the material. The iPad accessibility audit reported text
    /// on a 75% backing as low contrast, so it is 90%. Over a pure white frame the backing is at
    /// most a 10% gray, which white text passes against with a wide margin (WCAG 2.2, 1.4.3,
    /// 4.5:1). The camera screen is audited over a black viewfinder in the Simulator; the white
    /// and yellow frames are a device check (docs/TESTING.md).
    private static var dimming: Double { 0.9 }

    /// Puts the backing behind the content.
    ///
    /// - Parameter content: The content.
    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency || contrast == .increased {
                shape.fill(.black)
            } else {
                shape.fill(.ultraThinMaterial).overlay(shape.fill(.black.opacity(Self.dimming)))
            }
        }
    }
}

extension View {
    /// Puts a dark backing behind a control drawn over the picture.
    ///
    /// - Parameter shape: The backing's shape; a rounded rectangle by default.
    func darkBacking<S: Shape>(_ shape: S) -> some View {
        modifier(DarkBacking(shape: shape))
    }

    /// Puts a rounded dark backing behind a control drawn over the picture.
    func darkBacking() -> some View {
        modifier(DarkBacking(shape: RoundedRectangle(cornerRadius: CameraStyle.cornerRadius)))
    }
}

/// A capsule button that is filled white with bold black text when selected, and plain white on
/// a dark fill otherwise, as the camera's lens and readout buttons are (issue #68, "Colors").
struct SelectableCapsuleStyle: ButtonStyle {
    /// Whether the button shows the selected item.
    let isSelected: Bool

    /// The space on each side of the label, in points.
    let horizontalPadding: CGFloat

    /// Whether the button is enabled.
    @Environment(\.isEnabled) private var isEnabled

    /// Whether night mode is on: the dark fill is darker there, because night mode's red
    /// multiply turns white text on the 20% gray into red on dark red at only about 4.6:1, which
    /// the audit reported for small readout text; on an 8% gray it is about 5.2:1.
    @Environment(\.isNightMode) private var isNightMode

    /// Creates the style.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the button shows the selected item.
    ///   - horizontalPadding: The space on each side of the label, in points; smaller for the
    ///     manual readouts, so seven fit in a row.
    init(isSelected: Bool, horizontalPadding: CGFloat = 10) {
        self.isSelected = isSelected
        self.horizontalPadding = horizontalPadding
    }

    /// The styled button.
    ///
    /// - Parameter configuration: The button's label and press state.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(isSelected ? .bold : .regular)
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: CameraStyle.minimumTarget, minHeight: CameraStyle.minimumTarget)
            .background(isSelected ? Color.white : Color(white: isNightMode ? 0.08 : 0.2), in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.5))
            .contentShape(.capsule)
            .contentShape(.hoverEffect, .capsule)
            .hoverEffect(.highlight)
    }
}

/// Presents content as a popover in a regular-width window (iPad) and as a sheet otherwise
/// (iPhone), as issue #68 asks ("popovers instead of sheets" on iPad). On iPhone it is a real
/// sheet rather than a popover adapted to one: in the adapted form the accessibility audit
/// reported form headers and footers as not following Dynamic Type.
///
/// With `prefersSheet` (night mode) it is a sheet on iPad too: the iPad popover is translucent
/// glass whatever its presentation background, so the picture and the system's colors showed
/// through night mode's red on black. The style is chosen when the content opens and kept
/// while it is open, so turning night mode on or off inside it doesn't close it.
struct AdaptivePresentation<Presented: View>: ViewModifier {
    /// How the content is shown.
    enum Style {
        /// A popover (iPad).
        case popover
        /// A sheet.
        case sheet
    }

    /// Whether the content is shown.
    @Binding var isPresented: Bool

    /// Whether a sheet is wanted in a regular-width window too.
    let prefersSheet: Bool

    /// The presented content.
    let presented: () -> Presented

    /// The window's horizontal size class.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The style chosen when the content opened, or `nil` while it is closed.
    @State private var openStyle: Style?

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the content is shown.
    ///   - prefersSheet: Whether a sheet is wanted in a regular-width window too.
    ///   - presented: The presented content.
    init(isPresented: Binding<Bool>, prefersSheet: Bool, presented: @escaping () -> Presented) {
        _isPresented = isPresented
        self.prefersSheet = prefersSheet
        self.presented = presented
    }

    /// The style for the current window and preference.
    private var currentStyle: Style {
        horizontalSizeClass == .regular && !prefersSheet ? .popover : .sheet
    }

    /// Attaches the popover and the sheet; only the chosen one is ever shown.
    ///
    /// - Parameter content: The presenting view.
    func body(content: Content) -> some View {
        content
            // A popover keeps the appearance it opened with (ScreenAppearanceModifier).
            .popover(isPresented: shown(as: .popover)) { presented().environment(\.isPresentedInPopover, true) }
            .sheet(isPresented: shown(as: .sheet), content: presented)
            .onChange(of: isPresented, initial: true) { _, isOpen in openStyle = isOpen ? currentStyle : nil }
    }

    /// Whether the content is shown in the style.
    ///
    /// - Parameter style: A style.
    /// - Returns: A binding that is `true` while the content is shown in that style.
    private func shown(as style: Style) -> Binding<Bool> {
        Binding {
            isPresented && (openStyle ?? currentStyle) == style
        } set: { isOpen in
            if !isOpen { isPresented = false }
        }
    }
}

extension View {
    /// Presents content as a popover on iPad and as a sheet on iPhone, or as a sheet on both
    /// with `prefersSheet`.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the content is shown.
    ///   - prefersSheet: Whether a sheet is wanted on iPad too, as in night mode.
    ///   - content: The presented content.
    func adaptivePresentation<Presented: View>(
        isPresented: Binding<Bool>, prefersSheet: Bool = false, @ViewBuilder content: @escaping () -> Presented
    ) -> some View {
        modifier(AdaptivePresentation(isPresented: isPresented, prefersSheet: prefersSheet, presented: content))
    }
}

extension View {
    /// Turns off the soft fade iOS 26 draws where scrolling content meets the screen's edges, so
    /// text scrolled under the status bar keeps its contrast (the iPad audit reported faded text
    /// at the top of the scrolling camera layout). Earlier versions have no such effect.
    @ViewBuilder func hardScrollEdges() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.hard, for: .all)
        } else {
            self
        }
    }
}

/// A camera color that becomes night mode's red (issue #61): teal and amber have too little red
/// to show after ``NightModeStyle`` keeps only the red channel, so in night mode they resolve
/// to white, which turns into the full night red.
struct CameraColor: ShapeStyle {
    /// The color outside night mode.
    let color: Color

    /// Creates a camera color.
    ///
    /// - Parameter color: The color outside night mode.
    init(_ color: Color) {
        self.color = color
    }

    /// The color for the environment: white in night mode (shown as red), otherwise ``color``.
    ///
    /// - Parameter environment: The view's environment.
    func resolve(in environment: EnvironmentValues) -> Color {
        environment.isNightMode ? .white : color
    }
}

/// Night mode's look (issue #61): red on black, with no white, blue or yellow light, to keep
/// eyes used to the dark.
///
/// ``NightModeStyle`` multiplies everything the app draws by pure red, so white becomes red,
/// grays become darker reds and black stays black. Pure sRGB red on black has a contrast of
/// 5.25:1 (WCAG 2.2 relative luminance 0.2126), above the 4.5:1 text minimum, so every text
/// style is drawn at the full red: secondary and tertiary text are drawn like primary text,
/// because a dimmer red would fall below 4.5:1.
///
/// The app never changes the screen's brightness; people dim it with the device's own controls.
enum NightStyle {
    /// The one color of night mode: pure sRGB red.
    static var red: Color { Color(.sRGB, red: 1, green: 0, blue: 0) }

    /// The tint of system controls in night mode, before the multiply: white, shown as the full
    /// night red. Tinted text and icons (a back button, a picker's checkmark, a button in a list)
    /// need it: a mid gray showed as about `#800000`, under 2:1 against black and the dark red
    /// rows, below WCAG 2.2's 3:1 for icons (1.4.11) and 4.5:1 for text (1.4.3).
    static var controlTint: Color { .white }

    /// The tint of a switch's track and a slider's filled track in night mode, before the
    /// multiply: a dark gray, shown as a dark red, so the knob or thumb (white, shown as the full
    /// red) stands out from the track by at least 3:1 (WCAG 2.2, 1.4.11). Applied by
    /// ``NightModeSwitchStyle`` and `nightModeTrackTint()`.
    static var trackTint: Color { Color(white: 0.3) }
}

/// The system switch, with ``NightStyle/trackTint`` on its track in night mode, so its knob
/// stays distinct from the track while other tinted controls use the full night red. Outside
/// night mode it is the system's switch, unchanged. ``NightModeStyle`` applies it; a toggle
/// with its own style keeps that style.
struct NightModeSwitchStyle: ToggleStyle {
    /// Creates the style. It holds no state.
    init() {}

    /// The toggle, drawn by the system.
    ///
    /// - Parameter configuration: The toggle's label and state.
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .nightModeTrackTint()
    }
}

/// Puts ``NightStyle/trackTint`` on a control's track in night mode.
struct NightModeTrackTint: ViewModifier {
    /// Whether night mode is on.
    @Environment(\.isNightMode) private var isNightMode

    /// Creates the modifier. It holds no state.
    init() {}

    /// The control, with the track tint in night mode.
    ///
    /// - Parameter content: The control.
    func body(content: Content) -> some View {
        content.tint(isNightMode ? NightStyle.trackTint : nil)
    }
}

extension View {
    /// Draws a switch's or slider's filled track in night mode's dark red
    /// (``NightStyle/trackTint``), so its knob or thumb stays visible on it.
    func nightModeTrackTint() -> some View {
        modifier(NightModeTrackTint())
    }
}

extension EnvironmentValues {
    /// Whether night mode is on, for views that need a different color in it
    /// (``CameraColor``). Set by ``NightModeStyle``.
    @Entry var isNightMode = false
}

/// Draws a view in night mode's red on black when night mode is on, and leaves it unchanged
/// otherwise (issue #61).
///
/// The view's structure stays the same in both modes, so switching keeps each view's state.
/// System menus, alerts and the keyboard are drawn by the system outside the app's views and keep
/// the dark appearance night mode asks for; the system's Color Filters (red tint) cover them too.
struct NightModeStyle: ViewModifier {
    /// Whether night mode is on.
    let isOn: Bool

    /// Creates the style.
    ///
    /// - Parameter isOn: Whether night mode is on.
    init(isOn: Bool) {
        self.isOn = isOn
    }

    /// The view, in red on black when night mode is on.
    ///
    /// - Parameter content: The view.
    func body(content: Content) -> some View {
        content
            // The secondary level, used by section headers among others, is the darker gray of
            // ``SecondaryText`` in the light appearance: the system's lighter gray failed the
            // contrast audit there (the Live Aids header at the largest text size).
            .foregroundStyle(
                isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary),
                isOn ? AnyShapeStyle(.white) : AnyShapeStyle(SecondaryText()),
                isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
            .tint(isOn ? NightStyle.controlTint : nil)
            .toggleStyle(NightModeSwitchStyle())
            .environment(\.isNightMode, isOn)
            .colorMultiply(isOn ? NightStyle.red : .white)
    }
}

extension View {
    /// Draws the view in night mode's red on black while `isOn` is `true`.
    ///
    /// - Parameter isOn: Whether night mode is on.
    func nightModeStyle(_ isOn: Bool) -> some View {
        modifier(NightModeStyle(isOn: isOn))
    }
}

/// The style of secondary text: `.secondary` in the dark appearance, a darker gray in the light
/// one, and white in night mode (shown as the full night red by ``NightModeStyle``). See
/// ``CameraStyle/secondaryText``.
///
/// In the light appearance the accessibility audit reported footnote-sized explanations in the
/// system's secondary gray as low contrast ("Contrast nearly passed") on Settings' white rows, so
/// light uses ``lightGray``, as the design does (docs/design/settings.html).
struct SecondaryText: ShapeStyle {
    /// Secondary text in the light appearance: 5.2:1 on white and 4.8:1 on the grouped
    /// background (#F2F2F7), above WCAG 2.2's 4.5:1 for body text.
    static let lightGray = Color(red: 0x6D / 255, green: 0x6D / 255, blue: 0x72 / 255)

    /// Creates the style. It holds no state.
    init() {}

    /// The style for the environment.
    ///
    /// - Parameter environment: The view's environment.
    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        if environment.isNightMode { return AnyShapeStyle(Color.white) }
        return environment.colorScheme == .light ? AnyShapeStyle(Self.lightGray) : AnyShapeStyle(.secondary)
    }
}
