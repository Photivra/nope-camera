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

    /// Opens nope.'s page in the Settings app, where Photos access is allowed.
    case openSettings

    /// The action for an error, or `nil` when pressing a button wouldn't help: the camera is
    /// paused (its own message says why), the picture is blank (the camera says to restart the
    /// device), or this build can't save.
    ///
    /// - Parameter error: What went wrong.
    init?(for error: CaptureError) {
        switch error {
        case .photosAccessDenied: self = .openSettings
        case .configurationFailed, .captureFailed, .developmentFailed, .metadataNotAllowed, .saveFailed: self = .tryAgain
        case .notRunning, .blankPicture, .savingUnavailable: return nil
        }
    }
}

/// The banner for a failed capture or save (issue #68, "Feedback tiers"): it stays until it is
/// dismissed or the next photo is saved, takes VoiceOver focus when it appears, and offers one
/// action, Try Again or Open Settings. Its text wraps onto as many lines as it needs.
struct FailureBanner: View {
    /// What went wrong.
    let error: CaptureError

    /// Whether the shutter can take a photo now, for Try Again.
    let canCapture: Bool

    /// Takes the photo again.
    let tryAgain: () -> Void

    /// Hides the banner.
    let dismiss: () -> Void

    /// Opens Settings, or `nil` when the app can't.
    @Environment(\.openAppSettings) private var openAppSettings

    /// Whether VoiceOver focus is on the banner.
    @AccessibilityFocusState private var isFocused: Bool

    /// Creates the banner.
    ///
    /// - Parameters:
    ///   - error: What went wrong.
    ///   - canCapture: Whether the shutter can take a photo now.
    ///   - tryAgain: Takes the photo again.
    ///   - dismiss: Hides the banner.
    init(error: CaptureError, canCapture: Bool, tryAgain: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.error = error
        self.canCapture = canCapture
        self.tryAgain = tryAgain
        self.dismiss = dismiss
    }

    /// The banner.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CameraStyle.warning)
                    .accessibilityHidden(true)
                Text(verbatim: CaptureMessages.message(for: error))
                    .font(.callout)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityFocused($isFocused)
            }
            HStack(spacing: CameraStyle.targetSpacing) {
                actionButton
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: CameraStyle.minimumTarget, height: CameraStyle.minimumTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss", bundle: .module, comment: "Button that closes the message about a photo that wasn't taken or saved."))
                .accessibilityShowsLargeContentViewer {
                    Label {
                        Text("Dismiss", bundle: .module, comment: "Button that closes the message about a photo that wasn't taken or saved.")
                    } icon: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .padding(12)
        .darkBacking()
        .accessibilityElement(children: .contain)
        .onAppear { isFocused = true }
        .onChange(of: error) { isFocused = true }
    }

    /// Try Again or Open Settings, or nothing.
    @ViewBuilder private var actionButton: some View {
        switch FailureAction(for: error) {
        case .tryAgain:
            Button(action: tryAgain) {
                Text("Try Again", bundle: .module, comment: "Button on the message about a photo that wasn't taken or saved: takes the photo again.")
            }
            .buttonStyle(SelectableCapsuleStyle(isSelected: true))
            .disabled(!canCapture)
        case .openSettings:
            if let openAppSettings {
                Button {
                    openAppSettings()
                } label: {
                    Text("Open Settings", bundle: .module, comment: "Button that opens nope.'s page in the system Settings app, where camera or photo library access can be allowed. Keep \"nope.\" unchanged.")
                }
                .buttonStyle(SelectableCapsuleStyle(isSelected: true))
            }
        case nil:
            EmptyView()
        }
    }
}

/// The last-photo slot beside the shutter (issue #68, "Feedback tiers"): empty and invisible
/// until the first photo of the session, never an empty square. Then it shows the last photo with
/// a teal seal when every file was signed, or an amber mark when one wasn't.
///
/// With ``image``, it shows the photo itself (issue #36), made in memory from the saved file;
/// without one, a photo symbol. With ``openPhoto`` or ``showDetails`` it is a button: a tap opens
/// Photos (or the details, when the app can't open Photos), and a long press, VoiceOver and Voice
/// Control offer both, Open in Photos and Photo Details.
struct ThumbnailSlot: View {
    /// The photos saved by the last press of the shutter, or `nil` before the first.
    let photos: [SavedPhoto]?

    /// The photo's thumbnail, or `nil` to show a photo symbol.
    let image: Image?

    /// Whether a photo is being taken or saved now.
    let isBusy: Bool

    /// Opens Photos, or `nil` when the app can't.
    let openPhoto: (() -> Void)?

    /// Shows the photo's details (issue #53), or `nil` for none.
    let showDetails: (() -> Void)?

    /// The slot's side, in points: larger than the 44-point minimum, smaller than the shutter.
    static var side: CGFloat { 52 }

    /// Creates the slot.
    ///
    /// - Parameters:
    ///   - photos: The photos saved by the last press of the shutter, or `nil` before the first.
    ///   - image: The photo's thumbnail, or `nil` to show a photo symbol.
    ///   - isBusy: Whether a photo is being taken or saved now.
    ///   - openPhoto: Opens Photos, or `nil` when the app can't.
    ///   - showDetails: Shows the photo's details, or `nil` for none.
    init(
        photos: [SavedPhoto]?, image: Image? = nil, isBusy: Bool, openPhoto: (() -> Void)? = nil,
        showDetails: (() -> Void)? = nil
    ) {
        self.photos = photos
        self.image = image
        self.isBusy = isBusy
        self.openPhoto = openPhoto
        self.showDetails = showDetails
    }

    /// Whether every saved file is signed.
    private var isSigned: Bool {
        photos?.allSatisfy { $0.signature == .signed } ?? false
    }

    /// The slot.
    var body: some View {
        if isBusy {
            ProgressView {
                Text("Saving…", bundle: .module, comment: "Shown while a photo that was just taken is being checked and added to the photo library.")
            }
            .labelsHidden()
            .frame(width: Self.side, height: Self.side)
            .accessibilityLabel(Text("Saving…", bundle: .module, comment: "Shown while a photo that was just taken is being checked and added to the photo library."))
        } else if let photos {
            if let action = openPhoto ?? showDetails {
                Button(action: action) { thumbnail }
                    .buttonStyle(.plain)
                    .contextMenu { menuItems }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.label)
                    .accessibilityValue(Text(verbatim: CaptureMessages.message(forSaved: photos)))
                    .accessibilityAddTraits([.isButton, .isImage])
                    .accessibilityActions { menuItems }
                    .accessibilityShowsLargeContentViewer {
                        Label { Self.label } icon: { Image(systemName: "photo") }
                    }
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
    private static var label: Text {
        Text("Last Photo", bundle: .module, comment: "VoiceOver name of the small picture beside the shutter: the last photo taken in this session.")
    }

    /// Open in Photos and Photo Details, for the long-press menu and the accessibility actions.
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
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(white: 0.25))
                }
            }
            .frame(width: Self.side, height: Self.side)
            .clipShape(.rect(cornerRadius: 8))
            // A dark hairline, so the thumbnail's edge shows over any scene (issue #68, "Contrast").
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.6), lineWidth: 1))
            Image(systemName: isSigned ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(isSigned ? CameraStyle.fact : CameraStyle.warning)
                .padding(2)
                .background(.black, in: .circle)
                .offset(x: 6, y: 6)
        }
        .accessibilityIgnoresInvertColors()
    }
}
