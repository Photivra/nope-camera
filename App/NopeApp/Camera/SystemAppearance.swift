import NopeUI
import SwiftUI
import UIKit

/// Sets the camera window's appearance and gives the camera screen the system's light or dark
/// setting (`EnvironmentValues.windowAppearance` and `systemColorScheme`), so Settings and the
/// other screens that aren't the camera follow the system while the camera stays dark.
///
/// SwiftUI applies a window's `preferredColorScheme(_:)` to the whole window scene, and then
/// nothing in the scene shows the system's setting any more (`UIScreen` doesn't carry it
/// either). So the app sets the appearance itself:
/// - the window is dark while the camera shows (`overrideUserInterfaceStyle`), so the camera
///   stays dark under any sheet;
/// - the window scene is dark too (`traitOverrides`) while no screen that follows the system is
///   open, so the camera's own sheets are in a dark scene, as with `preferredColorScheme(_:)`
///   (the accessibility audit measured their navigation titles against a light background in a
///   light scene);
/// - while Settings or Presets is open, or on first run, the scene isn't overridden: it shows
///   the system's setting, which this reads and follows as it changes.
struct ProvidesSystemAppearance: ViewModifier {
    /// The system's setting, once read.
    @State private var systemScheme: ColorScheme?

    /// The appearance the camera screen asked for: dark, or `nil` to follow the system. Dark
    /// until it asks, as the camera starts dark.
    @State private var cameraScheme: ColorScheme? = .dark

    /// How many sheets or popovers that follow the system are open.
    @State private var systemScreens = 0

    /// The bridging view, to read the system's setting at once when such a screen opens.
    @State private var bridge = BridgeReference()

    /// The content, with the system's appearance and the window action in its environment.
    ///
    /// - Parameter content: The content.
    func body(content: Content) -> some View {
        content
            .environment(\.systemColorScheme, systemScheme)
            .environment(
                \.windowAppearance,
                WindowAppearanceAction { request in
                    switch request {
                    case .camera(let scheme):
                        cameraScheme = scheme
                        return nil
                    case .showsSystemScreen(let shown):
                        systemScreens = max(0, systemScreens + (shown ? 1 : -1))
                        guard shown, let scheme = bridge.view?.readSystemScheme() else { return nil }
                        // The scene showed the camera's dark until now, so the value read before
                        // may be stale: the screen opens with the current one.
                        systemScheme = scheme
                        return scheme
                    }
                }
            )
            .background {
                WindowAppearanceBridge(
                    windowScheme: cameraScheme,
                    sceneScheme: systemScreens > 0 ? nil : cameraScheme,
                    reference: bridge
                ) { systemScheme = $0 }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
    }
}

/// Holds the bridging view, so the action can read the system's setting through it.
@MainActor
private final class BridgeReference {
    /// The view, once made.
    weak var view: WindowAppearanceView?
}

/// A zero-size view that sets its window's and window scene's appearance and reports the
/// scene's.
private struct WindowAppearanceBridge: UIViewRepresentable {
    /// The window's appearance: a scheme, or `nil` to follow the system.
    let windowScheme: ColorScheme?

    /// The window scene's appearance: a scheme, or `nil` to follow the system.
    let sceneScheme: ColorScheme?

    /// Where the view is kept for the action.
    let reference: BridgeReference

    /// Called with the scene's appearance when it is first known and whenever it changes.
    let onSystemChange: @MainActor (ColorScheme) -> Void

    /// Makes the bridging view.
    ///
    /// - Parameter context: The representable's context.
    /// - Returns: The view.
    func makeUIView(context: Context) -> WindowAppearanceView {
        let view = WindowAppearanceView(onSystemChange: onSystemChange)
        reference.view = view
        return view
    }

    /// Updates the window's appearance and the handler.
    ///
    /// - Parameters:
    ///   - view: The view.
    ///   - context: The representable's context.
    func updateUIView(_ view: WindowAppearanceView, context: Context) {
        view.onSystemChange = onSystemChange
        view.windowStyle = Self.style(for: windowScheme)
        view.sceneStyle = Self.style(for: sceneScheme)
    }

    /// The interface style for a scheme.
    ///
    /// - Parameter scheme: A scheme, or `nil` to follow the system.
    /// - Returns: The matching style; unspecified for `nil`.
    static func style(for scheme: ColorScheme?) -> UIUserInterfaceStyle {
        switch scheme {
        case .dark: .dark
        case .light: .light
        default: .unspecified
        }
    }
}

/// Sets its window's and window scene's interface styles, and follows the scene's style while
/// the scene isn't overridden.
///
/// Nothing here changes SwiftUI state or UIKit traits while SwiftUI updates its views: the new
/// styles are applied, and the scene's style reported, on the next turn of the main actor
/// (`scheduleApply()`, `report(_:)`). Applying them inside `updateUIView` set a trait override
/// whose change was reported at once into SwiftUI state, and SwiftUI warned "Modifying state
/// during view update" on every Settings screen in the UI tests.
final class WindowAppearanceView: UIView {
    /// Called with the scene's appearance when it changes.
    var onSystemChange: @MainActor (ColorScheme) -> Void

    /// The style for the window: dark for the camera, unspecified to follow the system.
    var windowStyle = UIUserInterfaceStyle.unspecified {
        didSet { if windowStyle != oldValue { scheduleApply() } }
    }

    /// The style for the window scene: dark while only the camera is shown, unspecified to show
    /// the system's.
    var sceneStyle = UIUserInterfaceStyle.unspecified {
        didSet { if sceneStyle != oldValue { scheduleApply() } }
    }

    /// The scene whose changes are followed, and the registration that follows them.
    private var observed: (scene: UIWindowScene, registration: any UITraitChangeRegistration)?

    /// Whether the styles are to be applied on the next turn of the main actor.
    private var isApplyScheduled = false

    /// The appearance last reported, so an unchanged one isn't reported again.
    private var reported: ColorScheme?

    /// Creates the view.
    ///
    /// - Parameter onSystemChange: Called with the scene's appearance.
    init(onSystemChange: @escaping @MainActor (ColorScheme) -> Void) {
        self.onSystemChange = onSystemChange
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    /// Not used: the view is made in code.
    ///
    /// - Parameter coder: Unused.
    required init?(coder: NSCoder) {
        nil
    }

    /// Follows the new window's scene instead of the old one, and sets its styles.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        let scene = window?.windowScene
        if scene !== observed?.scene {
            if let observed { observed.scene.unregisterForTraitChanges(observed.registration) }
            observed = nil
            if let scene {
                report(scene.traitCollection)
                let registration = scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                    [weak self] (scene: UIWindowScene, _: UITraitCollection) in
                    self?.report(scene.traitCollection)
                }
                observed = (scene, registration)
            }
        }
        scheduleApply()
    }

    /// Shows the system's setting in the window scene at once, and returns it: the scene's
    /// override is removed now rather than on the next turn, so a screen that follows the
    /// system opens with the current setting. Called from the camera screen's request, not
    /// while SwiftUI updates its views.
    ///
    /// - Returns: The system's setting, or `nil` outside a window scene.
    func readSystemScheme() -> ColorScheme? {
        sceneStyle = .unspecified
        applyStyles()
        guard let scene = window?.windowScene else { return nil }
        let scheme: ColorScheme = scene.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        reported = scheme
        return scheme
    }

    /// Applies the styles on the next turn of the main actor, once however often it is asked.
    private func scheduleApply() {
        guard !isApplyScheduled else { return }
        isApplyScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            isApplyScheduled = false
            applyStyles()
        }
    }

    /// Sets the window's interface style and the scene's override, where they differ.
    private func applyStyles() {
        guard let window else { return }
        if window.overrideUserInterfaceStyle != windowStyle {
            window.overrideUserInterfaceStyle = windowStyle
        }
        guard let scene = window.windowScene else { return }
        let isOverridden = scene.traitOverrides.contains(UITraitUserInterfaceStyle.self)
        if sceneStyle == .unspecified {
            if isOverridden { scene.traitOverrides.remove(UITraitUserInterfaceStyle.self) }
        } else if !isOverridden || scene.traitOverrides.userInterfaceStyle != sceneStyle {
            scene.traitOverrides.userInterfaceStyle = sceneStyle
        }
    }

    /// Reports the appearance in the scene's traits while they show the system's setting (not
    /// while the scene's style is overridden), on the next turn of the main actor and only when
    /// it changed.
    ///
    /// - Parameter traits: The scene's traits.
    private func report(_ traits: UITraitCollection) {
        guard window?.windowScene?.traitOverrides.contains(UITraitUserInterfaceStyle.self) != true else { return }
        let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
        guard scheme != reported else { return }
        reported = scheme
        Task { @MainActor [weak self] in self?.onSystemChange(scheme) }
    }
}
