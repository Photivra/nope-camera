import NopeCore
import SwiftUI

/// The manual controls' readout row on the picture's lower edge, shown only while manual
/// controls are on (docs/design/BUILD-SPEC.md, 3.4): six readouts of equal width in a fixed
/// order (`ManualControl`), each with A or M over the value in use, then More (All Auto and Pro
/// Tools).
///
/// Pressing a readout opens its dial (``ControlDial``) above the row and fills the readout white;
/// pressing it again closes the dial. A control the lens can't set stays in its place. The camera
/// hides the row while a series runs, and at accessibility text sizes ``ManualControlsList``
/// replaces it. Every value and rule comes from `ManualControlsModel`.
///
/// VoiceOver reads the row as the container "Manual Controls"; each readout is adjustable
/// (docs/design/ACCESSIBILITY.md, row 8).
struct ManualReadoutRow: View {
    /// The camera model.
    let model: CameraModel

    /// The control whose dial is open, or `nil`.
    @Binding var openControl: ManualControl?

    /// Whether Pro Tools is shown; the camera screen presents it.
    @Binding var showsProTools: Bool

    /// Creates the readout row.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - openControl: The control whose dial is open.
    ///   - showsProTools: Whether Pro Tools is shown.
    init(model: CameraModel, openControl: Binding<ManualControl?>, showsProTools: Binding<Bool>) {
        self.model = model
        _openControl = openControl
        _showsProTools = showsProTools
    }

    /// The row, or two rows when the readouts don't fit side by side at an equal width (narrow
    /// screens, larger text, long values). Values never break inside a number.
    var body: some View {
        ReadoutRowLayout(spacing: NopeSpace.xxs) {
            readouts(ManualControl.allCases)
            optionsMenu
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Manual Controls", bundle: .module, comment: "Switch that shows manual exposure controls on the camera screen."))
    }

    /// The readouts of some controls.
    ///
    /// - Parameter controls: The controls, in order.
    private func readouts(_ controls: [ManualControl]) -> some View {
        ForEach(controls, id: \.self) { control in
            ControlReadout(model: model, control: control, isOpen: openControl == control) {
                openControl = openControl == control ? nil : control
            }
        }
    }

    /// More: "All Auto" and Pro Tools.
    private var optionsMenu: some View {
        ManualOptionsMenu(model: model, openControl: $openControl, showsProTools: $showsProTools)
    }
}

/// The readout row's arrangement: the readouts side by side, then More at
/// ``NopeSize/minTarget``, filling the width offered. The readouts share the width equally; a
/// readout whose value needs more than its share (its ideal width plus ``NopeSpace/xxs``) gets
/// what it needs and the others share the rest equally, as the design's flexible row does
/// (docs/design/screens/drive-astro: "ISO 3200" beside "1 s"). Only when the readouts' needs
/// don't fit together do they take two rows of four equal cells: the first four readouts, then
/// the rest and More.
///
/// A long value on its own, such as the highest ISO that Astro sets ("ISO 12,096"), so keeps the
/// one row on a 402-point iPhone: two rows pushed the Astro card up to a third of the picture,
/// against the quarter BUILD-SPEC.md, 3.5, allows.
///
/// It is a layout rather than `ViewThatFits` over an `HStack` and a `Grid`, so the readouts get
/// exactly equal widths whenever they fit, More keeps its own width, and one row is chosen
/// whenever the values fit (docs/design/screens/camera-manual, a 402-point iPhone).
struct ReadoutRowLayout: Layout {
    /// The space between views, in points.
    let spacing: CGFloat

    /// How many cells each of the two rows has.
    static let cellsPerRow = 4

    /// Creates the layout.
    ///
    /// - Parameter spacing: The space between views, in points.
    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    /// How the views are arranged at one width.
    struct Arrangement: Equatable {
        /// Whether everything is in one row.
        let isOneRow: Bool
        /// The width of a readout, in points: the equal share of the readouts that need no more
        /// than it, or the width of every cell in two rows.
        let cellWidth: CGFloat
        /// Each readout's width in one row, in points, in order; empty in two rows.
        let cellWidths: [CGFloat]
        /// The height of a row, in points.
        let rowHeight: CGFloat
        /// The whole size.
        let size: CGSize

        /// Creates an arrangement.
        ///
        /// - Parameters:
        ///   - isOneRow: Whether everything is in one row.
        ///   - cellWidth: The width of a readout, in points.
        ///   - cellWidths: Each readout's width in one row, in points; empty in two rows.
        ///   - rowHeight: The height of a row, in points.
        ///   - size: The whole size, in points.
        init(isOneRow: Bool, cellWidth: CGFloat, cellWidths: [CGFloat] = [], rowHeight: CGFloat, size: CGSize) {
            self.isOneRow = isOneRow
            self.cellWidth = cellWidth
            self.cellWidths = cellWidths
            self.rowHeight = rowHeight
            self.size = size
        }
    }

    /// The arrangement for some ideal sizes in a width.
    ///
    /// - Parameters:
    ///   - ideals: The views' ideal sizes; the last is More.
    ///   - width: The width offered, or `nil` for the ideal width.
    ///   - spacing: The space between views, in points.
    static func arrangement(ideals: [CGSize], width: CGFloat?, spacing: CGFloat) -> Arrangement {
        let readoutCount = max(ideals.count - 1, 0)
        let needs = ideals.dropLast().map { $0.width + NopeSpace.xxs }
        let widest = needs.max() ?? NopeSpace.xxs
        let rowHeight = ideals.map(\.height).max() ?? 0
        let fixedWidth = NopeSize.minTarget + spacing * CGFloat(readoutCount)
        let oneRowWidth = widest * CGFloat(readoutCount) + fixedWidth
        let available = width.flatMap { $0.isFinite ? $0 : nil } ?? oneRowWidth
        if needs.reduce(0, +) + fixedWidth <= available {
            let (share, widths) = sharedWidths(needs: needs, total: available - fixedWidth)
            return Arrangement(
                isOneRow: true, cellWidth: share, cellWidths: widths, rowHeight: rowHeight,
                size: CGSize(width: available, height: rowHeight))
        }
        let columns = CGFloat(cellsPerRow)
        let cell = max((available - spacing * (columns - 1)) / columns, widest)
        let totalWidth = cell * columns + spacing * (columns - 1)
        return Arrangement(
            isOneRow: false, cellWidth: cell, rowHeight: rowHeight,
            size: CGSize(width: totalWidth, height: rowHeight * 2 + spacing))
    }

    /// The readouts' widths in one row: an equal share of the total, except that a readout that
    /// needs more than the share gets what it needs and the others share the rest, repeated
    /// until every readout has at least what it needs.
    ///
    /// - Parameters:
    ///   - needs: Each readout's ideal width plus ``NopeSpace/xxs``, in points; their sum is at
    ///     most `total`.
    ///   - total: The width the readouts share, in points.
    /// - Returns: The share of the readouts that need no more than it, and every readout's width.
    static func sharedWidths(needs: [CGFloat], total: CGFloat) -> (share: CGFloat, widths: [CGFloat]) {
        var fixed = Set<Int>()
        var share = total / CGFloat(max(needs.count, 1))
        while true {
            let grown = needs.indices.filter { !fixed.contains($0) && needs[$0] > share }
            guard !grown.isEmpty else { break }
            fixed.formUnion(grown)
            let left = needs.count - fixed.count
            guard left > 0 else { break }
            share = (total - fixed.map { needs[$0] }.reduce(0, +)) / CGFloat(left)
        }
        let widths = needs.indices.map { fixed.contains($0) ? needs[$0] : share }
        return (share, widths)
    }

    /// The row's size for the width offered.
    ///
    /// - Parameters:
    ///   - proposal: The offered size.
    ///   - subviews: The readouts, then More.
    ///   - cache: Unused.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        return Self.arrangement(ideals: ideals, width: proposal.width, spacing: spacing).size
    }

    /// Places the readouts and More.
    ///
    /// - Parameters:
    ///   - bounds: The row's rectangle.
    ///   - proposal: The offered size.
    ///   - subviews: The readouts, then More.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let arrangement = Self.arrangement(ideals: ideals, width: bounds.width, spacing: spacing)
        var oneRowX = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let isMore = index == subviews.count - 1
            let column = arrangement.isOneRow ? index : index % Self.cellsPerRow
            let row = arrangement.isOneRow ? 0 : index / Self.cellsPerRow
            let width: CGFloat
            let x: CGFloat
            if arrangement.isOneRow {
                width = isMore ? NopeSize.minTarget : arrangement.cellWidths[index]
                x = oneRowX
                oneRowX += width + spacing
            } else {
                width = arrangement.cellWidth
                x = bounds.minX + CGFloat(column) * (arrangement.cellWidth + spacing)
            }
            let origin = CGPoint(x: x, y: bounds.minY + CGFloat(row) * (arrangement.rowHeight + spacing))
            subview.place(
                at: origin, anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: arrangement.rowHeight))
        }
    }
}

/// More, the last button of the readout row: "All Auto" and Pro Tools (exposure mode, metering,
/// the locks, bracketing and the live aids).
struct ManualOptionsMenu: View {
    /// The camera model.
    let model: CameraModel

    /// The control whose dial is open, or `nil`; "All Auto" closes it.
    @Binding var openControl: ManualControl?

    /// Whether Pro Tools is shown.
    @Binding var showsProTools: Bool

    /// Counts "All Auto" presses, to trigger the haptic.
    @State private var allAutoPresses = 0

    /// Creates the menu.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - openControl: The control whose dial is open.
    ///   - showsProTools: Whether Pro Tools is shown.
    init(model: CameraModel, openControl: Binding<ManualControl?>, showsProTools: Binding<Bool>) {
        self.model = model
        _openControl = openControl
        _showsProTools = showsProTools
    }

    /// The menu.
    var body: some View {
        Menu {
            Button {
                allAutoPresses += 1
                openControl = nil
                Task {
                    await model.send(.manual(.allAuto))
                    AccessibilityNotification.Announcement(
                        String(localized: "Full auto", bundle: .module, comment: "Announced after All Auto returned every control to automatic.")
                    ).post()
                }
            } label: {
                Label {
                    Text("All Auto", bundle: .module, comment: "Button that returns every manual control to automatic in one tap.")
                } icon: {
                    Image(systemName: "a.circle")
                }
            }
            .disabled(model.manual.settings.isAutomatic)
            Button {
                showsProTools = true
            } label: {
                Label {
                    Text("Pro Tools", bundle: .module, comment: "Button that opens metering, locks, bracketing and interval shooting.")
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        } label: {
            Label {
                Text("More Manual Controls", bundle: .module, comment: "VoiceOver and Voice Control name of the last button of the manual controls row: opens All Auto and Pro Tools.")
            } icon: {
                Image(systemName: "ellipsis")
                    .font(NopeFont.tileValue)
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(NopeTileStyle(isOn: false, minHeight: NopeSize.readout, alignment: .center))
        .sensoryFeedback(NopeHaptic.allAuto, trigger: allAutoPresses)
        .accessibilityShowsLargeContentViewer()
    }
}

/// One readout of the manual controls row: A or M over the value in use, in a tile
/// (``NopeTileStyle``) that is filled white while its dial is open.
///
/// For VoiceOver it is one adjustable element: swipe up or down steps the value without opening
/// the dial, double-tap opens its dial, and actions switch it between Auto and Manual or return
/// everything to Auto (AGENTS.md, "Manual controls are adjustable elements").
struct ControlReadout: View {
    /// The camera model.
    let model: CameraModel

    /// The control.
    let control: ManualControl

    /// Whether the control's dial is open.
    let isOpen: Bool

    /// Opens or closes the dial.
    let toggle: () -> Void

    /// Creates a readout.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - control: The control.
    ///   - isOpen: Whether its dial is open.
    ///   - toggle: Opens or closes the dial.
    init(model: CameraModel, control: ManualControl, isOpen: Bool, toggle: @escaping () -> Void) {
        self.model = model
        self.control = control
        self.isOpen = isOpen
        self.toggle = toggle
    }

    /// The manual controls model.
    private var manual: ManualControlsModel { model.manual }

    /// Whether the control is set manually.
    private var isManual: Bool { manual.settings.isManual(control) }

    /// The button.
    var body: some View {
        Button(action: toggle) {
            ReadoutLabel(isManual: isManual, value: visibleValue)
        }
        .buttonStyle(NopeTileStyle(isOn: isOpen, minHeight: NopeSize.readout, alignment: .center))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ControlText.name(control)))
        .accessibilityValue(Text(verbatim: SlotValue.spoken(for: control, in: manual)))
        .accessibilityAddTraits(isOpen ? [.isButton, .isSelected] : .isButton)
        .accessibilityAdjustableAction { direction in
            let steps = direction == .increment ? 1 : -1
            Task { await model.send(.manual(.step(control, by: steps))) }
        }
        .accessibilityAction(named: Text(verbatim: switchActionName)) {
            Task { await model.send(.manual(isManual ? .setAuto(control) : .step(control, by: 0))) }
        }
        .accessibilityActions {
            if !manual.settings.isAutomatic {
                Button {
                    Task { await model.send(.manual(.allAuto)) }
                } label: {
                    Text("All Auto", bundle: .module, comment: "Button that returns every manual control to automatic in one tap.")
                }
            }
        }
        .accessibilityInputLabels([Text(verbatim: ControlText.shortName(control)), Text(verbatim: ControlText.name(control))])
        // The readouts keep their size so six fit across the picture; the viewer shows them large.
        .accessibilityShowsLargeContentViewer {
            Text(verbatim: visibleValue)
        }
    }

    /// The readout's text: the value, with "ISO" before an ISO value, which is a bare number.
    private var visibleValue: String {
        let value = SlotValue.text(for: control, in: manual)
        return control == .iso ? "ISO " + value : value
    }

    /// "Switch to Auto" or "Switch to Manual".
    private var switchActionName: String {
        isManual
            ? String(localized: "Switch to Auto", bundle: .module, comment: "VoiceOver action that hands a control back to the camera.")
            : String(localized: "Switch to Manual", bundle: .module, comment: "VoiceOver action that fixes a control at its current value.")
    }
}

/// A readout's content: the mode letter over the value. "M" is drawn in a filled badge and "A"
/// plain, so the mode never depends on color alone; the letters are the same in every language,
/// as on a camera's readout.
struct ReadoutLabel: View {
    /// Whether the control is set manually.
    let isManual: Bool

    /// The value, such as "ISO 400" or "1/60".
    let value: String

    /// The color of the "A", set by the tile style for its state.
    @Environment(\.nopeSecondaryLabel) private var secondaryLabel

    /// Creates the content.
    ///
    /// - Parameters:
    ///   - isManual: Whether the control is set manually.
    ///   - value: The value.
    init(isManual: Bool, value: String) {
        self.isManual = isManual
        self.value = value
    }

    /// The letter over the value. Neither is truncated or broken inside a number: the row
    /// becomes two rows instead.
    var body: some View {
        VStack(spacing: NopeSpace.xxs) {
            if isManual {
                ManualBadge()
            } else {
                Text(verbatim: "A")
                    .font(NopeFont.readoutMode)
                    .foregroundStyle(secondaryLabel)
            }
            Text(verbatim: value)
                .font(NopeFont.tileName)
        }
        .fixedSize()
        // Six readouts and More fit across a 402-point picture only with less side padding than
        // a Q tile's (docs/design/screens/camera-manual): the label takes back the tile's
        // padding, and the row keeps a margin around the widest value (ReadoutRowLayout).
        .padding(.horizontal, -NopeSpace.xs)
    }
}

/// "M" in a badge of the label's color, with the letter cut out of it, so the tile's own fill
/// shows through: white on a dark tile, dark on the open (white) tile, and black on red in night
/// mode.
struct ManualBadge: View {
    /// Creates the badge. It holds no state.
    init() {}

    /// The badge.
    var body: some View {
        Text(verbatim: "M")
            .font(NopeFont.readoutMode)
            .padding(.horizontal, NopeSpace.xxs)
            .hidden()
            .background(Capsule().fill(.foreground))
            .overlay {
                Text(verbatim: "M")
                    .font(NopeFont.readoutMode)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
    }
}
/// The text a readout shows for a control, from the model.
@MainActor
enum SlotValue {
    /// The visible value: the value in use, "Fixed" values, or "n/a".
    ///
    /// - Parameters:
    ///   - control: The control.
    ///   - manual: The manual controls model.
    static func text(for control: ManualControl, in manual: ManualControlsModel) -> String {
        switch manual.availability(of: control) {
        case .unavailable:
            return String(localized: "n/a", bundle: .module, comment: "Short for not available: this lens can't set this control. Shown in a small grid slot.")
        case .fixed(let value):
            return ControlText.value(value, of: control)
        case .adjustable, .blockedByManualExposure:
            return manual.value(of: control).map { ControlText.value($0, of: control) } ?? "–"
        }
    }

    /// The VoiceOver value: "Manual, 200", "Auto, 1/500", "Fixed, f/1.78" or "Not available".
    ///
    /// - Parameters:
    ///   - control: The control.
    ///   - manual: The manual controls model.
    static func spoken(for control: ManualControl, in manual: ManualControlsModel) -> String {
        switch manual.availability(of: control) {
        case .unavailable:
            return String(localized: "Not available", bundle: .module, comment: "VoiceOver value of a control this lens can't set.")
        case .fixed(let value):
            let text = ControlText.value(value, of: control)
            return String(localized: "Fixed, \(text)", bundle: .module, comment: "VoiceOver value of a control the lens can't change, such as a fixed aperture. The value is for example f/1.78.")
        case .adjustable, .blockedByManualExposure:
            let mode = ControlText.mode(isManual: manual.settings.isManual(control))
            let text = text(for: control, in: manual)
            return String(
                localized: "Spoken control value", defaultValue: "\(mode), \(text)", bundle: .module,
                comment: "VoiceOver value of a manual control: Auto or Manual, then the value, for example Manual, 200.")
        }
    }
}
