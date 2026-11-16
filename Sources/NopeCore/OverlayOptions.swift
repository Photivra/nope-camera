import Foundation

/// The guide lines the grid overlay draws over the viewfinder (issue #40). Guides are drawn on
/// screen only and are never written to the photo.
public enum GridStyle: String, CaseIterable, Sendable {
    /// Two lines each way, at thirds: the default.
    case thirds

    /// Three lines each way, at quarters.
    case fourByFour

    /// A centered square frame, for photos cropped square later.
    case square

    /// Two lines each way at the golden ratio (phi): about 38% and 62%.
    case goldenRatio

    /// A golden (Fibonacci) spiral, in one of eight placements (``SpiralPlacement``).
    case goldenSpiral
}

/// Where the golden spiral sits: one of its eight placements, four quarter turns each drawn
/// plain or flipped (issue #40, "The spiral can be flipped and rotated to any of its 8
/// placements").
public struct SpiralPlacement: Hashable, Sendable {
    /// The number of placements: four turns, each plain or flipped.
    public static let count = 8

    /// The placement the app starts with: no turn, not flipped. The spiral then winds in toward the
    /// right third of a landscape frame.
    public static let standard = SpiralPlacement(quarterTurns: 0, isFlipped: false)

    /// Clockwise quarter turns, 0 to 3.
    public let quarterTurns: Int

    /// Whether the spiral is mirrored left to right before it is turned.
    public let isFlipped: Bool

    /// Creates a placement.
    ///
    /// - Parameters:
    ///   - quarterTurns: Clockwise quarter turns; any whole number, reduced to 0 through 3.
    ///   - isFlipped: Whether the spiral is mirrored left to right before it is turned.
    public init(quarterTurns: Int, isFlipped: Bool) {
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
        self.isFlipped = isFlipped
    }

    /// The placement's number, 0 to 7, as stored in the settings.
    public var index: Int {
        quarterTurns + (isFlipped ? 4 : 0)
    }

    /// The placement with a number.
    ///
    /// - Parameter index: Any whole number; it is reduced to 0 through 7.
    public init(index: Int) {
        let reduced = ((index % Self.count) + Self.count) % Self.count
        self.init(quarterTurns: reduced % 4, isFlipped: reduced >= 4)
    }

    /// The next of the eight placements, wrapping back to the first: the "Turn Spiral" button
    /// and accessibility action step through them.
    public var next: SpiralPlacement {
        SpiralPlacement(index: index + 1)
    }

    /// The placement turned by more quarter turns, so the spiral keeps its place relative to the
    /// horizon while the device is turned and the camera layout stays put.
    ///
    /// - Parameter turns: Clockwise quarter turns to add; negative turns counterclockwise.
    /// - Returns: The turned placement, flipped the same way.
    public func turned(by turns: Int) -> SpiralPlacement {
        SpiralPlacement(quarterTurns: quarterTurns + turns, isFlipped: isFlipped)
    }
}

/// The viewfinder overlays the person turned on: guides (grid, level) and live aids (focus
/// peaking, histogram, live camera readout). Every overlay is off by default (issues #40, #47,
/// #51 and #52).
///
/// Privacy rule (AGENTS.md, "No network, no analytics"): overlays are on screen only. Nothing
/// they show is written to the photo, stored or logged.
public struct OverlayOptions: Equatable, Sendable {
    /// Whether the grid is shown.
    public var showsGrid = false

    /// Which grid is drawn while ``showsGrid`` is on.
    public var gridStyle = GridStyle.thirds

    /// Where the golden spiral sits, when ``gridStyle`` is ``GridStyle/goldenSpiral``.
    public var spiralPlacement = SpiralPlacement.standard

    /// Whether the level is shown: a horizon bar, or a top-down level when the device points
    /// straight down.
    public var showsLevel = false

    /// Whether in-focus edges are highlighted (focus peaking).
    public var showsFocusPeaking = false

    /// Whether the live histogram and clipping indicators are shown with the manual controls.
    public var showsHistogram = false

    /// Whether the live camera readout ("stats for nerds") is shown.
    public var showsLiveReadout = false

    /// Whether the live camera readout stays shown in clean view ("pinned"); otherwise clean
    /// view hides it with the other controls. Off by default.
    public var pinsLiveReadout = false

    /// Creates the defaults: every overlay off, the rule-of-thirds grid style and the standard
    /// spiral placement.
    public init() {}

    /// Loads the options from a store, using the default for any value not stored yet or not
    /// readable.
    ///
    /// Each value has its own key, so a UI test can set one with a launch argument, such as
    /// `-NopeSettings.overlays.showsGrid YES`.
    ///
    /// - Parameter defaults: The store to read.
    init(defaults: UserDefaults) {
        showsGrid = defaults.bool(forKey: Key.showsGrid)
        gridStyle = defaults.string(forKey: Key.gridStyle).flatMap(GridStyle.init(rawValue:)) ?? .thirds
        spiralPlacement = SpiralPlacement(index: defaults.integer(forKey: Key.spiralPlacement))
        showsLevel = defaults.bool(forKey: Key.showsLevel)
        showsFocusPeaking = defaults.bool(forKey: Key.showsFocusPeaking)
        showsHistogram = defaults.bool(forKey: Key.showsHistogram)
        showsLiveReadout = defaults.bool(forKey: Key.showsLiveReadout)
        pinsLiveReadout = defaults.bool(forKey: Key.pinsLiveReadout)
    }

    /// Writes the options to a store.
    ///
    /// - Parameter defaults: The store to write.
    func store(in defaults: UserDefaults) {
        defaults.set(showsGrid, forKey: Key.showsGrid)
        defaults.set(gridStyle.rawValue, forKey: Key.gridStyle)
        defaults.set(spiralPlacement.index, forKey: Key.spiralPlacement)
        defaults.set(showsLevel, forKey: Key.showsLevel)
        defaults.set(showsFocusPeaking, forKey: Key.showsFocusPeaking)
        defaults.set(showsHistogram, forKey: Key.showsHistogram)
        defaults.set(showsLiveReadout, forKey: Key.showsLiveReadout)
        defaults.set(pinsLiveReadout, forKey: Key.pinsLiveReadout)
    }

    /// Whether the live camera readout is shown on a camera screen: when it is on, and in clean
    /// view only when it is pinned (issue #52).
    ///
    /// - Parameter isCleanView: Whether clean view is on.
    /// - Returns: `true` if the readout is shown.
    public func showsLiveReadout(inCleanView isCleanView: Bool) -> Bool {
        showsLiveReadout && (pinsLiveReadout || !isCleanView)
    }

    /// Whether any overlay is on, for the settings row's summary.
    public var isAnyOn: Bool {
        showsGrid || showsLevel || showsFocusPeaking || showsHistogram || showsLiveReadout
    }

    /// The `UserDefaults` keys, one per value.
    enum Key {
        /// Whether the grid is shown, a Boolean.
        static let showsGrid = "NopeSettings.overlays.showsGrid"
        /// The grid style, a ``GridStyle`` raw value.
        static let gridStyle = "NopeSettings.overlays.gridStyle"
        /// The spiral placement, a ``SpiralPlacement/index``.
        static let spiralPlacement = "NopeSettings.overlays.spiralPlacement"
        /// Whether the level is shown, a Boolean.
        static let showsLevel = "NopeSettings.overlays.showsLevel"
        /// Whether focus peaking is shown, a Boolean.
        static let showsFocusPeaking = "NopeSettings.overlays.showsFocusPeaking"
        /// Whether the histogram is shown, a Boolean.
        static let showsHistogram = "NopeSettings.overlays.showsHistogram"
        /// Whether the live camera readout is shown, a Boolean.
        static let showsLiveReadout = "NopeSettings.overlays.showsLiveReadout"
        /// Whether the live camera readout stays in clean view, a Boolean.
        static let pinsLiveReadout = "NopeSettings.overlays.pinsLiveReadout"
    }
}

extension NopeSettings {
    /// Shows or hides the grid, and saves the change.
    ///
    /// - Parameter isOn: Whether the grid is shown.
    public func setShowsGrid(_ isOn: Bool) {
        var options = overlays
        options.showsGrid = isOn
        setOverlays(options)
    }

    /// Chooses the grid style, and saves the change.
    ///
    /// - Parameter style: The style.
    public func setGridStyle(_ style: GridStyle) {
        var options = overlays
        options.gridStyle = style
        setOverlays(options)
    }

    /// Moves the golden spiral to its next placement, and saves the change.
    public func turnSpiral() {
        var options = overlays
        options.spiralPlacement = options.spiralPlacement.next
        setOverlays(options)
    }

    /// Shows or hides the level, and saves the change.
    ///
    /// - Parameter isOn: Whether the level is shown.
    public func setShowsLevel(_ isOn: Bool) {
        var options = overlays
        options.showsLevel = isOn
        setOverlays(options)
    }

    /// Turns focus peaking on or off, and saves the change.
    ///
    /// - Parameter isOn: Whether in-focus edges are highlighted.
    public func setShowsFocusPeaking(_ isOn: Bool) {
        var options = overlays
        options.showsFocusPeaking = isOn
        setOverlays(options)
    }

    /// Shows or hides the histogram, and saves the change.
    ///
    /// - Parameter isOn: Whether the histogram is shown with the manual controls.
    public func setShowsHistogram(_ isOn: Bool) {
        var options = overlays
        options.showsHistogram = isOn
        setOverlays(options)
    }

    /// Shows or hides the live camera readout, and saves the change.
    ///
    /// - Parameter isOn: Whether the readout is shown.
    public func setShowsLiveReadout(_ isOn: Bool) {
        var options = overlays
        options.showsLiveReadout = isOn
        setOverlays(options)
    }

    /// Pins the live camera readout so it stays in clean view, or unpins it, and saves the
    /// change.
    ///
    /// - Parameter isOn: Whether the readout stays in clean view.
    public func setPinsLiveReadout(_ isOn: Bool) {
        var options = overlays
        options.pinsLiveReadout = isOn
        setOverlays(options)
    }
}
