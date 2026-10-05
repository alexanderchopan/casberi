import SwiftUI

/// Coming up's box (prd §1078, §1105): what the next thirty days' bills add
/// up to, how many things wait on you, then the five weeks ahead as a
/// calendar, each thing on its day. `WalletDue` holds the arithmetic and the
/// words; `WalletCalendar` is the drawing the Subscriptions box shares, so the
/// two tiles' boxes read the same way.
struct WalletDueFigure: View {
    let bills: [WalletDue.Bill]
    let waiting: Int
    /// Every live row Coming up holds, soonest first.
    let upcoming: [Thing]

    @State private var rates: [String: Double] = [:]

    var body: some View {
        let reading = WalletDue.compose(bills: bills, waiting: waiting, rates: rates)
        let mask = BalancePrivacy.shared.withheld ? BalancePrivacy.mask : nil
        let codes = Set(bills.compactMap(\.currency)).subtracting(["USD"])
        let next = upcoming.first
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if reading.hasFigure {
                Text("\(mask ?? CardSpendRoom.money(reading.total, code: "USD")) due in \(WalletDue.windowDays) days")
                    .dsText(.heading24).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let next {
                Text(next.title)
                    .dsText(.heading24).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
            }
            line(reading: reading, next: next)
            Spacer(minLength: DS.Space.s1)
            WalletCalendar(marks: Self.marks(upcoming))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .task(id: codes) {
            guard !codes.isEmpty else { return }
            let fetched = await WalletCash.cachedRates(for: codes)
            if fetched != rates { rates = fetched }
        }
    }

    /// One 12pt line, the Subscriptions box's: what waits on you in the
    /// attention ink, then how many more fall inside the five weeks.
    private func line(reading: WalletDue.Reading, next: Thing?) -> some View {
        let window = WalletCalendar.window(now: .now)
        let dated = upcoming.filter { ($0.dueAt.map { $0 > .now } ?? false) && window.contains($0.dueAt!) }.count
        let end = window.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day())
        var text = Text(verbatim: "")
        if let waitingLine = WalletDue.waitingLine(reading.waiting) {
            text = Text(waitingLine).foregroundStyle(DS.attentionInk).fontWeight(.semibold)
            if dated > 0 {
                text = text + Text(verbatim: " · ").foregroundStyle(DS.textTertiary)
                    + Text("\(dated) more before \(end)").foregroundStyle(DS.textTertiary)
            }
        } else if reading.hasFigure || next == nil {
            text = Text("\(dated) before \(end)").foregroundStyle(DS.textTertiary)
        } else if let next, let due = FeedScreen.dueLine(next) {
            text = Text(due).foregroundStyle(DS.textTertiary)
        }
        // A bill with no amount or no rate is NAMED, never zeroed (§1078);
        // the box has one line for it, so it rides this one.
        if let uncounted = WalletDue.uncountedLine(reading.uncounted) {
            text = text + Text(verbatim: " · \(uncounted)").foregroundStyle(DS.textTertiary)
        }
        return text.dsText(.subhead12).lineLimit(1)
    }

    /// A dated row on its day; a row that waits on you (no date, or one
    /// already passed) on today, ringed.
    static func marks(_ upcoming: [Thing]) -> [WalletCalendar.Mark] {
        let now = Date.now
        return upcoming.compactMap { thing in
            guard thing.isLive else { return nil }
            let due = thing.dueAt
            let waits = due.map { $0 <= now } ?? true
            return .init(id: thing.id.uuidString, day: waits ? now : due!,
                         face: thing.source, attention: waits)
        }
    }
}
