import WidgetKit
import SwiftUI

/// What you follow in Markets, on the Home Screen (prd §1223, §1242): up to
/// four rows of your watchlist in its own order, as many as the tile holds,
/// each its symbol over the price this app last read, the day's move over the
/// day's line. A small tile only: one tap, and it opens Markets.
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
    private func stamp(_ drawn: ArraySlice<WidgetWatchlist.Row>) -> String? {
        let oldest = drawn.compactMap { WidgetWatch.quote($0, now: entry.date)?.at }.min()
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
                // Four rows of two lines overrun a 158pt tile, so the tile
                // draws as many as it holds, in order, never a row cut short.
                // Spelled out: a `ForEach` here is ONE subview to `ViewThatFits`,
                // and the fit would silently stop working. Four is `rowCap`.
                ViewThatFits(in: .vertical) {
                    list(rows.prefix(4))
                    list(rows.prefix(3))
                    list(rows.prefix(2))
                    list(rows.prefix(1))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetRoomURL.make("Markets"))
    }

    private func list(_ drawn: ArraySlice<WidgetWatchlist.Row>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(drawn, id: \.ref) { row in
                WatchlistRow(row: row, quote: WidgetWatch.quote(row, now: entry.date),
                             spark: WidgetWatch.spark(row, now: entry.date))
            }
            if let stamp = stamp(drawn) {
                Text(stamp)
                    .dsText(.widgetSubline11)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .dsText(.widgetSubline12)
            .foregroundStyle(.secondary)
            .lineLimit(3)
    }
}

/// One row, two lines: the symbol over the price, the day's move over the
/// day's line. The trailing column never truncates; the symbol and the price
/// shrink first, then the symbol cuts. A move that rounds to zero takes no
/// sign and no colour (§83), and its line is grey.
private struct WatchlistRow: View {
    let row: WidgetWatchlist.Row
    let quote: (price: Double, change: Double?, at: Date)?
    /// 0…1, oldest first, or nil (a stock, or no fresh price).
    let spark: [Double]?

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: row.symbol)
                    .dsText(.widgetTitle14)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let quote {
                    Text(verbatim: WidgetWatch.priceText(quote.price))
                        .dsText(.widgetSubline11)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
            if let quote {
                VStack(alignment: .trailing, spacing: 2) {
                    if let change = quote.change {
                        Text(verbatim: MoneyFormat.percentLabel(change * 100))
                            .dsText(.widgetSubline12)
                            .fontWeight(.semibold)
                            .foregroundStyle(tone)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    if let spark {
                        // Solid up, dashed down, as the Markets row's: the
                        // direction survives greyscale and the tinted Home Screen.
                        WidgetSpark(normalized: spark)
                            .stroke(tone, style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                                             lineJoin: .round,
                                                             dash: direction < 0 ? [3, 2] : []))
                            .frame(width: 40, height: 12)
                    }
                }
                .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    /// The day's direction: the move when it was read, else the line's ends.
    /// Zero when it rounds to flat.
    private var direction: Int {
        if let change = quote?.change {
            let pct = change * 100
            return MoneyFormat.isFlatPercent(pct) ? 0 : (pct > 0 ? 1 : -1)
        }
        guard let first = spark?.first, let last = spark?.last, last != first else { return 0 }
        return last > first ? 1 : -1
    }

    private var tone: AnyShapeStyle {
        switch direction {
        case 1: AnyShapeStyle(WidgetChrome.gain)
        case -1: AnyShapeStyle(WidgetChrome.loss)
        default: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
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
