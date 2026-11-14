import SwiftUI

/// The camera screen's colors and backings, one meaning each (issue #68, "Colors").
///
/// - Teal marks a verified fact only, such as the seal on a single-frame RAW.
/// - Amber marks a warning only, always with a symbol and words.
/// - A filled white capsule with bold text marks the selected item.
///
/// There is no yellow. Every state also has a symbol or words, so nothing depends on color
/// alone (AGENTS.md, "Vision settings").
enum CameraStyle {
    /// A verified fact, such as the seal on a single-frame RAW.
    static var fact: Color { .teal }

    /// A warning: something that changes what the photo is, or a failure.
    static var warning: Color { .orange }

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

    /// The opacity of the black over the material. Over a pure white frame the backing is at
    /// most a 25% gray, which white text passes against with a wide margin (WCAG 2.2, 1.4.3,
    /// 4.5:1). The camera screen is audited over a black viewfinder in the Simulator; the white
    /// and yellow frames are a device check (docs/TESTING.md).
    private static var dimming: Double { 0.75 }

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

    /// Whether the button is enabled.
    @Environment(\.isEnabled) private var isEnabled

    /// Creates the style.
    ///
    /// - Parameter isSelected: Whether the button shows the selected item.
    init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    /// The styled button.
    ///
    /// - Parameter configuration: The button's label and press state.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(isSelected ? .bold : .regular)
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .padding(.horizontal, 10)
            .frame(minWidth: CameraStyle.minimumTarget, minHeight: CameraStyle.minimumTarget)
            .background(isSelected ? Color.white : Color(white: 0.2), in: .capsule)
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
struct AdaptivePresentation<Presented: View>: ViewModifier {
    /// Whether the content is shown.
    @Binding var isPresented: Bool

    /// The presented content.
    let presented: () -> Presented

    /// The window's horizontal size class.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Attaches the popover or the sheet.
    ///
    /// - Parameter content: The presenting view.
    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content.popover(isPresented: $isPresented, content: presented)
        } else {
            content.sheet(isPresented: $isPresented, content: presented)
        }
    }
}

extension View {
    /// Presents content as a popover on iPad and as a sheet on iPhone.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the content is shown.
    ///   - content: The presented content.
    func adaptivePresentation<Presented: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Presented
    ) -> some View {
        modifier(AdaptivePresentation(isPresented: isPresented, presented: content))
    }
}
