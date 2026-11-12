#if DEBUG
// Debug-only metadata tag check (issue #1, step 2). Compiled only in the Debug configuration:
// Release builds contain none of this code. See docs/TESTING.md, "Tag check".

import NopeCore
import Observation
import SwiftUI

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

    /// `true` while the backend's session runs, so the screen shows its viewfinder.
    var showsPreview = false

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

/// The debug-only tag check screen: runs ``TagCheckRunner`` once with the app's own capture
/// backend, shows that backend's viewfinder, and lists the progress.
///
/// Text is English only and uses `Text(verbatim:)`, so none of it enters a String Catalog.
struct TagCheckScreen: View {
    /// The app's capture backend, the same one the camera screen uses.
    let backend: any CaptureBackend

    /// The progress shown in the list.
    @State private var progress = TagCheckProgress()

    /// Creates the screen.
    /// - Parameter backend: The app's capture backend.
    init(backend: any CaptureBackend) {
        self.backend = backend
    }

    /// The viewfinder above the status lines.
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // The backend's own preview, as on the camera screen, so the tester can aim at a
                // lit scene. No extra output is added to the session for it.
                Group {
                    if progress.showsPreview, let source = backend.previewSource {
                        Viewfinder(source: source)
                    } else {
                        Color.black
                    }
                }
                .frame(height: 240)
                list
            }
            .navigationTitle(Text(verbatim: "Tag check (debug)"))
        }
        .task {
            await TagCheckRunner(backend: backend, progress: progress).run()
        }
    }

    /// The status lines.
    private var list: some View {
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
    }
}
#endif
