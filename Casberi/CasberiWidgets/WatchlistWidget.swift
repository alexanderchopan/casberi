import WidgetKit
import SwiftUI

/// What you follow in Markets, on the Home Screen (prd §1223): the first four
/// rows of your watchlist in its own order, each its symbol, the price this
/// app last read and the day's move. A small tile only: one tap, and it opens
/// Markets.
///
/// It draws `WidgetWatch.published()`, which the app writes after each read
/// of the watchlist's prices (`WidgetPublish.watchlist`). A price older than
/// an hour is stamped, and one older than a day is not drawn: the symbol
/// stands alone rather than an old price drawn as now's (§83).
struct WatchlistWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetWatch.kind, provider: WatchlistProvider()) { entry in
            WatchlistWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("Watchlist")
        .description("What you follow in Markets.")
        .supportedFamilies([.systemSmall])
    }
}

struct WatchlistEntry: TimelineEntry {
    let date: Date
    /// nil when the app has published nothing (yet, or for a week).
    let list: WidgetWatchlist?
}

struct WatchlistProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchlistEntry {
        WatchlistEntry(date: .now, list: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchlistEntry) -> Void) {
        completion(WatchlistEntry(date: .now, list: WidgetWatch.published()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchlistEntry>) -> Void) {
        // The app reloads this kind whenever the prices change; the timeline
        // asks again within the hour only so the stamp and the day's cutoff
        // land on time.
        let now = Date.now
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now
        completion(Timeline(entries: [WatchlistEntry(date: now, list: WidgetWatch.published(now: now))],
                            policy: .after(next)))
    }
}

struct WatchlistWidgetView: View {
    let entry: WatchlistEntry

    private var rows: [WidgetWatchlist.Row] {
        Array((entry.list?.rows ?? []).prefix(WidgetWatch.rowCap))
    }

    /// "as of 3h ago" from the oldest price drawn, or nil while every price
    /// is within the hour.
    private var stamp: String? {
        let oldest = rows.compactMap { WidgetWatch.quote($0, now: entry.date)?.at }.min()
        return oldest.flatMap {
            WidgetStamp.text(for: $0, now: entry.date, after: WidgetWatch.stampAfter)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .dsGlyph(.caption, weight: .semibold)
                    .foregroundStyle(WidgetChrome.header)
                    .widgetAccentable()
                WidgetLabel(text: String(localized: "Watchlist"))
            }
            if entry.list == nil {
                line(String(localized: "Open Casberi to see your watchlist"))
            } else if rows.isEmpty {
                line(String(localized: "Follow a company in Markets"))
            } else {
                ForEach(rows, id: \.ref) { row in
                    WatchlistRow(row: row, quote: WidgetWatch.quote(row, now: entry.date))
                }
                if let stamp {
                    Text(stamp)
                        .dsText(.widgetSubline11)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetRoomURL.make("Markets"))
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .dsText(.widgetSubline12)
            .foregroundStyle(.secondary)
            .lineLimit(3)
    }
}

/// One row: the symbol, then the price and the day's move at the trailing
/// edge. A move that rounds to zero takes no sign and no colour (§83).
private struct WatchlistRow: View {
    let row: WidgetWatchlist.Row
    let quote: (price: Double, change: Double?, at: Date)?

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: row.symbol)
                .dsText(.widgetTitle14)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 2)
            if let quote {
                Text(verbatim: WidgetWatch.priceText(quote.price))
                    .dsText(.widgetSubline12)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let change = quote.change {
                    let pct = change * 100
                    Text(verbatim: MoneyFormat.percentLabel(pct))
                        .dsText(.widgetSubline12)
                        .fontWeight(.semibold)
                        .foregroundStyle(MoneyFormat.isFlatPercent(pct)
                                         ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                                         : AnyShapeStyle(pct > 0 ? WidgetChrome.gain : WidgetChrome.loss))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    private var spoken: String {
        var parts = [row.name]
        if let quote {
            parts.append(WidgetWatch.priceText(quote.price))
            if let change = quote.change { parts.append(MoneyFormat.percentLabel(change * 100)) }
        }
        return parts.joined(separator: ", ")
    }
}
