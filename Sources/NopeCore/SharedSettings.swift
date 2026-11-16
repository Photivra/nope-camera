import Foundation

/// Where the person's settings are kept so that the app and its extensions read the same values:
/// the `UserDefaults` of the app's App Group (issue #42).
///
/// The app, the Control Center controls and any later extension of the app (a Live Activity, a
/// Watch app's own extensions on the watch) open the same store with ``defaults(groupIdentifier:)``
/// and wrap it in ``NopeSettings``. Each target reads the group's identifier from its own
/// Info.plist (``groupIdentifierInfoKey``), which the build fills in from the bundle identifier,
/// so no identifier or team is written in code.
///
/// The Lock Screen camera can't use it: Apple's LockedCameraCapture documentation says a capture
/// extension "can't read from or write to the App Group's shared container". It gets the settings
/// as a ``NopeSettingsSnapshot`` instead.
///
/// Privacy rule (AGENTS.md, "No network, no analytics"): the App Group container is on the device
/// only. It is never synced through iCloud or sent anywhere.
///
/// ```swift
/// let identifier = SharedSettingsStore.groupIdentifier(infoDictionary: Bundle.main.infoDictionary)
/// if let identifier, let store = SharedSettingsStore.defaults(groupIdentifier: identifier) {
///     SharedSettingsStore.migrate(from: .standard, domainName: Bundle.main.bundleIdentifier ?? "", to: store)
///     let settings = NopeSettings(defaults: store)
/// }
/// ```
public enum SharedSettingsStore {
    /// The Info.plist key that holds the App Group's identifier, such as
    /// `group.com.photivra.nope.dev`. The build sets it from `NOPE_APP_GROUP_IDENTIFIER`.
    public static let groupIdentifierInfoKey = "NopeAppGroupIdentifier"

    /// The prefix of every key ``NopeSettings`` stores.
    public static let keyPrefix = "NopeSettings."

    /// The key that records, in the shared store, that the app's own settings were copied into it.
    public static let migrationKey = "NopeSharedSettings.migratedFromAppDefaults"

    /// The App Group's identifier from a target's Info.plist.
    ///
    /// - Parameter infoDictionary: The target's Info.plist, normally `Bundle.main.infoDictionary`.
    /// - Returns: The identifier, or `nil` when the target has none (the Lock Screen camera) or
    ///   the build didn't fill it in.
    public static func groupIdentifier(infoDictionary: [String: Any]?) -> String? {
        guard let identifier = infoDictionary?[groupIdentifierInfoKey] as? String,
            identifier.hasPrefix("group."), !identifier.contains("$(")
        else { return nil }
        return identifier
    }

    /// Opens the App Group's settings store.
    ///
    /// - Parameter groupIdentifier: The App Group's identifier, from
    ///   ``groupIdentifier(infoDictionary:)``.
    /// - Returns: The store, or `nil` when `UserDefaults` refuses the name.
    public static func defaults(groupIdentifier: String) -> UserDefaults? {
        UserDefaults(suiteName: groupIdentifier)
    }

    /// Whether a `UserDefaults` key belongs to ``NopeSettings``: shared, migrated and part of a
    /// ``NopeSettingsSnapshot``.
    ///
    /// - Parameter key: A key.
    /// - Returns: `true` for keys starting with ``keyPrefix`` and for the "Manual controls" key
    ///   used before `NopeSettings` existed, which `NopeSettings` migrates itself.
    public static func isSettingsKey(_ key: String) -> Bool {
        key.hasPrefix(keyPrefix) || key == NopeSettings.Key.legacyManualControls
    }

    /// Copies the settings stored by earlier versions in the app's own `UserDefaults` into the
    /// shared store, once.
    ///
    /// Only the app calls it, before it creates its ``NopeSettings``: an extension's own store is
    /// empty, so its call would mark the move done without moving anything. A value already in the
    /// shared store (set by a control before the app first ran) is kept. The old values stay where
    /// they were, so an earlier version still finds them; they are no longer read.
    ///
    /// Values given as launch arguments aren't copied: only the old store's persistent domain is.
    ///
    /// - Parameters:
    ///   - old: The app's own store, normally `UserDefaults.standard`.
    ///   - domainName: The old store's persistent domain: the app's bundle identifier for
    ///     `UserDefaults.standard`, or the suite name.
    ///   - shared: The shared store.
    /// - Returns: `true` when this call copied the settings, `false` when it was done before.
    @discardableResult
    public static func migrate(from old: UserDefaults, domainName: String, to shared: UserDefaults) -> Bool {
        guard !shared.bool(forKey: migrationKey) else { return false }
        let stored = old.persistentDomain(forName: domainName) ?? [:]
        for (key, value) in stored where isSettingsKey(key) && shared.object(forKey: key) == nil {
            shared.set(value, forKey: key)
        }
        shared.set(true, forKey: migrationKey)
        return true
    }

    /// The name of the system-wide notification that tells the app and its extensions the shared
    /// settings changed.
    ///
    /// - Parameter groupIdentifier: The App Group's identifier, so that two installed builds
    ///   (development and release) don't signal each other.
    /// - Returns: The notification name.
    public static func changeSignalName(groupIdentifier: String) -> String {
        "\(groupIdentifier).settings-changed"
    }
}

/// Tells other processes of the app (the app, its controls) that the shared settings changed,
/// and hears when they did.
///
/// The signal carries nothing: whoever hears it reads the store again (``NopeSettings/reload()``).
/// ``DarwinSettingsChangeSignal`` is the system's; tests use a fake.
public protocol SettingsChangeSignaling: Sendable {
    /// Tells every listening process, this one included, that the settings changed.
    func post()

    /// The signals from now on, from any process, until the stream's task is cancelled.
    ///
    /// - Returns: One element per signal heard. Close signals may arrive as one.
    func changes() -> AsyncStream<Void>
}

/// The settings change signal as a Darwin notification (Core Foundation,
/// `CFNotificationCenterGetDarwinNotifyCenter`), which the system delivers to every process that
/// listens for the name, without polling (AGENTS.md, "Battery").
///
/// The notification carries no data and never leaves the device.
public struct DarwinSettingsChangeSignal: SettingsChangeSignaling {
    /// The notification's name, from ``SharedSettingsStore/changeSignalName(groupIdentifier:)``.
    public let name: String

    /// Creates the signal.
    ///
    /// - Parameter name: The notification's name.
    public init(name: String) {
        self.name = name
    }

    /// Posts the notification to every listening process.
    public func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// The notifications heard from now on.
    ///
    /// - Returns: A stream with one element per notification heard.
    public func changes() -> AsyncStream<Void> {
        DarwinNotificationListeners.shared.stream(for: name)
    }
}

/// The listeners for Darwin notifications in this process, by name.
///
/// A Core Foundation callback is a C function that can't capture a listener, so one callback per
/// name forwards to the streams registered here. The callback stays registered for the life of the
/// process; a stream that ends is removed.
final class DarwinNotificationListeners: @unchecked Sendable {
    /// The listeners of this process.
    static let shared = DarwinNotificationListeners()

    /// Guards ``continuations`` and ``observedNames``, which the callback reads from the
    /// notification center's thread.
    private let lock = NSLock()

    /// The open streams, by notification name and stream.
    private var continuations: [String: [UUID: AsyncStream<Void>.Continuation]] = [:]

    /// The names with a registered callback.
    private var observedNames: Set<String> = []

    /// Creates the registry. Use ``shared``: one per process.
    private init() {}

    /// A new stream of the notifications with a name.
    ///
    /// - Parameter name: The notification's name.
    /// - Returns: The stream; it ends when its task is cancelled.
    func stream(for name: String) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            let isFirst = lock.withLock {
                continuations[name, default: [:]][id] = continuation
                return observedNames.insert(name).inserted
            }
            if isFirst {
                CFNotificationCenterAddObserver(
                    CFNotificationCenterGetDarwinNotifyCenter(), nil,
                    { _, _, name, _, _ in DarwinNotificationListeners.shared.deliver(name?.rawValue as String?) },
                    name as CFString, nil, .deliverImmediately)
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.continuations[name]?[id] = nil }
            }
        }
    }

    /// Passes a notification to every open stream for its name.
    ///
    /// - Parameter name: The notification's name, `nil` if the system gave none.
    func deliver(_ name: String?) {
        let listeners = lock.withLock { continuations[name ?? ""].map { Array($0.values) } ?? [] }
        for listener in listeners {
            listener.yield()
        }
    }
}

/// Keeps one process's ``NopeSettings`` in step with the other processes of the app.
///
/// When this process changes the settings, it posts the signal, so the app's controls and the
/// app's open screens update. When another process signals, it reloads the settings from the
/// store, and the interface follows through Observation. No timer or polling is involved
/// (AGENTS.md, "Battery").
///
/// Keep the object for as long as the settings should follow; releasing it stops both.
///
/// ```swift
/// let sync = SharedSettingsSync(settings: settings, signal: signal) {
///     // For example, refresh the Control Center controls.
/// }
/// ```
@MainActor
public final class SharedSettingsSync {
    /// The observers, removed when this object is released.
    private var observers: Observers?

    /// Called after the settings change, once for a group of changes made together.
    private let onChange: @MainActor () -> Void

    /// Whether a call to ``onChange`` is already scheduled for this process's own changes.
    private var isChangeScheduled = false

    /// Starts following.
    ///
    /// - Parameters:
    ///   - settings: The settings to keep in step. Its store's changes are posted; the signal
    ///     reloads it.
    ///   - signal: The signal shared by the app's processes.
    ///   - onChange: Called on the main actor after this process changed the settings, or after
    ///     another process's change reloaded them. Not called for a signal that changed nothing,
    ///     such as this process's own.
    public init(
        settings: NopeSettings, signal: any SettingsChangeSignaling, onChange: @escaping @MainActor () -> Void = {}
    ) {
        self.onChange = onChange
        // `UserDefaults.didChangeNotification` is posted only for changes made in this process,
        // on the thread that made them, so the signal is posted before the setter returns.
        let changes = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: settings.defaults, queue: nil
        ) { [weak self] _ in
            signal.post()
            Task { @MainActor in self?.scheduleChange() }
        }
        let stream = signal.changes()
        let reloads = Task { @MainActor [weak self, weak settings] in
            for await _ in stream {
                guard let self, let settings else { return }
                if settings.reload() { self.onChange() }
            }
        }
        observers = Observers(changes: changes, reloads: reloads)
    }

    /// Calls ``onChange`` once for this process's changes made together.
    private func scheduleChange() {
        guard !isChangeScheduled else { return }
        isChangeScheduled = true
        Task { @MainActor in
            isChangeScheduled = false
            onChange()
        }
    }

    /// The notification observer and the reload task, ended together.
    private final class Observers: @unchecked Sendable {
        /// The `UserDefaults.didChangeNotification` observer.
        let changes: any NSObjectProtocol

        /// The task that reloads the settings on each signal.
        let reloads: Task<Void, Never>

        /// Holds both.
        ///
        /// - Parameters:
        ///   - changes: The notification observer.
        ///   - reloads: The reload task.
        init(changes: any NSObjectProtocol, reloads: Task<Void, Never>) {
            self.changes = changes
            self.reloads = reloads
        }

        /// Removes the observer and cancels the task.
        deinit {
            NotificationCenter.default.removeObserver(changes)
            reloads.cancel()
        }
    }
}
