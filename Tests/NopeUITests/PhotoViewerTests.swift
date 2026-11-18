import CoreGraphics
import Foundation
import NopeCore
import Testing

@testable import NopeUI

/// The Last Photo viewer's rules (docs/design/BUILD-SPEC.md, 3.14): the status, the caption and
/// the photo's VoiceOver label and value, New Photo, paging, the zoom limit, the zoom and drag
/// arithmetic, and the fallback's size.
@MainActor
struct PhotoViewerTests {
    static let wide = Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4", magnification: 1)
    static let front = Lens(id: "front", kind: .front, bayerRAWFormat: "bgg4")
    static let preview = PhotoPreview(width: 3072, height: 2304, data: Data([1]))

    static func saved(_ signature: SignatureStatus = .signed, processed: Bool = false) -> SavedPhoto {
        SavedPhoto(formats: processed ? [.heif] : [.raw, .heif], isProcessedFallback: processed, signature: signature, metadata: [:])
    }

    static func photo(_ id: Int, lens: Lens? = wide, preview: PhotoPreview? = preview, saved: SavedPhoto = saved()) -> SessionPhoto {
        SessionPhoto(id: id, photo: saved, lens: lens, takenAt: Date(timeIntervalSince1970: 0), preview: preview)
    }

    @Test func signatureFollowsTheThumbnailBadge() {
        #expect(PhotoViewerFacts.signature(of: Self.saved(.signed)) == .signed)
        #expect(PhotoViewerFacts.signature(of: Self.saved(.unsigned(.failed))) == .failed)
        #expect(PhotoViewerFacts.signature(of: Self.saved(.unsigned(.unavailable))) == .failed)
        // Signing off by choice is not a warning (decision V11).
        #expect(PhotoViewerFacts.signature(of: Self.saved(.unsigned(.turnedOff))) == .off)
        #expect(PhotoViewerFacts.formatNames(of: Self.saved()) == "RAW + HEIF")
    }

    @Test func positionShowsOnlyWithSeveralPhotos() {
        let photos = [Self.photo(1), Self.photo(2), Self.photo(5)]
        #expect(PhotoViewerFacts.position(of: 5, in: photos)! == (3, 3))
        #expect(PhotoViewerFacts.position(of: 4, in: photos) == nil)
        #expect(PhotoViewerFacts.position(of: nil, in: photos) == nil)
        #expect(PhotoViewerFacts.positionText(number: 1, count: 1) == nil)
        #expect(PhotoViewerFacts.positionText(number: 2, count: 3) == "2 of 3")
        #expect(PhotoViewerFacts.label(of: 2, in: photos) == "Photo 2 of 3")
        #expect(PhotoViewerFacts.label(of: 1, in: [Self.photo(1)]) == "Photo")
        #expect(PhotoViewerFacts.label(of: nil, in: []) == "Photo")
    }

    @Test func captionHasThePositionTheLensAndTheTime() {
        let time = PhotoViewerFacts.time(Date(timeIntervalSince1970: 0))
        let photos = [Self.photo(1), Self.photo(2, lens: Self.front)]
        #expect(PhotoViewerFacts.caption(of: photos[0], in: photos) == "1 of 2 · 1× · \(time)")
        // A lens without a magnification is named; an unknown lens is left out.
        #expect(PhotoViewerFacts.caption(of: photos[1], in: photos) == "2 of 2 · Front · \(time)")
        let alone = Self.photo(3, lens: nil)
        #expect(PhotoViewerFacts.caption(of: alone, in: [alone]) == time)
        #expect(PhotoViewerFacts.lensLabel(Lens(id: "tele", kind: .telephoto, bayerRAWFormat: nil, magnification: 2.5)) == "2.5×")
    }

    @Test func spokenValueReadsEveryFactAndTheZoomAndFallback() {
        let time = PhotoViewerFacts.time(Date(timeIntervalSince1970: 0))
        #expect(PhotoViewerFacts.spokenValue(of: Self.photo(1), isZoomed: false) == "RAW and HEIF. Saved and signed. Wide. \(time).")
        // The simulated photo's size is unknown, so the hint isn't claimed.
        #expect(PhotoViewerFacts.spokenValue(of: Self.photo(1), isZoomed: true) == "RAW and HEIF. Saved and signed. Wide. \(time). Zoomed in.")
        let processed = Self.photo(1, lens: nil, saved: Self.saved(.unsigned(.turnedOff), processed: true))
        #expect(
            PhotoViewerFacts.spokenValue(of: processed, isZoomed: false)
                == "Processed: no RAW on this lens, HEIF. Saved. Not signed: signing is off in Settings. \(time).")
        let released = Self.photo(1, preview: nil)
        #expect(PhotoViewerFacts.spokenValue(of: released, isZoomed: true).hasSuffix(
            "Preview Not Kept. nope. keeps previews in memory only and has released this one. The photo is saved in Photos."))
    }

    @Test func theLockScreenCameraSaysItMakesNoPreviews() {
        // The Lock Screen camera makes no previews, so none was released (owner decision 1).
        let photo = Self.photo(1, preview: nil)
        let value = PhotoViewerFacts.spokenValue(of: photo, isZoomed: false, makesPreviews: false)
        #expect(value.hasSuffix("No Preview. On the Lock Screen, nope. doesn't make previews. The photo is saved in Photos."))
        #expect(!value.contains("released"))
        #expect(PhotoViewerText.noPreviewTitle(makesPreviews: false) == "No Preview")
        #expect(PhotoViewerText.noPreviewTitle(makesPreviews: true) == "Preview Not Kept")
        #expect(PhotoViewerText.noPreviewSentence(makesPreviews: true) == PhotoViewerText.previewNotKeptSentence)
        #expect(
            PhotoViewerText.noPreviewSentence(makesPreviews: false)
                == "On the Lock Screen, nope. doesn't make previews. The photo is saved in Photos.")
    }

    @Test func spokenValueAddsTheHintWhenThePreviewIsSmaller() {
        let file = PhotoDetails.File(
            format: .heif, byteCount: 1, pixelWidth: 4032, pixelHeight: 3024, bitDepth: 8, colorFilterPattern: nil,
            blackLevels: [], whiteLevels: [], storesLensCorrections: false, processing: .none, contentCredentials: nil,
            contents: [])
        let details = PhotoDetails(
            files: [file], exposure: nil, items: [], lockedItems: [], signature: .signed, timings: SaveTimings())
        let saved = SavedPhoto(
            formats: [.heif], isProcessedFallback: false, signature: .signed, metadata: [:], details: details)
        let photo = Self.photo(1, saved: saved)
        #expect(PhotoViewerFacts.spokenValue(of: photo, isZoomed: true).hasSuffix("Zoomed in. A screen-size preview, not the full photo."))
    }

    @Test func newPhotoShowsUntilTheNewestIsShown() {
        // Nothing new since opening.
        #expect(!PhotoViewerFacts.showsNewPhoto(shownID: 3, newestID: 3, lastSeenNewestID: 3))
        #expect(!PhotoViewerFacts.showsNewPhoto(shownID: 1, newestID: 3, lastSeenNewestID: 3))
        // A photo arrived while an older one is shown.
        #expect(PhotoViewerFacts.showsNewPhoto(shownID: 3, newestID: 4, lastSeenNewestID: 3))
        #expect(!PhotoViewerFacts.showsNewPhoto(shownID: 4, newestID: 4, lastSeenNewestID: 3))
        #expect(!PhotoViewerFacts.showsNewPhoto(shownID: nil, newestID: nil, lastSeenNewestID: nil))
        #expect(PhotoViewerFacts.showsNewPhoto(shownID: nil, newestID: 1, lastSeenNewestID: nil))
    }

    @Test func pagingAndDecodingStayAroundThePageShown() {
        let photos = [Self.photo(1), Self.photo(2), Self.photo(3), Self.photo(4)]
        #expect(PhotoViewerFacts.decodedIDs(around: 2, in: photos) == [2, 1, 3])
        #expect(PhotoViewerFacts.decodedIDs(around: 1, in: photos) == [1, 2])
        #expect(PhotoViewerFacts.decodedIDs(around: 4, in: photos) == [4, 3])
        #expect(PhotoViewerFacts.decodedIDs(around: 9, in: photos).isEmpty)
        #expect(PhotoViewerFacts.decodedIDs(around: nil, in: photos).isEmpty)
        #expect(PhotoViewerFacts.id(movingBy: 1, from: 2, in: photos) == 3)
        #expect(PhotoViewerFacts.id(movingBy: -1, from: 1, in: photos) == nil)
        #expect(PhotoViewerFacts.id(movingBy: 1, from: 4, in: photos) == nil)
        #expect(PhotoViewerFacts.id(movingBy: 1, from: nil, in: photos) == nil)
    }

    @Test func zoomReachesThePreviewsPixelsAndAtLeastTwiceFit() {
        let preview = CGSize(width: 3072, height: 2304)
        // An iPhone page of 402 points at 3 pixels per point: 1206 pixels, so 2.55 × fit.
        let iPhone = PhotoViewerFacts.maximumZoom(preview: preview, in: CGSize(width: 402, height: 600), displayScale: 3)
        #expect(abs(iPhone - 3072 / 1206) < 0.001)
        // A large page needs less than 2 × to reach the pixels; the limit stays at 2.
        #expect(PhotoViewerFacts.maximumZoom(preview: preview, in: CGSize(width: 1200, height: 900), displayScale: 2) == 2)
        #expect(PhotoViewerFacts.maximumZoom(preview: preview, in: .zero, displayScale: 3) == 2)
        #expect(PhotoViewerFacts.fittedSize(of: CGSize(width: 4, height: 3), in: CGSize(width: 400, height: 600)) == CGSize(width: 400, height: 300))
        #expect(PhotoViewerFacts.fittedSize(of: .zero, in: CGSize(width: 1, height: 1)) == .zero)
    }

    @Test func zoomKeepsThePointInPlaceAndStaysInsideThePicture() {
        let page = CGSize(width: 400, height: 600)
        let fitted = CGSize(width: 400, height: 300)
        // Zooming about the center leaves the picture centered.
        let centered = PhotoViewerZoom.fit.zoomed(to: 2, around: CGPoint(x: 200, y: 300), page: page, fitted: fitted, maximum: 3)
        #expect(centered == PhotoViewerZoom(scale: 2, offset: .zero))
        #expect(centered.isZoomed)
        #expect(!PhotoViewerZoom.fit.isZoomed)
        // About a point right of center, the picture moves left to keep it under the finger.
        let right = PhotoViewerZoom.fit.zoomed(to: 2, around: CGPoint(x: 300, y: 300), page: page, fitted: fitted, maximum: 3)
        #expect(right.offset == CGSize(width: -100, height: 0))
        // The scale stays between fit and the limit.
        #expect(PhotoViewerZoom.fit.zoomed(to: 9, around: .zero, page: page, fitted: fitted, maximum: 3).scale == 3)
        #expect(centered.zoomed(to: 0.2, around: .zero, page: page, fitted: fitted, maximum: 3) == .fit)
        // A drag past the edge stops at it: at 2 × the picture is 800 × 600, 200 points past each side.
        let dragged = centered.panned(by: CGSize(width: 500, height: 500), from: .zero, page: page, fitted: fitted)
        #expect(dragged.offset == CGSize(width: 200, height: 0))
    }

    @Test func fallbackIsNeverStretched() {
        #expect(PhotoViewerFacts.fallbackSide(thumbnailLongestSide: 156) == NopeSize.viewerFallback)
        #expect(PhotoViewerFacts.fallbackSide(thumbnailLongestSide: 40) == 80)
        #expect(NopeSize.viewerFallback == 160)
    }
}
