import NopeCore
import SwiftUI
import UIKit

/// Tells the screen keeper about touches and VoiceOver focus changes, for Keep Screen On
/// (issue #97, `docs/design/keep-screen-on.md`, section 3). `NopeUI` reports control changes and
/// photos itself (``CameraModel/activityCount``); a touch or a move of VoiceOver's focus isn't
/// visible to it.
///
/// - Touches: a gesture recognizer on the window that only watches. It never recognizes, never
///   cancels or delays a touch and never prevents another recognizer, so every control works
///   as before (UIKit, `UIGestureRecognizer.cancelsTouchesInView`, `delaysTouchesBegan`,
///   `canPrevent(_:)`).
/// - VoiceOver: `UIAccessibility.elementFocusedNotification`, posted when VoiceOver's focus
///   moves.
///
/// Nothing is stored or sent: each one only restarts the keeper's count.
struct ReportsScreenActivity: ViewModifier {
    /// The keeper to tell.
    let keeper: SeriesScreenKeeper

    /// Creates the modifier.
    ///
    /// - Parameter keeper: The keeper to tell.
    init(keeper: SeriesScreenKeeper) {
        self.keeper = keeper
    }

    /// The content, with the window's touch watcher installed behind it.
    ///
    /// - Parameter content: The camera screen.
    func body(content: Content) -> some View {
        content
            .background { TouchWatcherInstaller { keeper.noteActivity() } }
            .task {
                for await _ in NotificationCenter.default.notifications(named: UIAccessibility.elementFocusedNotification) {
                    keeper.noteActivity()
                }
            }
    }
}

/// Puts a ``TouchWatcher`` on the window its view is in.
private struct TouchWatcherInstaller: UIViewRepresentable {
    /// Called for each touch that begins.
    let onTouch: @MainActor () -> Void

    /// Creates the view that finds the window.
    ///
    /// - Parameter context: The context.
    func makeUIView(context: Context) -> WindowFinder {
        WindowFinder(onTouch: onTouch)
    }

    /// Nothing changes after creation.
    ///
    /// - Parameters:
    ///   - uiView: The view.
    ///   - context: The context.
    func updateUIView(_ uiView: WindowFinder, context: Context) {}

    /// An empty view that adds the watcher to its window once it has one.
    final class WindowFinder: UIView {
        /// The watcher.
        private let watcher: TouchWatcher

        /// Creates the view.
        ///
        /// - Parameter onTouch: Called for each touch that begins.
        init(onTouch: @escaping @MainActor () -> Void) {
            watcher = TouchWatcher(onTouch: onTouch)
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        /// Not used: the view is created in code.
        required init?(coder: NSCoder) { nil }

        /// Moves the watcher to the new window.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            watcher.view?.removeGestureRecognizer(watcher)
            window?.addGestureRecognizer(watcher)
        }
    }
}

/// A gesture recognizer that reports each touch that begins and recognizes nothing.
private final class TouchWatcher: UIGestureRecognizer {
    /// Called for each touch that begins.
    private let onTouch: @MainActor () -> Void

    /// Creates the watcher.
    ///
    /// - Parameter onTouch: Called for each touch that begins.
    init(onTouch: @escaping @MainActor () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    /// Reports the touch, then fails, so it never takes it.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }

    /// Never prevents another recognizer.
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    /// Is never prevented by another recognizer.
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

extension View {
    /// Tells the keeper about touches and VoiceOver focus changes (``ReportsScreenActivity``).
    ///
    /// - Parameter keeper: The keeper.
    func reportsScreenActivity(to keeper: SeriesScreenKeeper) -> some View {
        modifier(ReportsScreenActivity(keeper: keeper))
    }
}
