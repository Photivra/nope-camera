import Foundation

extension PresetChoice {
    /// The identifier of Factory Defaults in ``identifier``.
    public static let factoryDefaultsIdentifier = "factory-defaults"

    /// A stable text identifier, for an interface that names presets outside the app (a Shortcuts
    /// action): ``factoryDefaultsIdentifier`` or the saved preset's UUID.
    public var identifier: String {
        switch self {
        case .factoryDefaults: Self.factoryDefaultsIdentifier
        case .saved(let id): id.uuidString
        }
    }

    /// The preset an ``identifier`` names.
    ///
    /// - Parameter identifier: ``factoryDefaultsIdentifier`` or a saved preset's UUID.
    /// - Returns: The choice, or `nil` for text that is neither. Whether a saved preset still
    ///   exists is checked when it is applied.
    public init?(identifier: String) {
        if identifier == Self.factoryDefaultsIdentifier {
            self = .factoryDefaults
        } else if let id = UUID(uuidString: identifier) {
            self = .saved(id)
        } else {
            return nil
        }
    }
}

/// Applying a settings preset from Siri or Shortcuts (issues #62 and #72).
extension CameraModel {
    /// Applies a preset for a request, through the same path as the Presets list
    /// (``SettingsPresets/apply(_:camera:location:)``): every setting, then the camera's lens,
    /// exposure and drive values, with Location only through its permission prompt. A preset
    /// never turns the light on (``CameraSetup`` doesn't hold it). The apply can be undone in the
    /// Presets list, as one made there.
    ///
    /// The request waits for the camera to start, so the lens and exposure apply too; if the
    /// camera can't start, the settings still apply and the result says the camera values
    /// didn't (``PresetNotice/cameraNotReady``).
    ///
    /// - Parameters:
    ///   - choice: The preset.
    ///   - presets: The person's presets, or `nil` when the interface has none.
    ///   - inbox: The inbox, for its waits and timeouts.
    /// - Returns: ``ShortcutOutcome/presetApplied(_:)``, ``ShortcutOutcome/busy`` while photos
    ///   are being taken, or ``ShortcutOutcome/presetUnavailable`` when the preset doesn't exist
    ///   or can't be read.
    func applyPreset(_ choice: PresetChoice, presets: SettingsPresets?, inbox: ShortcutInbox) async -> ShortcutOutcome {
        guard let presets else { return .presetUnavailable }
        let camera: CameraModel? = await cameraProblem(inbox: inbox) == nil ? self : nil
        let result = await presets.apply(choice, camera: camera, location: location)
        if result.isApplied { return .presetApplied(result) }
        return result.notices.contains(.cameraBusy) ? .busy : .presetUnavailable
    }
}
