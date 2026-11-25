import NopeCore
import SwiftUI

/// Details in This Photo (`docs/design/BUILD-SPEC.md`, 3.15, group 6): the location first, hidden
/// until the person asks; then In the Files (open), each optional detail the files hold with its
/// value; Left Out, with the reason beside each item; Always Saved, the locked items; and whether
/// the Standard File Tags were written.
///
/// Privacy: the location is an identifying value. It reads "Hidden" until Show Value, and what
/// was revealed lives in the sheet's state only, forgotten when it closes.
struct MetadataItemsSection: View {
    /// The details.
    let details: PhotoDetails

    /// The identifying values the person chose to see.
    @Binding var revealed: Set<String>

    /// Whether In the Files is open; it is at first.
    @State private var showsWritten = true

    /// The key of the location in ``revealed``.
    static let locationKey = "location"

    /// Creates the group.
    ///
    /// - Parameters:
    ///   - details: The details.
    ///   - revealed: The values the person chose to see.
    init(details: PhotoDetails, revealed: Binding<Set<String>>) {
        self.details = details
        self._revealed = revealed
    }

    /// The written items other than the location.
    private var written: [PhotoDetails.ItemReceipt] { details.writtenReceipts.filter { $0.item != .location } }

    /// The left-out items other than the location.
    private var leftOut: [PhotoDetails.ItemReceipt] { details.leftOutItems.filter { $0.item != .location } }

    /// The group.
    var body: some View {
        Section {
            if let location = details.location {
                locationRow(location)
            }
            DisclosureGroup(isExpanded: $showsWritten) {
                ForEach(written, id: \.item) { receipt in
                    DetailRow(title: Text(PrivacySettingsView.title(of: receipt.item)), value: Self.value(of: receipt))
                }
            } label: {
                CountLabel(title: Text("Photo details: In the Files", tableName: "Honesty", bundle: .module, comment: "Disclosure row in the photo details: the optional details the saved files hold, each with its value. Draft wording for the Honesty review."), count: written.count)
            }
            DisclosureGroup {
                ForEach(leftOut, id: \.item) { receipt in
                    DetailRow(title: Text(PrivacySettingsView.title(of: receipt.item)), value: PhotoDetailsSections.reason(receipt.state))
                }
            } label: {
                CountLabel(title: Text("Left Out", tableName: "Honesty", bundle: .module, comment: "Disclosure row in the photo details: the optional details the saved files don't hold, each with the reason. Draft wording for the Honesty review."), count: leftOut.count)
            }
            DisclosureGroup {
                ForEach(details.lockedItems, id: \.self) { item in
                    DetailRow(
                        title: Text(PrivacySettingsView.title(of: item)),
                        value: Text("Always kept", tableName: "Honesty", bundle: .module, comment: "In the photo details, next to a metadata item every file keeps because the photo can't be opened without it."))
                }
            } label: {
                CountLabel(title: Text("Always Saved", tableName: "Honesty", bundle: .module, comment: "Disclosure row in the photo details: the details every file keeps because the photo can't be opened without them. Draft wording for the Honesty review."), count: details.lockedItems.count)
            }
            DetailRow(
                title: Text("Standard File Tags", tableName: "Honesty", bundle: .module, comment: "Settings switch, on by default: whether files carry the tags the Exif standard requires that say nothing about the photo, the device or the person (version numbers and the color space)."),
                value: details.writesStandardFileTags
                    ? Self.inTheFiles
                    : PhotoDetailsSections.reason(.removed))
        } header: {
            Text("Details in This Photo", tableName: "Honesty", bundle: .module, comment: "Heading in the photo details: which metadata details the saved files hold and which they don't. Draft wording for the Honesty review.")
        } footer: {
            Text("To change what the next photos hold, open Details in Each Photo in Settings. The files of this photo stay as they are.", tableName: "Honesty", bundle: .module, comment: "Footer of Details in This Photo in the photo details. Details in Each Photo is the name of the Settings page. Draft wording for the Honesty review.")
        }
    }

    /// The location row, in its four states: off, on with nothing to write, in the files and
    /// hidden, in the files and shown.
    ///
    /// - Parameter location: What happened to the location.
    @ViewBuilder private func locationRow(_ location: PhotoDetails.ItemReceipt) -> some View {
        let title = Text(PrivacySettingsView.title(of: MetadataItem.location))
        switch location.state {
        case .written:
            HiddenValueRow(
                title: title, value: location.value.map(Self.text(of:)) ?? Self.inTheFiles,
                note: Self.inTheFiles, isHidden: location.value != nil && !revealed.contains(Self.locationKey),
                showLocation: true) { revealed.insert(Self.locationKey) }
        case .removed, .nothingToWrite:
            DetailRow(title: title, value: PhotoDetailsSections.reason(location.state), note: PhotoDetailsText.notInFiles)
        }
    }

    /// "In the files", for a detail the files hold.
    static var inTheFiles: Text {
        Text("In the files", tableName: "Honesty", bundle: .module, comment: "In the photo details: the saved files hold this detail. Draft wording for the Honesty review.")
    }

    /// A written item's value: its text, date or place, or what stands for it.
    ///
    /// - Parameter receipt: The written item.
    /// - Returns: The text.
    static func value(of receipt: PhotoDetails.ItemReceipt) -> Text {
        if let value = receipt.value { return text(of: value) }
        switch receipt.item {
        case .exposureSettings:
            return Text("Shown under Exposure", tableName: "Honesty", bundle: .module, comment: "In the photo details, the value of the Exposure Settings detail: its values are listed in the Exposure group. Draft wording for the Honesty review.")
        case .lensCorrections:
            return Text("Stored, not applied", tableName: "Honesty", bundle: .module, comment: "In the photo details: the RAW file holds lens correction instructions that editors can use, but nope. didn't apply them to the pixels.")
        default:
            return inTheFiles
        }
    }

    /// An item value as text: the text, the date and time, or the coordinates and altitude.
    ///
    /// - Parameter value: The value.
    /// - Returns: The text.
    static func text(of value: PhotoDetails.ItemValue) -> Text {
        switch value {
        case .text(let text):
            return Text(verbatim: text)
        case .date(let date):
            return Text(verbatim: date.formatted(date: .abbreviated, time: .standard))
        case .location(let place):
            let coordinates = [place.latitude, place.longitude]
                .map { $0.formatted(.number.precision(.fractionLength(0...4))) + "°" }
                .formatted(.list(type: .and, width: .narrow))
            guard let altitude = place.altitude else { return Text(verbatim: coordinates) }
            let height = Measurement(value: altitude, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
            return Text("\(coordinates), altitude \(height)", bundle: .module, comment: "In the photo details, the location the files hold, after Show Value: the latitude and longitude in degrees, then the altitude, such as 45.5231°, -122.6765°, altitude 312 m.")
        }
    }
}

/// A disclosure row's label: its title and, trailing, its count.
struct CountLabel: View {
    /// The title.
    let title: Text

    /// The count.
    let count: Int

    /// Creates the label.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - count: The count.
    init(title: Text, count: Int) {
        self.title = title
        self.count = count
    }

    /// The label, read as "Left Out, 5".
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
            Spacer(minLength: NopeSpace.xs)
            Text(verbatim: count.formatted())
                .foregroundStyle(CameraStyle.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row whose identifying value reads "Hidden" until the person taps Show Value, as in Compare.
struct HiddenValueRow: View {
    /// The title.
    let title: Text

    /// The value, shown once revealed.
    let value: Text

    /// A note under the value, or `nil`.
    let note: Text?

    /// Whether the value is hidden.
    let isHidden: Bool

    /// Whether the value is the location, so Voice Control also answers to "Show Location".
    let showLocation: Bool

    /// Shows the value.
    let reveal: () -> Void

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - title: The title.
    ///   - value: The value.
    ///   - note: A note under the value, or `nil`.
    ///   - isHidden: Whether the value is hidden.
    ///   - showLocation: Whether the value is the location.
    ///   - reveal: Shows the value.
    init(title: Text, value: Text, note: Text?, isHidden: Bool, showLocation: Bool = false, reveal: @escaping () -> Void) {
        self.title = title
        self.value = value
        self.note = note
        self.isHidden = isHidden
        self.showLocation = showLocation
        self.reveal = reveal
    }

    /// The row, then the Show Value button while hidden.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
            DetailRow(title: title, value: isHidden ? PhotoDetailsText.hidden : value, note: note)
                .accessibilityIdentifier("PhotoDetails.hiddenValue")
            if isHidden {
                Button(action: reveal) {
                    PhotoDetailsText.showValue
                }
                .buttonStyle(.borderless)
                .frame(minHeight: NopeSize.minTarget)
                .accessibilityLabel(Text("Show Value, \(title)", bundle: .module, comment: "VoiceOver label of a Show Value button in the photo details. The placeholder is the row's title, such as Location."))
                .accessibilityInputLabels(
                    showLocation
                        ? [PhotoDetailsText.showValue, Text("Show Location", bundle: .module, comment: "Voice Control name of the Show Value button of the location in the photo details.")]
                        : [PhotoDetailsText.showValue])
            }
        }
    }
}

extension PhotoDetailsText {
    /// "Hidden", for an identifying value not yet shown (the Compare string).
    static var hidden: Text {
        Text("Hidden", bundle: .module, comment: "Compare view: an identifying value, such as a unique photo ID, hidden until the person taps Show Value.")
    }

    /// "Show Value" (the Compare string).
    static var showValue: Text {
        Text("Show Value", bundle: .module, comment: "Button in the compare view: shows a hidden identifying value, such as a unique photo ID, on screen.")
    }
}
