import NopeUI
import SwiftUI
import UIKit

/// Keeps the iPhone camera layout in portrait and lets sheets rotate (issue #68, "Landscape
/// (iPhone)": the camera layout is fixed; Settings and sheets rotate normally). The iPad rotates
/// in every orientation, and so does any window that is regular in both size classes, such as
/// the unfolded inner display of a foldable iPhone (iPhone Duo), where the system turns the
/// interface with the device whatever the app asks. The size classes come from the window's
/// traits, not from the device model, so the outer display of the same phone stays portrait.
///
/// UIKit asks the app delegate for the window's orientations
/// (`application(_:supportedInterfaceOrientationsFor:)`), which takes the place of the Info.plist
/// list; the Info.plist still lists landscape so a sheet can turn. When a sheet opens or closes,
/// ``setSheetPresented(_:)`` tells UIKit to ask again
/// (`UIViewController.setNeedsUpdateOfSupportedInterfaceOrientations()`, iOS 16), so the sheet
/// turns to match the device, and the camera turns back to portrait when it closes.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Whether a sheet is open over the iPhone camera, so the interface may turn.
    @MainActor private static var allowsLandscape = false

    /// The orientations the window may take: every one on iPad and in a window regular in both
    /// size classes; on iPhone portrait, plus landscape while a sheet is open.
    ///
    /// - Parameters:
    ///   - application: The app.
    ///   - window: The window.
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            guard UIDevice.current.userInterfaceIdiom == .phone, !Self.rotatesFreely(window?.traitCollection) else {
                return .all
            }
            return Self.allowsLandscape ? .allButUpsideDown : .portrait
        }
    }

    /// Whether a window with these traits rotates in every orientation: regular in both size
    /// classes, like an iPad window or the inner display of a foldable iPhone.
    ///
    /// - Parameter traits: The window's traits, or `nil` without a window.
    @MainActor private static func rotatesFreely(_ traits: UITraitCollection?) -> Bool {
        traits?.horizontalSizeClass == .regular && traits?.verticalSizeClass == .regular
    }

    /// Lets the iPhone interface turn while a sheet is open, and returns it to portrait when the
    /// sheet closes.
    ///
    /// - Parameter isPresented: Whether a sheet is open over the camera.
    @MainActor static func setSheetPresented(_ isPresented: Bool) {
        guard allowsLandscape != isPresented else { return }
        allowsLandscape = isPresented
        updateOrientations()
    }

    /// Asks UIKit again for the orientations after the window's size classes change, as when a
    /// foldable iPhone folds or unfolds: the inner display rotates with the device, and the
    /// outer display must return to portrait if the phone was folded while on its side.
    @MainActor static func windowSizeClassesChanged() {
        updateOrientations()
    }

    /// Tells UIKit to ask for the orientations again, and turns a portrait-only window that
    /// isn't in portrait back to portrait.
    @MainActor private static func updateOrientations() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            // An iPad window, and one that rotates freely, keeps the device's orientation.
            if UIDevice.current.userInterfaceIdiom == .phone, !allowsLandscape, !rotatesFreely(scene.traitCollection) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }
}

/// Tells the app delegate when the window's size classes change (``AppDelegate/windowSizeClassesChanged()``),
/// so a foldable iPhone's outer display returns to portrait after folding.
struct FollowsWindowSizeClasses: ViewModifier {
    /// The horizontal size class.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The vertical size class.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// The content, watching its size classes.
    ///
    /// - Parameter content: The content.
    func body(content: Content) -> some View {
        content.onChange(of: [horizontalSizeClass, verticalSizeClass]) {
            AppDelegate.windowSizeClassesChanged()
        }
    }
}

/// Follows which way up the person holds the iPhone, for the camera's upright icons and text
/// (``NopeUI/UprightRotation``). The interface stays in portrait, so the device's orientation is
/// read from `UIDevice` (its accelerometer-based `orientation`), not from the window.
///
/// Face up, face down and unknown keep the last orientation, so laying the phone flat doesn't
/// turn the icons. Upside down counts as portrait, which the iPhone interface doesn't support.
/// On iPad the interface itself rotates, so the rotation stays portrait.
@MainActor
@Observable
final class DeviceOrientation {
    /// Which way up the person holds the device.
    private(set) var rotation = UprightRotation.portrait

    /// The notification observer.
    private var observer: NSObjectProtocol?

    /// Starts following the device's orientation on iPhone.
    init() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        update(UIDevice.current.orientation)
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(UIDevice.current.orientation) }
        }
    }

    /// Applies a new device orientation.
    ///
    /// - Parameter orientation: The device's orientation.
    private func update(_ orientation: UIDeviceOrientation) {
        switch orientation {
        case .portrait, .portraitUpsideDown: rotation = .portrait
        case .landscapeLeft: rotation = .landscapeLeft
        case .landscapeRight: rotation = .landscapeRight
        default: break
        }
    }
}
