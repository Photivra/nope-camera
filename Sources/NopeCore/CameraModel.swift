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
    public private(set) var captureStatus: CaptureStatus = .idle

    /// Whether clean view is on: the interface hides every control that isn't essential. Off by
    /// default. Warnings that change what the photo is are never hidden.
    public private(set) var isCleanView = false

    /// The manual and pro controls. Their intents arrive as ``CameraIntent/manual(_:)``.
    public let manual: ManualControlsModel

    /// The last heat level the backend reported.
    private var heatLevel: HeatLevel = .nominal

    /// The hardware the model asks for permission, capabilities and photos.
    private let backend: any CaptureBackend

    /// Creates a model in the ``CameraState/starting`` state.
    ///
    /// - Parameters:
    ///   - backend: The hardware, or a ``SimulatedCaptureBackend`` in tests and previews. A
    ///     ``ManualCaptureBackend`` also gets manual controls.
    ///   - sleep: Waits a number of seconds between interval photos. Tests pass a faster one.
    public init(
        backend: any CaptureBackend,
        sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.backend = backend
        manual = ManualControlsModel(backend: backend as? any ManualCaptureBackend, sleep: sleep)
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

    /// Whether the shutter should be enabled: the camera is running and no photo is being taken.
    public var canCapture: Bool {
        sessionStatus.canCapture && captureStatus != .capturing
    }

    /// Handles one intent from the interface and updates the model's state.
    ///
    /// - Parameter intent: What the interface asks for.
    ///
    /// Side effects: ``CameraIntent/requestPermission`` may show the system camera prompt;
    /// ``CameraIntent/start``, ``CameraIntent/requestPermission`` and
    /// ``CameraIntent/selectLens(_:)`` start or reconfigure the camera;
    /// ``CameraIntent/capture`` takes a photo, held in memory only.
    public func send(_ intent: CameraIntent) async {
        switch intent {
        case .start:
            await resolve(await backend.currentPermission())
        case .requestPermission:
            await resolve(await backend.requestPermission())
        case .selectLens(let id):
            await selectLens(id)
        case .capture:
            await capture()
        case .manual(let intent):
            await manual.handle(intent) { [weak self] in await self?.capture() }
        case .setCleanView(let isOn):
            isCleanView = isOn
        }
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
        case .interruptionEnded:
            if case .interrupted = sessionStatus { sessionStatus = .running }
        case .heat(let level):
            await applyHeat(level)
        case .failed:
            // Apple's guidance for runtime errors such as a media services reset is to restart
            // the session (AVCaptureSession.runtimeErrorNotification).
            await startSession()
        }
    }

    /// Pauses the camera at a critical heat level and resumes it when the device cools down.
    ///
    /// - Parameter level: The new heat level.
    private func applyHeat(_ level: HeatLevel) async {
        heatLevel = level
        if level.requiresPause {
            guard sessionStatus != .pausedForHeat, selectedLensID != nil else { return }
            sessionStatus = .pausedForHeat
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
        do {
            try await backend.startSession(CaptureRequest(lens: lens))
            // An interruption or heat event may have arrived while starting; it wins.
            if sessionStatus == .starting { sessionStatus = .running }
            // Starting the camera returns its controls to automatic; apply the manual ones again.
            await manual.sessionDidStart()
        } catch {
            sessionStatus = .failed(error)
        }
    }

    /// Takes one photo with the selected lens, if the camera can capture now.
    ///
    /// A blank photo (``CaptureError/blankPicture``) is never kept: the model restarts the
    /// camera once and takes the photo again (``recoverFromBlankPicture(_:)``).
    private func capture() async {
        guard canCapture, let lens = selectedLens else { return }
        captureStatus = .capturing
        let request = CaptureRequest(lens: lens)
        if let frames = manual.bracketFrames(), let bracketBackend = backend as? any ManualCaptureBackend {
            await captureBracket(request, frames: frames, backend: bracketBackend)
            return
        }
        do {
            captureStatus = .captured(try await backend.capturePhoto(request))
        } catch .blankPicture {
            await recoverFromBlankPicture(request)
        } catch {
            captureStatus = .failed(error)
        }
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
    /// - Parameter request: The request whose photo was blank.
    private func recoverFromBlankPicture(_ request: CaptureRequest) async {
        await backend.stopSession()
        await startSession()
        guard sessionStatus == .running else {
            captureStatus = .failed(.blankPicture)
            return
        }
        do {
            captureStatus = .captured(try await backend.capturePhoto(request))
        } catch .blankPicture {
            sessionStatus = .noPicture
            captureStatus = .failed(.blankPicture)
        } catch {
            captureStatus = .failed(error)
        }
    }

    /// Takes an exposure bracket: separate single-frame photos, nothing merged. A failed or
    /// blank bracket isn't retried; the person can press the shutter again.
    ///
    /// - Parameters:
    ///   - request: The lens and format.
    ///   - frames: Each frame's ISO and exposure duration.
    ///   - backend: The backend, which supports brackets.
    private func captureBracket(
        _ request: CaptureRequest, frames: [BracketFrame], backend: any ManualCaptureBackend
    ) async {
        do {
            captureStatus = .capturedBracket(try await backend.captureBracket(request, frames: frames))
        } catch {
            captureStatus = .failed(error)
        }
    }
}
