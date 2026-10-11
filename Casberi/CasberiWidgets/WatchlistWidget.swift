import WidgetKit
import SwiftUI
import AppIntents

/// What you follow in Markets, on the Home Screen (prd §1223, §1242, §1250):
/// your watchlist in its own order, or the rows you chose for this tile, each
/// its symbol, the price this app last read, the day's move and the day's
/// line. Small (four two-line rows at most, as many as it holds), medium (six
/// one-line rows with a wider line) and, on the iPhone, the Lock Screen's
/// rectangle (two one-line rows, no line). One tap opens Markets.
///
/// It draws `WidgetWatch.published()`, which the app writes after each read
/// of the watchlist's prices (`WidgetPublish.watchlist`). A price older than
/// an hour is stamped, and one older than a day is not drawn: the symbol
/// stands alone rather than an old price drawn as now's (§83).
struct WatchlistWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetWatch.kind, intent: WatchlistPickIntent.self,
                               provider: WatchlistProvider()) { entry in
            WatchlistWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("Watchlist")
        .description("What you follow in Markets.")
        .supportedFamilies(Self.families)
    }

    /// The small tile, the medium (prd §1250) and, where there is a Lock
    /// Screen, its rectangle.
    static var families: [WidgetFamily] {
        #if targetEnvironment(macCatalyst)
        return [.systemSmall, .systemMedium]
        #else
        return [.systemSmall, .systemMedium, .accessoryRectangular]
        #endif
    }
}

// MARK: - Choosing the rows (prd §1250)

/// A row you follow, as the tile's settings offer it: read from the payload
/// the app published, never from the network or the store.
struct WatchlistRowEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Followed"
    static let defaultQuery = WatchlistRowQuery()

    /// The followed row's `sourceRef`.
    let id: String
    let symbol: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(symbol)", subtitle: "\(name)")
    }

    init(id: String, symbol: String, name: String) {
        self.id = id
        self.symbol = symbol
        self.name = name
    }

    init(_ published: WidgetWatchlist.Row) {
        self.init(id: published.ref, symbol: published.symbol, name: published.name)
    }
}

struct WatchlistRowQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WatchlistRowEntity] {
        let published = WidgetWatch.published()?.rows ?? []
        return identifiers.compactMap { id in
            published.first { $0.ref == id }.map(WatchlistRowEntity.init)
        }
    }

    func suggestedEntities() async throws -> [WatchlistRowEntity] {
        (WidgetWatch.published()?.rows ?? []).map(WatchlistRowEntity.init)
    }
}

/// The tile's one setting: which rows it shows. Nothing chosen is the
/// watchlist in its own order (`WidgetWatch.pick`).
struct WatchlistPickIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Watchlist"
    static let description = IntentDescription("Choose what the tile shows, or nothing for your watchlist in its own order.")

    @Parameter(title: "Show")
    var picks: [WatchlistRowEntity]?

    init() {}
}

struct WatchlistEntry: TimelineEntry {
    let date: Date
    /// nil when the app has published nothing (yet, or for a week).
    let list: WidgetWatchlist?
    /// The refs this tile was set to show, in the order chosen; empty for
    /// the watchlist's own order.
    var picks: [String] = []
}

struct WatchlistProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WatchlistEntry {
        WatchlistEntry(date: .now, list: nil)
    }

    func snapshot(for configuration: WatchlistPickIntent, in context: Context) async -> WatchlistEntry {
        WatchlistEntry(date: .now, list: WidgetWatch.published(), picks: Self.refs(configuration))
    }

    func timeline(for configuration: WatchlistPickIntent, in context: Context) async -> Timeline<WatchlistEntry> {
        // The app reloads this kind whenever the prices change; the timeline
        // asks again within the hour only so the stamp and the day's cutoff
        // land on time.
        let now = Date.now
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now
        return Timeline(entries: [WatchlistEntry(date: now, list: WidgetWatch.published(now: now),
                                                 picks: Self.refs(configuration))],
                        policy: .after(next))
    }

    private static func refs(_ configuration: WatchlistPickIntent) -> [String] {
        (configuration.picks ?? []).map(\.id)
    }
}

struct WatchlistWidgetView: View {
    let entry: WatchlistEntry
    @Environment(\.widgetFamily) private var family

    /// The rows this tile shows, before the family takes its few.
    private var chosen: [WidgetWatchlist.Row] {
        WidgetWatch.pick(entry.list?.rows ?? [], refs: entry.picks)
    }

    private var rows: [WidgetWatchlist.Row] {
        Array(chosen.prefix(WidgetWatch.rowCap))
    }

    private var isAccessory: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return family == .accessoryRectangular
        #endif
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
        Group {
            if isAccessory {
                accessory
            } else if family == .systemMedium {
                tile(wide: true)
            } else {
                tile(wide: false)
            }
        }
        .widgetURL(WidgetRoomURL.make("Markets"))
    }

    private func tile(wide: Bool) -> some View {
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
            } else if chosen.isEmpty {
                line(String(localized: "Follow a company in Markets"))
            } else if wide {
                // One line a row (prd §1250): six at most, as many as the
                // tile holds, never a row cut short. Spelled out for
                // `ViewThatFits`'s sake, as the small tile's are.
                let all = Array(chosen.prefix(WidgetWatch.mediumCap))
                ViewThatFits(in: .vertical) {
                    lines(all.prefix(6), spark: true)
                    lines(all.prefix(5), spark: true)
                    lines(all.prefix(4), spark: true)
                    lines(all.prefix(3), spark: true)
                    lines(all.prefix(2), spark: true)
                    lines(all.prefix(1), spark: true)
                }
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
    }

    /// The Lock Screen's rectangle (prd §1250): two one-line rows at most, no
    /// line (it does not fit beside a price there), the stamp when owed.
    @ViewBuilder private var accessory: some View {
        let all = Array(chosen.prefix(WidgetWatch.accessoryCap))
        if entry.list == nil || all.isEmpty {
            Text(entry.list == nil ? String(localized: "Open Casberi to see your watchlist")
                                   : String(localized: "Follow a company in Markets"))
                .dsText(.widgetSubline12)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ViewThatFits(in: .vertical) {
                lines(all.prefix(2), spark: false)
                lines(all.prefix(1), spark: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func list(_ drawn: ArraySlice<WidgetWatchlist.Row>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(drawn, id: \.ref) { row in
                WatchlistRow(row: row, quote: WidgetWatch.quote(row, now: entry.date),
                             spark: WidgetWatch.spark(row, now: entry.date))
            }
            stampLine(drawn)
        }
    }

    private func lines(_ drawn: ArraySlice<WidgetWatchlist.Row>, spark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(drawn, id: \.ref) { row in
                WatchlistLineRow(row: row, quote: WidgetWatch.quote(row, now: entry.date),
                                 spark: spark ? WidgetWatch.spark(row, now: entry.date) : nil)
            }
            stampLine(drawn)
        }
    }

    @ViewBuilder private func stampLine(_ drawn: ArraySlice<WidgetWatchlist.Row>) -> some View {
        if let stamp = stamp(drawn) {
            Text(stamp)
                .dsText(.widgetSubline11)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .dsText(.widgetSubline12)
            .foregroundStyle(.secondary)
            .lineLimit(3)
    }
}

/// One row on one line (prd §1250), for the medium tile and the Lock Screen:
/// the symbol, then the price, the day's line when there is room for it, and
/// the move. The move never cuts; the symbol and the price shrink first.
private struct WatchlistLineRow: View {
    let row: WidgetWatchlist.Row
    let quote: (price: Double, change: Double?, at: Date)?
    /// 0…1, oldest first, or nil (no line, no fresh price, or no room).
    let spark: [Double]?

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(verbatim: row.symbol)
                .dsText(.widgetTitle14)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            if let quote {
                Text(verbatim: WidgetWatch.priceText(quote.price))
                    .dsText(.widgetSubline12)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let spark {
                    WidgetSpark(normalized: spark)
                        .stroke(WatchTone.style(direction),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round,
                                                   dash: direction < 0 ? [3, 2] : []))
                        .frame(width: 56, height: 14)
                }
                if let change = quote.change {
                    Text(verbatim: MoneyFormat.percentLabel(change * 100))
                        .dsText(.widgetSubline12)
                        .fontWeight(.semibold)
                        .foregroundStyle(WatchTone.style(direction))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: WatchTone.spoken(name: row.name, quote: quote)))
    }

    private var direction: Int { WatchTone.direction(change: quote?.change, spark: spark) }
}

/// A row's direction and its ink, one rule for both row shapes: the move
/// when it was read, else the line's ends; zero when it rounds to flat (§83).
private enum WatchTone {
    static func direction(change: Double?, spark: [Double]?) -> Int {
        if let change {
            let pct = change * 100
            return MoneyFormat.isFlatPercent(pct) ? 0 : (pct > 0 ? 1 : -1)
        }
        guard let first = spark?.first, let last = spark?.last, last != first else { return 0 }
        return last > first ? 1 : -1
    }

    static func style(_ direction: Int) -> AnyShapeStyle {
        switch direction {
        case 1: AnyShapeStyle(WidgetChrome.gain)
        case -1: AnyShapeStyle(WidgetChrome.loss)
        default: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    static func spoken(name: String, quote: (price: Double, change: Double?, at: Date)?) -> String {
        var parts = [name]
        if let quote {
            parts.append(WidgetWatch.priceText(quote.price))
            if let change = quote.change { parts.append(MoneyFormat.percentLabel(change * 100)) }
        }
        return parts.joined(separator: ", ")
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
    /// Zero when it rounds to flat (`WatchTone`, one rule for both rows).
    private var direction: Int { WatchTone.direction(change: quote?.change, spark: spark) }

    private var tone: AnyShapeStyle { WatchTone.style(direction) }

    private var spoken: String { WatchTone.spoken(name: row.name, quote: quote) }
}
