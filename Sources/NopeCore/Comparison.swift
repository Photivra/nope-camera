import Foundation
import Observation

/// The phone's fully processed version of (almost) the same moment as the app's photo, for the
/// comparison shot (issue #55).
///
/// Privacy: it is never saved. It isn't a ``CapturedPhoto``, so it can't be handed to
/// ``PhotoSaver``; it is never written to a file, added to Photos, signed, shared or logged.
/// ``ComparisonModel`` turns it into a picture and a metadata list for the compare view and then
/// drops it; the picture and list are dropped when the view closes.
public struct PhoneProcessedPhoto: Equatable, Sendable {
    /// The file bytes as iOS wrote them, with the system's own metadata: a HEIF, or a JPEG on a
    /// lens that gives only JPEG.
    public let data: Data

    /// The format of ``data``: ``PhotoFormat/heif`` or ``PhotoFormat/jpeg``.
    public let format: PhotoFormat

    /// The photo's size, in pixels, as the system resolved it.
    public let dimensions: PhotoDimensions

    /// Everything metadata-like in ``data``, read by the project's own tag reader
    /// (``MetadataFileReader``): what the phone's version carries by default.
    public let metadata: MetadataInventory

    /// Creates a phone-processed photo.
    ///
    /// - Parameters:
    ///   - data: The file bytes.
    ///   - format: The format of the bytes.
    ///   - dimensions: The photo's size, in pixels.
    ///   - metadata: The file's metadata, as the tag reader found it.
    public init(data: Data, format: PhotoFormat, dimensions: PhotoDimensions, metadata: MetadataInventory) {
        self.data = data
        self.format = format
        self.dimensions = dimensions
        self.metadata = metadata
    }
}

/// A ``CaptureBackend`` that can also take the phone's fully processed photo for the comparison
/// shot (issue #55).
///
/// `NopeCapture` implements it with AVFoundation: a second capture, right after the app's own,
/// with `.quality` prioritization, which lets the system combine several frames where the
/// device does that. iOS doesn't allow that processing in the same capture as a Bayer RAW,
/// so it is a separate photo a moment later. ``SimulatedCaptureBackend`` returns a placeholder.
public protocol ComparisonCaptureBackend: CaptureBackend {
    /// Takes the phone's fully processed photo with the request's lens, in memory only.
    ///
    /// Side effects: none beyond the capture itself. The photo isn't written to a file or saved,
    /// and the camera is left configured for the app's own photos afterwards.
    ///
    /// - Parameter request: The lens, format and flash of the app's photo, just taken; the same as
    ///   the last ``CaptureBackend/startSession(_:)``. Its metadata plan is ignored: the
    ///   phone's version keeps the system's own metadata, because that is what it shows.
    /// - Returns: The photo.
    /// - Throws: ``CaptureError/notRunning`` if the camera isn't running, or
    ///   ``CaptureError/captureFailed`` if the system reports an error or returns no file.
    func captureComparison(_ request: CaptureRequest) async throws(CaptureError) -> PhoneProcessedPhoto
}

/// A request about the comparison shot, sent as ``CameraIntent/comparison(_:)``.
public enum ComparisonIntent: Equatable, Sendable {
    /// Turn the comparison shot on or off. While it is on, each single or self-timer photo is
    /// followed by the phone's fully processed photo, and the compare view opens after the app's
    /// photo is saved. Ignored when the backend can't take the second photo
    /// (``ComparisonModel/isAvailable``). Not remembered between launches.
    case setOn(Bool)

    /// Close the compare view and discard the phone's version and both pictures.
    case close
}

/// One finished comparison, for the compare view: the app's photo and the phone's version as
/// pictures, and their metadata side by side.
///
/// Privacy: in memory only, for as long as the compare view is open (``ComparisonModel``).
public struct PhotoComparison: Equatable, Sendable {
    /// The app's photo as a picture: the saved HEIF or JPEG, or the DNG when only the RAW was
    /// saved; `nil` when it couldn't be decoded or the app has no renderer.
    public let nopeImage: PhotoThumbnail?

    /// The phone's version as a picture, or `nil` when it couldn't be decoded.
    public let phoneImage: PhotoThumbnail?

    /// What the app's shown file is: its format, size and processing, from the photo's details,
    /// or `nil` when the details don't list it.
    public let nopeFile: PhotoDetails.File?

    /// The format of the phone's version.
    public let phoneFormat: PhotoFormat

    /// The size of the phone's version, in pixels.
    public let phoneDimensions: PhotoDimensions

    /// The metadata of the app's shown file and of the phone's version, side by side.
    public let metadata: MetadataComparison

    /// From the start of the app's photo to the start of the phone's version, measured with the
    /// monotonic clock.
    public let secondPhotoDelay: Duration

    /// Whether the app's picture is mirrored (a front camera photo with mirroring on, issue #45)
    /// while the phone's version isn't, so an interface mirrors the phone's picture to line the
    /// two up. The phone's file itself is never changed.
    public let mirrorsPhoneImage: Bool

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - nopeImage: the app's picture, or `nil`.
    ///   - phoneImage: The phone's picture, or `nil`.
    ///   - nopeFile: What the app's shown file is, or `nil`.
    ///   - phoneFormat: The phone's format.
    ///   - phoneDimensions: The phone's size, in pixels.
    ///   - metadata: The metadata side by side.
    ///   - secondPhotoDelay: The time between the starts of the two photos.
    ///   - mirrorsPhoneImage: Whether to mirror the phone's picture to match the app's.
    public init(
        nopeImage: PhotoThumbnail?, phoneImage: PhotoThumbnail?, nopeFile: PhotoDetails.File?, phoneFormat: PhotoFormat,
        phoneDimensions: PhotoDimensions, metadata: MetadataComparison, secondPhotoDelay: Duration,
        mirrorsPhoneImage: Bool
    ) {
        self.nopeImage = nopeImage
        self.phoneImage = phoneImage
        self.nopeFile = nopeFile
        self.phoneFormat = phoneFormat
        self.phoneDimensions = phoneDimensions
        self.metadata = metadata
        self.secondPhotoDelay = secondPhotoDelay
        self.mirrorsPhoneImage = mirrorsPhoneImage
    }
}

/// The comparison shot (issue #55): whether it is on, and the compare view's content.
///
/// ``CameraModel/comparison`` holds it; its intents arrive as ``CameraIntent/comparison(_:)``.
/// While ``isOn``, ``CameraModel`` follows each single or self-timer photo with the phone's
/// fully processed photo (``ComparisonCaptureBackend``), saves only the app's photo through
/// ``PhotoSaver`` as usual, and then fills ``state`` for the compare view.
///
/// Privacy: the phone's version never reaches the save pipeline. Its pictures and metadata are
/// kept in ``state`` only while the compare view is open; ``ComparisonIntent/close`` drops
/// them. Nothing is written to disk, logged or sent anywhere.
@MainActor
@Observable
public final class ComparisonModel {
    /// What the compare view shows.
    public enum State: Equatable, Sendable {
        /// No comparison: the compare view is closed.
        case idle
        /// The app's photo was saved and both pictures are being prepared. Show progress.
        case preparing
        /// Both photos are ready to compare.
        case ready(PhotoComparison)
        /// The app's photo was saved, but the phone's version couldn't be taken, so there is
        /// nothing to compare. Say so, and that the app's photo was saved.
        case failed(CaptureError)
    }

    /// Whether the comparison shot is on. Off at launch; not remembered.
    public private(set) var isOn = false

    /// The compare view's content.
    public private(set) var state: State = .idle

    /// Decodes both photos into pictures for the compare view, or `nil` for none: the comparison
    /// shot is then not offered (``isAvailable``). The app sets it once; `NopeDevelop`'s
    /// `ImageIOThumbnailer` with a large size does it with ImageIO, in memory. The Lock Screen
    /// capture extension sets none, so the comparison shot isn't offered on a locked device,
    /// where an extension's memory is limited and photos shouldn't be shown at full size.
    public var renderer: (any PhotoThumbnailing)?

    /// Takes the phone's version, or `nil` when the backend can't.
    let backend: (any ComparisonCaptureBackend)?

    /// Creates the comparison model.
    ///
    /// - Parameter backend: The backend that takes the phone's version, or `nil`.
    init(backend: (any ComparisonCaptureBackend)?) {
        self.backend = backend
    }

    /// Whether this device and build can take the comparison shot: the backend can take the
    /// second photo and a ``renderer`` is set. Interfaces show the switch only where it is
    /// `true`.
    public var isAvailable: Bool { backend != nil && renderer != nil }

    /// Whether the compare view is open: preparing, ready or showing the failure. The camera
    /// takes no photo while it is.
    public var isPresented: Bool { state != .idle }

    /// Handles one intent.
    ///
    /// - Parameter intent: The intent.
    func handle(_ intent: ComparisonIntent) {
        switch intent {
        case .setOn(let isOn):
            self.isOn = isOn && isAvailable
        case .close:
            state = .idle
        }
    }

    /// Takes the phone's version with a backend.
    ///
    /// - Parameters:
    ///   - request: the app's request.
    ///   - backend: The backend.
    /// - Returns: The photo, or the error.
    func takePhonePhoto(
        _ request: CaptureRequest, with backend: any ComparisonCaptureBackend
    ) async -> Result<PhoneProcessedPhoto, CaptureError> {
        do {
            return .success(try await backend.captureComparison(request))
        } catch {
            return .failure(error)
        }
    }

    /// Opens the compare view after the app's photo was saved: the failure when the phone's
    /// version couldn't be taken, otherwise both pictures and the metadata side by side.
    ///
    /// The pictures are decoded off the main actor. If the view was closed meanwhile, the result
    /// is dropped.
    ///
    /// - Parameters:
    ///   - phone: The phone's version, or why it couldn't be taken.
    ///   - saved: the app's saved photo.
    ///   - files: the app's saved files, in the order they were built.
    ///   - delay: The time between the starts of the two photos.
    ///   - mirrorsPhoneImage: Whether the app's picture is mirrored and the phone's isn't.
    func present(
        _ phone: Result<PhoneProcessedPhoto, CaptureError>, saved: SavedPhoto, files: [PhotoFile], delay: Duration,
        mirrorsPhoneImage: Bool
    ) async {
        let phonePhoto: PhoneProcessedPhoto
        switch phone {
        case .failure(let error):
            state = .failed(error)
            return
        case .success(let photo):
            phonePhoto = photo
        }
        state = .preparing
        let shown = Self.shownFile(in: files)
        let phoneFile = PhotoFile(format: phonePhoto.format, data: phonePhoto.data, isProcessedByDevice: true)
        async let nopeImage = Self.render(shown, with: renderer)
        async let phoneImage = Self.render(phoneFile, with: renderer)
        let nopeInventory = Self.inventory(of: shown, in: saved)
        let result = PhotoComparison(
            nopeImage: await nopeImage, phoneImage: await phoneImage,
            nopeFile: shown.flatMap { file in saved.details?.files.first { $0.format == file.format } },
            phoneFormat: phonePhoto.format, phoneDimensions: phonePhoto.dimensions,
            metadata: MetadataComparison(phone: phonePhoto.metadata, nope: nopeInventory), secondPhotoDelay: delay,
            mirrorsPhoneImage: mirrorsPhoneImage)
        guard state == .preparing else { return }
        state = .ready(result)
    }

    /// The app's file the compare view shows: the developed HEIF or JPEG when one was saved,
    /// because it is the same kind of file as the phone's version, otherwise the DNG.
    ///
    /// - Parameter files: the app's saved files.
    /// - Returns: The file, or `nil` for none.
    static func shownFile(in files: [PhotoFile]) -> PhotoFile? {
        files.first { $0.format != .raw } ?? files.first
    }

    /// The read-back of the app's shown file.
    ///
    /// - Parameters:
    ///   - file: The shown file, or `nil`.
    ///   - saved: the app's saved photo, with each file's read-back.
    /// - Returns: The file's read-back, or an empty inventory without a file.
    static func inventory(of file: PhotoFile?, in saved: SavedPhoto) -> MetadataInventory {
        file.flatMap { saved.metadata[$0.format] } ?? MetadataInventory()
    }

    /// Decodes a file into a picture, off the main actor.
    ///
    /// - Parameters:
    ///   - file: The file, or `nil`.
    ///   - renderer: The renderer, or `nil`.
    /// - Returns: The picture, or `nil` without a file or renderer, or when it can't be decoded.
    nonisolated static func render(_ file: PhotoFile?, with renderer: (any PhotoThumbnailing)?) async -> PhotoThumbnail? {
        guard let file, let renderer else { return nil }
        return await Task.detached { renderer.thumbnail(of: file) }.value
    }
}
