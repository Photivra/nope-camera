import NopeCore
import SwiftUI

/// The compare view of the comparison shot (issue #55): the app's photo and the phone's fully
/// processed version of almost the same moment, with a divider to slide between them, and their
/// metadata side by side.
///
/// It covers the whole screen while `CameraModel.comparison` is presented. It opens on the
/// pictures (the divider, a choice of the app's photo only, split or phone only, and zoom); its Details
/// button pushes a native list of the metadata, grouped by how it differs. Each side says exactly
/// what it is.
///
/// Privacy: the phone's version is shown only here and is never saved, shared or copied: the view
/// has no save, share or copy control, its text can't be selected, and its contents are hidden
/// while the app isn't the active app, so the app switcher's snapshot doesn't show them. Done
/// sends `ComparisonIntent.close`, which discards both pictures and the list.
struct ComparisonScreen: View {
    /// The camera model, whose comparison is shown.
    let model: CameraModel

    /// Whether the app is the active app; the contents are hidden otherwise.
    @Environment(\.scenePhase) private var scenePhase

    /// Creates the compare view.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The content for the comparison's state, hidden in the background.
    var body: some View {
        content
            .overlay {
                if scenePhase != .active {
                    ComparisonHiddenView()
                }
            }
            .accessibilityIdentifier("Comparison")
    }

    /// The content for the comparison's state.
    @ViewBuilder private var content: some View {
        switch model.comparison.state {
        case .ready(let result):
            ComparisonNavigation(close: close) {
                ComparisonPicturesView(result: result)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink {
                                ComparisonDetailsList(result: result)
                                    .navigationTitle(ComparisonText.details)
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbar {
                                        ToolbarItem(placement: .confirmationAction) {
                                            DoneButton(action: close)
                                        }
                                    }
                            } label: {
                                // Icon only, as the Done button: toolbar text doesn't grow with
                                // Dynamic Type; the Large Content Viewer shows the name.
                                Label {
                                    ComparisonText.details
                                } icon: {
                                    Image(systemName: "list.bullet.rectangle")
                                }
                                .labelStyle(.iconOnly)
                                .accessibilityShowsLargeContentViewer()
                            }
                        }
                    }
            }
        case .failed:
            ComparisonNavigation(close: close) {
                StatusMessageView(
                    title: Text("Nothing to Compare", bundle: .module, comment: "Title of the compare view when the phone-processed photo couldn't be taken."),
                    systemImage: "rectangle.split.2x1.slash",
                    message: Text(
                        "Your nope. photo was saved. The second photo, with the phone's processing, couldn't be taken, so there is nothing to compare. You can try again.",
                        tableName: "Honesty", bundle: .module,
                        comment: "Compare view, when the second photo of the comparison shot failed. Keep \"nope.\" unchanged. Must not claim more than the English."))
            }
        case .preparing, .idle:
            ComparisonNavigation(close: close) {
                ProgressView {
                    Text("Preparing the comparison…", bundle: .module, comment: "Shown briefly in the compare view while both photos are decoded for display.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Closes the view, discarding the comparison.
    private func close() {
        let model = model
        Task { await model.send(.comparison(.close)) }
    }
}

/// A navigation stack with the compare view's title and a Done button.
struct ComparisonNavigation<Content: View>: View {
    /// Closes the compare view.
    let close: () -> Void

    /// The content.
    let content: Content

    /// Creates the stack.
    ///
    /// - Parameters:
    ///   - close: Closes the compare view.
    ///   - content: The content.
    init(close: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.close = close
        self.content = content()
    }

    /// The stack.
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(ComparisonText.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        DoneButton(action: close)
                    }
                }
        }
    }
}

/// Covers the compare view while the app isn't the active app.
struct ComparisonHiddenView: View {
    /// Creates the cover.
    init() {}

    /// An opaque background with a short explanation.
    var body: some View {
        ZStack {
            Color(white: 0).ignoresSafeArea()
            Label {
                Text("Comparison hidden while nope. is in the background", bundle: .module, comment: "Shown over the compare view while the app isn't in front, so the app switcher doesn't show the photos. Keep \"nope.\" unchanged.")
            } icon: {
                Image(systemName: "eye.slash")
            }
            .foregroundStyle(.white)
            .padding()
        }
    }
}

/// Which picture the compare view shows.
enum ComparisonView: String, CaseIterable, Identifiable {
    /// The app's photo only.
    case nope
    /// Both, split by the divider.
    case split
    /// The phone's version only.
    case phone

    /// The case's raw value.
    var id: String { rawValue }
}

/// The pictures: both photos lined up, with the divider, the view choice, zoom, and what
/// each side is.
struct ComparisonPicturesView: View {
    /// The comparison.
    let result: PhotoComparison

    /// The divider's place: the share of the width that shows the app's photo, from 0 to 1.
    @State private var split = 0.5

    /// The zoom, from 1 (the whole photo) to ``maximumZoom``.
    @State private var zoom = 1.0

    /// The zoom at the start of a pinch.
    @State private var pinchStartZoom: Double?

    /// The pan while zoomed, in points.
    @State private var pan = CGSize.zero

    /// The pan at the start of a drag.
    @State private var dragStartPan: CGSize?

    /// The app's photo as an image, made once when the pictures appear.
    @State private var nopePicture: Image?

    /// The phone's version as an image, made once when the pictures appear.
    @State private var phonePicture: Image?

    /// Whether the images have been made.
    @State private var hasPictures = false

    /// The height of the scroll view, to keep the controls in view below the pictures.
    @State private var viewportHeight: CGFloat = 0

    /// The height of the controls below the pictures.
    @State private var controlsHeight: CGFloat = 0

    /// The window's horizontal size class: the pictures' height is limited only in a regular
    /// width window (iPad).
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The largest zoom: 4×, enough to see noise and sharpening at the photos' full size.
    static let maximumZoom = 4.0

    /// One step of the zoom buttons.
    static let zoomStep = 1.0

    /// One step of the divider for VoiceOver and the keyboard: a tenth of the width.
    static let splitStep = 0.1

    /// Creates the pictures.
    ///
    /// - Parameter result: The comparison.
    init(result: PhotoComparison) {
        self.result = result
    }

    /// The view choice that matches the divider.
    private var view: ComparisonView {
        switch split {
        case 1: .nope
        case 0: .phone
        default: .split
        }
    }

    /// The pictures above the controls, scrolling at large text sizes.
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                pictures
                    // The pictures are laid out left to right in every language: nope.'s photo
                    // on the left, as its label says. Text elsewhere follows the language.
                    .environment(\.layoutDirection, .leftToRight)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxWidth: maximumPictureWidth)
                    .frame(maxWidth: .infinity)
                controls
                    .padding(.horizontal)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                ComparisonSidesDescription(result: result)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
        } action: { viewportHeight = $0 }
        .task {
            // Made once: each image holds the photo's full-size pixels.
            nopePicture = result.nopeImage.flatMap(Image.photo)
            phonePicture = result.phoneImage.flatMap(Image.photo)
            hasPictures = true
        }
    }

    /// The widest the pictures may be in a regular width window (iPad): narrow enough for their
    /// full height to leave the controls in view below them; a full-width portrait photo pushed
    /// the divider's slider and the zoom buttons off screen there. At least half the scroll
    /// view's height, so at large text sizes the pictures stay large and the screen scrolls
    /// instead. On iPhone the pictures keep the full width.
    private var maximumPictureWidth: CGFloat {
        guard horizontalSizeClass == .regular, viewportHeight > 0 else { return .infinity }
        // The vertical padding and the space between the pictures and the controls.
        let spacing: CGFloat = 16 * 3
        let height = max(viewportHeight - controlsHeight - spacing, viewportHeight / 2)
        return height * aspectRatio
    }

    /// The photos' width over their height, from the app's picture, else the phone's, else 3:4.
    private var aspectRatio: CGFloat {
        let image = result.nopeImage ?? result.phoneImage
        guard let image else { return 3.0 / 4.0 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    /// Both photos, the app's over the phone's and cut off at the divider, with their labels.
    private var pictures: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                picture(phonePicture, mirrored: result.mirrorsPhoneImage)
                picture(nopePicture, mirrored: false)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * split)
                    }
                divider(width: width)
                labels
            }
            .clipped()
            .contentShape(.rect)
            .coordinateSpace(.named(Self.space))
            .gesture(panGesture)
            .simultaneousGesture(pinchGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Comparison", bundle: .module, comment: "VoiceOver name of the compare view's picture: nope.'s photo and the phone-processed version, split by a divider. Swipe up or down to move the divider."))
            .accessibilityValue(splitValue)
            .accessibilityIdentifier("ComparisonPicture")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: setSplit(split + Self.splitStep)
                case .decrement: setSplit(split - Self.splitStep)
                @unknown default: break
                }
            }
            .accessibilityZoomAction { action in
                setZoom(zoom + (action.direction == .zoomIn ? Self.zoomStep : -Self.zoomStep))
            }
        }
    }

    /// One photo, filling the frame, zoomed and panned with the other.
    ///
    /// - Parameters:
    ///   - picture: The photo, or `nil` when it couldn't be shown.
    ///   - mirrored: Whether to mirror it to line it up with the other.
    @ViewBuilder private func picture(_ picture: Image?, mirrored: Bool) -> some View {
        if let picture {
            picture
                .resizable()
                .scaledToFit()
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .scaleEffect(zoom)
                .offset(pan)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !hasPictures {
            Color(white: 0.15)
        } else {
            ZStack {
                Color(white: 0.15)
                Text("Picture unavailable", bundle: .module, comment: "Shown in the compare view where a photo couldn't be decoded for display.")
                    .foregroundStyle(.white)
            }
        }
    }

    /// The divider line with its handle, at the divider's place.
    ///
    /// - Parameter width: The pictures' width.
    private func divider(width: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 2)
            Image(systemName: "arrow.left.and.right.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .white)
                .frame(width: CameraStyle.minimumTarget, height: CameraStyle.minimumTarget)
                .contentShape(.rect)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { value in
                        setSplit(value.location.x / max(width, 1))
                    })
        }
        .frame(width: CameraStyle.minimumTarget)
        .frame(maxHeight: .infinity)
        .offset(x: width * split - CameraStyle.minimumTarget / 2)
        .opacity(view == .split ? 1 : 0)
    }

    /// The coordinate space of the pictures, for the divider's drag.
    private static let space = "ComparisonPictures"

    /// The two labels, on the photos' top corners.
    private var labels: some View {
        HStack(alignment: .top) {
            ComparisonSideLabel(text: ComparisonText.nopeSide)
                .opacity(view == .phone ? 0 : 1)
            Spacer(minLength: 8)
            ComparisonSideLabel(text: ComparisonText.phoneSide)
                .opacity(view == .nope ? 0 : 1)
        }
        .padding(8)
    }

    /// The view choice and the zoom buttons.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CameraStyle.targetSpacing) { viewButtons }
                VStack(alignment: .leading, spacing: CameraStyle.targetSpacing) { viewButtons }
            }
            Slider(value: Binding(get: { split }, set: { setSplit($0) }), in: 0...1) {
                Text("Divider", bundle: .module, comment: "Name of the slider in the compare view that moves the divider between nope.'s photo and the phone-processed version.")
            }
            .accessibilityValue(splitValue)
            .nightModeTrackTint()
            HStack(spacing: CameraStyle.targetSpacing) {
                Button {
                    setZoom(zoom - Self.zoomStep)
                } label: {
                    Label {
                        Text("Zoom Out", bundle: .module, comment: "Button in the compare view: shows more of both photos.")
                    } icon: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                }
                .accessibilityValue(zoomText)
                Text(verbatim: zoomText)
                    .monospacedDigit()
                    .fixedSize()
                    .accessibilityHidden(true)
                Button {
                    setZoom(zoom + Self.zoomStep)
                } label: {
                    Label {
                        Text("Zoom In", bundle: .module, comment: "Button in the compare view: enlarges both photos together, to see detail, noise and sharpening.")
                    } icon: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                }
                .accessibilityValue(zoomText)
            }
            .buttonStyle(.bordered)
            .font(.title3)
        }
    }

    /// One button per view choice, filled white when chosen.
    @ViewBuilder private var viewButtons: some View {
        ForEach(ComparisonView.allCases) { choice in
            Button {
                switch choice {
                case .nope: setSplit(1)
                case .split: setSplit(0.5)
                case .phone: setSplit(0)
                }
            } label: {
                ComparisonText.name(of: choice)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(SelectableCapsuleStyle(isSelected: view == choice))
            .accessibilityAddTraits(view == choice ? .isSelected : [])
        }
    }

    /// The zoom as text, such as "2×".
    private var zoomText: String {
        zoom.formatted(.number.precision(.fractionLength(0...1))) + "×"
    }

    /// The divider's place for VoiceOver, such as "Split: 60% nope., 40% phone processing".
    private var splitValue: Text {
        switch view {
        case .nope, .phone: ComparisonText.name(of: view)
        case .split:
            Text(
                "Split: \(split.formatted(.percent.precision(.fractionLength(0)))) nope., \((1 - split).formatted(.percent.precision(.fractionLength(0)))) phone processing",
                bundle: .module,
                comment: "VoiceOver value of the compare view's divider: how much of the width shows nope.'s photo and how much the phone-processed version, such as 60% and 40%. Keep \"nope.\" unchanged.")
        }
    }

    /// Pans both photos while zoomed.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard zoom > 1 else { return }
                let start = dragStartPan ?? pan
                dragStartPan = start
                pan = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
            }
            .onEnded { _ in dragStartPan = nil }
    }

    /// Zooms both photos together.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStartZoom ?? zoom
                pinchStartZoom = start
                setZoom(start * value.magnification)
            }
            .onEnded { _ in pinchStartZoom = nil }
    }

    /// Moves the divider, kept between 0 and 1.
    ///
    /// - Parameter value: The new place.
    private func setSplit(_ value: Double) {
        split = min(max(value, 0), 1)
    }

    /// Changes the zoom, kept between 1 and ``maximumZoom``; at 1 the pan returns to the center.
    ///
    /// - Parameter value: The new zoom.
    private func setZoom(_ value: Double) {
        zoom = min(max(value, 1), Self.maximumZoom)
        if zoom == 1 { pan = .zero }
    }
}

/// A side's label on the pictures: white text on a dark backing.
struct ComparisonSideLabel: View {
    /// The label.
    let text: Text

    /// Creates the label.
    ///
    /// - Parameter text: The label.
    init(text: Text) {
        self.text = text
    }

    /// The label.
    var body: some View {
        text
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .darkBacking()
    }
}

/// What each side of the comparison is, in plain words, and that the phone's version isn't saved.
struct ComparisonSidesDescription: View {
    /// The comparison.
    let result: PhotoComparison

    /// Creates the description.
    ///
    /// - Parameter result: The comparison.
    init(result: PhotoComparison) {
        self.result = result
    }

    /// One paragraph per side.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ComparisonText.nopeSide.font(.headline)
                if let file = result.nopeFile {
                    Text(verbatim: FormatsSettingsView.name(of: file.format))
                    PhotoDetailsSections.processing(file.processing)
                        .foregroundStyle(CameraStyle.secondaryText)
                    if file.format == .raw {
                        Text("Shown here as iOS displays RAW files.", tableName: "Honesty", bundle: .module, comment: "Compare view, when only the RAW was saved: the RAW is displayed with the system's own RAW decoding, not developed by nope. RAW is a file format name; iOS is a product name.")
                            .foregroundStyle(CameraStyle.secondaryText)
                    }
                }
                Text("Saved to Photos.", bundle: .module, comment: "Compare view: nope.'s photo, on one side, was saved to the photo library. Photos is the system photo library app.")
                    .foregroundStyle(CameraStyle.secondaryText)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 4) {
                ComparisonText.phoneSide.font(.headline)
                Text(verbatim: FormatsSettingsView.name(of: result.phoneFormat))
                Text(
                    "A second photo, started \(PhotoDetailsSections.milliseconds(result.secondPhotoDelay)) after nope.'s, with the processing iOS applies when an app asks for the highest quality. It may combine several frames, and it may differ from what other camera apps save.",
                    tableName: "Honesty", bundle: .module,
                    comment: "Compare view: what the phone-processed side is. The value is a time such as 850 ms. Keep \"nope.\" unchanged. Must not claim more than the English.")
                    .foregroundStyle(CameraStyle.secondaryText)
                Text("Not saved: it is discarded when you close this view.", tableName: "Honesty", bundle: .module, comment: "Compare view: the phone-processed photo is never saved and is discarded on Done. Must not claim more than the English.")
                    .foregroundStyle(CameraStyle.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The details: the metadata of the app's file and the phone's version, grouped by how they
/// differ, with identifying values hidden until the person asks.
struct ComparisonDetailsList: View {
    /// The comparison.
    let result: PhotoComparison

    /// The entries whose hidden values the person chose to see. On screen only; forgotten when
    /// the view closes.
    @State private var revealed: Set<String> = []

    /// Creates the list.
    ///
    /// - Parameter result: The comparison.
    init(result: PhotoComparison) {
        self.result = result
    }

    /// One section per kind of difference that has entries.
    var body: some View {
        List {
            Section {
                Text("What each file holds, read on this device. Values are shown on this screen only: nothing is stored or copied.", tableName: "Honesty", bundle: .module, comment: "Introduction of the compare view's Details tab. Must not claim more than the English.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(MetadataComparison.Difference.allCases, id: \.self) { difference in
                let entries = result.metadata.entries(difference)
                if !entries.isEmpty {
                    Section {
                        ForEach(entries) { entry in
                            ComparisonEntryRow(
                                entry: entry, isRevealed: revealed.contains(entry.id),
                                reveal: { revealed.insert(entry.id) })
                        }
                    } header: {
                        ComparisonText.heading(of: difference)
                    }
                }
            }
        }
    }
}

/// One metadata item: its name, each file's value, and why it matters.
struct ComparisonEntryRow: View {
    /// The item.
    let entry: MetadataComparison.Entry

    /// Whether its identifying value is shown.
    let isRevealed: Bool

    /// Shows its identifying value.
    let reveal: () -> Void

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - entry: The item.
    ///   - isRevealed: Whether its identifying value is shown.
    ///   - reveal: Shows its identifying value.
    init(entry: MetadataComparison.Entry, isRevealed: Bool, reveal: @escaping () -> Void) {
        self.entry = entry
        self.isRevealed = isRevealed
        self.reveal = reveal
    }

    /// Whether the values are hidden.
    private var isMasked: Bool {
        entry.isIdentifying && !isRevealed && [entry.phoneValue, entry.nopeValue].contains { ComparisonText.hasReadableValue($0) }
    }

    /// The row.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                // Specification names (tags, blocks, properties) aren't translated.
                Text(verbatim: entry.isSignature ? ComparisonText.signatureName : entry.name)
                    .font(.body.monospaced())
                if let value = entry.phoneValue {
                    Text("Phone: \(ComparisonText.describe(value, masked: isMasked))", bundle: .module, comment: "Compare view: the value the phone-processed version holds for a metadata item.")
                        .foregroundStyle(CameraStyle.secondaryText)
                }
                if let value = entry.nopeValue {
                    Text("nope.: \(ComparisonText.describe(value, masked: isMasked))", bundle: .module, comment: "Compare view: the value nope.'s saved file holds for a metadata item. Keep \"nope.\" unchanged.")
                        .foregroundStyle(CameraStyle.secondaryText)
                }
                explanation
                    .font(.footnote)
                    .foregroundStyle(CameraStyle.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityHint(ComparisonText.heading(of: entry.difference))
            if isMasked {
                Button(action: reveal) {
                    Text("Show Value", bundle: .module, comment: "Button in the compare view: shows a hidden identifying value, such as a unique photo ID, on screen.")
                }
                .buttonStyle(.borderless)
                .frame(minHeight: CameraStyle.minimumTarget)
            }
        }
    }

    /// Why the item matters: its privacy switch and explanation, that it is the app's signature,
    /// or that the app never writes it.
    @ViewBuilder private var explanation: some View {
        if entry.isSignature {
            Text("nope.'s Content Credentials signature.", tableName: "Honesty", bundle: .module, comment: "Compare view: this item of nope.'s file is its Content Credentials signature. Keep \"nope.\" unchanged.")
        } else if let item = entry.item {
            // The privacy setting that controls the item, with its explanation from Settings.
            VStack(alignment: .leading, spacing: 2) {
                Text(PrivacySettingsView.title(of: item)).fontWeight(.semibold)
                Text(PrivacySettingsView.explanation(of: item))
            }
        } else if entry.difference == .onlyInPhoneVersion {
            Text("nope. never writes this.", tableName: "Honesty", bundle: .module, comment: "Compare view, for a metadata item only the phone-processed version holds and that no nope. setting can turn on: nope.'s allowlist never writes it. Keep \"nope.\" unchanged. Must not claim more than the English.")
        }
    }
}

/// The compare view's words.
enum ComparisonText {
    /// The view's title.
    static var title: Text {
        Text("Compare", bundle: .module, comment: "Title of the compare view, and the camera switch and its Voice Control name that turns the comparison shot on: nope.'s photo next to the phone-processed version, which isn't saved.")
    }

    /// The name of the details list, and of the button that opens it.
    static var details: Text {
        Text("Details", bundle: .module, comment: "Button and screen title in the compare view: the metadata of nope.'s photo and of the phone-processed version, side by side.")
    }

    /// The label of the app's side.
    static var nopeSide: Text {
        Text(verbatim: "nope.")
    }

    /// The label of the phone's side.
    static var phoneSide: Text {
        Text("Phone Processing", bundle: .module, comment: "Compare view: the label of the side that shows the photo with the phone's full processing, which isn't saved.")
    }

    /// The name of the signature item.
    static var signatureName: String { "C2PA" }

    /// A view choice's name.
    ///
    /// - Parameter view: The choice.
    static func name(of view: ComparisonView) -> Text {
        switch view {
        case .nope: Text("nope. Only", bundle: .module, comment: "Button in the compare view: shows only nope.'s photo. Keep \"nope.\" unchanged.")
        case .split: Text("Split", bundle: .module, comment: "Button in the compare view: shows nope.'s photo and the phone-processed version side by side, split by a divider.")
        case .phone: Text("Phone Only", bundle: .module, comment: "Button in the compare view: shows only the phone-processed version.")
        }
    }

    /// A group's heading.
    ///
    /// - Parameter difference: The difference.
    static func heading(of difference: MetadataComparison.Difference) -> Text {
        switch difference {
        case .onlyInPhoneVersion: Text("Only in Phone Version", tableName: "Honesty", bundle: .module, comment: "Heading in the compare view's details, also spoken for each item: metadata only the phone-processed version holds.")
        case .different: Text("Different", tableName: "Honesty", bundle: .module, comment: "Heading in the compare view's details, also spoken for each item: metadata both files hold, with different values.")
        case .onlyInNopeFile: Text("Only in nope.'s File", tableName: "Honesty", bundle: .module, comment: "Heading in the compare view's details, also spoken for each item: metadata only nope.'s saved file holds, such as its signature. Keep \"nope.\" unchanged.")
        case .same: Text("Same in Both", tableName: "Honesty", bundle: .module, comment: "Heading in the compare view's details, also spoken for each item: metadata both files hold with the same value.")
        }
    }

    /// Whether a value has something to hide: text or numbers.
    ///
    /// - Parameter value: The value, or `nil`.
    static func hasReadableValue(_ value: MetadataComparison.Value?) -> Bool {
        switch value {
        case .text, .numbers: true
        case .count, .present, .none: false
        }
    }

    /// A value as text, or "Hidden" when masked.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - masked: Whether to hide it.
    static func describe(_ value: MetadataComparison.Value, masked: Bool) -> String {
        if masked && hasReadableValue(value) {
            return String(localized: "Hidden", bundle: .module, comment: "Compare view: an identifying value, such as a unique photo ID, hidden until the person taps Show Value.")
        }
        switch value {
        case .text(let text):
            return text
        case .numbers(let numbers):
            return numbers.map { $0.formatted(.number.grouping(.never).precision(.significantDigits(1...6))) }
                .formatted(.list(type: .and, width: .narrow))
        case .count(let count):
            return String(localized: "Count: \(count)", bundle: .module, comment: "Compare view: how many times a container block appears in a file.")
        case .present:
            return String(localized: "Present, no readable value", bundle: .module, comment: "Compare view: the file holds this metadata item, but its bytes have no value nope. can show, such as maker notes. Keep \"nope.\" unchanged if it appears.")
        }
    }
}

/// The comparison shot's camera controls: the tray switch, the state pill and the hint.
extension QuickControls {
    /// Compare: the comparison shot (issue #55). Shown where the device can take it.
    ///
    /// - Parameter context: The model and settings.
    static func compare(_ context: CameraControlContext) -> QuickControlItem? {
        let comparison = context.model.comparison
        guard comparison.isAvailable else { return nil }
        return QuickControlItem(
            id: "compare", title: ComparisonText.title, systemImage: "rectangle.split.2x1",
            kind: .toggle(isOn: comparison.isOn) { context.send(.comparison(.setOn($0))) })
    }
}

extension StatePills {
    /// The comparison shot, while it is on.
    ///
    /// - Parameter context: The model and settings.
    static func compare(_ context: CameraControlContext) -> StatePill? {
        guard context.model.comparison.isOn else { return nil }
        return StatePill(
            id: "compare", systemImage: "rectangle.split.2x1", text: ComparisonText.title, label: ComparisonText.title,
            actions: [
                StatePill.Action(
                    id: "off", title: Text("Turn Off Compare", bundle: .module, comment: "Action of the Compare pill on the camera: turns the comparison shot off.")
                ) {
                    context.send(.comparison(.setOn(false)))
                }
            ])
    }
}

/// The hint before a comparison shot: two photos are taken, so hold still.
struct ComparisonHint: View {
    /// The camera model.
    let model: CameraModel

    /// Creates the hint.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The hint, while the next photo is a comparison shot.
    var body: some View {
        if model.comparisonAppliesToNextPhoto {
            HintLabel(
                systemImage: "rectangle.split.2x1",
                text: String(
                    localized: "Hold the camera steady or use a tripod. Two photos are taken, a moment apart.", bundle: .module,
                    comment: "Hint on the camera while the comparison shot is on: nope. takes its photo and then one with the phone's processing."))
        }
    }
}

/// Covers the screen with the compare view while the comparison is presented.
///
/// The cover follows the model on the main actor's next turn, through its own state: presented
/// in the same update as the saved photo's status, the camera's reaction to that status (the
/// thumbnail and the "saved" announcement) was dropped as the cover hid the camera (issue #55).
struct ComparisonCover: ViewModifier {
    /// The camera model.
    let model: CameraModel

    /// Whether night mode is on, so the view is red too.
    let isNightMode: Bool

    /// Whether the cover is shown.
    @State private var isShown = false

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - isNightMode: Whether night mode is on.
    init(model: CameraModel, isNightMode: Bool) {
        self.model = model
        self.isNightMode = isNightMode
    }

    /// The content with the cover.
    ///
    /// - Parameter content: The camera.
    func body(content: Content) -> some View {
        content
            .onChange(of: model.comparison.isPresented, initial: true) {
                // On the main actor's next turn, after this update has been applied.
                let model = model
                Task { @MainActor in isShown = model.comparison.isPresented }
            }
            // The camera's elements changed while they were covered (the new thumbnail); tell
            // VoiceOver and the other assistive technologies to read the screen again.
            .fullScreenCover(isPresented: $isShown, onDismiss: { AccessibilityNotification.ScreenChanged().post() }) {
                ComparisonScreen(model: model)
                    .nightModeStyle(isNightMode)
            }
            .onChange(of: isShown) { _, isShown in
                if !isShown && model.comparison.isPresented { Task { await model.send(.comparison(.close)) } }
            }
    }
}

extension View {
    /// Covers the screen with the compare view while the comparison is presented
    /// (``ComparisonCover``).
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - isNightMode: Whether night mode is on, so the view is red too.
    func comparisonCover(_ model: CameraModel, isNightMode: Bool) -> some View {
        modifier(ComparisonCover(model: model, isNightMode: isNightMode))
    }
}
