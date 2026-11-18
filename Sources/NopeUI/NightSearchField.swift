import SwiftUI

/// The app's own search field, drawn in Night Mode in place of the system's
/// (`docs/design/night-search-field.md`; issues #88 and #98).
///
/// iOS draws the system search field as gray glass outside the app's views, where night mode's
/// red filter (``NightModeStyle``) can't reach it. This field is a plain text field inside the
/// app's views, so the filter covers it like every other row: a capsule at least
/// ``NopeSize/minTarget`` high, black, with a 1-point outline in the outline red at rest and a
/// 2-point outline in the full red and the cursor while it has focus. It draws in white and
/// grays, which the filter shows as reds; place it under ``NightModeStyle``.
///
/// It holds no search logic: it edits a text binding, and the screen that shows it decides what
/// the text finds. Outside Night Mode a screen keeps the system field (``NightSearchable``).
///
/// - Clear Text, a red disc with a black cross, shows while there is text; it empties the field
///   and keeps the keyboard.
/// - Cancel shows while the field has focus or holds text, beside the field, or under it at
///   accessibility text sizes; it empties the field and closes the keyboard. Escape on a
///   hardware keyboard and the VoiceOver escape gesture do the same.
/// - Return (the key reads Search) closes the keyboard and keeps the text.
/// - Autocorrection, suggestions and capitalization are off, so the system keyboard's bar,
///   which isn't red, holds less (decision 6). The keyboard itself is the system's dark one.
struct NightSearchField: View {
    /// The search text.
    @Binding var text: String

    /// The placeholder, "Search".
    let prompt: Text

    /// The field's VoiceOver and Voice Control name, such as "Search Settings".
    let accessibilityName: Text

    /// Whether the field has focus.
    @FocusState private var isFocused: Bool

    /// The text size: Cancel goes under the field at accessibility sizes.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Whether Increase Contrast is on: the outline at rest is the full red too.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the field.
    ///
    /// - Parameters:
    ///   - text: The search text.
    ///   - prompt: The placeholder.
    ///   - accessibilityName: The field's VoiceOver and Voice Control name.
    init(text: Binding<String>, prompt: Text, accessibilityName: Text) {
        _text = text
        self.prompt = prompt
        self.accessibilityName = accessibilityName
    }

    /// Whether Cancel shows: while searching.
    private var showsCancel: Bool {
        isFocused || !text.isEmpty
    }

    /// The field with Cancel beside or under it.
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: NopeSpace.xs) {
                    field
                    if showsCancel { cancelButton }
                }
            } else {
                HStack(spacing: NopeSpace.s) {
                    field
                    if showsCancel { cancelButton }
                }
            }
        }
        .animation(NopeMotion.fade, value: showsCancel)
        .animation(NopeMotion.fade, value: text.isEmpty)
        .padding(.horizontal, NopeSpace.m)
        .padding(.vertical, NopeSpace.xs)
        // Black behind it, so rows don't show through while the list scrolls under it.
        .background(NopeColor.nightBackground)
        .onKeyPress(.escape) {
            guard showsCancel else { return .ignored }
            cancel()
            return .handled
        }
    }

    /// The capsule: the magnifying glass, the text and Clear Text.
    private var field: some View {
        HStack(spacing: NopeSpace.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NopeColor.label)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: prompt.foregroundStyle(NopeColor.label)) {
                accessibilityName
            }
            .focused($isFocused)
            .foregroundStyle(NopeColor.label)
            .submitLabel(.search)
            .onSubmit { isFocused = false }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityLabel(accessibilityName)
            .accessibilityInputLabels([prompt, accessibilityName])
            .accessibilityAddTraits(.isSearchField)
            .accessibilityAction(.escape) { cancel() }
            .accessibilityIdentifier("nightSearchField")
            if !text.isEmpty {
                clearButton
                    .transition(.opacity)
            }
        }
        .font(.body)
        .padding(.leading, NopeSpace.m)
        .padding(.trailing, text.isEmpty ? NopeSpace.m : 0)
        .frame(maxWidth: .infinity, minHeight: NopeSize.minTarget)
        .background(NopeColor.nightBackground, in: Capsule())
        .overlay {
            // Inward, so the focus outline moves nothing.
            Capsule()
                .strokeBorder(outlineColor, lineWidth: isFocused ? NopeSize.focusOutline : NopeSize.outline)
        }
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
    }

    /// The outline: the full red (white before the filter) with focus or Increase Contrast,
    /// otherwise the outline red.
    private var outlineColor: Color {
        isFocused || contrast == .increased ? NopeColor.label : NopeColor.nightOutlineUnderMultiply
    }

    /// Clear Text: empties the field, and keeps the focus and the keyboard.
    private var clearButton: some View {
        Button {
            text = ""
            // The field keeps the focus, so the keyboard stays: set again after the tap, which
            // can end editing as the button goes away with the text.
            isFocused = true
            Task { @MainActor in isFocused = true }
        } label: {
            // A black cross on a disc in the full red.
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(NopeColor.selectedLabel, NopeColor.label)
                .frame(minWidth: NopeSize.minTarget, minHeight: NopeSize.minTarget)
                .contentShape(.rect)
        }
        .buttonStyle(NightSearchButtonStyle())
        .accessibilityLabel(Text("Clear text", bundle: .module, comment: "VoiceOver and Voice Control name of the button in the Night Mode search field that empties it. Use the name iOS gives the same button in its search fields."))
        .accessibilityIdentifier("nightSearchField.clear")
    }

    /// Cancel: empties the field and closes the keyboard.
    private var cancelButton: some View {
        Button(action: cancel) {
            Text("Cancel", bundle: .module, comment: "Button beside the Night Mode search field: ends the search and closes the keyboard. Use the word iOS shows beside its own search fields.")
                .font(.body)
                .foregroundStyle(NopeColor.label)
                .frame(minHeight: NopeSize.minTarget)
                .contentShape(.rect)
        }
        .buttonStyle(NightSearchButtonStyle())
        .accessibilityIdentifier("nightSearchField.cancel")
        .transition(.opacity)
    }

    /// Ends the search.
    private func cancel() {
        text = ""
        isFocused = false
    }
}

/// The press state of Clear Text and Cancel: 70% opacity, as every custom button
/// (``NopeMotion/pressedOpacity``).
struct NightSearchButtonStyle: ButtonStyle {
    /// Creates the style. It holds no state.
    init() {}

    /// The label, dimmed while pressed.
    ///
    /// - Parameter configuration: The button's label and state.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? NopeMotion.pressedOpacity : 1)
    }
}

/// A screen's search: the system field (`searchable`) outside Night Mode, and
/// ``NightSearchField`` under the navigation bar in it (issues #88 and #98). The text is the
/// same binding in both, so switching Night Mode keeps the search; the keyboard closes, because
/// the field that had focus goes away.
struct NightSearchable: ViewModifier {
    /// The search text.
    @Binding var text: String

    /// The night field's VoiceOver and Voice Control name.
    let accessibilityName: Text

    /// The system field's placement.
    let placement: SearchFieldPlacement

    /// Whether night mode is on.
    @Environment(\.isNightMode) private var isNightMode

    /// "Search": the night field's placeholder, and its name where the page's system field has
    /// no name of its own (Every Tag).
    static var prompt: Text {
        Text("Search", bundle: .module, comment: "Placeholder of the Night Mode search field, and its VoiceOver name on the Every Tag page. Use the word iOS shows in its own search fields.")
    }

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - text: The search text.
    ///   - accessibilityName: The night field's VoiceOver and Voice Control name.
    ///   - placement: The system field's placement.
    init(text: Binding<String>, accessibilityName: Text, placement: SearchFieldPlacement) {
        _text = text
        self.accessibilityName = accessibilityName
        self.placement = placement
    }

    /// The content with the field for the mode.
    ///
    /// - Parameter content: The screen's list.
    func body(content: Content) -> some View {
        if isNightMode {
            // Above the list, not in its safe area inset: an inset is hosted with the list, so
            // when the results replaced the list at the first letter, the field was built again
            // and the keyboard closed.
            VStack(spacing: 0) {
                NightSearchField(text: $text, prompt: Self.prompt, accessibilityName: accessibilityName)
                content
                    // Dragging the results closes the keyboard, as with the system field.
                    .scrollDismissesKeyboard(.interactively)
            }
        } else {
            content.searchable(text: $text, placement: placement)
        }
    }
}

extension View {
    /// Search with the system field, or with the red ``NightSearchField`` in Night Mode
    /// (``NightSearchable``).
    ///
    /// - Parameters:
    ///   - text: The search text.
    ///   - accessibilityName: The night field's VoiceOver and Voice Control name.
    ///   - placement: The system field's placement; automatic by default.
    func nightSearchable(
        text: Binding<String>, accessibilityName: Text, placement: SearchFieldPlacement = .automatic
    ) -> some View {
        modifier(NightSearchable(text: text, accessibilityName: accessibilityName, placement: placement))
    }
}
