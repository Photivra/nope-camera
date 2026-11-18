import Foundation
import Observation

/// One photo saved in this session: one page of the Last Photo viewer (docs/design/BUILD-SPEC.md,
/// 3.14; each frame of a bracket or burst is its own photo, decision V12).
///
/// Privacy: everything here lives in memory only. It is never written to disk, logged or
/// copied, and the app has add-only Photos access, so nothing comes from the library
/// (AGENTS.md, "Photos never linger"; docs/PRIVACY.md, "Last photo and its details").
public struct SessionPhoto: Identifiable, Equatable, Sendable {
    /// The photo's place in this session's saves: 1 for the first, counting up. Never reused,
    /// also after older photos are dropped, so a viewer can keep its page.
    public let id: Int

    /// What was saved: the formats, the signature, the thumbnail and the details.
    public let photo: SavedPhoto

    /// The lens the photo was taken with, for the caption, or `nil` if unknown.
    public let lens: Lens?

    /// When the shutter took the photo, by the device's clock, for the caption. For a bracket,
    /// every frame has the time of the press. In memory only; it is not the photo's date tag.
    public let takenAt: Date

    /// The compressed screen-size preview, or `nil` when there is none: the app made none (no
    /// previewer, or the file couldn't be read), or ``SessionPhotos`` released it. A viewer then
    /// shows its fallback with ``SavedPhoto/thumbnail``.
    public internal(set) var preview: PhotoPreview?

    /// Creates a record.
    ///
    /// - Parameters:
    ///   - id: The photo's place in this session's saves.
    ///   - photo: What was saved.
    ///   - lens: The lens, or `nil`.
    ///   - takenAt: When the shutter took it.
    ///   - preview: The compressed preview, or `nil`.
    public init(id: Int, photo: SavedPhoto, lens: Lens?, takenAt: Date, preview: PhotoPreview?) {
        self.id = id
        self.photo = photo
        self.lens = lens
        self.takenAt = takenAt
        self.preview = preview
    }

    /// Whether the preview has fewer pixels than the saved photo, so a viewer zoomed in says it
    /// shows a preview (BUILD-SPEC.md, 3.14, decision V5). `false` without a preview, and when
    /// the saved size isn't known.
    public var previewIsSmallerThanPhoto: Bool {
        guard let preview, let photoSide = photoLongestSide else { return false }
        return preview.longestSide < photoSide
    }

    /// The longest side of the largest saved file, in pixels, as the read-back reported it, or
    /// `nil` when unknown.
    public var photoLongestSide: Int? {
        photo.details?.files.compactMap { file in
            guard let width = file.pixelWidth, let height = file.pixelHeight else { return nil }
            return max(width, height)
        }.max()
    }
}

/// This session's saved photos, oldest first, with their compressed previews: the pages of the
/// Last Photo viewer (``CameraModel/sessionPhotos``; docs/design/BUILD-SPEC.md, 3.14 and
/// section 6, item 15).
///
/// The model adds every photo it saves: a single photo, each frame of a bracket or burst, each
/// astro or interval frame, and the app's photo of a comparison shot.
///
/// The rules (AGENTS.md, "Photos never linger" and "Battery"; docs/PRIVACY.md):
/// - A preview is made in memory from the saved file before its bytes are released, never read
///   back from Photos, and never written to disk, logged or copied. It is pixels only, at most
///   ``previewMaximumPixelSize`` on its longest side, JPEG-compressed.
/// - Only the newest ``maximumPreviews`` photos keep a preview (decision V6); adding a photo
///   releases the preview of the one that falls out. Older photos keep their record, which shows
///   the fallback.
/// - At most ``maximumCount`` records are kept; adding one drops the oldest.
/// - Every preview is released when the app leaves the foreground (decision V7) and when the
///   system reports low memory (``CameraIntent/releasePhotoPreviews``).
/// - Decoded pixels are not kept here: ``picture(of:maximumPixelSize:)`` decodes on request, and
///   a viewer keeps decoded pictures only for the page shown and its two neighbors.
/// - The records (``SessionPhoto/photo`` with the 156-pixel thumbnail and the details, the lens
///   and the time) stay in memory until the app quits, as the thumbnail and Photo Details always
///   have.
@MainActor
@Observable
public final class SessionPhotos {
    /// The longest side of a preview, in pixels: 3072.
    ///
    /// The viewer zooms from fit to the preview's own pixels, and at least 2 × fit (decision V5).
    /// A 4:3 photo fitted on an iPhone is about 1600 to 1760 pixels on its long side (iPhone 18
    /// Pro: 1206 × 2622 pixels; Pro Max: 1320 × 2868), so 3072 reaches 1.75 to 1.9 × fit in the
    /// preview's own pixels. On a 13-inch iPad (2752 × 2064 pixels) it is a little more than fit.
    /// The photos the app takes are 4032 pixels wide; the full size would cost about 49 MB per
    /// decoded page, against 28 MB here. Screen sizes: Apple, "Human Interface Guidelines,
    /// Layout, Specifications".
    nonisolated public static let previewMaximumPixelSize = 3072

    /// How many of the newest photos keep a preview: 20 (decision V6).
    nonisolated public static let maximumPreviews = 20

    /// How many records are kept: 100. A long interval or astro series can save hundreds of
    /// photos; each record holds a 156-pixel thumbnail (about 73 KB) and the photo's details, so
    /// they are bounded too. The oldest go first.
    nonisolated public static let maximumCount = 100

    /// The photos, oldest first. The last one is the newest.
    public private(set) var photos: [SessionPhoto] = []

    /// The ``SessionPhoto/id`` of the next photo added.
    private var nextID = 1

    /// The most records kept; ``maximumCount`` unless a test sets another.
    @ObservationIgnored let countLimit: Int

    /// How many of the newest photos keep a preview; ``maximumPreviews`` unless a test sets
    /// another.
    @ObservationIgnored let previewLimit: Int

    /// Decodes previews, or `nil` when this model makes none.
    @ObservationIgnored let decoder: (any PhotoPreviewing)?

    /// Creates an empty list.
    ///
    /// - Parameters:
    ///   - decoder: Decodes previews, or `nil`.
    ///   - countLimit: The most records kept; at least 1.
    ///   - previewLimit: How many of the newest photos keep a preview.
    init(decoder: (any PhotoPreviewing)?, countLimit: Int, previewLimit: Int) {
        self.decoder = decoder
        self.countLimit = max(1, countLimit)
        self.previewLimit = previewLimit
    }

    /// Creates an empty list with the standard limits, ``maximumCount`` and
    /// ``maximumPreviews``.
    ///
    /// - Parameter decoder: Decodes previews, or `nil` when this model makes none.
    public convenience init(decoder: (any PhotoPreviewing)?) {
        self.init(decoder: decoder, countLimit: Self.maximumCount, previewLimit: Self.maximumPreviews)
    }

    /// Whether this model makes previews: `false` without a decoder, as in the Lock Screen
    /// camera, whose save pipeline makes none. An interface then says that previews aren't made
    /// there, rather than that one was released.
    public var makesPreviews: Bool { decoder != nil }

    /// The newest photo, or `nil` before the first save.
    public var newest: SessionPhoto? { photos.last }

    /// The compressed bytes of the previews held now.
    public var previewBytes: Int {
        photos.reduce(0) { $0 + ($1.preview?.data.count ?? 0) }
    }

    /// The photo with an identifier, or `nil` if it was dropped.
    ///
    /// - Parameter id: A ``SessionPhoto/id``.
    public func photo(id: Int) -> SessionPhoto? {
        photos.first { $0.id == id }
    }

    /// Decodes a photo's preview, off the main actor. Nothing is kept: the caller holds the
    /// pixels only while it shows them (the page shown and its neighbors).
    ///
    /// - Parameters:
    ///   - id: The photo's ``SessionPhoto/id``.
    ///   - maximumPixelSize: The longest side to decode to, in pixels, or `nil` for the
    ///     preview's own size.
    /// - Returns: The pixels, or `nil` when the photo or its preview is gone, or it can't be
    ///   decoded.
    public func picture(of id: Int, maximumPixelSize: Int? = nil) async -> PhotoThumbnail? {
        guard let decoder, let preview = photo(id: id)?.preview else { return nil }
        return await Task.detached { decoder.decode(preview, maximumPixelSize: maximumPixelSize) }.value
    }

    /// Adds a saved photo as the newest, drops the oldest records beyond the count limit, and
    /// releases the previews of photos older than the newest ``previewLimit``.
    ///
    /// - Parameters:
    ///   - photo: What was saved.
    ///   - lens: The lens it was taken with.
    ///   - takenAt: When the shutter took it.
    ///   - preview: Its compressed preview, or `nil`.
    func add(_ photo: SavedPhoto, lens: Lens?, takenAt: Date, preview: PhotoPreview?) {
        var kept = photos
        kept.append(SessionPhoto(id: nextID, photo: photo, lens: lens, takenAt: takenAt, preview: preview))
        nextID += 1
        kept.removeFirst(max(0, kept.count - countLimit))
        for index in kept.indices.dropLast(previewLimit) where kept[index].preview != nil {
            kept[index].preview = nil
        }
        // One assignment, so an observer sees one change.
        photos = kept
    }

    /// Releases every preview, keeping the records.
    func releasePreviews() {
        guard photos.contains(where: { $0.preview != nil }) else { return }
        photos = photos.map {
            SessionPhoto(id: $0.id, photo: $0.photo, lens: $0.lens, takenAt: $0.takenAt, preview: nil)
        }
    }
}
