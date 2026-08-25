#if !targetEnvironment(macCatalyst)
import WidgetKit
import SwiftUI
import ActivityKit

/// A vibenet timelock running down, on the lock screen and in the Dynamic
/// Island (prd §473). See `VibenetUnlockActivityAttributes` for why the state
/// carries the END rather than the remainder.
///
/// **Every countdown here is `Text(timerInterval:)`, never a string we
/// computed.** The system ticks it, so it is right on the second forever with
/// no update from the app — which is the entire reason a timelock is a good
/// Live Activity and a card charge is not. It also means the lock screen and
/// the in-app countdown (§472's `TimelineView`) cannot drift: both are reading
/// the same instant rather than two independently-computed remainders.
struct VibenetUnlockActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VibenetUnlockActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.trianglebadge.exclamationmark")
                        .dsGlyph(17)
                        .foregroundStyle(WidgetChrome.accent)
                    Text(context.attributes.accountName)
                        .dsText(.widgetChrome15)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    countdown(context.state, style: .widgetChrome15)
                }
                // WHAT IT MEANS, not just how long. "Unlocking" alone is a
                // state word; this says what the clock is for, on a surface
                // read at arm's length with no room to tap through and find
                // out.
                Text(context.state.finished
                     ? String(localized: "The delay has ended")
                     : String(localized: "Unlock delay running"))
                    .dsText(.widgetTimer13)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .activityBackgroundTint(.black.opacity(0.8))
            .widgetURL(URL(string: "casberi://feed/Base%20Vibenet"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "lock.open.trianglebadge.exclamationmark")
                        .dsGlyph(20)
                        .foregroundStyle(WidgetChrome.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state, style: .heading17)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.accountName)
                        .dsText(.widgetTimer13)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "lock.open.trianglebadge.exclamationmark")
                    .dsGlyph(14)
                    .foregroundStyle(WidgetChrome.accent)
            } compactTrailing: {
                countdown(context.state, style: .widgetTimer13)
            } minimal: {
                Image(systemName: "lock.open.trianglebadge.exclamationmark")
                    .dsGlyph(14)
                    .foregroundStyle(WidgetChrome.accent)
            }
        }
    }

    /// The clock. `.timer` counts DOWN to the instant on its own; a finished
    /// delay draws a word instead, because a timer at an elapsed date renders
    /// a stopped zero, which reads as broken rather than as done.
    @ViewBuilder
    private func countdown(_ state: VibenetUnlockActivityAttributes.ContentState,
                           style: DSTextStyle) -> some View {
        if state.finished || state.unlocksAt <= .now {
            Text(String(localized: "Open"))
                .dsText(style)
        } else {
            Text(timerInterval: .now...state.unlocksAt, countsDown: true)
                .dsText(style)
                .monospacedDigit()
                // A countdown's width changes as digits drop; without this the
                // compact trailing slot jitters the whole island every minute.
                .multilineTextAlignment(.trailing)
        }
    }
}
#endif
