import NopeCore
import SwiftUI

/// Which appearance a screen uses: the camera's dark appearance, or the person's light or dark
/// setting.
///
/// The camera screen and its own sheets (the format details, What's in This Photo, Compare, the
/// astro and interval settings, Pro Tools) are always dark: a camera is used in every light, and
/// a dark frame doesn't change how a scene looks. Settings and the other screens that aren't the
/// camera (first run, camera access declined, no camera, Presets, Honesty, About and Licenses)
/// follow the system's light or dark setting. Night mode is red on black everywhere: its style
/// is drawn on the dark appearance.
enum ScreenAppearance: Equatable {
    /// Always dark: the camera screen and its own sheets.
    case camera

    /// The system's light or dark setting: Settings and the screens that aren't the camera.
    case system

    /// The appearance of the camera screen's content in a camera state: the ready camera and the
    /// brief starting message are the camera; first run, camera access declined and no camera
    /// aren't.
    ///
    /// - Parameter state: The camera's state.
    /// - Returns: The appearance for that state.
    static func of(_ state: CameraState) -> ScreenAppearance {
        switch state {
        case .starting, .ready: .camera
        case .needsPermission, .permissionDenied, .unavailable: .system
        }
    }

    /// The color scheme to ask for.
    ///
    /// The camera screen asks its window for the dark appearance, and a sheet presented from it
    /// inherits that unless it asks for a scheme of its own; so a screen that follows the system
    /// asks for the system's scheme by name.
    ///
    /// - Parameters:
    ///   - isNightMode: Whether night mode is on: always dark.
    ///   - system: The system's light or dark setting
    ///     (``SwiftUICore/EnvironmentValues/systemColorScheme``), or `nil` when it isn't known.
    /// - Returns: `ColorScheme.dark` for the camera or in night mode, otherwise the
    ///   system's scheme, or `nil` (no preference) when that isn't known.
    func colorScheme(isNightMode: Bool, system: ColorScheme?) -> ColorScheme? {
        if isNightMode { return .dark }
        switch self {
        case .camera: return .dark
        case .system: return system
        }
    }
}

/// Asks the nearest presentation (a sheet or a popover) for a screen's appearance, and tells the
/// app while it shows a screen that follows the system
/// (``WindowAppearanceRequest/showsSystemScreen(_:)``).
///
/// A sheet follows changes of the system's setting while it is open. A popover (Settings on
/// iPad) keeps the setting it opened with until it closes: when the scheme changed under an
/// open popover, its glass stayed half in the old appearance, a mid gray behind white text.
struct ScreenAppearanceModifier: ViewModifier {
    /// The screen's appearance.
    let appearance: ScreenAppearance

    /// Whether night mode is on.
    let isNightMode: Bool

    /// The system's light or dark setting, from the app.
    @Environment(\.systemColorScheme) private var systemColorScheme

    /// Sets the window's appearance, from the app, or `nil`.
    @Environment(\.windowAppearance) private var windowAppearance

    /// Whether the screen is presented in a popover.
    @Environment(\.isPresentedInPopover) private var isInPopover

    /// Whether the app was last told that this screen follows the system.
    @State private var reportsSystem = false

    /// The system's setting when the popover opened, kept while it is open.
    @State private var openedWith: ColorScheme?

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - appearance: The screen's appearance.
    ///   - isNightMode: Whether night mode is on.
    init(appearance: ScreenAppearance, isNightMode: Bool) {
        self.appearance = appearance
        self.isNightMode = isNightMode
    }

    /// Whether the screen follows the system now: not in night mode, which is always dark.
    private var followsSystem: Bool {
        appearance == .system && !isNightMode
    }

    /// The system's setting the screen shows: the one it opened with in a popover.
    private var shownSystemScheme: ColorScheme? {
        isInPopover ? openedWith ?? systemColorScheme : systemColorScheme
    }

    /// The content, with its color scheme preference.
    ///
    /// - Parameter content: The content.
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance.colorScheme(isNightMode: isNightMode, system: shownSystemScheme))
            .onAppear { report(followsSystem) }
            .onChange(of: followsSystem) { _, follows in report(follows) }
            .onDisappear { report(false) }
    }

    /// Tells the app when the screen starts or stops following the system, and keeps the
    /// setting the app reads when it starts.
    ///
    /// - Parameter follows: Whether it follows the system.
    private func report(_ follows: Bool) {
        guard follows != reportsSystem else { return }
        reportsSystem = follows
        let current = windowAppearance?(.showsSystemScreen(follows))
        if follows, openedWith == nil { openedWith = current ?? systemColorScheme }
    }
}

extension EnvironmentValues {
    /// Whether the view is presented in a popover (Settings and the format details on iPad), set
    /// by ``AdaptivePresentation``.
    @Entry var isPresentedInPopover = false
}

/// Gives the window a screen's appearance: through the app's
/// ``SwiftUICore/EnvironmentValues/windowAppearance`` when it sets one, otherwise with
/// `preferredColorScheme(_:)`.
///
/// SwiftUI applies a window's `preferredColorScheme(_:)` to the whole window scene, which then
/// no longer shows the system's own setting; the app sets the appearance itself so it can read
/// that setting for Settings (``SwiftUICore/EnvironmentValues/systemColorScheme``).
struct WindowAppearanceModifier: ViewModifier {
    /// The screen's appearance.
    let appearance: ScreenAppearance

    /// Whether night mode is on.
    let isNightMode: Bool

    /// Sets the window's appearance, from the app, or `nil`.
    @Environment(\.windowAppearance) private var windowAppearance

    /// Creates the modifier.
    ///
    /// - Parameters:
    ///   - appearance: The screen's appearance.
    ///   - isNightMode: Whether night mode is on.
    init(appearance: ScreenAppearance, isNightMode: Bool) {
        self.appearance = appearance
        self.isNightMode = isNightMode
    }

    /// The content, with the window's appearance set.
    ///
    /// - Parameter content: The content.
    func body(content: Content) -> some View {
        // The window follows the system by itself: no scheme is named for it.
        let scheme = appearance.colorScheme(isNightMode: isNightMode, system: nil)
        if let windowAppearance {
            content.onChange(of: scheme, initial: true) { _, scheme in windowAppearance(.camera(scheme)) }
        } else {
            content.preferredColorScheme(scheme)
        }
    }
}

/// What the camera screen asks of the app's window through ``WindowAppearanceAction``.
public enum WindowAppearanceRequest: Equatable, Sendable {
    /// The camera screen's own appearance: `ColorScheme.dark` for the camera and in night mode,
    /// or `nil` to follow the system (first run, camera access declined, no camera).
    case camera(ColorScheme?)

    /// A sheet or popover that follows the system's light or dark setting (Settings, Presets)
    /// opened (`true`) or closed (`false`). While one is open, the window scene shows the
    /// system's setting, so the app can read and follow it; otherwise the whole scene is dark
    /// with the camera, so the camera's own sheets match the scene they are in.
    case showsSystemScreen(Bool)
}

/// Sets the appearance of the window the camera screen is in. Call it like a function with a
/// ``WindowAppearanceRequest``.
public struct WindowAppearanceAction: Sendable {
    /// Handles a request, and returns the system's setting when it reads it.
    private let handler: @MainActor @Sendable (WindowAppearanceRequest) -> ColorScheme?

    /// Creates an action.
    ///
    /// - Parameter handler: Handles a request, on the main actor. For
    ///   ``WindowAppearanceRequest/showsSystemScreen(_:)`` with `true` it returns the system's
    ///   light or dark setting, read as the screen opens; otherwise `nil`.
    public init(_ handler: @escaping @MainActor @Sendable (WindowAppearanceRequest) -> ColorScheme?) {
        self.handler = handler
    }

    /// Handles a request.
    ///
    /// - Parameter request: The request.
    /// - Returns: The system's light or dark setting when the request read it, otherwise `nil`.
    @discardableResult
    @MainActor public func callAsFunction(_ request: WindowAppearanceRequest) -> ColorScheme? {
        handler(request)
    }
}

extension View {
    /// Asks the nearest sheet or popover for a screen's appearance: dark for the camera, the
    /// system's light or dark setting for other screens, and dark in night mode.
    ///
    /// - Parameters:
    ///   - appearance: The screen's appearance.
    ///   - isNightMode: Whether night mode is on.
    func screenAppearance(_ appearance: ScreenAppearance, isNightMode: Bool) -> some View {
        modifier(ScreenAppearanceModifier(appearance: appearance, isNightMode: isNightMode))
    }

    /// Gives the window a screen's appearance: dark for the camera and in night mode, otherwise
    /// the system's.
    ///
    /// - Parameters:
    ///   - appearance: The screen's appearance.
    ///   - isNightMode: Whether night mode is on.
    func windowAppearance(_ appearance: ScreenAppearance, isNightMode: Bool) -> some View {
        modifier(WindowAppearanceModifier(appearance: appearance, isNightMode: isNightMode))
    }
}
