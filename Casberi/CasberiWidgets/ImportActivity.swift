#if !targetEnvironment(macCatalyst)
import WidgetKit
import SwiftUI
import ActivityKit

/// A bulk import on the lock screen and in the Dynamic Island (2026-08-14,
/// prd §382). See `ImportActivityAttributes` for why the count it shows is
/// always "saved" and never "in progress".
struct ImportActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ImportActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: context.state.finished
                          ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                        .dsGlyph(17)
                        .foregroundStyle(WidgetChrome.accent)
                    Text(headline(context.attributes.source, context.state))
                        .dsText(.widgetChrome15)
                    Spacer(minLength: 4)
                    Text(count(context.state))
                        .dsText(.widgetChrome15)
                        .monospacedDigit()
                }
                if let fraction = fraction(context.state) {
                    ProgressView(value: fraction)
                        .tint(WidgetChrome.accent)
                }
            }
            .padding(14)
            .activityBackgroundTint(.black.opacity(0.8))
            .widgetURL(URL(string: "casberi://feed/source/\(context.attributes.source)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.finished
                          ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                        .dsGlyph(20)
                        .foregroundStyle(WidgetChrome.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(count(context.state))
                        .dsText(.heading17)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(headline(context.attributes.source, context.state))
                        .dsText(.widgetChrome15)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let fraction = fraction(context.state) {
                        ProgressView(value: fraction).tint(WidgetChrome.accent)
                    }
                }
            } compactLeading: {
                Image(systemName: "tray.and.arrow.down.fill")
                    .foregroundStyle(WidgetChrome.accent)
            } compactTrailing: {
                Text(count(context.state))
                    .dsText(.widgetTimer13)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "tray.and.arrow.down.fill")
                    .foregroundStyle(WidgetChrome.accent)
            }
            .widgetURL(URL(string: "casberi://feed/source/\(context.attributes.source)"))
        }
    }

    private func headline(_ source: String, _ state: ImportActivityAttributes.ContentState) -> String {
        state.finished ? String(localized: "\(source) imported")
                       : String(localized: "Saving your \(source) archive")
    }

    /// Always the SAVED count — see the attributes' own note. Never "N of M",
    /// which would read as a promise that the remainder is still coming even
    /// when the run has been suspended.
    private func count(_ state: ImportActivityAttributes.ContentState) -> String {
        String(localized: "\(state.landed) saved")
    }

    /// No bar when the total is unknown, rather than a bar against a
    /// denominator we invented. Clamped, because a caller that under-counts its
    /// own total must not produce a bar wider than the track.
    private func fraction(_ state: ImportActivityAttributes.ContentState) -> Double? {
        guard state.total > 0 else { return nil }
        return min(1, Double(state.landed) / Double(state.total))
    }
}
#endif
