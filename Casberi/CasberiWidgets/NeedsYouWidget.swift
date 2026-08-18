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
    /// A signature somebody is blocked on (2026-08-17). Not a row: it has no
    /// due date and must never be drawn on the dated rail — see `WidgetSafeCall`.
    var safe: WidgetSafeCall?

    var overdue: [WidgetDeadline] { rows.filter { $0.isOverdue(now: date) } }

    /// Everything on this tile, deadline or not. The tile's subject is things
    /// that want something from you, and a queue item awaiting your signature
    /// is one of them — so a corpus with nothing dated and one signature
    /// pending must not read "Nothing due", which is what it did before this
    /// payload existed.
    var isEmpty: Bool { rows.isEmpty && (safe?.awaitsYou ?? 0) == 0 }

    /// Something already late outranks something merely coming; an empty tile
    /// asks for no slot at all. The Smart Stack rule the hero established
    /// (§282), applied to the one payload where lateness is objective.
    ///
    /// A pending signature scores as PRESSING rather than merely open, and
    /// that is a definition and not an inference about a date: the state means
    /// a co-signer's transaction cannot proceed until you act.
    var relevance: TimelineEntryRelevance? {
        if isEmpty { return TimelineEntryRelevance(score: 0) }
        let pressing = !overdue.isEmpty || (safe?.awaitsYou ?? 0) > 0
        return TimelineEntryRelevance(score: pressing ? 95 : 45)
    }
}

struct NeedsYouProvider: TimelineProvider {
    func placeholder(in context: Context) -> NeedsYouEntry {
        NeedsYouEntry(date: .now, rows: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (NeedsYouEntry) -> Void) {
        completion(NeedsYouEntry(date: .now, rows: WidgetDeadlines.published(),
                                 safe: WidgetSafe.published()))
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
        let safe = WidgetSafe.published(now: now)
        let hourly = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        // `> now` and not `>= now`: a deadline exactly at this instant has
        // already flipped, and asking to be woken for it again would schedule a
        // reload in the past.
        let nextFlip = rows.map(\.due).filter { $0 > now }.min()
        let next = min(nextFlip ?? hourly, hourly)
        // The Safe call needs no flip time of its own: it carries no date, and
        // its own six-hour shelf life is enforced on READ, so the hourly
        // ceiling already re-asks well inside it.
        completion(Timeline(entries: [NeedsYouEntry(date: now, rows: rows, safe: safe)],
                            policy: .after(next)))
    }
}

struct NeedsYouWidgetView: View {
    let entry: NeedsYouEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { WidgetChrome.accent }
    private var rows: [WidgetDeadline] { entry.rows }
    private var overdueCount: Int { entry.overdue.count }
    /// The call, only when it actually asks for something. A payload whose
    /// `awaitsYou` has fallen to zero is a stale reading, not a quiet one.
    private var call: WidgetSafeCall? {
        guard let safe = entry.safe, safe.awaitsYou > 0 else { return nil }
        return safe
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                // A gauge whose fill is the PRESSING share of what's open. It
                // draws nothing at all when nothing is due, rather than an empty
                // ring that reads as a broken tile. A pending signature counts
                // in both numerator and denominator: it is open, and it is
                // pressing by definition (see `NeedsYouEntry.relevance`).
                Gauge(value: openCount == 0 ? 0 : Double(pressingCount) / Double(openCount)) {
                    Image(systemName: "clock").dsGlyph(11)
                } currentValueLabel: {
                    Text("\(openCount)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .accessibilityLabel(Text("Needs you"))
            case .accessoryRectangular:
                // The signature leads this family outright rather than sharing
                // it: there is room for one thing, and the one thing a person
                // is blocked on beats the one with a date on it.
                if let call {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(headline).dsText(.widgetEyebrow11).widgetAccentable()
                        Text(call.subject).dsText(.widgetTitle14).lineLimit(1)
                        Text(waitLine(call)).dsText(.widgetSubline11).opacity(0.75).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let first = rows.first {
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
                    if let call {
                        Text(headline)
                            .dsText(.widgetTitle17)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(call.subject)
                                .dsText(.widgetRecentTitle12)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(waitLine(call))
                                .dsText(.widgetSubline11)
                                .foregroundStyle(accent)
                                .lineLimit(1)
                        }
                    } else if let first = rows.first {
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
                        if !entry.isEmpty {
                            Text(headline)
                                .dsText(.widgetSubline11)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    // ABOVE the rail, and never on it. The rail is a time axis
                    // and this has no time on it; placing it there would need
                    // an invented date, which would then draw as late or early
                    // — a claim nobody made.
                    if let call { signatureCall(call) }
                    if rows.isEmpty {
                        if call == nil { emptyLine }
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

    /// The signature request, drawn as a banner rather than a row.
    ///
    /// It links to the pending transaction when the corpus has it, and to the
    /// tile's own ask when it doesn't — never to `casberi://thing/` with an id
    /// we don't have, which is a door onto nothing.
    @ViewBuilder
    private func signatureCall(_ call: WidgetSafeCall) -> some View {
        let content = HStack(alignment: .top, spacing: 6) {
            Image(systemName: "signature")
                .dsGlyph(11, weight: .semibold)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(call.awaitsYou == 1
                     ? String(localized: "Your signature is needed")
                     : String(localized: "Your signature is needed on \(call.awaitsYou)"))
                    .dsText(.widgetRecentTitle12)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(call.subject)
                    .dsText(.widgetSubline11)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        if let id = call.id, let url = URL(string: "casberi://thing/\(id)") {
            Link(destination: url) { content }
        } else {
            content
        }
    }

    /// "waiting 5 days" / "waiting" — never "waiting 0 days". A submission
    /// date the wire didn't carry is unknown, not today.
    private func waitLine(_ call: WidgetSafeCall) -> String {
        guard let days = call.waitingDays, days > 0 else { return String(localized: "waiting") }
        return days == 1 ? String(localized: "waiting 1 day")
                         : String(localized: "waiting \(days) days")
    }

    /// Everything open on this tile, dated or not.
    private var openCount: Int { rows.count + (call?.awaitsYou ?? 0) }
    /// The subset that is already someone else's problem waiting on you.
    private var pressingCount: Int { overdueCount + (call?.awaitsYou ?? 0) }

    /// "2 late" / "1 to sign" / "3 coming up" — ranked by how much each state
    /// is already a problem. A signature outranks a future deadline (somebody
    /// is blocked right now) and sits below something already late.
    private var headline: String {
        if overdueCount > 0 {
            return overdueCount == 1 ? String(localized: "1 late")
                                     : String(localized: "\(overdueCount) late")
        }
        if let call {
            return call.awaitsYou == 1 ? String(localized: "1 to sign")
                                       : String(localized: "\(call.awaitsYou) to sign")
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
