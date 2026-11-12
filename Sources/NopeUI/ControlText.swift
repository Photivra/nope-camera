import NopeCore
import SwiftUI

/// The names and value texts of the manual controls, localized and formatted with the person's
/// locale (`FormatStyle`, `Measurement`).
///
/// It only formats values `NopeCore` publishes; it decides nothing.
enum ControlText {
    /// The full name of a control, for VoiceOver and panel titles, such as "White Balance".
    ///
    /// - Parameter control: A control.
    static func name(_ control: ManualControl) -> String {
        switch control {
        case .exposureCompensation:
            String(localized: "Exposure Compensation", bundle: .module, comment: "Name of the exposure compensation control (makes photos brighter or darker than the meter's reading).")
        case .iso:
            // ISO is the standard's name (ISO 12232) and reads the same in every launch language.
            "ISO"
        case .shutter:
            String(localized: "Shutter", bundle: .module, comment: "Name of the shutter speed (exposure time) control.")
        case .aperture:
            String(localized: "Aperture", bundle: .module, comment: "Name of the lens aperture (f-number) control.")
        case .focus:
            String(localized: "Focus", bundle: .module, comment: "Name of the focus control.")
        case .whiteBalance:
            String(localized: "White Balance", bundle: .module, comment: "Name of the white balance (color temperature) control.")
        }
    }

    /// The short name shown in a grid slot, such as "WB". Voice Control accepts it too.
    ///
    /// - Parameter control: A control.
    static func shortName(_ control: ManualControl) -> String {
        switch control {
        case .exposureCompensation:
            String(localized: "EV", bundle: .module, comment: "Short label of the exposure compensation control in the control grid. EV means exposure value.")
        case .whiteBalance:
            String(localized: "WB", bundle: .module, comment: "Short label of the white balance control in the control grid.")
        case .iso, .shutter, .aperture, .focus:
            name(control)
        }
    }

    /// "Auto" or "Manual".
    ///
    /// - Parameter isManual: Whether the control is set manually.
    static func mode(isManual: Bool) -> String {
        isManual
            ? String(localized: "Manual", bundle: .module, comment: "A control set by the person, not the camera. Also the M exposure mode.")
            : String(localized: "Auto", bundle: .module, comment: "A control set automatically by the camera.")
    }

    /// The value of a control as text, such as "200", "1/500", "f/1.8", "+0.3", "5,200 K" or
    /// "Near".
    ///
    /// - Parameters:
    ///   - value: The value in the control's unit.
    ///   - control: The control.
    static func value(_ value: Double, of control: ManualControl) -> String {
        switch control {
        case .exposureCompensation:
            value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
        case .iso:
            value.formatted(.number.precision(.fractionLength(0)))
        case .shutter:
            shutter(value)
        case .aperture:
            // The f-number notation is the same in every launch language.
            "f/" + value.formatted(.number.precision(.fractionLength(0...2)))
        case .focus:
            focus(value)
        case .whiteBalance:
            Measurement(value: value.rounded(), unit: UnitTemperature.kelvin)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
    }

    /// The shortest exposure shown as seconds rather than a fraction: 0.3 s, where cameras
    /// switch from fractions to seconds.
    private static let shortestWholeSeconds = 0.3

    /// A shutter speed: "1/500" below 0.3 s, otherwise seconds, such as "2 s".
    ///
    /// - Parameter seconds: The exposure duration.
    static func shutter(_ seconds: Double) -> String {
        guard seconds >= shortestWholeSeconds - 0.001 else {
            // The fraction notation is the same in every launch language.
            return "1/" + (1 / seconds).rounded().formatted(.number.precision(.fractionLength(0)))
        }
        return Measurement(value: seconds, unit: UnitDuration.seconds)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    /// The relative focus position as a word: Near, Middle or Far. There is no distance.
    ///
    /// - Parameter position: The lens position, 0 (closest) to 1 (far).
    static func focus(_ position: Double) -> String {
        if position < 1.0 / 3.0 {
            return String(localized: "Near", bundle: .module, comment: "Focus position in the nearest third of the lens's relative range. Not a distance.")
        }
        if position < 2.0 / 3.0 {
            return String(localized: "Middle", bundle: .module, comment: "Focus position in the middle third of the lens's relative range. Not a distance.")
        }
        return String(localized: "Far", bundle: .module, comment: "Focus position in the farthest third of the lens's relative range, toward infinity. Not a distance.")
    }

    /// The range a scale covers, such as "54–12,096" or "1/16000 – 1 s".
    ///
    /// - Parameters:
    ///   - scale: The scale.
    ///   - control: The control.
    static func range(_ scale: ControlScale, of control: ManualControl) -> String {
        if control == .focus {
            return String(localized: "Closest to Far", bundle: .module, comment: "The range of the relative focus scale, from the closest focus to far. Not a distance.")
        }
        let lower = value(scale.range.lowerBound, of: control)
        let upper = value(scale.range.upperBound, of: control)
        return lower == upper ? lower : "\(lower) – \(upper)"
    }

    /// The EV meter reading, such as "−0.7 EV".
    ///
    /// - Parameter offset: The metered offset, in EV.
    static func meter(_ offset: Double) -> String {
        let number = offset.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
        return String(localized: "\(number) EV", bundle: .module, comment: "An exposure value in EV units, such as -0.7 EV. EV means exposure value.")
    }

    /// The name of an exposure mode, such as "Shutter Priority".
    ///
    /// - Parameter mode: The mode.
    static func name(_ mode: ExposureMode) -> String {
        switch mode {
        case .program:
            String(localized: "Program", bundle: .module, comment: "Exposure mode P: the camera sets ISO and shutter.")
        case .shutterPriority:
            String(localized: "Shutter Priority", bundle: .module, comment: "Exposure mode S: the person sets the shutter speed, the camera sets ISO.")
        case .isoPriority:
            String(localized: "ISO Priority", bundle: .module, comment: "Exposure mode I: the person sets ISO, the camera sets the shutter speed.")
        case .manual:
            Self.mode(isManual: true)
        }
    }

    /// The one-letter mark of an exposure mode: P, S, I or M, the marks used on camera dials.
    ///
    /// - Parameter mode: The mode.
    static func mark(_ mode: ExposureMode) -> String {
        switch mode {
        case .program: "P"
        case .shutterPriority: "S"
        case .isoPriority: "I"
        case .manual: "M"
        }
    }

    /// The name of a metering mode.
    ///
    /// - Parameter mode: The mode.
    static func name(_ mode: MeteringMode) -> String {
        switch mode {
        case .center:
            String(localized: "Center", bundle: .module, comment: "Metering mode: the camera measures a region at the center of the frame.")
        case .spot:
            String(localized: "Spot", bundle: .module, comment: "Metering mode: the camera measures a small spot at the center of the frame.")
        case .wholeFrame:
            String(localized: "Whole Frame", bundle: .module, comment: "Metering mode: the camera measures the whole frame.")
        }
    }

    /// The name of a white balance preset.
    ///
    /// - Parameter preset: The preset.
    static func name(_ preset: WhiteBalancePreset) -> String {
        switch preset {
        case .tungsten:
            String(localized: "Tungsten", bundle: .module, comment: "White balance preset for incandescent (tungsten) light.")
        case .fluorescent:
            String(localized: "Fluorescent", bundle: .module, comment: "White balance preset for fluorescent light.")
        case .daylight:
            String(localized: "Daylight", bundle: .module, comment: "White balance preset for direct daylight.")
        case .cloudy:
            String(localized: "Cloudy", bundle: .module, comment: "White balance preset for an overcast sky.")
        case .shade:
            String(localized: "Shade", bundle: .module, comment: "White balance preset for open shade.")
        }
    }

    /// An exposure step in EV as text, with thirds as fractions: "⅓ EV", "1 EV".
    ///
    /// - Parameter step: The step, in EV.
    static func step(_ step: Double) -> String {
        let thirds = Int((step * 3).rounded())
        let number: String
        switch thirds {
        case 1: number = "⅓"
        case 2: number = "⅔"
        default: number = step.formatted(.number.precision(.fractionLength(0...1)))
        }
        return String(localized: "\(number) EV", bundle: .module, comment: "An exposure value in EV units, such as -0.7 EV. EV means exposure value.")
    }
}
