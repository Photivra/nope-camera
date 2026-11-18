import NopeCore
import SwiftUI

/// Every Tag (`docs/design/BUILD-SPEC.md`, 3.15, group 8): one row for each file with how many
/// tags, blocks and properties it holds, each opening that file's page.
struct EveryTagSection: View {
    /// The details.
    let details: PhotoDetails

    /// The identifying values the person chose to see.
    @Binding var revealed: Set<String>

    /// Creates the group.
    ///
    /// - Parameters:
    ///   - details: The details.
    ///   - revealed: The values the person chose to see.
    init(details: PhotoDetails, revealed: Binding<Set<String>>) {
        self.details = details
        self._revealed = revealed
    }

    /// The group.
    var body: some View {
        Section {
            ForEach(Array(details.files.enumerated()), id: \.offset) { index, file in
                NavigationLink {
                    EveryTagPage(file: file, key: "tags:\(index)", revealed: $revealed)
                } label: {
                    CountLabel(title: Text(verbatim: FormatsSettingsView.name(of: file.format)), count: file.entries.count)
                }
                .accessibilityInputLabels([Text(verbatim: FormatsSettingsView.name(of: file.format)), Text(verbatim: file.format.rawValue.uppercased())])
            }
        } header: {
            Text("Every Tag", bundle: .module, comment: "Heading in the photo details: every metadata tag, block and property of each saved file.")
        } footer: {
            Text("Every tag, block and property nope. read back from each file before saving it, with its value.", tableName: "Honesty", bundle: .module, comment: "Footer of Every Tag in the photo details. Keep nope. unchanged. Draft wording for the Honesty review.")
        }
    }
}

/// One file's tags, blocks and properties, grouped by where they live in the file, each group
/// closed at first, with search by name. Identifying values read "Hidden" until Show Hidden
/// Values in their group.
struct EveryTagPage: View {
    /// The file.
    let file: PhotoDetails.File

    /// The prefix of this page's keys in ``revealed``.
    let key: String

    /// The identifying values the person chose to see.
    @Binding var revealed: Set<String>

    /// The groups the person opened.
    @State private var opened: Set<PhotoDetails.TagEntry.Place> = []

    /// The search text.
    @State private var query = ""

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - key: The prefix of this page's keys in `revealed`.
    ///   - revealed: The values the person chose to see.
    init(file: PhotoDetails.File, key: String, revealed: Binding<Set<String>>) {
        self.file = file
        self.key = key
        self._revealed = revealed
    }

    /// The page.
    var body: some View {
        List {
            Section {
                Text("\(file.entries.count) tags, blocks and properties in this file, as nope. read them back before saving it. Names are the standards' own.", tableName: "Honesty", bundle: .module, comment: "Top of a file's Every Tag page in the photo details: how many metadata items the file holds. Tag, block and property names are not translated. Keep nope. unchanged. Draft wording for the Honesty review.")
                    .font(.footnote)
                    .foregroundStyle(CameraStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(file.places, id: \.self) { place in
                let entries = Self.matching(file.entries(in: place), query: query)
                if !entries.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: expansion(of: place)) {
                            let groupKey = "\(key):\(place)"
                            let isHidden = !revealed.contains(groupKey)
                            if isHidden && entries.contains(where: \.hidesValue) {
                                Button {
                                    revealed.insert(groupKey)
                                    AccessibilityNotification.Announcement(
                                        String(localized: "Values shown.", bundle: .module, comment: "VoiceOver announcement after Show Hidden Values on the Every Tag page: the hidden values of the group are now shown.")
                                    ).post()
                                } label: {
                                    Text("Show Hidden Values", bundle: .module, comment: "Button at the top of a group on the Every Tag page of the photo details: shows the group's identifying values, such as the location, until the sheet closes.")
                                }
                                .frame(minHeight: NopeSize.minTarget)
                            }
                            ForEach(entries) { entry in
                                TagRow(entry: entry, isHidden: isHidden && entry.hidesValue)
                            }
                        } label: {
                            CountLabel(title: Self.name(of: place), count: entries.count)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle(Text(verbatim: FormatsSettingsView.name(of: file.format)))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Whether a group is open: opened by the person, or holding a match while searching.
    ///
    /// - Parameter place: The group.
    /// - Returns: The binding.
    private func expansion(of place: PhotoDetails.TagEntry.Place) -> Binding<Bool> {
        Binding {
            !query.isEmpty || opened.contains(place)
        } set: { isOpen in
            if isOpen { opened.insert(place) } else { opened.remove(place) }
        }
    }

    /// The entries whose names contain the search text, ignoring case; all without search text.
    ///
    /// - Parameters:
    ///   - entries: The entries.
    ///   - query: The search text.
    /// - Returns: The matching entries.
    static func matching(_ entries: [PhotoDetails.TagEntry], query: String) -> [PhotoDetails.TagEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    /// A group's name. The standards' names (TIFF, EXIF, GPS, DNG, XMP) aren't translated.
    ///
    /// - Parameter place: The group.
    /// - Returns: The name.
    static func name(of place: PhotoDetails.TagEntry.Place) -> Text {
        switch place {
        case .tiff: Text(verbatim: "TIFF")
        case .exif: Text(verbatim: "EXIF")
        case .gps: Text(verbatim: "GPS")
        case .dng: Text(verbatim: "DNG")
        case .xmp: Text(verbatim: "XMP")
        case .fileStructure: Text("File Structure", bundle: .module, comment: "Group on the Every Tag page of the photo details: the file's container blocks (HEIF boxes, JPEG segments).")
        case .contentCredentials: Text("Content Credentials", tableName: "Honesty", bundle: .module, comment: "Heading in the photo details: the photo's Content Credentials signature. Content Credentials is the name of the C2PA standard's signatures. Draft wording for the Honesty review.")
        }
    }
}

/// The tag number as VoiceOver custom content (the More Content rotor), so it doesn't slow the
/// list; nothing for a block or an XMP property.
struct TagNumberContent: ViewModifier {
    /// The tag number, such as `0x829A`, or `nil`.
    let number: String?

    /// Creates the modifier.
    ///
    /// - Parameter number: The tag number, or `nil`.
    init(number: String?) {
        self.number = number
    }

    /// The view with the custom content.
    ///
    /// - Parameter content: The view.
    func body(content: Content) -> some View {
        if let number {
            content.accessibilityCustomContent(
                Text("Tag number", bundle: .module, comment: "VoiceOver More Content label on the Every Tag page: the tag's number, such as 0x829A."),
                Text(verbatim: number))
        } else {
            content
        }
    }
}

/// One tag, block or property: its name, its value and, in a footnote, its tag number and what
/// controls it.
struct TagRow: View {
    /// The entry.
    let entry: PhotoDetails.TagEntry

    /// Whether its value is hidden.
    let isHidden: Bool

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - entry: The entry.
    ///   - isHidden: Whether its value is hidden.
    init(entry: PhotoDetails.TagEntry, isHidden: Bool) {
        self.entry = entry
        self.isHidden = isHidden
    }

    /// The row, read as "ExposureTime, 0.008, Exposure Settings", with the tag number as custom
    /// content.
    var body: some View {
        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
            // Specification names (tags, blocks, properties) aren't translated.
            Text(verbatim: entry.name)
                .font(.body.monospaced())
            Text(verbatim: ComparisonText.describe(entry.value, masked: isHidden))
                .foregroundStyle(CameraStyle.secondaryText)
            footnote
                .font(.footnote)
                .foregroundStyle(CameraStyle.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: entry.name))
        .accessibilityValue(Text("\(ComparisonText.describe(entry.value, masked: isHidden)), \(Self.control(entry.control))", bundle: .module, comment: "VoiceOver value of a tag on the Every Tag page: the tag's value, then the setting that controls it."))
        .modifier(TagNumberContent(number: entry.tagNumberText))
    }

    /// The tag number and what controls the entry, such as "0x829A · Exposure Settings".
    private var footnote: Text {
        guard let number = entry.tagNumberText else { return Self.control(entry.control) }
        return Text("\(number) · \(Self.control(entry.control))", bundle: .module, comment: "Every Tag page of the photo details: a tag's number, then the setting that controls it, such as 0x829A · Exposure Settings. Keep the separator.")
    }

    /// What controls an entry: its setting, "Always saved", or the signature.
    ///
    /// - Parameter control: The control.
    /// - Returns: The text.
    static func control(_ control: PhotoDetails.TagEntry.Control) -> Text {
        switch control {
        case .setting(let item):
            Text(PrivacySettingsView.title(of: item))
        case .alwaysSaved:
            Text("Always saved", bundle: .module, comment: "Every Tag page of the photo details: every file of this format holds the tag; no setting controls it.")
        case .signature:
            Text("nope.'s Content Credentials signature.", tableName: "Honesty", bundle: .module, comment: "Compare view: this item of nope.'s file is its Content Credentials signature. Keep \"nope.\" unchanged.")
        }
    }
}
