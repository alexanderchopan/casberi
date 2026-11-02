import Foundation
import Observation

/// The savings goal, kept on this phone (prd §1667): read once, written
/// through `DefaultsWrite`, never synced. The demo shows its own goal when
/// none is set, so the row is never an empty promise there (§1618).
@MainActor
@Observable
final class SavingsGoalStore {
    static let shared = SavingsGoalStore()

    private(set) var goal: SavingsGoal.Goal?

    private init() {
        goal = SavingsGoal.decode(UserDefaults.standard.data(forKey: SavingsGoal.key))
        #if DEBUG
        // `-savingsGoal "<dollars>[|<days>]"|clear`: set or clear the goal at
        // launch, so the row can be looked at on a simulator (NSLogs
        // `savingsGoal:`).
        if let arg = UserDefaults.standard.string(forKey: "savingsGoal") {
            if arg == "clear" {
                set(nil)
            } else {
                let parts = arg.split(separator: "|").map(String.init)
                if let dollars = parts.first.flatMap(SavingsGoal.dollars(typed:)) {
                    let by = parts.dropFirst().first.flatMap(Double.init).map { Date().addingTimeInterval($0 * 86_400) }
                    set(.init(dollars: dollars, by: by))
                }
            }
            NSLog("savingsGoal: %@", goal.map { "\($0.dollars) by \($0.by.map { "\($0)" } ?? "none")" } ?? "none")
        }
        #endif
    }

    /// What the row draws: yours, else the demo's.
    var shown: SavingsGoal.Goal? {
        goal ?? (YourAccountDemo.isOn ? .init(dollars: 500, by: Date().addingTimeInterval(56 * 86_400)) : nil)
    }

    func set(_ goal: SavingsGoal.Goal?) {
        self.goal = goal
        if let goal, let data = SavingsGoal.encode(goal) {
            DefaultsWrite.set(data, forKey: SavingsGoal.key)
        } else {
            DefaultsWrite.remove(SavingsGoal.key)
        }
    }
}
