import Foundation

/// A small picture of a photo the app just saved, for the last-photo thumbnail beside the shutter
/// (issue #36).
///
/// The app has add-only Photos access and can't read the library, so the thumbnail is made from
/// the saved file while it is still in memory (``PhotoThumbnailing``).
///
/// Privacy: the pixels live in memory only, for this session. They are never written to disk,
/// logged or copied (AGENTS.md, "Photos never linger").
public struct PhotoThumbnail: Equatable, Sendable {
    /// The width, in pixels.
    public let width: Int
    /// The height, in pixels.
    public let height: Int
    /// The pixels: `width × height` RGBA values, 8 bits per channel, alpha premultiplied, in
    /// the sRGB color space, row by row from the top-left corner, with no padding between rows.
    public let rgba: Data

    /// Bytes per pixel in ``rgba``: red, green, blue and alpha, one byte each.
    public static let bytesPerPixel = 4

    /// Creates a thumbnail, or `nil` if the size and the pixel data don't match.
    ///
    /// - Parameters:
    ///   - width: The width, in pixels; at least 1.
    ///   - height: The height, in pixels; at least 1.
    ///   - rgba: The pixels, exactly `width × height × 4` bytes, as ``rgba`` describes.
    public init?(width: Int, height: Int, rgba: Data) {
        guard width > 0, height > 0, rgba.count == width * height * Self.bytesPerPixel else { return nil }
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// The bytes in one row of ``rgba``.
    public var bytesPerRow: Int { width * Self.bytesPerPixel }
}

/// Makes the last-photo thumbnail from a saved file, in memory.
///
/// `NopeDevelop` implements it with ImageIO (`ImageIOThumbnailer`). ``PhotoSaver`` calls it
/// once per saved photo, after the photo is in Photos, with the file that is quickest to read:
/// the HEIF or JPEG when there is one, otherwise the DNG.
public protocol PhotoThumbnailing: Sendable {
    /// Makes a thumbnail.
    ///
    /// - Parameter file: A file that was just saved.
    /// - Returns: The thumbnail, upright, or `nil` if the file can't be read. A missing
    ///   thumbnail never fails the save; the interface shows a photo symbol instead.
    func thumbnail(of file: PhotoFile) -> PhotoThumbnail?
}

/// What a file's Content Credentials manifest says, as the signer embedded it: for the "What's
/// in this photo" details (issue #53).
///
/// The signer fills it from the manifest it built and the manifest bytes the C2PA library
/// returned (``PhotoFile/contentCredentials``). Privacy: it holds nothing about the person or
/// the device; the manifest itself doesn't (docs/PRIVACY.md, "Content Credentials").
public struct ContentCredentialsSummary: Equatable, Sendable {
    /// The claim generator's name, "Photivra Nope Camera".
    public let generatorName: String
    /// The claim generator's version, such as `0.2.0`.
    public let generatorVersion: String
    /// The manifest's description of what happened to the file, in the manifest's own (English)
    /// words.
    public let actionDescription: String
    /// The SHA-256 hash of the embedded manifest store, as 64 lowercase hexadecimal digits.
    public let manifestSHA256: String

    /// Creates a summary.
    ///
    /// - Parameters:
    ///   - generatorName: The claim generator's name.
    ///   - generatorVersion: The claim generator's version.
    ///   - actionDescription: The manifest's description of the file.
    ///   - manifestSHA256: The manifest store's SHA-256 hash, in lowercase hexadecimal.
    public init(generatorName: String, generatorVersion: String, actionDescription: String, manifestSHA256: String) {
        self.generatorName = generatorName
        self.generatorVersion = generatorVersion
        self.actionDescription = actionDescription
        self.manifestSHA256 = manifestSHA256
    }
}

/// What ImageIO reports about the image in a file when the read-back opens it: its size and bit
/// depth (`kCGImagePropertyPixelWidth`, `kCGImagePropertyPixelHeight`, `kCGImagePropertyDepth`).
///
/// The details use it for HEIF and JPEG, whose size and depth aren't TIFF tags.
public struct ImageProperties: Equatable, Sendable {
    /// The width, in pixels, or `nil` if ImageIO didn't report one.
    public let pixelWidth: Int?
    /// The height, in pixels, or `nil` if ImageIO didn't report one.
    public let pixelHeight: Int?
    /// Bits per color channel, or `nil` if ImageIO didn't report it.
    public let depth: Int?

    /// Creates the properties.
    ///
    /// - Parameters:
    ///   - pixelWidth: The width, in pixels.
    ///   - pixelHeight: The height, in pixels.
    ///   - depth: Bits per color channel.
    public init(pixelWidth: Int?, pixelHeight: Int?, depth: Int?) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.depth = depth
    }
}

/// How long each step of taking and saving one photo took, for the details (issue #53).
///
/// Measured on the device with a monotonic clock (`ContinuousClock`); never logged or stored.
/// A step that didn't run, such as developing when only the RAW is saved, is `nil`.
public struct SaveTimings: Equatable, Sendable {
    /// From the shutter to the camera returning the photo, or `nil` for a bracket frame.
    public var capture: Duration?
    /// Developing the HEIF and JPEG from the RAW, all files together.
    public var develop: Duration?
    /// Signing every file.
    public var sign: Duration?
    /// Reading every file back and checking it against the allowlist.
    public var readBack: Duration?
    /// Adding the files to Photos.
    public var save: Duration?

    /// Creates timings.
    ///
    /// - Parameters:
    ///   - capture: The capture time, or `nil`.
    ///   - develop: The development time, or `nil`.
    ///   - sign: The signing time, or `nil`.
    ///   - readBack: The read-back time, or `nil`.
    ///   - save: The time to add to Photos, or `nil`.
    public init(
        capture: Duration? = nil, develop: Duration? = nil, sign: Duration? = nil, readBack: Duration? = nil,
        save: Duration? = nil
    ) {
        self.capture = capture
        self.develop = develop
        self.sign = sign
        self.readBack = readBack
        self.save = save
    }

    /// Adds a duration to a step's total, starting from zero.
    ///
    /// - Parameters:
    ///   - duration: The time one more run of the step took.
    ///   - step: The step.
    mutating func add(_ duration: Duration, to step: WritableKeyPath<SaveTimings, Duration?>) {
        self[keyPath: step] = (self[keyPath: step] ?? .zero) + duration
    }

    /// The duration in whole milliseconds, rounded to the nearest, for display.
    ///
    /// - Parameter duration: A duration.
    /// - Returns: The milliseconds.
    public static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int((Double(seconds) * 1000 + Double(attoseconds) / 1e15).rounded())
    }
}
