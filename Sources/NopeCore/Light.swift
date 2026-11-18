import Foundation

/// When the flash fires for a photo (issue #38).
///
/// The flash only adds light; the app turns on no processing with it. Each lens lists the modes
/// it supports in ``Lens/flashModes``; an interface offers a flash control only when that list
/// has a mode other than ``off``.
public enum FlashMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// The flash never fires. The default.
    case off
    /// The camera decides at capture time whether the scene needs the flash.
    case auto
    /// The flash fires for every photo, unless the device is too hot for it (the system then
    /// takes the photo without it).
    case on
}

/// The state of the torch, the light that stays on while framing and taking photos
/// (issue #38): for close subjects in the dark, such as an insect at night.
public enum TorchStatus: Equatable, Sendable {
    /// The light is off.
    case off

    /// The light is on at a brightness level from just above 0 to 1 (full).
    case on(level: Double)

    /// The person asked for the light while the camera isn't ready for it: it is starting,
    /// or switching lenses or settings, so no camera is attached to switch (issue #75). The
    /// light is off for now. It is applied as soon as the camera has started, and then becomes
    /// ``on(level:)``, or ``unavailable`` if the system refuses it. An interface shows the
    /// person's choice (the switch stays on), not "off".
    case pending

    /// The person asked for the light, but the system didn't allow it or turned it off, for
    /// example because the device is too hot. The light is off. An interface says so until the
    /// person turns the light off or tries again.
    case unavailable
}

/// A request an interface sends to change the flash or the torch, wrapped in
/// ``CameraIntent/light(_:)``.
public enum LightIntent: Equatable, Sendable {
    /// Choose when the flash fires. A mode the lens doesn't support means no flash on that lens.
    case setFlashMode(FlashMode)

    /// Turn the torch on or off. Ignored while the lens has no torch.
    case setTorch(Bool)

    /// Set the torch's brightness, from just above 0 to 1. Moved inside
    /// ``LightModel/torchLevelRange``. Applies at once when the torch is on.
    case setTorchLevel(Double)
}

/// A ``CaptureBackend`` that can also switch the torch of the running lens.
///
/// `NopeCapture`'s AVFoundation backend and ``SimulatedCaptureBackend`` implement it. With a
/// backend that doesn't, ``LightModel`` offers no torch.
public protocol LightCaptureBackend: CaptureBackend {
    /// Turns the torch of the running lens on at a brightness level, or off.
    ///
    /// The system may refuse a level while the device is hot; the backend then reports
    /// ``TorchStatus/unavailable`` and leaves the light off. Stopping the camera or switching
    /// lenses turns the light off, so ``LightModel`` asks again after each start.
    ///
    /// A request to turn the light on while no camera is attached (before the start, or while
    /// the camera is reconfigured) is answered ``TorchStatus/pending``, never
    /// ``TorchStatus/off``: the light can't be switched yet, and ``LightModel`` applies it after
    /// the start (issue #75).
    ///
    /// - Parameter level: The brightness, from just above 0 to 1, or `nil` to turn the light
    ///   off.
    /// - Returns: The light's state afterwards.
    func setTorch(level: Double?) async -> TorchStatus
}

/// The flash and the torch: what the person chose, and what the light is doing (issue #38).
///
/// ``CameraModel`` owns one as ``CameraModel/light`` and sends it ``CameraIntent/light(_:)``
/// intents. The rules:
///
/// - The torch stays on while framing, focusing and taking photos; while it is on, the flash
///   is off for every photo, so the light doesn't change or blink when the shutter fires.
///   Choosing Auto or On for the flash turns the torch off.
/// - The torch turns off when the camera stops, pauses (an interruption, heat) or switches to a
///   lens without a torch (AGENTS.md, "Battery"). The brightness level is kept.
/// - After a restart of the same lens, such as a recovery from an error, a torch that was on
///   comes back on.
/// - A request made before the camera is ready is kept as ``TorchStatus/pending`` and applied
///   once the camera has started; the light then comes on or is reported unavailable, never
///   silently turned off (issue #75).
///
/// Isolated to the main actor, like ``CameraModel``.
@MainActor
@Observable
public final class LightModel {
    /// The brightness levels an interface offers, from dim to full. A dim level suits close
    /// subjects, which a full torch would wash out.
    nonisolated public static let torchLevels: [Double] = [0.1, 0.25, 0.5, 0.75, 1]

    /// The brightness the torch starts at until the person picks another: a quarter.
    nonisolated public static let defaultTorchLevel = 0.25

    /// The levels the torch accepts. AVFoundation takes a level above 0 and up to 1
    /// (`AVCaptureDevice.setTorchModeOn(level:)`); 0 is "off", which ``LightIntent/setTorch(_:)``
    /// handles.
    nonisolated public static let torchLevelRange: ClosedRange<Double> = 0.01...1

    /// Moves a brightness level inside ``torchLevelRange``.
    ///
    /// - Parameter level: A brightness level.
    /// - Returns: The nearest level in the range.
    nonisolated public static func clampedTorchLevel(_ level: Double) -> Double {
        min(max(level, torchLevelRange.lowerBound), torchLevelRange.upperBound)
    }

    /// When the flash fires, as the person chose. Applies only on a lens that supports it and
    /// while the torch is off (``flashModeForCapture``).
    public private(set) var flashMode: FlashMode = .off

    /// The torch's brightness, as the person chose. Kept while the light is off.
    public private(set) var torchLevel = LightModel.defaultTorchLevel

    /// What the torch is doing now.
    public private(set) var torch: TorchStatus = .off

    /// The lens in use, or `nil` before the camera starts.
    private var lens: Lens?

    /// Whether the camera is running, so the torch can be switched.
    private var isRunning = false

    /// Whether the person wants the torch on. It survives a restart of the same lens, and
    /// is what ``TorchStatus/pending`` shows while the camera isn't ready.
    private var wantsTorch = false

    /// The hardware, or `nil` when the backend has no torch.
    private let backend: (any LightCaptureBackend)?

    /// Creates the model.
    ///
    /// - Parameter backend: The hardware, or `nil` for no torch.
    public init(backend: (any LightCaptureBackend)?) {
        self.backend = backend
    }

    /// Whether the lens in use has a torch the app can switch.
    public var supportsTorch: Bool {
        backend != nil && lens?.hasTorch == true
    }

    /// The flash modes of the lens in use, in ``FlashMode`` order (off first); empty before the
    /// camera starts and on a lens with no flash.
    public var supportedFlashModes: [FlashMode] {
        FlashMode.allCases.filter { lens?.flashModes.contains($0) == true }
    }

    /// Whether the lens in use has a flash: it supports a mode other than ``FlashMode/off``.
    public var supportsFlash: Bool {
        supportedFlashModes.contains { $0 != .off }
    }

    /// Whether the torch is on now.
    public var isTorchOn: Bool {
        if case .on = torch { true } else { false }
    }

    /// The flash mode for the next photo: the person's choice when the lens supports it, and
    /// ``FlashMode/off`` while the torch is on, so the steady light isn't replaced by a flash.
    public var flashModeForCapture: FlashMode {
        guard !isTorchOn, supportedFlashModes.contains(flashMode) else { return .off }
        return flashMode
    }

    /// Handles one light intent.
    ///
    /// - Parameter intent: What the interface asks for.
    ///
    /// Side effect: may switch the torch on or off.
    func handle(_ intent: LightIntent) async {
        switch intent {
        case .setFlashMode(let mode):
            flashMode = mode
            // The last choice wins: choosing a flash turns the steady light off, so the photo
            // gets the light the person just asked for.
            if mode != .off, isTorchOn { await setTorch(false) }
        case .setTorch(let isOn):
            await setTorch(isOn)
        case .setTorchLevel(let level):
            torchLevel = Self.clampedTorchLevel(level)
            if isTorchOn { await applyTorch() }
        }
    }

    /// Records the lens the camera is about to start with. Called by ``CameraModel`` before
    /// each start; the light is off until ``sessionDidStart()``, and shows
    /// ``TorchStatus/pending`` meanwhile when the person wants it.
    ///
    /// - Parameter lens: The lens.
    func lensWillStart(_ lens: Lens) {
        if !lens.hasTorch { wantsTorch = false }
        self.lens = lens
        isRunning = false
        if torch != .unavailable { torch = wantsTorch ? .pending : .off }
    }

    /// Records that the camera runs, after a start or after an interruption ended, and turns the
    /// torch on if the person asked for it meanwhile and the lens has one.
    ///
    /// Side effect: may switch the torch on.
    func sessionDidStart() async {
        isRunning = true
        // Only a lens with a torch keeps the wish (`lensWillStart(_:)`), and only a backend
        // with a torch sets it (`setTorch(_:)`).
        guard wantsTorch else { return }
        await applyTorch()
    }

    /// Turns the torch off because the camera stopped or paused (an interruption, heat, or the app
    /// leaving the screen). The person turns it on again when they want it.
    ///
    /// Side effect: switches the torch off.
    func cameraDidPause() async {
        isRunning = false
        wantsTorch = false
        if torch == .pending { torch = .off }
        guard isTorchOn else { return }
        torch = .off
        _ = await backend?.setTorch(level: nil)
    }

    /// Records that the system took the light away, for example because the device is too hot.
    func systemMadeTorchUnavailable() {
        guard wantsTorch || isTorchOn else { return }
        wantsTorch = false
        torch = .unavailable
    }

    /// Turns the torch on or off.
    ///
    /// - Parameter isOn: Whether the person wants the light.
    private func setTorch(_ isOn: Bool) async {
        if isOn {
            guard supportsTorch else { return }
            wantsTorch = true
            guard isRunning else {
                // Kept, and shown, until the camera has started (issue #75).
                torch = .pending
                return
            }
            await applyTorch()
        } else {
            wantsTorch = false
            let wasOn = isTorchOn
            torch = .off
            if wasOn { _ = await backend?.setTorch(level: nil) }
        }
    }

    /// Asks the hardware for the torch at ``torchLevel``, and records the answer. Does nothing
    /// without a backend.
    ///
    /// The answer is never recorded as a silent "off" (issue #75):
    /// - ``TorchStatus/pending`` (the camera is being reconfigured) keeps the request, which the
    ///   next ``sessionDidStart()`` applies;
    /// - ``TorchStatus/off`` in answer to "on" is recorded as ``TorchStatus/unavailable``, so an
    ///   interface says the light didn't come on;
    /// - if the person turned the light off, or the camera paused, while the hardware answered,
    ///   a light that came on is turned off again.
    func applyTorch() async {
        guard let backend else { return }
        let status = await backend.setTorch(level: torchLevel)
        guard wantsTorch else {
            if case .on = status { _ = await backend.setTorch(level: nil) }
            return
        }
        switch status {
        case .on, .pending:
            torch = status
        case .off, .unavailable:
            torch = .unavailable
            wantsTorch = false
        }
    }
}
