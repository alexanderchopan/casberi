import SwiftUI

/// **DAY'S BOX IS A CALENDAR (prd §1229, user: "should calendar section show
/// a literal calendar? perhaps the same one that shows subscriptions" … "it
/// should still show the events on their personal calendar")**: the next
/// thing on top — its title, when, where — and under it the Wallet's
/// five-week `WalletCalendar`, each event and due to-do as its app's face on
/// its day. It replaced today's timeline strip (`DayAheadCard`, §1087).
struct DayCalendarFigure: View {
    let title: String
    let when: String
    let line: String
    let marks: [WalletCalendar.Mark]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(verbatim: title)
                    .dsText(.heading24).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: when)
                    .dsText(.subhead12).foregroundStyle(DS.brandInk)
                    .lineLimit(1)
            }
            if !line.isEmpty {
                Text(verbatim: line)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.s1)
            WalletCalendar(marks: marks)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
