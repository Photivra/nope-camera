import Foundation

/// The camera's status for the Apple Watch app (issue #63).
extension CameraModel {
    /// What the camera is doing, as the watch shows it. It reads only observable state, so a
    /// ``WatchCommandServer`` can follow it without polling.
    ///
    /// A camera that is still starting counts as ``WatchCameraProblem/notRunning``: a photo is
    /// taken for the watch only when the camera is already running, so nothing is taken later by
    /// surprise (issue #63, "Done when"). Busy follows the same rule as a Siri request: a photo
    /// being taken or saved, or a countdown, burst, interval series or astro
    /// run.
    public var watchStatus: WatchStatus {
        switch state {
        case .needsPermission: return .unavailable(.needsPermission)
        case .permissionDenied: return .unavailable(.permissionDenied)
        case .unavailable: return .unavailable(.noCamera)
        case .starting: return .unavailable(.notRunning)
        case .ready: break
        }
        if let seconds = drive.countdown.remainingSeconds { return .countingDown(secondsLeft: seconds) }
        if isTakingPhoto || isRunningSeries { return .busy }
        return canCapture ? .ready : .unavailable(.notRunning)
    }
}

extension WatchCameraProblem {
    /// The watch's problem for a Siri and Shortcuts reason.
    ///
    /// - Parameter reason: Why the camera couldn't take a photo for a request.
    init(_ reason: CameraUnavailability) {
        switch reason {
        case .needsPermission: self = .needsPermission
        case .permissionDenied: self = .permissionDenied
        case .noCamera: self = .noCamera
        case .notRunning: self = .notRunning
        }
    }
}

extension SignatureStatus.UnsignedReason {
    /// Why the photos a capture saved aren't all signed, for the watch (``PhoneUpdate``).
    ///
    /// When the photos are unsigned for different reasons, a reason other than
    /// ``turnedOff`` wins: a photo that couldn't be signed must not read as the person's choice.
    ///
    /// - Parameter status: The camera's capture status after the photos were saved.
    /// - Returns: `nil` when every photo is signed or the status holds no saved photo.
    init?(photosOf status: CaptureStatus) {
        let photos: [SavedPhoto]
        switch status {
        case .saved(let photo): photos = [photo]
        case .savedBracket(let saved), .savedBurst(let saved): photos = saved
        case .idle, .capturing, .saving, .failed: return nil
        }
        let reasons = photos.compactMap { photo -> Self? in
            guard case .unsigned(let reason) = photo.signature else { return nil }
            return reason
        }
        guard let reason = reasons.first(where: { $0 != .turnedOff }) ?? reasons.first else { return nil }
        self = reason
    }
}

extension WatchResult {
    /// Whether the result reports saved photos that aren't all signed, so a ``PhoneUpdate``
    /// carries the reason.
    var includesUnsignedPhotos: Bool {
        self == .saved(isSigned: false) || self == .savedSeveral(allSigned: false)
    }

    /// The watch's result for how a photo request through the ``ShortcutInbox`` ended.
    ///
    /// The watch asks only for a photo, so the outcomes of other requests (a lens, the light, an
    /// interval series, a bracket, the focus range, a photo size, a preset) can't happen; they would be
    /// reported as not saved.
    ///
    /// - Parameter outcome: How the request ended.
    init(_ outcome: ShortcutOutcome) {
        switch outcome {
        case .saved(let isSigned): self = .saved(isSigned: isSigned)
        case .savedSeveral(let allSigned): self = .savedSeveral(allSigned: allSigned)
        case .notSaved, .lensUnavailable, .lensSelected, .lightOn, .lightOff, .noLight, .lightUnavailable,
            .intervalStarted, .intervalBlockedByAstro, .intervalStopped, .noIntervalRunning, .bracketUnavailable,
            .focusRangeSet,
            .focusRangeUnavailable, .photoSizeSet, .noPhotoSizeChoice, .presetApplied, .presetUnavailable:
            self = .notSaved
        case .cancelled: self = .cancelled
        case .busy, .busyWithEarlierRequest, .lensBusy: self = .busy
        case .cameraUnavailable(let reason): self = .notTaken(WatchCameraProblem(reason))
        }
    }

    /// The result of asking for a photo while the camera isn't ready, or `nil` when it is.
    ///
    /// - Parameter status: The camera's status when the request arrived.
    init?(refusing status: WatchStatus) {
        switch status {
        case .ready: return nil
        case .countingDown, .busy: self = .busy
        case .unavailable(let problem): self = .notTaken(problem)
        }
    }
}
