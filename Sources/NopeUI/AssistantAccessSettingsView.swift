import NopeCore
import SwiftUI

extension EnvironmentValues {
    /// What assistants did since the app opened (issue #82), for the camera's Assistant Access
    /// hint, refusal card and tip and for the This Session list. `nil` where no assistant can
    /// reach the app: the Lock Screen camera, whose Settings then show Assistant Access read
    /// only, and previews. The app sets it.
    @Entry public var assistantSession: AssistantSession?
}

/// Settings › Privacy › Assistant Access (issue #82; `docs/design/assistant-access.md`,
/// section 3; figures `assistant-page-off`, `assistant-page-on`): while access is off, a line
/// that Ask First is not used now; the Assistant Access switch with its explanation; the three
/// Ask First choices, always shown and enabled; what assistants get; and the requests of this
/// session.
///
/// The page changes the settings only through `NopeSettings.setAssistantAccess(_:)` and
/// `NopeSettings.setAssistantAsk(_:)`; the rules are in `AssistantAccess` in `NopeCore`. No row appears or
/// disappears when the switch changes, except the line at the top, which is shown only while
/// access is off, as Fast Shutter's is while Manual Controls are on.
struct AssistantAccessSettingsView: View {
    /// The person's settings.
    let settings: NopeSettings

    /// The session's requests, or `nil` where there are none to show.
    let session: AssistantSession?

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - settings: The person's settings.
    ///   - session: What assistants did since the app opened, or `nil`.
    init(settings: NopeSettings, session: AssistantSession?) {
        self.settings = settings
        self.session = session
    }

    /// The page.
    var body: some View {
        NopeForm {
            if !settings.assistantAccess {
                Section {
                    // A plain text row, as on Fast Shutter: with the information symbol of the
                    // drawing (a Label), the audit reported that sentence as clipped there.
                    Text(AssistantAccessText.offLine)
                        .accessibilityIdentifier("settings.assistantAccess.notUsedNow")
                }
            }
            Section {
                AssistantAccessSwitch(
                    isOn: Binding(get: { settings.assistantAccess }, set: { settings.setAssistantAccess($0) }))
                .settingsRow(.assistantAccessSwitch)
            }
            Section {
                Picker(selection: Binding(get: { settings.assistantAsk }, set: { settings.setAssistantAsk($0) })) {
                    ForEach(AssistantAskLevel.allCases, id: \.self) { level in
                        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                            Text(AssistantAccessText.name(of: level))
                            Text(AssistantAccessText.sentence(of: level))
                                .font(.footnote)
                                .foregroundStyle(CameraStyle.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityInputLabels([Text(AssistantAccessText.name(of: level))])
                        .accessibilityIdentifier("settings.assistantAccess.ask.\(level.rawValue)")
                        .tag(level)
                    }
                } label: {
                    Text(SettingsText.askFirst)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .settingsContainerRow(.assistantAsk)
            } header: {
                Text(SettingsText.askFirst)
            } footer: {
                Text(AssistantAccessText.askFooter)
            }
            // Rows rather than a section footer, as on Fast Shutter, so they follow Dynamic Type.
            Section {
                Text(AssistantAccessText.whatAssistantsGet1)
                Text(AssistantAccessText.whatAssistantsGet2)
                Text(AssistantAccessText.whatAssistantsGet3)
            } header: {
                Text(AssistantAccessText.whatAssistantsGetHeader)
            }
            Section {
                if let records = session?.records, !records.isEmpty {
                    ForEach(records) { record in
                        Text(AssistantAccessText.line(for: record))
                            .accessibilityIdentifier("settings.assistantAccess.session.line")
                    }
                } else {
                    Text(AssistantAccessText.noRequests)
                        .foregroundStyle(CameraStyle.secondaryText)
                        .accessibilityIdentifier("settings.assistantAccess.session.empty")
                }
            } header: {
                Text(AssistantAccessText.sessionHeader)
            } footer: {
                Text(AssistantAccessText.sessionFooter)
            }
        }
        .navigationTitle(Text(SettingsText.assistantAccess))
        .modifier(SettingsScrollTarget(navigation: navigation, page: .assistantAccess))
    }

    /// The Settings navigation, for search's scroll target.
    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    /// The row's value: Off, or the Ask First choice while access is on.
    ///
    /// - Parameter settings: The settings.
    /// - Returns: The value.
    static func summary(of settings: NopeSettings) -> Text {
        guard settings.assistantAccess else { return Text(AssistantAccessText.valueOff) }
        return Text(AssistantAccessText.value(of: settings.assistantAsk))
    }
}

/// The Assistant Access switch with its explanation, as an ``ExplainedToggle``, except at the
/// accessibility text sizes: there the title is a line of its own above the switch, across the
/// row's full width. Beside the switch, "Assistant Access" wrapped into a narrow column that the
/// accessibility audit reported as "Dynamic Type font sizes are partially unsupported" (iPhone
/// 18 Pro Simulator, iOS 27.2). VoiceOver still reads one element: the switch, named
/// "Assistant Access", with its value, then the explanation.
struct AssistantAccessSwitch: View {
    /// Whether Assistant Access is on.
    let isOn: Binding<Bool>

    /// The current text size.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates the switch.
    ///
    /// - Parameter isOn: Whether Assistant Access is on.
    init(isOn: Binding<Bool>) {
        self.isOn = isOn
    }

    /// The switch and its explanation.
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: NopeSpace.xs) {
                Text(SettingsText.assistantAccess)
                    // Without it the row was laid out a few points short of the wrapped title,
                    // which the audit reported as clipped.
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                // No text inside the switch: its name is its accessibility label.
                Toggle(isOn: isOn) { EmptyView() }
                    .labelsHidden()
                    .accessibilityLabel(Text(SettingsText.assistantAccess))
                Text(AssistantAccessText.switchExplanation)
                    .font(.footnote)
                    .foregroundStyle(CameraStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            ExplainedToggle(
                isOn: isOn, title: Text(SettingsText.assistantAccess),
                explanation: Text(AssistantAccessText.switchExplanation))
        }
    }
}

/// The Assistant Access hint and cards on the camera (`docs/design/assistant-access.md`,
/// section 10; figures `assistant-camera-notice`, `assistant-camera-refused`, `assistant-tip`):
/// after an action an assistant ran, "Siri or Shortcuts" and the sentence the assistant got,
/// with Close; after a refusal, how many were refused, with Settings and Close; once after five
/// confirmed requests, the tip. Nothing where the app has no session (the Lock Screen camera).
///
/// No message here leaves on a timer (docs/design/ACCESSIBILITY.md): the hint stays until the
/// next action on the camera (`CameraModel.actionCount`) or Close, so a person using
/// VoiceOver, Switch Control or the largest text size has as long as they need (third review of
/// 1.0.0, S7).
struct AssistantHints: View {
    /// The camera model, whose actions close the hint.
    let model: CameraModel

    /// What assistants did since the app opened.
    @Environment(\.assistantSession) private var session

    /// Opens Settings at a page.
    @Environment(\.openSettingsAt) private var openSettingsAt

    /// Creates the hints; they read the session from the environment.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The hint and cards that apply.
    var body: some View {
        if let session {
            if let notice = session.notice {
                AssistantNoticeHint(sentence: notice.sentence, close: { session.clearNotice(notice.id) })
                    .id(notice.id)
                    // The next action closes it. The assistant's own action came before the
                    // notice, so it isn't counted.
                    .onChange(of: model.actionCount) { session.clearNotice(notice.id) }
            }
            if session.showsRefusalCard {
                AssistantCard(
                    text: AssistantAccessText.refusals(session.refusedCount), identifier: "assistant.refusalCard",
                    openSettings: openSettingsAt.map { open in
                        {
                            session.dismissRefusalCard()
                            open(.assistantAccess)
                        }
                    },
                    close: { session.dismissRefusalCard() })
            } else if session.showsTip {
                AssistantCard(
                    text: AssistantAccessText.tip, identifier: "assistant.tip",
                    openSettings: openSettingsAt.map { open in
                        {
                            session.dismissTip()
                            open(.assistantAccess)
                        }
                    },
                    close: { session.dismissTip() })
            }
        }
    }
}

/// "Siri or Shortcuts" over the sentence an assistant got, announced after any capture result,
/// with a Close button.
struct AssistantNoticeHint: View {
    /// The sentence.
    let sentence: String

    /// Closes the hint.
    let close: () -> Void

    /// Creates the hint.
    ///
    /// - Parameters:
    ///   - sentence: The sentence the assistant got.
    ///   - close: Closes the hint.
    init(sentence: String, close: @escaping () -> Void) {
        self.sentence = sentence
        self.close = close
    }

    /// The hint.
    var body: some View {
        HStack(spacing: NopeSpace.xs) {
            VStack(spacing: NopeSpace.xxs) {
                Text(AssistantAccessText.hintCaption)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CameraStyle.secondaryText)
                Text(verbatim: sentence)
                    .font(NopeFont.status)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("assistant.notice")
            Button(action: close) {
                Label {
                    Text("Assistant card: Close", tableName: "Honesty", bundle: .module, comment: "Button that closes nope.'s Assistant Access card, tip or hint on the camera.")
                } icon: {
                    Image(systemName: "xmark")
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(NopeIconButtonStyle())
            .accessibilityIdentifier("assistant.notice.close")
        }
        .foregroundStyle(NopeColor.label)
        .padding(.leading, NopeSpace.s)
        .padding(.trailing, NopeSpace.xs)
        .padding(.vertical, NopeSpace.xs)
        .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.small))
        .accessibilityElement(children: .contain)
        .onAppear {
            // Queued behind a capture result's announcement rather than interrupting it.
            var announcement = AttributedString(AssistantAccessText.spokenHint(sentence))
            announcement.accessibilitySpeechAnnouncementPriority = .low
            AccessibilityNotification.Announcement(announcement).post()
        }
    }
}

/// A card on the camera with a sentence, a Settings button and a Close button, which stays
/// until one is pressed.
struct AssistantCard: View {
    /// The sentence.
    let text: String

    /// The card's accessibility identifier.
    let identifier: String

    /// Opens Settings at Assistant Access, or `nil` where Settings can't be opened.
    let openSettings: (() -> Void)?

    /// Closes the card.
    let close: () -> Void

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - text: The sentence.
    ///   - identifier: The card's accessibility identifier.
    ///   - openSettings: Opens Settings at Assistant Access, or `nil`.
    ///   - close: Closes the card.
    init(text: String, identifier: String, openSettings: (() -> Void)?, close: @escaping () -> Void) {
        self.text = text
        self.identifier = identifier
        self.openSettings = openSettings
        self.close = close
    }

    /// The card.
    var body: some View {
        HStack(spacing: NopeSpace.xs) {
            Text(verbatim: text)
                .font(NopeFont.status)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let openSettings {
                Button(action: openSettings) {
                    Text("Settings", bundle: .module, comment: "Title of the settings screen, and the camera button that opens it.")
                }
                .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .tile))
                .accessibilityIdentifier("\(identifier).settings")
            }
            Button(action: close) {
                Label {
                    Text("Assistant card: Close", tableName: "Honesty", bundle: .module, comment: "Button that closes nope.'s Assistant Access card, tip or hint on the camera.")
                } icon: {
                    Image(systemName: "xmark")
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(NopeIconButtonStyle())
            .accessibilityIdentifier("\(identifier).close")
        }
        .foregroundStyle(NopeColor.label)
        .padding(NopeSpace.s)
        .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.small))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// The text of Assistant Access (`docs/design/assistant-access.md`, section 15). Drafts for the
/// Honesty review; all are in `Honesty.xcstrings`.
enum AssistantAccessText {
    /// The module's bundle, for the resources.
    static let bundle = SettingsText.bundle

    /// The row's note (text 1).
    static let rowNote = LocalizedStringResource("For Siri, Shortcuts and other assistants.", table: "Honesty", bundle: bundle, comment: "Note under the Assistant Access row in nope.'s Settings. Siri and Shortcuts are Apple's names. Draft for the Honesty review. Must not claim more than the English.")

    /// The note of the read-only row in the Lock Screen camera (text 24).
    static let unlockToChange = LocalizedStringResource("Unlock to change.", table: "Honesty", bundle: bundle, comment: "Note under the Assistant Access row in the Settings of nope.'s Lock Screen camera, where the setting can't be changed. Draft for the Honesty review.")

    /// The row's value while access is off (text 2).
    static let valueOff = LocalizedStringResource("Assistant Access: Off", defaultValue: "Off", table: "Honesty", bundle: bundle, comment: "Value of the Assistant Access row in nope.'s Settings: assistants can't use nope.'s actions.")

    /// The row's value for an Ask First choice while access is on (text 2).
    ///
    /// - Parameter level: The choice.
    /// - Returns: The value.
    static func value(of level: AssistantAskLevel) -> LocalizedStringResource {
        switch level {
        case .everyAction: LocalizedStringResource("Ask Every Action", table: "Honesty", bundle: bundle, comment: "Value of the Assistant Access row in nope.'s Settings: access is on and nope. asks before every action.")
        case .beforePhoto: LocalizedStringResource("Ask Before a Photo", table: "Honesty", bundle: bundle, comment: "Value of the Assistant Access row in nope.'s Settings: access is on and nope. asks only before an action that takes photos.")
        case .never: LocalizedStringResource("Never Ask", table: "Honesty", bundle: bundle, comment: "Value of the Assistant Access row in nope.'s Settings: access is on and nope. never asks first.")
        }
    }

    /// The line at the top while access is off (text 3).
    static let offLine = LocalizedStringResource("Assistant Access is off, so Ask First is not used now.", table: "Honesty", bundle: bundle, comment: "First row of the Assistant Access page in nope.'s Settings while the switch is off. Assistant Access and Ask First are names on the page. Draft for the Honesty review. Must not claim more than the English.")

    /// The switch's explanation (text 4).
    static let switchExplanation = LocalizedStringResource("Lets Siri, Shortcuts and other assistants on this device use nope.'s actions, such as taking a photo or switching lenses. While this is off, nope. refuses its actions.", table: "Honesty", bundle: bundle, comment: "Explains the Assistant Access switch in nope.'s Settings. Siri and Shortcuts are Apple's names. Keep \"nope.\" unchanged. Draft for the Honesty review. Must not claim more than the English.")

    /// An Ask First choice's name (text 5).
    ///
    /// - Parameter level: The choice.
    /// - Returns: The name.
    static func name(of level: AssistantAskLevel) -> LocalizedStringResource {
        switch level {
        case .everyAction: LocalizedStringResource("Every Action", table: "Honesty", bundle: bundle, comment: "A choice of Ask First on nope.'s Assistant Access page: nope. asks before every action. A name in nope.'s Settings.")
        case .beforePhoto: LocalizedStringResource("Only Before a Photo", table: "Honesty", bundle: bundle, comment: "A choice of Ask First on nope.'s Assistant Access page: nope. asks only before an action that takes photos. A name in nope.'s Settings.")
        case .never: LocalizedStringResource("Ask First: Never", defaultValue: "Never", table: "Honesty", bundle: bundle, comment: "A choice of Ask First on nope.'s Assistant Access page: nope. never asks first. A name in nope.'s Settings.")
        }
    }

    /// An Ask First choice's sentence (texts 6 to 8).
    ///
    /// - Parameter level: The choice.
    /// - Returns: The sentence.
    static func sentence(of level: AssistantAskLevel) -> LocalizedStringResource {
        switch level {
        case .everyAction: LocalizedStringResource("nope. names each action and asks before it runs.", table: "Honesty", bundle: bundle, comment: "Explains the Every Action choice of Ask First on nope.'s Assistant Access page. Keep \"nope.\" unchanged. Draft for the Honesty review. Must not claim more than the English.")
        case .beforePhoto: LocalizedStringResource("Changes run without asking. nope. asks before an action that takes photos.", table: "Honesty", bundle: bundle, comment: "Explains the Only Before a Photo choice of Ask First on nope.'s Assistant Access page. Keep \"nope.\" unchanged. Draft for the Honesty review. Must not claim more than the English.")
        case .never: LocalizedStringResource("Actions run without asking.", table: "Honesty", bundle: bundle, comment: "Explains the Never choice of Ask First on nope.'s Assistant Access page. Draft for the Honesty review. Must not claim more than the English.")
        }
    }

    /// The Ask First footer (text 9).
    static let askFooter = LocalizedStringResource("An automation that runs with no one there can’t answer, so it stops at the question.", table: "Honesty", bundle: bundle, comment: "Under the Ask First choices on nope.'s Assistant Access page: a Shortcuts automation that runs unattended stops at nope.'s question. Draft for the Honesty review. Must not claim more than the English.")

    /// The What Assistants Get header.
    static let whatAssistantsGetHeader = LocalizedStringResource("What Assistants Get", table: "Honesty", bundle: bundle, comment: "Section header on nope.'s Assistant Access page: what Siri, Shortcuts and other assistants can learn from nope.")

    /// What Assistants Get, 1 (text 10).
    static let whatAssistantsGet1 = LocalizedStringResource("After an action, the assistant gets one sentence about what happened, such as “Photo saved.” It never gets a photo, a location or a photo’s details from nope.", table: "Honesty", bundle: bundle, comment: "On nope.'s Assistant Access page. \"Photo saved.\" quotes Siri's answer; use its translation. Keep \"nope.\" unchanged. Draft for the Honesty review. Must not claim more than the English: \"from nope.\" is part of the claim.")

    /// What Assistants Get, 2 (text 11).
    static let whatAssistantsGet2 = LocalizedStringResource("While access is on, assistants can see the names of your presets. No action changes a Privacy setting, and a preset applied this way leaves your privacy settings as they are.", table: "Honesty", bundle: bundle, comment: "On nope.'s Assistant Access page. Privacy is the name of the group in nope.'s Settings. Draft for the Honesty review. Must not claim more than the English.")

    /// What Assistants Get, 3 (text 12).
    static let whatAssistantsGet3 = LocalizedStringResource("This covers nope.’s own actions. The shutter, the volume buttons, Camera Control, the Apple Watch app and the Control Center controls are not affected. Photos saved to Photos, and what Siri or other apps can see or do outside nope., are up to iOS.", table: "Honesty", bundle: bundle, comment: "On nope.'s Assistant Access page. Camera Control, Apple Watch, Control Center, Photos, Siri and iOS are Apple's names. Keep \"nope.\" unchanged. Draft for the Honesty review. Must not claim more than the English.")

    /// The This Session header (text 13).
    static let sessionHeader = LocalizedStringResource("This Session", table: "Honesty", bundle: bundle, comment: "Section header on nope.'s Assistant Access page: the assistant requests since nope. opened.")

    /// The This Session list while it is empty (text 13).
    static let noRequests = LocalizedStringResource("No requests since nope. opened.", table: "Honesty", bundle: bundle, comment: "On nope.'s Assistant Access page when no assistant asked for anything since nope. opened. Keep \"nope.\" unchanged.")

    /// The This Session footer (text 13).
    static let sessionFooter = LocalizedStringResource("Kept in memory only. Cleared when nope. closes.", table: "Honesty", bundle: bundle, comment: "Under the This Session list on nope.'s Assistant Access page. Keep \"nope.\" unchanged. Draft for the Honesty review. Must not claim more than the English.")

    /// The camera hint's caption (text 20).
    static let hintCaption = LocalizedStringResource("Siri or Shortcuts", table: "Honesty", bundle: bundle, comment: "Caption of the hint on nope.'s camera after Siri, Shortcuts or another assistant ran an action. nope. can't tell which one asked. Siri and Shortcuts are Apple's names.")

    /// The tip (text 22).
    static var tip: String {
        String(localized: "You’ve confirmed 5 assistant requests. You can change how nope. asks.", table: "Honesty", bundle: .module, comment: "Tip on nope.'s camera, shown once after the person confirmed five Siri or Shortcuts requests. Keep \"nope.\" unchanged. Draft for the Honesty review.")
    }

    /// The refusal card (text 21).
    ///
    /// - Parameter count: The requests refused since the app opened, at least 1.
    /// - Returns: The sentence.
    static func refusals(_ count: Int) -> String {
        String(localized: "Assistant Access is off. nope. refused \(count) requests since it opened.", table: "Honesty", bundle: .module, comment: "Card on nope.'s camera after Siri, Shortcuts or another assistant asked for an action while Assistant Access was off. The number is how many requests were refused. Keep \"nope.\" unchanged. Draft for the Honesty review.")
    }

    /// What VoiceOver says for the hint.
    ///
    /// - Parameter sentence: The sentence the assistant got.
    /// - Returns: "Siri or Shortcuts." and the sentence.
    static func spokenHint(_ sentence: String) -> String {
        String(localized: "Siri or Shortcuts. \(sentence)", table: "Honesty", bundle: .module, comment: "What VoiceOver says for the hint on nope.'s camera after an assistant ran an action. The placeholder is the sentence the assistant got, such as \"Now using the telephoto camera.\".")
    }

    /// One line of the This Session list: the action's name and what happened.
    ///
    /// - Parameter record: The request.
    /// - Returns: For example "Take Photo. Asked, allowed."
    static func line(for record: AssistantRequestRecord) -> String {
        let action = String(localized: name(of: record.action))
        let result = String(localized: name(of: record.result))
        return String(localized: "Assistant session line", defaultValue: "\(action). \(result)", table: "Honesty", bundle: .module, comment: "One line of the This Session list on nope.'s Assistant Access page: an action's name, then what happened, such as \"Take Photo. Asked, allowed.\".")
    }

    /// What happened to a request (text 14).
    ///
    /// - Parameter result: The result.
    /// - Returns: The words.
    static func name(of result: AssistantRequestResult) -> LocalizedStringResource {
        switch result {
        case .askedAllowed: LocalizedStringResource("Asked, allowed.", table: "Honesty", bundle: bundle, comment: "In the This Session list on nope.'s Assistant Access page: nope. asked and the person allowed the action.")
        case .askedCancelled: LocalizedStringResource("Asked, canceled.", table: "Honesty", bundle: bundle, comment: "In the This Session list on nope.'s Assistant Access page: nope. asked and the person cancelled.")
        case .ranWithoutAsking: LocalizedStringResource("Ran without asking.", table: "Honesty", bundle: bundle, comment: "In the This Session list on nope.'s Assistant Access page: the action ran without a question.")
        case .refused: LocalizedStringResource("Refused.", table: "Honesty", bundle: bundle, comment: "In the This Session list on nope.'s Assistant Access page: nope. refused the action.")
        }
    }

    /// An action's name, as the Shortcuts app shows it.
    ///
    /// - Parameter action: The action.
    /// - Returns: The name.
    static func name(of action: AssistantAction) -> LocalizedStringResource {
        switch action {
        case .takePhoto: LocalizedStringResource("Assistant action: Take Photo", defaultValue: "Take Photo", bundle: bundle, comment: "The name of nope.'s Take Photo action, in the This Session list on the Assistant Access page.")
        case .takeBracket: LocalizedStringResource("Assistant action: Take Bracket", defaultValue: "Take Bracket", bundle: bundle, comment: "The name of nope.'s Take Bracket action, in the This Session list on the Assistant Access page.")
        case .startInterval: LocalizedStringResource("Assistant action: Start Interval Shooting", defaultValue: "Start Interval Shooting", bundle: bundle, comment: "The name of nope.'s Start Interval Shooting action, in the This Session list on the Assistant Access page.")
        case .stopInterval: LocalizedStringResource("Assistant action: Stop Interval Shooting", defaultValue: "Stop Interval Shooting", bundle: bundle, comment: "The name of nope.'s Stop Interval Shooting action, in the This Session list on the Assistant Access page.")
        case .switchLens: LocalizedStringResource("Assistant action: Switch Lens", defaultValue: "Switch Lens", bundle: bundle, comment: "The name of nope.'s Switch Lens action, in the This Session list on the Assistant Access page.")
        case .turnOnLight: LocalizedStringResource("Assistant action: Turn On the Light", defaultValue: "Turn On the Light", bundle: bundle, comment: "The name of nope.'s Turn On the Light action, in the This Session list on the Assistant Access page.")
        case .turnOffLight: LocalizedStringResource("Assistant action: Turn Off the Light", defaultValue: "Turn Off the Light", bundle: bundle, comment: "The name of nope.'s Turn Off the Light action, in the This Session list on the Assistant Access page.")
        case .setNightMode: LocalizedStringResource("Assistant action: Set Night Mode", defaultValue: "Set Night Mode", bundle: bundle, comment: "The name of nope.'s Set Night Mode action, in the This Session list on the Assistant Access page.")
        case .setFocusRange: LocalizedStringResource("Assistant action: Set Focus Range", defaultValue: "Set Focus Range", bundle: bundle, comment: "The name of nope.'s Set Focus Range action, in the This Session list on the Assistant Access page.")
        case .setPhotoSize: LocalizedStringResource("Assistant action: Set Photo Size", defaultValue: "Set Photo Size", bundle: bundle, comment: "The name of nope.'s Set Photo Size action, in the This Session list on the Assistant Access page.")
        case .setFastShutter: LocalizedStringResource("Assistant action: Set Fast Shutter", defaultValue: "Set Fast Shutter", bundle: bundle, comment: "The name of nope.'s Set Fast Shutter action, in the This Session list on the Assistant Access page.")
        case .setFocusOnFaces: LocalizedStringResource("Assistant action: Set Focus on Faces", defaultValue: "Set Focus on Faces", bundle: bundle, comment: "The name of nope.'s Set Focus on Faces action, in the This Session list on the Assistant Access page.")
        case .applyPreset: LocalizedStringResource("Assistant action: Apply Preset", defaultValue: "Apply Preset", bundle: bundle, comment: "The name of nope.'s Apply Preset action, in the This Session list on the Assistant Access page.")
        case .openCamera: LocalizedStringResource("Assistant action: Open the Camera", defaultValue: "Open the Camera", bundle: bundle, comment: "The name of nope.'s Open the Camera action.")
        case .openAssistantAccess: LocalizedStringResource("Assistant action: Open Assistant Access", defaultValue: "Open Assistant Access", bundle: bundle, comment: "The name of nope.'s Open Assistant Access action.")
        case .nightModeControl: SettingsText.nightMode
        case .liveActivityStop: LocalizedStringResource("Stop", bundle: bundle, comment: "Button that stops interval shooting.")
        }
    }
}
