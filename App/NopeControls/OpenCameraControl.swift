import AppIntents
import SwiftUI
import WidgetKit

/// The controls the app offers in Control Center, on the Lock Screen and for the Action button
/// (WidgetKit controls, iOS 18; issue #42).
///
/// This extension describes the controls and changes only the shared Night Mode setting, through
/// `NopeSettings` in the App Group's store. It contains no camera or photo code, and makes no
/// network request (AGENTS.md, "No network").
@main
struct NopeControls: WidgetBundle {
    /// The controls: "Open nope." and the Night Mode switch.
    var body: some Widget {
        OpenCameraControl()
        NightModeControl()
    }
}

/// A button that opens the app's camera, with ``OpenCameraIntent``. Because the intent is a
/// `CameraCaptureIntent`, the system opens the Lock Screen capture extension when the device
/// is locked, and the app when it isn't.
struct OpenCameraControl: ControlWidget {
    /// The control's identifier, stable across releases so a placed control keeps working.
    static let kind = NopeControlKind.openCamera

    /// The control: the camera symbol and its name.
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenCameraIntent()) {
                Label {
                    Text(
                        "Open nope.",
                        comment: "The name of the control that opens nope.'s camera, in Control Center and on the Lock Screen. Keep \"nope.\" unchanged."
                    )
                } icon: {
                    Image(systemName: "camera")
                }
            }
        }
        .displayName(
            LocalizedStringResource(
                "Open nope.",
                comment: "The name of the control that opens nope.'s camera, in Control Center and on the Lock Screen. Keep \"nope.\" unchanged."))
        .description(
            LocalizedStringResource(
                "Opens the nope. camera.",
                comment: "Describes what nope.'s Open the Camera action and control do, in the Shortcuts app and the controls gallery. Keep \"nope.\" unchanged."))
    }
}
