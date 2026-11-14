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
        // **WHAT IT IS, THEN ROWS, THEN WHAT A DATE GIVES (prd §1803, user:
        // "say what it is … and what 'By a date' gives (how much a week gets
        // you there); Save at the foot").** The goal is typed in its row, as
        // Move's amounts are; with a day set, the last line says the weekly
        // sum that reaches it from what is saved now.
        DSTray(title: String(localized: "Savings goal"), height: dated ? 560 : 440) {
            VStack(alignment: .leading, spacing: 0) {
                DSFootnote("A target for your private balance. Round-ups and what you send there fill it.")
                    .padding(.bottom, DS.Space.s3)
                HStack(spacing: DS.Space.s2) {
                    Text("Goal").dsText(.body17).foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    Text(verbatim: "$").dsText(.heading20).foregroundStyle(typed.isEmpty ? DS.textSecondary : DS.textPrimary)
                    TextField(String(localized: "0"), text: $typed)
                        .keyboardType(.decimalPad)
                        .dsText(.heading20).monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                        .tint(DS.pickInk)
                        .fixedSize()
                        .focused($focused)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
                DSToggleRow(title: Text("By a date"), isOn: $dated.animation(DS.Motion.standard))
                    .frame(minHeight: 48)
                if dated {
                    HStack(spacing: DS.Space.s2) {
                        Text("Date").dsText(.body17).foregroundStyle(DS.textSecondary)
                        Spacer(minLength: DS.Space.s2)
                        DatePicker("", selection: $by, in: Date.now..., displayedComponents: .date)
                            .labelsHidden()
                            .tint(DS.pickInk)
                    }
                    .frame(minHeight: 48)
                    .transition(.opacity)
                }
                fact(String(localized: "Saved so far"), WalletValue.money(SavingsGoal.savedNow()), ink: DS.textSecondary)
                    .padding(.top, DS.Space.s3)
                if dated, let weekly {
                    fact(String(localized: "To get there"), weekly, ink: DS.textPrimary)
                        .transition(.opacity)
                }
                Spacer(minLength: DS.Space.s3)
                if editing {
                    DSDoorRow(icon: "trash", label: "Remove goal", role: .destructive) {
                        withAnimation(DS.Motion.standard) { SavingsGoalStore.shared.set(nil) }
                        dismiss()
                    }
                }
                Button {
                    guard let dollars else { return }
                    withAnimation(DS.Motion.standard) {
                        SavingsGoalStore.shared.set(.init(dollars: dollars, by: dated ? by : nil))
                    }
                    DSHaptic.success()
                    dismiss()
                } label: { MoveSentence.actCard(String(localized: "Save"), on: dollars != nil) }
                    .buttonStyle(PressSpring())
                    .disabled(dollars == nil)
            }
        }
        .onAppear { if !editing { focused = true } }
    }

    private func fact(_ name: String, _ value: String, ink: Color) -> some View {
        HStack(spacing: DS.Space.s2) {
            Text(verbatim: name).dsText(.body17).foregroundStyle(DS.textSecondary)
            Spacer(minLength: DS.Space.s2)
            Text(verbatim: value).dsText(.body17).monospacedDigit().foregroundStyle(ink).lineLimit(1)
        }
        .frame(minHeight: 30)
    }

    /// What a week has to put away to reach the goal by its day: "about $14
    /// a week". Nil with no goal typed, nothing left to save, or a day
    /// under a week off.
    private var weekly: String? {
        guard let dollars else { return nil }
        return Self.weekly(goal: dollars, saved: SavingsGoal.savedNow(), by: by, now: .now)
    }

    static func weekly(goal: Double, saved: Double, by: Date, now: Date) -> String? {
        let left = goal - saved
        let weeks = by.timeIntervalSince(now) / (7 * 24 * 3600)
        guard left > 0, weeks >= 1 else { return nil }
        return String(localized: "about \(WalletValue.money((left / weeks).rounded(.up))) a week")
    }

    /// 500 → "500", 1250.5 → "1250.50".
    private static func typedText(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d)
    }
}
