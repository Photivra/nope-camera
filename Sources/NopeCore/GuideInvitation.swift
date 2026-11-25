import Foundation
import Observation

/// The invitation to the how-to-use guide (issue #117; `docs/design/finish-1.0.md`, section 2):
/// a small card on the camera, "How to use nope.", with Open and Dismiss.
///
/// The card shows from the first time the camera is live until the person presses Open or
/// Dismiss, or opens the guide another way (from Settings or About). Either is final: the card
/// doesn't come back on this device. Nothing takes it away on a timer or after a number of
/// launches (owner decision 3), and Factory Defaults doesn't bring it back (decision 4); the
/// guide itself can always be opened again from Settings and About.
///
/// Privacy rule (AGENTS.md, "No network, no analytics"): the one stored value is a Boolean in the
/// app's own settings store on the device. It isn't a count or a date, and it is never sent. It
/// is kept under a key outside ``SharedSettingsStore/keyPrefix``: it is the app's state, not a
/// setting, so presets, Factory Defaults and the Lock Screen camera's snapshot don't carry it.
///
/// When the card may show on the camera is ``showsCard(_:)``: never over the first start, clean
/// view, a countdown or series, or a paused camera, and it gives way to the other cards of the
/// picture's lower edge.
///
/// ```swift
/// let invitation = GuideInvitation(settings: settings)
/// if invitation.showsCard(GuideCardContext(camera: model, showsOtherCard: false)) {
///     // Show the card; Open calls invitation.guideOpened(), Dismiss invitation.dismiss().
/// }
/// ```
@MainActor
@Observable
public final class GuideInvitation {
    /// The store key: whether the invitation was answered, a Boolean.
    nonisolated static let answeredKey = "NopeGuide.invitationAnswered"

    /// Whether the person answered the invitation: pressed Open or Dismiss, or opened the guide
    /// from Settings or About. `false` on a new install and after an update from a build without
    /// the guide, so everyone sees the card once.
    public private(set) var isAnswered: Bool

    /// Where the answer is stored.
    private let defaults: UserDefaults

    /// Loads the invitation's answer.
    ///
    /// - Parameter defaults: The store, normally the settings' store. Tests pass one of their own.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        isAnswered = defaults.bool(forKey: Self.answeredKey)
    }

    /// Loads the invitation's answer from the settings' store.
    ///
    /// - Parameter settings: The person's settings, whose store keeps the answer.
    public convenience init(settings: NopeSettings) {
        self.init(defaults: settings.defaults)
    }

    /// Records that the guide was opened, from the card's Open or from Settings or About: the
    /// card is answered and doesn't show again. Side effect: stores one Boolean on the device.
    public func guideOpened() {
        answer()
    }

    /// Records the card's Dismiss: the card doesn't show again. The guide stays in Settings and
    /// About. Side effect: stores one Boolean on the device.
    public func dismiss() {
        answer()
    }

    /// Whether the card shows on the camera now.
    ///
    /// - Parameter context: What the camera shows.
    /// - Returns: `true` while the invitation is unanswered, the picture is live, the controls are
    ///   shown, nothing runs and no other card of the picture's lower edge is shown.
    public func showsCard(_ context: GuideCardContext) -> Bool {
        !isAnswered && context.isCameraLive && !context.isCleanView && !context.isRunning && !context.showsOtherCard
    }

    /// Stores the answer.
    private func answer() {
        isAnswered = true
        defaults.set(true, forKey: Self.answeredKey)
    }
}

/// What the camera shows, for when the guide's invitation card may show
/// (``GuideInvitation/showsCard(_:)``).
public struct GuideCardContext: Equatable, Sendable {
    /// Whether the picture is live: the camera is ready, its first start has ended, and its
    /// session runs (not interrupted, paused for heat or failed).
    public var isCameraLive: Bool

    /// Whether the camera is in clean view.
    public var isCleanView: Bool

    /// Whether a countdown, burst, interval series, astro run or bracket is going.
    public var isRunning: Bool

    /// Whether another card of the picture's lower edge shows: a drive mode's card, an open dial
    /// or a hint. It takes the invitation's place while it shows.
    public var showsOtherCard: Bool

    /// Creates a context from plain values.
    ///
    /// - Parameters:
    ///   - isCameraLive: Whether the picture is live.
    ///   - isCleanView: Whether the camera is in clean view.
    ///   - isRunning: Whether a countdown or series is going.
    ///   - showsOtherCard: Whether another card shows on the picture's lower edge.
    public init(isCameraLive: Bool, isCleanView: Bool = false, isRunning: Bool = false, showsOtherCard: Bool = false) {
        self.isCameraLive = isCameraLive
        self.isCleanView = isCleanView
        self.isRunning = isRunning
        self.showsOtherCard = showsOtherCard
    }

    /// Reads the context from the camera.
    ///
    /// - Parameters:
    ///   - camera: The camera model.
    ///   - showsOtherCard: Whether the interface shows another card on the picture's lower edge.
    @MainActor
    public init(camera: CameraModel, showsOtherCard: Bool) {
        let isReady = if case .ready = camera.state { true } else { false }
        self.init(
            isCameraLive: isReady && !camera.isFirstStart && camera.sessionStatus == .running,
            isCleanView: camera.isCleanView,
            isRunning: camera.isRunningSeries || camera.bracketProgress != nil,
            showsOtherCard: showsOtherCard)
    }
}
