import Foundation

/// Where a photo was taken: the only location values the app ever writes (issue #43).
///
/// Privacy rule (`docs/PRIVACY.md`, "Location"): a photo carries a location only when the person
/// turned the Location switch on and allowed location access. Then it carries exactly the
/// latitude, the longitude and, when the system knows it, the altitude, each with its EXIF
/// reference tag. No speed, direction, accuracy, satellite data, GPS time or date is written.
/// The values are the system's own, not rounded or changed.
public struct PhotoLocation: Equatable, Hashable, Sendable {
    /// The latitude in degrees, WGS 84, from −90 (south) to 90 (north).
    public let latitude: Double
    /// The longitude in degrees, WGS 84, from −180 (west) to 180 (east).
    public let longitude: Double
    /// The altitude in meters above (positive) or below (negative) sea level, or `nil` when the
    /// system has no valid altitude.
    public let altitude: Double?

    /// Creates a location.
    ///
    /// - Parameters:
    ///   - latitude: The latitude in degrees, WGS 84.
    ///   - longitude: The longitude in degrees, WGS 84.
    ///   - altitude: The altitude in meters relative to sea level, or `nil`.
    public init(latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    /// The ImageIO GPS dictionary (`kCGImagePropertyGPSDictionary`) for the location.
    ///
    /// EXIF 3.0, 4.6.6 ("GPS Attribute Information"): latitude and longitude are written as
    /// positive values with a reference of `N`/`S` and `E`/`W` (`GPSLatitudeRef`,
    /// `GPSLongitudeRef`), and altitude as a positive value with a reference of 0 (above sea
    /// level) or 1 (below) (`GPSAltitudeRef`). The keys are the values of ImageIO's
    /// `kCGImagePropertyGPS…` constants (`CGImageProperties.h`), checked against the constants
    /// by `NopeDevelopTests`.
    public var gpsProperties: [String: Any] {
        var properties: [String: Any] = [
            Self.latitudeRefKey: latitude < 0 ? "S" : "N", Self.latitudeKey: abs(latitude),
            Self.longitudeRefKey: longitude < 0 ? "W" : "E", Self.longitudeKey: abs(longitude),
        ]
        if let altitude {
            properties[Self.altitudeRefKey] = altitude < 0 ? 1 : 0
            properties[Self.altitudeKey] = abs(altitude)
        }
        return properties
    }

    /// `kCGImagePropertyGPSLatitudeRef`.
    public static let latitudeRefKey = "LatitudeRef"
    /// `kCGImagePropertyGPSLatitude`.
    public static let latitudeKey = "Latitude"
    /// `kCGImagePropertyGPSLongitudeRef`.
    public static let longitudeRefKey = "LongitudeRef"
    /// `kCGImagePropertyGPSLongitude`.
    public static let longitudeKey = "Longitude"
    /// `kCGImagePropertyGPSAltitudeRef`.
    public static let altitudeRefKey = "AltitudeRef"
    /// `kCGImagePropertyGPSAltitude`.
    public static let altitudeKey = "Altitude"
    /// `kCGImagePropertyGPSVersion`, the GPS directory's version tag (`GPSVersionID`). The app
    /// never writes it, but EXIF 3.0 makes it mandatory in a GPS directory, so the writer may add
    /// it: ImageIO on the iOS 27.2 Simulator didn't for HEIF or JPEG; whether AVFoundation does
    /// for a DNG is a device check (docs/PRIVACY.md, "Location").
    public static let versionKey = "GPSVersion"
}
