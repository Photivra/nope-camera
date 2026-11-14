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
/// A Settings button opens ``SettingsScreen`` (a popover on iPad, a sheet on iPhone) in every
/// state, so settings and the Honesty screen are reachable before the camera is allowed. Before
/// camera access is asked, ``FirstRunView`` says what nope. does, then asks.
///
/// The app target can set ``SwiftUI/EnvironmentValues/openAppSettings`` (Open Settings buttons),
/// ``SwiftUI/EnvironmentValues/cameraUprightRotation`` (upright icons on a turned iPhone) and
/// ``SwiftUI/EnvironmentValues/cameraPresentsSheet`` (rotation while a sheet is open).
///
/// ```swift
/// CameraScreen(model: model, settings: settings) { source in
///     MyPreviewView(source: source)
/// }
/// ```
public struct CameraScreen<Viewfinder: View>: View {
    /// The model the screen renders.
    private let model: CameraModel

    /// The person's settings, shown and changed in the settings sheet.
    private let settings: NopeSettings

    /// Whether the settings sheet is open.
    @State private var showsSettings = false

    /// Makes the live viewfinder for the model's preview source.
    private let viewfinder: (any CameraPreviewSource) -> Viewfinder

    /// Creates the camera screen.
    ///
    /// - Parameters:
    ///   - model: The model to render. The screen sends `CameraIntent.start` when it appears
    ///     and runs `CameraModel.observeEvents()` while it is visible.
    ///   - settings: The person's settings, opened from the Settings button.
    ///   - viewfinder: Makes the live viewfinder from the model's preview source.
    public init(
        model: CameraModel, settings: NopeSettings,
        @ViewBuilder viewfinder: @escaping (any CameraPreviewSource) -> Viewfinder
    ) {
        self.model = model
        self.settings = settings
        self.viewfinder = viewfinder
    }

    /// Opens nope.'s page in the Settings app, or `nil` when the app can't.
    @Environment(\.openAppSettings) private var openAppSettings

    /// Tells the app that a sheet opened or closed, so it can rotate.
    @Environment(\.cameraPresentsSheet) private var presentsSheet

    /// The screen's content for the current state.
    public var body: some View {
        // Outside the ready camera, the Settings button sits above the content, not over it, so
        // scrolling content at large text sizes never passes under it. The ready camera has it
        // in its own top bar or control column.
        VStack(spacing: 0) {
            if !isReady {
                HStack {
                    Spacer()
                    SettingsButton { showsSettings = true }
                }
                .padding(.horizontal)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background)
        // A popover on iPad; on iPhone the system shows it as a sheet.
        .adaptivePresentation(isPresented: $showsSettings) {
            SettingsScreen(settings: settings, deviceSupportsBayerRAW: model.capabilities?.supportsBayerRAW ?? true)
                .frame(idealWidth: 480, idealHeight: 720)
        }
        .onChange(of: showsSettings) { _, isPresenting in presentsSheet(isPresenting) }
        .preferredColorScheme(.dark)
        .task { await model.send(.start) }
        .task { await model.observeEvents() }
        .task { await model.manual.observeReadings() }
        // An interval series runs only while the camera screen is shown (AGENTS.md, "Battery").
        .onDisappear { Task { await model.send(.manual(.stopInterval)) } }
    }

    /// Whether the camera is ready, so the Settings button is in the camera layout.
    private var isReady: Bool {
        if case .ready = model.state { true } else { false }
    }

    /// The view for the model's current state.
    @ViewBuilder private var content: some View {
        switch model.state {
        case .starting:
            ProgressView {
                Text("Starting the camera…", bundle: .module, comment: "Shown briefly while the app checks camera access.")
            }
        case .needsPermission:
            FirstRunView { Task { await model.send(.requestPermission) } }
        case .permissionDenied:
            StatusMessageView(
                title: Text("Camera Access Is Off", bundle: .module, comment: "Title when camera access was declined."),
                systemImage: "camera.badge.ellipsis",
                message: Text(
                    "To take photos, turn on camera access for nope. in the Settings app.",
                    bundle: .module,
                    comment: "Explains how to allow camera access after it was declined. Keep \"nope.\" unchanged: it is the app's name."
                )
            ) {
                if let openAppSettings {
                    Button {
                        openAppSettings()
                    } label: {
                        Text("Open Settings", bundle: .module, comment: "Button that opens nope.'s page in the system Settings app, where camera or photo library access can be allowed. Keep \"nope.\" unchanged.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
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
            CameraReadyView(model: model, settings: settings, lenses: capabilities.lenses, openSettings: { showsSettings = true }) {
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
    /// - Parameters:
    ///   - model: The model to render.
    ///   - settings: The person's settings.
    public init(model: CameraModel, settings: NopeSettings) {
        self.init(model: model, settings: settings) { _ in Color.black }
    }
}
