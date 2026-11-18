import Foundation
import Observation

/// The battery's state, as the system reports it.
public struct BatteryReading: Equatable, Sendable {
    /// The charge from 0 to 1, or `nil` when the system doesn't know it (as in the Simulator).
    public let level: Double?

    /// Whether the device is plugged in: charging or full.
    public let isCharging: Bool

    /// Whether Low Power Mode is on.
    public let isLowPowerMode: Bool

    /// Creates a reading.
    ///
    /// - Parameters:
    ///   - level: The charge from 0 to 1, or `nil` when unknown.
    ///   - isCharging: Whether the device is plugged in.
    ///   - isLowPowerMode: Whether Low Power Mode is on.
    public init(level: Double?, isCharging: Bool, isLowPowerMode: Bool) {
        self.level = level
        self.isCharging = isCharging
        self.isLowPowerMode = isLowPowerMode
    }
}

/// Reads the device's free storage and battery state. The app implements it with the system
/// APIs; tests and the UI tests pass fakes.
///
/// Privacy rule (AGENTS.md, "Nothing tracks you"): the values are read on the device, used only
/// for the camera's warnings and never stored or sent. The free storage API is a required-reason
/// API, declared in the app's privacy manifest.
@MainActor
public protocol DeviceStatusReading {
    /// The bytes free for important data, such as photos the person takes, or `nil` when the
    /// system can't say.
    func availableStorageBytes() -> Int64?

    /// The battery's state, or `nil` on a device without a battery.
    func battery() -> BatteryReading?
}

/// A storage warning: few photos fit, or the next one doesn't (issue #44).
public enum StorageWarning: Equatable, Sendable {
    /// About this many more photos fit, fewer than ``DeviceStatus/lowStoragePhotoCount``.
    case low(photosThatFit: Int)

    /// The next photo doesn't fit: saving it would fail.
    case full
}

/// A battery warning: the battery is low and the device isn't plugged in (issue #44).
public struct BatteryWarning: Equatable, Sendable {
    /// The charge, in percent.
    public let percent: Int

    /// Whether Low Power Mode is on.
    public let isLowPowerMode: Bool

    /// Creates a warning.
    ///
    /// - Parameters:
    ///   - percent: The charge, in percent.
    ///   - isLowPowerMode: Whether Low Power Mode is on.
    public init(percent: Int, isLowPowerMode: Bool) {
        self.percent = percent
        self.isLowPowerMode = isLowPowerMode
    }
}

/// The largest a saved photo's files can be, estimated before the photo is taken.
///
/// The estimates are upper bounds chosen to warn early; they are assumptions until measured on a
/// device (docs/TESTING.md, "Low storage"):
/// - Bayer RAW: at most 16 bits a photosite (DNG 1.7, "BitsPerSample"), 2 bytes a pixel, whether
///   or not it is compressed.
/// - HEIF: 1 byte a pixel, several times what the system HEVC encoder writes at full quality.
/// - JPEG at full quality: 2.5 bytes a pixel.
/// - Each file adds up to 1 MB for its metadata, preview and Content Credentials manifest.
public enum PhotoSizeEstimate {
    /// Bytes a pixel for Bayer RAW.
    static let rawBytesPerPixel = 2.0

    /// Bytes a pixel for HEIF.
    static let heifBytesPerPixel = 1.0

    /// Bytes a pixel for JPEG.
    static let jpegBytesPerPixel = 2.5

    /// Bytes each file adds besides its pixels.
    static let fileOverheadBytes = 1_000_000.0

    /// The size assumed for a lens that doesn't report its photo sizes: 12 MP, 4032 × 3024.
    static let fallbackDimensions = PhotoDimensions(width: 4032, height: 3024)

    /// The most bytes one photo with this lens and these settings saves.
    ///
    /// - Parameters:
    ///   - lens: The lens. A lens without Bayer RAW saves only its processed fallback.
    ///   - settings: The formats chosen.
    /// - Returns: The estimate, in bytes.
    public static func bytes(for lens: Lens, settings: SaveSettings) -> Int64 {
        let dimensions = lens.photoDimensions.last ?? fallbackDimensions
        let pixels = Double(dimensions.width * dimensions.height)
        let formats: [PhotoFormat] = lens.supportsBayerRAW ? Array(settings.formats) : [lens.processedFallback.format]
        let total = formats.reduce(0.0) { sum, format in sum + pixels * bytesPerPixel(format) + fileOverheadBytes }
        return Int64(total)
    }

    /// Bytes a pixel for a format.
    ///
    /// - Parameter format: The format.
    static func bytesPerPixel(_ format: PhotoFormat) -> Double {
        switch format {
        case .raw: rawBytesPerPixel
        case .heif: heifBytesPerPixel
        case .jpeg: jpegBytesPerPixel
        }
    }
}

extension ProcessedFallback {
    /// The file format of the fallback.
    var format: PhotoFormat {
        switch self {
        case .heif: .heif
        case .jpeg: .jpeg
        }
    }
}

/// The device's free storage and battery, for the camera's warnings and to stop a burst before
/// storage runs out (issue #44).
///
/// ``CameraModel`` owns one as ``CameraModel/deviceStatus``. Nothing polls: the model reads it
/// when the camera starts, before each photo and after each save, and the app calls
/// ``refresh()`` when the system reports a battery or Low Power Mode change (AGENTS.md,
/// "Battery").
@MainActor
@Observable
public final class DeviceStatus {
    /// Below this many photos, the storage warning shows.
    public static let lowStoragePhotoCount = 25

    /// At or below this charge, unplugged, the battery warning shows: 3%, when the device is
    /// about to run out. iOS itself already warns and offers Low Power Mode at 20% (Apple
    /// Support, "Use Low Power Mode to save battery life on your iPhone"), so the camera warns
    /// only when the battery is nearly empty. An astro run stops earlier, at ``AstroModel/stopBatteryLevel``.
    public static let lowBatteryLevel = 0.03

    /// The bytes free for important data, or `nil` when unknown.
    public private(set) var availableStorageBytes: Int64?

    /// The battery's state, or `nil` when unknown.
    public private(set) var battery: BatteryReading?

    /// Reads the values, or `nil` when this build has no reader (previews).
    private let reader: (any DeviceStatusReading)?

    /// Creates the status with nothing read yet.
    ///
    /// - Parameter reader: Reads the values, or `nil` for none.
    public init(reader: (any DeviceStatusReading)?) {
        self.reader = reader
    }

    /// Whether this build reads the storage and battery at all. The Lock Screen capture
    /// extension and previews have no reader, so nothing that needs the readings (the astro
    /// helper's stops) is offered there.
    public var canRead: Bool {
        reader != nil
    }

    /// Reads the storage and battery again.
    public func refresh() {
        availableStorageBytes = reader?.availableStorageBytes()
        battery = reader?.battery()
    }

    /// Whether a photo of this size fits. `true` when the free storage is unknown, so an unknown
    /// value never blocks a burst.
    ///
    /// - Parameter bytes: The photo's estimated size.
    public func fits(bytes: Int64) -> Bool {
        guard let availableStorageBytes else { return true }
        return availableStorageBytes >= bytes
    }

    /// The storage warning for photos of this size, or `nil` when enough fit or the free storage
    /// is unknown.
    ///
    /// - Parameter bytesPerPhoto: The estimated size of one photo, more than 0.
    public func storageWarning(bytesPerPhoto: Int64) -> StorageWarning? {
        guard let availableStorageBytes, bytesPerPhoto > 0 else { return nil }
        let photosThatFit = Int(availableStorageBytes / bytesPerPhoto)
        if photosThatFit < 1 { return .full }
        return photosThatFit < Self.lowStoragePhotoCount ? .low(photosThatFit: photosThatFit) : nil
    }

    /// Whether the battery is at or below a charge and not charging. `false` when the charge is
    /// unknown, so an unknown value never stops an astro run.
    ///
    /// - Parameter level: The charge, from 0 to 1.
    public func isBatteryBelow(_ level: Double) -> Bool {
        guard let battery, let charge = battery.level, !battery.isCharging else { return false }
        return charge <= level
    }

    /// The battery warning, or `nil` when the battery isn't low, is unknown, or is charging.
    public var batteryWarning: BatteryWarning? {
        guard let battery, let level = battery.level, !battery.isCharging, level <= Self.lowBatteryLevel else {
            return nil
        }
        return BatteryWarning(percent: Int((level * 100).rounded()), isLowPowerMode: battery.isLowPowerMode)
    }
}
