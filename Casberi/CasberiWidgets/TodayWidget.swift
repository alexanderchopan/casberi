import WidgetKit
import SwiftUI
import SwiftData
import UIKit

/// Today (prd §877) — "Your day" and "Needs you" as ONE tile, with the replies
/// to your posts and GitHub's review requests folded in.
///
/// Why one: "Your day" showed one line item and "Needs you" read "Nothing due"
/// on most phones (user, 2026-09-22: "they could likely be combined"). One
/// list, in the order each thing is already a problem — what wants you, then
/// who answered you, then what landed — is full on a quiet day and never a
/// single line. The ordering is `WidgetTodayPlan.make`, in `Shared/`, where the
/// harness can drive it; this file only draws it.
///
/// Every lead is a PICTURE: a brand mark or a face the app wrote into the app
/// group (`WidgetImages`), since the widget can reach neither the asset catalog
/// nor a URL. A picture that has not arrived yet draws a monogram, never a hole.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        // The hero's kind, so a "Your day" tile already placed becomes this one.
        StaticConfiguration(kind: WidgetToday.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetField() }
        }
        .configurationDisplayName("Today")
        .description("What needs you, who replied, and what landed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    var deadlines: [WidgetDeadline] = []
    var safe: WidgetSafeCall?
    var requests: [WidgetRequest] = []
    var people = WidgetPeople(replies: [], likes: nil)
    var landed: [WidgetLanded] = []

    func plan(capacity: Int) -> WidgetTodayPlan {
        WidgetTodayPlan.make(deadlines: deadlines, safe: safe, requests: requests,
                             people: people, landed: landed, capacity: capacity, now: date)
    }

    /// Late or a blocked signature is pressing; anything else that wants you is
    /// worth a lift; people answering you a little less; an empty tile nothing.
    var relevance: TimelineEntryRelevance? {
        let p = plan(capacity: 4)
        if p.isEmpty { return TimelineEntryRelevance(score: 0) }
        if p.late > 0 || (safe?.awaitsYou ?? 0) > 0 { return TimelineEntryRelevance(score: 95) }
        if p.rows.contains(where: { $0.section == .needs }) { return TimelineEntryRelevance(score: 60) }
        if p.rows.contains(where: { $0.section == .people }) { return TimelineEntryRelevance(score: 45) }
        return TimelineEntryRelevance(score: 10)
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(load(now: .now))
    }

    /// Entries every quarter hour, plus one at each deadline's own moment, so
    /// "12m" does not read "12m" for an hour and a row flips to late when it
    /// goes late — the Needs-you clock rule, kept.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let base = load(now: now)
        let hour = now.addingTimeInterval(3600)
        let flips = base.deadlines.map(\.due).filter { $0 > now && $0 < hour }
        let quarters = (1..<4).map { now.addingTimeInterval(Double($0) * 900) }
        let dates = ([now] + quarters + flips).sorted()
        let entries = dates.map { date in
            TodayEntry(date: date, deadlines: base.deadlines, safe: base.safe,
                       requests: base.requests, people: base.people, landed: base.landed)
        }
        completion(Timeline(entries: entries, policy: .after(hour)))
    }

    private func load(now: Date) -> TodayEntry {
        TodayEntry(date: now,
                   deadlines: WidgetDeadlines.published(now: now),
                   safe: WidgetSafe.published(now: now),
                   requests: WidgetToday.requests(now: now),
                   people: WidgetToday.people(now: now),
                   landed: landed())
    }

    /// The newest things, straight from the store, so one saved while the app
    /// is closed still reaches the tile. Values are copied out at once — no
    /// model reference outlives this function (the liveness rule).
    private func landed() -> [WidgetLanded] {
        guard let container = try? SharedStore.extensionContainer() else { return [] }
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.propertiesToFetch = [\.id, \.title, \.source, \.capturedAt, \.authorAvatarURL]
        descriptor.fetchLimit = 8
        guard let rows = try? ModelContext(container).fetch(descriptor) else { return [] }
        return rows.map {
            WidgetLanded(id: $0.id.uuidString, title: $0.title, source: $0.source,
                         at: $0.capturedAt,
                         face: $0.authorAvatarURL.flatMap { $0.isEmpty ? nil : WidgetImages.faceKey(url: $0) })
        }
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { WidgetChrome.accent }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemSmall: small
            case .systemLarge: list(capacity: 8, large: true)
            default: list(capacity: 4, large: false)
            }
        }
        .widgetURL(URL(string: "casberi://feed"))
    }

    // MARK: - Home Screen

    private var small: some View {
        let plan = entry.plan(capacity: 4)
        let lead = plan.rows.first
        return VStack(alignment: .leading, spacing: 4) {
            header(plan, large: false)
            if let lead {
                Text(TodayWords.title(lead))
                    .dsText(.widgetTitle17)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.top, 2)
                let clock = TodayWords.clock(lead.clock, now: entry.date)
                Text(clock.text)
                    .dsText(.widgetSubline11)
                    .foregroundStyle(clock.tone.color(accent: accent))
                    .lineLimit(1)
            } else if let next = plan.next {
                Text("Nothing due this week")
                    .dsText(.widgetTitle17)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                Text(TodayWords.next(next))
                    .dsText(.widgetSubline11)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            } else {
                empty(plan)
            }
            Spacer(minLength: 0)
            if !plan.faces.isEmpty {
                FacePile(keys: plan.faces, size: 26)
                Text(TodayWords.repliers(plan.repliers))
                    .dsText(.widgetSubline11)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            } else if plan.rows.count > 1 {
                // Nobody replied today: the next two rows, lead and words only,
                // so the tile is never one line and a blank (seen on the sim).
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(plan.rows.dropFirst().prefix(2).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 6) {
                            LeadImage(lead: row.lead, size: 16)
                            Text(TodayWords.title(row))
                                .dsText(.widgetSubline11)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                }
            } else if let next = plan.next, lead != nil {
                Text(TodayWords.next(next))
                    .dsText(.widgetSubline11)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func list(capacity: Int, large: Bool) -> some View {
        let plan = entry.plan(capacity: capacity)
        let sections: [(WidgetTodayRow.Section, [WidgetTodayRow])] =
            [WidgetTodayRow.Section.needs, .people, .landed].compactMap { section in
                let rows = plan.rows.filter { $0.section == section }
                return rows.isEmpty ? nil : (section, rows)
            }
        return VStack(alignment: .leading, spacing: large ? 8 : 7) {
            header(plan, large: large)
            if large, !entry.deadlines.isEmpty {
                TodayRunway(dates: entry.deadlines.map(\.due), now: entry.date, accent: accent)
            }
            if let next = plan.next {
                Text(TodayWords.next(next))
                    .dsText(.widgetSubline11)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            if plan.rows.isEmpty, plan.next == nil { empty(plan) }
            ForEach(Array(sections.enumerated()), id: \.offset) { index, part in
                VStack(alignment: .leading, spacing: large ? 8 : 7) {
                    // Only the large tile names its sections below the first;
                    // the medium one separates them with air alone.
                    if large, part.0 != .needs {
                        Text(TodayWords.sectionName(part.0, rows: part.1))
                            .dsText(.widgetSubline11)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    ForEach(Array(part.1.enumerated()), id: \.offset) { _, row in
                        TodayRowView(row: row, now: entry.date, accent: accent)
                    }
                }
                .padding(.top, index == 0 ? 0 : (large ? 4 : 3))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ plan: WidgetTodayPlan, large: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            WidgetLabel(text: String(localized: "Today"))
            Spacer(minLength: 4)
            if let summary = TodayWords.summary(plan) {
                Text(summary)
                    .dsText(.widgetSubline11)
                    .foregroundStyle(plan.late > 0 ? WidgetChrome.loss : .white.opacity(0.6))
                    .lineLimit(1)
            } else if large {
                Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .dsText(.widgetSubline11)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func empty(_ plan: WidgetTodayPlan) -> some View {
        // A true statement, not a celebration — the Needs-you rule.
        Text("Nothing yet today")
            .dsText(.widgetTitle17)
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(2)
    }

    // MARK: - Lock Screen

    private var rectangular: some View {
        let plan = entry.plan(capacity: 2)
        return VStack(alignment: .leading, spacing: 1) {
            Text(TodayWords.summary(plan) ?? String(localized: "Today"))
                .dsText(.widgetEyebrow11)
                .widgetAccentable()
                .lineLimit(1)
            if let first = plan.rows.first {
                Text(TodayWords.title(first)).dsText(.widgetTitle14).lineLimit(1)
                if let second = plan.rows.dropFirst().first {
                    Text("then \(TodayWords.title(second)) · \(TodayWords.clock(second.clock, now: entry.date).text)")
                        .dsText(.widgetSubline11).opacity(0.75).lineLimit(1)
                } else {
                    Text(TodayWords.clock(first.clock, now: entry.date).text)
                        .dsText(.widgetSubline11).opacity(0.75).lineLimit(1)
                }
            } else if let next = plan.next {
                Text(TodayWords.next(next)).dsText(.widgetTitle14).lineLimit(2)
            } else {
                Text("Nothing yet today").dsText(.widgetTitle14).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The most pressing thing: whose it is and how late — no ring, because a
    /// ring's fill would have to mean something and a count of open items is
    /// not a fraction of anything (user, 2026-09-22).
    private var circular: some View {
        let plan = entry.plan(capacity: 1)
        return ZStack {
            AccessoryWidgetBackground()
            if let first = plan.rows.first {
                VStack(spacing: 2) {
                    LeadImage(lead: first.lead, size: 24)
                    Text(TodayWords.clock(first.clock, now: entry.date).text)
                        .dsText(.widgetEyebrow11)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                }
            } else {
                Image(systemName: "checkmark")
                    .dsGlyph(.title, weight: .semibold)
            }
        }
        .accessibilityLabel(Text("Today"))
    }

    private var inline: some View {
        let plan = entry.plan(capacity: 1)
        if let first = plan.rows.first {
            return Text("\(TodayWords.title(first)) · \(TodayWords.clock(first.clock, now: entry.date).text)")
        }
        return Text("Nothing yet today")
    }
}

/// One row: the lead, the words, the clock. One anatomy for every section —
/// a deadline, a signature, a reply and a thing that landed differ only in
/// what fills the three slots.
private struct TodayRowView: View {
    let row: WidgetTodayRow
    let now: Date
    let accent: Color

    var body: some View {
        let clock = TodayWords.clock(row.clock, now: now)
        let line = HStack(spacing: 8) {
            LeadImage(lead: row.lead, size: 20)
            Text(TodayWords.title(row))
                .dsText(.widgetLabel12)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(clock.text)
                .dsText(.widgetSubline11)
                .foregroundStyle(clock.tone.color(accent: accent))
                .lineLimit(1)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        if let id = row.id, let url = URL(string: "casberi://thing/\(id)") {
            Link(destination: url) { line }
        } else {
            line
        }
    }
}

/// A mark (rounded square) or a face (circle), read from the app group, or a
/// monogram when the picture has not been written yet.
private struct LeadImage: View {
    let lead: WidgetTodayRow.Lead
    let size: CGFloat

    var body: some View {
        let (key, round, name): (String, Bool, String) = {
            switch lead {
            case .mark(let source): return (WidgetImages.markKey(source: source), false, source)
            case .face(let key, let source): return (key, true, source)
            }
        }()
        let shape = round ? AnyShape(Circle())
                          : AnyShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        Group {
            if let url = WidgetImages.file(key), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.18))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }
}

/// The small tile's pile of reply faces, newest in front.
private struct FacePile: View {
    let keys: [String]
    let size: CGFloat

    var body: some View {
        HStack(spacing: -size * 0.27) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                LeadImage(lead: .face(key: key, source: ""), size: size)
                    .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                    .zIndex(Double(keys.count - index))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The deadlines on a rail, above the rows (large only). The geometry — and
/// the invariant that the window always CONTAINS now — is `WidgetRunway`.
private struct TodayRunway: View {
    let dates: [Date]
    let now: Date
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            if let placed = WidgetRunway.positions(for: dates, now: now) {
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 2)
                        .offset(y: 8)
                    // A bar, not a dot: it is where you are standing, not one
                    // of the things on the rail.
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 2, height: 14)
                        .offset(x: width * placed.now - 1, y: 2)
                    ForEach(Array(placed.dots.enumerated()), id: \.offset) { index, position in
                        Circle()
                            .fill(dates[index] < now ? WidgetChrome.loss : accent)
                            .frame(width: 8, height: 8)
                            .offset(x: width * position - 4, y: 5)
                    }
                }
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

/// Every word the tile says, in one place, so the rows, the small tile and
/// the lock screen word one row the same way.
enum TodayWords {
    enum Tone {
        case plain, late, asking
        func color(accent: Color) -> Color {
            switch self {
            case .plain: return .white.opacity(0.6)
            case .late: return WidgetChrome.loss
            case .asking: return accent
            }
        }
    }

    static func title(_ row: WidgetTodayRow) -> String {
        switch row.kind {
        case .signature(let count):
            return count > 1 ? String(localized: "Sign \(count): \(row.title)")
                             : String(localized: "Sign: \(row.title)")
        case .reply(let who):
            return "\(who): \(row.title)"
        case .deadline, .request, .likes, .landed:
            return row.title
        }
    }

    /// Short everywhere ("2h late", "in 1d 6h", "12m"): the clock sits
    /// beside a title and must never be the thing that truncates it.
    static func clock(_ clock: WidgetTodayRow.Clock, now: Date) -> (text: String, tone: Tone) {
        switch clock {
        case .due(let date):
            if date < now {
                let span = short(WidgetSpan(now.timeIntervalSince(date)))
                return (String(localized: "\(span) late"), .late)
            }
            return (String(localized: "in \(short(WidgetSpan(date.timeIntervalSince(now))))"), .plain)
        case .waiting(let days):
            guard let days, days > 0 else { return (String(localized: "waiting"), .asking) }
            return (String(localized: "waiting \(days)d"), .asking)
        case .asked(let date):
            return (String(localized: "asked \(short(WidgetSpan(now.timeIntervalSince(date))))"), .asking)
        case .at(let date):
            return (short(WidgetSpan(now.timeIntervalSince(date))), .plain)
        }
    }

    static func short(_ span: WidgetSpan) -> String {
        if span.days > 0 {
            return span.hours > 0 ? String(localized: "\(span.days)d \(span.hours)h")
                                  : String(localized: "\(span.days)d")
        }
        if span.hours > 0 { return String(localized: "\(span.hours)h") }
        return String(localized: "\(span.minutes)m")
    }

    /// "1 late · 1 to sign" — only the states that are a problem; nil when
    /// nothing is, and the quiet tile says so with its "Next" line instead.
    static func summary(_ plan: WidgetTodayPlan) -> String? {
        var parts: [String] = []
        if plan.late > 0 { parts.append(String(localized: "\(plan.late) late")) }
        if plan.toSign > 0 { parts.append(String(localized: "\(plan.toSign) to sign")) }
        if parts.isEmpty, plan.next != nil { return String(localized: "nothing due this week") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Replies" only over rows that include a reply; a likes-only section
    /// is "Likes" (seen on the sim: "Replies" over one like roll).
    static func sectionName(_ section: WidgetTodayRow.Section, rows: [WidgetTodayRow]) -> String {
        switch section {
        case .needs: return String(localized: "Needs you")
        case .landed: return String(localized: "Landed")
        case .people:
            let replies = rows.contains { if case .reply = $0.kind { return true } else { return false } }
            return replies ? String(localized: "Replies") : String(localized: "Likes")
        }
    }

    static func next(_ deadline: WidgetDeadline) -> String {
        let day = deadline.due.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "Next: \(deadline.title) · \(day)")
    }

    /// "ana, mia +2 replied" — names, never a bare count (§330).
    static func repliers(_ names: [String]) -> String {
        var unique: [String] = []
        for name in names where !unique.contains(name) { unique.append(name) }
        switch unique.count {
        case 0: return ""
        case 1: return String(localized: "\(unique[0]) replied")
        case 2: return String(localized: "\(unique[0]), \(unique[1]) replied")
        default: return String(localized: "\(unique[0]), \(unique[1]) +\(unique.count - 2) replied")
        }
    }
}
