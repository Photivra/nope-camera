import ActivityKit
import NopeCore
import SwiftUI
import WidgetKit

/// The Live Activity's layouts on the Lock Screen and in the Dynamic Island (issue #64).
///
/// The app starts, updates and ends the activity on the device (`LiveActivityCoordinator`); this
/// extension only draws it from its content state. Tapping it opens the app, as the system does
/// for every Live Activity, so no URL is needed. Night mode draws it red on black.
struct SeriesLiveActivity: Widget {
    /// The layouts.
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SeriesActivityAttributes.self) { context in
            SeriesActivityLockScreenView(content: context.state)
                .activityBackgroundTint(context.state.isNightMode ? .black : nil)
                .activitySystemActionForegroundColor(context.state.isNightMode ? SeriesActivityStyle.nightRed : nil)
        } dynamicIsland: { context in
            let content = context.state
            let color = content.isNightMode ? SeriesActivityStyle.nightRed : Color.white
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SeriesActivityIcon(kind: content.kind)
                        .font(.title2)
                        .foregroundStyle(color)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SeriesActivityCompactCount(content: content)
                        .font(.title3)
                        .foregroundStyle(color)
                }
                DynamicIslandExpandedRegion(.center) {
                    SeriesActivityText.title(content.kind)
                        .font(.headline)
                        .foregroundStyle(color)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: NopeSpace.s) {
                        SeriesActivityDetails(content: content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if content.canStop {
                            SeriesStopButton(isNightMode: content.isNightMode, kind: content.kind)
                        }
                    }
                    .foregroundStyle(color)
                }
            } compactLeading: {
                SeriesActivityIcon(kind: content.kind)
                    .foregroundStyle(color)
            } compactTrailing: {
                SeriesActivityCompactCount(content: content)
                    .foregroundStyle(color)
            } minimal: {
                SeriesActivityIcon(kind: content.kind)
                    .foregroundStyle(color)
            }
            .keylineTint(color)
        }
    }
}
