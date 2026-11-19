import SwiftUI

/// A system `Form` whose rows and page keep their night mode contrast: unchanged outside night
/// mode; in night mode the rows are ``NopeColor/nightRowUnderMultiply`` (shown as `#1C0000`) on a
/// black page (``NightModeRows``).
///
/// Use it in place of `Form` for every settings page and sheet, so all of them look the same in
/// night mode.
struct NopeForm<Content: View>: View {
    /// The form's sections and rows.
    private let content: Content

    /// Creates the form.
    ///
    /// - Parameter content: The form's sections and rows.
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// The system form, with the night mode rows.
    var body: some View {
        Form {
            Group { content }
                .modifier(NightModeRowBackground())
        }
        .modifier(NightModeRows())
    }
}

/// A system `List` whose rows and page keep their night mode contrast, as ``NopeForm`` does.
struct NopeList<Content: View>: View {
    /// The list's sections and rows.
    private let content: Content

    /// Creates the list.
    ///
    /// - Parameter content: The list's sections and rows.
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// The system list, with the night mode rows.
    var body: some View {
        List {
            Group { content }
                .modifier(NightModeRowBackground())
        }
        .modifier(NightModeRows())
    }
}

/// Puts ``NopeColor/nightRowUnderMultiply`` behind each row in night mode, and leaves the
/// system's row background outside it. Applied to the sections and rows of ``NopeForm`` and
/// ``NopeList``.
///
/// In a sheet the system draws grouped rows in its elevated dark gray, `#2C2C2E`, which night
/// mode's multiply by red (``NightModeStyle``) turns into `#2C0000`. The night red is only
/// 4.74:1 on that, close to WCAG 2.2's 4.5:1 for text (1.4.3), and the iOS 26.5 accessibility
/// audit reported it as "Contrast nearly passed". On `#1C0000` the night red is 5.0:1.
struct NightModeRowBackground: ViewModifier {
    /// Whether night mode is on.
    @Environment(\.isNightMode) private var isNightMode

    /// Creates the modifier. It holds no state.
    init() {}

    /// The rows, with the night row background in night mode.
    ///
    /// - Parameter content: The sections and rows.
    func body(content: Content) -> some View {
        content.listRowBackground(isNightMode ? NopeColor.nightRowUnderMultiply : nil)
    }
}

/// In night mode, draws a form's or list's page in black (``NopeColor/nightBackground``) behind
/// its rows, as the dark appearance outside a sheet does (`#000000` page, `#1C1C1E` rows), so the
/// darker rows of ``NightModeRowBackground`` still stand apart from the page. Outside night mode
/// the system's page is unchanged.
struct NightModeRows: ViewModifier {
    /// Whether night mode is on.
    @Environment(\.isNightMode) private var isNightMode

    /// Creates the modifier. It holds no state.
    init() {}

    /// The form or list, on a black page in night mode.
    ///
    /// - Parameter content: The form or list.
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(isNightMode ? .hidden : .automatic)
            .background(isNightMode ? NopeColor.nightBackground : Color.clear)
    }
}
