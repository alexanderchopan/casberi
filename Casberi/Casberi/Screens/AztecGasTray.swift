import SwiftUI

/// **GAS ON AZTEC, AND ADD GAS (prd §1761).** Gas came only two ways: riding
/// along with a move in, or from an "Add gas" that Send showed after a send
/// had already failed for want of it. Someone who opened an app first had no
/// way to get any. Holdings' gas row opens this: what the account holds, how
/// it stands, and the one top-up.
struct AztecGasTray: View {
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var failed: String?

    var body: some View {
        let store = AztecAccountStore.shared
        let juice = store.shown.holdings.first { $0.kind == .feeJuice }
        let state = adding ? AztecGas.Standing.arriving : AztecGas.state
        DSTray(title: String(localized: "Gas on Aztec"), height: 360) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(verbatim: juice.map { FeedScreen.aztecFigure($0, units: NSDecimalNumber(decimal: $0.gasUnits).stringValue) } ?? "0")
                        .dsText(.price40).monospacedDigit().foregroundStyle(DS.textPrimary)
                    Text(verbatim: "AZTEC").dsText(.body17).foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    if let word = Self.word(state) {
                        Text(verbatim: word.words).dsText(.body17)
                            .foregroundStyle(word.attention ? DS.attentionInk : DS.textSecondary)
                    }
                }
                Text("30 AZTEC from your account pays for it, about $0.45.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                DSSlabButton(title: String(localized: "Add gas"), systemImage: "fuelpump", busy: adding,
                             enabled: !adding && state != .arriving && !DemoMode.isActive) { add() }
                if let failed {
                    Text(verbatim: failed).dsText(.subhead12).foregroundStyle(DS.attentionInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The state in one word; none when there is enough.
    static func word(_ state: AztecGas.Standing) -> (words: String, attention: Bool)? {
        switch state {
        case .arriving: (String(localized: "On its way"), false)
        case .none: (String(localized: "None"), true)
        case .low: (String(localized: "Low"), true)
        case .enough: nil
        }
    }

    private func add() {
        adding = true
        failed = nil
        Task {
            do {
                _ = try await AztecGas.topUp { _ in }
                DSHaptic.success()
                dismiss()
            } catch {
                failed = AztecEngine.words(error)
            }
            adding = false
        }
    }
}
