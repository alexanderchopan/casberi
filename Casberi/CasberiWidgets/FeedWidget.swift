import WidgetKit
import SwiftUI

/// The Feed's contents in Feed order, on the Home Screen (prd §1210): each
/// category with something today, in the order Settings › Feed order sets,
/// and how many came today. A small tile only: one tap, and it opens the Feed.
///
/// It draws `WidgetFeedTile.published()`, which the app writes on every
/// foreground (`WidgetPublish.feed`). The counts are for one day: past
/// midnight the tile stops showing them and asks you to open the app, since
/// a count of yesterday drawn as today's is a wrong number (§83).
struct FeedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetFeedTile.kind, provider: FeedProvider()) { entry in
            FeedWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("Feed")
        .description("What came today, in your Feed order.")
        .supportedFamilies([.systemSmall])
    }
}

struct FeedEntry: TimelineEntry {
    let date: Date
    /// nil when the app has published nothing (yet, or for two days).
    let feed: WidgetFeed?
}

struct FeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeedEntry {
        FeedEntry(date: .now, feed: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FeedEntry) -> Void) {
        completion(FeedEntry(date: .now, feed: WidgetFeedTile.published()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedEntry>) -> Void) {
        // Two entries: now, and midnight, where the counts stop being today's.
        // The app reloads this kind whenever the counts change, which a new
        // day always does.
        let now = Date.now
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let feed = WidgetFeedTile.published(now: now)
        completion(Timeline(entries: [FeedEntry(date: now, feed: feed),
                                      FeedEntry(date: midnight, feed: WidgetFeedTile.published(now: midnight))],
                            policy: .never))
    }
}

struct FeedWidgetView: View {
    let entry: FeedEntry

    /// Today's sections, or nil when the counts are not today's.
    private var sections: [WidgetFeed.Section]? {
        guard let feed = entry.feed, feed.isCurrent(now: entry.date) else { return nil }
        return feed.sections
    }

    /// The rows the tile has room for. Past the cap the last row says how
    /// many more there are, so the tile never drops a category silently.
    private func shown(_ all: [WidgetFeed.Section]) -> (rows: [WidgetFeed.Section], more: Int) {
        guard all.count > WidgetFeedTile.rowCap else { return (all, 0) }
        let rows = Array(all.prefix(WidgetFeedTile.rowCap - 1))
        return (rows, all.count - rows.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "square.stack")
                    .dsGlyph(.caption, weight: .semibold)
                    .foregroundStyle(WidgetChrome.header)
                    .widgetAccentable()
                WidgetLabel(text: String(localized: "Feed"))
            }
            if let sections {
                if sections.isEmpty {
                    line(String(localized: "Nothing yet today"))
                } else {
                    let cut = shown(sections)
                    ForEach(cut.rows, id: \.room) { section in
                        HStack(spacing: 6) {
                            Text(verbatim: section.room)
                                .dsText(.widgetTitle14)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(verbatim: "\(section.today)")
                                .dsText(.widgetSubline12)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    if cut.more > 0 {
                        line(String(localized: "\(cut.more) more"))
                    }
                }
            } else {
                line(String(localized: "Open Casberi to see today"))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "casberi://feed"))
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .dsText(.widgetSubline12)
            .foregroundStyle(.secondary)
            .lineLimit(3)
    }
}
