import NopeCore
import SwiftUI

/// The camera screen: renders a `CameraModel` and sends it intents.
///
/// The screen holds no rules: it shows the model's state and sends `CameraIntent` values
/// (AGENTS.md, "One direction of flow"). It uses the dark appearance, because a camera is used
/// in every light and a dark frame doesn't change how a scene looks; other screens follow the
/// system appearance.
///
/// The live viewfinder comes from the app target: `NopeUI` can't show camera video, so the app
/// passes a closure that turns the model's `CameraPreviewSource` into a view (for example one
/// backed by `AVCaptureVideoPreviewLayer`).
///
/// ```swift
/// CameraScreen(model: model) { source in
///     MyPreviewView(source: source)
/// }
/// ```
public struct CameraScreen<Viewfinder: View>: View {
    /// The model the screen renders.
    private let model: CameraModel

    /// Makes the live viewfinder for the model's preview source.
    private let viewfinder: (any CameraPreviewSource) -> Viewfinder

    /// Creates the camera screen.
    ///
    /// - Parameters:
    ///   - model: The model to render. The screen sends `CameraIntent.start` when it appears
    ///     and runs `CameraModel.observeEvents()` while it is visible.
    ///   - viewfinder: Makes the live viewfinder from the model's preview source.
    public init(model: CameraModel, @ViewBuilder viewfinder: @escaping (any CameraPreviewSource) -> Viewfinder) {
        self.model = model
        self.viewfinder = viewfinder
    }

    /// The screen's content for the current state.
    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .preferredColorScheme(.dark)
            .task { await model.send(.start) }
            .task { await model.observeEvents() }
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
            CameraReadyView(model: model, lenses: capabilities.lenses) {
                if let source = model.previewSource {
                    viewfinder(source)
                } else {
                    Color.black
                }
            }
        }
    }
}

extension CameraScreen where Viewfinder == Color {
    /// Creates the camera screen with a plain black viewfinder, for tests and previews.
    ///
    /// - Parameter model: The model to render.
    public init(model: CameraModel) {
        self.init(model: model) { _ in Color.black }
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
