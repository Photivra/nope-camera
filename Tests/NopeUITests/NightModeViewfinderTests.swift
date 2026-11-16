import Foundation
import NopeCore
import SwiftUI
import Testing
import UIKit

@testable import NopeUI

/// Night mode must not rebuild the live viewfinder. On a device the viewfinder is an
/// `AVCaptureVideoPreviewLayer`, and a new layer attaches itself to the running capture session
/// on the main thread, which makes the session rebuild its connections: turning night mode on or
/// off froze the camera for a while. These tests host the real camera screen with a viewfinder
/// that counts how often it is made and taken down.
@MainActor
struct NightModeViewfinderTests {
    /// Counts the viewfinder views made and taken down.
    final class Counter {
        var made = 0
        var dismantled = 0
    }

    /// A viewfinder backed by a UIKit view, as the app's preview layer is.
    struct CountingViewfinder: UIViewRepresentable {
        let counter: Counter

        func makeCoordinator() -> Counter { counter }

        func makeUIView(context: Context) -> UIView {
            counter.made += 1
            return UIView()
        }

        func updateUIView(_ view: UIView, context: Context) {}

        static func dismantleUIView(_ view: UIView, coordinator: Counter) {
            coordinator.dismantled += 1
        }
    }

    /// A simulated camera that counts how often the session starts and stops.
    final class CountingBackend: CaptureBackend, @unchecked Sendable {
        let simulated = SimulatedCaptureBackend(
            permission: .authorized,
            capabilities: DeviceCapabilities(lenses: [Lens(id: "wide", kind: .wide, bayerRAWFormat: "bgg4")]))
        private let lock = NSLock()
        private var starts = 0
        private var stops = 0

        /// How many times the session started and stopped.
        var sessionChanges: (starts: Int, stops: Int) { lock.withLock { (starts, stops) } }

        var events: AsyncStream<CaptureEvent> { simulated.events }
        var previewSource: (any CameraPreviewSource)? { simulated.previewSource }
        func currentPermission() async -> CameraPermission { await simulated.currentPermission() }
        func requestPermission() async -> CameraPermission { await simulated.requestPermission() }
        func deviceCapabilities() async -> DeviceCapabilities { await simulated.deviceCapabilities() }

        func startSession(_ request: CaptureRequest) async throws(CaptureError) {
            lock.withLock { starts += 1 }
            try await simulated.startSession(request)
        }

        func stopSession() async {
            lock.withLock { stops += 1 }
            await simulated.stopSession()
        }

        func capturePhoto(_ request: CaptureRequest) async throws(CaptureError) -> CapturedPhoto {
            try await simulated.capturePhoto(request)
        }
    }

    /// The camera screen in a window, ready, with a counting viewfinder.
    @MainActor
    struct Harness {
        let counter = Counter()
        let model: CameraModel
        let settings: NopeSettings
        let window: UIWindow
        let backend = CountingBackend()

        init(suite: String) async {
            let store = UserDefaults(suiteName: suite)!
            store.removePersistentDomain(forName: suite)
            settings = NopeSettings(defaults: store)
            model = CameraModel(backend: backend)
            await model.send(.start)
            let counter = counter
            let screen = CameraScreen(model: model, settings: settings) { _ in CountingViewfinder(counter: counter) }
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = UIHostingController(rootView: screen)
            window.makeKeyAndVisible()
            await settle()
        }

        /// Lets SwiftUI apply the latest changes and lay the window out.
        func settle() async {
            for _ in 0..<5 {
                window.rootViewController?.view.setNeedsLayout()
                window.layoutIfNeeded()
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    @Test(arguments: [false, true])
    func togglingNightModeKeepsTheViewfinder(tintsViewfinder: Bool) async throws {
        let harness = await Harness(suite: "NightModeViewfinderTests.\(tintsViewfinder)")
        harness.settings.setTintsViewfinderInNightMode(tintsViewfinder)
        await harness.settle()
        #expect(harness.counter.made == 1)
        let sessionBefore = harness.backend.sessionChanges
        for isOn in [true, false, true, false] {
            harness.settings.setNightMode(isOn)
            await harness.settle()
        }
        // One viewfinder, made once and never taken down, and the camera never restarted.
        #expect(harness.counter.made == 1)
        #expect(harness.counter.dismantled == 0)
        #expect(harness.backend.sessionChanges == sessionBefore)
    }

    @Test func turningRedViewfinderOnOrOffKeepsTheViewfinder() async throws {
        let harness = await Harness(suite: "NightModeViewfinderTests.red")
        harness.settings.setNightMode(true)
        await harness.settle()
        for isOn in [true, false, true, false] {
            harness.settings.setTintsViewfinderInNightMode(isOn)
            await harness.settle()
        }
        #expect(harness.counter.made == 1)
        #expect(harness.counter.dismantled == 0)
    }
}
