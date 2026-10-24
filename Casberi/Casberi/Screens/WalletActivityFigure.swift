import SwiftUI

/// **ACTIVITY'S BOX: HOW BUSY IT WAS (prd §1480 item 3).** The window's
/// transactions — "99 transactions this month" — the count against the last
/// window to the same point, then one bar per day of the window, today's in
/// the primary ink and the days still ahead an empty floor. Week · Month as
/// slim words, as Spending's box (§942, §1468).
///
/// It counts the rows Activity lists (`FeedScreen.walletMoves`), so the box and
/// the list can never disagree. Nothing is coloured: a busy day is neither
/// good nor bad (§83).
struct WalletActivityFigure: View {
    let moves: [Thing]
    @AppStorage("wallet.activity.window") private var windowRaw = Spending.Window.month.rawValue

    private var window: Spending.Window { Spending.Window(rawValue: windowRaw) ?? .month }

    /// The window's days, each with its count, and the two totals.
    struct Reading: Equatable {
        var days: [(day: Date, count: Int, ahead: Bool)]
        var total: Int
        var earlier: Int?

        static func == (a: Reading, b: Reading) -> Bool {
            a.total == b.total && a.earlier == b.earlier && a.days.count == b.days.count
        }
    }

    /// Pure: what the box draws for `dates` in `window` at `now`.
    static func read(_ dates: [Date], window: Spending.Window, now: Date = .now,
                     calendar: Calendar = .current) -> Reading {
        let unit: Calendar.Component = window == .week ? .weekOfYear : .month
        guard let span = calendar.dateInterval(of: unit, for: now) else {
            return Reading(days: [], total: 0, earlier: nil)
        }
        var byDay: [Date: Int] = [:]
        for date in dates where span.contains(date) && date <= now {
            byDay[calendar.startOfDay(for: date), default: 0] += 1
        }
        var days: [(Date, Int, Bool)] = []
        var day = span.start
        while day < span.end {
            days.append((day, byDay[day] ?? 0, day > now))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let total = byDay.values.reduce(0, +)
        // The last window to the same point: as far into it as now is into this.
        let into = now.timeIntervalSince(span.start)
        var earlier: Int?
        if let last = calendar.date(byAdding: unit, value: -1, to: span.start) {
            let cut = last.addingTimeInterval(into)
            let lastDates = dates.filter { $0 >= last && $0 <= cut }
            // Only once the record reaches that far back: a young record has
            // nothing to compare, and "0 last month" would be a false fact.
            if let oldest = dates.min(), oldest <= last { earlier = lastDates.count }
        }
        return Reading(days: days, total: total, earlier: earlier)
    }

    var body: some View {
        let reading = Self.read(moves.map(\.capturedAt), window: window)
        let busiest = max(1, reading.days.map(\.count).max() ?? 1)
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(headline(reading))
                .dsText(.heading24).foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let compare = compareLine(reading) {
                Text(verbatim: compare)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: window == .week ? DS.Space.s2 : 2) {
                    ForEach(Array(reading.days.enumerated()), id: \.offset) { _, day in
                        let isToday = Calendar.current.isDateInToday(day.day)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(day.ahead ? DS.fillFaint
                                  : (isToday ? DS.textPrimary : DS.textTertiary.opacity(0.55)))
                            .frame(height: day.ahead ? 3
                                   : max(3, geo.size.height * CGFloat(day.count) / CGFloat(busiest)))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .padding(.top, DS.Space.s3)
            .accessibilityElement()
            .accessibilityLabel(Text("Transactions each day"))
            DSRangeChips(ranges: Spending.Window.allCases, range: window,
                         label: { $0 == .week ? String(localized: "Week") : String(localized: "Month") },
                         slim: true) { picked in
                withAnimation(DS.Motion.standard) { windowRaw = picked.rawValue }
            }
            .padding(.top, DS.Space.s2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func headline(_ reading: Reading) -> String {
        let n = reading.total
        let noun = n == 1 ? String(localized: "1 transaction") : String(localized: "\(n) transactions")
        return window == .week ? String(localized: "\(noun) this week") : String(localized: "\(noun) this month")
    }

    /// "12 more than by now last month"; nil with nothing to compare.
    private func compareLine(_ reading: Reading) -> String? {
        guard let earlier = reading.earlier else { return nil }
        let last = window == .week ? String(localized: "last week") : String(localized: "last month")
        let diff = reading.total - earlier
        if diff == 0 { return String(localized: "The same as by now \(last)") }
        return diff > 0 ? String(localized: "\(diff) more than by now \(last)")
                        : String(localized: "\(-diff) fewer than by now \(last)")
    }
}
