import Foundation

/// A request an interface sends to ``CameraModel``.
///
/// Intents are the only way an interface changes the camera. They carry no business rules: the
/// model decides what each one means.
public enum CameraIntent: Equatable, Sendable {
    /// Check permission and capabilities, then start the camera with the default lens. Send it
    /// once when the camera screen appears.
    case start

    /// Ask the person for camera access. Send it only from ``CameraState/needsPermission``,
    /// in response to a button the person pressed. When access is allowed, the camera starts.
    case requestPermission

    /// Switch to another lens. Send it when the person picks a lens.
    ///
    /// - Parameter id: The ``Lens/id`` of a lens in the ready state's capabilities. An unknown
    ///   identifier, or the lens already selected, is ignored.
    case selectLens(Lens.ID)

    /// Take one photo with the selected lens, in the format the model chose. Send it from the
    /// shutter button, the volume buttons or the Camera Control. Ignored while the camera isn't
    /// running or a photo is already being taken.
    ///
    /// The ``DriveModel/mode`` applies: a timer mode starts the countdown and burst mode starts
    /// a burst. While a countdown or burst runs, it stops it instead.
    case capture

    /// Change a manual or pro control: see ``ManualControlIntent``. Ignored while manual
    /// controls are off, except ``ManualControlIntent/setEnabled(_:)``.
    case manual(ManualControlIntent)

    /// Turn clean view on or off. Clean view hides every control that isn't essential, leaving
    /// the viewfinder and the shutter; it never changes a setting.
    case setCleanView(Bool)

    /// Change the drive mode, start or cancel the self-timer, stop a burst, or report a hardware
    /// shutter button: see ``DriveIntent``.
    case drive(DriveIntent)

    /// Use an aid that works in full auto too: tap to focus and expose, the focus and exposure
    /// lock, exposure compensation, Close-Up, the fast shutter rule and the focus magnifier. See
    /// ``AutoControlIntent``.
    case auto(AutoControlIntent)

    /// Change the flash or the torch: see ``LightIntent``. Turning the torch on is ignored while
    /// the astro helper is on.
    case light(LightIntent)

    /// Turn the astro helper on or off, choose its frames, or stop a run: see ``AstroIntent``.
    case astro(AstroIntent)

    /// Turn Bracket on or off, choose its type, set up or stop a focus bracket: see
    /// ``BracketIntent``.
    case bracket(BracketIntent)

    /// Turn the comparison shot on or off, or close the compare view: see ``ComparisonIntent``.
    case comparison(ComparisonIntent)

    /// Use the person's photo size for each lens (``NopeSettings/photoSizes``, issue #57). Send
    /// it when the camera screen appears and whenever the choice changes. When the selected
    /// lens's size changes, the camera is reconfigured; a size a lens doesn't offer
    /// (``Lens/photoSizeChoices``) is ignored.
    ///
    /// - Parameter sizes: The chosen size for each lens.
    case setPhotoSizes([Lens.ID: PhotoDimensions])

    /// The app came back to the foreground (`true`) or went to the background (`false`). Send it
    /// whenever the scene phase changes to or from the background (issue #64).
    ///
    /// Leaving closes the Last Photo viewer and releases the previews in
    /// ``CameraModel/sessionPhotos`` (docs/PRIVACY.md), and cancels the self-timer, because the camera stops and can't take its photo. With
    /// the astro helper on, leaving pauses its frames instead (``AstroModel/isPaused``), or, during
    /// its start delay, starts the run paused; coming back with the camera running counts the
    /// start delay down again and continues the run.
    ///
    /// - Parameter isInForeground: Whether the app is in the foreground now.
    case setInForeground(Bool)

    /// Release every preview in ``CameraModel/sessionPhotos`` now, keeping the photos' records.
    /// Send it when the system says memory is low (`UIApplication.didReceiveMemoryWarningNotification`).
    /// Leaving the foreground releases them too, without this intent.
    case releasePhotoPreviews

    /// The Last Photo viewer opened (`true`) or closed (`false`): ``CameraModel/isViewerOpen``.
    /// Send it when the viewer is shown and when it is dismissed. While it is open, a hardware
    /// shutter press closes it and takes no photo (docs/design/BUILD-SPEC.md, 3.14, decision V1).
    /// The interface's Take Photo command (the Space key) does the same by sending
    /// `setViewerOpen(false)` instead of ``capture`` while the viewer is open; ``capture`` itself
    /// still takes a photo, as Siri, Shortcuts and the Apple Watch app do.
    ///
    /// - Parameter isOpen: Whether the viewer is open now.
    case setViewerOpen(Bool)
}

extension CameraIntent {
    /// Whether the intent is something the person did, by any means (a touch, VoiceOver, Voice
    /// Control, a keyboard, Siri, a shortcut, the Apple Watch), which Keep Screen On counts as
    /// activity (``CameraModel/activityCount``). The camera's own lifecycle (starting, the
    /// permission, the foreground, the photo sizes, releasing previews) isn't.
    public var isActivity: Bool {
        switch self {
        case .start, .requestPermission, .setPhotoSizes, .setInForeground, .releasePhotoPreviews: false
        case .selectLens, .capture, .manual, .setCleanView, .drive, .auto, .light, .astro, .comparison, .setViewerOpen:
            true
        }
    }
}
