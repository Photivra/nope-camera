import Foundation
import NopeCore

/// Turns the cameras the hardware reports into the lenses `NopeCore` publishes.
///
/// Rules (capability survey, item 1, and AGENTS.md, "Honesty"):
/// - only physical cameras: virtual multi-camera devices and unknown types are dropped;
/// - a lens's RAW format is its first Bayer RAW format; Apple ProRAW never counts;
/// - lenses are ordered rear ultra wide, wide, telephoto (by magnification), then front;
/// - the front camera gets no flash modes: the app uses no screen flash (issue #38).
enum LensCatalog {
    /// Builds the lens list.
    ///
    /// - Parameter devices: The cameras the hardware reported.
    /// - Returns: The usable lenses, in display order.
    static func lenses(from devices: [CameraDeviceDescription]) -> [Lens] {
        let physical = devices.filter { !$0.isVirtual && $0.deviceType != .other }
        let referenceFieldOfView = physical.first {
            $0.position != .front && $0.deviceType == .wideAngle
        }?.fieldOfViewDegrees
        let lenses = physical.map { lens(from: $0, referenceFieldOfView: referenceFieldOfView) }
        return lenses.enumerated().sorted { left, right in
            let leftKey = sortKey(left.element)
            let rightKey = sortKey(right.element)
            return leftKey == rightKey ? left.offset < right.offset : leftKey < rightKey
        }.map(\.element)
    }

    /// Builds one lens.
    ///
    /// - Parameters:
    ///   - device: The camera.
    ///   - referenceFieldOfView: The rear wide camera's field of view in degrees, or `nil`.
    /// - Returns: The lens description.
    private static func lens(from device: CameraDeviceDescription, referenceFieldOfView: Double?) -> Lens {
        let kind = kind(of: device)
        let bayer = device.rawPixelFormats.first { $0.isBayer }.map { FourCharacterCode.string($0.code) }
        let magnification = kind == .front ? nil : referenceFieldOfView.flatMap {
            magnification(fieldOfView: device.fieldOfViewDegrees, reference: $0)
        }
        return Lens(
            id: device.uniqueID,
            kind: kind,
            bayerRAWFormat: bayer,
            processedFallback: device.supportsHEVC ? .heif : .jpeg,
            magnification: magnification,
            isoRange: device.isoRange,
            exposureDurationRange: device.exposureDurationRange,
            aperture: device.aperture,
            maxBracketedPhotoCount: device.maxBracketedPhotoCount,
            photoDimensions: device.photoDimensions.sorted { $0.pixelCount < $1.pixelCount },
            manualControls: device.manualControls.capabilities,
            equivalentFocalLength: equivalentFocalLength(
                fieldOfView: device.fieldOfViewDegrees, photoSize: device.photoDimensions.max { $0.pixelCount < $1.pixelCount }),
            flashModes: kind == .front ? [] : device.flashModes,
            hasTorch: device.hasTorch
        )
    }

    /// The diagonal of a 35 mm film frame (36 × 24 mm), in millimeters: the reference for a
    /// 35 mm-equivalent focal length (CIPA DC-008, `FocalLengthIn35mmFilm`, compares angles of
    /// view on this frame).
    static let filmDiagonal = (36.0 * 36.0 + 24.0 * 24.0).squareRoot()

    /// The 35 mm-equivalent focal length of a lens: the focal length that gives a 35 mm film
    /// frame the same diagonal angle of view, `(diagonal / 2) / tan(diagonal angle / 2)`. The
    /// diagonal angle comes from the horizontal angle and the photo's shape:
    /// `tan(diagonal / 2) = tan(horizontal / 2) × diagonal / width`.
    ///
    /// - Parameters:
    ///   - fieldOfView: The horizontal field of view, in degrees (`videoFieldOfView`).
    ///   - photoSize: The largest photo size, for its shape; 4:3 when `nil`.
    /// - Returns: The focal length in millimeters, or `nil` if the angle isn't between 0 and
    ///   180 degrees.
    static func equivalentFocalLength(fieldOfView: Double, photoSize: PhotoDimensions?) -> Double? {
        guard fieldOfView > 0, fieldOfView < 180 else { return nil }
        let width = Double(photoSize?.width ?? 4)
        let height = Double(photoSize?.height ?? 3)
        let shape = width > 0 && height > 0 ? (width * width + height * height).squareRoot() / max(width, height) : 1.25
        return (filmDiagonal / 2) / (tan(fieldOfView * .pi / 360) * shape)
    }

    /// The `NopeCore` kind: any front camera is ``Lens/Kind/front``; rear cameras follow their
    /// device type.
    ///
    /// - Parameter device: A physical camera (not ``CameraDeviceDescription/DeviceType/other``).
    private static func kind(of device: CameraDeviceDescription) -> Lens.Kind {
        if device.position == .front { return .front }
        switch device.deviceType {
        case .ultraWide: return .ultraWide
        case .telephoto: return .telephoto
        case .wideAngle, .other: return .wide
        }
    }

    /// How much closer a lens sees than the reference, from both horizontal fields of view:
    /// `tan(reference / 2) / tan(fieldOfView / 2)`, rounded for labels: to 0.1 below 1×, and to
    /// the nearest 0.5 from 1× up (for example 0.5×, 1×, 2.5×, 5×).
    ///
    /// - Parameters:
    ///   - fieldOfView: The lens's horizontal field of view, in degrees.
    ///   - reference: The rear wide camera's horizontal field of view, in degrees.
    /// - Returns: The magnification, or `nil` if either angle isn't between 0 and 180 degrees.
    static func magnification(fieldOfView: Double, reference: Double) -> Double? {
        let valid = 0.0..<180.0
        guard valid.contains(fieldOfView), valid.contains(reference), fieldOfView > 0, reference > 0 else {
            return nil
        }
        let ratio = tan(reference * .pi / 360) / tan(fieldOfView * .pi / 360)
        return ratio < 0.95 ? (ratio * 10).rounded() / 10 : (ratio * 2).rounded() / 2
    }

    /// Display order: rear lenses by magnification (unknown last among rear lenses), then
    /// front lenses.
    ///
    /// - Parameter lens: A lens.
    /// - Returns: A key that sorts lenses into display order.
    private static func sortKey(_ lens: Lens) -> Double {
        if lens.kind == .front { return .infinity }
        return lens.magnification ?? .greatestFiniteMagnitude
    }
}
