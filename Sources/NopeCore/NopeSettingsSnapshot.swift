import Foundation

/// A copy of every stored ``NopeSettings`` value, for a process that can't read the shared store:
/// the Lock Screen camera (issue #42).
///
/// Apple's LockedCameraCapture documentation says a capture extension "can't read from or write to
/// the App Group's shared container", and offers the `appContext` of its `CameraCaptureIntent`
/// instead: "up to four KB" that the app writes and the extension reads when it opens. The app
/// writes a snapshot there whenever the settings change; the Lock Screen camera applies it to its
/// own settings with ``NopeSettings/apply(_:)``, so it saves photos in the person's formats, with
/// their metadata and signing choices and their night mode.
///
/// The snapshot holds settings only: Booleans, names of choices and numbers. It holds no photo,
/// location or other personal data, and stays on the device.
///
/// It copies every key ``SharedSettingsStore/isSettingsKey(_:)`` accepts, so a setting added later
/// is included without changing this type.
public struct NopeSettingsSnapshot: Codable, Sendable, Equatable {
    /// The most bytes Apple allows in a `CameraCaptureIntent`'s `appContext` (LockedCameraCapture,
    /// "Creating a camera experience for the Lock Screen": "up to four KB").
    public static let appContextLimit = 4096

    /// The stored values, as a binary property list of a dictionary from key to value.
    public let values: Data

    /// Creates a snapshot from its encoded values.
    ///
    /// - Parameter values: A binary property list of a dictionary from key to value.
    public init(values: Data) {
        self.values = values
    }

    /// The size of the snapshot once encoded as JSON, the larger of the two encodings an
    /// `appContext` may use, in bytes. Compare it with ``appContextLimit``.
    ///
    /// - Returns: The size in bytes.
    /// - Throws: An `EncodingError` if the snapshot can't be encoded.
    public func encodedSize() throws -> Int {
        try JSONEncoder().encode(self).count
    }
}

extension NopeSettings {
    /// Copies every stored setting, including values given as launch arguments.
    ///
    /// - Returns: The snapshot.
    /// - Throws: An error from `PropertyListSerialization` if a stored value isn't a property
    ///   list value, which ``NopeSettings`` never stores.
    public func makeSnapshot() throws -> NopeSettingsSnapshot {
        let values = defaults.dictionaryRepresentation().filter { SharedSettingsStore.isSettingsKey($0.key) }
        return NopeSettingsSnapshot(
            values: try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0))
    }

    /// Replaces the stored settings with a snapshot's, and reloads them.
    ///
    /// A setting missing from the snapshot goes back to its default. Every value is read back
    /// through the same rules as a stored one, so a value this version doesn't know falls back to
    /// the default (AGENTS.md, "Fail closed"). A snapshot that can't be read changes nothing.
    ///
    /// Night mode then is the snapshot's, a choice the person made by applying it (a preset), so
    /// the astro helper no longer turns it off when it ends (``isNightModeFromAstro``).
    ///
    /// - Parameter snapshot: The snapshot, from ``makeSnapshot()``.
    /// - Returns: `true` when the snapshot could be read.
    @discardableResult
    public func apply(_ snapshot: NopeSettingsSnapshot) -> Bool {
        guard
            let values = try? PropertyListSerialization.propertyList(from: snapshot.values, format: nil)
                as? [String: Any]
        else { return false }
        for key in defaults.dictionaryRepresentation().keys
        where SharedSettingsStore.isSettingsKey(key) && values[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in values where SharedSettingsStore.isSettingsKey(key) {
            defaults.set(value, forKey: key)
        }
        setNightModeFromAstro(false)
        reload()
        return true
    }
}
