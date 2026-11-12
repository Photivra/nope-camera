import Foundation

/// How nope. develops the HEIF and JPEG it makes from the RAW. The RAW (DNG) itself is never
/// affected.
///
/// Both looks demosaic the sensor data and apply the file's own white balance and color
/// matrices, with no noise reduction, sharpening, local contrast, local tone mapping or lens
/// correction (`docs/PRIVACY.md`, "How each file's metadata is built and checked"; owner
/// decision, 2026-11-12). They differ only in the tone curve.
///
/// ``SaveSettings/developedLook`` holds the choice; a Settings screen shows it as a picker.
public enum DevelopedLook: String, CaseIterable, Codable, Hashable, Sendable {
    /// One global tone curve, the RAW developer's default for the camera, so the photo looks
    /// like a normal photo. The default.
    case standard
    /// No tone curve: the image is linear to the scene, and only the output color space's
    /// standard transfer function is applied when it is encoded, so it looks flat and low in
    /// contrast. Meant for editing afterwards.
    case flat
}
