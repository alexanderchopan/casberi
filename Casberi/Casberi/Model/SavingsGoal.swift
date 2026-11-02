import Foundation

/// **A SAVINGS GOAL ON YOUR PRIVATE BALANCE (prd §1667).** One number you
/// set, kept on this phone, and optionally a day to reach it by. What counts
/// toward it is the private money Holdings already shows (`PrivateMoney`,
/// approved and earning on Aave, §1563), which round-ups and Send to your
/// private balance fill (§1578). Nothing moves on its own: the goal only
/// says where you stand and, with a day, what a week takes to get there.
///
/// Pure (Foundation only): `savings-goal-selftest.sh` compiles it whole.
enum SavingsGoal {
    struct Goal: Codable, Equatable, Sendable {
        /// Dollars, above zero.
        var dollars: Double
        /// The day to reach it by; nil for none.
        var by: Date?
    }

    static let key = "savings.goal.v1"

    static func decode(_ data: Data?) -> Goal? {
        guard let data, let goal = try? JSONDecoder().decode(Goal.self, from: data),
              goal.dollars > 0, goal.dollars.isFinite else { return nil }
        return goal
    }

    static func encode(_ goal: Goal) -> Data? { try? JSONEncoder().encode(goal) }

    /// A typed amount as dollars: "500", "1,250.50", "$80"; nil for nothing,
    /// zero or words.
    static func dollars(typed: String) -> Double? {
        let digits = typed.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let d = Double(digits), d > 0, d.isFinite, d < 1_000_000_000 else { return nil }
        return d
    }

    /// How far, 0 to 1.
    static func progress(saved: Double, goal: Goal) -> Double {
        guard goal.dollars > 0, saved.isFinite else { return 0 }
        return min(1, max(0, saved / goal.dollars))
    }

    /// "28%", whole percent rounded down, so 99.6% is never "100%".
    static func percent(saved: Double, goal: Goal) -> String {
        "\(Int((progress(saved: saved, goal: goal) * 100).rounded(.down)))%"
    }

    /// What is left, whole weeks to the day (at least one), and what each
    /// week takes; nil once reached or with no day ahead.
    static func pace(saved: Double, goal: Goal, now: Date, calendar: Calendar = .current) -> (weekly: Double, weeks: Int)? {
        guard let by = goal.by, saved < goal.dollars else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: by)).day ?? 0
        guard days > 0 else { return nil }
        let weeks = max(1, Int((Double(days) / 7).rounded(.up)))
        return ((goal.dollars - max(0, saved)) / Double(weeks), weeks)
    }

    /// What the row's line says.
    enum Line: Equatable {
        /// Saved at least the goal.
        case reached
        /// A day ahead: what each week takes.
        case weekly(Double, by: Date)
        /// The day passed short of it.
        case overdue(left: Double, was: Date)
        /// No day: what is left.
        case left(Double)
    }

    static func line(saved: Double, goal: Goal, now: Date, calendar: Calendar = .current) -> Line {
        if saved >= goal.dollars { return .reached }
        let left = goal.dollars - max(0, saved)
        if let by = goal.by {
            if let pace = pace(saved: saved, goal: goal, now: now, calendar: calendar) { return .weekly(pace.weekly, by: by) }
            return .overdue(left: left, was: by)
        }
        return .left(left)
    }
}
