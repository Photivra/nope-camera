#if DEBUG
// Debug-only: every Live Activity layout in the app's own window, so the UI tests can audit them
// (issue #64). XCTest can't reach the Lock Screen or the Dynamic Island, and the layouts are the
// same views the NopeControls extension draws (App/Shared/SeriesActivity.swift).

import NopeCore
import SwiftUI

/// Shows each Live Activity state in its Lock Screen layout and its compact Dynamic Island parts.
///
/// Launch with `-NopeLiveActivityGallery`; add `-NopeLiveActivityGallery.night YES` for night
/// mode.
struct LiveActivityGallery: View {
    /// The launch argument.
    static let argument = "-NopeLiveActivityGallery"

    /// Whether this launch shows the gallery instead of the camera.
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    /// Whether the gallery is in night mode.
    private let isNightMode = UserDefaults.standard.bool(forKey: "NopeLiveActivityGallery.night")

    /// One example of each phase and kind people can see.
    private var examples: [LiveActivityContent] {
        let end = Date.now.addingTimeInterval(8)
        // A series that stops after an hour and a half, started 18 minutes ago.
        let seriesTime = Date.now.addingTimeInterval(-18 * 60)...Date.now.addingTimeInterval(72 * 60)
        return [
            LiveActivityContent(kind: .timer, phase: .countingDown, countdownEnd: end),
            LiveActivityContent(kind: .astro, phase: .countingDown, total: 20, countdownEnd: end),
            LiveActivityContent(kind: .interval, phase: .running, taken: 12, total: 120),
            LiveActivityContent(kind: .interval, phase: .paused, taken: 42, total: 120),
            LiveActivityContent(kind: .interval, phase: .running, taken: 1, seriesTime: seriesTime),
            LiveActivityContent(kind: .interval, phase: .paused, taken: 108, seriesTime: seriesTime),
            LiveActivityContent(kind: .astro, phase: .running, taken: 4, total: 20, saved: 3),
            LiveActivityContent(kind: .astro, phase: .paused, taken: 6, total: 20, saved: 6),
            LiveActivityContent(kind: .burst, phase: .saving, taken: 12, saved: 7),
            LiveActivityContent(kind: .astro, phase: .savingPaused, taken: 9, total: 20, saved: 6),
            LiveActivityContent(kind: .timer, phase: .saving, taken: 1),
            LiveActivityContent(kind: .burst, phase: .finished, taken: 12, saved: 12, signing: .allSigned),
            LiveActivityContent(kind: .astro, phase: .stopped, taken: 9, total: 20, saved: 9, signing: .notAllSigned),
            LiveActivityContent(kind: .timer, phase: .finished, taken: 1, saved: 1, signing: .notAllSigned),
            LiveActivityContent(kind: .burst, phase: .finished, taken: 5, saved: 5, signing: .off),
            LiveActivityContent(kind: .interval, phase: .stopped, taken: 42, total: 120),
            LiveActivityContent(kind: .interval, phase: .finished, taken: 540, seriesTime: seriesTime),
            LiveActivityContent(kind: .timer, phase: .stopped),
            LiveActivityContent(kind: .burst, phase: .failed, taken: 3, saved: 2),
        ].map { content in
            var content = content
            content.isNightMode = isNightMode
            return content
        }
    }

    /// The examples, each on a Lock Screen-like background, with its compact parts below.
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(Array(examples.enumerated()), id: \.offset) { _, content in
                    VStack(spacing: 0) {
                        SeriesActivityLockScreenView(content: content)
                        // The compact parts, read together, as one 44-point row: the audit measures
                        // them as a touch target, as the whole activity is in the Dynamic Island.
                        HStack {
                            SeriesActivityIcon(kind: content.kind)
                            Spacer()
                            SeriesActivityCompactCount(content: content)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .foregroundStyle(isNightMode ? SeriesActivityStyle.nightRed : .white)
                        .background(.black)
                    }
                    .background(isNightMode ? Color.black : Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 20))
                }
            }
            .padding()
        }
        .background(isNightMode ? Color.black : Color(.systemBackground))
        .preferredColorScheme(isNightMode ? .dark : nil)
    }
}
#endif
