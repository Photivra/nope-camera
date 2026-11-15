import Foundation

/// Requests from Siri and Shortcuts (issue #62), performed with the same intents as the camera
/// screen's own controls.
extension CameraModel {
    /// Performs each request from the inbox in turn, until the calling task is cancelled. Run it
    /// for as long as the camera screen is shown, for example in a SwiftUI `.task`.
    ///
    /// Side effects: as ``CameraIntent/capture`` and ``CameraIntent/selectLens(_:)``; a request
    /// may switch the lens, start the self-timer, take a photo and add it to Photos.
    ///
    /// - Parameter inbox: Where the app's App Intents leave their requests.
    public func serveShortcuts(from inbox: ShortcutInbox) async {
        while let pending = await inbox.next() {
            pending.finish(await perform(pending.request, inbox: inbox))
        }
    }

    /// Performs one request.
    ///
    /// - Parameters:
    ///   - request: What was asked for.
    ///   - inbox: The inbox, for its waits and timeouts.
    /// - Returns: How it ended.
    func perform(_ request: ShortcutRequest, inbox: ShortcutInbox) async -> ShortcutOutcome {
        switch request {
        case .takePhoto(let photo): await takePhoto(photo, inbox: inbox)
        }
    }

    /// Takes one photo for a request: waits for the camera, switches the lens if asked, then
    /// takes the photo at once or after the self-timer (``DriveIntent/startTimer(seconds:)``).
    ///
    /// Without a delay it takes a single photo whatever the drive mode, because the request
    /// asked for one photo; a bracket that is on in the manual controls still applies, as it does
    /// to the shutter.
    ///
    /// - Parameters:
    ///   - photo: The request's delay and lens.
    ///   - inbox: The inbox, for its waits and timeouts.
    /// - Returns: How it ended.
    private func takePhoto(_ photo: PhotoShortcut, inbox: ShortcutInbox) async -> ShortcutOutcome {
        if let problem = await cameraProblem(inbox: inbox) { return .cameraUnavailable(problem) }
        if let kind = photo.lensKind, selectedLens?.kind != kind {
            guard let lens = capabilities?.lenses.first(where: { $0.kind == kind }) else { return .lensUnavailable }
            await send(.selectLens(lens.id))
            if let problem = await cameraProblem(inbox: inbox) { return .cameraUnavailable(problem) }
        }
        guard canCapture, !drive.isBusy else { return .busy }
        let before = captureStatus
        if photo.delaySeconds == 0 {
            await capture()
        } else {
            await send(.drive(.startTimer(seconds: photo.delaySeconds)))
            _ = await inbox.wait { !self.drive.countdown.isRunning }
            guard isTakingPhoto || captureStatus != before else {
                return sessionStatus.canCapture ? .cancelled : .cameraUnavailable(.notRunning)
            }
            _ = await inbox.wait { !self.isTakingPhoto }
        }
        return outcome(of: captureStatus)
    }

    /// Whether a photo is being taken or saved.
    private var isTakingPhoto: Bool {
        captureStatus == .capturing || captureStatus == .saving
    }

    /// Waits for the camera to finish starting, at most ``ShortcutInbox/startTimeoutSeconds``,
    /// then says why it can't take a photo, if it can't.
    ///
    /// - Parameter inbox: The inbox, for its wait and timeout.
    /// - Returns: Why the camera can't take a photo, or `nil` when it can.
    private func cameraProblem(inbox: ShortcutInbox) async -> CameraUnavailability? {
        _ = await inbox.wait(timeoutSeconds: ShortcutInbox.startTimeoutSeconds) { !self.isStartingCamera }
        switch state {
        case .needsPermission: return .needsPermission
        case .permissionDenied: return .permissionDenied
        case .unavailable: return .noCamera
        case .starting: return .notRunning
        case .ready: return sessionStatus.canCapture ? nil : .notRunning
        }
    }

    /// Whether the camera is still checking access or starting a session.
    private var isStartingCamera: Bool {
        switch state {
        case .starting: true
        case .ready: sessionStatus == .stopped || sessionStatus == .starting
        default: false
        }
    }

    /// The outcome a capture status reports.
    ///
    /// - Parameter status: The status after the photo.
    /// - Returns: The outcome.
    func outcome(of status: CaptureStatus) -> ShortcutOutcome {
        switch status {
        case .saved(let photo): .saved(isSigned: photo.signature == .signed)
        case .savedBracket(let photos), .savedBurst(let photos):
            .savedSeveral(allSigned: photos.allSatisfy { $0.signature == .signed })
        case .failed(let error): .notSaved(error)
        case .idle, .capturing, .saving: .notSaved(.notRunning)
        }
    }
}
