import Foundation
import Observation

/// The camera's state machine: the single object an interface talks to.
///
/// An interface observes ``state``, ``selectedLens``, ``captureFormat``, ``sessionStatus`` and
/// ``captureStatus``, and sends ``CameraIntent`` values through ``send(_:)``. It also runs
/// ``observeEvents()`` for as long as it is visible. The model asks its ``CaptureBackend`` for
/// facts and decides the next state; the interface holds no rules of its own (AGENTS.md, "One
/// direction of flow").
///
/// The model is isolated to the main actor, so an interface can read its properties directly.
@MainActor
@Observable
public final class CameraModel {
    /// The current camera state. Interfaces render it; only the model changes it.
    public private(set) var state: CameraState = .starting

    /// The identifier of the lens in use, once the camera is ready.
    public private(set) var selectedLensID: Lens.ID?

    /// Whether the camera is running, and if not, why. Meaningful while ``state`` is
    /// ``CameraState/ready(_:)``.
    public private(set) var sessionStatus: SessionStatus = .stopped

    /// The state of the most recent capture.
    public internal(set) var captureStatus: CaptureStatus = .idle

    /// The formats and metadata choices used for the next photo. A Settings screen changes them
    /// through ``SaveSettings`` and ``MetadataSettings``, whose methods hold the rules.
    public var saveSettings = SaveSettings()

    /// Location tagging (issue #43), which gives each photo its location while the Location
    /// switch is on, or `nil` when the app has no location service (previews, tests). The app
    /// sets it once.
    public var location: LocationTagging?

    /// Builds, checks and saves each photo, or `nil` when this model can't save (previews).
    let saver: PhotoSaver?

    /// Whether clean view is on: the interface hides every control that isn't essential. Off by
    /// default. Warnings that change what the photo is are never hidden.
    public private(set) var isCleanView = false

    /// Whether the app is in the foreground, as the interface last said with
    /// ``CameraIntent/setInForeground(_:)``. `true` until it says otherwise.
    public internal(set) var isInForeground = true

    /// The manual and pro controls. Their intents arrive as ``CameraIntent/manual(_:)``.
    public let manual: ManualControlsModel

    /// The drive mode, the self-timer and bursts. Their intents arrive as ``CameraIntent/drive(_:)``.
    public let drive: DriveModel

    /// The device's free storage and battery, for warnings and to stop a burst in time.
    public let deviceStatus: DeviceStatus

    /// The live aids over the viewfinder: histogram, focus peaking and the live camera readout.
    public let live: LiveViewModel

    /// Whether the focus magnifier is shown: an enlarged part of the viewfinder for checking
    /// focus. Off by default. It changes only the preview, never the photo or the camera's zoom.
    public private(set) var isMagnifying = false

    /// The flash and the torch. Their intents arrive as ``CameraIntent/light(_:)``.
    public let light: LightModel

    /// The astro helper (issue #60). Its intents arrive as ``CameraIntent/astro(_:)``.
    public let astro = AstroModel()

    /// The comparison shot (issue #55). Its intents arrive as ``CameraIntent/comparison(_:)``.
    public let comparison: ComparisonModel

    /// This session's saved photos with their compressed previews: the pages of the Last Photo
    /// viewer (docs/design/BUILD-SPEC.md, 3.14). Every save adds to it; leaving the foreground
    /// and ``CameraIntent/releasePhotoPreviews`` release the previews (docs/PRIVACY.md, "Last
    /// photo and its details").
    public let sessionPhotos: SessionPhotos

    /// Whether the Last Photo viewer is open, as the interface last said with
    /// ``CameraIntent/setViewerOpen(_:)``. While it is open, a hardware shutter press closes it
    /// and takes no photo (decision V1); the model sets it to `false` then, and when the app
    /// leaves the foreground (decision V7). An interface presents the viewer while it is `true`.
    /// Siri, Shortcuts, the Apple Watch app and a running series still take photos.
    public internal(set) var isViewerOpen = false

    /// Whether the press of a hardware shutter button that is down now closed the viewer, so
    /// its release takes no photo.
    @ObservationIgnored var hardwarePressClosedViewer = false

    /// Reads the device's clock for ``SessionPhoto/takenAt``. Tests replace it.
    @ObservationIgnored var wallClock: @Sendable () -> Date = { Date() }

    /// The person's photo size for each lens (``CameraIntent/setPhotoSizes(_:)``), applied when
    /// the camera starts with a lens. Empty by default: every lens at its default size.
    public private(set) var photoSizes: [Lens.ID: PhotoDimensions] = [:]

    /// The last heat level the backend reported.
    private var heatLevel: HeatLevel = .nominal

    /// The hardware the model asks for permission, capabilities and photos.
    let backend: any CaptureBackend

    /// Reads the monotonic clock, to time each capture for the photo's details (issue #53).
    let now: @Sendable () -> ContinuousClock.Instant

    /// Waits ``pauseAfterErrorSeconds`` after a photo of a series fails, for the pause that may
    /// have caused it (`failureWasAPause()`). Tests replace it.
    @ObservationIgnored var pauseAfterErrorSleep: @Sendable () async throws -> Void = {
        try await Task.sleep(for: .seconds(CameraModel.pauseAfterErrorSeconds))
    }

    /// Creates a model in the ``CameraState/starting`` state.
    ///
    /// - Parameters:
    ///   - backend: The hardware, or a ``SimulatedCaptureBackend`` in tests and previews.
    ///   - saver: The save pipeline. Without one, every photo ends in
    ///     ``CaptureError/savingUnavailable`` and nothing is saved.
    ///   - sleep: Waits a number of seconds between interval photos and self-timer ticks. Tests
    ///     pass a faster one.
    ///   - now: Reads the clock that times each capture. Tests pass a scripted one.
    ///   - deviceStatusReader: Reads the free storage and battery, or `nil` for no warnings.
    ///
    /// A ``ManualCaptureBackend`` also gets manual controls (``manual``), and a
    /// ``LightCaptureBackend`` a torch (``light``).
    public init(
        backend: any CaptureBackend, saver: PhotoSaver? = nil,
        sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
        deviceStatusReader: (any DeviceStatusReading)? = nil
    ) {
        self.backend = backend
        self.saver = saver
        self.now = now
        manual = ManualControlsModel(backend: backend as? any ManualCaptureBackend, sleep: sleep)
        drive = DriveModel(sleep: sleep)
        deviceStatus = DeviceStatus(reader: deviceStatusReader)
        live = LiveViewModel(backend: backend as? any LiveViewBackend)
        light = LightModel(backend: backend as? any LightCaptureBackend)
        comparison = ComparisonModel(backend: backend as? any ComparisonCaptureBackend)
        sessionPhotos = SessionPhotos(decoder: saver?.previewer)
    }

    /// The handle the app turns into the live viewfinder, or `nil` when there is no video.
    public var previewSource: (any CameraPreviewSource)? {
        backend.previewSource
    }

    /// The device's capabilities while ``state`` is ``CameraState/ready(_:)``, otherwise `nil`.
    public var capabilities: DeviceCapabilities? {
        guard case .ready(let capabilities) = state else { return nil }
        return capabilities
    }

    /// The distortion correction of the lens a photo was taken with, for its details (issue #80),
    /// or `nil` when the lens isn't known.
    ///
    /// - Parameter photo: A captured photo.
    /// - Returns: The lens's ``Lens/distortionCorrection``.
    func distortionCorrection(of photo: CapturedPhoto) -> DistortionCorrection? {
        capabilities?.lens(withID: photo.lensID)?.distortionCorrection
    }

    /// The lens in use, or `nil` before the camera is ready.
    public var selectedLens: Lens? {
        guard let selectedLensID else { return nil }
        return capabilities?.lens(withID: selectedLensID)
    }

    /// The format the next photo will have: Bayer RAW, or the labeled processed fallback.
    /// `nil` before the camera is ready.
    public var captureFormat: CaptureFormat? {
        selectedLens.map(CaptureFormat.init(for:))
    }

    /// Whether the shutter should be enabled: the camera is running, no photo is being taken
    /// or saved, and the compare view isn't open.
    public var canCapture: Bool {
        sessionStatus.canCapture && captureStatus != .capturing && captureStatus != .saving
            && !comparison.isPresented
    }

    /// Handles one intent from the interface and updates the model's state.
    ///
    /// - Parameter intent: What the interface asks for.
    ///
    /// Side effects: ``CameraIntent/requestPermission`` may show the system camera prompt;
    /// ``CameraIntent/start``, ``CameraIntent/requestPermission`` and
    /// ``CameraIntent/selectLens(_:)`` start or reconfigure the camera;
    /// ``CameraIntent/capture`` takes a photo and, once it passes the metadata read-back, adds
    /// it to Photos (which may show the add-only Photos prompt), or applies the drive mode
    /// (``pressShutter()``).
    public func send(_ intent: CameraIntent) async {
        switch intent {
        case .start:
            await resolve(await backend.currentPermission())
        case .requestPermission:
            await resolve(await backend.requestPermission())
        case .selectLens(let id):
            await selectLens(id)
        case .capture:
            await pressShutter()
        case .manual(let intent):
            if case .startInterval = intent, intervalBlocker != nil { return }
            await manual.handle(intent) { [weak self] in await self?.takeIntervalPhoto() ?? false }
            await manualControlsDidChange(after: intent)
        case .setCleanView(let isOn):
            isCleanView = isOn
        case .drive(let intent):
            await handle(intent)
        case .auto(let intent):
            await handleAuto(intent)
        case .light(let intent):
            if !astroRefuses(intent) { await light.handle(intent) }
        case .astro(let intent):
            await handle(intent)
        case .comparison(let intent):
            comparison.handle(intent)
        case .setPhotoSizes(let sizes):
            await setPhotoSizes(sizes)
        case .setInForeground(let isInForeground):
            setInForeground(isInForeground)
            // Privacy: the previews don't outlast the visit, and the viewer closes
            // (docs/PRIVACY.md; BUILD-SPEC.md, decision V7).
            if !isInForeground {
                isViewerOpen = false
                sessionPhotos.releasePreviews()
            }
        case .releasePhotoPreviews:
            sessionPhotos.releasePreviews()
        case .setViewerOpen(let isOpen):
            isViewerOpen = isOpen
        }
    }

    /// Keeps the person's photo sizes, and reconfigures the camera when the selected lens's size
    /// changed while it was started.
    ///
    /// - Parameter sizes: The chosen size for each lens.
    private func setPhotoSizes(_ sizes: [Lens.ID: PhotoDimensions]) async {
        let previous = selectedLens.flatMap { $0.photoSize(for: photoSizes[$0.id]) }
        photoSizes = sizes
        guard let lens = selectedLens, lens.photoSize(for: sizes[lens.id]) != previous, sessionStatus != .stopped else {
            return
        }
        await startSession()
    }

    /// Applies the backend's events until its stream ends. Run it for as long as the camera
    /// screen is visible, for example in a SwiftUI `.task`.
    public func observeEvents() async {
        for await event in backend.events {
            await handle(event)
        }
    }

    /// Applies one event from the backend.
    ///
    /// - Parameter event: What happened to the camera.
    ///
    /// Side effects: may stop the camera when the device is critically hot, and restart it when
    /// it cools down or after a runtime error.
    private func handle(_ event: CaptureEvent) async {
        switch event {
        case .interrupted(let reason):
            sessionStatus = .interrupted(reason)
            await light.cameraDidPause()
        case .interruptionEnded:
            guard case .interrupted = sessionStatus else { return }
            sessionStatus = .running
            // The camera runs again without a new start, so the light must learn it here: left
            // out, a light asked for after any interruption (a call, or a return from the
            // background) stayed "pending" and never reached the hardware (issue #75).
            await light.sessionDidStart()
        case .heat(let level):
            await applyHeat(level)
        case .failed:
            // Apple's guidance for runtime errors such as a media services reset is to restart
            // the session (AVCaptureSession.runtimeErrorNotification).
            await startSession()
        case .subjectAreaChanged:
            await manual.subjectAreaDidChange()
        case .torchUnavailable:
            light.systemMadeTorchUnavailable()
        }
    }

    /// The lens to suggest when the subject seems closer than the selected lens can focus: the
    /// ultra wide lens, from the wide or a telephoto lens, while
    /// ``ManualControlsModel/suggestsCloseUpLens`` is true. `nil` otherwise. An interface offers
    /// a button to switch; the app never switches on its own (issue #51).
    public var closeUpLens: Lens? {
        guard manual.suggestsCloseUpLens, let kind = selectedLens?.kind, kind == .wide || kind == .telephoto else {
            return nil
        }
        return capabilities?.lenses.first { $0.kind == .ultraWide }
    }

    /// Handles an aid that works in full auto too.
    ///
    /// - Parameter intent: The intent.
    ///
    /// Side effects: may refocus or re-expose the camera.
    private func handleAuto(_ intent: AutoControlIntent) async {
        switch intent {
        case .focusAndExpose(let point):
            await focus(at: point, locks: false)
        case .lockFocusAndExposure(let point):
            await focus(at: point ?? manual.focusTarget?.viewfinderPoint ?? .center, locks: true)
        case .unlockFocusAndExposure:
            await manual.unlockFocus()
        case .setExposureCompensation(let value):
            await manual.setExposureCompensation(value)
        case .stepExposureCompensation(let steps):
            await manual.stepExposureCompensation(by: steps)
        case .setNearFocusLimit(let isOn):
            await manual.setNearFocusLimit(isOn)
        case .setFarFocusLimit(let isOn):
            await manual.setFarFocusLimit(isOn)
        case .setFollowsFaces(let isOn):
            await manual.setFollowsFaces(isOn)
        case .setFastShutter(let choice):
            await manual.setFastShutter(choice)
        case .dismissCloseUpSuggestion:
            manual.dismissCloseUpSuggestion()
        case .setMagnifier(let isOn):
            isMagnifying = isOn
        }
    }

    /// Aims focus and exposure at a viewfinder point, converted to the camera's coordinates by
    /// the preview. A backend without a preview has no rotation, so the point is used as it is.
    ///
    /// - Parameters:
    ///   - point: The point in the viewfinder.
    ///   - locks: Whether to lock focus and exposure there.
    private func focus(at point: FramePoint, locks: Bool) async {
        let devicePoint = previewSource.map { $0.devicePoint(forViewfinderPoint: point) } ?? point
        guard let devicePoint else { return }
        await manual.focus(at: point, devicePoint: devicePoint, locks: locks)
    }

    /// Pauses the camera at a critical heat level and resumes it when the device cools down.
    ///
    /// - Parameter level: The new heat level.
    private func applyHeat(_ level: HeatLevel) async {
        heatLevel = level
        if level.requiresPause {
            guard sessionStatus != .pausedForHeat, selectedLensID != nil else { return }
            sessionStatus = .pausedForHeat
            await light.cameraDidPause()
            await backend.stopSession()
        } else if sessionStatus == .pausedForHeat {
            await startSession()
        }
    }

    /// Moves to the state that matches a permission, discovering capabilities and starting the
    /// camera when allowed.
    ///
    /// - Parameter permission: The permission the backend just reported.
    private func resolve(_ permission: CameraPermission) async {
        switch permission {
        case .notDetermined:
            state = .needsPermission
        case .denied, .restricted:
            state = .permissionDenied
        case .authorized:
            let capabilities = await backend.deviceCapabilities()
            guard let lens = capabilities.defaultLens else {
                state = .unavailable
                return
            }
            state = .ready(capabilities)
            selectedLensID = lens.id
            deviceStatus.refresh()
            await startSession()
        }
    }

    /// Switches to another lens, ignoring unknown identifiers and the lens already in use.
    ///
    /// - Parameter id: The lens to switch to.
    private func selectLens(_ id: Lens.ID) async {
        guard id != selectedLensID, capabilities?.lens(withID: id) != nil else { return }
        selectedLensID = id
        await startSession()
        await astroLensDidChange()
    }

    /// Starts or reconfigures the camera for the selected lens, unless the device is too hot.
    private func startSession() async {
        guard let lens = selectedLens else { return }
        guard !heatLevel.requiresPause else {
            sessionStatus = .pausedForHeat
            return
        }
        sessionStatus = .starting
        manual.lensWillStart(lens)
        light.lensWillStart(lens)
        do {
            try await backend.startSession(CaptureRequest(lens: lens, photoSize: lens.photoSize(for: photoSizes[lens.id])))
            // An interruption or heat event may have arrived while starting; it wins.
            if sessionStatus == .starting { sessionStatus = .running }
            // Starting the camera returns its controls to automatic; apply the manual ones again.
            await manual.sessionDidStart()
            await light.sessionDidStart()
        } catch {
            sessionStatus = .failed(error)
            // The camera didn't start, so a light waiting for it is turned off rather than left
            // waiting (issue #75).
            await light.cameraDidPause()
        }
    }

    /// Takes one photo with the selected lens, if the camera can capture now.
    ///
    /// A blank photo (``CaptureError/blankPicture``) is never kept: the model restarts the
    /// camera once and takes the photo again (`recoverFromBlankPicture(_:settings:)`).
    ///
    /// - Parameter onceBracket: A bracket to take this time only, through the same bracket path
    ///   as the one in Pro Tools, without changing ``ManualControlsModel/bracket`` (a Siri or
    ///   Shortcuts request, issue #62); `nil` for the shutter's usual photo. The caller checks
    ///   first that ``ManualControlsModel/bracketFrames(once:)`` can plan it.
    func capture(onceBracket: BracketSettings? = nil) async {
        guard canCapture, let lens = selectedLens else { return }
        deviceStatus.refresh()
        captureStatus = .capturing
        let settings = saveSettings
        var plan = saver?.plan(for: settings.metadata) ?? MetadataPlan(settings: settings.metadata)
        plan.location = location?.location(isOn: settings.metadata.isOn(.location))
        plan.mirrorsHorizontally = lens.kind == .front && settings.mirrorsFrontCamera
        let request = CaptureRequest(lens: lens, metadata: plan, flashMode: light.flashModeForCapture)
        let frames = onceBracket.map(manual.bracketFrames(once:)) ?? manual.bracketFrames()
        if let frames, let bracketBackend = backend as? any ManualCaptureBackend {
            await captureBracket(request, frames: frames, backend: bracketBackend, settings: settings)
            return
        }
        let comparisonBackend = comparisonBackendForNextPhoto
        do {
            let start = now()
            let takenAt = wallClock()
            let photo = try await backend.capturePhoto(request)
            if let comparisonBackend {
                await saveComparing(
                    photo, started: start, takenAt: takenAt, request: request, settings: settings,
                    backend: comparisonBackend)
                return
            }
            await save(photo, lens: lens, takenAt: takenAt, settings: settings, captureDuration: now() - start)
        } catch .blankPicture {
            await recoverFromBlankPicture(request, settings: settings)
        } catch {
            captureStatus = .failed(error)
        }
    }

    /// Saves a captured photo through the ``PhotoSaver``, and records the result.
    ///
    /// Side effects: may show the add-only Photos prompt; adds the photo to Photos.
    ///
    /// - Parameters:
    ///   - photo: The captured photo.
    ///   - lens: The lens it was taken with, for ``sessionPhotos``.
    ///   - takenAt: When the shutter took it, for ``sessionPhotos``.
    ///   - settings: The settings the photo was taken with.
    ///   - captureDuration: How long the camera took to return the photo.
    private func save(
        _ photo: CapturedPhoto, lens: Lens, takenAt: Date, settings: SaveSettings, captureDuration: Duration
    ) async {
        guard let saver else {
            captureStatus = .failed(.savingUnavailable)
            return
        }
        captureStatus = .saving
        do {
            let result = try await saver.saveWithPreview(
                photo, settings: settings, captureDuration: captureDuration,
                distortionCorrection: distortionCorrection(of: photo))
            keepInSession(result, lens: lens, takenAt: takenAt)
            captureStatus = .saved(result.saved)
        } catch {
            captureStatus = .failed(error)
        }
        deviceStatus.refresh()
    }

    /// Handles a blank photo: stops the camera, starts it again, and retries the photo once.
    ///
    /// On a device, a camera that runs and sends frames whose buffers are all zero stayed that
    /// way until the device was restarted (docs/TESTING.md, "Black frames"). One restart of the
    /// session is the cheap fix to try first; if the retry is blank too, the model moves to
    /// ``SessionStatus/noPicture`` and stops retrying, so the person is told to restart the
    /// device instead of pressing the shutter again and again.
    ///
    /// Side effects: stops and restarts the camera, and takes a second photo if it comes back.
    ///
    /// - Parameters:
    ///   - request: The request whose photo was blank.
    ///   - settings: The settings the photo is taken with.
    private func recoverFromBlankPicture(_ request: CaptureRequest, settings: SaveSettings) async {
        await backend.stopSession()
        await startSession()
        guard sessionStatus == .running else {
            captureStatus = .failed(.blankPicture)
            return
        }
        do {
            let start = now()
            let takenAt = wallClock()
            let photo = try await backend.capturePhoto(request)
            await save(photo, lens: request.lens, takenAt: takenAt, settings: settings, captureDuration: now() - start)
        } catch .blankPicture {
            sessionStatus = .noPicture
            captureStatus = .failed(.blankPicture)
        } catch {
            captureStatus = .failed(error)
        }
    }

    /// Takes an exposure bracket and saves each frame as its own photo: separate single-frame
    /// photos, nothing merged. Saving stops at the first frame that fails, and a failed or
    /// blank bracket isn't retried; the person can press the shutter again.
    ///
    /// Side effects: may show the add-only Photos prompt; adds each photo to Photos.
    ///
    /// - Parameters:
    ///   - request: The lens, format and metadata plan.
    ///   - frames: Each frame's ISO and exposure duration.
    ///   - backend: The backend, which supports brackets.
    ///   - settings: The settings the photos are taken with.
    private func captureBracket(
        _ request: CaptureRequest, frames: [BracketFrame], backend: any ManualCaptureBackend, settings: SaveSettings
    ) async {
        do {
            let takenAt = wallClock()
            let photos = try await backend.captureBracket(request, frames: frames)
            guard let saver else {
                captureStatus = .failed(.savingUnavailable)
                return
            }
            captureStatus = .saving
            var saved: [SavedPhoto] = []
            for photo in photos {
                let result = try await saver.saveWithPreview(
                    photo, settings: settings, distortionCorrection: distortionCorrection(of: photo))
                keepInSession(result, lens: request.lens, takenAt: takenAt)
                saved.append(result.saved)
            }
            captureStatus = .savedBracket(saved)
        } catch {
            captureStatus = .failed(error)
        }
    }

    /// Adds a saved photo and its preview to ``sessionPhotos``. A preview made after the app
    /// left the foreground is released at once, so none outlasts the visit.
    ///
    /// - Parameters:
    ///   - result: The saved photo and its preview.
    ///   - lens: The lens it was taken with.
    ///   - takenAt: When the shutter took it.
    func keepInSession(_ result: (saved: SavedPhoto, preview: PhotoPreview?), lens: Lens, takenAt: Date) {
        sessionPhotos.add(result.saved, lens: lens, takenAt: takenAt, preview: isInForeground ? result.preview : nil)
    }
}
