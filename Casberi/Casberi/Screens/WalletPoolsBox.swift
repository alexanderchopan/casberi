import SwiftUI

/// **THE 0XBOW PRIVACY POOLS PICK'S BOX (prd §1614).** Your private balance
/// is 0xBow's Privacy Pools v2, so the pick answers "how much is private,
/// what is cleared, and how hidden is it?". The figure is what is private
/// (approved), counted once with the Wallet's total (§1554); under it the
/// app's catalogue name; a bar splits your money into Ready, Earning and
/// Waiting (Not approved in red where there is any); then the rate where it
/// earns. Empty, the same box drawn empty (§769) with the one verb, Move to
/// private, where this build can move (`PrivateMove.available`).
///
/// "Private" is the money's state, never the app's name: the app is always
/// "0xBow Privacy Pools", as the catalogue says (user, 2026-10-29).
struct WalletPoolsBox: View {
    let split: PoolsSplit
    /// Masked under Hide balances.
    let mask: String?
    /// "Earning 1.0% on Aave", or nil where nothing earns.
    let earning: String?
    let canMove: Bool
    var onMove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: mask ?? split.figure)
                .dsText(.price40)
                .foregroundStyle(split.isEmpty ? DS.textTertiary : DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: split.isEmpty ? String(localized: "Nothing private yet")
                 : String(localized: "private in 0xBow Privacy Pools"))
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s3)
            bar
            legend
                .padding(.top, DS.Space.s2)
            if split.isEmpty, canMove {
                Button {
                    DSHaptic.selection()
                    onMove()
                } label: {
                    HStack {
                        Text("Move to private")
                            .dsText(.body17)
                            .foregroundStyle(DS.pickInk)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .padding(.top, DS.Space.s2)
            } else if let earning {
                Text(verbatim: earning)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .frame(minHeight: 44, alignment: .leading)
                    .padding(.top, DS.Space.s2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bar: some View {
        GeometryReader { geo in
            let parts = split.parts.filter { $0.share > 0 }
            let gaps = CGFloat(max(parts.count - 1, 0)) * 2
            // The old room card's split (`PrivacyPoolsRoomCard.splitBar`): the
            // track, then the parts over it, one length.
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(DS.fillFaint)
                HStack(spacing: 2) {
                    ForEach(parts) { part in
                        Rectangle()
                            .fill(ink(part.kind))
                            .frame(width: max((geo.size.width - gaps) * part.share, 3))
                    }
                    Spacer(minLength: 0)
                }
                .mask(Capsule(style: .continuous))
            }
        }
        .frame(height: 12)
        .chartWipe(reduceMotion: reduceMotion)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: DS.Space.s4) {
            ForEach(split.parts.filter { split.isEmpty || $0.share > 0 }) { part in
                HStack(spacing: 6) {
                    Circle().fill(split.isEmpty ? DS.fillStrong : ink(part.kind)).frame(width: 7, height: 7)
                    Text(verbatim: [part.kind.label, split.isEmpty ? nil : (mask ?? part.figure)]
                        .compactMap { $0 }.joined(separator: " "))
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func ink(_ kind: PoolsSplit.Kind) -> Color {
        switch kind {
        case .ready: DS.pickInk
        case .earning: DS.pickInk.opacity(0.45)
        case .waiting: DS.attentionInk
        case .refused: DS.destructiveInk
        }
    }
}

/// The box's reading: private money in four states, by value (prd §1614).
struct PoolsSplit: Equatable {
    enum Kind: Int, Equatable, CaseIterable {
        case ready, earning, waiting, refused
        var label: String {
            switch self {
            case .ready: String(localized: "Ready")
            case .earning: String(localized: "Earning")
            case .waiting: String(localized: "Waiting")
            case .refused: String(localized: "Not approved")
            }
        }
    }

    struct Part: Equatable, Identifiable {
        var id: Int { kind.rawValue }
        let kind: Kind
        /// Of the whole bar, 0…1.
        let share: CGFloat
        let figure: String
    }

    let figure: String
    let parts: [Part]
    let isEmpty: Bool

    /// Splits the rows by value: dollars where priced, else (test money,
    /// §949) the token's own amount, and then a share only among rows of one
    /// token. A held row on a network where its token earns is Earning.
    @MainActor
    static func compose(_ rows: [PrivateMoney.Row], store: PrivateMoneyStore) -> PoolsSplit {
        func kind(_ row: PrivateMoney.Row) -> Kind {
            switch row.kind {
            case .held: store.yieldLine(row) != nil ? .earning : .ready
            case .waiting: .waiting
            case .refused: .refused
            }
        }
        // Dollars where any row is priced (an unpriced row, test money or a
        // price not read yet, is left out rather than added as units of
        // another token); units only when every row is one token.
        let usd = rows.map { PrivateMoney.rowUSD($0, prices: store.prices) }
        let priced = usd.contains { $0 != nil }
        let rows = priced ? zip(rows, usd).filter { $0.1 != nil }.map(\.0) : rows
        let usdKept = usd.compactMap { $0 }
        var sums: [Kind: Double] = [:]
        var units: [Kind: Decimal] = [:]
        for (i, row) in rows.enumerated() {
            let k = kind(row)
            if priced { sums[k, default: 0] += usdKept[i] }
            let amount = (Decimal(string: row.amount) ?? 0) / pow(10, row.decimals)
            units[k, default: 0] += amount
        }
        guard !rows.isEmpty else {
            return PoolsSplit(figure: WalletValue.money(0),
                              parts: [.ready, .earning, .waiting].map { Part(kind: $0, share: 0, figure: "") },
                              isEmpty: true)
        }
        let symbol = Set(rows.map(\.symbol)).count == 1 ? rows[0].symbol : nil
        // Several unpriced tokens add up to nothing honest: their count.
        if !priced, symbol == nil {
            return PoolsSplit(figure: String(localized: "\(Set(rows.map(\.symbol)).count) tokens"),
                              parts: [], isEmpty: false)
        }
        func words(_ k: Kind) -> String {
            if priced { return WalletValue.money(sums[k] ?? 0) }
            let n = NSDecimalNumber(decimal: units[k] ?? 0).doubleValue
            return [n.formatted(.number.precision(.significantDigits(1...4))), symbol].compactMap { $0 }.joined(separator: " ")
        }
        let values: [Kind: Double] = priced ? sums
            : units.mapValues { NSDecimalNumber(decimal: $0).doubleValue }
        let whole = values.values.reduce(0, +)
        let parts = Kind.allCases.compactMap { k -> Part? in
            guard let v = values[k], v > 0 else { return nil }
            return Part(kind: k, share: whole > 0 ? CGFloat(v / whole) : 0, figure: words(k))
        }
        // The figure is what is private: approved money, ready or earning.
        let privateValue = (values[.ready] ?? 0) + (values[.earning] ?? 0)
        let figure: String
        if priced { figure = WalletValue.money(privateValue) }
        else {
            let n = NSDecimalNumber(decimal: (units[.ready] ?? 0) + (units[.earning] ?? 0)).doubleValue
            figure = [n.formatted(.number.precision(.significantDigits(1...4))), symbol].compactMap { $0 }.joined(separator: " ")
        }
        return PoolsSplit(figure: figure, parts: parts, isEmpty: false)
    }
}
