import SwiftUI

/// **DAY IS THE WEEK (prd §1640, user, 2026-11-01: "it feels like the
/// calendar part of the feed should show a calendar"; of the mock, "i like
/// the calendar that shows the week", "i like it having the week like you
/// drew. and agree media has its own layout").** The Feed's Day section
/// draws this week as seven days, each with the faces of what is on it, the
/// way Media draws its grid: a section's own shape, not a figure dropped
/// among rows. The next thing stands under it as a row; the rest of the
/// month is the Calendar app's own page, which a tap on the week raises.
///
/// One button, never seven: a day is too small a target to pick in a
/// scrolling feed, and a picked day standing in for the section's rows is
/// what §1413 deleted.
struct DayWeek: View {
    struct Mark: Identifiable, Equatable {
        let id: String
        let day: Date
        /// A seat's source or a plan's name, drawn as its face.
        let face: String
    }

    let marks: [Mark]
    var now: Date = .now
    /// The app the week opens; nil draws the week with no door (§83).
    let open: (() -> Void)?

    /// Two faces fit a day's column at every width the phone draws.
    static let facesPerDay = 2
    static let faceSize: CGFloat = 16
    static let daySize: CGFloat = 32

    var body: some View {
        if let open {
            Button(action: open) { week }
                .buttonStyle(RowPress())
                .accessibilityHint(Text("Opens Calendar"))
        } else {
            week
        }
    }

    private var week: some View {
        let cal = Calendar.current
        let start = WalletCalendar.start(now: now, calendar: cal)
        let today = cal.startOfDay(for: now)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let faces = Self.faces(marks, calendar: cal)
        return HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                VStack(spacing: DS.Space.s1) {
                    Text(verbatim: WalletCalendar.weekdayLetters(cal)[i])
                        .dsText(.dockCaption10)
                        .foregroundStyle(DS.textTertiary)
                    Text(verbatim: "\(cal.component(.day, from: day))")
                        .dsText(.body17)
                        .fontWeight(day == today ? .semibold : .regular)
                        .monospacedDigit()
                        .foregroundStyle(day == today ? Color.white : (day < today ? DS.textTertiary : DS.textPrimary))
                        .frame(width: Self.daySize, height: Self.daySize)
                        .background { if day == today { Circle().fill(DS.pickInk) } }
                    HStack(spacing: 2) {
                        ForEach(faces[day] ?? [], id: \.self) { face in
                            SubscriptionFace(name: face, size: Self.faceSize)
                        }
                    }
                    .frame(height: Self.faceSize)
                    .opacity(day < today ? 0.5 : 1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.spoken(marks, days: days, calendar: cal)))
    }

    /// Each day's faces, the first two apps or plans on it, one face per name.
    static func faces(_ marks: [Mark], calendar cal: Calendar) -> [Date: [String]] {
        var out: [Date: [String]] = [:]
        for mark in marks.sorted(by: { $0.day < $1.day }) {
            let day = cal.startOfDay(for: mark.day)
            var names = out[day] ?? []
            guard names.count < facesPerDay, !names.contains(mark.face) else { continue }
            names.append(mark.face)
            out[day] = names
        }
        return out
    }

    /// The week read as one sentence.
    static func spoken(_ marks: [Mark], days: [Date], calendar cal: Calendar) -> String {
        guard let first = days.first, let last = days.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else { return "" }
        let inside = marks.filter { $0.day >= first && $0.day < end }.sorted { $0.day < $1.day }
        guard !inside.isEmpty else { return String(localized: "Nothing this week") }
        let parts = inside.prefix(6).map {
            "\($0.face), \($0.day.formatted(.dateTime.weekday(.wide)))"
        }
        return String(localized: "This week: \(ListFormatter.localizedString(byJoining: Array(parts)))")
    }
}
