import NopeCore
import SwiftUI

/// The words for each capture result. The signature and privacy wording lives in
/// `Honesty.xcstrings`; a missing signature is always stated, never hidden (issue #1).
enum CaptureMessages {
    /// The message for a failed capture or save.
    ///
    /// - Parameter error: What went wrong.
    /// - Returns: The message, a whole sentence.
    static func message(for error: CaptureError) -> String {
        switch error {
        case .notRunning:
            String(localized: "No photo was taken: the camera is paused.", bundle: .module, comment: "Shown when the shutter is pressed while the camera is paused.")
        case .configurationFailed, .captureFailed:
            String(localized: "The photo wasn't taken. Try again.", bundle: .module, comment: "Shown when taking a photo failed.")
        case .blankPicture:
            String(localized: "No photo was taken: the camera sent a blank picture.", bundle: .module, comment: "Shown when the camera delivered a completely blank picture, so the app discarded it.")
        case .developmentFailed:
            String(localized: "Not saved: the photo couldn't be developed. Try again.", bundle: .module, comment: "Shown when the app couldn't turn the RAW photo into a HEIF or JPEG file, so nothing was saved. HEIF and JPEG are not mentioned to keep it short.")
        case .metadataNotAllowed:
            String(localized: "Not saved: nope. couldn't confirm that the photo holds only the details you chose.", table: "Honesty", bundle: .module, comment: "Shown when a finished photo file contained a metadata detail that is not on the privacy list, or couldn't be checked, so the app saved nothing. Honesty and privacy wording. Keep the name nope. unchanged, lowercase with its period.")
        case .photosAccessDenied:
            String(localized: "Not saved: nope. isn't allowed to add photos. You can allow it in the Settings app.", bundle: .module, comment: "Shown when the person hasn't allowed the app to add photos to their photo library. Keep the name nope. unchanged, lowercase with its period.")
        case .saveFailed:
            String(localized: "Not saved: the photo library couldn't add the photo. Try again.", bundle: .module, comment: "Shown when the system photo library reported an error while adding the photo.")
        case .bracketNotReady:
            String(localized: "No photos were taken: the camera wasn't ready for the bracket. Try again.", bundle: .module, comment: "Shown when the shutter was pressed with an exposure bracket on, but the camera had not yet measured the exposure the bracket's photos are planned around (for example just after switching lenses), so nothing was taken.")
        case .savingUnavailable:
            String(localized: "Not saved: this version of the app can't save photos.", bundle: .module, comment: "Shown when this build of the app has no way to save photos, for example in a preview.")
        }
    }

    /// The message for saved photos: how many were saved and signed, or, when one isn't signed,
    /// why, as for a single photo. A missing signature is never hidden.
    ///
    /// - Parameter photos: The saved photos: one, or a bracket's frames.
    /// - Returns: The message.
    static func message(forSaved photos: [SavedPhoto]) -> String {
        if let unsigned = photos.first(where: { $0.signature != .signed }) {
            return message(for: unsigned.signature)
        }
        guard photos.count > 1 else { return message(for: .signed) }
        return String(
            localized: "\(photos.count) photos saved and signed.", table: "Honesty", bundle: .module,
            comment: "Shown after an exposure bracket: each frame was added to the photo library as its own photo, each with a Content Credentials signature. The number is the count of photos, at least 3. Honesty wording: says only that they were saved and signed.")
    }

    /// The message for a saved photo: signed, or not signed with the reason.
    ///
    /// - Parameter signature: The photo's signature status.
    /// - Returns: The message.
    static func message(for signature: SignatureStatus) -> String {
        switch signature {
        case .signed:
            String(localized: "Saved and signed.", table: "Honesty", bundle: .module, comment: "Shown after a photo was added to the photo library with a Content Credentials signature in every file. Honesty wording: says only that it was saved and signed.")
        case .unsigned(.turnedOff):
            String(localized: "Saved. Not signed: signing is off in Settings.", table: "Honesty", bundle: .module, comment: "Shown after a photo was saved without a Content Credentials signature because the person turned signing off in the app's settings. Honesty wording: never imply the photo is signed.")
        case .unsigned(.unavailable):
            String(localized: "Saved. Not signed: this version of the app can't sign photos.", table: "Honesty", bundle: .module, comment: "Shown after a photo was saved without a Content Credentials signature because this build of the app has no signer, for example a preview or a different interface built on NopeCore. Honesty wording: never imply the photo is signed.")
        case .unsigned(.failed):
            String(localized: "Saved. Not signed: the signature couldn't be created.", table: "Honesty", bundle: .module, comment: "Shown after a photo was saved without a Content Credentials signature because creating the signature failed. Honesty wording: never imply the photo is signed.")
        case .unsigned(.signedFileFailedCheck):
            String(localized: "Saved. Not signed: the signed file didn't pass the check.", table: "Honesty", bundle: .module, comment: "Shown after a photo was saved without a Content Credentials signature because the signed file failed the app's final check (for example, the system couldn't open it), so the unsigned file, which passed, was saved instead. Honesty wording: never imply the photo is signed.")
        }
    }

    /// The photos a status reports as saved, or `nil` when it reports no save.
    ///
    /// - Parameter status: A capture status.
    static func savedPhotos(in status: CaptureStatus) -> [SavedPhoto]? {
        switch status {
        case .saved(let photo): [photo]
        case .savedBracket(let photos): photos
        case .savedBurst(let photos): photos
        default: nil
        }
    }

    /// The error a status reports, or `nil` when it reports none.
    ///
    /// - Parameter status: A capture status.
    static func error(in status: CaptureStatus) -> CaptureError? {
        if case .failed(let error) = status { error } else { nil }
    }
}

/// What a failure banner's one button does.
enum FailureAction: Equatable {
    /// Takes the photo again.
    case tryAgain

    /// Opens the app's page in the Settings app, where Photos access is allowed.
    case openSettings

    /// The action for an error, or `nil` when pressing a button wouldn't help: the camera is
    /// paused (its own message says why), the picture is blank (the camera says to restart the
    /// device), or this build can't save.
    ///
    /// - Parameter error: What went wrong.
    init?(for error: CaptureError) {
        switch error {
        case .photosAccessDenied: self = .openSettings
        case .configurationFailed, .captureFailed, .bracketNotReady, .developmentFailed, .metadataNotAllowed, .saveFailed:
            self = .tryAgain
        case .notRunning, .blankPicture, .savingUnavailable: return nil
        }
    }
}

/// The banner for a failed capture or save (issue #68, "Feedback tiers"; docs/design/BUILD-SPEC.md,
/// 3.7): it stays until it is dismissed or the next photo is saved, takes VoiceOver focus when it
/// appears, and offers one action, Try Again or Open Settings. It sits on the picture's upper
/// edge on solid black inside an amber outline, the sentence leading and the buttons trailing;
/// at accessibility text sizes the buttons go below the sentence, which wraps onto as many lines
/// as it needs.
struct FailureBanner: View {
    /// What went wrong.
    let error: CaptureError

    /// Whether the shutter can take a photo now, for Try Again.
    let canCapture: Bool

    /// Takes the photo again.
    let tryAgain: () -> Void

    /// Hides the banner.
    let dismiss: () -> Void

    /// How far a bracket got when one of its frames couldn't be saved, or `nil`: the banner then
    /// starts with "Bracket stopped: 2 of 3 photos saved." and offers only Dismiss, since taking
    /// the bracket again would save the frames already saved a second time
    /// (docs/design/BRACKETING.md, section 4).
    let failedBracket: BracketProgress?

    /// Opens Settings, or `nil` when the app can't.
    @Environment(\.openAppSettings) private var openAppSettings

    /// The current text size: at accessibility sizes the buttons go below the sentence.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Whether VoiceOver focus is on the banner.
    @AccessibilityFocusState private var isFocused: Bool

    /// Creates the banner.
    ///
    /// - Parameters:
    ///   - error: What went wrong.
    ///   - canCapture: Whether the shutter can take a photo now.
    ///   - tryAgain: Takes the photo again.
    ///   - dismiss: Hides the banner.
    ///   - failedBracket: How far a bracket got when a frame couldn't be saved, or `nil`.
    init(
        error: CaptureError, canCapture: Bool, tryAgain: @escaping () -> Void, dismiss: @escaping () -> Void,
        failedBracket: BracketProgress? = nil
    ) {
        self.error = error
        self.canCapture = canCapture
        self.tryAgain = tryAgain
        self.dismiss = dismiss
        self.failedBracket = failedBracket
    }

    /// The banner's sentence: what went wrong, after how far a bracket got.
    private var message: String {
        let reason = CaptureMessages.message(for: error)
        guard let failedBracket else { return reason }
        return "\(BracketText.stopped(failedBracket)) \(reason)"
    }

    /// The banner.
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: NopeSpace.xs) {
                    sentence
                    HStack(spacing: NopeSpace.xs) {
                        actionButton
                        Spacer(minLength: 0)
                        dismissButton
                    }
                }
            } else {
                HStack(alignment: .center, spacing: NopeSpace.s) {
                    sentence
                    VStack(alignment: .trailing, spacing: NopeSpace.xs) {
                        actionButton
                        dismissButton
                    }
                    .fixedSize()
                }
            }
        }
        .padding(.vertical, NopeSpace.s)
        .padding(.leading, NopeSpace.m)
        .padding(.trailing, NopeSpace.s)
        .nopeBackground(.solid, in: RoundedRectangle(cornerRadius: NopeRadius.large))
        .overlay(RoundedRectangle(cornerRadius: NopeRadius.large).strokeBorder(CameraStyle.warning, lineWidth: NopeSize.warningOutline))
        .accessibilityElement(children: .contain)
        .onAppear { isFocused = true }
        .onChange(of: error) { isFocused = true }
    }

    /// The triangle and what went wrong.
    private var sentence: some View {
        HStack(alignment: .firstTextBaseline, spacing: NopeSpace.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CameraStyle.warning)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(NopeColor.label)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityFocused($isFocused)
        }
    }

    /// Hides the banner.
    private var dismissButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
        }
        .buttonStyle(NopeIconButtonStyle(size: NopeSize.capsule))
        .accessibilityLabel(Text("Dismiss", bundle: .module, comment: "Button that closes the message about a photo that wasn't taken or saved."))
        .accessibilityShowsLargeContentViewer {
            Label {
                Text("Dismiss", bundle: .module, comment: "Button that closes the message about a photo that wasn't taken or saved.")
            } icon: {
                Image(systemName: "xmark")
            }
        }
    }

    /// Try Again or Open Settings, or nothing.
    @ViewBuilder private var actionButton: some View {
        switch failedBracket == nil ? FailureAction(for: error) : nil {
        case .tryAgain:
            Button(action: tryAgain) {
                Text("Try Again", bundle: .module, comment: "Button on the message about a photo that wasn't taken or saved: takes the photo again.")
            }
            .buttonStyle(NopeCapsuleStyle(isCompact: true))
            .disabled(!canCapture)
        case .openSettings:
            if let openAppSettings {
                Button {
                    openAppSettings()
                } label: {
                    Text("Open Settings", bundle: .module, comment: "Button that opens nope.'s page in the system Settings app, where camera or photo library access can be allowed. Keep \"nope.\" unchanged.")
                }
                .buttonStyle(NopeCapsuleStyle(isCompact: true))
            }
        case nil:
            EmptyView()
        }
    }
}

/// What the Last Photo spot beside the shutter holds (docs/design/device-feedback-1.0.md,
/// section 1).
enum LastPhotoSpot: Equatable {
    /// Nothing: in clean view (Show Controls has the spot), during a countdown or series before
    /// the first photo, or where Photos can't be opened (the Lock Screen camera).
    case nothing

    /// Open Photos, which opens the Photos app: before the first photo since the app opened.
    case openPhotos

    /// The spinner, while a photo is taken or saved.
    case saving

    /// The last photo, which opens the Last Photo viewer.
    case lastPhoto

    /// What the spot holds.
    ///
    /// - Parameters:
    ///   - hasPhotos: Whether a photo was saved since the app opened.
    ///   - isBusy: Whether a photo is being taken or saved now.
    ///   - isSeriesRunning: Whether a countdown or series runs or is paused: leaving the app for
    ///     Photos would interrupt it.
    ///   - isCleanView: Whether clean view hides the controls.
    ///   - canOpenPhotos: Whether the app can open Photos (not in the Lock Screen camera).
    /// - Returns: The content.
    static func content(
        hasPhotos: Bool, isBusy: Bool, isSeriesRunning: Bool, isCleanView: Bool, canOpenPhotos: Bool
    ) -> LastPhotoSpot {
        if isCleanView { return .nothing }
        if isBusy { return .saving }
        if hasPhotos { return .lastPhoto }
        return !isSeriesRunning && canOpenPhotos ? .openPhotos : .nothing
    }
}

/// The last-photo slot beside the shutter (issue #68, "Feedback tiers"). Before the first photo
/// since the app opened, it holds Open Photos, which opens the Photos app; where Photos can't be
/// opened, or while a countdown or series runs, it is empty, never an empty square
/// (docs/design/device-feedback-1.0.md, section 1). Then it shows the last photo with
/// a teal seal when every file was signed, or an amber mark when signing was on and a file
/// couldn't be signed. With signing off by choice it has no badge (docs/design/BUILD-SPEC.md, 3.3
/// and 3.7): that isn't a warning, and its value still says "Saved. Not signed: signing is off in
/// Settings."
///
/// With ``image``, it shows the photo itself (issue #36), made in memory from the saved file;
/// without one, a photo symbol. With ``openViewer`` it is a button: a tap opens the Last Photo
/// viewer (docs/design/BUILD-SPEC.md, 3.14). VoiceOver and Voice Control also offer Open in Photos
/// and Photo Details as actions, so both are one action away without opening the viewer; there
/// is no touch-and-hold menu (decision V3).
struct ThumbnailSlot: View {
    /// The photos saved by the last press of the shutter, or `nil` before the first.
    let photos: [SavedPhoto]?

    /// The photo's thumbnail, or `nil` to show a photo symbol.
    let image: Image?

    /// Whether a photo is being taken or saved now.
    let isBusy: Bool

    /// Opens the Last Photo viewer, or `nil` for none.
    let openViewer: (() -> Void)?

    /// Opens Photos, or `nil` when the app can't.
    let openPhoto: (() -> Void)?

    /// Shows the photo's details (issue #53), or `nil` for none.
    let showDetails: (() -> Void)?

    /// Whether a countdown or series runs or is paused, so Open Photos isn't offered.
    let isSeriesRunning: Bool

    /// The slot's side, in points: larger than the 44-point minimum, smaller than the shutter
    /// (``NopeSize/thumbnail``).
    static var side: CGFloat { NopeSize.thumbnail }

    /// The mark on the thumbnail's corner.
    enum Badge: Equatable {
        /// A teal seal: every file is signed.
        case signed
        /// An amber triangle: signing was on and a file couldn't be signed.
        case notSigned
    }

    /// The mark for the photos saved by one press of the shutter, or `nil` for none: a teal seal
    /// when every file is signed, an amber triangle when one couldn't be signed while signing
    /// was on, and nothing when signing was off by choice.
    ///
    /// - Parameter photos: The saved photos.
    /// - Returns: The badge, or `nil`.
    static func badge(for photos: [SavedPhoto]) -> Badge? {
        guard !photos.isEmpty else { return nil }
        if photos.allSatisfy({ $0.signature == .signed }) { return .signed }
        let failed = photos.contains { photo in
            if case .unsigned(let reason) = photo.signature { reason != .turnedOff } else { false }
        }
        return failed ? .notSigned : nil
    }

    /// Creates the slot.
    ///
    /// - Parameters:
    ///   - photos: The photos saved by the last press of the shutter, or `nil` before the first.
    ///   - image: The photo's thumbnail, or `nil` to show a photo symbol.
    ///   - isBusy: Whether a photo is being taken or saved now.
    ///   - openViewer: Opens the Last Photo viewer, or `nil` for none.
    ///   - openPhoto: Opens Photos, or `nil` when the app can't.
    ///   - showDetails: Shows the photo's details, or `nil` for none.
    ///   - isSeriesRunning: Whether a countdown or series runs or is paused. Defaults to `false`.
    init(
        photos: [SavedPhoto]?, image: Image? = nil, isBusy: Bool, openViewer: (() -> Void)? = nil,
        openPhoto: (() -> Void)? = nil, showDetails: (() -> Void)? = nil, isSeriesRunning: Bool = false
    ) {
        self.photos = photos
        self.image = image
        self.isBusy = isBusy
        self.openViewer = openViewer
        self.openPhoto = openPhoto
        self.showDetails = showDetails
        self.isSeriesRunning = isSeriesRunning
    }

    /// What the slot holds now.
    private var content: LastPhotoSpot {
        LastPhotoSpot.content(
            hasPhotos: photos != nil, isBusy: isBusy, isSeriesRunning: isSeriesRunning, isCleanView: false,
            canOpenPhotos: openPhoto != nil)
    }

    /// The slot.
    var body: some View {
        if content == .openPhotos, let openPhoto {
            OpenPhotosButton(action: openPhoto)
        } else if isBusy {
            ProgressView {
                Text("Saving…", bundle: .module, comment: "Shown while a photo that was just taken is being checked and added to the photo library.")
            }
            .labelsHidden()
            .frame(width: Self.side, height: Self.side)
            .accessibilityLabel(Text("Saving…", bundle: .module, comment: "Shown while a photo that was just taken is being checked and added to the photo library."))
        } else if let photos {
            if let openViewer {
                Button(action: openViewer) { thumbnail }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.label)
                    .accessibilityValue(Text(verbatim: CaptureMessages.message(forSaved: photos)))
                    .accessibilityHint(PhotoViewerText.lastPhotoHint)
                    .accessibilityAddTraits([.isButton, .isImage])
                    .accessibilityActions { menuItems }
                    // No Large Content Viewer: the thumbnail is the photo itself, not a label or
                    // symbol the Large Content Viewer would enlarge.
            } else {
                thumbnail
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.label)
                    .accessibilityValue(Text(verbatim: CaptureMessages.message(forSaved: photos)))
                    .accessibilityAddTraits(.isImage)
            }
        }
    }

    /// The slot's name for VoiceOver and Voice Control.
    static var label: Text {
        Text("Last Photo", bundle: .module, comment: "VoiceOver name of the small picture beside the shutter: the last photo taken in this session.")
    }

    /// Open in Photos and Photo Details, the accessibility actions.
    @ViewBuilder private var menuItems: some View {
        if let openPhoto {
            Button(action: openPhoto) {
                Label {
                    Text("Open in Photos", bundle: .module, comment: "Button that opens the Photos app, where the saved photo is. Photos is the system photo library app.")
                } icon: {
                    Image(systemName: "photo.on.rectangle")
                }
            }
        }
        if let showDetails {
            Button(action: showDetails) {
                Label {
                    Text("Photo Details", bundle: .module, comment: "Button and VoiceOver action on the last-photo thumbnail: shows the facts read back from the photo nope. just saved. Keep nope. unchanged if it appears.")
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
        }
    }

    /// The picture with its badge.
    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(NopeColor.label)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(NopeColor.controlFill)
                }
            }
            .frame(width: Self.side, height: Self.side)
            .clipShape(.rect(cornerRadius: NopeRadius.small))
            // A light ring, so the thumbnail's edge shows against the black row and any scene
            // (issue #68, "Contrast").
            .overlay(RoundedRectangle(cornerRadius: NopeRadius.small).strokeBorder(NopeColor.stripIdle, lineWidth: NopeSize.warningOutline))
            if let badge = photos.flatMap(Self.badge(for:)) {
                Image(systemName: badge == .signed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(badge == .signed ? CameraStyle.fact : CameraStyle.warning)
                    .padding(NopeSpace.xxs / 2)
                    .background(.black, in: .circle)
                    .padding(NopeSpace.xxs / 2)
            }
        }
        .accessibilityIgnoresInvertColors()
    }
}

/// Open Photos, in the Last Photo spot before the first photo since the app opened
/// (docs/design/device-feedback-1.0.md, section 1): the thumbnail's size and corner, the fill of
/// a control, and the symbol Open in Photos uses. No ring: the ring belongs to a photo. It opens
/// the Photos app where the person left it; the app can't read the library or name a photo, so
/// nothing here says it shows the last photo.
struct OpenPhotosButton: View {
    /// Opens the Photos app.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameter action: Opens the Photos app.
    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// The button's name for VoiceOver, Voice Control and the Large Content Viewer.
    static var label: Text {
        Text("Open Photos", bundle: .module, comment: "Button in the Last Photo spot beside the shutter, before the first photo since nope. opened: opens the Photos app. Photos is the system photo library app. Draft for the Honesty review.")
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            Image(systemName: "photo.on.rectangle")
                .font(.title3.weight(.semibold))
        }
        .buttonStyle(NopeIconButtonStyle(size: ThumbnailSlot.side, cornerRadius: NopeRadius.small))
        .accessibilityLabel(Self.label)
        .accessibilityInputLabels([
            Self.label,
            // Its own key: "Photos" alone is the interval series' picker.
            Text(String(localized: "Open Photos: second name", defaultValue: "Photos", bundle: .module, comment: "Second Voice Control name of the Open Photos button beside the shutter. Photos is the system photo library app.")),
        ])
        .accessibilityHint(
            Text("Opens the Photos app.", bundle: .module, comment: "VoiceOver hint of the Open Photos button beside the shutter. Photos is the system photo library app. Draft for the Honesty review."))
        .accessibilityShowsLargeContentViewer {
            Label {
                Self.label
            } icon: {
                Image(systemName: "photo.on.rectangle")
            }
        }
        .accessibilityIdentifier("openPhotos")
    }
}
