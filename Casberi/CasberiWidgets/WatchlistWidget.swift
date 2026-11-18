import WidgetKit
import SwiftUI

/// The Watchlist tile (prd §1881): your first four watched tokens and the
/// day's move of each, as Home's Watchlist row reads them. Small tile only.
/// It came back with the Watchlist (§1632) after leaving with Markets (§1529).
struct WatchlistWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetWatchlist.kind, provider: WatchlistProvider()) { entry in
            WatchlistWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("Watchlist")
        .description("The tokens you watch, and today's move.")
        .supportedFamilies([.systemSmall])
    }
}

struct WatchlistEntry: TimelineEntry {
    let date: Date
    let watch: WidgetWatch?
}

struct WatchlistProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchlistEntry {
        WatchlistEntry(date: .now, watch: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchlistEntry) -> Void) {
        completion(WatchlistEntry(date: .now, watch: WidgetWatchlist.published()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchlistEntry>) -> Void) {
        // The app reloads this kind when it reads new prices; the hourly ask
        // only retires a reading past its window.
        let now = Date.now
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        completion(Timeline(entries: [WatchlistEntry(date: now, watch: WidgetWatchlist.published(now: now))],
                            policy: .after(next)))
    }
}

struct WatchlistWidgetView: View {
    let entry: WatchlistEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetLabel(text: String(localized: "Watchlist"))
            if let rows = entry.watch?.rows, !rows.isEmpty {
                ForEach(Array(rows.prefix(WidgetWatchlist.rowCap).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        Text(verbatim: row.symbol)
                            .dsText(.widgetTitle14)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let pct = row.dayPct {
                            let move = WidgetWatchlist.change(pct)
                            Text(verbatim: move.words)
                                .dsText(.widgetSubline12)
                                .foregroundStyle(move.up == nil ? .secondary
                                                 : move.up == true ? WidgetChrome.gain : WidgetChrome.loss)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                Text("Today")
                    .dsText(.widgetSubline11)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(entry.watch == nil ? "Open Casberi to see your watchlist" : "Watch a token in Casberi")
                    .dsText(.widgetSubline12)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "casberi://home"))
    }
}
