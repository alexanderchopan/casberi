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
    /// The face's door, where it has one (a person's profile, a room).
    var onFace: (() -> Void)? = nil
    @ViewBuilder let face: () -> Face

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            if let onFace {
                Button {
                    DSHaptic.tap()
                    onFace()
                } label: { face() }
                .buttonStyle(.plain)
                .dsHover()
            } else {
                face()
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    // A name is words here (a show, a book, a sender), so it
                    // wraps rather than losing its middle (prd §897).
                    Text(verbatim: name)
                        .dsText(.heading17).foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.s2)
                    if let day {
                        Text(FeedScreen.dayWord(day))
                            .dsText(.label12)
                            .foregroundStyle(DS.brandInk)
                            .lineLimit(1)
                    }
                }
                if let line, !line.isEmpty {
                    Text(verbatim: line)
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 0) {
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
                .padding(.horizontal, DSRoomChassis.leadInset)
                Text(clockLine)
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, DS.Space.s3)
            } else if isReminder {
                Text(dueLine)
                    .dsText(.heading24)
                    .foregroundStyle(overdue ? DS.destructive : DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DSRoomChassis.leadInset)
            } else {
                Text(clockLine)
                    .dsText(.heading40).foregroundStyle(DS.textPrimary)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, DSRoomChassis.leadInset)
                Text(relativeLine)
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DSRoomChassis.leadInset)
                    .padding(.top, DS.Space.s1)
            }
            if !rows.isEmpty {
                FactRows(facts: rows)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Overdue since yesterday, 12:00" / "Due tomorrow, 11:00".
    private var dueLine: String {
        let cal = Calendar.current
        let near = cal.isDateInToday(start) || cal.isDateInYesterday(start)
            || cal.isDateInTomorrow(start)
        let day = FeedScreen.dayWord(start)
        // "yesterday" reads inside a sentence; a named day keeps its capital,
        // and takes "on" only after "Due" ("since on Monday" is not English).
        let clock = start.formatted(date: .omitted, time: .shortened)
        if overdue {
            let when = near ? day.lowercased() : day
            return String(localized: "Overdue since \(when), \(clock)")
        }
        let when = near ? day.lowercased() : String(localized: "on \(day)")
        return String(localized: "Due \(when), \(clock)")
    }
}
