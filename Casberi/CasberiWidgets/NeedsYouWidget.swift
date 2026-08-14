import WidgetKit
import SwiftUI

/// What wants something from you (2026-08-14, prd §382).
///
/// WHY THIS IS THE MOST USEFUL TILE HERE. `dueAt` is the one field in this
/// corpus that carries an obligation — a dispute's evidence deadline, a
/// TestFlight build about to expire, an Aerodrome vote window, a 1Claw grant, a
/// reminder, an ENS name — and since the Home board and its "Coming up" card
/// retired (§131) the app has had NO surface that announces one. §131 settled
/// that deliberately: "a chip you ask beats a card that announces". A Home
/// Screen widget is neither. It is a thing you chose to place, which is the one
/// arrangement where announcing is something you asked for.
///
/// It never says how many things landed (§213) — but it does count DEADLINES,
/// and the distinction is worth stating because it looks like the same thing.
/// §213 retired VOLUME claims: "people do not care how many things landed,
/// because we have dozens a day". A count of open obligations is not volume, it
/// is workload, and the app already speaks in exactly those terms — `overdue`'s
/// own reading is literally "3 things late".
struct NeedsYouWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetDeadlines.kind, provider: NeedsYouProvider()) { entry in
            NeedsYouWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("Needs you")
        .description("Deadlines, soonest first.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular])
    }
}

struct NeedsYouEntry: TimelineEntry {
    let date: Date
    let rows: [WidgetDeadline]

    var overdue: [WidgetDeadline] { rows.filter { $0.isOverdue(now: date) } }

    /// Something already late outranks something merely coming; an empty tile
    /// asks for no slot at all. The Smart Stack rule the hero established
    /// (§282), applied to the one payload where lateness is objective.
    var relevance: TimelineEntryRelevance? {
        if rows.isEmpty { return TimelineEntryRelevance(score: 0) }
        return TimelineEntryRelevance(score: overdue.isEmpty ? 45 : 95)
    }
}

struct NeedsYouProvider: TimelineProvider {
    func placeholder(in context: Context) -> NeedsYouEntry {
        NeedsYouEntry(date: .now, rows: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (NeedsYouEntry) -> Void) {
        completion(NeedsYouEntry(date: .now, rows: WidgetDeadlines.published()))
    }

    /// The refresh clock is the DEADLINES THEMSELVES, not a fixed hour.
    ///
    /// This tile's whole content is a set of before/after states, and every one
    /// of them flips at a moment we know in advance. Reloading hourly would
    /// leave a row reading "ahead" for up to an hour after it went late — on the
    /// one surface whose entire job is to say which of those two it is. So the
    /// entry is valid exactly until the next deadline passes, and the hour is
    /// only the ceiling for when nothing is pending.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NeedsYouEntry>) -> Void) {
        let now = Date.now
        let rows = WidgetDeadlines.published(now: now)
        let hourly = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        // `> now` and not `>= now`: a deadline exactly at this instant has
        // already flipped, and asking to be woken for it again would schedule a
        // reload in the past.
        let nextFlip = rows.map(\.due).filter { $0 > now }.min()
        let next = min(nextFlip ?? hourly, hourly)
        completion(Timeline(entries: [NeedsYouEntry(date: now, rows: rows)], policy: .after(next)))
    }
}

struct NeedsYouWidgetView: View {
    let entry: NeedsYouEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { WidgetChrome.accent }
    private var rows: [WidgetDeadline] { entry.rows }
    private var overdueCount: Int { entry.overdue.count }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                // A gauge whose fill is the OVERDUE share of what's open. It
                // draws nothing at all when nothing is due, rather than an empty
                // ring that reads as a broken tile.
                Gauge(value: rows.isEmpty ? 0 : Double(overdueCount) / Double(rows.count)) {
                    Image(systemName: "clock").dsGlyph(11)
                } currentValueLabel: {
                    Text("\(rows.count)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .accessibilityLabel(Text("Deadlines"))
            case .accessoryRectangular:
                if let first = rows.first {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(headline).dsText(.widgetEyebrow11).widgetAccentable()
                        Text(first.title).dsText(.widgetTitle14).lineLimit(1)
                        Text(first.due, style: .relative)
                            .dsText(.widgetSubline11).opacity(0.75).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Nothing due").dsText(.widgetTitle14)
                }
            case .systemSmall:
                VStack(alignment: .leading, spacing: 6) {
                    WidgetLabel(text: String(localized: "Needs you"))
                    if let first = rows.first {
                        Text(headline)
                            .dsText(.widgetTitle17)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        // The small family names the SOONEST one rather than
                        // listing: three truncated titles at this width say less
                        // than one whole one.
                        VStack(alignment: .leading, spacing: 1) {
                            Text(first.title)
                                .dsText(.widgetRecentTitle12)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(first.due, style: .relative)
                                .dsText(.widgetSubline11)
                                .foregroundStyle(first.isOverdue(now: entry.date)
                                                 ? accent : .white.opacity(0.6))
                                .lineLimit(1)
                                .monospacedDigit()
                        }
                    } else {
                        emptyLine
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        WidgetLabel(text: String(localized: "Needs you"))
                        Spacer(minLength: 4)
                        if !rows.isEmpty {
                            Text(headline)
                                .dsText(.widgetSubline11)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    if rows.isEmpty {
                        emptyLine
                        Spacer(minLength: 0)
                    } else {
                        // The rail, above the rows it summarises (2026-08-14,
                        // prd §382 amendment). Four rows say what the next four
                        // things are; the rail says the SHAPE — two behind you,
                        // three ahead, and roughly how far — which is a reading
                        // a list cannot give at any size. It draws every
                        // published deadline, not just the ones listed below,
                        // so the tile stops being a window onto its own top
                        // three.
                        HeroRunway(dates: rows.map(\.due), now: entry.date, accent: accent)
                        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 7) {
                            ForEach(Array(rows.prefix(family == .systemLarge ? 3 : 2)),
                                    id: \.id) { row in
                                Link(destination: URL(string: "casberi://thing/\(row.id)")!) {
                                    WidgetDueRow(row: row, showsSource: family == .systemLarge)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        // The tile as a whole opens the ask that IS this tile — the same
        // standing question the app answers as "what's coming up", so tapping
        // the header lands on the full list rather than the feed.
        .widgetURL(WidgetAskLink.url(asking: askQuery))
    }

    /// "2 late" / "3 coming up" — the overdue count leads whenever there is
    /// one, because late and soon are different states and only one of them is
    /// already a problem.
    private var headline: String {
        if overdueCount > 0 {
            return overdueCount == 1 ? String(localized: "1 late")
                                     : String(localized: "\(overdueCount) late")
        }
        return rows.count == 1 ? String(localized: "1 coming up")
                               : String(localized: "\(rows.count) coming up")
    }

    private var emptyLine: some View {
        // A true statement, not a celebration: this reads the same on a corpus
        // with no dated rows at all, and "You're all caught up!" would be
        // congratulating someone for connecting nothing.
        Text("Nothing due")
            .dsText(.widgetTitle17)
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(2)
    }

    /// DELIBERATELY NOT LOCALIZED, and this is the one place in the file where
    /// that is the correct call rather than an oversight.
    ///
    /// The query is not copy — it is a TRIGGER. `KeptAskComposers.matchesUpcoming`
    /// recognizes this ask by English substrings (`"coming up"`, `"due soon"`),
    /// as every recognizer in the composer does. A localized query would be a
    /// well-formed sentence that no composer matches, so on any non-English
    /// device this tile's tap would quietly fall through to a generic answer
    /// instead of the deadline list it is showing — a dead control that looks
    /// alive, and one nothing in a build or a screen sweep could see.
    ///
    /// The composer shows the words it was handed, so they appear in English
    /// there. That is a visible, honest limitation of an English-only
    /// recognizer, and strictly better than a tap that does the wrong thing.
    private var askQuery: String { "what's coming up" }
}
