import NopeCore
import SwiftUI

extension EnvironmentValues {
    /// The invitation to the how-to-use guide (issue #117), or `nil` where the camera shows no
    /// invitation card: the Lock Screen camera, previews and tests. The app sets it. The guide
    /// itself opens from Settings and About either way.
    @Entry public var guideInvitation: GuideInvitation?
}

/// One page of the how-to-use guide (issue #117; `docs/design/finish-1.0.md`, section 2.2): one
/// idea, in a title, one or two short sentences and, for the two key ideas, a link to the full
/// explanation in Settings.
///
/// The pages follow the owner's list for 1.0.0 (2026-11-21): shooting, the two key ideas
/// (unprocessed photos and privacy) right after it, then lenses, Auto and manual, drive modes
/// and Q. The words describe only what ships, and name nothing a device may lack: the lens
/// sentence depends on the device's lenses, and the drive sentence names only Single, Timer
/// and Burst, which every device offers. Q is described as it is: a button that opens the
/// Quick Menu (its tiles are fixed; nothing here changes them).
enum GuidePage: Int, CaseIterable, Identifiable {
    /// How to take a photo.
    case takePhoto
    /// The first key idea: as little processing as the camera allows.
    case unprocessed
    /// The second key idea: no internet, and the person chooses each photo's details.
    case privacy
    /// The lens buttons and Switch Camera.
    case lenses
    /// Auto and Manual.
    case autoAndManual
    /// The drive modes.
    case driveModes
    /// Q and Settings.
    case quickMenu

    /// The page itself, so the pages can be listed with `ForEach`.
    var id: Self { self }

    /// The page's number, from 1.
    var number: Int { rawValue + 1 }

    /// The page's title.
    var title: LocalizedStringResource {
        switch self {
        case .takePhoto: GuideText.takePhotoTitle
        case .unprocessed: GuideText.unprocessedTitle
        case .privacy: GuideText.privacyTitle
        case .lenses: GuideText.lensesTitle
        case .autoAndManual: GuideText.autoAndManualTitle
        case .driveModes: GuideText.driveModesTitle
        case .quickMenu: GuideText.quickMenuTitle
        }
    }

    /// The page's text.
    ///
    /// - Parameter lenses: What the device has, for the lens page.
    /// - Returns: The text.
    func text(lenses: GuideLenses) -> LocalizedStringResource {
        switch self {
        case .takePhoto: GuideText.takePhotoText
        case .unprocessed: GuideText.unprocessedText
        case .privacy: GuideText.privacyText
        case .lenses: GuideText.lensesText(lenses)
        case .autoAndManual: GuideText.autoAndManualText
        case .driveModes: GuideText.driveModesText
        case .quickMenu: GuideText.quickMenuText
        }
    }

    /// The page's link into Settings: its words and the page it opens, or `nil`.
    var link: (title: LocalizedStringResource, destination: SettingsID)? {
        switch self {
        case .unprocessed: (GuideText.aboutProcessing, .honesty)
        case .privacy: (SettingsText.details, .details)
        case .takePhoto, .lenses, .autoAndManual, .driveModes, .quickMenu: nil
        }
    }

    /// The page after this one, or `nil` on the last.
    var next: GuidePage? { GuidePage(rawValue: rawValue + 1) }

    /// The page before this one, or `nil` on the first.
    var previous: GuidePage? { GuidePage(rawValue: rawValue - 1) }
}

/// What the device's cameras are, for the lens page's sentence and picture: nothing a device
/// lacks is named.
struct GuideLenses: Equatable {
    /// The rear lenses, in display order.
    let rear: [Lens]

    /// Whether the device has a front camera, so Switch Camera is shown.
    let hasFrontCamera: Bool

    /// Whether any lens saves Bayer RAW, for the picture of the format status.
    let supportsBayerRAW: Bool

    /// Reads the device's lenses.
    ///
    /// - Parameter lenses: The device's lenses (`DeviceCapabilities/lenses`), or none when they
    ///   aren't known yet; the guide then describes a device with two or more rear lenses and a
    ///   front camera, as most have, and shows RAW.
    init(_ lenses: [Lens]) {
        guard !lenses.isEmpty else {
            rear = []
            hasFrontCamera = true
            supportsBayerRAW = true
            return
        }
        rear = lenses.filter { $0.kind != .front }
        hasFrontCamera = lenses.contains { $0.kind == .front }
        supportsBayerRAW = lenses.contains(where: \.supportsBayerRAW)
    }

    /// Whether the lens buttons offer a choice: two or more rear lenses, or the lenses aren't
    /// known.
    var offersLensChoice: Bool { rear.isEmpty || rear.count > 1 }
}

/// The how-to-use guide (issue #117; `docs/design/finish-1.0.md`, section 2.2): seven short
/// pages in a sheet, one idea each, opened from the camera's invitation card and from the How to
/// Use nope. rows in Settings and About.
///
/// Each page has a picture, a title (a heading), its text and, for the two key ideas, a link
/// that closes the guide and opens Settings at the full explanation. The pictures are the camera's
/// own controls (the shutter, the lens buttons, Auto, the drive words, Q) or a symbol, drawn by
/// the same views the camera uses, so no picture carries baked-in text and each follows text size,
/// language and night mode. They are decoration: hidden from VoiceOver and not buttons.
///
/// Moving: Back and Next (Done on the last page) under the page, with the page number between
/// them, and Close in the bar. A horizontal swipe moves between pages too; the arrow keys and
/// Escape work from a keyboard. Nothing advances by itself. Pages cross-fade with Reduce Motion
/// and slide otherwise; Back and Next follow the layout direction. At large text sizes the page
/// scrolls and the buttons stay pinned under it. Moving to a page announces its number and title
/// to VoiceOver.
struct GuideView: View {
    /// What the device's cameras are.
    let lenses: GuideLenses

    /// Called with a page of Settings when a link is chosen: the presenter closes the guide and
    /// opens Settings there.
    let openLink: (SettingsID) -> Void

    /// The page shown.
    @State private var page = GuidePage.takePhoto

    /// Whether the last move went forward, for the slide's direction.
    @State private var movedForward = true

    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Whether Reduce Motion is on: pages cross-fade.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The layout direction: Back and Next swap sides in right-to-left layouts, and so do the
    /// arrow keys and the swipe.
    @Environment(\.layoutDirection) private var layoutDirection

    /// Creates the guide at its first page.
    ///
    /// - Parameters:
    ///   - lenses: The device's lenses (`DeviceCapabilities/lenses`), or none when not known.
    ///   - openLink: Called with a Settings page when a link is chosen.
    init(lenses: [Lens], openLink: @escaping (SettingsID) -> Void) {
        self.lenses = GuideLenses(lenses)
        self.openLink = openLink
    }

    /// The page, the pinned buttons and the bar.
    var body: some View {
        NavigationStack {
            ScrollView {
                pageContent(page)
                    .id(page)
                    .transition(transition)
                    .frame(maxWidth: NopeSize.pictureStackMaxWidth)
                    .padding(.horizontal, NopeSpace.l)
                    .padding(.vertical, NopeSpace.m)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The screen's own background, inside night mode's red multiply: the sheet's, which
            // the multiply can't reach, would show its gray.
            .background(.background, ignoresSafeAreaEdges: .all)
            .simultaneousGesture(swipe)
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
            .navigationTitle(Text(GuideText.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        dismiss()
                    } label: {
                        Label { Text(GuideText.close) } icon: { Image(systemName: "xmark") }
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("guide.close")
                }
            }
        }
        .accessibilityIdentifier("guide")
    }

    /// How a page comes in: a cross-fade with Reduce Motion, otherwise a slide from the side the
    /// move went to.
    private var transition: AnyTransition {
        reduceMotion ? .opacity : .push(from: movedForward ? .trailing : .leading)
    }

    /// One page: the picture, the title, the text and the link.
    ///
    /// - Parameter page: The page.
    private func pageContent(_ page: GuidePage) -> some View {
        VStack(spacing: NopeSpace.m) {
            GuideFigure(page: page, lenses: lenses)
            Text(page.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("guide.title")
            Text(page.text(lenses: lenses))
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let link = page.link {
                Button {
                    openLink(link.destination)
                } label: {
                    HStack(spacing: NopeSpace.xxs) {
                        // Underlined, so the link isn't marked by color alone (night mode is red
                        // only).
                        Text(link.title)
                            .underline()
                            .multilineTextAlignment(.center)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: NopeSize.minTarget)
                    .contentShape(.rect)
                }
                .foregroundStyle(.primary)
                .accessibilityHint(Text(GuideText.linkHint))
                .accessibilityIdentifier("guide.link")
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Back, the page number and Next or Done, pinned under the page: side by side; at large
    /// text sizes the page number over Back and Next; stacked when even those don't fit.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NopeSpace.s) {
                backButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                pageNumber
                    .fixedSize()
                nextButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            // At large text sizes: the page number over Back and Next, which keep their sides.
            VStack(spacing: NopeSpace.xxs) {
                pageNumber
                HStack(spacing: NopeSpace.s) {
                    backButton
                    Spacer(minLength: 0)
                    nextButton
                }
            }
            VStack(spacing: NopeSpace.xs) {
                pageNumber
                nextButton
                backButton
            }
        }
        .padding(.horizontal, NopeSpace.l)
        .padding(.vertical, NopeSpace.s)
        .frame(maxWidth: NopeSize.pictureStackMaxWidth + 2 * NopeSpace.l)
        .frame(maxWidth: .infinity)
        .background(.background)
    }

    /// "2 of 7", read as "Page 2 of 7".
    private var pageNumber: some View {
        Text(GuideText.pageNumber(page.number, of: GuidePage.allCases.count))
            .font(.subheadline)
            .foregroundStyle(CameraStyle.secondaryText)
            .accessibilityLabel(Text(GuideText.spokenPageNumber(page.number, of: GuidePage.allCases.count)))
            .accessibilityIdentifier("guide.pageNumber")
    }

    /// Back, or an empty space of the same size on the first page.
    @ViewBuilder private var backButton: some View {
        if page.previous != nil {
            Button(action: goBack) {
                Text(GuideText.back)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The camera's capsule, which has its night mode colors (the system's bordered
            // button nearly failed the contrast audit in night mode).
            .buttonStyle(NopeCapsuleStyle(size: NopeSize.capsuleLarge))
            .keyboardShortcut(layoutDirection == .rightToLeft ? .rightArrow : .leftArrow, modifiers: [])
            .accessibilityIdentifier("guide.back")
        } else {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// Next, or Done on the last page, which closes the guide.
    private var nextButton: some View {
        Button(action: goForward) {
            Text(page.next == nil ? GuideText.done : GuideText.next)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(NopeGuideNextStyle())
        .keyboardShortcut(layoutDirection == .rightToLeft ? .leftArrow : .rightArrow, modifiers: [])
        .accessibilityIdentifier(page.next == nil ? "guide.done" : "guide.next")
    }

    /// A horizontal swipe moves a page: toward the leading edge goes forward. Vertical drags
    /// scroll the page as usual.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: NopeSize.minTarget)
            .onEnded { value in
                let width = value.translation.width
                guard abs(width) > abs(value.translation.height) else { return }
                // A drag's translation is in the page's own coordinates, which a right-to-left
                // layout doesn't mirror: there, a drag to the right goes forward.
                let forward = layoutDirection == .rightToLeft ? width > 0 : width < 0
                if forward {
                    if page.next != nil { goForward() }
                } else {
                    goBack()
                }
            }
    }

    /// Shows the next page, or closes the guide on the last.
    private func goForward() {
        guard let next = page.next else {
            dismiss()
            return
        }
        move(to: next, forward: true)
    }

    /// Shows the page before, if any.
    private func goBack() {
        guard let previous = page.previous else { return }
        move(to: previous, forward: false)
    }

    /// Moves to a page and tells VoiceOver which.
    ///
    /// - Parameters:
    ///   - target: The page.
    ///   - forward: Whether the move goes forward.
    private func move(to target: GuidePage, forward: Bool) {
        movedForward = forward
        withAnimation(reduceMotion ? NopeMotion.fade : .snappy) { page = target }
        AccessibilityNotification.Announcement(GuideText.announcement(for: target)).post()
    }
}

/// Next and Done in the guide: the filled capsule of the screen's one primary action, at its
/// natural width (``NopePrimaryActionStyle`` is full width).
struct NopeGuideNextStyle: PrimitiveButtonStyle {
    /// Creates the style. It holds no state.
    init() {}

    /// The button, in the system's prominent style.
    ///
    /// - Parameter configuration: The button's label, role and action.
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .foregroundStyle(Color(uiColor: .systemBackground))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Color(uiColor: .label))
    }
}

/// A guide page's picture: the camera control the page talks about, drawn by the camera's own
/// view on a black panel, or a symbol. Decoration only: hidden from VoiceOver and not touchable.
struct GuideFigure: View {
    /// The page.
    let page: GuidePage

    /// What the device's cameras are.
    let lenses: GuideLenses

    /// Creates the picture.
    ///
    /// - Parameters:
    ///   - page: The page.
    ///   - lenses: What the device's cameras are.
    init(page: GuidePage, lenses: GuideLenses) {
        self.page = page
        self.lenses = lenses
    }

    /// The panel and its picture.
    var body: some View {
        figure
            .frame(maxWidth: .infinity, minHeight: NopeSize.shutter + 2 * NopeSpace.l)
            .padding(.vertical, NopeSpace.m)
            .padding(.horizontal, NopeSpace.s)
            .background(Color.black, in: RoundedRectangle(cornerRadius: NopeRadius.large))
            // The camera's controls on the camera's black, in both appearances.
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The picture for the page.
    @ViewBuilder private var figure: some View {
        switch page {
        case .takePhoto:
            ShutterButton(isEnabled: true) {}
                .frame(width: NopeSize.shutter, height: NopeSize.shutter)
        case .unprocessed:
            formatStatus
        case .privacy:
            Image(systemName: "lock")
                .font(.largeTitle)
        case .lenses:
            HStack(spacing: NopeSpace.m) {
                if !lenses.rear.isEmpty {
                    LensButtons(lenses: lenses.rear, selectedID: selectedLensID) { _ in }
                }
                if lenses.hasFrontCamera {
                    CameraFlipButton {}
                }
            }
        case .autoAndManual:
            ManualControlsButton(isOn: false) {}
        case .driveModes:
            HStack(spacing: NopeSpace.xs) {
                ForEach([DriveWord.single, .timer, .burst]) { word in
                    Button {} label: { word.title }
                        .buttonStyle(NopeCapsuleStyle(isSelected: word == .single, size: NopeSize.driveWord, idleFill: .none))
                }
            }
        case .quickMenu:
            QuickButton(isOpen: false) {}
        }
    }

    /// The rear lens shown selected: the wide lens, or the first.
    private var selectedLensID: Lens.ID? {
        (lenses.rear.first { $0.kind == .wide } ?? lenses.rear.first)?.id
    }

    /// The camera's format status as it shows before a photo: RAW with its seal, or, on a device
    /// without Bayer RAW, the Processed marker.
    @ViewBuilder private var formatStatus: some View {
        if lenses.supportsBayerRAW {
            HStack(spacing: NopeSpace.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(CameraStyle.fact)
                Text(verbatim: "RAW")
            }
            .font(NopeFont.status)
        } else {
            HStack(spacing: NopeSpace.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CameraStyle.warning)
                Text(GuideText.processed)
            }
            .font(NopeFont.status)
        }
    }
}

/// Presents the how-to-use guide as a sheet, and opens Settings at a link's page once the guide
/// has closed.
struct GuideSheet: ViewModifier {
    /// Whether the guide is shown.
    @Binding var isPresented: Bool

    /// The device's lenses, or none when not known.
    let lenses: [Lens]

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the guide is shown.
    ///   - lenses: The device's lenses, or none when not known.
    init(isPresented: Binding<Bool>, lenses: [Lens]) {
        _isPresented = isPresented
        self.lenses = lenses
    }

    /// Opens Settings at a page: from the camera it opens Settings; inside Settings it moves to
    /// the page.
    @Environment(\.openSettingsAt) private var openSettingsAt

    /// Whether night mode is on, so the guide is red too.
    @Environment(\.isNightMode) private var isNightMode

    /// The invitation, answered when the guide opens, or `nil`.
    @Environment(\.guideInvitation) private var invitation

    /// The link chosen, opened once the guide has closed, so two presentations never change at
    /// once.
    @State private var pendingLink: SettingsID?

    /// The content with the guide's sheet.
    ///
    /// - Parameter content: The view that presents the guide.
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: openPendingLink) {
                GuideView(lenses: lenses) { link in
                    pendingLink = link
                    isPresented = false
                }
                .nightModeStyle(isNightMode)
                .presentationBackground(.background)
                .presentationDetents([.large])
                // A form sheet on iPad and the iPhone Duo's inner display, with the text at a
                // readable width.
                .presentationSizing(.form)
            }
            // Opening the guide, from anywhere, answers the invitation.
            .onChange(of: isPresented) { _, isOpen in
                if isOpen { invitation?.guideOpened() }
            }
    }

    /// Opens Settings at the chosen link's page, once.
    private func openPendingLink() {
        guard let link = pendingLink else { return }
        pendingLink = nil
        openSettingsAt?(link)
    }
}

extension View {
    /// Presents the how-to-use guide while `isPresented` is `true`.
    ///
    /// - Parameters:
    ///   - isPresented: Whether the guide is shown.
    ///   - lenses: The device's lenses, or none when not known.
    func guideSheet(isPresented: Binding<Bool>, lenses: [Lens]) -> some View {
        modifier(GuideSheet(isPresented: isPresented, lenses: lenses))
    }
}

/// The How to Use nope. row of Settings › More and of About: opens the guide at its first page.
struct GuideRow: View {
    /// The row's identifier: ``SettingsID/howToUse`` or ``SettingsID/aboutHowToUse``.
    let id: SettingsID

    /// The device's lenses, or none when not known.
    let lenses: [Lens]

    /// Whether the guide is shown.
    @State private var showsGuide = false

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - id: The row's identifier.
    ///   - lenses: The device's lenses, or none when not known.
    init(id: SettingsID, lenses: [Lens]) {
        self.id = id
        self.lenses = lenses
    }

    /// The row: the guide's title and a chevron, as the page rows beside it.
    var body: some View {
        Button {
            showsGuide = true
        } label: {
            HStack {
                Text(SettingsText.howToUse)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: NopeSpace.xs)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CameraStyle.secondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityHint(Text(GuideText.opensGuide))
        .settingsRow(id)
        .guideSheet(isPresented: $showsGuide, lenses: lenses)
    }
}

/// The guide's words, as resources. Page 2 and 3 make the app's key claims, so their titles and
/// texts are in the `Honesty` table. Every string is a draft for the Honesty review
/// (`docs/design/finish-1.0.md`, section 8).
enum GuideText {
    /// The module's bundle, for the resources.
    static let bundle = SettingsText.bundle

    /// "How to use nope.": the card's name on the camera.
    static let cardTitle = LocalizedStringResource(
        "Guide card: How to use nope.", defaultValue: "How to use nope.", bundle: bundle,
        comment: "Name of the small card on the camera that offers the how-to-use guide, with Open and Dismiss beside it. Keep \"nope.\" unchanged: it is the app's name. Sentence case, unlike the guide's title. Draft for the Honesty review.")

    /// "Open".
    static let open = LocalizedStringResource(
        "Guide card: Open", defaultValue: "Open", bundle: bundle,
        comment: "Button on the camera's how-to-use card: opens the guide. A short word.")

    /// "Opens the guide.".
    static let opensGuide = LocalizedStringResource(
        "Opens the guide.", bundle: bundle,
        comment: "VoiceOver hint of the Open button on the camera's how-to-use card, and of the How to Use nope. rows in Settings and About.")

    /// "Dismiss".
    static let dismiss = LocalizedStringResource(
        "Guide card: Dismiss", defaultValue: "Dismiss", bundle: bundle,
        comment: "VoiceOver and Voice Control name of the round ✕ button on the camera's how-to-use card. It hides the card for good; the guide stays in Settings.")

    /// "Hides this card.".
    static let hidesCard = LocalizedStringResource(
        "Hides this card. The guide stays in Settings.", bundle: bundle,
        comment: "VoiceOver hint of the Dismiss button on the camera's how-to-use card. Settings is the name of the app's settings screen.")

    /// "How to Use nope.": the guide's title, and the rows that open it.
    static let title = LocalizedStringResource(
        "How to Use nope.", bundle: bundle,
        comment: "Title of the how-to-use guide, and of the rows in Settings and About that open it. Keep \"nope.\" unchanged: it is the app's name. Title case. Draft for the Honesty review.")

    /// "Close".
    static let close = LocalizedStringResource(
        "Guide: Close", defaultValue: "Close", bundle: bundle,
        comment: "VoiceOver and Voice Control name of the ✕ button that closes the how-to-use guide.")

    /// "Next".
    static let next = LocalizedStringResource(
        "Guide: Next", defaultValue: "Next", bundle: bundle,
        comment: "Button under a page of the how-to-use guide: shows the next page.")

    /// "Back".
    static let back = LocalizedStringResource(
        "Guide: Back", defaultValue: "Back", bundle: bundle,
        comment: "Button under a page of the how-to-use guide: shows the page before.")

    /// "Done".
    static let done = LocalizedStringResource(
        "Guide: Done", defaultValue: "Done", bundle: bundle,
        comment: "Button under the last page of the how-to-use guide, in Next's place: closes the guide.")

    /// "Opens Settings.".
    static let linkHint = LocalizedStringResource(
        "Closes the guide and opens Settings.", bundle: bundle,
        comment: "VoiceOver hint of a link in the how-to-use guide: the guide closes and the app's Settings open at the page the link names.")

    /// "2 of 7".
    ///
    /// - Parameters:
    ///   - number: The page's number, from 1.
    ///   - total: The number of pages.
    /// - Returns: The page number as shown.
    static func pageNumber(_ number: Int, of total: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "\(number) of \(total)", bundle: bundle,
            comment: "Page number under the how-to-use guide, between Back and Next, such as \"2 of 7\": the page shown, of how many.")
    }

    /// "Page 2 of 7".
    ///
    /// - Parameters:
    ///   - number: The page's number, from 1.
    ///   - total: The number of pages.
    /// - Returns: The page number as VoiceOver reads it.
    static func spokenPageNumber(_ number: Int, of total: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "Page \(number) of \(total)", bundle: bundle,
            comment: "VoiceOver reading of the how-to-use guide's page number, such as \"Page 2 of 7\".")
    }

    /// What VoiceOver hears when a page shows: "Page 2 of 7: Photos as the camera took them".
    ///
    /// - Parameter page: The page.
    /// - Returns: The announcement.
    static func announcement(for page: GuidePage) -> String {
        String(
            localized: "Page \(page.number) of \(GuidePage.allCases.count): \(String(localized: page.title))", bundle: .module,
            comment: "What VoiceOver says when a page of the how-to-use guide shows: the page's number, of how many, then the page's title, such as \"Page 2 of 7: Photos as the camera took them\".")
    }

    // Page 1.

    /// "Take a photo".
    static let takePhotoTitle = LocalizedStringResource(
        "Take a photo", bundle: bundle, comment: "Title of page 1 of the how-to-use guide. A heading.")

    /// Page 1's text.
    static let takePhotoText = LocalizedStringResource(
        "Press the shutter or a volume button. Photos are saved to the Photos app.", bundle: bundle,
        comment: "Page 1 of the how-to-use guide. The shutter is the large round button; the volume buttons are the device's own. Photos is the name of Apple's app: use its name in the language's iOS.")

    // Page 2: the first key idea.

    /// "Photos as the camera took them".
    static let unprocessedTitle = LocalizedStringResource(
        "Photos as the camera took them", table: "Honesty", bundle: bundle,
        comment: "Title of page 2 of the how-to-use guide: photos are saved with as little processing as possible. A heading. Must not claim more than the English. Draft for the Honesty review.")

    /// Page 2's text.
    static let unprocessedText = LocalizedStringResource(
        "nope. saves each photo with as little processing as the camera allows, so it can look flatter or noisier at first.",
        table: "Honesty", bundle: bundle,
        comment: "Page 2 of the how-to-use guide. Keep \"nope.\" unchanged. Must not claim more than the English: as little processing as the camera allows, never none. Draft for the Honesty review.")

    /// "About processing".
    static let aboutProcessing = LocalizedStringResource(
        "About processing", bundle: bundle,
        comment: "Link on page 2 of the how-to-use guide: closes the guide and opens the Honesty page in Settings, which explains what nope. does and doesn't process.")

    // Page 3: the second key idea.

    /// "Private by design".
    static let privacyTitle = LocalizedStringResource(
        "Private by design", table: "Honesty", bundle: bundle,
        comment: "Title of page 3 of the how-to-use guide: the app's privacy. A heading. Must not claim more than the English. Draft for the Honesty review.")

    /// Page 3's text.
    static let privacyText = LocalizedStringResource(
        "nope. never connects to the internet, and you choose which details each photo keeps.", table: "Honesty", bundle: bundle,
        comment: "Page 3 of the how-to-use guide. Keep \"nope.\" unchanged. Must not claim more than the English: the app makes no network connections, and the person chooses the photo's optional details in Details in Each Photo. Draft for the Honesty review.")

    // Page 4.

    /// "Lenses".
    static let lensesTitle = LocalizedStringResource(
        "Guide: Lenses", defaultValue: "Lenses", bundle: bundle,
        comment: "Title of page 4 of the how-to-use guide: the lens buttons. A heading.")

    /// Page 4's text for the device's lenses: only what the device has is named.
    ///
    /// - Parameter lenses: What the device has.
    /// - Returns: The text.
    static func lensesText(_ lenses: GuideLenses) -> LocalizedStringResource {
        switch (lenses.offersLensChoice, lenses.hasFrontCamera) {
        case (true, true):
            LocalizedStringResource(
                "Tap a lens to switch to it. Switch Camera turns to the front camera and back.", bundle: bundle,
                comment: "Page 4 of the how-to-use guide, on a device with two or more rear lenses and a front camera. Switch Camera is the name of the round button with arrows; use its translation.")
        case (true, false):
            LocalizedStringResource(
                "Tap a lens to switch to it.", bundle: bundle,
                comment: "Page 4 of the how-to-use guide, on a device with two or more rear lenses and no front camera.")
        case (false, true):
            LocalizedStringResource(
                "Switch Camera turns to the front camera and back.", bundle: bundle,
                comment: "Page 4 of the how-to-use guide, on a device with one rear lens and a front camera. Switch Camera is the name of the round button with arrows; use its translation.")
        case (false, false):
            LocalizedStringResource(
                "nope. uses this device's one camera.", bundle: bundle,
                comment: "Page 4 of the how-to-use guide, on a device with only one camera. Keep \"nope.\" unchanged.")
        }
    }

    // Page 5.

    /// "Auto and manual".
    static let autoAndManualTitle = LocalizedStringResource(
        "Auto and manual", bundle: bundle,
        comment: "Title of page 5 of the how-to-use guide: full auto and the manual controls. A heading.")

    /// Page 5's text.
    static let autoAndManualText = LocalizedStringResource(
        "Tap Auto to set the exposure and focus yourself. Tap Manual to go back to full auto.", bundle: bundle,
        comment: "Page 5 of the how-to-use guide. Auto and Manual are the words the Manual Controls button shows on the camera; use the same translations.")

    // Page 6.

    /// "One photo or a series".
    static let driveModesTitle = LocalizedStringResource(
        "One photo or a series", bundle: bundle,
        comment: "Title of page 6 of the how-to-use guide: the drive modes. A heading.")

    /// Page 6's text.
    static let driveModesText = LocalizedStringResource(
        "Single, Timer, Burst and the other modes choose what a press does: one photo, a timer or a series.", bundle: bundle,
        comment: "Page 6 of the how-to-use guide. Single, Timer and Burst are drive mode words on the camera; use the same translations.")

    // Page 7.

    /// "Q and Settings".
    static let quickMenuTitle = LocalizedStringResource(
        "Q and Settings", bundle: bundle,
        comment: "Title of page 7 of the how-to-use guide. Q is the letter on the Quick Menu button, the same in every language; Settings is the app's settings screen.")

    /// Page 7's text.
    static let quickMenuText = LocalizedStringResource(
        "Tap Q to open the Quick Menu. Everything else is in Settings.", bundle: bundle,
        comment: "Page 7 of the how-to-use guide. Q is the letter on the button, the same in every language; Quick Menu is the button's name; Settings is the app's settings screen. Describe Q only as a button that opens the menu.")

    /// "Processed", the camera's marker on a device without Bayer RAW, for page 2's picture.
    static let processed = LocalizedStringResource(
        "Guide picture: Processed", defaultValue: "Processed", table: "Honesty", bundle: bundle,
        comment: "The camera's format status, shown in the how-to-use guide's picture on a device whose lenses can't save RAW. Use the same translation as the camera's \"Processed\" marker. Must not claim more than the English.")
}
