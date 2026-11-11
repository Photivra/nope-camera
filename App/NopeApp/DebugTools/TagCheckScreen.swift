#if DEBUG
// Debug-only metadata tag check (issue #1, step 2). Compiled only in the Debug configuration:
// Release builds contain none of this code. See docs/TESTING.md, "Tag check".

import AVFoundation
import Observation
import SwiftUI
import os

/// Decides whether this launch runs the debug-only tag check instead of the camera screen.
///
/// The tag check runs only when the app is launched with the ``argument`` launch argument in a
/// Debug build. It is never compiled into Release builds.
enum TagCheckLaunch {
    /// The launch argument that starts the tag check: `-NopeTagCheck`.
    static let argument = "-NopeTagCheck"

    /// `true` when the current process was launched with ``argument``.
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }
}

/// The tag check's progress, one plain status line per step, shown on screen.
///
/// Main-actor isolated: the capture queue posts lines through ``TagCheckRunner``.
@MainActor
@Observable
final class TagCheckProgress {
    /// One status line.
    struct Line: Identifiable {
        /// The line's position in the list.
        let id: Int
        /// The status text, in English (debug tool, not localized).
        let text: String
    }

    /// Every status line so far, oldest first.
    private(set) var lines: [Line] = []

    /// `true` once the tag check has finished, whether or not every lens succeeded.
    private(set) var isFinished = false

    /// Adds a status line.
    /// - Parameter text: The status text.
    func append(_ text: String) {
        lines.append(Line(id: lines.count, text: text))
    }

    /// Marks the tag check as finished.
    func finish() {
        isFinished = true
    }
}

/// The debug-only tag check screen: asks for camera access, runs ``TagCheckCapturer`` once, and
/// lists its progress.
///
/// Text is English only and uses `Text(verbatim:)`, so none of it enters a String Catalog.
struct TagCheckScreen: View {
    /// The progress shown in the list.
    @State private var progress = TagCheckProgress()

    /// A list of status lines under a title.
    var body: some View {
        NavigationStack {
            List {
                ForEach(progress.lines) { line in
                    Text(verbatim: line.text)
                }
                if progress.isFinished {
                    Label {
                        Text(verbatim: "Finished. Files are in Documents/TagCheck.")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Tag check (debug)"))
        }
        .task {
            await TagCheckRunner.run(progress: progress)
        }
    }
}

/// Runs the tag check: camera permission on the main actor, then every capture on a private
/// serial queue, because `AVCaptureSession.startRunning()` blocks.
enum TagCheckRunner {
    /// The queue that owns every capture session and file write.
    private static let queue = DispatchQueue(label: "com.photivra.nope.tagcheck")

    /// Requests camera access (the user taps Allow once), then captures with every physical
    /// lens and writes the files described in docs/TESTING.md, "Tag check".
    ///
    /// Side effects: shows the camera permission prompt if access is undetermined, and replaces
    /// the contents of `Documents/TagCheck/`.
    /// - Parameter progress: Receives one status line per step.
    @MainActor
    static func run(progress: TagCheckProgress) async {
        progress.append("Requesting camera access")
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            progress.append("Camera access denied. Allow it in Settings and relaunch.")
            progress.finish()
            return
        }
        // Lines are delivered on the main queue in the order they were posted.
        let report: @Sendable (String) -> Void = { text in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { progress.append(text) }
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                TagCheckCapturer(report: report).runAll()
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        progress.finish()
    }
}
#endif
