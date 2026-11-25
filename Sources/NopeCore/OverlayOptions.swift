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

    /// Creates the defaults: every overlay off and the rule-of-thirds grid style.
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
        // A style this version doesn't have, such as the golden ratio and golden spiral removed
        // in issue #76, reads as thirds.
        gridStyle = defaults.string(forKey: Key.gridStyle).flatMap(GridStyle.init(rawValue:)) ?? .thirds
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
        // The golden spiral's placement is no longer a setting (issue #76); drop the stale
        // value so it isn't copied into new presets.
        defaults.removeObject(forKey: Key.removedSpiralPlacement)
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
        /// The golden spiral's placement, stored before issue #76 removed the golden grids; no
        /// longer read, and removed when the options are stored.
        static let removedSpiralPlacement = "NopeSettings.overlays.spiralPlacement"
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
