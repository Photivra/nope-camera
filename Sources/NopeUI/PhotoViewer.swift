import NopeCore
import SwiftUI

// The Last Photo viewer (docs/design/BUILD-SPEC.md, 3.14; docs/design/viewer.html;
// docs/design/ACCESSIBILITY.md, "Last Photo viewer"): a tap on Last Photo shows this session's
// photos full screen inside the app, with Photo Details and Open in Photos.
//
// Privacy (AGENTS.md, "Photos never linger"; docs/PRIVACY.md, "Last photo and its details"): the
// viewer shows only the previews `CameraModel.sessionPhotos` holds in memory. It writes nothing to
// disk, logs nothing, and keeps decoded pictures only for the page shown and its two neighbors.
// Its contents are hidden while the scene isn't active, so the app switcher's snapshot holds no
// photo, and it closes when the app goes to the background (decision V7, in the model).

/// The rules of the Last Photo viewer that don't draw anything: the caption, the status, the
/// position, the zoom limit and the fallback's size. Plain data in and out, so they are tested
/// without a screen (`PhotoViewerTests`).
@MainActor
enum PhotoViewerFacts {
    /// What the status line says about the signature (decision V11).
    enum Signature: Equatable {
        /// Every file is signed: the teal seal and "Signed".
        case signed
        /// Signing was on and a file couldn't be signed: the amber triangle and "Not signed".
        case failed
        /// Signing is off by the person's choice: "Not signed" in secondary text, no symbol.
        case off
    }

    /// The signature status of a saved photo, by the rule of the Last Photo thumbnail's badge
    /// (``ThumbnailSlot/badge(for:)``).
    ///
    /// - Parameter photo: The saved photo.
    /// - Returns: Signed, failed, or off by choice.
    static func signature(of photo: SavedPhoto) -> Signature {
        switch ThumbnailSlot.badge(for: [photo]) {
        case .signed: .signed
        case .notSigned: .failed
        case nil: .off
        }
    }

    /// The saved formats' names, such as "RAW + HEIF". Format names aren't translated.
    ///
    /// - Parameter photo: The saved photo.
    /// - Returns: The names joined with plus signs.
    static func formatNames(of photo: SavedPhoto) -> String {
        FormatChip.names(of: photo.formats)
    }

    /// The photo's place among the session's photos, counted from 1, or `nil` when it isn't one
    /// of them.
    ///
    /// - Parameters:
    ///   - id: The photo's `SessionPhoto.id`.
    ///   - photos: The session's photos, oldest first.
    /// - Returns: The place and the count.
    static func position(of id: Int?, in photos: [SessionPhoto]) -> (number: Int, count: Int)? {
        guard let id, let index = photos.firstIndex(where: { $0.id == id }) else { return nil }
        return (index + 1, photos.count)
    }

    /// "3 of 5", shown only when there is more than one photo.
    ///
    /// - Parameters:
    ///   - number: The photo's place, from 1.
    ///   - count: How many photos there are.
    /// - Returns: The text, or `nil` for a single photo.
    static func positionText(number: Int, count: Int) -> String? {
        guard count > 1 else { return nil }
        return String(
            localized: "\(number) of \(count)", bundle: .module,
            comment: "Caption in the Last Photo viewer: the position of the photo shown among the photos taken since nope. opened, such as 3 of 5. Shown only when there is more than one photo.")
    }

    /// The lens's visible label, as the lens row shows it: "1×", or its name when it has no
    /// magnification; `nil` when the lens isn't known.
    ///
    /// - Parameter lens: The lens the photo was taken with.
    /// - Returns: The label, or `nil`.
    static func lensLabel(_ lens: Lens?) -> String? {
        guard let lens else { return nil }
        if let magnification = lens.magnification {
            return magnification.formatted(.number.precision(.fractionLength(0...1))) + "×"
        }
        return LensName.string(for: lens.kind)
    }

    /// The time the photo was taken, in the system's short time style, such as "2:41 PM".
    ///
    /// - Parameter date: When the shutter took the photo.
    /// - Returns: The time.
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// The caption: the position (with more than one photo), the lens and the time, such as
    /// "3 of 5 · 1× · 2:41 PM". Each part is a whole, separately localized fact.
    ///
    /// - Parameters:
    ///   - photo: The photo shown.
    ///   - photos: The session's photos, oldest first.
    /// - Returns: The caption.
    static func caption(of photo: SessionPhoto, in photos: [SessionPhoto]) -> String {
        let position = Self.position(of: photo.id, in: photos).flatMap { positionText(number: $0.number, count: $0.count) }
        return [position, lensLabel(photo.lens), time(photo.takenAt)].compactMap { $0 }.joined(separator: " · ")
    }

    /// The frames of the bracket a photo belongs to, in the order taken, or the photo alone
    /// when it isn't a bracket's frame: the session's records next to it with the same bracket,
    /// the same press of the shutter (`SessionPhoto.takenAt`) and consecutive frame numbers.
    /// A frame that wasn't saved leaves the frames before it as the bracket.
    ///
    /// - Parameters:
    ///   - photo: The photo shown.
    ///   - photos: The session's photos, oldest first.
    /// - Returns: The frames, at least the photo itself.
    static func bracketFrames(of photo: SessionPhoto, in photos: [SessionPhoto]) -> [SessionPhoto] {
        guard let place = photo.photo.bracket, let index = photos.firstIndex(where: { $0.id == photo.id }) else {
            return [photo]
        }
        /// Whether a record is frame `number` of the same bracket.
        func isFrame(_ record: SessionPhoto, _ number: Int) -> Bool {
            guard let other = record.photo.bracket else { return false }
            return other.frame.number == number && other.count == place.count && other.offsets == place.offsets
                && other.order == place.order && record.takenAt == photo.takenAt
        }
        var first = index
        while first > photos.startIndex, place.frame.number - (index - first) > 1,
            isFrame(photos[first - 1], place.frame.number - (index - first) - 1)
        {
            first -= 1
        }
        var last = index
        while last + 1 < photos.endIndex, isFrame(photos[last + 1], place.frame.number + (last - index) + 1) {
            last += 1
        }
        return Array(photos[first...last])
    }

    /// The photo's VoiceOver label (``label(of:in:)``), followed for a bracket's frame by its
    /// chip's words: "Photo 6 of 7. Exposure bracket, frame 2 of 3, 0 EV." (docs/design/BRACKETING.md,
    /// section 4, "Viewer chip").
    ///
    /// - Parameters:
    ///   - photo: The photo shown, or `nil`.
    ///   - photos: The session's photos, oldest first.
    /// - Returns: The label.
    static func spokenLabel(of photo: SessionPhoto?, in photos: [SessionPhoto]) -> String {
        let label = label(of: photo?.id, in: photos)
        guard let place = photo?.photo.bracket else { return label }
        return label + ". " + BracketText.chipSpoken(place)
    }

    /// The photo's VoiceOver label: "Photo", or "Photo 3 of 5" with more than one photo.
    ///
    /// - Parameters:
    ///   - id: The photo shown.
    ///   - photos: The session's photos, oldest first.
    /// - Returns: The label.
    static func label(of id: Int?, in photos: [SessionPhoto]) -> String {
        if let position = position(of: id, in: photos), position.count > 1 {
            return String(
                localized: "Viewer: photo position", defaultValue: "Photo \(position.number) of \(position.count)",
                bundle: .module,
                comment: "VoiceOver label of the photo in the Last Photo viewer when there are several: its position among the photos taken since nope. opened, such as Photo 3 of 5.")
        }
        return String(
            localized: "Viewer: photo", defaultValue: "Photo", bundle: .module,
            comment: "VoiceOver and Voice Control name of the photo in the Last Photo viewer when there is one photo.")
    }

    /// The photo's VoiceOver value: the formats, the save sentence, the lens and the time, then,
    /// while zoomed, that it is zoomed and is a preview; for a released preview, the fallback's
    /// title and sentence (docs/design/ACCESSIBILITY.md, "Last Photo viewer", VoiceOver).
    ///
    /// - Parameters:
    ///   - photo: The photo shown.
    ///   - isZoomed: Whether it is zoomed in.
    /// - Returns: The value, sentences joined with spaces.
    static func spokenValue(of photo: SessionPhoto, isZoomed: Bool) -> String {
        let formats = photo.photo.formats.map { FormatChip.names(of: [$0]) }.formatted(.list(type: .and))
        var sentences = [String]()
        if photo.photo.isProcessedFallback {
            sentences.append(PhotoViewerText.processedSpoken + ", " + formats + ".")
        } else {
            sentences.append(formats + ".")
        }
        sentences.append(CaptureMessages.message(forSaved: [photo.photo]))
        if let lens = photo.lens { sentences.append(LensName.string(for: lens.kind) + ".") }
        sentences.append(time(photo.takenAt) + ".")
        if photo.preview == nil {
            sentences.append(PhotoViewerText.previewNotKeptTitle + ".")
            sentences.append(PhotoViewerText.previewNotKeptSentence)
        } else if isZoomed {
            sentences.append(PhotoViewerText.zoomedIn)
            if photo.previewIsSmallerThanPhoto { sentences.append(PhotoViewerText.previewHint) }
        }
        return sentences.joined(separator: " ")
    }

    /// Whether New Photo shows: a photo newer than any shown since the viewer opened has
    /// arrived, and the newest isn't the one shown (decision V2).
    ///
    /// - Parameters:
    ///   - shownID: The photo shown.
    ///   - newestID: The newest photo.
    ///   - lastSeenNewestID: The newest photo when the viewer opened, or the newest shown since.
    /// - Returns: Whether to offer New Photo.
    static func showsNewPhoto(shownID: Int?, newestID: Int?, lastSeenNewestID: Int?) -> Bool {
        guard let newestID, newestID != shownID else { return false }
        return newestID > (lastSeenNewestID ?? 0)
    }

    /// The photos whose pictures are decoded: the one shown and its two neighbors.
    ///
    /// - Parameters:
    ///   - shownID: The photo shown.
    ///   - photos: The session's photos, oldest first.
    /// - Returns: Their identifiers, the shown one first.
    static func decodedIDs(around shownID: Int?, in photos: [SessionPhoto]) -> [Int] {
        guard let shownID, let index = photos.firstIndex(where: { $0.id == shownID }) else { return [] }
        return [index, index - 1, index + 1].filter { photos.indices.contains($0) }.map { photos[$0].id }
    }

    /// The identifier of the photo an offset away from the one shown, or `nil` past either end.
    ///
    /// - Parameters:
    ///   - offset: How many photos later (positive) or earlier (negative).
    ///   - shownID: The photo shown.
    ///   - photos: The session's photos, oldest first.
    /// - Returns: The identifier, or `nil`.
    static func id(movingBy offset: Int, from shownID: Int?, in photos: [SessionPhoto]) -> Int? {
        guard let shownID, let index = photos.firstIndex(where: { $0.id == shownID }) else { return nil }
        let target = index + offset
        return photos.indices.contains(target) ? photos[target].id : nil
    }

    /// The size a picture fills when fitted into a space, keeping its shape.
    ///
    /// - Parameters:
    ///   - pixelSize: The picture's size, in pixels (only its shape matters).
    ///   - space: The space, in points.
    /// - Returns: The fitted size, in points.
    static func fittedSize(of pixelSize: CGSize, in space: CGSize) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0, space.width > 0, space.height > 0 else { return .zero }
        let scale = min(space.width / pixelSize.width, space.height / pixelSize.height)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    /// The most a preview zooms: to its own pixels, and at least 2 × fit (decision V5).
    ///
    /// - Parameters:
    ///   - preview: The preview's size, in pixels.
    ///   - space: The page's size, in points.
    ///   - displayScale: The screen's pixels per point.
    /// - Returns: The limit, as a multiple of fit; at least 2.
    static func maximumZoom(preview: CGSize, in space: CGSize, displayScale: CGFloat) -> CGFloat {
        let fitted = fittedSize(of: preview, in: space)
        guard fitted.width > 0, displayScale > 0 else { return minimumMaximumZoom }
        let ownPixels = preview.width / (fitted.width * displayScale)
        return max(minimumMaximumZoom, ownPixels)
    }

    /// The zoom limit never goes below 2 × fit (decision V5).
    nonisolated static let minimumMaximumZoom: CGFloat = 2

    /// The largest side of the fallback's thumbnail, in points: ``NopeSize/viewerFallback``, and
    /// never above twice the thumbnail's own pixel size, so it is never stretched to the screen.
    ///
    /// - Parameter thumbnailLongestSide: The thumbnail's longest side, in pixels.
    /// - Returns: The side, in points.
    static func fallbackSide(thumbnailLongestSide: Int) -> CGFloat {
        min(NopeSize.viewerFallback, 2 * CGFloat(thumbnailLongestSide))
    }
}

/// The zoom of the photo shown: a scale from fit and an offset, kept inside the picture's edges.
struct PhotoViewerZoom: Equatable {
    /// The scale, 1 at fit.
    var scale: CGFloat = 1

    /// How far the scaled picture is moved from the center, in points.
    var offset: CGSize = .zero

    /// Creates a zoom.
    ///
    /// - Parameters:
    ///   - scale: The scale, 1 at fit.
    ///   - offset: How far the scaled picture is moved from the center, in points.
    init(scale: CGFloat = 1, offset: CGSize = .zero) {
        self.scale = scale
        self.offset = offset
    }

    /// The photo at fit.
    static let fit = PhotoViewerZoom()

    /// Whether the photo is zoomed in.
    var isZoomed: Bool { scale > 1.001 }

    /// The zoom at a new scale, keeping the point under a finger or the double tap in place, and
    /// kept inside the picture's edges.
    ///
    /// - Parameters:
    ///   - newScale: The new scale; kept between 1 and `maximum`.
    ///   - point: The point to keep in place, in the page's coordinates.
    ///   - page: The page's size, in points.
    ///   - fitted: The picture's fitted size, in points.
    ///   - maximum: The zoom limit.
    /// - Returns: The new zoom.
    func zoomed(to newScale: CGFloat, around point: CGPoint, page: CGSize, fitted: CGSize, maximum: CGFloat) -> PhotoViewerZoom {
        let scale = min(max(newScale, 1), maximum)
        let center = CGPoint(x: page.width / 2, y: page.height / 2)
        // The picture's point under `point` now, relative to the center at scale 1.
        let contentX = (point.x - center.x - offset.width) / self.scale
        let contentY = (point.y - center.y - offset.height) / self.scale
        let moved = CGSize(width: point.x - center.x - contentX * scale, height: point.y - center.y - contentY * scale)
        return PhotoViewerZoom(scale: scale, offset: moved).clamped(page: page, fitted: fitted)
    }

    /// The zoom moved by a drag, kept inside the picture's edges: at an edge a drag does nothing.
    ///
    /// - Parameters:
    ///   - translation: The drag, in points.
    ///   - start: The offset when the drag began.
    ///   - page: The page's size, in points.
    ///   - fitted: The picture's fitted size, in points.
    /// - Returns: The new zoom.
    func panned(by translation: CGSize, from start: CGSize, page: CGSize, fitted: CGSize) -> PhotoViewerZoom {
        PhotoViewerZoom(
            scale: scale, offset: CGSize(width: start.width + translation.width, height: start.height + translation.height)
        )
        .clamped(page: page, fitted: fitted)
    }

    /// The zoom with its offset kept so the scaled picture covers the page where it is larger,
    /// and centered where it is smaller.
    ///
    /// - Parameters:
    ///   - page: The page's size, in points.
    ///   - fitted: The picture's fitted size, in points.
    /// - Returns: The clamped zoom.
    func clamped(page: CGSize, fitted: CGSize) -> PhotoViewerZoom {
        let limitX = max(0, (fitted.width * scale - page.width) / 2)
        let limitY = max(0, (fitted.height * scale - page.height) / 2)
        return PhotoViewerZoom(
            scale: scale,
            offset: CGSize(width: min(max(offset.width, -limitX), limitX), height: min(max(offset.height, -limitY), limitY)))
    }
}

/// The viewer's words. The claims about the preview and the signature are honesty wording, in
/// `Honesty.xcstrings`, and are drafts until reviewed (BUILD-SPEC.md, section 5).
enum PhotoViewerText {
    /// "Close".
    static var close: Text {
        Text("Close", bundle: .module, comment: "Button in the Last Photo viewer that closes the viewer and returns to the camera. Drawn as an X where Last Photo is.")
    }

    /// "New Photo".
    static var newPhoto: Text {
        Text("New Photo", bundle: .module, comment: "Button in the Last Photo viewer that goes to a photo taken while the viewer was open, for example from Apple Watch or Siri.")
    }

    /// "Photo Not Saved".
    static var photoNotSaved: Text {
        Text("Photo Not Saved", bundle: .module, comment: "Warning chip in the Last Photo viewer when a photo taken while the viewer was open couldn't be saved. Tapping it closes the viewer, where the camera says what went wrong.")
    }

    /// "Signed".
    static var signed: Text {
        Text("Signed", tableName: "Honesty", bundle: .module, comment: "Status in the Last Photo viewer, with a seal: every file of the photo shown has a Content Credentials signature. A short form of \"Saved and signed.\". Must not claim more than the English. Honesty wording: a fluent human must review every translation before release.")
    }

    /// "Not signed".
    static var notSigned: Text {
        Text(
            String(
                localized: "Viewer status: Not signed", defaultValue: "Not signed", table: "Honesty", bundle: .module,
                comment: "Status in the Last Photo viewer: the photo shown has no Content Credentials signature, either because signing is off in Settings or because it failed (then with a warning triangle). Not the title-case warning chip \"Not Signed\", which has its own key. Honesty wording: never imply the photo is signed."))
    }

    /// "A screen-size preview, not the full photo."
    static var previewHint: String {
        String(
            localized: "A screen-size preview, not the full photo.", table: "Honesty", bundle: .module,
            comment: "Hint in the Last Photo viewer while the photo is zoomed in: what is shown is a screen-size preview held in memory, not the saved file. Honesty wording: must not claim more than the English. Draft for the Honesty review.")
    }

    /// "Preview Not Kept".
    static var previewNotKeptTitle: String {
        String(
            localized: "Preview Not Kept", table: "Honesty", bundle: .module,
            comment: "Title in the Last Photo viewer when the preview of the photo shown was released from memory, so only its small thumbnail is left. Honesty wording. Draft for the Honesty review.")
    }

    /// "nope. keeps previews in memory only and has released this one. The photo is saved in
    /// Photos."
    static var previewNotKeptSentence: String {
        String(
            localized: "nope. keeps previews in memory only and has released this one. The photo is saved in Photos.",
            table: "Honesty", bundle: .module,
            comment: "Sentence under Preview Not Kept in the Last Photo viewer. Photos is the system photo library app. Keep \"nope.\" unchanged, lowercase with its period. Honesty wording: must not claim more than the English. Draft for the Honesty review.")
    }

    /// "Processed", the word of the format status for a lens without RAW (``FormatChip``).
    static var processed: String {
        String(
            localized: "Processed", table: "Honesty", bundle: .module,
            comment: "Format status on the camera, with an amber triangle, before a photo on a lens that can't save RAW: the phone processes that lens's photos. The same word starts \"Processed: no RAW on this lens\"; use the same translation. Must not claim more than the English. Honesty wording: a fluent human must review every translation before release.")
    }

    /// "Processed: no RAW on this lens", as the format status says it to VoiceOver.
    static var processedSpoken: String {
        String(
            localized: "Processed marker: spoken value", defaultValue: "Processed: no RAW on this lens", table: "Honesty",
            bundle: .module,
            comment: "VoiceOver value of the Processed marker on the camera, read before the format, for example \"Processed: no RAW on this lens, HEIF\". RAW is a file format name. Not the title-case chip text \"Processed: No RAW on This Lens\", which has its own key. Must not claim more than the English. Honesty wording: a fluent human must review every translation before release.")
    }

    /// "Zoomed in."
    static var zoomedIn: String {
        String(localized: "Zoomed in.", bundle: .module, comment: "Part of the VoiceOver value of the photo in the Last Photo viewer while it is zoomed in.")
    }

    /// "Shows the photo."
    static var lastPhotoHint: Text {
        Text("Shows the photo.", bundle: .module, comment: "VoiceOver hint of Last Photo, the small picture beside the shutter: double tap opens the Last Photo viewer.")
    }

    /// "Photo Details".
    static var photoDetails: Text {
        Text("Photo Details", bundle: .module, comment: "Button and VoiceOver action on the last-photo thumbnail: shows the facts read back from the photo nope. just saved. Keep nope. unchanged if it appears.")
    }

    /// "Open in Photos".
    static var openInPhotos: Text {
        Text("Open in Photos", bundle: .module, comment: "Button that opens the Photos app, where the saved photo is. Photos is the system photo library app.")
    }

    /// "Zoom In".
    static var zoomIn: Text {
        Text("Zoom In", bundle: .module, comment: "Button in the compare view: enlarges both photos together, to see detail, noise and sharpening.")
    }

    /// "Zoom Out".
    static var zoomOut: Text {
        Text("Zoom Out", bundle: .module, comment: "Button in the compare view: shows more of both photos.")
    }

    /// "Hide Controls".
    static var hideControls: Text {
        Text("Hide Controls", bundle: .module, comment: "Button that turns on clean view: hides every control except the shutter.")
    }

    /// "Show Controls".
    static var showControls: Text {
        Text("Show Controls", bundle: .module, comment: "Button and VoiceOver action that brings back the controls hidden by clean view.")
    }
}

/// Presents the Last Photo viewer over the camera while `CameraModel.isViewerOpen` is `true`
/// (BUILD-SPEC.md, 3.14), modeled on ``ComparisonCover``: a full-screen cover in every window, red
/// on black in night mode, the photo included (decision V4).
///
/// The cover itself appears without the system's slide; ``PhotoViewerScreen`` draws the opening
/// and closing with the design's fallback motion (``NopeMotion/panel`` for the frame,
/// ``NopeMotion/fade`` with Reduce Motion, opacity only) and its own swipe down. The system zoom
/// transition (`navigationTransition(.zoom)`) was tried first: its swipe down also closed a
/// zoomed photo, which the design rules out, and SwiftUI has no way to stop it while zoomed.
///
/// The model closes the viewer too: a hardware shutter press while it is open (decision V1) and
/// leaving the foreground (V7). Closing posts a screen change, and `didClose` returns focus to
/// Last Photo.
struct PhotoViewerCover: ViewModifier {
    /// The camera model.
    let model: CameraModel

    /// Whether night mode is on, so the viewer is red too, the photo included (decision V4).
    let isNightMode: Bool

    /// Called when the viewer has closed.
    let didClose: () -> Void

    /// Opens Photos, or `nil` where the app can't (the Lock Screen camera).
    @Environment(\.openPhotosApp) private var openPhotosApp

    /// Whether the cover is shown.
    @State private var isShown = false

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - isNightMode: Whether night mode is on.
    ///   - didClose: Called when the viewer has closed.
    init(model: CameraModel, isNightMode: Bool, didClose: @escaping () -> Void) {
        self.model = model
        self.isNightMode = isNightMode
        self.didClose = didClose
    }

    /// The camera with the cover.
    ///
    /// - Parameter content: The camera.
    func body(content: Content) -> some View {
        content
            .onChange(of: model.isViewerOpen, initial: true) { _, isOpen in setShown(isOpen) }
            .fullScreenCover(isPresented: $isShown, onDismiss: {
                // The camera changed under the cover (a new thumbnail); VoiceOver reads it again.
                AccessibilityNotification.ScreenChanged().post()
                didClose()
            }) {
                PhotoViewerScreen(model: model, openPhoto: openPhotosApp.map { open in { open() } }) { setShown(false) }
                    .nightModeStyle(isNightMode)
                    .environment(\.colorScheme, .dark)
                    // As on the camera: in night mode the system's home indicator and iPad window
                    // controls, which aren't red, are hidden (the iPad night-mode test found the
                    // gray window corner control in the viewer without this).
                    .persistentSystemOverlays(isNightMode ? .hidden : .automatic)
                    // Clear: the viewer draws its own black, which fades in over the camera.
                    .presentationBackground(.clear)
            }
            .onChange(of: isShown) { _, isShown in
                if !isShown && model.isViewerOpen { Task { await model.send(.setViewerOpen(false)) } }
            }
    }

    /// Shows or hides the cover without the system's slide.
    ///
    /// - Parameter isShown: Whether the cover is shown.
    private func setShown(_ isShown: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { self.isShown = isShown }
    }
}

extension View {
    /// Presents the Last Photo viewer while the model says it is open (``PhotoViewerCover``).
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - isNightMode: Whether night mode is on.
    ///   - didClose: Called when the viewer has closed, to return focus to Last Photo.
    func photoViewerCover(_ model: CameraModel, isNightMode: Bool, didClose: @escaping () -> Void) -> some View {
        modifier(PhotoViewerCover(model: model, isNightMode: isNightMode, didClose: didClose))
    }
}

/// The Last Photo viewer: this session's photos, one page each, oldest first, opening on the
/// newest, with the status, the caption, Close, Photo Details and Open in Photos.
///
/// It chooses its arrangement with the camera's rule (``CameraLayout/arrangement(for:isAccessibilitySize:isRegularSize:)``):
/// stacked on an iPhone in portrait, the trailing column in wider windows, and full-width rows at
/// accessibility text sizes. It holds the page shown, whether the controls are hidden, and the
/// newest photo seen, for New Photo.
struct PhotoViewerScreen: View {
    /// The camera model, whose session photos are shown.
    let model: CameraModel

    /// Opens Photos, or `nil` in the Lock Screen camera.
    let openPhoto: (() -> Void)?

    /// Closes the viewer.
    let close: () -> Void

    /// Whether the app is the active app; the contents are hidden otherwise.
    @Environment(\.scenePhase) private var scenePhase

    /// The text size: accessibility sizes use full-width rows.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The horizontal size class.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The vertical size class.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Whether Reduce Motion is on.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The screen's pixels per point, for the zoom limit.
    @Environment(\.displayScale) private var displayScale

    /// The layout direction, for the arrow keys.
    @Environment(\.layoutDirection) private var layoutDirection

    /// Whether night mode is on, so Photo Details is red too.
    @Environment(\.isNightMode) private var isNightMode

    /// The window's space.
    @State private var size = CGSize.zero

    /// The page's space.
    @State private var pageSize = CGSize.zero

    /// The photo shown.
    @State private var shownID: Int?

    /// The newest photo when the viewer opened, or the newest shown since (New Photo).
    @State private var lastSeenNewestID: Int?

    /// Whether a tap has hidden the controls (decision V8).
    @State private var hidesControls = false

    /// The zoom of the photo shown.
    @State private var zoom = PhotoViewerZoom.fit

    /// Whether Photo Details is shown.
    @State private var showsDetails = false

    /// Whether a photo taken while the viewer was open couldn't be saved.
    @State private var showsFailure = false

    /// The decoded pictures of the page shown and its neighbors.
    @State private var pictures: [Int: Image] = [:]

    /// The heights of the facts and the rows in the scrolling arrangement.
    @State private var scrollingRowsHeight: CGFloat = 0

    /// Whether the viewer has faded in (and hasn't begun to fade out).
    @State private var isVisible = false

    /// How far a swipe down has moved the viewer, in points.
    @State private var dismissOffset: CGFloat = 0

    /// The scale the viewer grows from as it opens, and shrinks to as it closes, without Reduce
    /// Motion: a short zoom from the camera's place, about the system zoom transition's feel.
    static let openingScale: CGFloat = 0.92

    /// Whether VoiceOver focus is on the photo.
    @AccessibilityFocusState private var isPhotoFocused: Bool

    /// Whether VoiceOver focus is on the Photo Not Saved chip.
    @AccessibilityFocusState private var isFailureFocused: Bool

    /// Creates the viewer, on the newest photo.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - openPhoto: Opens Photos, or `nil`.
    ///   - close: Closes the viewer.
    init(model: CameraModel, openPhoto: (() -> Void)?, close: @escaping () -> Void) {
        self.model = model
        self.openPhoto = openPhoto
        self.close = close
        let newest = model.sessionPhotos.newest?.id
        _shownID = State(initialValue: newest)
        _lastSeenNewestID = State(initialValue: newest)
    }

    /// The session's photos, oldest first.
    private var photos: [SessionPhoto] { model.sessionPhotos.photos }

    /// The photo shown: the chosen one, or the newest if it was dropped.
    private var shown: SessionPhoto? {
        photos.first { $0.id == shownID } ?? photos.last
    }

    /// The arrangement for the window.
    private var layout: CameraLayout {
        CameraLayout.arrangement(
            for: size, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            isRegularSize: CameraLayout.isRegularSize(horizontal: horizontalSizeClass, vertical: verticalSizeClass))
    }

    /// Whether the controls are shown.
    private var showsControls: Bool { !hidesControls }

    /// Whether New Photo shows.
    private var showsNewPhoto: Bool {
        PhotoViewerFacts.showsNewPhoto(shownID: shown?.id, newestID: photos.last?.id, lastSeenNewestID: lastSeenNewestID)
    }

    /// The zoom limit of the photo shown, or 1 without a preview.
    private var maximumZoom: CGFloat {
        guard let preview = shown?.preview else { return 1 }
        return PhotoViewerFacts.maximumZoom(
            preview: CGSize(width: preview.width, height: preview.height), in: pageSize, displayScale: displayScale)
    }

    /// The viewer.
    var body: some View {
        ZStack {
            Color.black
                .opacity(isVisible ? 1 - min(1, dismissOffset / max(size.height, 1)) : 0)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            Group {
                switch layout {
                case .stacked: stacked
                case .column: column
                case .scrolling: scrolling
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(reduceMotion || isVisible ? 1 : Self.openingScale)
            .offset(y: dismissOffset)
        }
        // The window's size, whatever the content does: a zoomed or dragged photo made the
        // stack measure wider than the window, which read as a resize and reset the zoom.
        .containerRelativeFrame([.horizontal, .vertical])
        .accessibilityElement(children: .contain)
        // The camera shows through while the viewer fades; VoiceOver reads only the viewer.
        .accessibilityAddTraits(.isModal)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .background { keyCommands }
        .overlay {
            // Privacy: no photo in the app switcher's snapshot (AGENTS.md, "Photos never linger").
            if scenePhase != .active {
                Color.black.ignoresSafeArea().accessibilityHidden(true)
            }
        }
        .accessibilityAction(.escape, closeAnimated)
        .onAppear {
            isPhotoFocused = true
            withAnimation(reduceMotion ? NopeMotion.fade : NopeMotion.panel) { isVisible = true }
        }
        .onChange(of: shownID) { _, id in
            zoom = .fit
            if let id, id == photos.last?.id { lastSeenNewestID = id }
        }
        // Fold, unfold, rotate, resize: zoom returns to fit.
        .onChange(of: size) { zoom = .fit }
        .onChange(of: CaptureMessages.error(in: model.captureStatus) != nil) { _, failed in
            if failed {
                showsFailure = true
                isFailureFocused = true
            }
        }
        .task(id: PictureRequest(ids: PhotoViewerFacts.decodedIDs(around: shown?.id, in: photos), previews: photos.map { $0.preview != nil })) {
            await decodePictures()
        }
        .sheet(isPresented: $showsDetails) {
            if let shown {
                // A bracket's frame opens on that frame, with the Photo row stepping through
                // the bracket's frames (docs/design/BRACKETING.md, section 4, figure
                // `bracket-details`); any other photo is shown alone.
                let frames = PhotoViewerFacts.bracketFrames(of: shown, in: photos)
                PhotoDetailsSheet(
                    photos: frames.map(\.photo), openPhoto: openPhoto, session: frames,
                    selection: frames.firstIndex { $0.id == shown.id } ?? 0)
                    .nightModeStyle(isNightMode)
                    .persistentSystemOverlays(isNightMode ? .hidden : .automatic)
                    .presentationBackground(.background)
                    .presentationSizing(.page)
                    .presentationDetents([.large])
            }
        }
    }

    // MARK: - Arrangements

    /// Status line, photo, caption and actions (iPhone in portrait). The status line and the
    /// caption are inside the photo's accessibility element: their words are its value.
    private var stacked: some View {
        VStack(spacing: 0) {
            photoElement(topInset: topFactsHeight, bottomInset: bottomFactsHeight) {
                VStack(spacing: 0) {
                    PhotoViewerStatus(photo: shown?.photo, isOnPicture: false)
                        .frame(maxWidth: .infinity, minHeight: NopeSize.statusRow)
                        .padding(.horizontal, NopeSpace.m)
                        .controlsVisibility(showsControls)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topFactsHeight = $0 }
                    pager
                    PhotoViewerCaption(text: shown.map { PhotoViewerFacts.caption(of: $0, in: photos) } ?? "", isOnPicture: false)
                        .frame(maxWidth: .infinity, minHeight: NopeSize.statusRow)
                        .controlsVisibility(showsControls)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomFactsHeight = $0 }
                }
            }
            PhotoViewerActions(arrangement: .stacked, openPhoto: openPhoto, showDetails: { showsDetails = true }, close: closeAnimated)
                .padding(.horizontal, NopeSpace.xl)
                .frame(minHeight: NopeSize.shutterRowMin)
                .controlsVisibility(showsControls)
        }
    }

    /// The photo beside a trailing column (iPad, the iPhone Duo's inner display, sideways), with
    /// the facts on its top edge on the backing.
    private var column: some View {
        HStack(spacing: 0) {
            photoElement(topInset: topFactsHeight, bottomInset: 0) {
                pager
                    .overlay(alignment: .top) {
                        HStack(alignment: .top, spacing: NopeSpace.xs) {
                            PhotoViewerStatus(photo: shown?.photo, isOnPicture: true)
                            Spacer(minLength: NopeSpace.xs)
                            if let shown {
                                PhotoViewerCaption(text: PhotoViewerFacts.caption(of: shown, in: photos), isOnPicture: true)
                            }
                        }
                        .padding(NopeSpace.xs)
                        .controlsVisibility(showsControls)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topFactsHeight = $0 }
                    }
            }
            PhotoViewerActions(arrangement: .column, openPhoto: openPhoto, showDetails: { showsDetails = true }, close: closeAnimated)
                .frame(width: NopeSize.column)
                .frame(maxHeight: .infinity)
                .controlsVisibility(showsControls)
        }
    }

    /// Facts as lines, the photo at least 280 points high, and full-width rows (accessibility
    /// text sizes). In a window too short for all of it, the rows scroll under the photo.
    private var scrolling: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NopeSpace.xs) {
                photoElement(topInset: topFactsHeight, bottomInset: 0) {
                    VStack(alignment: .leading, spacing: NopeSpace.xs) {
                        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                            PhotoViewerStatus(photo: shown?.photo, isOnPicture: false, isStackedLines: true)
                            if let shown {
                                PhotoViewerCaption(text: PhotoViewerFacts.caption(of: shown, in: photos), isOnPicture: false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, NopeSpace.m)
                        .controlsVisibility(showsControls)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topFactsHeight = $0 }
                        pager
                            .frame(height: max(NopeSize.scrollingPicture, size.height - topFactsHeight - scrollingRowsHeight - 2 * NopeSpace.xs))
                    }
                }
                PhotoViewerActions(arrangement: .scrolling, openPhoto: openPhoto, showDetails: { showsDetails = true }, close: closeAnimated)
                    .padding(.horizontal, NopeSpace.m)
                    .controlsVisibility(showsControls)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollingRowsHeight = $0 }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(zoom.isZoomed)
        .hardScrollEdges()
    }

    /// The height of the facts above the photo (the status line, or the facts' lines).
    @State private var topFactsHeight: CGFloat = 0

    /// The height of the caption below the photo (stacked arrangement).
    @State private var bottomFactsHeight: CGFloat = 0

    // MARK: - The photo

    /// The pages.
    private var pager: some View {
        PhotoViewerPager(
            // The scroll view reports no page while a drag it doesn't scroll is under way; that
            // isn't a page change, and mustn't reset the zoom.
            photos: photos, shownID: Binding(get: { shownID }, set: { id in if let id { shownID = id } }), pictures: pictures, zoom: $zoom, maximumZoom: maximumZoom,
            pageSize: pageSize, toggleControls: toggleControls
        )
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
        // Not in the scrolling arrangement, where a vertical drag scrolls the rows.
        .simultaneousGesture(dismissDrag, isEnabled: !zoom.isZoomed && layout != .scrolling)
    }

    /// The photo's accessibility element around the pages and their facts, with the chip on the
    /// photo's top edge and the hint and New Photo on its lower edge.
    ///
    /// - Parameters:
    ///   - topInset: The height of the facts above the photo, or over its top edge.
    ///   - bottomInset: The height of the facts below the photo.
    ///   - content: The pages with their facts.
    private func photoElement(
        topInset: CGFloat, bottomInset: CGFloat, @ViewBuilder content: () -> some View
    ) -> some View {
        content()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: PhotoViewerFacts.spokenLabel(of: shown, in: photos)))
            .accessibilityValue(Text(verbatim: shown.map { PhotoViewerFacts.spokenValue(of: $0, isZoomed: zoom.isZoomed) } ?? ""))
            .accessibilityAddTraits(.isImage)
            .accessibilityRemoveTraits(.isButton)
            .accessibilityInputLabels([Text(verbatim: PhotoViewerFacts.label(of: nil, in: []))])
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(by: 1)
                case .decrement: move(by: -1)
                @unknown default: break
                }
            }
            .accessibilityAction { toggleControls() }
            .accessibilityActions { photoActions }
            .accessibilityFocused($isPhotoFocused)
            .accessibilitySortPriority(6)
            .accessibilityIdentifier("ViewerPhoto")
            .overlay(alignment: .top) {
                if showsFailure {
                    failureChip
                        .padding(.top, topInset + NopeSpace.xs)
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: NopeSpace.xs) {
                    // A bracket's frame: the chip names the bracket and the frame
                    // (docs/design/BRACKETING.md, section 4; figure `bracket-viewer`). It hides
                    // with the other controls; its words are part of the photo's label.
                    if let place = shown?.photo.bracket {
                        BracketChip(place: place)
                            .controlsVisibility(showsControls)
                    }
                    if zoom.isZoomed, shown?.previewIsSmallerThanPhoto == true {
                        PhotoViewerHint()
                    }
                    if showsNewPhoto {
                        Button {
                            if let newest = photos.last?.id { show(newest) }
                        } label: {
                            Label {
                                PhotoViewerText.newPhoto
                            } icon: {
                                Image(systemName: "arrow.forward")
                            }
                            .labelStyle(TitleTrailingIconLabelStyle())
                        }
                        .buttonStyle(NopeCapsuleStyle(isCompact: true, idleFill: .backing))
                        .accessibilitySortPriority(4)
                    }
                }
                .padding(.bottom, bottomInset + NopeSpace.xs)
                .padding(.horizontal, NopeSpace.m)
            }
    }

    /// The chip that says a photo wasn't saved; it closes the viewer, where the banner waits.
    private var failureChip: some View {
        Button(action: closeAnimated) {
            HStack(spacing: NopeSpace.xxs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CameraStyle.warning)
                    .accessibilityHidden(true)
                PhotoViewerText.photoNotSaved
            }
        }
        .buttonStyle(WarningChipStyle())
        .accessibilityLabel(PhotoViewerText.photoNotSaved)
        .accessibilityShowsLargeContentViewer()
        .accessibilityFocused($isFailureFocused)
        .accessibilitySortPriority(5)
    }

    /// The photo's accessibility actions.
    @ViewBuilder private var photoActions: some View {
        Button { showsDetails = true } label: { PhotoViewerText.photoDetails }
        if let openPhoto {
            Button(action: openPhoto) { PhotoViewerText.openInPhotos }
        }
        if shown?.preview != nil {
            if zoom.scale < maximumZoom {
                Button { setZoom(maximumZoom) } label: { PhotoViewerText.zoomIn }
            }
            if zoom.isZoomed {
                Button { setZoom(1) } label: { PhotoViewerText.zoomOut }
            }
        }
        Button(action: toggleControls) {
            hidesControls ? PhotoViewerText.showControls : PhotoViewerText.hideControls
        }
    }

    /// Hidden buttons for the keyboard: Escape closes, the arrows page (BUILD-SPEC.md, 3.14).
    /// Key commands without priority yield to Full Keyboard Access (UIKit, `UIKeyCommand`).
    private var keyCommands: some View {
        ZStack {
            Button(action: closeAnimated) { PhotoViewerText.close }
                .keyboardShortcut(.cancelAction)
                .accessibilityHidden(true)
            Button { move(byVisualStep: -1) } label: { Text(verbatim: "←") }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityHidden(true)
            Button { move(byVisualStep: 1) } label: { Text(verbatim: "→") }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityHidden(true)
        }
        .hidden()
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    /// Fades the viewer out (with a short shrink unless Reduce Motion is on), then closes it.
    private func closeAnimated() {
        withAnimation(reduceMotion ? NopeMotion.fade : NopeMotion.panel, completionCriteria: .logicallyComplete) {
            isVisible = false
        } completion: {
            close()
        }
    }

    /// A swipe down on a photo at fit: the viewer follows the finger and closes on release past a
    /// third of the photo's height, otherwise it returns. With Reduce Motion it doesn't follow,
    /// and closes on release past the same distance (ACCESSIBILITY.md, "Last Photo viewer").
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: NopeSpace.m)
            .onChanged { value in
                guard !reduceMotion, !zoom.isZoomed, value.translation.height > abs(value.translation.width) else { return }
                dismissOffset = value.translation.height
            }
            .onEnded { value in
                let distance = max(value.translation.height, value.predictedEndTranslation.height)
                let isDown = !zoom.isZoomed && value.translation.height > abs(value.translation.width)
                if isDown, distance > pageSize.height / 3 {
                    closeAnimated()
                } else {
                    withAnimation(reduceMotion ? nil : NopeMotion.panel) { dismissOffset = 0 }
                }
            }
    }

    /// Hides or shows the controls.
    private func toggleControls() {
        withAnimation(reduceMotion ? nil : NopeMotion.fade) { hidesControls.toggle() }
    }

    /// Goes to a photo.
    ///
    /// - Parameter id: The photo.
    private func show(_ id: Int) {
        // With Reduce Motion the pages crossfade in place (PhotoViewerPager).
        withAnimation(reduceMotion ? NopeMotion.fade : NopeMotion.panel) { shownID = id }
    }

    /// Goes to a later (positive) or earlier (negative) photo.
    ///
    /// - Parameter offset: How many photos to move.
    private func move(by offset: Int) {
        guard let id = PhotoViewerFacts.id(movingBy: offset, from: shown?.id, in: photos) else { return }
        show(id)
    }

    /// Goes one photo to the left (negative) or right (positive) on screen: earlier and later
    /// left to right, the other way right to left.
    ///
    /// - Parameter step: -1 for the left arrow, 1 for the right.
    private func move(byVisualStep step: Int) {
        guard !zoom.isZoomed else { return }
        move(by: layoutDirection == .rightToLeft ? -step : step)
    }

    /// Zooms the photo shown about its center.
    ///
    /// - Parameter scale: The new scale.
    private func setZoom(_ scale: CGFloat) {
        guard let preview = shown?.preview else { return }
        let fitted = PhotoViewerFacts.fittedSize(of: CGSize(width: preview.width, height: preview.height), in: pageSize)
        let center = CGPoint(x: pageSize.width / 2, y: pageSize.height / 2)
        withAnimation(reduceMotion ? nil : NopeMotion.panel) {
            zoom = zoom.zoomed(to: scale, around: center, page: pageSize, fitted: fitted, maximum: maximumZoom)
        }
    }

    /// Decodes the pictures of the page shown and its neighbors, and lets go of the others.
    private func decodePictures() async {
        let ids = PhotoViewerFacts.decodedIDs(around: shown?.id, in: photos)
        pictures = pictures.filter { ids.contains($0.key) }
        for id in ids where pictures[id] == nil {
            guard let thumbnail = await model.sessionPhotos.picture(of: id) else { continue }
            guard !Task.isCancelled else { return }
            pictures[id] = Image.photo(thumbnail)
        }
        // A released preview loses its picture too (docs/PRIVACY.md).
        pictures = pictures.filter { entry in photos.first { $0.id == entry.key }?.preview != nil }
    }
}

/// What the viewer decodes: the pages around the one shown, and which previews are held.
private struct PictureRequest: Equatable {
    /// The pages to decode.
    let ids: [Int]
    /// Whether each photo of the session holds a preview, oldest first.
    let previews: [Bool]
}

extension View {
    /// Shows the view while the viewer's controls are shown, and keeps its place while they're
    /// hidden, so the photo doesn't move (decision V8). Hidden, it leaves the accessibility tree.
    ///
    /// - Parameter isShown: Whether the controls are shown.
    @ViewBuilder fileprivate func controlsVisibility(_ isShown: Bool) -> some View {
        // `hidden()`, not only `accessibilityHidden`: hidden alone left the elements in the
        // accessibility tree the UI tests and the audit read, as for Q's panel.
        if isShown {
            self
        } else {
            hidden()
        }
    }
}

/// The title, then the symbol, as New Photo shows its arrow after the words.
private struct TitleTrailingIconLabelStyle: LabelStyle {
    /// The label.
    ///
    /// - Parameter configuration: The title and icon.
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: NopeSpace.xxs) {
            configuration.title
            configuration.icon
        }
    }
}

/// The pages: one per photo, oldest first, in the layout direction, with ``NopeSpace/m`` between
/// them. A swipe moves one page; the first and last spring back. While the photo is zoomed in the
/// pages don't scroll, so a drag moves the photo instead. With Reduce Motion the pages crossfade
/// in place instead of sliding.
struct PhotoViewerPager: View {
    /// The session's photos, oldest first.
    let photos: [SessionPhoto]

    /// The photo shown.
    @Binding var shownID: Int?

    /// The decoded pictures.
    let pictures: [Int: Image]

    /// The zoom of the photo shown.
    @Binding var zoom: PhotoViewerZoom

    /// The zoom limit of the photo shown.
    let maximumZoom: CGFloat

    /// The page's size.
    let pageSize: CGSize

    /// Hides or shows the controls.
    let toggleControls: () -> Void

    /// Whether Reduce Motion is on.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the pages.
    ///
    /// - Parameters:
    ///   - photos: The session's photos, oldest first.
    ///   - shownID: The photo shown.
    ///   - pictures: The decoded pictures.
    ///   - zoom: The zoom of the photo shown.
    ///   - maximumZoom: The zoom limit of the photo shown.
    ///   - pageSize: The page's size, in points.
    ///   - toggleControls: Hides or shows the controls.
    init(
        photos: [SessionPhoto], shownID: Binding<Int?>, pictures: [Int: Image], zoom: Binding<PhotoViewerZoom>,
        maximumZoom: CGFloat, pageSize: CGSize, toggleControls: @escaping () -> Void
    ) {
        self.photos = photos
        _shownID = shownID
        self.pictures = pictures
        _zoom = zoom
        self.maximumZoom = maximumZoom
        self.pageSize = pageSize
        self.toggleControls = toggleControls
    }

    /// The pages.
    var body: some View {
        let fades = reduceMotion
        let stride = pageSize.width + NopeSpace.m
        ScrollView(.horizontal) {
            LazyHStack(spacing: NopeSpace.m) {
                ForEach(photos) { photo in
                    PhotoViewerPage(
                        photo: photo, picture: pictures[photo.id],
                        zoom: photo.id == shownID ? $zoom : .constant(.fit), maximumZoom: maximumZoom,
                        toggleControls: toggleControls
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        // Reduce Motion: the page stays in place and fades (ACCESSIBILITY.md).
                        content
                            .opacity(fades ? 1 - abs(phase.value) : 1)
                            .offset(x: fades ? -phase.value * stride : 0)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $shownID)
        .scrollIndicators(.hidden)
        .scrollDisabled(zoom.isZoomed)
    }
}

/// One photo: its preview fitted and centered, with double tap, pinch and drag; or the fallback
/// once the preview is released. The picture isn't mirrored right to left and is excluded from
/// Smart Invert.
struct PhotoViewerPage: View {
    /// The photo.
    let photo: SessionPhoto

    /// Its decoded picture, or `nil` while it is decoded or after its preview is released.
    let picture: Image?

    /// The zoom; a constant fit for pages not shown.
    @Binding var zoom: PhotoViewerZoom

    /// The zoom limit.
    let maximumZoom: CGFloat

    /// Hides or shows the controls.
    let toggleControls: () -> Void

    /// Whether Reduce Motion is on: zoom changes without animation.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The page's size.
    @State private var size = CGSize.zero

    /// The zoom when a pinch began.
    @State private var pinchStart: PhotoViewerZoom?

    /// The offset when a drag began.
    @State private var dragStart: CGSize?

    /// Creates a page.
    ///
    /// - Parameters:
    ///   - photo: The photo.
    ///   - picture: Its decoded picture, or `nil`.
    ///   - zoom: The zoom; a constant fit for pages not shown.
    ///   - maximumZoom: The zoom limit.
    ///   - toggleControls: Hides or shows the controls.
    init(
        photo: SessionPhoto, picture: Image?, zoom: Binding<PhotoViewerZoom>, maximumZoom: CGFloat,
        toggleControls: @escaping () -> Void
    ) {
        self.photo = photo
        self.picture = picture
        _zoom = zoom
        self.maximumZoom = maximumZoom
        self.toggleControls = toggleControls
    }

    /// The page.
    var body: some View {
        Group {
            if let preview = photo.preview {
                if let picture {
                    picture
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom.scale)
                        .offset(zoom.offset)
                        .accessibilityIgnoresInvertColors()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(.rect)
                        .clipped()
                        .onTapGesture(count: 2, coordinateSpace: .local) { point in doubleTap(at: point, preview: preview) }
                        .onTapGesture(perform: toggleControls)
                        .simultaneousGesture(pinch(preview: preview))
                        .simultaneousGesture(pan(preview: preview), isEnabled: zoom.isZoomed)
                } else {
                    Color.black
                        .contentShape(.rect)
                        .onTapGesture(perform: toggleControls)
                }
            } else {
                PhotoViewerFallback(thumbnail: photo.photo.thumbnail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                    .onTapGesture(perform: toggleControls)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }

    /// The picture's fitted size on this page.
    ///
    /// - Parameter preview: The preview.
    private func fitted(_ preview: PhotoPreview) -> CGSize {
        PhotoViewerFacts.fittedSize(of: CGSize(width: preview.width, height: preview.height), in: size)
    }

    /// Zooms to the limit at the point, or back to fit.
    ///
    /// - Parameters:
    ///   - point: Where the double tap was.
    ///   - preview: The preview.
    private func doubleTap(at point: CGPoint, preview: PhotoPreview) {
        let target: CGFloat = zoom.isZoomed ? 1 : maximumZoom
        withAnimation(reduceMotion ? nil : NopeMotion.panel) {
            zoom = zoom.zoomed(to: target, around: point, page: size, fitted: fitted(preview), maximum: maximumZoom)
        }
    }

    /// Zooms between fit and the limit about the pinch.
    ///
    /// - Parameter preview: The preview.
    private func pinch(preview: PhotoPreview) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? zoom
                pinchStart = start
                let point = CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height)
                zoom = start.zoomed(
                    to: start.scale * value.magnification, around: point, page: size, fitted: fitted(preview),
                    maximum: maximumZoom)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// Moves a zoomed photo; at its edge a drag does nothing.
    ///
    /// - Parameter preview: The preview.
    private func pan(preview: PhotoPreview) -> some Gesture {
        DragGesture(minimumDistance: NopeSpace.xs)
            .onChanged { value in
                let start = dragStart ?? zoom.offset
                dragStart = start
                zoom = zoom.panned(by: value.translation, from: start, page: size, fitted: fitted(preview))
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// A photo whose preview was released: the small thumbnail, never stretched to the screen, and
/// why (BUILD-SPEC.md, 3.14; the wording is an Honesty draft). No zoom.
struct PhotoViewerFallback: View {
    /// The saved photo's thumbnail, or `nil` for a photo symbol.
    let thumbnail: PhotoThumbnail?

    /// Creates the fallback.
    ///
    /// - Parameter thumbnail: The saved photo's thumbnail, or `nil`.
    init(thumbnail: PhotoThumbnail?) {
        self.thumbnail = thumbnail
    }

    /// The fallback.
    var body: some View {
        VStack(spacing: NopeSpace.m) {
            picture
            VStack(spacing: NopeSpace.xs) {
                Text(verbatim: PhotoViewerText.previewNotKeptTitle)
                    .font(.headline)
                    .foregroundStyle(NopeColor.label)
                Text(verbatim: PhotoViewerText.previewNotKeptSentence)
                    .font(.subheadline)
                    .foregroundStyle(CameraColor(NopeColor.labelSecondary))
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, NopeSpace.xl)
    }

    /// The thumbnail at most ``NopeSize/viewerFallback`` on its longest side, with the ring of
    /// Last Photo.
    @ViewBuilder private var picture: some View {
        if let thumbnail, let image = Image.photo(thumbnail) {
            let side = PhotoViewerFacts.fallbackSide(thumbnailLongestSide: max(thumbnail.width, thumbnail.height))
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: side, maxHeight: side)
                .clipShape(.rect(cornerRadius: NopeRadius.small))
                .overlay(RoundedRectangle(cornerRadius: NopeRadius.small).strokeBorder(NopeColor.stripIdle, lineWidth: NopeSize.warningOutline))
                .accessibilityIgnoresInvertColors()
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(NopeColor.label)
        }
    }
}

/// The status line of the photo shown (decision V11): the saved formats leading, with the amber
/// Processed marker for a lens without RAW; Signed with the teal seal, Not signed with the amber
/// triangle when signing failed, or Not signed in secondary text when signing is off, trailing.
/// Only facts read back from the saved photo. Its words are part of the photo's VoiceOver value,
/// so it isn't a separate element.
struct PhotoViewerStatus: View {
    /// The saved photo, or `nil` for none.
    let photo: SavedPhoto?

    /// Whether it is drawn over the picture, on the backing (column arrangement).
    let isOnPicture: Bool

    /// Whether the formats and the signature are lines one above the other (accessibility text
    /// sizes).
    let isStackedLines: Bool

    /// Whether Increase Contrast is on.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the status line.
    ///
    /// - Parameters:
    ///   - photo: The saved photo, or `nil`.
    ///   - isOnPicture: Whether it is drawn over the picture, on the backing.
    ///   - isStackedLines: Whether the facts are lines one above the other.
    init(photo: SavedPhoto?, isOnPicture: Bool, isStackedLines: Bool = false) {
        self.photo = photo
        self.isOnPicture = isOnPicture
        self.isStackedLines = isStackedLines
    }

    /// The status.
    var body: some View {
        if let photo {
            Group {
                if isStackedLines {
                    VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                        formats(of: photo)
                        signature(of: photo)
                    }
                } else if isOnPicture {
                    HStack(spacing: NopeSpace.s) {
                        formats(of: photo)
                        signature(of: photo)
                    }
                    .padding(.horizontal, NopeSpace.s)
                    .frame(minHeight: NopeSize.minTarget)
                    .nopeBackground(.backing, in: Capsule())
                    .overlay {
                        if contrast == .increased {
                            Capsule().strokeBorder(NopeColor.labelSecondary, lineWidth: NopeSize.outline)
                        }
                    }
                } else {
                    // Formats first; the line wraps onto two lines when both don't fit.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: NopeSpace.s) {
                            formats(of: photo)
                            Spacer(minLength: NopeSpace.s)
                            signature(of: photo)
                        }
                        VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                            formats(of: photo)
                            signature(of: photo)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .font(NopeFont.status)
            .accessibilityHidden(true)
        }
    }

    /// "RAW + HEIF", or the triangle and "Processed · HEIF".
    ///
    /// - Parameter photo: The saved photo.
    @ViewBuilder private func formats(of photo: SavedPhoto) -> some View {
        // Left-to-right marks keep "RAW + HEIF" in reading order in right-to-left layouts.
        let names = "\u{200E}" + PhotoViewerFacts.formatNames(of: photo) + "\u{200E}"
        HStack(spacing: NopeSpace.xxs) {
            if photo.isProcessedFallback {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CameraStyle.warning)
                    .accessibilityHidden(true)
                Text(verbatim: PhotoViewerText.processed + " · " + names)
            } else {
                Text(verbatim: names)
            }
        }
        .foregroundStyle(NopeColor.label)
        .fixedSize()
    }

    /// The signature: Signed, Not signed as a warning, or Not signed plain.
    ///
    /// - Parameter photo: The saved photo.
    @ViewBuilder private func signature(of photo: SavedPhoto) -> some View {
        HStack(spacing: NopeSpace.xxs) {
            switch PhotoViewerFacts.signature(of: photo) {
            case .signed:
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(CameraStyle.fact)
                    .accessibilityHidden(true)
                PhotoViewerText.signed
                    .foregroundStyle(NopeColor.label)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CameraStyle.warning)
                    .accessibilityHidden(true)
                PhotoViewerText.notSigned
                    .foregroundStyle(NopeColor.label)
            case .off:
                PhotoViewerText.notSigned
                    .foregroundStyle(CameraColor(NopeColor.labelSecondary))
            }
        }
        .fixedSize()
    }
}

/// The caption of the photo shown: the position, the lens and the time.
struct PhotoViewerCaption: View {
    /// The caption.
    let text: String

    /// Whether it is drawn over the picture, on the backing (column arrangement).
    let isOnPicture: Bool

    /// Creates the caption.
    ///
    /// - Parameters:
    ///   - text: The caption.
    ///   - isOnPicture: Whether it is drawn over the picture, on the backing.
    init(text: String, isOnPicture: Bool) {
        self.text = text
        self.isOnPicture = isOnPicture
    }

    /// The caption.
    var body: some View {
        Text(verbatim: text)
            .font(NopeFont.pill.monospacedDigit())
            .foregroundStyle(isOnPicture ? AnyShapeStyle(NopeColor.label) : AnyShapeStyle(CameraColor(NopeColor.labelSecondary)))
            .padding(.horizontal, isOnPicture ? NopeSpace.s : 0)
            .frame(minHeight: isOnPicture ? NopeSize.minTarget : nil)
            .background {
                if isOnPicture { Capsule().fill(.clear).nopeBackground(.backing, in: Capsule()) }
            }
            .accessibilityHidden(true)
    }
}

/// The preview hint on the photo's lower edge while it is zoomed in, in the look of the camera's
/// hints. Its words are part of the photo's VoiceOver value.
struct PhotoViewerHint: View {
    /// Creates the hint. It holds no state.
    init() {}

    /// The hint.
    var body: some View {
        Label {
            Text(verbatim: PhotoViewerText.previewHint)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(NopeFont.status)
        .foregroundStyle(NopeColor.label)
        .padding(.horizontal, NopeSpace.s)
        .padding(.vertical, NopeSpace.xs)
        .nopeBackground(.backing, in: RoundedRectangle(cornerRadius: NopeRadius.small))
        .accessibilityHidden(true)
    }
}

/// Close, Photo Details and Open in Photos. Open in Photos is left out where the app can't open
/// Photos (the Lock Screen camera).
struct PhotoViewerActions: View {
    /// Where the actions are drawn.
    enum Arrangement {
        /// Close leading where Last Photo is, the two actions trailing (iPhone in portrait).
        case stacked
        /// Symbol buttons with their names below, then Close, centered in the column.
        case column
        /// Three full-width rows (accessibility text sizes).
        case scrolling
    }

    /// Where the actions are drawn.
    let arrangement: Arrangement

    /// Whether night mode is on, for the column buttons' fill.
    @Environment(\.isNightMode) private var isNightMode

    /// Whether Increase Contrast is on: the column buttons get an outline.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Opens Photos, or `nil`.
    let openPhoto: (() -> Void)?

    /// Opens Photo Details for the photo shown.
    let showDetails: () -> Void

    /// Closes the viewer.
    let close: () -> Void

    /// Creates the actions.
    ///
    /// - Parameters:
    ///   - arrangement: Where the actions are drawn.
    ///   - openPhoto: Opens Photos, or `nil` to leave Open in Photos out.
    ///   - showDetails: Opens Photo Details for the photo shown.
    ///   - close: Closes the viewer.
    init(arrangement: Arrangement, openPhoto: (() -> Void)?, showDetails: @escaping () -> Void, close: @escaping () -> Void) {
        self.arrangement = arrangement
        self.openPhoto = openPhoto
        self.showDetails = showDetails
        self.close = close
    }

    /// The actions.
    var body: some View {
        switch arrangement {
        case .stacked:
            HStack(spacing: NopeSpace.m) {
                closeButton
                Spacer(minLength: 0)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NopeSize.targetGap) { capsules }
                    VStack(alignment: .trailing, spacing: NopeSize.targetGap) { capsules }
                }
            }
        case .column:
            VStack(spacing: NopeSpace.m) {
                columnButton(PhotoViewerText.photoDetails, systemImage: "info.circle", sortPriority: 2, action: showDetails)
                if let openPhoto {
                    columnButton(PhotoViewerText.openInPhotos, systemImage: "photo", sortPriority: 1, action: openPhoto)
                }
                closeButton
            }
        case .scrolling:
            VStack(spacing: NopeSize.targetGap) {
                rowButton(PhotoViewerText.photoDetails, sortPriority: 2, action: showDetails)
                if let openPhoto {
                    rowButton(PhotoViewerText.openInPhotos, sortPriority: 1, action: openPhoto)
                }
                rowButton(PhotoViewerText.close, sortPriority: 3, action: close)
            }
        }
    }

    /// Close: an X the size of Last Photo, in its place.
    private var closeButton: some View {
        Button(action: close) {
            Label {
                PhotoViewerText.close
            } icon: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(NopeIconButtonStyle(size: NopeSize.thumbnail))
        .accessibilitySortPriority(3)
    }

    /// Photo Details and Open in Photos as compact capsules.
    @ViewBuilder private var capsules: some View {
        Button(action: showDetails) { PhotoViewerText.photoDetails }
            .buttonStyle(NopeCapsuleStyle(isCompact: true))
            .accessibilitySortPriority(2)
        if let openPhoto {
            Button(action: openPhoto) { PhotoViewerText.openInPhotos }
                .buttonStyle(NopeCapsuleStyle(isCompact: true))
                .accessibilitySortPriority(1)
        }
    }

    /// A 44-point symbol button with its name below, for the column.
    ///
    /// - Parameters:
    ///   - title: The name.
    ///   - systemImage: The symbol.
    ///   - sortPriority: Its place in the VoiceOver order.
    ///   - action: What it does.
    private func columnButton(_ title: Text, systemImage: String, sortPriority: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: NopeSpace.xxs) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NopeColor.label)
                    .frame(width: NopeSize.iconButton, height: NopeSize.iconButton)
                    .background(Circle().fill(isNightMode ? NopeColor.controlFillNight : NopeColor.controlFill))
                    .overlay {
                        if isNightMode || contrast == .increased {
                            Circle().strokeBorder(
                                isNightMode ? NopeColor.nightOutlineUnderMultiply : NopeColor.labelSecondary,
                                lineWidth: NopeSize.outline)
                        }
                    }
                title
                    .font(NopeFont.tileName)
                    .foregroundStyle(NopeColor.label)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilitySortPriority(Double(sortPriority))
    }

    /// A full-width row.
    ///
    /// - Parameters:
    ///   - title: The name.
    ///   - sortPriority: Its place in the VoiceOver order.
    ///   - action: What it does.
    private func rowButton(_ title: Text, sortPriority: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(NopeCapsuleStyle(size: NopeSize.capsuleLarge))
        .accessibilitySortPriority(sortPriority)
    }
}
