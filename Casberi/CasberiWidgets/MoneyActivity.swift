#if !targetEnvironment(macCatalyst)
import WidgetKit
import SwiftUI
import ActivityKit

/// A record still in the machine, on the lock screen and in the Dynamic Island
/// (prd §369 amendment, 2026-08-16). See `MoneyActivityAttributes` for the
/// three rulings behind it — in particular why there is no figure anywhere in
/// this view, and why the age is never hidden.
struct MoneyActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MoneyActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: glyph(context.state))
                        .dsGlyph(17)
                        .foregroundStyle(WidgetChrome.accent)
                    Text(context.attributes.title)
                        .dsText(.widgetChrome15)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(context.state.stamp)
                        .dsText(.widgetChrome15)
                }
                // The age, always. This is the whole honesty rail: a Live
                // Activity implies "now", and the app only knows what a sweep
                // last told it.
                Text(checked(context.state))
                    .dsText(.widgetTimer13)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .activityBackgroundTint(.black.opacity(0.8))
            .widgetURL(URL(string: "casberi://thing/\(context.attributes.thingID)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: glyph(context.state))
                        .dsGlyph(20)
                        .foregroundStyle(WidgetChrome.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.stamp)
                        .dsText(.heading17)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .dsText(.widgetChrome15)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(checked(context.state))
                        .dsText(.widgetTimer13)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: glyph(context.state))
                    .foregroundStyle(WidgetChrome.accent)
            } compactTrailing: {
                // The STAMP, not the age: a compact slot fits one thing, and
                // the state is the answer to the question somebody is glancing
                // down to ask.
                Text(context.state.stamp)
                    .dsText(.widgetTimer13)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: glyph(context.state))
                    .foregroundStyle(WidgetChrome.accent)
            }
            .widgetURL(URL(string: "casberi://thing/\(context.attributes.thingID)"))
        }
    }

    /// Settled gets the closed mark; everything else is the waiting mark. No
    /// per-stamp glyph table: the stamp WORD is right there beside it, and a
    /// second encoding of the same fact is one more thing that can drift.
    private func glyph(_ state: MoneyActivityAttributes.ContentState) -> String {
        state.settled ? "checkmark.circle.fill" : "hourglass"
    }

    private func checked(_ state: MoneyActivityAttributes.ContentState) -> String {
        if state.settled { return String(localized: "Settled just now") }
        return String(localized: "Checked \(state.checkedAt.formatted(.relative(presentation: .named)))")
    }
}
#endif
