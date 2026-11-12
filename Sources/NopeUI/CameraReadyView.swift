import NopeCore
import SwiftUI

/// The camera when it is ready: the format badge, the viewfinder with any pause message, the
/// last capture's status, the manual controls when they are on, the lens buttons and the
/// shutter.
///
/// Clean view hides everything but the viewfinder, the shutter and the button that brings the
/// controls back; the no-RAW badge, a running interval series and capture results stay. Hidden
/// controls stay reachable: the shutter offers "Show Controls" as a VoiceOver action, and Voice
/// Control can say it.
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

    /// The manual control whose panel is open, or `nil`.
    @State private var openControl: ManualControl?

    /// Whether Pro Tools is shown.
    @State private var showsProTools = false

    /// The shortest vertical swipe on the viewfinder that toggles clean view, in points.
    private static var cleanViewSwipeDistance: CGFloat { 60 }

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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    stack(viewfinderHeight: Self.scrollingViewfinderHeight)
                }
            } else {
                stack(viewfinderHeight: nil)
            }
        }
        // While Pro Tools covers the screen, the camera controls under it are hidden from
        // assistive technologies, so VoiceOver reads only the form.
        .accessibilityHidden(showsProTools)
        .fullScreenCover(isPresented: $showsProTools) {
            ProToolsSheet(model: model)
        }
    }

    /// The screen's parts, top to bottom.
    ///
    /// - Parameter viewfinderHeight: A fixed viewfinder height, or `nil` to fill the free space.
    private func stack(viewfinderHeight: CGFloat?) -> some View {
        VStack(spacing: 12) {
            // The no-RAW badge changes what the photo is, so clean view never hides it.
            if let format = model.captureFormat, !model.isCleanView || !format.isBayerRAW {
                FormatBadge(format: format)
            }
            viewfinderArea
                .frame(maxWidth: .infinity, minHeight: viewfinderHeight, maxHeight: viewfinderHeight ?? .infinity)
                .gesture(cleanViewSwipe, isEnabled: viewfinderHeight == nil)
            if let progress = model.manual.intervalProgress {
                IntervalProgressView(progress: progress) {
                    Task { await model.send(.manual(.stopInterval)) }
                }
            }
            CaptureStatusView(status: model.captureStatus)
            if !model.isCleanView {
                if model.manual.isEnabled {
                    ManualControlsView(model: model, openControl: $openControl, showsProTools: $showsProTools)
                }
                // The lens buttons make room while a control's panel is open.
                if openControl == nil || !model.manual.isEnabled {
                    LensPicker(lenses: lenses, selectedID: model.selectedLensID) { id in
                        Task { await model.send(.selectLens(id)) }
                    }
                }
            }
            ZStack {
                ShutterButton(isEnabled: model.canCapture) {
                    Task { await model.send(.capture) }
                }
                .accessibilityActions {
                    if model.isCleanView {
                        Button {
                            Task { await model.send(.setCleanView(false)) }
                        } label: {
                            Text("Show Controls", bundle: .module, comment: "Button and VoiceOver action that brings back the controls hidden by clean view.")
                        }
                    }
                }
                CleanViewButton(isCleanView: model.isCleanView) {
                    Task { await model.send(.setCleanView(!model.isCleanView)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .onChange(of: model.selectedLensID) { openControl = nil }
        .onChange(of: model.manual.isEnabled) { openControl = nil }
    }

    /// Swipe down on the viewfinder for clean view, up to bring the controls back.
    private var cleanViewSwipe: some Gesture {
        DragGesture(minimumDistance: Self.cleanViewSwipeDistance).onEnded { drag in
            let height = drag.translation.height
            guard abs(height) >= Self.cleanViewSwipeDistance, abs(height) > abs(drag.translation.width) else { return }
            Task { await model.send(.setCleanView(height > 0)) }
        }
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

/// The eye button that turns clean view on and off. Its name says what it does next: "Hide
/// Controls" or "Show Controls", so Voice Control can say either.
struct CleanViewButton: View {
    /// Whether clean view is on.
    let isCleanView: Bool

    /// Toggles clean view.
    let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - isCleanView: Whether clean view is on.
    ///   - action: Toggles clean view.
    init(isCleanView: Bool, action: @escaping () -> Void) {
        self.isCleanView = isCleanView
        self.action = action
    }

    /// The button.
    var body: some View {
        Button(action: action) {
            Label {
                isCleanView
                    ? Text("Show Controls", bundle: .module, comment: "Button and VoiceOver action that brings back the controls hidden by clean view.")
                    : Text("Hide Controls", bundle: .module, comment: "Button that turns on clean view: hides every control except the shutter.")
            } icon: {
                Image(systemName: isCleanView ? "eye" : "eye.slash")
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            // Primary on the gray fill: the secondary tint fails the contrast audit.
            .foregroundStyle(.primary)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
    }
}
