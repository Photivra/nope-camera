import NopeCore
import SwiftUI

/// The Camera menu: "Take Photo" with the Space bar, for a hardware keyboard on iPad or iPhone.
///
/// Menu commands appear in the iPadOS menu bar and in the keyboard shortcuts overlay (hold
/// Command), so the shortcut can be discovered there. Return is not a shortcut: a bare Return
/// key command, in the menu or on the shutter button, didn't fire in the iOS 27.2 Simulator's
/// UI tests, so only Space is offered until a device check shows otherwise. The command sends `CameraIntent.capture`, which the model
/// ignores when a photo can't be taken, and it is disabled whenever the shutter is.
///
/// Full Keyboard Access keeps the Space bar for the focused control: a key command without
/// `wantsPriorityOverSystemBehavior` yields to system behavior (UIKit, `UIKeyCommand`).
///
/// Add it to the app's scene:
///
/// ```swift
/// WindowGroup { CameraScreen(model: model) }
///     .commands { CameraCommands(model: model) }
/// ```
public struct CameraCommands: Commands {
    /// The model that takes the photo.
    private let model: CameraModel

    /// Creates the Camera menu.
    ///
    /// - Parameter model: The model that takes the photo; the same one the camera screen shows.
    public init(model: CameraModel) {
        self.model = model
    }

    /// The menu with its one command.
    public var body: some Commands {
        CommandMenu(Text("Camera", bundle: .module, comment: "Name of the menu with camera commands, in the iPad menu bar and keyboard shortcuts overlay.")) {
            Button {
                Task { await model.send(.capture) }
            } label: {
                Text("Take Photo", bundle: .module, comment: "VoiceOver and Voice Control name of the shutter button.")
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!model.canCapture)
        }
    }
}
