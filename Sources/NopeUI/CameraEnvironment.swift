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

    /// The turn upright content needs in a window, given the device's orientation: none in a
    /// window that is regular in both size classes (``CameraLayout/isRegularSize(horizontal:vertical:)``),
    /// because that window rotates with the device, as on iPad and on the unfolded inner display
    /// of a foldable iPhone, where the system turns the interface whatever the app asks.
    ///
    /// - Parameter isRegularSize: Whether the window is regular in both size classes.
    /// - Returns: This rotation in a portrait-only window, otherwise ``portrait``.
    func inWindow(isRegularSize: Bool) -> UprightRotation {
        isRegularSize ? .portrait : self
    }
}

/// Clears ``SwiftUICore/EnvironmentValues/cameraUprightRotation`` in a window that rotates with
/// the device, so icons and text aren't turned twice: once by the interface and again as
/// upright units. The size classes come from the environment, so the same rule covers an iPad
/// and both displays of a foldable iPhone, and changes as it folds or unfolds.
struct WindowUprightRotation: ViewModifier {
    /// Which way up the person holds the device, from the app.
    @Environment(\.cameraUprightRotation) private var rotation

    /// The horizontal size class.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The vertical size class.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Creates the modifier. It reads everything from the environment.
    init() {}

    /// The content, with the rotation its window needs.
    ///
    /// - Parameter content: The content.
    func body(content: Content) -> some View {
        content.environment(
            \.cameraUprightRotation,
            rotation.inWindow(
                isRegularSize: CameraLayout.isRegularSize(horizontal: horizontalSizeClass, vertical: verticalSizeClass)))
    }
}

extension EnvironmentValues {
    /// Which way up the person holds the iPhone, for the camera layout's upright icons and text.
    /// ``UprightRotation/portrait`` by default.
    @Entry public var cameraUprightRotation: UprightRotation = .portrait

    /// Opens the app's page in the Settings app, for the Open Settings buttons (camera access
    /// declined, photos access declined). `nil` hides those buttons, so an interface without a
    /// way to open Settings shows no button that does nothing. The app target sets it with
    /// `UIApplication.openSettingsURLString`.
    @Entry public var openAppSettings: CameraAction?

    /// Opens the Photos app, for the last-photo thumbnail (issue #36). `nil` makes a tap on the
    /// thumbnail show the photo's details instead, and hides Open in Photos. The app target sets
    /// it; it runs only when the person taps.
    @Entry public var openPhotosApp: CameraAction?

    /// Called with `true` when the camera screen presents Settings or another sheet, and `false`
    /// when it closes. The iPhone app keeps the camera layout in portrait and lets sheets rotate
    /// (issue #68, "Settings and sheets rotate normally"); it uses this to allow rotation while a
    /// sheet is open.
    @Entry public var cameraPresentsSheet = SheetPresentationAction { _ in }

    /// The light or dark appearance chosen in the system's settings, which Settings and the
    /// other screens that aren't the camera follow (``CameraScreen``, "Appearance").
    ///
    /// The camera screen's window is dark, so its own color scheme can't tell the system's
    /// setting, and a sheet presented from the camera would stay dark. The app target sets this
    /// from its window scene and updates it when the setting changes. `nil` (not known, the default) leaves those sheets in the camera's dark
    /// appearance.
    @Entry public var systemColorScheme: ColorScheme?

    /// Sets the appearance of the window the camera screen is in: dark while the camera shows,
    /// following the system on first run and the other screens that aren't the camera, and
    /// hears when a sheet that follows the system opens or closes (``WindowAppearanceRequest``).
    /// The app target sets it so it can keep reading the system's setting for
    /// ``systemColorScheme``. `nil` (the default) makes the camera screen ask with
    /// `preferredColorScheme(_:)`.
    @Entry public var windowAppearance: WindowAppearanceAction?
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
///
/// The measured size settles (``settledSize(_:measured:)``): it is rounded up to whole points,
/// and within a point of the size in use it only grows. The turned frame can sit at a
/// fractional position, where the content measured a third of a point larger or smaller; taking
/// every such measurement made the frame move, the content measure again, and so on without end,
/// which kept the main thread busy (a sideways iPhone at the largest text size with manual controls on; UI test
/// testEveryManualControlIsSettableInLandscapeAtTheLargestTextSize).
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
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = Self.settledSize(size, measured: $0) }
                .rotationEffect(rotation.angle)
                .frame(width: size.height, height: size.width)
        } else {
            content
        }
    }

    /// The size to lay out with, given the size in use and a new measurement: the measurement
    /// rounded up to whole points, so the frame is never smaller than the content. Within a point
    /// of the size in use, in both dimensions, the size only grows, so sub-point changes can't
    /// make it go back and forth; a larger change is taken as it is.
    ///
    /// - Parameters:
    ///   - current: The size in use.
    ///   - measured: The content's new measured size.
    /// - Returns: The size to lay out with.
    static func settledSize(_ current: CGSize, measured: CGSize) -> CGSize {
        let rounded = CGSize(width: measured.width.rounded(.up), height: measured.height.rounded(.up))
        let isSmallChange = abs(rounded.width - current.width) <= 1 && abs(rounded.height - current.height) <= 1
        guard isSmallChange else { return rounded }
        return CGSize(width: max(current.width, rounded.width), height: max(current.height, rounded.height))
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
