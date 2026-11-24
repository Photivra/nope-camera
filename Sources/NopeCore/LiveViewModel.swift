import Foundation
import Observation

/// A ``CaptureBackend`` that can analyze the live preview at a low rate (histogram and focus
/// peaking) and report the camera's values for the live readout.
///
/// `NopeCapture`'s AVFoundation backend and ``SimulatedCaptureBackend`` implement it. Both are
/// off until asked, so nothing is measured ahead of need (AGENTS.md, "Battery"), and neither
/// changes what is captured: the analysis reads reduced preview frames from a separate video
/// output, never the photo output.
public protocol LiveViewBackend: CaptureBackend {
    /// The analyses of live frames, while analysis is on (``setFrameAnalysis(_:)``), a few a
    /// second at most (``LiveUpdateRate``). ``LiveViewModel/observeAnalyses()`` is its only
    /// consumer. The stream ends when the backend is released.
    var frameAnalyses: AsyncStream<FrameAnalysis> { get }

    /// The camera's values for the live readout, while it is on
    /// (``setStatsReadingsEnabled(_:)``), a few a second at most. ``LiveViewModel/observeStats()``
    /// is its only consumer. The stream ends when the backend is released.
    var statsReadings: AsyncStream<CameraStatsReading> { get }

    /// Starts, changes or stops the live frame analysis.
    ///
    /// - Parameter needs: What to measure; empty stops the analysis and removes its video
    ///   output.
    func setFrameAnalysis(_ needs: LiveAnalysisNeeds) async

    /// Turns the live readout's values on or off.
    ///
    /// - Parameter enabled: Whether to send values.
    func setStatsReadingsEnabled(_ enabled: Bool) async
}

/// The live aids over the viewfinder: the latest frame analysis (histogram, clipping and focus
/// peaking) and the live camera readout's values.
///
/// An interface tells it what is shown with ``setNeeds(_:)`` and ``setShowsStats(_:)``, and runs
/// ``observeAnalyses()`` and ``observeStats()`` for as long as the camera screen is visible.
/// Each copy of the interface also reports itself with ``interfaceDidAppear()`` and
/// ``interfaceDidDisappear()``; the aids stop when the last copy goes away. The model asks the
/// backend for nothing while nothing is shown.
@MainActor
@Observable
public final class LiveViewModel {
    /// The latest analysis, holding only what is needed now, or `nil`.
    public private(set) var analysis: FrameAnalysis?

    /// The latest values for the live readout, or `nil` while it is off or before the first.
    public private(set) var stats: CameraStatsReading?

    /// What the analysis is asked for now.
    public private(set) var needs: LiveAnalysisNeeds = []

    /// Whether the live readout is on.
    public private(set) var showsStats = false

    /// The hardware, or `nil` when the backend has no live view.
    private let backend: (any LiveViewBackend)?

    /// How many copies of the interface that shows the live aids are on screen now
    /// (``interfaceDidAppear()`` and ``interfaceDidDisappear()``).
    private var shownInterfaces = 0

    /// Creates the model.
    ///
    /// - Parameter backend: The backend, or `nil` when it has no live view; the model then
    ///   reports nothing.
    public init(backend: (any LiveViewBackend)?) {
        self.backend = backend
    }

    /// Whether the backend can analyze the preview and report values. Interfaces hide the live
    /// aids' switches when it can't.
    public var isSupported: Bool {
        backend != nil
    }

    /// Asks for what the screen shows now, and drops what it no longer needs.
    ///
    /// - Parameter needs: What to measure; see ``LiveAnalysisNeeds/needed(for:manualControlsShown:isCleanView:)``.
    ///
    /// Side effect: starts, changes or stops the backend's video analysis.
    public func setNeeds(_ needs: LiveAnalysisNeeds) async {
        guard needs != self.needs else { return }
        self.needs = needs
        analysis = analysis?.keeping(needs)
        await backend?.setFrameAnalysis(needs)
    }

    /// Turns the live readout on or off.
    ///
    /// - Parameter isOn: Whether the readout is shown.
    ///
    /// Side effect: starts or stops the backend's readings; turning off clears ``stats``.
    public func setShowsStats(_ isOn: Bool) async {
        guard isOn != showsStats else { return }
        showsStats = isOn
        if !isOn { stats = nil }
        await backend?.setStatsReadingsEnabled(isOn)
    }

    /// Records that an interface showing the live aids appeared. Call it as the interface
    /// appears, before it asks for anything.
    public func interfaceDidAppear() {
        shownInterfaces += 1
    }

    /// Records that an interface showing the live aids went away, and stops the analysis and the
    /// readout once no interface is left.
    ///
    /// SwiftUI can swap the interface for a new copy (when a layout moves the picture to another
    /// container) and tell the old copy it disappeared after the new one appeared and asked for
    /// the same needs. Stopping then left the new copy with nothing: its requests had changed
    /// nothing, so they weren't made again, and the histogram and readout never showed.
    ///
    /// Side effect: when no interface is left, stops the backend's video analysis and readings.
    public func interfaceDidDisappear() async {
        shownInterfaces = max(0, shownInterfaces - 1)
        guard shownInterfaces == 0 else { return }
        await setNeeds([])
        // An interface may have appeared while the analysis stopped; it asks for the readout itself.
        guard shownInterfaces == 0 else { return }
        await setShowsStats(false)
    }

    /// Applies the backend's analyses until its stream ends, keeping only what is needed (an
    /// analysis started before a change can arrive after it).
    public func observeAnalyses() async {
        guard let backend else { return }
        for await analysis in backend.frameAnalyses {
            self.analysis = analysis.keeping(needs)
        }
    }

    /// Applies the backend's readout values until its stream ends, while the readout is on.
    public func observeStats() async {
        guard let backend else { return }
        for await reading in backend.statsReadings where showsStats {
            stats = reading
        }
    }
}
