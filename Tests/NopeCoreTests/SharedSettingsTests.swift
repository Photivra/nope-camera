import Foundation
import Testing

@testable import NopeCore

/// A settings change signal that records posts and delivers signals on request.
final class FakeChangeSignal: SettingsChangeSignaling, @unchecked Sendable {
    /// Guards the counters and the stream.
    private let lock = NSLock()

    /// How many times ``post()`` was called.
    private var postCount = 0

    /// The open stream's continuation.
    private var continuation: AsyncStream<Void>.Continuation?

    /// The number of posts so far.
    var posts: Int { lock.withLock { postCount } }

    func post() {
        lock.withLock { postCount += 1 }
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in lock.withLock { self.continuation = continuation } }
    }

    /// Delivers a signal as if another process had posted it.
    func deliverFromAnotherProcess() {
        _ = lock.withLock { continuation }?.yield()
    }
}

/// Waits on the main actor until a condition holds, up to about two seconds.
///
/// - Parameter condition: The condition.
/// - Returns: Whether it held in time.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

struct SharedSettingsStoreTests {
    @Test func groupIdentifierComesFromTheInfoPlist() {
        let key = SharedSettingsStore.groupIdentifierInfoKey
        #expect(key == "NopeAppGroupIdentifier")
        #expect(
            SharedSettingsStore.groupIdentifier(infoDictionary: [key: "group.com.photivra.nope.dev"])
                == "group.com.photivra.nope.dev")
        #expect(SharedSettingsStore.groupIdentifier(infoDictionary: nil) == nil)
        #expect(SharedSettingsStore.groupIdentifier(infoDictionary: [:]) == nil)
        #expect(SharedSettingsStore.groupIdentifier(infoDictionary: [key: 42]) == nil)
        // Not an App Group, or a build setting the build didn't fill in.
        #expect(SharedSettingsStore.groupIdentifier(infoDictionary: [key: "com.photivra.nope"]) == nil)
        #expect(SharedSettingsStore.groupIdentifier(infoDictionary: [key: "group.$(NOPE_BUNDLE_IDENTIFIER)"]) == nil)
    }

    @Test func storeAndSignalName() {
        let name = "group.NopeSharedSettingsTests.\(UUID().uuidString)"
        let store = SharedSettingsStore.defaults(groupIdentifier: name)
        #expect(store != nil)
        store?.removePersistentDomain(forName: name)
        #expect(SharedSettingsStore.changeSignalName(groupIdentifier: "group.a") == "group.a.settings-changed")
    }

    @Test func settingsKeys() {
        #expect(SharedSettingsStore.isSettingsKey("NopeSettings.isNightModeOn"))
        #expect(SharedSettingsStore.isSettingsKey("NopeSettings.overlays.showsGrid"))
        #expect(SharedSettingsStore.isSettingsKey("manualControlsEnabled"))
        #expect(!SharedSettingsStore.isSettingsKey("AppleLanguages"))
        #expect(!SharedSettingsStore.isSettingsKey(SharedSettingsStore.migrationKey))
    }

    @Test func migrationCopiesTheAppsSettingsOnce() {
        let old = ScratchDefaults()
        let shared = ScratchDefaults()
        old.defaults.set(true, forKey: "NopeSettings.isNightModeOn")
        old.defaults.set("always", forKey: "NopeSettings.flashMode")
        old.defaults.set(true, forKey: "manualControlsEnabled")
        old.defaults.set("unrelated", forKey: "SomethingElse")
        // A control already wrote this one before the app first ran: it is kept.
        shared.defaults.set("auto", forKey: "NopeSettings.flashMode")

        #expect(SharedSettingsStore.migrate(from: old.defaults, domainName: old.name, to: shared.defaults))
        #expect(shared.defaults.bool(forKey: "NopeSettings.isNightModeOn"))
        #expect(shared.defaults.string(forKey: "NopeSettings.flashMode") == "auto")
        #expect(shared.defaults.bool(forKey: "manualControlsEnabled"))
        #expect(shared.defaults.object(forKey: "SomethingElse") == nil)
        // The old values stay, for an earlier version.
        #expect(old.defaults.bool(forKey: "NopeSettings.isNightModeOn"))

        // Once only: a later change in the old store is not copied again.
        old.defaults.set(true, forKey: "NopeSettings.startsInCleanView")
        #expect(!SharedSettingsStore.migrate(from: old.defaults, domainName: old.name, to: shared.defaults))
        #expect(!shared.defaults.bool(forKey: "NopeSettings.startsInCleanView"))
    }

    @Test @MainActor func migratedSettingsLoad() {
        let old = ScratchDefaults()
        let shared = ScratchDefaults()
        let before = NopeSettings(defaults: old.defaults)
        before.setNightMode(true)
        before.setFormat(.jpeg, isSelected: true)
        before.setSignsPhotos(false)
        before.setShowsGrid(true)

        SharedSettingsStore.migrate(from: old.defaults, domainName: old.name, to: shared.defaults)
        let after = NopeSettings(defaults: shared.defaults)
        #expect(after.isNightModeOn)
        #expect(after.formats.contains(.jpeg))
        #expect(!after.signsPhotos)
        #expect(after.overlays.showsGrid)
    }

    @Test func migrationOfAnEmptyStore() {
        let shared = ScratchDefaults()
        #expect(SharedSettingsStore.migrate(from: shared.defaults, domainName: "NopeSharedSettingsTests.none", to: shared.defaults))
        #expect(shared.defaults.bool(forKey: SharedSettingsStore.migrationKey))
    }
}

@MainActor
struct NopeSettingsReloadTests {
    @Test func reloadReadsAnotherWritersChanges() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        #expect(!settings.reload())

        let other = NopeSettings(defaults: scratch.defaults)
        other.setNightMode(true)
        other.setTintsViewfinderInNightMode(true)
        other.setFormat(.jpeg, isSelected: true)
        other.setShowsManualControls(true)
        other.setStartsInCleanView(true)
        other.setShowsGrid(true)
        other.setFastShutter(.freezeMotion)
        other.setFlashMode(.on)
        other.setTorchLevel(0.5)

        #expect(settings.reload())
        #expect(settings.isNightModeOn)
        #expect(settings.tintsViewfinderInNightMode)
        #expect(settings.formats.contains(.jpeg))
        #expect(settings.showsManualControls)
        #expect(settings.startsInCleanView)
        #expect(settings.overlays.showsGrid)
        #expect(settings.fastShutter == .freezeMotion)
        #expect(settings.flashMode == .on)
        #expect(settings.torchLevel == 0.5)
        #expect(!settings.reload())
    }
}

@MainActor
struct NopeSettingsSnapshotTests {
    @Test func snapshotCarriesEverySettingToAnotherStore() throws {
        let app = ScratchDefaults()
        let settings = NopeSettings(defaults: app.defaults)
        settings.setNightMode(true)
        settings.setFormat(.jpeg, isSelected: true)
        settings.setMetadataItem(.lensMakeAndModel, isIncluded: true)
        settings.setSignsPhotos(false)
        settings.setFlashMode(.auto)
        app.defaults.set("not a setting", forKey: "SomethingElse")

        let snapshot = try settings.makeSnapshot()
        let lockScreen = ScratchDefaults()
        lockScreen.defaults.set(true, forKey: "NopeSettings.startsInCleanView")
        let locked = NopeSettings(defaults: lockScreen.defaults)
        #expect(locked.startsInCleanView)

        #expect(locked.apply(snapshot))
        #expect(locked.isNightModeOn)
        #expect(locked.formats.contains(.jpeg))
        #expect(locked.metadata.isOn(.lensMakeAndModel))
        #expect(!locked.signsPhotos)
        #expect(locked.flashMode == .auto)
        // A setting missing from the snapshot goes back to its default.
        #expect(!locked.startsInCleanView)
        #expect(lockScreen.defaults.object(forKey: "SomethingElse") == nil)
    }

    @Test func snapshotFitsTheAppContextLimit() throws {
        let app = ScratchDefaults()
        let settings = NopeSettings(defaults: app.defaults)
        // Every setting stored, most away from its default.
        for format in PhotoFormat.allCases { settings.setFormat(format, isSelected: true) }
        settings.setRemovesAllOptionalDetails(false)
        for item in MetadataItem.allCases { settings.setMetadataItem(item, isIncluded: true) }
        settings.setSignsPhotos(false)
        settings.setDevelopedLook(DevelopedLook.allCases.last ?? .standard)
        settings.setRAWPairing(.jpeg)
        settings.setMirrorsFrontCamera(true)
        settings.setFileOptions(DevelopedFileOptions())
        settings.setShowsManualControls(true)
        settings.setStartsInCleanView(true)
        settings.setOverlays(OverlayOptions())
        settings.setShowsGrid(true)
        settings.setFastShutter(.freezeMotion)
        settings.setFlashMode(.on)
        settings.setTorchLevel(0.123456789)
        settings.setNightMode(true)
        settings.setTintsViewfinderInNightMode(true)

        let size = try settings.makeSnapshot().encodedSize()
        // Half the limit, so settings added later still fit.
        #expect(size < NopeSettingsSnapshot.appContextLimit / 2, "snapshot is \(size) bytes")
        #expect(NopeSettingsSnapshot.appContextLimit == 4096)
    }

    @Test func unreadableSnapshotChangesNothing() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        settings.setNightMode(true)
        #expect(!settings.apply(NopeSettingsSnapshot(values: Data("nope".utf8))))
        #expect(settings.isNightModeOn)
    }

    @Test func snapshotRoundTripsThroughJSON() throws {
        let snapshot = NopeSettingsSnapshot(values: Data([1, 2, 3]))
        let decoded = try JSONDecoder().decode(NopeSettingsSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test func snapshotOfAStoreThatHoldsSomethingElse() {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        // Not a property list value: NopeSettings never stores one, but the snapshot reports it.
        scratch.defaults.set(["NopeSettings.bad": "x"], forKey: "NopeSettings.nested")
        #expect((try? settings.makeSnapshot()) != nil)
    }
}

@MainActor
struct SharedSettingsSyncTests {
    @Test func ownChangesArePostedAndReported() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let signal = FakeChangeSignal()
        var changes = 0
        let sync = SharedSettingsSync(settings: settings, signal: signal) { changes += 1 }

        settings.setNightMode(true)
        // Posted before the setter returns, so a short-lived control intent posts it too.
        #expect(signal.posts >= 1)
        #expect(await eventually { changes == 1 })

        // Several values written together are reported once.
        settings.setOverlays(OverlayOptions())
        let posts = signal.posts
        #expect(posts > 2)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(changes == 2)
        withExtendedLifetime(sync) {}
    }

    @Test func anotherProcessesChangeReloads() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let signal = FakeChangeSignal()
        var changes = 0
        let sync = SharedSettingsSync(settings: settings, signal: signal) { changes += 1 }

        // Another process (here, another `UserDefaults` object for the same store) turns night
        // mode on; its write isn't this store object's change.
        NopeSettings(defaults: UserDefaults(suiteName: scratch.name)!).setNightMode(true)
        #expect(!settings.isNightModeOn)
        try? await Task.sleep(for: .milliseconds(20))
        signal.deliverFromAnotherProcess()
        #expect(await eventually { settings.isNightModeOn })
        #expect(changes == 1, "changes: \(changes)")

        // A signal that changes nothing, such as the echo of this process's own, isn't reported.
        signal.deliverFromAnotherProcess()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(changes == 1, "changes: \(changes)")
        withExtendedLifetime(sync) {}
    }

    @Test func syncWithoutAChangeHandler() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let signal = FakeChangeSignal()
        let sync = SharedSettingsSync(settings: settings, signal: signal)
        settings.setNightMode(true)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(signal.posts >= 1)
        withExtendedLifetime(sync) {}
    }

    @Test func releasingTheSyncStopsIt() async {
        let scratch = ScratchDefaults()
        let settings = NopeSettings(defaults: scratch.defaults)
        let signal = FakeChangeSignal()
        var sync: SharedSettingsSync? = SharedSettingsSync(settings: settings, signal: signal)
        #expect(sync != nil)
        sync = nil
        try? await Task.sleep(for: .milliseconds(20))
        NopeSettings(defaults: scratch.defaults).setNightMode(true)
        signal.deliverFromAnotherProcess()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!settings.isNightModeOn)
        settings.setNightMode(false)
        #expect(signal.posts == 0)
    }

    @Test func releasedSettingsEndTheReloads() async {
        let scratch = ScratchDefaults()
        let signal = FakeChangeSignal()
        var settings: NopeSettings? = NopeSettings(defaults: scratch.defaults)
        let sync = SharedSettingsSync(settings: settings!, signal: signal)
        settings = nil
        signal.deliverFromAnotherProcess()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(settings == nil)
        withExtendedLifetime(sync) {}
    }
}

struct DarwinSettingsChangeSignalTests {
    @Test func signalReachesListeners() async {
        let signal = DarwinSettingsChangeSignal(name: "NopeSharedSettingsTests.\(UUID().uuidString)")
        let second = DarwinSettingsChangeSignal(name: signal.name)
        let heard = Task {
            var count = 0
            for await _ in signal.changes() {
                count += 1
                break
            }
            return count
        }
        let alsoHeard = Task {
            for await _ in second.changes() { return true }
            return false
        }
        // Repeat the post until the listeners are registered.
        let poster = Task {
            while !Task.isCancelled {
                signal.post()
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        #expect(await heard.value == 1)
        #expect(await alsoHeard.value)
        poster.cancel()
    }

    @Test func endedStreamsStopListening() async {
        let name = "NopeSharedSettingsTests.\(UUID().uuidString)"
        let listening = Task {
            for await _ in DarwinSettingsChangeSignal(name: name).changes() {}
        }
        try? await Task.sleep(for: .milliseconds(20))
        listening.cancel()
        await listening.value
        DarwinNotificationListeners.shared.deliver(name)
        DarwinNotificationListeners.shared.deliver(nil)
    }
}
