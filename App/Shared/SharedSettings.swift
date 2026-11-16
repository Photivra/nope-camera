import AppIntents
import Foundation
import NopeCore
import os

/// The person's settings as the app and its extensions share them (issue #42): the App Group's
/// store, the change signal between processes, and the copy handed to the Lock Screen camera.
///
/// Compiled into the app, the Lock Screen camera and the controls (App/Shared). Each target reads
/// the App Group's identifier from its own Info.plist (`NopeAppGroupIdentifier`, filled in from
/// `NOPE_APP_GROUP_IDENTIFIER` in `Config/Base.xcconfig`). The Lock Screen camera has none, because
/// Apple doesn't let a capture extension use the App Group's container; it reads the
/// ``OpenCameraIntent`` app context instead (``NopeSettingsSnapshot``).
///
/// A later target that shows or changes settings (a Live Activity, a widget) uses the same
/// three pieces: ``store()``, ``changeSignal`` and, after a change, ``publishToLockScreenCamera(_:)``.
enum SharedSettings {
    /// The App Group's identifier from this target's Info.plist, or `nil` in the Lock Screen
    /// camera.
    static let groupIdentifier = SharedSettingsStore.groupIdentifier(infoDictionary: Bundle.main.infoDictionary)

    /// Logs failures to hand the settings to the Lock Screen camera; no value is logged.
    private static let logger = Logger(subsystem: "com.photivra.nope", category: "SharedSettings")

    /// The App Group's settings store, or `nil` in a target without the App Group.
    ///
    /// - Returns: The shared store.
    static func store() -> UserDefaults? {
        groupIdentifier.flatMap(SharedSettingsStore.defaults(groupIdentifier:))
    }

    /// The app's settings store: the shared one, with the settings of earlier versions copied in
    /// once from the app's own `UserDefaults`; or the app's own if the App Group is missing.
    ///
    /// Only the app calls this (see ``SharedSettingsStore/migrate(from:domainName:to:)``).
    ///
    /// - Returns: The store for the app's `NopeSettings`.
    static func appStore() -> UserDefaults {
        guard let shared = store(), let domain = Bundle.main.bundleIdentifier else { return .standard }
        SharedSettingsStore.migrate(from: .standard, domainName: domain, to: shared)
        return shared
    }

    /// The signal that tells the app and its controls the settings changed, or `nil` without the
    /// App Group.
    static var changeSignal: DarwinSettingsChangeSignal? {
        groupIdentifier.map { DarwinSettingsChangeSignal(name: SharedSettingsStore.changeSignalName(groupIdentifier: $0)) }
    }

    /// Hands a copy of the settings to the Lock Screen camera, which reads it when it opens
    /// (`CameraCaptureIntent.updateAppContext(_:)`, App Intents, iOS 18).
    ///
    /// Apple documents writing the app context from the app and the capture extension; the
    /// controls call this too after they change a setting, which is an assumption to verify on a
    /// device (docs/TESTING.md, "On-device checks"). A failure is logged; the Lock Screen camera
    /// then opens with the copy it had.
    ///
    /// - Parameter settings: The settings to copy.
    @MainActor
    static func publishToLockScreenCamera(_ settings: NopeSettings) async {
        do {
            let snapshot = try settings.makeSnapshot()
            guard try snapshot.encodedSize() <= NopeSettingsSnapshot.appContextLimit else {
                logger.error("Settings snapshot is over the app context limit")
                return
            }
            try await OpenCameraIntent.updateAppContext(snapshot)
        } catch {
            logger.error("Settings snapshot not handed to the Lock Screen camera: \(error, privacy: .private)")
        }
    }
}

/// The identifiers of the app's Control Center and Lock Screen controls, stable across releases
/// so a placed control keeps working. The app uses them to refresh a control after a change.
enum NopeControlKind {
    /// The "Open nope." button.
    static let openCamera = "com.photivra.nope.controls.open-camera"

    /// The Night Mode switch.
    static let nightMode = "com.photivra.nope.controls.night-mode"
}
