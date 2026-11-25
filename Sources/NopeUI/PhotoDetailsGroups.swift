import NopeCore
import SwiftUI

/// Exposure (`docs/design/BUILD-SPEC.md`, 3.15, group 1): the exposure as the files record it,
/// with the less-asked values behind More Exposure Details. When the files hold no exposure, the
/// shutter and ISO the camera reported, each marked "Not in the files".
struct ExposureSection: View {
    /// The details.
    let details: PhotoDetails

    /// Creates the group.
    ///
    /// - Parameter details: The details.
    init(details: PhotoDetails) {
        self.details = details
    }

    /// Whether the person turned the exposure settings off, so the files hold none.
    private var isTurnedOff: Bool {
        details.items.contains { $0.item == .exposureSettings && $0.state == .removed }
    }

    /// The group.
    var body: some View {
        Section {
            if let exposure = details.exposure {
                written(exposure)
            } else if let capture = details.exposureNotInFiles {
                if let time = capture.exposureDuration {
                    DetailRow(title: Text(ControlText.name(.shutter)), value: Text(verbatim: ControlText.value(time, of: .shutter)), note: PhotoDetailsText.notInFiles)
                }
                if let iso = capture.iso {
                    DetailRow(title: Text(ControlText.name(.iso)), value: Text(verbatim: ControlText.value(iso, of: .iso)), note: PhotoDetailsText.notInFiles)
                }
            } else {
                Text("The files don't record the exposure.", tableName: "Honesty", bundle: .module, comment: "Shown in the photo details when the saved files hold no exposure values although the exposure settings item is on, because the camera didn't supply them.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Photo details: Exposure", bundle: .module, comment: "Heading in the photo details: the shutter speed, ISO, aperture and other exposure values.")
        } footer: {
            if details.exposure != nil {
                PhotoDetailsText.asWritten
            } else if details.exposureNotInFiles != nil && isTurnedOff {
                Text("Exposure Settings is off, so the files don't hold the exposure. These are the values the camera reported for this photo. nope. keeps them only until it closes.", tableName: "Honesty", bundle: .module, comment: "Footer of the Exposure group in the photo details when the files hold no exposure: the shutter and ISO shown are what the camera reported, kept in memory until the app closes. Exposure Settings is the name of the setting. Keep nope. unchanged. Draft wording for the Honesty review.")
            } else if details.exposureNotInFiles != nil {
                Text("The files don't record the exposure.", tableName: "Honesty", bundle: .module, comment: "Shown in the photo details when the saved files hold no exposure values although the exposure settings item is on, because the camera didn't supply them.")
            }
        }
    }

    /// The exposure the files record.
    ///
    /// - Parameter exposure: The exposure.
    @ViewBuilder private func written(_ exposure: PhotoDetails.Exposure) -> some View {
        if let time = exposure.exposureTime {
            DetailRow(title: Text(ControlText.name(.shutter)), value: Text(verbatim: ControlText.value(time, of: .shutter)))
        }
        if let iso = exposure.iso {
            DetailRow(title: Text(ControlText.name(.iso)), value: Text(verbatim: ControlText.value(iso, of: .iso)))
        }
        if let fNumber = exposure.fNumber {
            DetailRow(title: Text(ControlText.name(.aperture)), value: Text(verbatim: ControlText.value(fNumber, of: .aperture)))
        }
        if let focalLength = exposure.focalLength {
            DetailRow(
                title: Text("Focal Length", bundle: .module, comment: "Row in the photo details: the lens's real focal length, in millimeters, as written in the file."),
                value: Text(verbatim: Self.millimeters(focalLength)))
        }
        if let equivalent = exposure.equivalentFocalLength {
            DetailRow(
                title: Text("35 mm Equivalent", bundle: .module, comment: "Row in the photo details: the focal length a 35 mm film camera would need for the same field of view, in millimeters, as written in the file."),
                value: Text(verbatim: Self.millimeters(equivalent)))
        }
        if let bias = exposure.exposureBias {
            DetailRow(title: Text(ControlText.name(.exposureCompensation)), value: Text(verbatim: ControlText.meter(bias)))
        }
        if let whiteBalance = exposure.whiteBalance {
            DetailRow(title: Text(ControlText.name(.whiteBalance)), value: Text(verbatim: ControlText.mode(isManual: whiteBalance == .manual)))
        }
        if let fired = exposure.flashFired {
            DetailRow(
                title: Text("Flash", bundle: .module, comment: "Camera menu and its Voice Control name: when the flash fires (Off, Auto, On)."),
                value: fired
                    ? Text("Fired", bundle: .module, comment: "In the photo details, the flash as the file records it: the flash fired for this photo.")
                    : Text("Didn't fire", bundle: .module, comment: "In the photo details, the flash as the file records it: the flash didn't fire for this photo."))
        }
        if exposure.hasMoreDetails {
            DisclosureGroup {
                more(exposure)
            } label: {
                Text("More Exposure Details", bundle: .module, comment: "Disclosure row in the photo details: opens the less-asked exposure values (exposure mode, program, metering, brightness, largest aperture, subject area).")
            }
        }
    }

    /// The values behind More Exposure Details.
    ///
    /// - Parameter exposure: The exposure.
    @ViewBuilder private func more(_ exposure: PhotoDetails.Exposure) -> some View {
        if let mode = exposure.exposureMode {
            DetailRow(
                title: Text("Exposure Mode", bundle: .module, comment: "Row in the photo details: the EXIF exposure mode, such as Auto or Manual."),
                value: Text(verbatim: PhotoDetailsText.name(of: mode)))
        }
        if let program = exposure.program {
            DetailRow(
                title: Text("Photo details: Program", bundle: .module, comment: "Row in the photo details: the EXIF exposure program the camera used, such as Normal program."),
                value: Text(verbatim: PhotoDetailsText.name(of: program)))
        }
        if let metering = exposure.metering {
            DetailRow(
                title: Text("Metering", bundle: .module, comment: "Picker for how auto exposure measures the scene."),
                value: Text(verbatim: PhotoDetailsText.name(of: metering)))
        }
        if let brightness = exposure.brightness {
            DetailRow(
                title: Text("Scene Brightness", bundle: .module, comment: "Row in the photo details: the brightness of the scene the camera measured, in EV, as written in the file."),
                value: Text(verbatim: ControlText.meter(brightness)))
        }
        if let largest = exposure.largestAperture {
            DetailRow(
                title: Text("Largest Aperture", bundle: .module, comment: "Row in the photo details: the lens's widest aperture, as an f-number, as written in the file."),
                value: Text(verbatim: ControlText.value(largest, of: .aperture)))
        }
        if !exposure.subjectArea.isEmpty {
            DetailRow(
                title: Text("Subject Area", bundle: .module, comment: "Row in the photo details: where the subject is in the picture, as two to four numbers in pixels, as written in the file."),
                value: Text(verbatim: PhotoDetailsText.numbers(exposure.subjectArea)))
        }
    }

    /// A length in millimeters, such as "6.86 mm".
    ///
    /// - Parameter value: The length in millimeters.
    /// - Returns: The text.
    static func millimeters(_ value: Double) -> String {
        Measurement(value: value, unit: UnitLength.millimeters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2))))
    }
}

/// Lens and Camera (group 2): the names the files hold; with none, the lens that was selected,
/// marked "Not in the files". Left out when there is neither.
struct LensSection: View {
    /// The details.
    let details: PhotoDetails

    /// The lens the photo was taken with, or `nil`.
    let lens: Lens?

    /// Creates the group.
    ///
    /// - Parameters:
    ///   - details: The details.
    ///   - lens: The lens, or `nil`.
    init(details: PhotoDetails, lens: Lens?) {
        self.details = details
        self.lens = lens
    }

    /// The lens title.
    private var lensTitle: Text {
        Text("Photo details: Lens", bundle: .module, comment: "Row in the photo details: the lens the photo was taken with.")
    }

    /// The group.
    var body: some View {
        if let names = details.lensAndCamera {
            Section {
                if let model = names.lensModel {
                    DetailRow(title: lensTitle, value: Text(verbatim: model))
                } else if details.lensNotInFiles != nil, let lens {
                    DetailRow(title: lensTitle, value: Text(verbatim: PhotoDetailsText.name(of: lens)), note: PhotoDetailsText.notInFiles)
                }
                if let make = names.lensMake {
                    DetailRow(title: Text("Lens Maker", bundle: .module, comment: "Row in the photo details: the maker of the lens, as written in the file."), value: Text(verbatim: make))
                }
                if let camera = names.camera {
                    DetailRow(title: Text("Photo details: Camera", bundle: .module, comment: "Row in the photo details: the camera's maker and model, as written in the file."), value: Text(verbatim: camera))
                }
            } header: {
                header
            } footer: {
                PhotoDetailsText.asWritten
            }
        } else if details.lensNotInFiles != nil, let lens {
            Section {
                DetailRow(title: lensTitle, value: Text(verbatim: PhotoDetailsText.name(of: lens)), note: PhotoDetailsText.notInFiles)
            } header: {
                header
            } footer: {
                Text("Lens and camera names are off in Settings, so the files don't hold them.", tableName: "Honesty", bundle: .module, comment: "Footer of the Lens and Camera group in the photo details when the files hold no lens or camera names: the lens shown is the one that was selected. Draft wording for the Honesty review.")
            }
        }
    }

    /// The group's heading.
    private var header: some View {
        Text("Lens and Camera", bundle: .module, comment: "Heading in the photo details: the lens and camera names.")
    }
}

/// RAW Sensor Data (group 3): the RAW file's size, bit depth, color filter, clipping and lens
/// corrections, with the levels, structure and each color's clipping behind More Sensor Details.
/// Shown only for a photo with RAW.
struct SensorSection: View {
    /// The RAW file.
    let file: PhotoDetails.File

    /// The clipping counted at capture, or why it wasn't; `nil` when unknown.
    let clipping: RAWClippingResult?

    /// Creates the group.
    ///
    /// - Parameters:
    ///   - file: The RAW file.
    ///   - clipping: The clipping, or `nil`.
    init(file: PhotoDetails.File, clipping: RAWClippingResult?) {
        self.file = file
        self.clipping = clipping
    }

    /// The group.
    var body: some View {
        Section {
            if let pixels = PhotoDetailsText.pixels(of: file) {
                DetailRow(
                    title: Text("Photo details: Size", bundle: .module, comment: "Row in the photo details: the RAW image's size in pixels, with its megapixels under it."),
                    value: Text(verbatim: pixels),
                    note: file.megapixels.map { megapixels in
                        Text("\(megapixels.formatted(.number.precision(.fractionLength(0...1)))) MP", bundle: .module, comment: "In the photo details, under a size in pixels: the number of megapixels, such as 12 MP. MP means megapixels.")
                    })
            }
            if let bitDepth = file.bitDepth {
                DetailRow(title: Text("Bit Depth", bundle: .module, comment: "Row in the photo details: the bits stored for each sample of the RAW, such as 12."), value: Text(verbatim: bitDepth.formatted()))
            }
            if let pattern = file.colorFilterPattern {
                DetailRow(title: Text("Color Filter Pattern", bundle: .module, comment: "Row in the photo details: the RAW sensor's color filter pattern, as letters such as RGGB (R red, G green, B blue). Keep the letters unchanged."), value: Text(verbatim: pattern))
            }
            switch clipping {
            case .measured(let clipping):
                DetailRow(
                    title: Text("Clipped Highlights", bundle: .module, comment: "Row in the photo details: the share of the RAW's photosites recorded at or near the white level (full)."),
                    value: Self.share(clipping.highlightShare))
                DetailRow(
                    title: Text("Clipped Shadows", bundle: .module, comment: "Row in the photo details: the share of the RAW's photosites recorded at or near the black level (no signal)."),
                    value: Self.share(clipping.shadowShare))
            case .notMeasured(let failure):
                Self.reason(failure).fixedSize(horizontal: false, vertical: true)
            case nil:
                EmptyView()
            }
            DetailRow(
                title: Text("Lens Corrections", bundle: .module, comment: "Row in the photo details: whether the RAW file holds lens correction instructions."),
                value: file.storesLensCorrections
                    ? Text("Stored, not applied", tableName: "Honesty", bundle: .module, comment: "In the photo details: the RAW file holds lens correction instructions that editors can use, but nope. didn't apply them to the pixels.")
                    : Text("Not stored", tableName: "Honesty", bundle: .module, comment: "In the photo details: the RAW file holds no lens correction instructions."))
            DisclosureGroup {
                more
            } label: {
                Text("More Sensor Details", bundle: .module, comment: "Disclosure row in the photo details: opens each color's clipping, the black and white levels and the RAW file's structure.")
            }
        } header: {
            Text("RAW Sensor Data", bundle: .module, comment: "Heading in the photo details: facts about the RAW file's sensor data. RAW is a file format name.")
        }
    }

    /// The values behind More Sensor Details.
    @ViewBuilder private var more: some View {
        if case .measured(let clipping) = clipping {
            ForEach(clipping.channels, id: \.color) { channel in
                DetailRow(
                    title: Self.name(of: channel.color),
                    value: Text(
                        "Highlights \(Self.percent(channel.highlightShare)), shadows \(Self.percent(channel.shadowShare))", bundle: .module,
                        comment: "In the photo details, one color of the RAW sensor's color filter: the share of its photosites that are clipped highlights, then clipped shadows, as percentages."))
            }
        }
        if !file.blackLevels.isEmpty {
            DetailRow(title: Text("Black Level", bundle: .module, comment: "Row in the photo details: the RAW file's black level values, as numbers."), value: Text(verbatim: PhotoDetailsText.numbers(file.blackLevels)))
        }
        if !file.whiteLevels.isEmpty {
            DetailRow(title: Text("White Level", bundle: .module, comment: "Row in the photo details: the RAW file's white level values, as numbers."), value: Text(verbatim: PhotoDetailsText.numbers(file.whiteLevels)))
        }
        if let structure = file.rawStructure {
            if !structure.activeArea.isEmpty {
                DetailRow(title: Text("Active Area", bundle: .module, comment: "Row in the photo details: the DNG ActiveArea, the part of the sensor with image data, as four numbers (top, left, bottom, right)."), value: Text(verbatim: PhotoDetailsText.numbers(structure.activeArea)))
            }
            if structure.defaultCropSize.count == 2 {
                DetailRow(title: Text("Default Crop", bundle: .module, comment: "Row in the photo details: the DNG default crop, its size and origin."), value: Self.crop(structure))
            }
            if let compression = structure.compression {
                DetailRow(title: Text("Compression", bundle: .module, comment: "Row in the photo details: how the RAW data is compressed."), value: Self.name(of: compression))
            }
            if let version = structure.dngVersionText {
                DetailRow(title: Text("DNG Version", bundle: .module, comment: "Row in the photo details: the version of the DNG specification the RAW file follows. DNG is a file format name."), value: Text(verbatim: version))
            }
            if let baseline = structure.baselineExposure {
                DetailRow(title: Text("Baseline Exposure", bundle: .module, comment: "Row in the photo details: the DNG BaselineExposure, in EV, that raw editors apply by default."), value: Text(verbatim: ControlText.meter(baseline)))
            }
            if !structure.asShotNeutral.isEmpty {
                DetailRow(title: Text("As-Shot Neutral", bundle: .module, comment: "Row in the photo details: the DNG AsShotNeutral, the white balance at capture, as one number per color."), value: Text(verbatim: PhotoDetailsText.numbers(structure.asShotNeutral)))
            }
        }
        if case .measured = clipping {
            Text(
                "Counted on the RAW sensor data when the photo was taken, over every photosite of the active area. Clipped highlights are within 0.5% of the white level or above it; clipped shadows are within 0.5% of the black level or below it, where 0.5% is of the range between the two levels.",
                tableName: "Honesty", bundle: .module,
                comment: "Footer in the photo details: how the RAW clipping is defined and measured. A photosite is one sensor element. The white and black levels are the RAW file's own values. Must not claim more than the English.")
                .font(.footnote)
                .foregroundStyle(CameraStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The default crop, such as "4032 × 3024 at 0, 0".
    ///
    /// - Parameter structure: The DNG's structure, with a crop size of two numbers.
    /// - Returns: The text.
    static func crop(_ structure: PhotoDetails.RAWStructure) -> Text {
        let size = structure.defaultCropSize.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...2))) }
            .joined(separator: " × ")
        let origin = PhotoDetailsText.numbers(structure.defaultCropOrigin.isEmpty ? [0, 0] : structure.defaultCropOrigin)
        return Text("\(size) at \(origin)", bundle: .module, comment: "In the photo details: the DNG default crop, its size then its origin, such as 4032 × 3024 at 0, 0.")
    }

    /// A RAW compression's name, or its code.
    ///
    /// - Parameter compression: The compression.
    /// - Returns: The text.
    static func name(of compression: PhotoDetails.RAWCompression) -> Text {
        switch compression {
        case .uncompressed: Text("Uncompressed", bundle: .module, comment: "In the photo details: the RAW data isn't compressed (TIFF compression 1).")
        case .losslessJPEG: Text("Lossless JPEG", bundle: .module, comment: "In the photo details: the RAW data is compressed with lossless JPEG (DNG compression 7). JPEG is a format name.")
        case .lossyJPEG: Text("Lossy JPEG", bundle: .module, comment: "In the photo details: the RAW data is compressed with lossy JPEG (DNG compression 34892). JPEG is a format name.")
        case .jpegXL: Text(verbatim: "JPEG XL")
        case .other(let code): Text(verbatim: code.formatted(.number.grouping(.never)))
        }
    }

    /// A share of photosites, such as "0.4% of photosites".
    ///
    /// - Parameter share: The share, 0 to 1.
    /// - Returns: The text.
    static func share(_ share: Double) -> Text {
        Text("\(percent(share)) of photosites", bundle: .module, comment: "In the photo details: a share of the RAW's photosites, such as 0.4% of photosites. A photosite is one sensor element.")
    }

    /// A share as a percentage with up to two significant digits, such as "0.4%" or "0.0012%",
    /// so a small share never reads as 0; exactly 0 is "0%".
    ///
    /// - Parameter share: The share, 0 to 1.
    /// - Returns: The percentage, in the current language.
    static func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.significantDigits(1...2)))
    }

    /// The name of a color of the color filter.
    ///
    /// - Parameter color: The color.
    /// - Returns: The name.
    static func name(of color: CFAColor) -> Text {
        switch color {
        case .red: Text("Red", bundle: .module, comment: "In the photo details: the red photosites of the RAW sensor's color filter.")
        case .green: Text("Green", bundle: .module, comment: "In the photo details: the green photosites of the RAW sensor's color filter.")
        case .blue: Text("Blue", bundle: .module, comment: "In the photo details: the blue photosites of the RAW sensor's color filter.")
        }
    }

    /// Why the clipping wasn't measured, in plain words.
    ///
    /// - Parameter failure: The reason.
    /// - Returns: The text, from `Honesty.xcstrings`.
    static func reason(_ failure: RAWClippingFailure) -> Text {
        switch failure {
        case .noSamples:
            Text("Not measured: the camera gave no RAW samples to count.", tableName: "Honesty", bundle: .module, comment: "In the photo details, why the RAW clipping isn't shown: the camera returned no RAW sensor samples with the photo.")
        case .unsupportedLayout:
            Text("Not measured: nope. can't read how this camera lays out its RAW samples.", tableName: "Honesty", bundle: .module, comment: "In the photo details, why the RAW clipping isn't shown: the camera's RAW sample format isn't one nope. reads. Keep nope. unchanged.")
        case .levelsUnreadable:
            Text("Not measured: the camera's RAW file doesn't give black and white levels that nope. can apply.", tableName: "Honesty", bundle: .module, comment: "In the photo details, why the RAW clipping isn't shown: the RAW file's black and white levels are missing or in a form nope. doesn't apply. Keep nope. unchanged.")
        case .sizeMismatch:
            Text("Not measured: the RAW samples and the RAW file differ in size.", tableName: "Honesty", bundle: .module, comment: "In the photo details, why the RAW clipping isn't shown: the camera's RAW samples and its RAW file don't have the same size, so they can't be compared.")
        case .scaleMismatch:
            Text("Not measured: the RAW samples don't fit the RAW file's white level.", tableName: "Honesty", bundle: .module, comment: "In the photo details, why the RAW clipping isn't shown: the camera's RAW sample values are larger than the RAW file's white level allows, so they can't be compared.")
        }
    }
}

/// Files (group 4): one row for each file, with its size, pixels, bit depth and, for a developed
/// copy, color space and quality; then how a RAW and a copy were added to Photos.
struct FilesSection: View {
    /// The details.
    let details: PhotoDetails

    /// Creates the group.
    ///
    /// - Parameter details: The details.
    init(details: PhotoDetails) {
        self.details = details
    }

    /// The group.
    var body: some View {
        Section {
            ForEach(Array(details.files.enumerated()), id: \.offset) { _, file in
                DetailRow(
                    title: Text(verbatim: FormatsSettingsView.name(of: file.format)),
                    value: Text(verbatim: file.byteCount.formatted(.byteCount(style: .file))),
                    note: Self.facts(of: file))
            }
            if let pairing = details.inPhotos {
                DetailRow(title: Text("In Photos", tableName: "Honesty", bundle: .module, comment: "Row in the photo details: how the files were added to the Photos app. Photos is the system photo library app. Draft wording for the Honesty review."), value: Self.pairing(pairing))
            }
        } header: {
            Text("Files", bundle: .module, comment: "Heading in the photo details: the files saved for this photo.")
        }
    }

    /// A file's pixels, bit depth and, for a developed copy, color space and quality; for a RAW,
    /// "lossless" when its compression keeps every value.
    ///
    /// - Parameter file: The file.
    /// - Returns: The text, or `nil` without a pixel size.
    static func facts(of file: PhotoDetails.File) -> Text? {
        guard let pixels = PhotoDetailsText.pixels(of: file) else { return nil }
        guard let bitDepth = file.bitDepth else { return Text(verbatim: pixels) }
        if file.rawStructure?.compression?.isLossless == true {
            return Text("\(pixels) · \(bitDepth)-bit · lossless", bundle: .module, comment: "In the photo details, under a RAW file: its pixels, bit depth and that its compression is lossless, such as 4032 × 3024 pixels · 12-bit · lossless.")
        }
        if let space = file.colorSpace, let quality = file.quality {
            return Text("\(pixels) · \(bitDepth)-bit · \(CopiesSettingsView.name(of: space)) · \(CopiesSettingsView.title(of: quality))", bundle: .module, comment: "In the photo details, under a HEIF or JPEG copy: its pixels, bit depth, color space and compression quality, such as 4032 × 3024 pixels · 10-bit · Display P3 · High Quality. The last placeholder is the name of the compression choice in Settings.")
        }
        return Text("\(pixels) · \(bitDepth)-bit", bundle: .module, comment: "In the photo details, under a file: its pixels and bit depth, such as 4032 × 3024 pixels · 10-bit.")
    }

    /// How a RAW and a copy were added to Photos.
    ///
    /// - Parameter pairing: The pairing.
    /// - Returns: The sentence, from `Honesty.xcstrings`.
    static func pairing(_ pairing: PhotoDetails.PhotosPairing) -> Text {
        let paired = FormatsSettingsView.name(of: pairing.pairedFormat)
        guard let separate = pairing.separateFormat.map(FormatsSettingsView.name(of:)) else {
            return Text("One photo: the RAW with its \(paired)", tableName: "Honesty", bundle: .module, comment: "In the photo details: the RAW and its copy (the placeholder is its format, such as HEIF) were added to Photos as one photo. States what nope. asked Photos to do. RAW is a file format name. Draft wording for the Honesty review.")
        }
        return Text("One photo: the RAW with its \(paired). The \(separate) is a photo of its own.", tableName: "Honesty", bundle: .module, comment: "In the photo details: the RAW and one copy (first placeholder, such as HEIF) were added to Photos as one photo, and the other copy (second placeholder, such as JPEG) as a photo of its own. States what nope. asked Photos to do. Draft wording for the Honesty review.")
    }
}

/// Processing (group 5): what was done to each file's picture and by whom; for a processed
/// fallback, the lens's distortion correction and what the app did.
struct ProcessingSection: View {
    /// The details.
    let details: PhotoDetails

    /// Creates the group.
    ///
    /// - Parameter details: The details.
    init(details: PhotoDetails) {
        self.details = details
    }

    /// The group.
    var body: some View {
        Section {
            ForEach(Array(details.files.enumerated()), id: \.offset) { _, file in
                VStack(alignment: .leading, spacing: NopeSpace.xxs) {
                    if file.processing == .byDevice {
                        SymbolLine(
                            text: PhotoDetailsSections.processing(file.processing),
                            symbol: "exclamationmark.triangle.fill", style: AnyShapeStyle(CameraStyle.warning))
                    } else {
                        Text(verbatim: FormatsSettingsView.name(of: file.format))
                        PhotoDetailsSections.processing(file.processing)
                            .foregroundStyle(CameraStyle.secondaryText)
                        Self.look(of: file.processing)
                            .font(.footnote)
                            .foregroundStyle(CameraStyle.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
            // A processed fallback: whether the lens let the app turn off distortion correction
            // (issue #80), and that the app didn't change the picture. RAW never has the
            // correction, so a RAW photo has neither line.
            if let correction = details.distortionCorrection {
                ProcessingNote.distortion(correction)
                    .fixedSize(horizontal: false, vertical: true)
                Text("nope. didn't change this file's picture.", tableName: "Honesty", bundle: .module, comment: "In the photo details, for a file the phone's camera processed (a lens without RAW): nope. didn't change its picture. Keep nope. unchanged. Draft wording for the Honesty review.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Processing", bundle: .module, comment: "Heading in the photo details: what processing each file went through.")
        }
    }

    /// What a developed copy's look does, or nothing for other files.
    ///
    /// - Parameter processing: The processing.
    /// - Returns: The sentence, from `Honesty.xcstrings`.
    @ViewBuilder static func look(of processing: PhotoDetails.Processing) -> some View {
        switch processing {
        case .developed(.standard):
            Text("One overall tone curve. nope. turns off noise reduction, sharpening and local tone mapping.", tableName: "Honesty", bundle: .module, comment: "In the photo details, under a copy developed with the Standard look: what the look does. The same claims as the processing note. Draft wording for the Honesty review.")
        case .developed(.flat):
            Text("No contrast curve. nope. turns off noise reduction, sharpening and local tone mapping.", tableName: "Honesty", bundle: .module, comment: "In the photo details, under a copy developed with the Flat look: what the look does. The same claims as the processing note. Draft wording for the Honesty review.")
        case .none, .byDevice:
            EmptyView()
        }
    }
}

extension PhotoDetailsText {
    /// The name of an EXIF exposure mode: the app's Auto and Manual, or the EXIF term.
    ///
    /// - Parameter mode: The value.
    /// - Returns: The name, or the code as a number.
    static func name(of mode: PhotoDetails.ExposureModeValue) -> String {
        switch mode {
        case .auto: ControlText.mode(isManual: false)
        case .manual: ControlText.mode(isManual: true)
        case .autoBracket: String(localized: "Auto bracket", bundle: .module, comment: "In the photo details: the EXIF exposure mode Auto bracket, the camera took a bracket of exposures.")
        case .other(let code): code.formatted(.number.grouping(.never))
        }
    }

    /// The EXIF term for an exposure program.
    ///
    /// - Parameter program: The value.
    /// - Returns: The name, or the code as a number.
    static func name(of program: PhotoDetails.ExposureProgramValue) -> String {
        switch program {
        case .notDefined: String(localized: "Not defined", bundle: .module, comment: "In the photo details: the EXIF exposure program Not defined.")
        case .manual: String(localized: "EXIF program: Manual", bundle: .module, comment: "In the photo details: the EXIF exposure program Manual.")
        case .normal: String(localized: "Normal program", bundle: .module, comment: "In the photo details: the EXIF exposure program Normal program, the camera's automatic exposure.")
        case .aperturePriority: String(localized: "EXIF program: Aperture priority", bundle: .module, comment: "In the photo details: the EXIF exposure program Aperture priority.")
        case .shutterPriority: String(localized: "EXIF program: Shutter priority", bundle: .module, comment: "In the photo details: the EXIF exposure program Shutter priority.")
        case .creative: String(localized: "Creative program", bundle: .module, comment: "In the photo details: the EXIF exposure program Creative program, biased toward depth of field.")
        case .action: String(localized: "Action program", bundle: .module, comment: "In the photo details: the EXIF exposure program Action program, biased toward a fast shutter.")
        case .portrait: String(localized: "Portrait mode", bundle: .module, comment: "In the photo details: the EXIF exposure program Portrait mode.")
        case .landscape: String(localized: "Landscape mode", bundle: .module, comment: "In the photo details: the EXIF exposure program Landscape mode.")
        case .other(let code): code.formatted(.number.grouping(.never))
        }
    }

    /// The name of an EXIF metering mode: the app's Center and Spot, or the EXIF term.
    ///
    /// - Parameter metering: The value.
    /// - Returns: The name, or the code as a number.
    static func name(of metering: PhotoDetails.MeteringValue) -> String {
        switch metering {
        case .centerWeighted: ControlText.name(MeteringMode.center)
        case .spot: ControlText.name(MeteringMode.spot)
        case .unknown: String(localized: "EXIF metering: Unknown", bundle: .module, comment: "In the photo details: the EXIF metering mode Unknown.")
        case .average: String(localized: "Average", bundle: .module, comment: "In the photo details: the EXIF metering mode Average.")
        case .multiSpot: String(localized: "Multi-spot", bundle: .module, comment: "In the photo details: the EXIF metering mode Multi-spot.")
        case .pattern: String(localized: "Pattern", bundle: .module, comment: "In the photo details: the EXIF metering mode Pattern, which measures many zones of the frame.")
        case .partial: String(localized: "Partial", bundle: .module, comment: "In the photo details: the EXIF metering mode Partial.")
        case .otherMode: String(localized: "EXIF metering: Other", bundle: .module, comment: "In the photo details: the EXIF metering mode Other (code 255).")
        case .other(let code): code.formatted(.number.grouping(.never))
        }
    }
}
