import Foundation
import Observation

/// What a pinch on the viewfinder does (issue #95; docs/design/pinch-lens.md, section 7): the
/// Pinch setting in Settings › Camera, stored in ``NopeSettings/pinch`` and in presets.
///
/// A pinch never enlarges or crops the picture: the app has no digital zoom (issue #1). It only
/// chooses between the device's rear cameras, as the lens buttons do.
public enum PinchAction: String, CaseIterable, Codable, Sendable {
    /// Spread two fingers for the next longer rear lens, pinch for the next wider one. The
    /// default.
    case switchLenses

    /// A pinch does nothing.
    case off
}

/// The step logic of a pinch that switches lenses (docs/design/pinch-lens.md, section 3): which
/// lens a pinch has reached, given how far the fingers have moved apart or together.
///
/// A lens is a separate camera, not a point on a scale, so the steps are equal and don't follow
/// the lenses' magnifications. Spreading past ``firstSpreadStep`` moves one lens longer, and each
/// further factor of ``furtherStep`` one more; pinching past ``firstPinchStep`` moves one lens
/// wider, and each further factor of 1 / ``furtherStep`` one more. Going back over a threshold
/// within the same pinch needs the scale to return ``returnMargin`` inside it, so a hand resting
/// at a threshold doesn't flip between two lenses. The pinch stops at the first and the last rear
/// lens; it never wraps and never reaches the front camera.
///
/// The thresholds are starting values for tuning on devices (AGENTS.md, rule 1;
/// docs/TESTING.md, "Pinch to switch lenses on a device").
///
/// ```swift
/// var pinch = LensPinch(lenses: capabilities.lenses, startingAt: model.selectedLensID)
/// let target = pinch?.update(scale: 1.3)  // the next longer lens
/// ```
public struct LensPinch: Equatable, Sendable {
    /// The scale of the first step toward a longer lens: the fingers a quarter further apart.
    /// A device-tuning value (docs/design/pinch-lens.md, 3.2).
    public static let firstSpreadStep = 1.25

    /// The scale of the first step toward a wider lens: the fingers a fifth closer together.
    /// A device-tuning value (docs/design/pinch-lens.md, 3.2).
    public static let firstPinchStep = 0.80

    /// The further factor for each further step in the same pinch: scale 1.69 is the second
    /// longer lens, 0.59 the second wider one. A device-tuning value
    /// (docs/design/pinch-lens.md, 3.2).
    public static let furtherStep = 1.35

    /// How far, as a fraction of the threshold, the scale must return inside a threshold just
    /// crossed to step back over it: 10%. A device-tuning value (docs/design/pinch-lens.md, 3.2).
    public static let returnMargin = 0.10

    /// A tolerance for comparing scales, so a scale of exactly 0.80 reaches the first wider step
    /// whatever the rounding of the multiplications.
    static let tolerance = 1e-9

    /// The rear lenses in the lens row's order.
    public let lenses: [Lens]

    /// The index in ``lenses`` of the lens the pinch started on.
    public let startIndex: Int

    /// The steps reached from the starting lens: positive toward longer lenses, negative toward
    /// wider ones.
    public private(set) var step = 0

    /// Starts a pinch on a lens, or returns `nil` when a pinch can't switch lenses from it: the
    /// device has fewer than two rear lenses, the lens is the front camera, or no lens is known.
    ///
    /// - Parameters:
    ///   - lenses: The device's lenses in the lens row's order (``DeviceCapabilities/lenses``);
    ///     the front camera is left out.
    ///   - lensID: The lens in use when the fingers land.
    public init?(lenses: [Lens], startingAt lensID: Lens.ID?) {
        let rear = Self.rearLenses(lenses)
        guard rear.count >= 2, let lensID, let index = rear.firstIndex(where: { $0.id == lensID }) else { return nil }
        self.lenses = rear
        startIndex = index
    }

    /// The rear lenses a pinch moves between, in the lens row's order: every lens but the front
    /// camera, lenses without Bayer RAW included (decision 4). A lens without a magnification
    /// keeps its place in the catalog's order.
    ///
    /// - Parameter lenses: The device's lenses in display order.
    /// - Returns: The rear lenses.
    public static func rearLenses(_ lenses: [Lens]) -> [Lens] {
        lenses.filter { $0.kind != .front }
    }

    /// Whether a device offers the pinch at all: it has two or more rear lenses. The Pinch row in
    /// Settings is shown only then (decision 12).
    ///
    /// - Parameter lenses: The device's lenses.
    /// - Returns: `true` with two or more rear lenses.
    public static func isOffered(on lenses: [Lens]) -> Bool {
        rearLenses(lenses).count >= 2
    }

    /// The lens the pinch has reached.
    public var target: Lens {
        lenses[startIndex + step]
    }

    /// The scale at the boundary between step `boundary - 1` and step `boundary`: 1.25, 1.69,
    /// 2.28… for the longer lenses (boundaries 1, 2, 3…) and 0.80, 0.59… for the wider ones
    /// (boundaries 0, −1…).
    ///
    /// - Parameter boundary: The boundary.
    /// - Returns: The scale.
    static func threshold(_ boundary: Int) -> Double {
        boundary >= 1
            ? firstSpreadStep * pow(furtherStep, Double(boundary - 1))
            : firstPinchStep * pow(furtherStep, Double(boundary))
    }

    /// Moves the pinch to the lens a scale reaches, and returns it.
    ///
    /// The scale is the distance between the fingers compared with when they landed, as
    /// `MagnifyGesture` reports it. Moving away from the starting lens crosses a threshold as soon
    /// as the scale reaches it; moving back toward it needs the scale ``returnMargin`` inside the
    /// threshold. At the first and the last lens a further scale changes nothing.
    ///
    /// - Parameter scale: The pinch's scale, 1 when the fingers haven't moved.
    /// - Returns: The lens the pinch has reached.
    @discardableResult
    public mutating func update(scale: Double) -> Lens {
        while startIndex + step + 1 < lenses.count, crossesUp(boundary: step + 1, at: scale) {
            step += 1
        }
        while startIndex + step > 0, crossesDown(boundary: step, at: scale) {
            step -= 1
        }
        return target
    }

    /// Whether a scale moves the pinch up over a boundary, from step `boundary - 1` to `boundary`.
    ///
    /// - Parameters:
    ///   - boundary: The boundary.
    ///   - scale: The pinch's scale.
    private func crossesUp(boundary: Int, at scale: Double) -> Bool {
        let threshold = Self.threshold(boundary)
        // Away from the starting lens (toward longer lenses) at the threshold; back toward it
        // (from a wider lens) only once the scale is the margin inside it.
        return boundary >= 1
            ? scale >= threshold - Self.tolerance
            : scale >= threshold / (1 - Self.returnMargin) - Self.tolerance
    }

    /// Whether a scale moves the pinch down over a boundary, from step `boundary` to
    /// `boundary - 1`.
    ///
    /// - Parameters:
    ///   - boundary: The boundary.
    ///   - scale: The pinch's scale.
    private func crossesDown(boundary: Int, at scale: Double) -> Bool {
        let threshold = Self.threshold(boundary)
        // Away from the starting lens (toward wider lenses) at the threshold; back toward it
        // (from a longer lens) only once the scale is the margin inside it.
        return boundary <= 0
            ? scale <= threshold + Self.tolerance
            : scale <= threshold * (1 - Self.returnMargin) + Self.tolerance
    }
}

/// Sends the lens a pinch settles on to the camera, one switch at a time
/// (docs/design/pinch-lens.md, 3.3).
///
/// Restarting the camera for a lens takes time, so a long pinch doesn't restart it for every lens
/// it passes. The interface calls ``settle(on:)`` when the fingers lift, or when the target hasn't
/// changed for ``settleSeconds``. Only the latest target is sent; a switch already running
/// finishes first, and a target reached meanwhile is sent after it. A target that is already the
/// lens in use is not sent, so a pinch that returns to the lens it started on sends nothing.
///
/// Every switch goes through the camera's one rule for a lens change: the `switchLens` closure
/// sends ``CameraIntent/selectLens(_:)``, which does nothing while ``CameraModel/canChangeLens``
/// is false (issue #96).
@MainActor
@Observable
public final class LensPinchSwitcher {
    /// How long, in seconds, a target must stay the same during a pinch before the camera is
    /// asked to switch to it: 0.25 s. A device-tuning value (docs/design/pinch-lens.md, 3.3).
    public nonisolated static let settleSeconds = 0.25

    /// How long, in seconds, the lens label stays on the picture after the fingers lift: 0.8 s
    /// (docs/design/pinch-lens.md, section 4).
    public nonisolated static let labelSeconds = 0.8

    /// The lens in use, read each time before a switch is sent.
    private let lensInUse: @MainActor () -> Lens.ID?

    /// Asks the camera to switch to a lens and returns when the switch has finished.
    private let switchLens: @MainActor (Lens.ID) async -> Void

    /// The lens waiting to be sent, or `nil`.
    private var pending: Lens.ID?

    /// Whether a switch is running.
    public private(set) var isSwitching = false

    /// Creates a switcher.
    ///
    /// - Parameters:
    ///   - lensInUse: The camera's lens in use (``CameraModel/selectedLensID``).
    ///   - switchLens: Sends ``CameraIntent/selectLens(_:)`` and returns when it has finished.
    public init(
        lensInUse: @escaping @MainActor () -> Lens.ID?, switchLens: @escaping @MainActor (Lens.ID) async -> Void
    ) {
        self.lensInUse = lensInUse
        self.switchLens = switchLens
    }

    /// Creates a switcher for a camera.
    ///
    /// - Parameter model: The camera.
    public convenience init(model: CameraModel) {
        self.init(lensInUse: { model.selectedLensID }, switchLens: { await model.send(.selectLens($0)) })
    }

    /// Asks the camera to switch to the lens a pinch has settled on. If a switch is running, the
    /// lens is sent once it has finished, replacing any lens still waiting. Returns once no switch
    /// is left to send from this call.
    ///
    /// - Parameter lensID: The pinch's target.
    public func settle(on lensID: Lens.ID) async {
        pending = lensID
        guard !isSwitching else { return }
        isSwitching = true
        while let next = pending {
            pending = nil
            if next != lensInUse() { await switchLens(next) }
        }
        isSwitching = false
    }
}

extension CameraModel {
    /// Whether a pinch on the viewfinder switches lenses now (docs/design/pinch-lens.md,
    /// section 5), as far as the camera knows. An interface adds what only it knows: nothing is
    /// open over the picture (the quick menu, a dial, a sheet) and the layout isn't the
    /// scrolling one.
    ///
    /// It is `false`, and a pinch does nothing at all:
    /// - when the Pinch setting is ``PinchAction/off``;
    /// - while the lens can't be changed (``canChangeLens``, issue #96): a photo is taken or
    ///   saved, a countdown, burst, bracket, interval series or astro run is going, or the
    ///   compare view is open;
    /// - while the astro helper is on, even idle (decision 6);
    /// - while an end of the focus bracket's range is being set on the picture
    ///   (``BracketModel/rangeEditing``): its dial is open, and a dial takes the touch (section 5);
    /// - while the camera isn't running: before it is ready, during its first start, and while it
    ///   is paused, interrupted, too hot, failed or sends no picture. A restart for a lens change
    ///   counts as running, so a pinch can go on while the camera switches;
    /// - on the front camera, and on a device with fewer than two rear lenses.
    ///
    /// Night Mode, Manual Controls, clean view, Magnify and a drive mode chosen but idle don't
    /// change it.
    ///
    /// - Parameter setting: The Pinch setting (``NopeSettings/pinch``).
    /// - Returns: `true` when a pinch may switch lenses.
    public func pinchSwitchesLenses(setting: PinchAction) -> Bool {
        guard setting == .switchLenses, canChangeLens, !astro.isOn, bracketing.rangeEditing == nil, isRunningForPinch,
            let capabilities = capabilities
        else {
            return false
        }
        return LensPinch(lenses: capabilities.lenses, startingAt: selectedLensID) != nil
    }

    /// Whether the camera is running, or restarting for a lens change after its first start.
    private var isRunningForPinch: Bool {
        switch sessionStatus {
        case .running: true
        case .starting: !isFirstStart
        case .stopped, .interrupted, .pausedForHeat, .failed, .noPicture: false
        }
    }
}
