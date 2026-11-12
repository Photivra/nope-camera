import Foundation

/// The "Manual controls" option: where it is stored and its default.
///
/// The Settings screen stores the switch in `UserDefaults` under ``userDefaultsKey``; the app
/// target reads it and sends ``ManualControlIntent/setEnabled(_:)``. It is off by default: full
/// auto, with manual controls hidden (AGENTS.md, "Manual controls stay hidden unless turned on").
public enum ManualControlsSetting {
    /// The `UserDefaults` key of the option.
    public static let userDefaultsKey = "manualControlsEnabled"

    /// The option's default: off.
    public static let defaultValue = false
}
