import Foundation
import NopeCore

/// The question each gated action asks before it runs, with the values it will run with
/// (`docs/design/assistant-access.md`, 5.2). Each is a whole sentence with placeholders; the
/// button names the action. Drafts for the Honesty review.
///
/// A lens is named with a whole localized noun phrase ("the telephoto camera",
/// ``cameraPhrase(_:)``), the same names Siri's answers use.
enum AssistantQuestions {
    /// The camera, as a noun phrase for the questions.
    ///
    /// - Parameter lens: The lens kind.
    /// - Returns: For example "the telephoto camera".
    static func cameraPhrase(_ lens: Lens.Kind) -> String {
        switch lens {
        case .ultraWide:
            String(localized: "the ultra wide camera", comment: "Fills the camera placeholder of the questions Siri asks before nope.'s actions, as in \"Take a photo with the ultra wide camera?\".")
        case .wide:
            String(localized: "the wide camera", comment: "Fills the camera placeholder of the questions Siri asks before nope.'s actions, as in \"Take a photo with the wide camera?\".")
        case .telephoto:
            String(localized: "the telephoto camera", comment: "Fills the camera placeholder of the questions Siri asks before nope.'s actions, as in \"Take a photo with the telephoto camera?\".")
        case .front:
            String(localized: "the front camera", comment: "Fills the camera placeholder of the questions Siri asks before nope.'s actions, as in \"Take a photo with the front camera?\".")
        }
    }

    /// Take Photo.
    ///
    /// - Parameter photo: The request, with its values checked.
    /// - Returns: The question.
    static func takePhoto(_ photo: PhotoShortcut) -> AssistantQuestion {
        let delay = photo.delaySeconds
        let count = photo.count
        let camera = photo.lensKind.map(cameraPhrase)
        let question: LocalizedStringResource =
            switch (count > 1, delay > 0, camera) {
            case (false, false, nil):
                LocalizedStringResource("Take a photo?", comment: "Question Siri asks before nope. takes a photo.")
            case (false, true, nil):
                LocalizedStringResource("Take a photo in \(delay) seconds?", comment: "Question Siri asks before nope. takes a photo after a delay. The number is the delay in seconds.")
            case (false, false, let camera?):
                LocalizedStringResource("Take a photo with \(camera)?", comment: "Question Siri asks before nope. takes a photo with a lens. The placeholder is a camera, such as \"the telephoto camera\".")
            case (false, true, let camera?):
                LocalizedStringResource("Take a photo with \(camera) in \(delay) seconds?", comment: "Question Siri asks before nope. takes a photo with a lens after a delay. The placeholder is a camera, such as \"the telephoto camera\"; the number is the delay in seconds.")
            case (true, false, nil):
                LocalizedStringResource("Take a burst of \(count) photos?", comment: "Question Siri asks before nope. takes a burst. The number is how many photos, at least 2.")
            case (true, true, nil):
                LocalizedStringResource("Take a burst of \(count) photos in \(delay) seconds?", comment: "Question Siri asks before nope. takes a burst after a delay. The first number is how many photos, at least 2; the second is the delay in seconds.")
            case (true, false, let camera?):
                LocalizedStringResource("Take a burst of \(count) photos with \(camera)?", comment: "Question Siri asks before nope. takes a burst with a lens. The number is how many photos, at least 2; the placeholder is a camera, such as \"the telephoto camera\".")
            case (true, true, let camera?):
                LocalizedStringResource("Take a burst of \(count) photos with \(camera) in \(delay) seconds?", comment: "Question Siri asks before nope. takes a burst with a lens after a delay. The first number is how many photos, at least 2; the placeholder is a camera, such as \"the telephoto camera\"; the last number is the delay in seconds.")
            }
        let button =
            count > 1
            ? LocalizedStringResource("Take Photos", comment: "Button of the question Siri asks before nope. takes a burst.")
            : LocalizedStringResource("Take Photo", comment: "The name of nope.'s action that takes a photo, in the Shortcuts app and Siri.")
        return AssistantQuestion(question: question, button: button)
    }

    /// Take Bracket.
    ///
    /// - Parameter bracket: The request.
    /// - Returns: The question.
    static func takeBracket(_ bracket: BracketShortcut) -> AssistantQuestion {
        let delay = bracket.delaySeconds
        let camera = bracket.lensKind.map(cameraPhrase)
        let question =
            bracket.type == .focus
            ? focusBracketQuestion(count: bracket.focusFrameCount, delay: delay, camera: camera)
            : exposureBracketQuestion(count: bracket.bracket.frameCount, delay: delay, camera: camera)
        return AssistantQuestion(
            question: question,
            button: LocalizedStringResource(
                "Take Bracket", comment: "The name of nope.'s action that takes an exposure bracket: several separate photos at different exposures, in the Shortcuts app."))
    }

    /// The question before an exposure bracket.
    ///
    /// - Parameters:
    ///   - count: The frames: 3, 5 or 7.
    ///   - delay: The delay in seconds; 0 for none.
    ///   - camera: The camera as a noun phrase, or `nil` for the lens in use.
    /// - Returns: The question.
    private static func exposureBracketQuestion(count: Int, delay: Int, camera: String?) -> LocalizedStringResource {
        switch (delay > 0, camera) {
        case (false, nil):
            LocalizedStringResource("Take a bracket of \(count) photos?", comment: "Question Siri asks before nope. takes an exposure bracket. The number is how many photos: 3, 5 or 7.")
        case (true, nil):
            LocalizedStringResource("Take a bracket of \(count) photos in \(delay) seconds?", comment: "Question Siri asks before nope. takes an exposure bracket after a delay. The first number is how many photos: 3, 5 or 7; the second is the delay in seconds.")
        case (false, let camera?):
            LocalizedStringResource("Take a bracket of \(count) photos with \(camera)?", comment: "Question Siri asks before nope. takes an exposure bracket with a lens. The number is how many photos: 3, 5 or 7; the placeholder is a camera, such as \"the telephoto camera\".")
        case (true, let camera?):
            LocalizedStringResource("Take a bracket of \(count) photos with \(camera) in \(delay) seconds?", comment: "Question Siri asks before nope. takes an exposure bracket with a lens after a delay. The first number is how many photos: 3, 5 or 7; the placeholder is a camera, such as \"the telephoto camera\"; the last number is the delay in seconds.")
        }
    }

    /// The question before a focus bracket (issue #90), Take Bracket with the type Focus.
    ///
    /// - Parameters:
    ///   - count: The frames, from 3 to 50.
    ///   - delay: The delay in seconds; 0 for none.
    ///   - camera: The camera as a noun phrase, or `nil` for the lens in use.
    /// - Returns: The question.
    private static func focusBracketQuestion(count: Int, delay: Int, camera: String?) -> LocalizedStringResource {
        switch (delay > 0, camera) {
        case (false, nil):
            LocalizedStringResource("Take a focus bracket of \(count) photos?", comment: "Question Siri asks before nope. takes a focus bracket: photos at different focus positions. The number is how many photos, from 3 to 50.")
        case (true, nil):
            LocalizedStringResource("Take a focus bracket of \(count) photos in \(delay) seconds?", comment: "Question Siri asks before nope. takes a focus bracket after a delay. The first number is how many photos, from 3 to 50; the second is the delay in seconds.")
        case (false, let camera?):
            LocalizedStringResource("Take a focus bracket of \(count) photos with \(camera)?", comment: "Question Siri asks before nope. takes a focus bracket with a lens. The number is how many photos, from 3 to 50; the placeholder is a camera, such as \"the telephoto camera\".")
        case (true, let camera?):
            LocalizedStringResource("Take a focus bracket of \(count) photos with \(camera) in \(delay) seconds?", comment: "Question Siri asks before nope. takes a focus bracket with a lens after a delay. The first number is how many photos, from 3 to 50; the placeholder is a camera, such as \"the telephoto camera\"; the last number is the delay in seconds.")
        }
    }

    /// Start Interval Shooting. The values shown are those the request gives; a value it leaves
    /// out is the one chosen in Interval Settings, which the question names.
    ///
    /// - Parameter series: The request.
    /// - Returns: The question.
    static func startInterval(_ series: IntervalShortcut) -> AssistantQuestion {
        let style = Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes, .seconds], width: .wide)
        let question: LocalizedStringResource =
            switch (series.intervalSeconds, series.durationSeconds, series.count) {
            case (let interval?, let duration?, _):
                LocalizedStringResource(
                    "Start interval shooting? A photo every \(Duration.seconds(interval).formatted(style)) for \(Duration.seconds(duration).formatted(style)).",
                    comment: "Question Siri asks before nope. starts an interval series. The placeholders are durations, such as \"10 seconds\" and \"5 minutes\".")
            case (let interval?, nil, let count?):
                LocalizedStringResource(
                    "Start interval shooting? \(count) photos, one every \(Duration.seconds(interval).formatted(style)).",
                    comment: "Question Siri asks before nope. starts an interval series. The number is how many photos; the placeholder is a duration, such as \"10 seconds\".")
            default:
                LocalizedStringResource(
                    "Start interval shooting with the times in Interval Settings?",
                    comment: "Question Siri asks before nope. starts an interval series whose interval or length the shortcut leaves to the ones chosen in nope. Interval Settings is the name of the card in nope.")
            }
        return AssistantQuestion(
            question: question,
            button: LocalizedStringResource("Start", comment: "Button of the question Siri asks before nope. starts interval shooting."))
    }

    /// Stop Interval Shooting.
    static let stopInterval = AssistantQuestion(
        question: LocalizedStringResource("Stop interval shooting?", comment: "Question Siri asks before nope. stops an interval series."),
        button: LocalizedStringResource("Stop", comment: "Button of the question Siri asks before nope. stops interval shooting."))

    /// Switch Lens.
    ///
    /// - Parameter lens: The lens kind.
    /// - Returns: The question.
    static func switchLens(_ lens: Lens.Kind) -> AssistantQuestion {
        AssistantQuestion(
            question: LocalizedStringResource(
                "Switch to \(cameraPhrase(lens))?",
                comment: "Question Siri asks before nope. switches lenses. The placeholder is a camera, such as \"the telephoto camera\"."),
            button: LocalizedStringResource(
                "Switch Lens", comment: "The name of nope.'s action that switches the camera to another lens, in the Shortcuts app."))
    }

    /// Turn On the Light or Turn Off the Light.
    ///
    /// - Parameter isOn: Whether the light is turned on.
    /// - Returns: The question.
    static func light(isOn: Bool) -> AssistantQuestion {
        isOn
            ? AssistantQuestion(
                question: LocalizedStringResource("Turn on the light?", comment: "Question Siri asks before nope. turns its steady light (the torch) on."),
                button: turnOn)
            : AssistantQuestion(
                question: LocalizedStringResource("Turn off the light?", comment: "Question Siri asks before nope. turns its steady light (the torch) off."),
                button: turnOff)
    }

    /// Set Night Mode.
    ///
    /// - Parameter isOn: Whether night mode is turned on.
    /// - Returns: The question.
    static func nightMode(isOn: Bool) -> AssistantQuestion {
        isOn
            ? AssistantQuestion(
                question: LocalizedStringResource("Turn on night mode?", comment: "Question Siri asks before nope. turns night mode on."),
                button: turnOn)
            : AssistantQuestion(
                question: LocalizedStringResource("Turn off night mode?", comment: "Question Siri asks before nope. turns night mode off."),
                button: turnOff)
    }

    /// Set Focus on Faces.
    ///
    /// - Parameter isOn: Whether Focus on Faces is turned on.
    /// - Returns: The question.
    static func focusOnFaces(isOn: Bool) -> AssistantQuestion {
        isOn
            ? AssistantQuestion(
                question: LocalizedStringResource("Turn on Focus on Faces?", comment: "Question Siri asks before nope. turns Focus on Faces on. Focus on Faces is the name of nope.'s switch."),
                button: turnOn)
            : AssistantQuestion(
                question: LocalizedStringResource("Turn off Focus on Faces?", comment: "Question Siri asks before nope. turns Focus on Faces off. Focus on Faces is the name of nope.'s switch."),
                button: turnOff)
    }

    /// Set Focus Range.
    ///
    /// - Parameter name: The range's name, as the action's choice shows it.
    /// - Returns: The question.
    static func focusRange(named name: String) -> AssistantQuestion {
        AssistantQuestion(
            question: LocalizedStringResource(
                "Set the focus range to \(name)?",
                comment: "Question Siri asks before nope. changes the autofocus range. The placeholder is the choice's name: No Limit, Close-Up or Far Focus."),
            button: set)
    }

    /// Set Photo Size.
    ///
    /// - Parameters:
    ///   - name: The size's name, as the action's choice shows it.
    ///   - lens: The lens asked for, or `nil` for the lens in use.
    /// - Returns: The question.
    static func photoSize(named name: String, lens: Lens.Kind?) -> AssistantQuestion {
        let question: LocalizedStringResource =
            if let lens {
                LocalizedStringResource(
                    "Set the photo size of \(cameraPhrase(lens)) to \(name)?",
                    comment: "Question Siri asks before nope. changes a lens's photo size. The first placeholder is a camera, such as \"the telephoto camera\"; the second is Standard or Largest.")
            } else {
                LocalizedStringResource(
                    "Set the photo size to \(name)?",
                    comment: "Question Siri asks before nope. changes the photo size of the lens in use. The placeholder is Standard or Largest.")
            }
        return AssistantQuestion(question: question, button: set)
    }

    /// Set Fast Shutter.
    ///
    /// - Parameter name: The choice's name.
    /// - Returns: The question.
    static func fastShutter(named name: String) -> AssistantQuestion {
        AssistantQuestion(
            question: LocalizedStringResource(
                "Set Fast Shutter to \(name)?",
                comment: "Question Siri asks before nope. changes Fast Shutter. Fast Shutter is the name of nope.'s setting; the placeholder is a choice, such as \"Freeze Motion (1/500 s)\"."),
            button: set)
    }

    /// Apply Preset.
    ///
    /// - Parameter name: The saved preset's name, or `nil` for Factory Defaults.
    /// - Returns: The question.
    static func applyPreset(named name: String?) -> AssistantQuestion {
        guard let name else {
            return AssistantQuestion(
                question: LocalizedStringResource(
                    "Apply Factory Defaults? Privacy settings stay as they are.", table: "Honesty",
                    comment: "Question Siri asks before nope. applies Factory Defaults through Siri or Shortcuts, which leaves every Privacy setting as it is. Factory Defaults and Privacy are names in nope.'s Settings. Draft for the Honesty review. Must not claim more than the English."),
                button: LocalizedStringResource("Apply", comment: "Button of the question Siri asks before nope. applies Factory Defaults."))
        }
        return AssistantQuestion(
            question: LocalizedStringResource(
                "Apply the preset “\(name)”? Its privacy settings are not applied.", table: "Honesty",
                comment: "Question Siri asks before nope. applies a saved preset through Siri or Shortcuts, which leaves every Privacy setting as it is. The placeholder is the preset's name, in the language's quotation marks. Draft for the Honesty review. Must not claim more than the English."),
            button: LocalizedStringResource(
                "Apply Preset", comment: "The name of nope.'s action that applies a settings preset (Factory Defaults or one the person saved), in the Shortcuts app."))
    }

    /// "Turn On".
    private static let turnOn = LocalizedStringResource("Turn On", comment: "Button of the question Siri asks before nope. turns something on: the light, night mode or Focus on Faces.")

    /// "Turn Off".
    private static let turnOff = LocalizedStringResource("Turn Off", comment: "Button of the question Siri asks before nope. turns something off: the light, night mode or Focus on Faces.")

    /// "Set".
    private static let set = LocalizedStringResource("Set", comment: "Button of the question Siri asks before nope. changes a setting: the focus range, the photo size or Fast Shutter.")
}
