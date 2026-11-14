import Foundation
import Observation

/// The screen's brightness and idle timer. The app implements it with UIKit
/// (`UIScreen.brightness`, `UIApplication.isIdleTimerDisabled`); tests pass a fake.
@MainActor
public protocol ScreenControlling: AnyObject {
    /// The screen's brightness, from 0 to 1.
    var brightness: Double { get set }

    /// Whether the system's idle timer is off, so the screen doesn't lock.
    var isIdleTimerDisabled: Bool { get set }
}

/// Keeps the screen awake and dimmed while an interval series runs, and puts both back when it
/// ends (issue #48).
///
/// During a series the screen mustn't lock, or the camera stops and the series with it; dimming
/// saves battery over a long series (AGENTS.md, "Battery"). This is the only place nope. turns
/// the idle timer off, and it is turned on again whenever the series ends or is stopped, the
/// camera screen goes away, or the app leaves the foreground.
///
/// An interface calls ``update(isSeriesRunning:isInForeground:)`` whenever either value changes,
/// shows a "Brighten Screen" control over the whole screen while ``isDimmed``, and announces the
/// change to VoiceOver. ``brighten()`` restores the brightness while the series continues.
@MainActor
@Observable
public final class SeriesScreenKeeper {
    /// The brightness during a series, from 0 to 1. A screen already darker isn't changed. An
    /// assumption to be checked on a device: dark enough to save power, bright enough to see the
    /// progress.
    public static let dimmedBrightness = 0.1

    /// Whether the screen is dimmed now.
    public private(set) var isDimmed = false

    /// Whether the idle timer is off now.
    public private(set) var isKeepingAwake = false

    /// The brightness to restore.
    private var brightnessBeforeDimming = 1.0

    /// The screen.
    private let screen: any ScreenControlling

    /// Creates the keeper. It changes nothing until a series runs.
    ///
    /// - Parameter screen: The screen.
    public init(screen: any ScreenControlling) {
        self.screen = screen
    }

    /// Keeps the screen awake and dims it when a series runs in the foreground, and puts both
    /// back otherwise.
    ///
    /// - Parameters:
    ///   - isSeriesRunning: Whether an interval series runs on the camera screen.
    ///   - isInForeground: Whether the app is in the foreground.
    public func update(isSeriesRunning: Bool, isInForeground: Bool) {
        guard isSeriesRunning && isInForeground else {
            restore()
            return
        }
        guard !isKeepingAwake else { return }
        isKeepingAwake = true
        screen.isIdleTimerDisabled = true
        brightnessBeforeDimming = screen.brightness
        screen.brightness = min(brightnessBeforeDimming, Self.dimmedBrightness)
        isDimmed = true
    }

    /// Restores the brightness while the series continues; the screen still doesn't lock.
    public func brighten() {
        guard isDimmed else { return }
        screen.brightness = brightnessBeforeDimming
        isDimmed = false
    }

    /// Puts the brightness and the idle timer back.
    private func restore() {
        brighten()
        guard isKeepingAwake else { return }
        screen.isIdleTimerDisabled = false
        isKeepingAwake = false
    }
}
