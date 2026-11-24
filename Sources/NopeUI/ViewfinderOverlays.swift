import NopeCore
import SwiftUI

extension EnvironmentValues {
    /// Where the level's gravity readings come from, or `nil` to hide the level. The app target
    /// sets it to a Core Motion source; `NopeUI` doesn't import Core Motion.
    @Entry public var cameraGravitySource: (any GravitySource)?

    /// Whether a sheet, popover or full-screen cover is over the camera (Settings, Formats,
    /// What's in This Photo, Compare, Presets and the others), so the level's tap is held back.
    /// The camera screen sets it; `false` by default.
    @Entry var cameraIsCovered = false
}

/// The guides and live aids drawn over the viewfinder: the grid and the level, and, at standard
/// text sizes, the histogram and the live camera readout (``LiveAidsPanel``).
///
/// Everything here is on screen only and never written to the photo (issues #40, #47, #51 and
/// #52). Nothing takes touches, so the viewfinder's own gestures still work. The guides stay in
/// clean view; the histogram doesn't, and the readout only when it is pinned.
///
/// It tells the model what the live analysis must measure and whether the readout is on, as
/// the options and the screen change, and turns both off when it goes away (AGENTS.md,
/// "Battery").
struct ViewfinderOverlays: View {
    /// The camera model.
    let model: CameraModel

    /// The person's settings.
    let settings: NopeSettings

    /// Where the level's readings come from, or `nil` without motion sensors.
    @Environment(\.cameraGravitySource) private var gravitySource

    /// The current text size; at accessibility sizes the panel moves below the picture.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Which way up the person holds the iPhone, for the panel's corner.
    @Environment(\.cameraUprightRotation) private var rotation

    /// The layout direction, to put the panel on a physical corner.
    @Environment(\.layoutDirection) private var layoutDirection

    /// Whether a sheet is over the camera, which holds the level's tap back.
    @Environment(\.cameraIsCovered) private var isCovered

    /// Whether the app is active, which the level's tap needs.
    @Environment(\.scenePhase) private var scenePhase

    /// The level.
    @State private var level = LevelModel()

    /// Creates the overlays.
    ///
    /// - Parameters:
    ///   - model: The camera model.
    ///   - settings: The person's settings.
    init(model: CameraModel, settings: NopeSettings) {
        self.model = model
        self.settings = settings
    }

    /// The overlay options.
    private var options: OverlayOptions { settings.overlays }

    /// What the live analysis must measure now.
    private var needs: LiveAnalysisNeeds {
        guard model.live.isSupported, model.sessionStatus == .running else { return [] }
        var needs = LiveAnalysisNeeds.needed(
            for: options, manualControlsShown: model.manual.isEnabled, isCleanView: model.isCleanView)
        // Focus peaking shows while an end of a focus bracket's range is set, whatever its
        // switch says (docs/design/BRACKETING.md, section 5).
        if model.bracketing.rangeEditing != nil { needs.insert(.focusPeaking) }
        return needs
    }

    /// Whether the live readout is shown: on, supported, and not in clean view unless pinned.
    private var showsStats: Bool {
        options.showsLiveReadout(inCleanView: model.isCleanView) && model.live.isSupported && model.sessionStatus == .running
    }

    /// Whether the level's tap is held back: by the camera (`CameraModel.holdsBackLevelTap`),
    /// a sheet over the camera, or the app not being active (docs/design/level-haptic.md,
    /// section 4).
    private var holdsBackLevelTap: Bool {
        model.holdsBackLevelTap || isCovered || scenePhase != .active
    }

    /// The overlays.
    var body: some View {
        ZStack {
            // Drawn shapes only, so nothing here is an accessibility element. (Marking them
            // hidden made SwiftUI expose an unlabeled element instead.)
            if options.showsGrid {
                GridOverlay(style: options.gridStyle)
                    .allowsHitTesting(false)
            }
            if options.showsLevel, let gravitySource {
                LevelOverlay(state: level.state, holdsBackTap: holdsBackLevelTap)
                    .allowsHitTesting(false)
                    .task { await level.run(gravitySource) }
            }
            if !dynamicTypeSize.isAccessibilitySize {
                LiveAidsPanel(model: model, settings: settings)
                    .allowsHitTesting(false)
                    .uprightUnit()
                    .padding(NopeSpace.xs)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panelAlignment)
            }
        }
        .onAppear { model.live.interfaceDidAppear() }
        .task(id: needs) { await model.live.setNeeds(needs) }
        .task(id: showsStats) { await model.live.setShowsStats(showsStats) }
        // Stops the aids only when no copy of the overlays is left: a layout change replaces
        // them with a new copy, which has already asked for what it shows.
        .onDisappear { Task { await model.live.interfaceDidDisappear() } }
    }

    /// The corner that is the person's top trailing corner: the screen's in portrait, and the
    /// one that is up and to the right while the iPhone is on its side.
    private var panelAlignment: Alignment {
        let isRightToLeft = layoutDirection == .rightToLeft
        switch rotation {
        case .portrait: return .topTrailing
        case .landscapeLeft: return isRightToLeft ? .bottomLeading : .bottomTrailing
        case .landscapeRight: return isRightToLeft ? .topTrailing : .topLeading
        }
    }
}

/// Focus peaking over the live picture, while the live analysis measures it. The camera puts it
/// on the picture itself, under the focus magnifier's enlargement, so the highlight stays on the
/// edges it marks.
struct FocusPeakingLayer: View {
    /// The camera model.
    let model: CameraModel

    /// Creates the layer.
    ///
    /// - Parameter model: The camera model.
    init(model: CameraModel) {
        self.model = model
    }

    /// The highlight, or nothing.
    var body: some View {
        if model.live.needs.contains(.focusPeaking), let map = model.live.analysis?.focusPeaking {
            FocusPeakingOverlay(map: map)
                .allowsHitTesting(false)
        }
    }
}

/// The grid: thin white lines with a dark outline, so they show over any scene (issue #40).
struct GridOverlay: View {
    /// The style.
    let style: GridStyle

    /// The width of the white line, in points.
    static let lineWidth: CGFloat = 1

    /// The width of the dark outline under it, in points.
    static let outlineWidth: CGFloat = 2.5

    /// Creates the grid.
    ///
    /// - Parameter style: The style.
    init(style: GridStyle) {
        self.style = style
    }

    /// The lines: a dark outline under a white line, drawn as shapes (not a canvas), so they
    /// add nothing to the accessibility tree.
    var body: some View {
        let shape = GridShape(style: style)
        shape.stroke(.white.opacity(0.9), lineWidth: Self.lineWidth)
            .background(shape.stroke(.black.opacity(0.6), lineWidth: Self.outlineWidth))
    }

    /// The grid's lines at a size.
    ///
    /// - Parameters:
    ///   - style: The style.
    ///   - size: The picture's size.
    nonisolated static func path(style: GridStyle, in size: CGSize) -> Path {
        let point = { (guide: GuidePoint) in CGPoint(x: guide.x * size.width, y: guide.y * size.height) }
        var path = Path()
        let aspectRatio = size.height > 0 ? size.width / size.height : 1
        for line in GridGeometry.lines(for: style, aspectRatio: aspectRatio) {
            path.move(to: point(line.start))
            path.addLine(to: point(line.end))
        }
        return path
    }
}

/// The grid's lines as a shape.
struct GridShape: Shape {
    /// The style.
    let style: GridStyle

    /// Creates the shape.
    ///
    /// - Parameter style: The style.
    init(style: GridStyle) {
        self.style = style
    }

    /// The lines in a rectangle.
    ///
    /// - Parameter rect: The picture's rectangle.
    func path(in rect: CGRect) -> Path {
        GridOverlay.path(style: style, in: rect.size)
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Focus peaking: the in-focus cells of the live preview filled in magenta, a color that stands
/// out over most scenes and isn't one of the camera's teal, amber or white meanings.
struct FocusPeakingOverlay: View {
    /// The map of in-focus cells.
    let map: FocusPeakingMap

    /// The highlight color: magenta, a color the interface uses for nothing else
    /// (``NopeColor/peaking``).
    static var color: Color { NopeColor.peaking }

    /// Creates the overlay.
    ///
    /// - Parameter map: The map of in-focus cells.
    init(map: FocusPeakingMap) {
        self.map = map
    }

    /// The highlighted cells, drawn as a shape so they add nothing to the accessibility tree.
    var body: some View {
        PeakingShape(map: map).fill(Self.color.opacity(0.75))
    }
}

/// The in-focus cells of a focus peaking map as a shape.
struct PeakingShape: Shape {
    /// The map.
    let map: FocusPeakingMap

    /// Creates the shape.
    ///
    /// - Parameter map: The map.
    init(map: FocusPeakingMap) {
        self.map = map
    }

    /// One rectangle per in-focus cell.
    ///
    /// - Parameter rect: The picture's rectangle.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard map.width > 0, map.height > 0 else { return path }
        let cell = CGSize(width: rect.width / CGFloat(map.width), height: rect.height / CGFloat(map.height))
        for (index, inFocus) in map.cells.enumerated() where inFocus {
            let origin = CGPoint(
                x: rect.minX + CGFloat(index % map.width) * cell.width, y: rect.minY + CGFloat(index / map.width) * cell.height)
            path.addRect(CGRect(origin: origin, size: cell))
        }
        return path
    }
}

/// The level (issue #40): a horizon bar that stays on the real horizon and turns solid and
/// thicker when the device is level, or, when the device points straight down, a top-down level
/// whose inner circle fills when level.
///
/// A tap (``NopeHaptic/levelReached``) marks the moment it becomes level, and VoiceOver says
/// "Level" (or "Pointing straight down, level") at the same moment, at low priority. When they
/// play is decided by `LevelTapRule` in `NopeCore`; this view only plays them. VoiceOver also
/// reads the state on request, as the element's value; the tilt isn't announced as it changes,
/// and nothing is announced on leaving level.
struct LevelOverlay: View {
    /// What the level shows, or `nil` before the first reading.
    let state: LevelState?

    /// Whether the tap and its announcement are held back now.
    let holdsBackTap: Bool

    /// Decides when to tap. It starts again whenever the level appears.
    @State private var tapRule = LevelTapRule()

    /// The number of taps played, the haptic's trigger.
    @State private var taps = 0

    /// The horizon bar's length, as a share of the picture's shorter side.
    static let barShare = 0.45

    /// How far the top-down level's inner circle moves per degree of tilt, in points.
    static let pointsPerDegree: CGFloat = 3

    /// The farthest the inner circle moves, in points.
    static let maximumOffset: CGFloat = 60

    /// Creates the level.
    ///
    /// - Parameters:
    ///   - state: What the level shows, or `nil` before the first reading.
    ///   - holdsBackTap: Whether the tap and its announcement are held back now.
    init(state: LevelState?, holdsBackTap: Bool) {
        self.state = state
        self.holdsBackTap = holdsBackTap
    }

    /// The level.
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch state {
                case .horizon(let rotation, _, let isLevel):
                    horizon(length: min(proxy.size.width, proxy.size.height) * Self.barShare, rotation: rotation, isLevel: isLevel)
                case .flat(let pitch, let roll, let isLevel):
                    flat(pitch: pitch, roll: roll, isLevel: isLevel)
                case nil:
                    EmptyView()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Level", bundle: .module, comment: "Name of the horizon level shown over the viewfinder, and of its switch."))
        .accessibilityValue(LevelText.description(of: state))
        // VoiceOver reads it; touches go to the viewfinder under it.
        .accessibilityRespondsToUserInteraction(false)
        .onChange(of: state) { _, state in
            guard tapRule.update(state, at: .now, isHeldBack: holdsBackTap), let state else { return }
            taps += 1
            LevelText.announceReached(state)
        }
        .sensoryFeedback(NopeHaptic.levelReached, trigger: taps)
    }

    /// The horizon bar, with short fixed marks on either side to show the tilt against.
    ///
    /// - Parameters:
    ///   - length: The bar's length, in points.
    ///   - rotation: How far the device is turned clockwise, in degrees.
    ///   - isLevel: Whether the device is level.
    private func horizon(length: CGFloat, rotation: Double, isLevel: Bool) -> some View {
        ZStack {
            // The fixed marks follow the nearest upright or sideways position.
            HStack(spacing: length) {
                mark
                mark
            }
            .rotationEffect(.degrees(-90 * (rotation / 90).rounded()))
            Capsule()
                .fill(.white)
                .frame(width: length, height: isLevel ? 4 : 2)
                .overlay(Capsule().stroke(.black.opacity(0.6), lineWidth: 1))
                .opacity(isLevel ? 1 : 0.8)
                .rotationEffect(.degrees(-rotation))
        }
    }

    /// A short fixed mark beside the horizon bar.
    private var mark: some View {
        Rectangle()
            .fill(.white)
            .frame(width: 16, height: 2)
            .overlay(Rectangle().stroke(.black.opacity(0.6), lineWidth: 1))
    }

    /// The top-down level: a fixed ring, and an inner circle that moves toward the raised side.
    ///
    /// - Parameters:
    ///   - pitch: How far the top edge is raised, in degrees.
    ///   - roll: How far the right edge is raised, in degrees.
    ///   - isLevel: Whether the device is level.
    private func flat(pitch: Double, roll: Double, isLevel: Bool) -> some View {
        let offset = CGSize(
            width: max(min(CGFloat(roll) * Self.pointsPerDegree, Self.maximumOffset), -Self.maximumOffset),
            height: max(min(CGFloat(-pitch) * Self.pointsPerDegree, Self.maximumOffset), -Self.maximumOffset))
        return ZStack {
            Circle()
                .stroke(.white, lineWidth: 2)
                .background(Circle().stroke(.black.opacity(0.6), lineWidth: 4))
                .frame(width: 48, height: 48)
            Circle()
                .fill(isLevel ? Color.white : Color.clear)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .background(Circle().stroke(.black.opacity(0.6), lineWidth: 4))
                .frame(width: 24, height: 24)
                .offset(offset)
        }
    }
}

/// The level's words for VoiceOver.
enum LevelText {
    /// The level's state in words, such as "Tilted 3° clockwise" or "Level".
    ///
    /// - Parameter state: The state, or `nil` before the first reading.
    static func description(of state: LevelState?) -> Text {
        switch state {
        case nil:
            return Text(verbatim: "")
        case .horizon(_, let tilt, let isLevel):
            if isLevel {
                return Text("Level", bundle: .module, comment: "Name of the horizon level shown over the viewfinder, and of its switch.")
            }
            let degrees = degreesText(abs(tilt))
            if tilt > 0 {
                return Text("Tilted \(degrees) clockwise", bundle: .module, comment: "VoiceOver value of the horizon level: how far the device is turned clockwise from level. The value is an angle such as 3°.")
            }
            return Text("Tilted \(degrees) counterclockwise", bundle: .module, comment: "VoiceOver value of the horizon level: how far the device is turned counterclockwise from level. The value is an angle such as 3°.")
        case .flat(_, _, let isLevel):
            if isLevel {
                return Text("Pointing straight down, level", bundle: .module, comment: "VoiceOver value of the top-down level when the device points straight down and is level.")
            }
            return Text("Pointing down, not level", bundle: .module, comment: "VoiceOver value of the top-down level when the device points down but is tilted.")
        }
    }

    /// Says "Level", or "Pointing straight down, level" for the top-down level, to VoiceOver as
    /// the level becomes level. Queued at low priority, so it never interrupts a capture result,
    /// a countdown second or a warning.
    ///
    /// - Parameter state: The level state that was just reached.
    static func announceReached(_ state: LevelState) {
        var announcement: AttributedString
        if case .flat = state {
            announcement = AttributedString(localized: "Pointing straight down, level", bundle: .module, comment: "VoiceOver value of the top-down level when the device points straight down and is level.")
        } else {
            announcement = AttributedString(localized: "Level", bundle: .module, comment: "Name of the horizon level shown over the viewfinder, and of its switch.")
        }
        announcement.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(announcement).post()
    }

    /// An angle in whole degrees, such as "3°".
    ///
    /// - Parameter degrees: The angle.
    static func degreesText(_ degrees: Double) -> String {
        Measurement(value: degrees.rounded(), unit: UnitAngle.degrees)
            .formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
