import Foundation

/// Why the lens can't be changed now (issue #96; docs/design/lens-while-busy.md).
///
/// Changing the lens restarts the camera. During a photo that would reconfigure the session
/// under it; during a series it would end the series part-way or mix lenses in it. An interface
/// disables its lens controls while ``CameraModel/lensChangeBlocker`` is not `nil`, and may draw
/// the cases differently: a single photo is usually over before a person would notice, so the
/// design draws the controls dimmed for ``takingPhoto`` only if it lasts, and for the others at
/// once.
public enum LensChangeBlocker: Equatable, Sendable {
    /// One photo or one exposure bracket is being taken or saved.
    case takingPhoto

    /// A self-timer countdown, a burst, an interval series or an astro run is in progress,
    /// including the waits between its photos.
    case runningSeries

    /// The compare view is open (issue #55): its photos are taken with the lens in use.
    case comparing
}

extension CameraModel {
    /// Why the lens can't be changed now, or `nil` when it can (``canChangeLens``).
    ///
    /// A series wins over its own photos, so the reason stays ``LensChangeBlocker/runningSeries``
    /// for the whole series, the photos and the waits between them included.
    public var lensChangeBlocker: LensChangeBlocker? {
        if isRunningSeries { return .runningSeries }
        if isTakingPhoto { return .takingPhoto }
        if comparison.isPresented { return .comparing }
        return nil
    }

    /// Whether the lens can be changed now: no photo is being taken or saved, no countdown,
    /// burst, interval series or astro run is in progress, and the compare view isn't open.
    ///
    /// The one rule for every way of changing the lens: ``CameraIntent/selectLens(_:)`` does
    /// nothing while it is false, Siri and Shortcuts refuse a lens change, and presets aren't
    /// applied (``isBusyForPresets``). An interface disables its lens controls while it is false.
    public var canChangeLens: Bool {
        lensChangeBlocker == nil
    }

    /// Whether a countdown, a burst, an interval series or an astro run is in progress.
    var isRunningSeries: Bool {
        drive.isBusy || manual.intervalProgress != nil || astro.isRunning
    }

    /// Whether a photo or an exposure bracket is being taken or saved. A bracket counts from its
    /// request to its last frame's save (``bracketProgress``), in full auto as with Manual
    /// Controls on.
    var isTakingPhoto: Bool {
        captureStatus == .capturing || captureStatus == .saving || bracketProgress != nil
    }
}
