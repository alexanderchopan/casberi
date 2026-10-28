import SwiftUI

/// The one head the thing sheets share (prd §892): a face, the name of who or
/// what it is from, the day in the divider's pink on the name's line, and a
/// quiet line under it saying what it is. The post, money and devnet-event
/// heads (§884, §887, §891) drew this shape on their own; the kinds after them
/// compose it from here, so the next one cannot drift.
///
/// **The day is the divider's word** (`FeedScreen.dayWord`, §882) — never an
/// age — and this is its only brand ink (`day-divider-audit.py` check 5).
struct SheetPartyHead<Face: View>: View {
    let name: String
    let day: Date?
    let line: String?
    /// The clock beside the day (prd §1397); off where the day is the fact.
    var clock: Bool = true
    /// The face's door, where it has one (a person's profile, a room).
    var onFace: (() -> Void)? = nil
    @ViewBuilder let face: () -> Face

    /// **CENTRED, THREE THINGS (prd §1397, user: "give mail, post, event,
    /// contact and the other thing sheets the same centred head").** The
    /// face at `DS.Face.sheet`, the name at the head rung, one grey line —
    /// what it is and when, the day in the divider's ink with the clock
    /// beside it — as the money sheet's head stands (§1396). The title row
    /// and the box that stood over every other kind said the name twice.
    var body: some View {
        VStack(spacing: DS.Space.s3) {
            if let onFace {
                Button {
                    DSHaptic.tap()
                    onFace()
                } label: { face() }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text(verbatim: name))
                .dsHover()
            } else {
                face()
            }
            VStack(spacing: DS.Space.s1) {
            Text(verbatim: name)
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if line?.isEmpty == false || day != nil {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                    if let line, !line.isEmpty {
                        Text(verbatim: day == nil ? line : line + " ·")
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                    }
                    if let day {
                        Text(FeedScreen.dayWord(day))
                            .dsText(.body17)
                            .foregroundStyle(DS.headInk)
                        if clock {
                            Text(verbatim: day.formatted(date: .omitted, time: .shortened))
                                .dsText(.body17).foregroundStyle(DS.textSecondary)
                        }
                    }
                }
                .lineLimit(1)
            }
            }
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .frame(maxWidth: .infinity)
    }
}

/// WHEN, under a moment's title (prd §892) — the event sheet drew none of it.
///
/// `contentShown` has excluded `.event` since the "When" row was retired
/// (2026-08-12), on the promise that the content view spoke for the clock; the
/// content view is exactly what that exclusion switched off, so an event's
/// sheet showed its title and nothing about its time, length or place. Here
/// the clock leads at the head rung ("2:58 – 3:58 PM"), then how far off and
/// how long; a workout leads with what it measured and puts its clock under
/// it; a reminder states its due, in the destructive ink when it has passed.
/// The facts (a place, a writer) follow as the content view's own rows.
struct MomentSheetBlock: View {
    let start: Date
    var end: Date?
    var overdue = false
    var isReminder = false
    var facts: [ThingFact] = []
    /// Which half draws (prd §1179): the clock in a sheet's card, the fact
    /// rows under its tiles, or both where no card stands.
    enum Part { case whole, box, rows }
    var part: Part = .whole
    /// What the date IS (sheet sweep, 2026-10-16): a reminder's due, an
    /// offer's END (CardPointers: "Ends Tuesday", never "Due on"), or a
    /// chain's deadline whose title already says what happens then
    /// ("Staked HYPE unlocks" — the line is just the day and the hour).
    enum DueWord { case due, ends, on }
    var dueWord: DueWord = .due
    /// Under the centred head (prd §1397): the clock stands in the middle.
    var centered: Bool = false

    /// Inside the card the well gives the inset; outside, the lead's column.
    private var inset: CGFloat { part == .box ? 0 : DSRoomChassis.leadInset }

    private var metrics: [ThingFact] { facts.filter { $0.action == .metric } }
    private var rows: [ThingFact] {
        facts.filter { $0.action != .metric && $0.action != .allDay }
    }
    private var allDay: Bool { facts.contains { $0.action == .allDay } }

    private var clockLine: String {
        if allDay { return String(localized: "All day") }
        let from = start.formatted(date: .omitted, time: .shortened)
        guard let end else { return from }
        let to = Calendar.current.isDate(start, inSameDayAs: end)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(date: .abbreviated, time: .shortened)
        return "\(from) – \(to)"
    }

    private var relativeLine: String {
        let relative = start.formatted(.relative(presentation: .named))
        let lead = relative.prefix(1).uppercased() + relative.dropFirst()
        guard let end, end > start else { return lead }
        return "\(lead) · \(Self.duration(from: start, to: end))"
    }

    static func duration(from: Date, to: Date) -> String {
        let minutes = max(1, Int((to.timeIntervalSince(from) / 60).rounded()))
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return String(localized: "\(m) min") }
        return m == 0 ? String(localized: "\(h) hr") : String(localized: "\(h) hr \(m) min")
    }

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 0) {
            if part != .rows { clock.multilineTextAlignment(centered ? .center : .leading) }
            if part != .box, !rows.isEmpty {
                // Rows in the lead's column, no card (prd §1381, §1386).
                FactRows(facts: rows)
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, part == .rows ? 0 : DS.Space.s4)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    /// Whether the rows half has anything to draw.
    var hasRows: Bool { !rows.isEmpty }

    @ViewBuilder private var clock: some View {
            if !metrics.isEmpty {
                // A run is its distance first (prd §365), the clock beneath.
                HStack(alignment: .top, spacing: DS.Space.s6) {
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.value)
                                .dsText(.heading24).foregroundStyle(DS.textPrimary)
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            Text(metric.label)
                                .dsText(.label12).foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, inset)
                Text(clockLine)
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, inset)
                    .padding(.top, DS.Space.s3)
            } else if isReminder {
                Text(dueLine)
                    .dsText(.heading24)
                    .foregroundStyle(overdue ? DS.destructiveInk : DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, inset)
            } else {
                Text(clockLine)
                    .dsText(.heading40).foregroundStyle(DS.textPrimary)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, inset)
                Text(relativeLine)
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, inset)
                    .padding(.top, DS.Space.s1)
            }
    }

    /// "Due Tuesday 12:00 PM", "Overdue · Today 3:38 AM", "Ends Oct 20" —
    /// the one day word (`FeedScreen.dayWord`, prd §1359) and the clock,
    /// never a long weekday with its month, day and year (sheet sweep,
    /// 2026-10-16). An offer ends on a DAY; its clock is the feed's hour.
    private var dueLine: String {
        let day = FeedScreen.dayWord(start)
        let clock = start.formatted(date: .omitted, time: .shortened)
        switch dueWord {
        case .ends:
            return overdue ? String(localized: "Ended \(day)") : String(localized: "Ends \(day)")
        case .on:
            return "\(day) \(clock)"
        case .due:
            if overdue { return String(localized: "Overdue · \(day) \(clock)") }
            return String(localized: "Due \(day) \(clock)")
        }
    }

    // MARK: - A workout's numbers, said once (sheet sweep, 2026-10-16)

    /// A workout's title without the distance its box states as the figure:
    /// "Swim · 1,200 m" over "1.20 km" said one distance in two units. Only
    /// a trailing segment that IS a distance goes, so "Run · tempo" stays.
    static func title(_ title: String, facts: [ThingFact]) -> String {
        guard facts.contains(where: { $0.action == .metric && ($0.label == "km" || $0.label == "m") }),
              let r = title.range(of: " · ", options: .backwards) else { return title }
        let tail = title[r.upperBound...].trimmingCharacters(in: .whitespaces)
        let unit = tail.split(separator: " ").last.map(String.init) ?? ""
        let number = tail.dropLast(unit.count).trimmingCharacters(in: .whitespaces)
        guard ["km", "m", "mi"].contains(unit),
              !number.isEmpty, number.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," })
        else { return title }
        return String(title[..<r.lowerBound])
    }

    /// The facts a moment's box draws. A swim's distance is in METRES and has
    /// no pace per kilometre (a pool is laps, and nobody swims a km split);
    /// "Written by" stays only where the source is Apple Health — a Strava
    /// or Garmin row's writer is the app the source line already names.
    static func shown(_ facts: [ThingFact], source: String, title: String) -> [ThingFact] {
        let swim = title.lowercased().contains("swim")
        return facts.compactMap { fact in
            if fact.label == "Written by", source != "Apple Health" { return nil }
            guard swim, fact.action == .metric else { return fact }
            if fact.label == "Pace / km" { return nil }
            if fact.label == "km", let km = Double(fact.value) {
                let meters = Int((km * 1000).rounded())
                return ThingFact("m", meters.formatted(.number), .metric)
            }
            return fact
        }
    }
}
