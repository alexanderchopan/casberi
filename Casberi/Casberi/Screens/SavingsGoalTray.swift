import SwiftUI

/// **SET A SAVINGS GOAL (prd §1667).** The amount, and a day if you want
/// one; Save keeps it on this phone, Remove forgets it. Nothing here moves
/// money: the goal is filled by round-ups and Send to your private balance.
struct SavingsGoalTray: View {
    @Environment(\.dismiss) private var dismiss
    @State private var typed: String
    @State private var dated: Bool
    @State private var by: Date
    @FocusState private var focused: Bool
    private let editing: Bool

    init() {
        let goal = SavingsGoalStore.shared.goal
        editing = goal != nil
        _typed = State(initialValue: goal.map { Self.typedText($0.dollars) } ?? "")
        _dated = State(initialValue: goal?.by != nil)
        _by = State(initialValue: goal?.by ?? Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now)
    }

    private var dollars: Double? { SavingsGoal.dollars(typed: typed) }

    var body: some View {
        DSTray(title: String(localized: "Savings goal"), height: dated ? 470 : 380) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: "$").dsText(.price40).foregroundStyle(DS.textPrimary)
                        .fixedSize()
                    TextField(String(localized: "0"), text: $typed)
                        .keyboardType(.decimalPad)
                        .dsText(.price40).monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                        .focused($focused)
                }
                DSToggleRow(title: Text("By a date"), isOn: $dated.animation(DS.Motion.standard))
                if dated {
                    DatePicker("", selection: $by, in: Date.now..., displayedComponents: .date)
                        .labelsHidden()
                        .transition(.opacity)
                }
                DSSlabButton(title: String(localized: "Save"), enabled: dollars != nil) {
                    guard let dollars else { return }
                    withAnimation(DS.Motion.standard) {
                        SavingsGoalStore.shared.set(.init(dollars: dollars, by: dated ? by : nil))
                    }
                    DSHaptic.success()
                    dismiss()
                }
                if editing {
                    DSDoorRow(icon: "trash", label: "Remove goal", role: .destructive) {
                        withAnimation(DS.Motion.standard) { SavingsGoalStore.shared.set(nil) }
                        dismiss()
                    }
                }
            }
        }
        .onAppear { if !editing { focused = true } }
    }

    /// 500 → "500", 1250.5 → "1250.50".
    private static func typedText(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d)
    }
}
