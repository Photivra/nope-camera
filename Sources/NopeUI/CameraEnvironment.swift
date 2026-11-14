import SwiftUI

/// Which way up the person holds an iPhone whose camera layout stays in portrait, so icons and
/// text blocks can turn to read upright (issue #68, "Landscape (iPhone)").
///
/// The app target sets it from the device's orientation with ``SwiftUICore/EnvironmentValues/cameraUprightRotation``.
/// On iPad the interface itself rotates, so the app leaves it at ``portrait``.
public enum UprightRotation: Equatable, Sendable {
    /// Upright in portrait: nothing turns.
    case portrait

    /// The device is turned so its top points left (`UIDeviceOrientation.landscapeLeft`):
    /// content turns 90 degrees clockwise.
    case landscapeLeft

    /// The device is turned so its top points right (`UIDeviceOrientation.landscapeRight`):
    /// content turns 90 degrees counterclockwise.
    case landscapeRight

    /// The angle that turns content upright for the person.
    var angle: Angle {
        switch self {
        case .portrait: .zero
        case .landscapeLeft: .degrees(90)
        case .landscapeRight: .degrees(-90)
        }
    }

    /// Whether the device is on its side, so content turns a quarter turn.
    var isSideways: Bool { self != .portrait }
}

extension EnvironmentValues {
    /// Which way up the person holds the iPhone, for the camera layout's upright icons and text.
    /// ``UprightRotation/portrait`` by default.
    @Entry public var cameraUprightRotation: UprightRotation = .portrait

    /// Opens nope.'s page in the Settings app, for the Open Settings buttons (camera access
    /// declined, photos access declined). `nil` hides those buttons, so an interface without a
    /// way to open Settings shows no button that does nothing. The app target sets it with
    /// `UIApplication.openSettingsURLString`.
    @Entry public var openAppSettings: CameraAction?

    /// Called with `true` when the camera screen presents Settings or another sheet, and `false`
    /// when it closes. The iPhone app keeps the camera layout in portrait and lets sheets rotate
    /// (issue #68, "Settings and sheets rotate normally"); it uses this to allow rotation while a
    /// sheet is open.
    @Entry public var cameraPresentsSheet = SheetPresentationAction { _ in }
}

/// An action the app target supplies to the camera screen, such as opening Settings. Call it
/// like a function.
public struct CameraAction: Sendable {
    /// Performs the action.
    private let handler: @MainActor @Sendable () -> Void

    /// Creates an action.
    ///
    /// - Parameter handler: Performs the action, on the main actor.
    public init(_ handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
    }

    /// Performs the action.
    @MainActor public func callAsFunction() {
        handler()
    }
}

/// Tells the app target that the camera screen opened or closed a sheet. Call it like a
/// function with `true` or `false`.
public struct SheetPresentationAction: Sendable {
    /// Handles the change.
    private let handler: @MainActor @Sendable (Bool) -> Void

    /// Creates an action.
    ///
    /// - Parameter handler: Handles the change: `true` when a sheet opens, `false` when it
    ///   closes, on the main actor.
    public init(_ handler: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.handler = handler
    }

    /// Handles the change.
    ///
    /// - Parameter isPresented: Whether a sheet is open.
    @MainActor public func callAsFunction(_ isPresented: Bool) {
        handler(isPresented)
    }
}

/// Turns a block of content upright as one unit while the iPhone is on its side, and gives it
/// the turned size in the layout, so neighbors make room for it.
///
/// It measures the content's natural size, turns it a quarter turn, and swaps the frame's width
/// and height. With `sidewaysWidth`, text wraps at that width before turning, for banners.
struct UprightUnit: ViewModifier {
    /// The width the content wraps at while sideways, or `nil` for its natural width.
    let sidewaysWidth: CGFloat?

    /// Which way up the person holds the device.
    @Environment(\.cameraUprightRotation) private var rotation

    /// The content's measured size before turning.
    @State private var size: CGSize = .zero

    /// Creates the modifier.
    ///
    /// - Parameter sidewaysWidth: The width the content wraps at while sideways, or `nil` for
    ///   its natural width.
    init(sidewaysWidth: CGFloat?) {
        self.sidewaysWidth = sidewaysWidth
    }

    /// The content, turned when the device is on its side.
    ///
    /// - Parameter content: The content.
    func body(content: Content) -> some View {
        if rotation.isSideways {
            sized(content)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .rotationEffect(rotation.angle)
                .frame(width: size.height, height: size.width)
        } else {
            content
        }
    }

    /// The content at its natural size, or wrapped at the sideways width.
    ///
    /// - Parameter content: The content.
    @ViewBuilder private func sized(_ content: Content) -> some View {
        if let sidewaysWidth {
            content.frame(width: sidewaysWidth).fixedSize(horizontal: false, vertical: true)
        } else {
            content.fixedSize()
        }
    }
}

extension View {
    /// Turns this block upright as one unit while the iPhone is on its side.
    ///
    /// - Parameter sidewaysWidth: The width text wraps at while sideways, or `nil` for the
    ///   natural width.
    func uprightUnit(sidewaysWidth: CGFloat? = nil) -> some View {
        modifier(UprightUnit(sidewaysWidth: sidewaysWidth))
    }
}
