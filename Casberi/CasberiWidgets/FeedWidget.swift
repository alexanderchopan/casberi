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
        .description("The newest from your apps today.")
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
        // Two entries: now, and midnight, where the rows stop being today's.
        // The app reloads this kind whenever the rows change, which a new
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

    /// Today's rows, or nil once the day they were for has passed.
    private var feed: WidgetFeed? {
        guard let feed = entry.feed, feed.isCurrent(now: entry.date) else { return nil }
        return feed
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
            if let feed {
                if feed.rows.isEmpty {
                    line(String(localized: "Nothing yet today"))
                } else {
                    // Home's Activity at tile size (§1864): the app's icon and
                    // its newest thing, one line, no name.
                    ForEach(Array(feed.rows.prefix(WidgetFeedTile.rowCap)), id: \.id) { row in
                        HStack(spacing: 7) {
                            mark(row.source)
                            Text(verbatim: row.title)
                                .dsText(.widgetSubline12)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if feed.more > 0 {
                        Text("\(feed.more) more today")
                            .dsText(.widgetSubline11)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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

    /// The app's icon as the app drew it into the app group
    /// (`WidgetFeedTile.marksFolder`); a blank square while it has not.
    @ViewBuilder
    private func mark(_ source: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        if let image = Self.markImage(source) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 20, height: 20).clipShape(shape)
        } else {
            shape.fill(.secondary.opacity(0.3)).frame(width: 20, height: 20)
        }
    }

    static func markImage(_ source: String) -> UIImage? {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent(WidgetFeedTile.marksFolder, isDirectory: true)
        else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent(WidgetFeedTile.markFile(source)).path)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .dsText(.widgetSubline12)
            .foregroundStyle(.secondary)
            .lineLimit(3)
    }
}
