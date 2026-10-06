import SwiftUI

/// THE WALLET'S CALENDAR (prd §1105): five weeks from the start of this one,
/// each renewal on its day as its face, in the Subscriptions tile's box
/// (Coming up's too until §1111 made that tile Subscriptions).
///
/// Five weeks is a month of renewals rounded out to whole weeks, so the box
/// never pages and nothing in it claims a horizontal drag the room's pager
/// owns.
///
/// **Day's Subscriptions box is the same calendar looking BACK (prd §1117)**:
/// the five weeks that END with this one, each list's face on the days it
/// wrote. What is ahead of a mailing list is a guess, so it never looks
/// forward; the days after today stay quiet instead.
struct WalletCalendar: View {
    struct Mark: Identifiable, Equatable {
        let id: String
        let day: Date
        /// The name the face is drawn for: a seat's source, or a merchant.
        let face: String
        /// Rings the face in the attention hue: it needs you, or it carries a
        /// word (a price rise).
        var attention = false
    }

    let marks: [Mark]
    var now: Date = .now
    /// The five weeks ending with this one, not starting with it (Day's box).
    var looksBack = false

    static let weeks = 5
    static let rowHeight: CGFloat = 27
    /// The face ramp's badge tier: a mark beside a day number.
    static let faceSize: CGFloat = DS.Face.badge

    var body: some View {
        let cal = Calendar.current
        let start = Self.start(now: now, calendar: cal, looksBack: looksBack)
        let today = cal.startOfDay(for: now)
        let days = (0..<(Self.weeks * 7)).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let byDay = Dictionary(grouping: marks) { cal.startOfDay(for: $0.day) }
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Array(Self.weekdayLetters(cal).enumerated()), id: \.offset) { _, letter in
                    Text(verbatim: letter)
                        .dsText(.dockCaption10).foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<Self.weeks, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { weekday in
                            let index = week * 7 + weekday
                            if index < days.count {
                                let day = days[index]
                                cell(day, index: index, today: today,
                                     marks: byDay[day] ?? [], calendar: cal)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken(start: start, calendar: cal)))
    }

    private func cell(_ day: Date, index: Int, today: Date, marks: [Mark],
                      calendar cal: Calendar) -> some View {
        let isToday = day == today
        // What the box is not about fades: the days gone, ahead; the days
        // still to come, looking back.
        let isPast = looksBack ? day > today : day < today
        let number = cal.component(.day, from: day)
        // The first of a month names its month, so the turn reads.
        let label = number == 1 && index > 0
            ? day.formatted(.dateTime.month(.abbreviated).day())
            : "\(number)"
        return ZStack {
            if let first = marks.first {
                // A dated thing TAKES its day (the box is 206pt, prd §919):
                // the face stands where the number would, the grid says which
                // day it is, and today keeps its tint as a ring.
                SubscriptionFace(name: first.face, size: Self.faceSize)
                    .overlay {
                        if marks.contains(where: \.attention) || isToday {
                            Circle().strokeBorder(marks.contains(where: \.attention) ? DS.attention : DS.tint,
                                                  lineWidth: 2)
                                .padding(-2)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if marks.count > 1 {
                            Text(verbatim: "\(marks.count)")
                                .dsText(.dockCaption10).monospacedDigit()
                                .foregroundStyle(DS.textPrimary)
                                .frame(width: 13, height: 13)
                                .background(Circle().fill(DS.surfaceRaised))
                                .offset(x: 6, y: 3)
                        }
                    }
            } else {
                Text(verbatim: label)
                    .dsText(.dockCaption10)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(isToday ? Color.white : (isPast ? DS.textTertiary : DS.textSecondary))
                    .frame(minWidth: isToday ? Self.faceSize : nil, minHeight: isToday ? Self.faceSize : nil)
                    .background {
                        if isToday { Circle().fill(DS.tint) }
                    }
            }
        }
        .opacity(isPast ? 0.5 : 1)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight)
    }

    /// The first day of this week, in the person's own week; looking back,
    /// the first day of the week four before it.
    static func start(now: Date, calendar cal: Calendar, looksBack: Bool = false) -> Date {
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        guard looksBack else { return thisWeek }
        return cal.date(byAdding: .day, value: -(weeks - 1) * 7, to: thisWeek) ?? thisWeek
    }

    /// The marks inside the five weeks, for a caller that counts them.
    static func window(now: Date, calendar cal: Calendar = .current, looksBack: Bool = false) -> DateInterval {
        let start = start(now: now, calendar: cal, looksBack: looksBack)
        let end = cal.date(byAdding: .day, value: weeks * 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func weekdayLetters(_ cal: Calendar) -> [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func spoken(start: Date, calendar cal: Calendar) -> String {
        let window = Self.window(now: now, calendar: cal, looksBack: looksBack)
        let inside = marks.filter { window.contains($0.day) }.sorted { looksBack ? $0.day > $1.day : $0.day < $1.day }
        guard !inside.isEmpty else {
            return looksBack ? String(localized: "Nothing in the last five weeks")
                             : String(localized: "Nothing dated in the next five weeks")
        }
        let parts = inside.prefix(6).map {
            "\($0.face), \($0.day.formatted(.dateTime.month(.wide).day()))"
        }
        return ListFormatter.localizedString(byJoining: Array(parts))
    }
}

/// A subscription's or a dated row's face: the seat's own mark when it has
/// one, else the name's first letter on a quiet disc — never the blank `app`
/// square a merchant's name would fall to.
struct SubscriptionFace: View {
    let name: String
    var size: CGFloat = DS.Face.row
    /// The thing's own picture, where it has one (a feed's mark, prd §1118).
    var url: String? = nil

    var body: some View {
        if let url {
            WatchFace(url: url, lettered: name, size: size)
        } else if BridgeIcon.hasMark(name) {
            BridgeIcon(name: name, size: size, circular: true)
        } else {
            Text(verbatim: String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .dsText(.badgeInitial12).foregroundStyle(DS.textSecondary)
                .frame(width: size, height: size)
                .background(Circle().fill(DS.fillFaint))
                .accessibilityHidden(true)
        }
    }
}
