import NopeCore
import SwiftUI

/// The camera when it is ready: the format badge, the viewfinder with any pause message, the
/// last capture's status, the lens buttons and the shutter.
///
/// At accessibility text sizes the whole screen scrolls, so no control is clipped (AGENTS.md,
/// "Larger Text").
struct CameraReadyView<Viewfinder: View>: View {
    /// The model to render and send intents to.
    let model: CameraModel

    /// The lenses, in display order.
    let lenses: [Lens]

    /// The live viewfinder from the app.
    let viewfinder: Viewfinder

    /// The current text size; accessibility sizes switch to a scrolling layout.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The minimum viewfinder height in the scrolling layout, in points: enough to frame a shot
    /// while the enlarged controls take the rest of the screen.
    private static var scrollingViewfinderHeight: CGFloat { 280 }

    /// Creates the ready view.
    ///
    /// - Parameters:
    ///   - model: The model to render.
    ///   - lenses: The lenses, in display order.
    ///   - viewfinder: Makes the live viewfinder.
    init(model: CameraModel, lenses: [Lens], @ViewBuilder viewfinder: () -> Viewfinder) {
        self.model = model
        self.lenses = lenses
        self.viewfinder = viewfinder()
    }

    /// The badge, viewfinder and controls, scrolling at accessibility text sizes.
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                stack(viewfinderHeight: Self.scrollingViewfinderHeight)
            }
        } else {
            stack(viewfinderHeight: nil)
        }
    }

    /// The screen's parts, top to bottom.
    ///
    /// - Parameter viewfinderHeight: A fixed viewfinder height, or `nil` to fill the free space.
    private func stack(viewfinderHeight: CGFloat?) -> some View {
        VStack(spacing: 12) {
            if let format = model.captureFormat {
                FormatBadge(format: format)
            }
            viewfinderArea
                .frame(maxWidth: .infinity, minHeight: viewfinderHeight, maxHeight: viewfinderHeight ?? .infinity)
            CaptureStatusView(status: model.captureStatus)
            LensPicker(lenses: lenses, selectedID: model.selectedLensID) { id in
                Task { await model.send(.selectLens(id)) }
            }
            ShutterButton(isEnabled: model.canCapture) {
                Task { await model.send(.capture) }
            }
        }
        .padding()
    }

    /// The viewfinder, with the session's pause or error message on top of it.
    ///
    /// VoiceOver reads it as one element that names the lens and the format (AGENTS.md,
    /// "VoiceOver"). Smart Invert leaves it alone.
    private var viewfinderArea: some View {
        ZStack {
            viewfinder
                .accessibilityIgnoresInvertColors()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Viewfinder", bundle: .module, comment: "VoiceOver name of the live camera view."))
                .accessibilityValue(viewfinderDescription)
            SessionStatusView(status: model.sessionStatus)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    /// "Lens: Wide. Format: single-frame RAW." for VoiceOver.
    private var viewfinderDescription: Text {
        guard let lens = model.selectedLens, let format = model.captureFormat else { return Text(verbatim: "") }
        let lensName = LensName.string(for: lens.kind)
        let formatName = FormatBadge.spokenName(for: format)
        return Text(
            "Lens: \(lensName). Format: \(formatName).", bundle: .module,
            comment: "VoiceOver value of the viewfinder. The first value is a lens name such as Wide; the second is a format such as single-frame RAW.")
    }
}
