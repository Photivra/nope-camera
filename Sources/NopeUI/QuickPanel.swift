import NopeCore
import SwiftUI

// Q, the quick menu (docs/design/BUILD-SPEC.md, 3.6; docs/design/ACCESSIBILITY.md, "Q").
//
// The camera layout owns the Q button and where the panel sits; this file draws what Q opens.
// The layout keeps one `Bool` for whether Q is open and passes it here as a binding:
//
// ```swift
// @State private var showsQuickMenu = false
// …
// if showsQuickMenu {
//     QuickPanel(context: context, isPresented: $showsQuickMenu, openSettings: openSettings)
// }
// ```
//
// In the scrolling layout (accessibility text sizes) the layout shows `QuickMenuList` instead,
// with the same arguments. The layout also closes Q on the shutter, a lens and a tap on the
// picture, by setting the binding to `false`.

/// Q's panel: every tile the camera offers now, in rows of up to three, then the foot with Hide
/// Controls and Settings.
///
/// It is drawn on the dark backing with large corners. It has no fixed height: when it would be
/// taller than the space it is given, it scrolls. Switches and menus leave it open; a button
/// tile (Exposure, Presets), Hide Controls and Settings close it. Escape, or the VoiceOver
/// escape gesture, closes it, and VoiceOver focus moves to the first tile when it opens.
struct QuickPanel: View {
    /// The tiles, in display order.
    let items: [QuickControlItem]

    /// Closes the panel.
    let close: () -> Void

    /// Turns on clean view.
    let hideControls: () -> Void

    /// Opens Settings.
    let openSettings: () -> Void

    /// The tile VoiceOver focuses, by identifier.
    @AccessibilityFocusState private var focusedTile: String?

    /// Creates the panel from its parts.
    ///
    /// - Parameters:
    ///   - items: The tiles, in display order.
    ///   - close: Closes the panel.
    ///   - hideControls: Turns on clean view.
    ///   - openSettings: Opens Settings.
    init(
        items: [QuickControlItem], close: @escaping () -> Void, hideControls: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.items = items
        self.close = close
        self.hideControls = hideControls
        self.openSettings = openSettings
    }

    /// Creates the panel for the camera: the tiles of ``QuickControls`` for the context, with
    /// Hide Controls sending clean view to its model.
    ///
    /// - Parameters:
    ///   - context: The model and settings.
    ///   - isPresented: Whether Q is open; the panel sets it to `false` to close.
    ///   - openSettings: Opens Settings.
    init(context: CameraControlContext, isPresented: Binding<Bool>, openSettings: @escaping () -> Void) {
        let hide = QuickControls.hideControls(context)
        self.init(
            items: QuickControls.current(context),
            close: { isPresented.wrappedValue = false },
            hideControls: {
                if case .button(let action) = hide.kind { action() }
            },
            openSettings: openSettings)
    }

    /// The panel, scrolling when it doesn't fit.
    var body: some View {
        // One scroll view, as tall as its content up to the space it is given, rather than a
        // choice between the content and a scroll view.
        HuggingHeight {
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.large))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(QuickControlsText.title)
        .accessibilityIdentifier("quickMenu")
        .accessibilityAction(.escape) { close() }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onAppear { focusedTile = items.first?.id }
    }

    /// The tiles and the foot.
    private var content: some View {
        VStack(spacing: NopeSpace.xs) {
            QuickTiles(items: items, close: close, focusedTile: $focusedTile)
            QuickPanelFoot(
                hideControls: {
                    close()
                    hideControls()
                },
                openSettings: {
                    close()
                    openSettings()
                })
        }
        .padding(NopeSpace.m)
    }
}

/// The tiles in rows of up to three (``QuickTileGrid``), each tile with its two hidden
/// measuring copies.
struct QuickTiles: View {
    /// The tiles, in display order.
    let items: [QuickControlItem]

    /// Closes the panel, after a button tile.
    let close: () -> Void

    /// The tile VoiceOver focuses, if the panel tracks it.
    let focusedTile: AccessibilityFocusState<String?>.Binding?

    /// The language, for whether a name may break between any two characters.
    @Environment(\.locale) private var locale

    /// Creates the tiles.
    ///
    /// - Parameters:
    ///   - items: The tiles, in display order.
    ///   - close: Closes the panel, after a button tile.
    ///   - focusedTile: The tile VoiceOver focuses, if the panel tracks it.
    init(items: [QuickControlItem], close: @escaping () -> Void, focusedTile: AccessibilityFocusState<String?>.Binding? = nil) {
        self.items = items
        self.close = close
        self.focusedTile = focusedTile
    }

    /// The tiles.
    var body: some View {
        QuickTileGrid(spacing: NopeSpace.xs, breaksAnywhere: QuickTileMetrics.breaksAnywhere(languageCode: locale.language.languageCode?.identifier)) {
            ForEach(items) { item in
                tile(item)
                // Measured by the grid, never shown: the name on one line and the value, at
                // the tile's fonts, so the grid can choose a column count at which no word breaks.
                item.title
                    .font(NopeFont.tileName)
                    .hidden()
                    .accessibilityHidden(true)
                (item.value ?? Text(verbatim: ""))
                    .font(NopeFont.tileValue)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
    }

    /// One tile, with VoiceOver focus tracked when the panel asks for it.
    ///
    /// - Parameter item: The tile's item.
    @ViewBuilder private func tile(_ item: QuickControlItem) -> some View {
        if let focusedTile {
            QuickTile(item: item, close: close)
                .accessibilityFocused(focusedTile, equals: item.id)
        } else {
            QuickTile(item: item, close: close)
        }
    }
}

/// One tile: a button, a switch or a menu, drawn with ``NopeTileStyle``.
///
/// VoiceOver reads the name, then the value ("Grid, Thirds"); a switch has the selected trait
/// while it is on. Voice Control uses the name.
struct QuickTile: View {
    /// The item.
    let item: QuickControlItem

    /// Closes the panel after a button's action.
    let close: () -> Void

    /// Creates a tile.
    ///
    /// - Parameters:
    ///   - item: The item.
    ///   - close: Closes the panel after a button's action.
    init(item: QuickControlItem, close: @escaping () -> Void) {
        self.item = item
        self.close = close
    }

    /// The control.
    var body: some View {
        control
            .accessibilityLabel(item.title)
            .accessibilityValue(item.value ?? Text(verbatim: ""))
            .accessibilityIdentifier("quick.\(item.id)")
    }

    /// The tile's control for its kind.
    @ViewBuilder private var control: some View {
        switch item.kind {
        case .button(let action):
            Button {
                close()
                action()
            } label: {
                QuickTileLabel(item: item)
            }
            .buttonStyle(NopeTileStyle(isOn: item.isOn))
        case .toggle(let isOn, let set):
            Button {
                set(!isOn)
            } label: {
                QuickTileLabel(item: item)
            }
            .buttonStyle(NopeTileStyle(isOn: item.isOn))
            .accessibilityAddTraits(isOn ? .isSelected : [])
        case .menu(let options):
            Menu {
                QuickMenuPicker(item: item, options: options)
            } label: {
                QuickTileLabel(item: item)
            }
            .buttonStyle(NopeTileStyle(isOn: item.isOn))
        }
    }
}

/// A menu item's values as a native picker, with a checkmark on the one in use.
struct QuickMenuPicker: View {
    /// The item, for the picker's name.
    let item: QuickControlItem

    /// The values.
    let options: [QuickControlItem.Option]

    /// Creates the picker.
    ///
    /// - Parameters:
    ///   - item: The item, for the picker's name.
    ///   - options: The values.
    init(item: QuickControlItem, options: [QuickControlItem.Option]) {
        self.item = item
        self.options = options
    }

    /// The picker.
    var body: some View {
        Picker(
            selection: Binding(
                get: { options.first(where: \.isSelected)?.id ?? "" },
                set: { id in options.first(where: { $0.id == id })?.select() })
        ) {
            ForEach(options) { option in option.title.tag(option.id) }
        } label: {
            item.title
        }
    }
}

/// A tile's content: the name on top, in the secondary color, wrapping onto more lines rather
/// than being cut; then the symbol and the value, on one line.
///
/// ``QuickTileGrid`` chooses a column count at which every word of every name and value fits, so
/// a word such as "Thirds" is never broken mid-word; names and values wrap between words.
struct QuickTileLabel: View {
    /// The item.
    let item: QuickControlItem

    /// Creates the view for an item.
    ///
    /// - Parameter item: The item.
    init(item: QuickControlItem) {
        self.item = item
    }

    /// The color of the name, set by the tile style for its state.
    @Environment(\.nopeSecondaryLabel) private var secondaryLabel

    /// The name over the value row.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
            item.title
                .font(NopeFont.tileName)
                .foregroundStyle(secondaryLabel)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            QuickTileValueRow(item: item)
        }
        // Fills the height the grid gives it, so every tile in a row is as tall as the tallest.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A tile's symbol and value: side by side when both fit on one line; otherwise the symbol
/// above the value, which then has the tile's whole width and wraps between its words ("None /
/// Saved"). ``QuickTileGrid`` keeps every word of the value within the tile, so a value is never
/// broken mid-word ("Stand / ard") or cut.
///
/// A `ViewThatFits` of the two arrangements made the accessibility audit report "Text clipped"
/// for the arrangement it didn't show; ``SymbolAndValueLayout`` measures instead.
struct QuickTileValueRow: View {
    /// The item.
    let item: QuickControlItem

    /// Creates the view for an item.
    ///
    /// - Parameter item: The item.
    init(item: QuickControlItem) {
        self.item = item
    }

    /// The symbol and the value.
    var body: some View {
        Group {
            if let value = item.value {
                SymbolAndValueLayout(spacing: NopeSpace.xxs) {
                    symbol
                    value
                        .multilineTextAlignment(.leading)
                }
            } else {
                symbol
            }
        }
        .font(NopeFont.tileValue)
    }

    /// The item's symbol, hidden from VoiceOver: the name says the same.
    private var symbol: some View {
        Image(systemName: item.systemImage)
            .accessibilityHidden(true)
    }
}

/// A symbol and a text: in a row, centered on each other, when both fit the width at their
/// natural sizes; otherwise the symbol above the text, which wraps at the full width.
struct SymbolAndValueLayout: Layout {
    /// The space between the symbol and the text.
    let spacing: CGFloat

    /// Creates the layout.
    ///
    /// - Parameter spacing: The space between the views, in points.
    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    /// Whether the two fit side by side.
    ///
    /// - Parameters:
    ///   - subviews: The symbol and the text.
    ///   - width: The width offered, or `nil` for any.
    /// - Returns: `true` when they fit in a row.
    private func fitsInARow(_ subviews: Subviews, width: CGFloat?) -> Bool {
        guard let width else { return true }
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        return widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0)) <= width
    }

    /// The size of the row, or of the symbol above the wrapped text.
    ///
    /// - Parameters:
    ///   - proposal: The proposed size.
    ///   - subviews: The symbol and the text.
    ///   - cache: Unused.
    /// - Returns: The size.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if fitsInARow(subviews, width: proposal.width) {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            return CGSize(
                width: sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0)),
                height: sizes.map(\.height).max() ?? 0)
        }
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        return CGSize(
            width: min(sizes.map(\.width).max() ?? 0, proposal.width ?? .infinity),
            height: sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0)))
    }

    /// Places the symbol and the text in a row from the leading edge, or one above the other.
    ///
    /// - Parameters:
    ///   - bounds: Where to place them.
    ///   - proposal: The proposed size.
    ///   - subviews: The symbol and the text.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if fitsInARow(subviews, width: bounds.width) {
            var x = bounds.minX
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            return
        }
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += size.height + spacing
        }
    }
}

/// The panel's foot: Hide Controls and Settings, side by side when both fit at their natural
/// widths, otherwise one above the other (``SideBySideOrStacked``).
struct QuickPanelFoot: View {
    /// Turns on clean view.
    let hideControls: () -> Void

    /// Opens Settings.
    let openSettings: () -> Void

    /// Creates the foot.
    ///
    /// - Parameters:
    ///   - hideControls: Turns on clean view.
    ///   - openSettings: Opens Settings.
    init(hideControls: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.hideControls = hideControls
        self.openSettings = openSettings
    }

    /// The two buttons.
    var body: some View {
        SideBySideOrStacked(spacing: NopeSpace.xs) {
            Button(action: hideControls) {
                Label { QuickControlsText.hideControls } icon: { Image(systemName: "eye.slash") }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("quick.hideControls")
            Button(action: openSettings) {
                Label { QuickControlsText.settings } icon: { Image(systemName: "gearshape") }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("quick.settings")
        }
        .buttonStyle(NopeCapsuleStyle(size: NopeSize.capsuleLarge, idleFill: .tile))
    }
}

/// Q as a full-height list, for the scrolling layout at accessibility text sizes: the title and
/// Done, then one row per tile, then Hide Controls and Settings. In this layout it is the only
/// way to Settings (docs/design/BUILD-SPEC.md, 3.12).
struct QuickMenuList: View {
    /// The tiles, in display order.
    let items: [QuickControlItem]

    /// Closes the list.
    let close: () -> Void

    /// Turns on clean view.
    let hideControls: () -> Void

    /// Opens Settings.
    let openSettings: () -> Void

    /// The row VoiceOver focuses, by identifier.
    @AccessibilityFocusState private var focusedRow: String?

    /// Creates the list from its parts.
    ///
    /// - Parameters:
    ///   - items: The tiles, in display order.
    ///   - close: Closes the list.
    ///   - hideControls: Turns on clean view.
    ///   - openSettings: Opens Settings.
    init(
        items: [QuickControlItem], close: @escaping () -> Void, hideControls: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.items = items
        self.close = close
        self.hideControls = hideControls
        self.openSettings = openSettings
    }

    /// Creates the list for the camera, as ``QuickPanel/init(context:isPresented:openSettings:)``.
    ///
    /// - Parameters:
    ///   - context: The model and settings.
    ///   - isPresented: Whether Q is open; the list sets it to `false` to close.
    ///   - openSettings: Opens Settings.
    init(context: CameraControlContext, isPresented: Binding<Bool>, openSettings: @escaping () -> Void) {
        let hide = QuickControls.hideControls(context)
        self.init(
            items: QuickControls.current(context),
            close: { isPresented.wrappedValue = false },
            hideControls: {
                if case .button(let action) = hide.kind { action() }
            },
            openSettings: openSettings)
    }

    /// The title bar over the rows.
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: NopeSpace.xs) {
                QuickControlsText.title
                    .font(.title2.weight(.bold))
                    .foregroundStyle(NopeColor.label)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: close) {
                    Label { QuickControlsText.done } icon: { Image(systemName: "checkmark") }
                        .labelStyle(.iconOnly)
                        // The 44-point button can't grow; its name is in the Large Content Viewer.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                .buttonStyle(NopeIconButtonStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityShowsLargeContentViewer()
                .accessibilityIdentifier("quick.done")
            }
            .padding(.horizontal, NopeSpace.m)
            .padding(.vertical, NopeSpace.xs)
            List {
                ForEach(items) { item in
                    row(QuickListRow(item: item, close: close), id: item.id)
                }
                row(
                    footRow(title: QuickControlsText.hideControls, systemImage: "eye.slash", id: "quick.hideControls") {
                        close()
                        hideControls()
                    }, id: "hideControls")
                row(
                    footRow(title: QuickControlsText.settings, systemImage: "gearshape", id: "quick.settings") {
                        close()
                        openSettings()
                    }, id: "settings")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(.black)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(QuickControlsText.title)
        .accessibilityIdentifier("quickMenu")
        .accessibilityAction(.escape) { close() }
        .onAppear { focusedRow = items.first?.id }
    }

    /// A row of the list, without the list's own background and separators.
    ///
    /// - Parameters:
    ///   - content: The row's control.
    ///   - id: The row's identifier, for VoiceOver focus.
    private func row(_ content: some View, id: String) -> some View {
        content
            .accessibilityFocused($focusedRow, equals: id)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: NopeSpace.xxs, leading: NopeSpace.m, bottom: NopeSpace.xxs, trailing: NopeSpace.m))
    }

    /// Hide Controls or Settings as a full-width row.
    ///
    /// - Parameters:
    ///   - title: The button's name.
    ///   - systemImage: Its symbol.
    ///   - id: Its accessibility identifier.
    ///   - action: What it does.
    private func footRow(title: Text, systemImage: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { title } icon: { Image(systemName: systemImage) }
                .font(.body.weight(.semibold))
        }
        .buttonStyle(NopeTileStyle(isOn: false))
        .accessibilityIdentifier(id)
    }
}

/// One row of ``QuickMenuList``: the tile's name over its value, full width, as a button, a
/// switch or a menu.
struct QuickListRow: View {
    /// The item.
    let item: QuickControlItem

    /// Closes the list after a button's action.
    let close: () -> Void

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - item: The item.
    ///   - close: Closes the list after a button's action.
    init(item: QuickControlItem, close: @escaping () -> Void) {
        self.item = item
        self.close = close
    }

    /// The row's control.
    var body: some View {
        control
            .accessibilityLabel(item.title)
            .accessibilityValue(item.value ?? Text(verbatim: ""))
            .accessibilityIdentifier("quick.\(item.id)")
    }

    /// The control for the item's kind.
    @ViewBuilder private var control: some View {
        switch item.kind {
        case .button(let action):
            Button {
                close()
                action()
            } label: {
                QuickListRowLabel(item: item)
            }
            .buttonStyle(NopeTileStyle(isOn: item.isOn))
        case .toggle(let isOn, let set):
            Button {
                set(!isOn)
            } label: {
                QuickListRowLabel(item: item)
            }
            .buttonStyle(NopeTileStyle(isOn: item.isOn))
            .accessibilityAddTraits(isOn ? .isSelected : [])
        case .menu(let options):
            Menu {
                QuickMenuPicker(item: item, options: options)
            } label: {
                QuickListRowLabel(item: item)
            }
            .buttonStyle(NopeTileStyle(isOn: item.isOn))
        }
    }
}

/// A list row's content: the name in the body style, the value under it in the secondary color.
struct QuickListRowLabel: View {
    /// The item.
    let item: QuickControlItem

    /// Creates the view for an item.
    ///
    /// - Parameter item: The item.
    init(item: QuickControlItem) {
        self.item = item
    }

    /// The color of the value, set by the tile style for its state.
    @Environment(\.nopeSecondaryLabel) private var secondaryLabel

    /// The name over the value.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
            item.title
                .font(.body.weight(.semibold))
            if let value = item.value {
                value
                    .font(.body)
                    .foregroundStyle(secondaryLabel)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Layout

/// The measurements behind the tile grid's column count, as plain functions, so they are tested
/// without drawing.
enum QuickTileMetrics {
    /// The most columns: three (docs/design/BUILD-SPEC.md, 3.6).
    static let maxColumns = 3

    /// The widest character as a share of a line's height: about 0.95 em for "W" in the system
    /// font, whose lines are about 1.2 em high. A word broken between characters fills its line
    /// to within one character; German and other languages also hyphenate, and a hyphenated
    /// line usually ends further from the edge, so the bound is kept as tight as it safely can
    /// be (a looser one stopped at a hyphenated "Kurze Verschluss-" and dropped to one column).
    /// Measured on the iOS 27.2 Simulator: "Kurze Verschlusszeit" at the largest standard size
    /// is 171 points on one line with lines 21.7 points high.
    static let widestCharacterPerLineHeight: CGFloat = 0.8

    /// The space a tile adds on each side of its content: ``NopeTileStyle`` pads the content by
    /// ``NopeSpace/s`` on the leading side and ``NopeSpace/xs`` on the trailing side.
    static let tileHorizontalPadding = NopeSpace.s + NopeSpace.xs

    /// Whether names in a language may break between any two characters, as Japanese and
    /// Chinese are written without spaces between words; Korean, like the other launch
    /// languages, breaks between words.
    ///
    /// - Parameter languageCode: The language's code, such as "ja", or `nil`.
    /// - Returns: `true` for Japanese and Chinese.
    static func breaksAnywhere(languageCode: String?) -> Bool {
        languageCode == "ja" || languageCode == "zh"
    }

    /// The narrowest width at which a text wraps only between words, found without knowing its
    /// words.
    ///
    /// Text that must wrap breaks between words while each word fits on a line, and in the
    /// middle of a word only when the word is wider than the line; a word broken that way fills
    /// its line to within a character of the width. So, from the one-line width, this asks for
    /// one point less each time and takes the width the text then lays out at; it stops at the
    /// last width before a layout filled its line to within `characterWidth`. A text whose
    /// lines happen to end that close to the edge stops early, which only asks for more room.
    ///
    /// - Parameters:
    ///   - singleLineWidth: The text's width on one line, in points.
    ///   - characterWidth: The widest a character can be, in points
    ///     (``widestCharacterPerLineHeight`` of the line height).
    ///   - laidOutWidth: The width the text takes when it is offered a width, in points.
    /// - Returns: The narrowest width without a word broken, in points.
    static func wordSafeWidth(
        singleLineWidth: CGFloat, characterWidth: CGFloat, laidOutWidth: (CGFloat) -> CGFloat
    ) -> CGFloat {
        var width = singleLineWidth.rounded(.up)
        // Each step makes the width at least a point narrower, so this ends; the bound only
        // guards against a measurement that doesn't follow the rule.
        for _ in 0..<64 {
            let offered = width - 1
            guard offered > characterWidth else { return width }
            let laidOut = laidOutWidth(offered)
            guard laidOut <= offered - characterWidth else { return width }
            width = laidOut.rounded(.up)
        }
        return width
    }

    /// The width of each column for a column count.
    ///
    /// - Parameters:
    ///   - columns: The number of columns, at least 1.
    ///   - width: The grid's width, in points.
    ///   - spacing: The space between columns, in points.
    /// - Returns: The column width, in points.
    static func columnWidth(columns: Int, width: CGFloat, spacing: CGFloat) -> CGFloat {
        let count = CGFloat(max(columns, 1))
        return max((width - spacing * (count - 1)) / count, 0)
    }

    /// The most columns, up to ``maxColumns``, at which every tile fits; one when even one
    /// column is too narrow.
    ///
    /// - Parameters:
    ///   - requiredWidths: Each tile's narrowest width, in points.
    ///   - width: The grid's width, in points.
    ///   - spacing: The space between columns, in points.
    /// - Returns: The column count.
    static func columnCount(requiredWidths: [CGFloat], width: CGFloat, spacing: CGFloat) -> Int {
        let widest = requiredWidths.max() ?? 0
        for columns in stride(from: maxColumns, to: 1, by: -1)
        where columnWidth(columns: columns, width: width, spacing: spacing) >= widest {
            return columns
        }
        return 1
    }

    /// The rows of a grid: the indexes of the tiles in each row, in reading order.
    ///
    /// - Parameters:
    ///   - count: The number of tiles.
    ///   - columns: The column count, at least 1.
    /// - Returns: The rows.
    static func rows(count: Int, columns: Int) -> [Range<Int>] {
        let columns = max(columns, 1)
        return stride(from: 0, to: count, by: columns).map { $0..<min($0 + columns, count) }
    }
}

/// The tiles in rows of equal columns, three when every tile fits, otherwise two or one.
///
/// Its subviews come in threes: each tile, then its name and its value, both hidden. A tile fits
/// a column when its name and its value each wrap there only between words (``QuickTileMetrics/wordSafeWidth(singleLineWidth:characterWidth:laidOutWidth:)``).
/// A `LazyVGrid` of flexible columns can't make that choice: its tiles fill whatever width they
/// get, so a long word was broken across lines instead ("Third / s"). Tiles in a row share the
/// tallest one's height. Right to left, SwiftUI mirrors the placement.
struct QuickTileGrid: Layout {
    /// The space between tiles, across and down.
    let spacing: CGFloat

    /// Whether names may break between any two characters (Japanese and Chinese).
    let breaksAnywhere: Bool

    /// Creates the grid.
    ///
    /// - Parameters:
    ///   - spacing: The space between tiles, across and down, in points.
    ///   - breaksAnywhere: Whether names may break between any two characters.
    init(spacing: CGFloat, breaksAnywhere: Bool) {
        self.spacing = spacing
        self.breaksAnywhere = breaksAnywhere
    }

    /// Each tile's narrowest width, worked out once per set of subviews.
    struct Cache {
        /// The narrowest width of each tile, in points, in order.
        var requiredWidths: [CGFloat]

        /// Creates the cache.
        ///
        /// - Parameter requiredWidths: The narrowest width of each tile, in points, in order.
        init(requiredWidths: [CGFloat]) {
            self.requiredWidths = requiredWidths
        }
    }

    /// Measures every tile's narrowest width.
    ///
    /// - Parameter subviews: The tiles and their measuring copies.
    /// - Returns: The cache.
    func makeCache(subviews: Subviews) -> Cache {
        Cache(requiredWidths: requiredWidths(subviews))
    }

    /// Measures again when the subviews change.
    ///
    /// - Parameters:
    ///   - cache: The cache.
    ///   - subviews: The tiles and their measuring copies.
    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.requiredWidths = requiredWidths(subviews)
    }

    /// The grid's size: as wide as offered (or three of the widest tile), as tall as its rows.
    ///
    /// - Parameters:
    ///   - proposal: The proposed size.
    ///   - subviews: The tiles and their measuring copies.
    ///   - cache: The tiles' narrowest widths.
    /// - Returns: The grid's size.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let tiles = tileViews(subviews)
        guard !tiles.isEmpty else { return .zero }
        let width = proposal.width ?? idealWidth(cache)
        let columns = QuickTileMetrics.columnCount(requiredWidths: cache.requiredWidths, width: width, spacing: spacing)
        let heights = rowHeights(tiles, columns: columns, width: width)
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0)))
    }

    /// Places the tiles row by row from the leading edge, and the measuring copies out of sight.
    ///
    /// - Parameters:
    ///   - bounds: Where to place the tiles.
    ///   - proposal: The proposed size.
    ///   - subviews: The tiles and their measuring copies.
    ///   - cache: The tiles' narrowest widths.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        // At their natural size, so nothing reads them as clipped text; they are hidden.
        for index in subviews.indices where index % 3 != 0 {
            subviews[index].place(at: bounds.origin, proposal: .unspecified)
        }
        let tiles = tileViews(subviews)
        let columns = QuickTileMetrics.columnCount(requiredWidths: cache.requiredWidths, width: bounds.width, spacing: spacing)
        let columnWidth = QuickTileMetrics.columnWidth(columns: columns, width: bounds.width, spacing: spacing)
        let rows = QuickTileMetrics.rows(count: tiles.count, columns: columns)
        let heights = rowHeights(tiles, columns: columns, width: bounds.width)
        var y = bounds.minY
        for (row, height) in zip(rows, heights) {
            for (column, index) in row.enumerated() {
                let x = bounds.minX + CGFloat(column) * (columnWidth + spacing)
                tiles[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: columnWidth, height: height))
            }
            y += height + spacing
        }
    }

    /// The tiles, without their measuring copies.
    ///
    /// - Parameter subviews: The tiles and their measuring copies.
    /// - Returns: Every third subview, from the first.
    private func tileViews(_ subviews: Subviews) -> [LayoutSubview] {
        stride(from: 0, to: subviews.count, by: 3).map { subviews[$0] }
    }

    /// The width that gives every tile its narrowest width in three columns.
    ///
    /// - Parameter cache: The tiles' narrowest widths.
    /// - Returns: The width, in points.
    private func idealWidth(_ cache: Cache) -> CGFloat {
        let columns = CGFloat(QuickTileMetrics.maxColumns)
        return (cache.requiredWidths.max() ?? 0) * columns + spacing * (columns - 1)
    }

    /// The height of each row: its tallest tile at the column width.
    ///
    /// - Parameters:
    ///   - tiles: The tiles.
    ///   - columns: The column count.
    ///   - width: The grid's width.
    /// - Returns: The rows' heights.
    private func rowHeights(_ tiles: [LayoutSubview], columns: Int, width: CGFloat) -> [CGFloat] {
        let columnWidth = QuickTileMetrics.columnWidth(columns: columns, width: width, spacing: spacing)
        return QuickTileMetrics.rows(count: tiles.count, columns: columns).map { row in
            row.map { tiles[$0].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
        }
    }

    /// The narrowest width at which a text wraps only between words or at the system's
    /// hyphenation points; in Japanese and Chinese, which may break anywhere, about one character.
    ///
    /// - Parameter text: The measuring copy of a name or value.
    /// - Returns: The width, in points.
    private func wordSafeWidth(_ text: LayoutSubview) -> CGFloat {
        let line = text.sizeThatFits(.unspecified)
        guard !breaksAnywhere else { return line.height }
        let characterWidth = line.height * QuickTileMetrics.widestCharacterPerLineHeight
        return QuickTileMetrics.wordSafeWidth(singleLineWidth: line.width, characterWidth: characterWidth) { offered in
            text.sizeThatFits(ProposedViewSize(width: offered, height: nil)).width
        }
    }

    /// Each tile's narrowest width: the word-safe width of its name or of its value, whichever is
    /// wider, plus the tile's padding, and never under the 44-point target. The symbol before
    /// the value isn't counted: the tile leaves it out where it doesn't fit.
    ///
    /// - Parameter subviews: The tiles and their measuring copies.
    /// - Returns: The widths, in tile order.
    private func requiredWidths(_ subviews: Subviews) -> [CGFloat] {
        stride(from: 0, to: subviews.count - 2, by: 3).map { index in
            let nameWidth = wordSafeWidth(subviews[index + 1])
            let valueWidth = wordSafeWidth(subviews[index + 2])
            return max(max(nameWidth, valueWidth) + QuickTileMetrics.tileHorizontalPadding, NopeSize.minTarget)
        }
    }
}

/// One view as tall as it would like to be, up to the height offered, such as a scroll view that
/// hugs short content and scrolls long content.
struct HuggingHeight: Layout {
    /// Creates the layout.
    init() {}

    /// The view's ideal height at the offered width, capped at the offered height.
    ///
    /// - Parameters:
    ///   - proposal: The proposed size.
    ///   - subviews: The one view.
    ///   - cache: Unused.
    /// - Returns: The size.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let ideal = view.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? ideal.width, height: min(ideal.height, proposal.height ?? ideal.height))
    }

    /// Gives the view the whole bounds.
    ///
    /// - Parameters:
    ///   - bounds: Where to place the view.
    ///   - proposal: The proposed size.
    ///   - subviews: The one view.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Two views side by side in equal halves when both fit there at their natural widths;
/// otherwise one above the other, each the full width. Unlike `ViewThatFits`, it measures the
/// views' content, so buttons that stretch to fill their space don't always count as fitting.
struct SideBySideOrStacked: Layout {
    /// The space between the two views.
    let spacing: CGFloat

    /// Creates the layout.
    ///
    /// - Parameter spacing: The space between the views, in points.
    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    /// Whether the views go side by side at a width.
    ///
    /// - Parameters:
    ///   - subviews: The views.
    ///   - width: The width offered.
    /// - Returns: `true` when each view's natural width fits half the width.
    private func isSideBySide(_ subviews: Subviews, width: CGFloat) -> Bool {
        let half = (width - spacing * CGFloat(max(subviews.count - 1, 0))) / CGFloat(max(subviews.count, 1))
        return subviews.allSatisfy { $0.sizeThatFits(.unspecified).width <= half }
    }

    /// The size: the width offered, or the natural widths side by side; the height of the
    /// taller view, or of both stacked.
    ///
    /// - Parameters:
    ///   - proposal: The proposed size.
    ///   - subviews: The views.
    ///   - cache: Unused.
    /// - Returns: The size.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let width = proposal.width ?? (subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0) * CGFloat(subviews.count) + gaps
        if isSideBySide(subviews, width: width) {
            let half = (width - gaps) / CGFloat(subviews.count)
            let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: half, height: nil)).height }.max() ?? 0
            return CGSize(width: width, height: height)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + gaps)
    }

    /// Places the views side by side from the leading edge, or one above the other.
    ///
    /// - Parameters:
    ///   - bounds: Where to place the views.
    ///   - proposal: The proposed size.
    ///   - subviews: The views.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let gaps = spacing * CGFloat(subviews.count - 1)
        if isSideBySide(subviews, width: bounds.width) {
            let half = (bounds.width - gaps) / CGFloat(subviews.count)
            let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: half, height: nil)).height }.max() ?? 0
            for (index, subview) in subviews.enumerated() {
                subview.place(
                    at: CGPoint(x: bounds.minX + CGFloat(index) * (half + spacing), y: bounds.minY),
                    proposal: ProposedViewSize(width: half, height: height))
            }
            return
        }
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }
}
