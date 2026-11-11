import NopeCore
import SwiftUI

/// The camera screen: renders a `CameraModel` and sends it intents.
///
/// The screen holds no rules: it shows the model's `CameraState` and sends
/// `CameraIntent` values (AGENTS.md, "One direction of flow"). It uses the dark
/// appearance, because a camera is used in every light and a dark frame doesn't change how a
/// scene looks; other screens follow the system appearance.
public struct CameraScreen: View {
    /// The model the screen renders.
    private let model: CameraModel

    /// Creates the camera screen.
    ///
    /// - Parameter model: The model to render. The screen sends `CameraIntent.start`
    ///   when it appears.
    public init(model: CameraModel) {
        self.model = model
    }

    /// The screen's content for the current state.
    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .preferredColorScheme(.dark)
            .task { await model.send(.start) }
    }

    /// The view for the model's current state.
    @ViewBuilder private var content: some View {
        switch model.state {
        case .starting:
            ProgressView {
                Text("Starting the camera…", bundle: .module, comment: "Shown briefly while the app checks camera access.")
            }
        case .needsPermission:
            PermissionRequestView { Task { await model.send(.requestPermission) } }
        case .permissionDenied:
            StatusMessageView(
                title: Text("Camera Access Is Off", bundle: .module, comment: "Title when camera access was declined."),
                systemImage: "camera.badge.ellipsis",
                message: Text(
                    "To take photos, turn on camera access for nope. in the Settings app.",
                    bundle: .module,
                    comment: "Explains how to allow camera access after it was declined. Keep \"nope.\" unchanged: it is the app's name."
                )
            )
        case .unavailable:
            StatusMessageView(
                title: Text("No Camera Available", bundle: .module, comment: "Title when the device has no usable camera."),
                systemImage: "camera",
                message: Text(
                    "This device has no camera that nope. can use.",
                    bundle: .module,
                    comment: "Explains that the device has no usable camera. Keep \"nope.\" unchanged: it is the app's name."
                )
            )
        case .ready(let capabilities):
            LensListView(lenses: capabilities.lenses)
        }
    }
}

/// Explains why nope. needs the camera and offers one button to ask.
struct PermissionRequestView: View {
    /// Called when the person presses the button.
    let requestAccess: () -> Void

    /// Creates the permission request.
    ///
    /// - Parameter requestAccess: Called when the person presses the button.
    init(requestAccess: @escaping () -> Void) {
        self.requestAccess = requestAccess
    }

    /// The explanation and the button.
    var body: some View {
        StatusMessageView(
            title: Text("Camera Access Needed", bundle: .module, comment: "Title before the app asks for camera access."),
            systemImage: "camera",
            message: Text(
                "nope. uses the camera only to take the photos you ask for.",
                bundle: .module,
                comment: "Explains why the app asks for camera access. Keep \"nope.\" unchanged: it is the app's name."
            )
        ) {
            Button(action: requestAccess) {
                Text("Allow Camera Access", bundle: .module, comment: "Button that shows the system camera permission prompt.")
            }
            // The bordered style, not the prominent one: white text on the system blue fill
            // fails the accessibility audit's contrast check (WCAG 2.2 AA, 4.5:1) in dark mode.
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

/// Lists the device's lenses and whether each one gives RAW.
struct LensListView: View {
    /// The lenses to list, in display order.
    let lenses: [Lens]

    /// Creates the lens list.
    ///
    /// - Parameter lenses: The lenses to list, in display order.
    init(lenses: [Lens]) {
        self.lenses = lenses
    }

    /// A list with one row per lens.
    var body: some View {
        List {
            Section {
                ForEach(lenses) { lens in
                    LabeledContent {
                        lens.supportsBayerRAW
                            ? Text("RAW", bundle: .module, comment: "Shown next to a lens that saves unprocessed RAW photos. RAW is a file format name; keep it unchanged unless your language writes it differently.")
                            : Text("HEIF only", bundle: .module, comment: "Shown next to a lens that can't save RAW, only HEIF with some device processing. HEIF is a file format name.")
                    } label: {
                        LensName(kind: lens.kind)
                    }
                }
            } header: {
                Text("Lenses", bundle: .module, comment: "Heading above the list of the device's camera lenses.")
            } footer: {
                Text("The viewfinder isn't built yet.", bundle: .module, comment: "Shown in development builds, before the live camera view exists.")
            }
        }
    }
}

/// The localized name of a kind of lens.
struct LensName: View {
    /// The kind of lens to name.
    let kind: Lens.Kind

    /// Creates the lens name.
    ///
    /// - Parameter kind: The kind of lens to name.
    init(kind: Lens.Kind) {
        self.kind = kind
    }

    /// The lens name as text.
    var body: some View {
        switch kind {
        case .ultraWide:
            Text("Ultra Wide", bundle: .module, comment: "Name of the rear ultra wide camera lens.")
        case .wide:
            Text("Wide", bundle: .module, comment: "Name of the rear wide (main) camera lens.")
        case .telephoto:
            Text("Telephoto", bundle: .module, comment: "Name of a rear telephoto camera lens.")
        case .front:
            Text("Front", bundle: .module, comment: "Name of the front (selfie) camera.")
        }
    }
}
