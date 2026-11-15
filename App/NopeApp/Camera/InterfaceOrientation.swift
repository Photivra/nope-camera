import NopeUI
import SwiftUI
import UIKit

/// Keeps the iPhone camera layout in portrait and lets sheets rotate (issue #68, "Landscape
/// (iPhone)": the camera layout is fixed; Settings and sheets rotate normally). The iPad rotates
/// in every orientation.
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

    /// The orientations the window may take: every one on iPad; on iPhone portrait, plus
    /// landscape while a sheet is open.
    ///
    /// - Parameters:
    ///   - application: The app.
    ///   - window: The window.
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
            return Self.allowsLandscape ? .allButUpsideDown : .portrait
        }
    }

    /// Lets the iPhone interface turn while a sheet is open, and returns it to portrait when the
    /// sheet closes.
    ///
    /// - Parameter isPresented: Whether a sheet is open over the camera.
    @MainActor static func setSheetPresented(_ isPresented: Bool) {
        guard allowsLandscape != isPresented else { return }
        allowsLandscape = isPresented
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if !isPresented {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
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
