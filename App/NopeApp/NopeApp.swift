import AVKit
import ActivityKit
import AppIntents
import NopeCapture
import NopeCore
import NopeDevelop
import NopeSigning
import NopeUI
import SwiftUI
import UIKit
import WidgetKit

/// The Photivra Nope Camera app: wires the capture backend into `NopeCore` and hosts `NopeUI`.
///
/// On a device it uses `AVFoundationCaptureBackend`. Debug builds launched by the UI tests with
/// `-NopeSimulatedCamera <scenario>` use a simulated backend instead (``SimulatedCameraLaunch``).
@main
struct NopeApp: App {
    /// The capture backend for this launch, created once. The camera screen and, in Debug
    /// builds, the tag check share it, so the app never owns more than one capture session.
    private static let backend = makeBackend()

    /// The camera model shared by the app's single scene.
    @State private var model = CameraModel(
        backend: Self.backend, saver: Self.makeSaver(), deviceStatusReader: Self.makeDeviceStatusReader())

    /// Keeps the screen awake and dimmed during an interval series.
    @State private var screenKeeper = SeriesScreenKeeper(screen: SystemScreen())

    /// The person's settings, stored on the device only.
    @State private var settings = Self.sharedSettings

    /// The settings object, created once so the App Intents change the same one the camera
    /// screen shows (``SetNightModeIntent``).
    private static let sharedSettings = NopeSettings(defaults: makeSettingsStore())

    /// Keeps the settings in step with the Control Center controls (issue #42); `nil` without the
    /// App Group and in UI tests, whose settings are their own.
    private static let settingsSync = makeSettingsSync()

    /// Whether the app is in the foreground, to read the shared settings again when it returns,
    /// and for the Live Activity.
    @Environment(\.scenePhase) private var scenePhase

    /// The saved settings presets (issue #72), stored with the settings on the device.
    @State private var presets = Self.sharedPresets

    /// The presets object, created once so the Apply Preset action lists and applies the same
    /// presets the camera screen shows (``ApplyPresetIntent``).
    private static let sharedPresets = SettingsPresets(settings: sharedSettings)

    /// Requests from Siri and Shortcuts (issue #62), which the camera screen serves.
    private static let shortcuts = ShortcutInbox()

    /// The link to the Apple Watch app (issue #63), whose commands go through ``shortcuts``.
    private static let watchSession = PhoneWatchSession()

    /// Location tagging for photos (issue #43): off until the person turns Location on.
    @State private var location = LocationTagging(provider: Self.makeLocationProvider())

    /// The Live Activity for a series and its saving (issue #64), and the time to finish saving
    /// after the app leaves the foreground.
    @State private var liveActivities = LiveActivityCoordinator(
        presenter: SystemLiveActivities(), backgroundTime: SystemBackgroundTime())

    /// Keeps the iPhone camera in portrait while sheets rotate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Which way up the person holds the iPhone, for the camera's upright icons.
    @State private var orientation = DeviceOrientation()

    /// Registers what the App Intents need: the settings and the Siri and Shortcuts inbox
    /// (App Intents, `AppDependencyManager`).
    /// Activates the link to the Apple Watch app (WatchConnectivity), so a watch command that
    /// launches the app is delivered.
    init() {
        let settings = Self.sharedSettings
        let shortcuts = Self.shortcuts
        AppDependencyManager.shared.add(dependency: settings)
        AppDependencyManager.shared.add(dependency: shortcuts)
        let presets = Self.sharedPresets
        AppDependencyManager.shared.add(dependency: presets)
        _ = Self.settingsSync
        Self.watchSession.activate()
    }

    /// The app's single window, showing the camera screen.
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Debug builds only: `-NopeTagCheck`, `-NopeCameraProbe` or an armed run replace the
            // camera screen (docs/TESTING.md, "Tag check"). Release builds don't contain them.
            switch DebugRunLaunch.decision {
            case .perform(.tagCheck):
                // Drives the app's own backend: no second capture session.
                TagCheckScreen(backend: Self.backend)
            case .perform(.probe):
                // Apple's sample capture pipeline with its own session; the app's backend never
                // starts in this launch. Run it only on a freshly restarted phone
                // (docs/TESTING.md, "Black frames").
                CameraProbeScreen()
            case .armed(let run):
                Text(verbatim: "Debug run \(run.rawValue) armed. Close nope. and open it from the Home Screen.")
                    .padding()
            case .none where LiveActivityGallery.isRequested:
                // UI tests only: the Live Activity layouts (`-NopeLiveActivityGallery`).
                LiveActivityGallery()
            case .none where ProcessInfo.processInfo.arguments.contains("-NopeButtonGallery"):
                // UI tests only: every custom button type and state (`-NopeButtonGallery`).
                NopeButtonGallery(isNightMode: UserDefaults.standard.bool(forKey: "NopeButtonGallery.night"))
            case .none:
                cameraScreen
            }
            #else
            cameraScreen
            #endif
        }
        // The Camera menu: Space takes a photo from a hardware keyboard, listed in the iPad
        // menu bar and keyboard shortcuts overlay.
        .commands { CameraCommands(model: model) }
    }

    /// The camera screen with the live viewfinder and the hardware shutter.
    ///
    /// The volume buttons and the Camera Control are the shutter through `onCameraCaptureEvent`
    /// (AVKit, iOS 18): its single handler gets both the primary and the secondary button
    /// (`AVCaptureEventInteraction.init(handler:)`). The model takes a photo on release of the
    /// button, as the system Camera app does, or in burst mode, takes a burst while it is held.
    /// The system delivers these events only while a capture session runs; while the camera
    /// isn't running, the interaction is off, so the buttons keep their system behavior.
    private var cameraScreen: some View {
        CameraScreen(model: model, settings: settings, presets: presets) { source in
            Viewfinder(source: source)
        }
        .environment(\.cameraUprightRotation, orientation.rotation)
        .modifier(FollowsWindowSizeClasses())
        // Settings and the screens that aren't the camera follow the system's light or dark setting.
        .modifier(ProvidesSystemAppearance())
        .environment(\.cameraGravitySource, Self.gravitySource)
        .environment(\.cameraPresentsSheet, SheetPresentationAction { AppDelegate.setSheetPresented($0) })
        // Open Settings goes to nope.'s own page in the Settings app (UIKit,
        // `openSettingsURLString`), opened only when the person taps the button.
        .environment(
            \.openAppSettings,
            CameraAction {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
        // The last-photo thumbnail opens the Photos app (issue #36), only when the person taps
        // it. Add-only access can't read the library, and iOS has no documented way to open
        // Photos at one asset, so this opens Photos with its `photos-redirect:` URL, which isn't
        // documented by Apple either (an owner decision; docs/TESTING.md, "On-device checks").
        .environment(
            \.openPhotosApp,
            CameraAction {
                guard let url = URL(string: "photos-redirect://") else { return }
                UIApplication.shared.open(url)
            })
        .onCameraCaptureEvent(isEnabled: model.handlesHardwareButtons) { event in
            let phase: HardwareButtonPhase =
                switch event.phase {
                case .began: .pressed
                case .ended: .released
                default: .cancelled
                }
            Task { await model.send(.drive(.hardwareButton(phase))) }
        }
        .environment(\.seriesScreenKeeper, screenKeeper)
        // The Live Activity follows the camera model while the camera screen is shown; its Stop
        // button stops the interval series here (StopSeriesIntent runs in the app).
        .environment(\.offersLiveActivity, ActivityAuthorizationInfo().areActivitiesEnabled)
        .task {
            SeriesActivityActions.stop = { [liveActivities, model] in await liveActivities.stopSeries(model) }
            await liveActivities.observe(model)
        }
        // Inactive (Control Center, a system alert) is still the foreground: the camera keeps
        // shooting. An activity starts only while the app is active.
        .onChange(of: scenePhase, initial: true) { _, phase in
            liveActivities.isInForeground = phase != .background
            liveActivities.isActive = phase == .active
        }
        .onChange(of: settings.showsLiveActivity, initial: true) { _, isOn in liveActivities.isEnabled = isOn }
        .onChange(of: settings.isNightModeOn, initial: true) { _, isOn in liveActivities.isNightMode = isOn }
        // Siri and Shortcuts requests are performed while the camera screen is shown.
        .task { await model.serveShortcuts(from: Self.shortcuts, settings: settings, presets: presets) }
        // The Apple Watch app's shutter and status (issue #63), while the camera screen is shown.
        .task { await Self.watchSession.serve(model: model, inbox: Self.shortcuts) }
        #if DEBUG
        // UI tests only: `-NopeSimulatedShortcut <seconds>` sends a Take Photo request.
        .task { await SimulatedShortcut.run(with: Self.shortcuts) }
        .overlay(alignment: .center) { SimulatedShortcut.ResultView() }
        #endif
        // The battery and Low Power Mode warnings follow the system's change notifications;
        // nothing polls (AGENTS.md, "Battery").
        .task { await refreshDeviceStatus(on: UIDevice.batteryLevelDidChangeNotification) }
        .task { await refreshDeviceStatus(on: UIDevice.batteryStateDidChangeNotification) }
        .task { await refreshDeviceStatus(on: .NSProcessInfoPowerStateDidChange) }
        // The Last Photo viewer's previews are the first thing to let go when memory is low;
        // leaving the foreground releases them too (docs/PRIVACY.md, "Last photo and its
        // details").
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification) {
                await model.send(.releasePhotoPreviews)
            }
        }
        // The compare view's pictures (issue #55); set once, as for the location below.
        .task { if model.comparison.renderer == nil { model.comparison.renderer = Self.makeComparisonRenderer() } }
        // The person's save settings (formats, metadata, signing) apply from the next photo.
        .onChange(of: settings.save, initial: true) { _, save in
            model.saveSettings = save
        }
        // Location runs only while the Location switch is on and the camera is running
        // (AGENTS.md, "Battery"); LocationTagging holds the rule.
        .task(id: [settings.metadata.isOn(.location), model.sessionStatus == .running]) {
            // Set once: assigning an observed property, even the same object, redraws the camera.
            if model.location !== location { model.location = location }
            await location.update(
                isOn: settings.metadata.isOn(.location), cameraIsRunning: model.sessionStatus == .running)
        }
        // The "Manual controls" option from Settings shows or hides the manual controls. A
        // preset sets them up itself, with the astro helper, so its change isn't sent again.
        .task(id: settings.showsManualControls) {
            guard !presets.handlesManualControlsChange(to: settings.showsManualControls) else { return }
            await model.send(.manual(.setEnabled(settings.showsManualControls)))
        }
        // "Fast Shutter": full auto's shutter rule, applied when the camera opens and whenever the
        // choice changes (in Settings or the quick-controls tray).
        .task(id: settings.fastShutter) {
            await model.send(.auto(.setFastShutter(settings.fastShutter)))
        }
        // Face Detection (issue #57): applied when the camera opens and whenever it changes.
        .task(id: settings.followsFaces) {
            await model.send(.auto(.setFollowsFaces(settings.followsFaces)))
        }
        // The photo size of each lens that offers a choice (issue #57).
        .task(id: settings.photoSizes) {
            await model.send(.setPhotoSizes(settings.photoSizes))
        }
        // "Start in clean view": applied when the camera opens and whenever the option changes;
        // the camera's own button still toggles clean view at any time.
        .task(id: settings.startsInCleanView) {
            await model.send(.setCleanView(settings.startsInCleanView))
        }
        // The remembered flash mode and light brightness (issue #38); the light itself always
        // starts off.
        .task(id: settings.flashMode) {
            await model.send(.light(.setFlashMode(settings.flashMode)))
        }
        .task(id: settings.torchLevel) {
            await model.send(.light(.setTorchLevel(settings.torchLevel)))
        }
        // A control's change normally arrives at once (`SharedSettingsSync`); reading the store
        // again on return to the foreground also covers a signal sent while the app was suspended.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, Self.settingsSync != nil, settings.reload() { Self.settingsDidChange() }
            #if DEBUG
            // UI tests: the simulated camera is interrupted in the background, as AVFoundation's is.
            SimulatedCameraLaunch.followScenePhase(phase == .background, backend: Self.backend)
            #endif
        }
    }

    /// Reads the storage and battery again each time the notification is posted, for as long as
    /// the camera screen is shown.
    ///
    /// - Parameter name: A battery or power state notification.
    private func refreshDeviceStatus(on name: Notification.Name) async {
        for await _ in NotificationCenter.default.notifications(named: name) {
            model.deviceStatus.refresh()
        }
    }

    /// The storage and battery reader: fixed values for a UI test in Debug builds, otherwise
    /// the system's.
    @MainActor private static func makeDeviceStatusReader() -> any DeviceStatusReading {
        #if DEBUG
        if let reader = SimulatedDeviceStatus.reader() { return reader }
        #endif
        return SystemDeviceStatusReader()
    }

    /// The level's motion readings: Core Motion, or in Debug builds launched by the UI tests, a
    /// fixed reading (``SimulatedGravity``), because the Simulator has no motion sensors.
    private static var gravitySource: any GravitySource {
        #if DEBUG
        if let simulated = SimulatedGravity.fromLaunchArguments() { return simulated }
        #endif
        return MotionGravitySource()
    }

    /// Where settings are stored: the App Group's `UserDefaults`, shared with the controls (with
    /// the settings of earlier versions moved in once), or in Debug builds launched by the UI
    /// tests, an empty store of their own, so every test starts from the defaults.
    private static func makeSettingsStore() -> UserDefaults {
        #if DEBUG
        if let store = SimulatedCameraLaunch.settingsStore() { return store }
        #endif
        return SharedSettings.appStore()
    }

    /// Follows the shared settings, and hands the current ones to the Lock Screen camera.
    ///
    /// - Returns: The sync, or `nil` without the App Group or in a UI test.
    private static func makeSettingsSync() -> SharedSettingsSync? {
        #if DEBUG
        if SimulatedCameraLaunch.scenario != nil { return nil }
        #endif
        guard let signal = SharedSettings.changeSignal else { return nil }
        let sync = SharedSettingsSync(settings: sharedSettings, signal: signal) { settingsDidChange() }
        settingsDidChange()
        return sync
    }

    /// After a settings change here or in a control: refreshes the Night Mode control and hands the
    /// settings to the Lock Screen camera. Never called in UI tests, so they can't change either.
    private static func settingsDidChange() {
        ControlCenter.shared.reloadControls(ofKind: NopeControlKind.nightMode)
        Task { await SharedSettings.publishToLockScreenCamera(sharedSettings) }
    }

    /// The location service for this launch: a simulated one for a UI test scenario in Debug
    /// builds, otherwise Core Location.
    private static func makeLocationProvider() -> any LocationProviding {
        #if DEBUG
        if let provider = SimulatedLocationLaunch.provider() { return provider }
        #endif
        return CoreLocationProvider()
    }

    /// The save pipeline for this launch: simulated steps for a UI test scenario in Debug builds,
    /// otherwise the RAW developer, the ImageIO read-back and add-only PhotoKit.
    ///
    /// Every file is signed with Content Credentials when the signature switch is on: a new
    /// Secure Enclave key per file on a device (`platformKeyProvider()`), fully offline. If
    /// signing fails, the photo is saved unsigned and the status says so.
    private static func makeSaver() -> PhotoSaver {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        #if DEBUG
        if let saver = SimulatedCameraLaunch.saver(appVersion: version) { return saver }
        #endif
        return PhotoSaver(
            developer: RAWDeveloper(),
            signer: ContentCredentialsSigner(
                keyProvider: platformKeyProvider(), generator: ClaimGenerator(version: version)),
            reader: ImageIOReadBack(), library: PhotoKitLibrary(),
            appVersion: version, thumbnailer: ImageIOThumbnailer(),
            previewer: ImageIOPreviewer())
    }

    /// Decodes both photos of the comparison shot for the compare view (issue #55): ImageIO, in
    /// memory, up to 4032 pixels on the long side, the size of the 12 MP photos the app takes
    /// (`CapturePolicy` picks the lens's smallest photo size), so zooming in shows the photos'
    /// own pixels. In Debug builds launched by the UI tests, two plain colored pictures.
    private static func makeComparisonRenderer() -> any PhotoThumbnailing {
        #if DEBUG
        if SimulatedCameraLaunch.scenario != nil { return SimulatedComparisonRenderer() }
        #endif
        return ImageIOThumbnailer(maximumPixelSize: 4032)
    }

    /// The backend for this launch: the simulated one for a UI test scenario in Debug builds,
    /// otherwise the device's cameras.
    private static func makeBackend() -> any CaptureBackend {
        #if DEBUG
        if let backend = SimulatedCameraLaunch.backend() { return backend }
        #endif
        return AVFoundationCaptureBackend()
    }
}
