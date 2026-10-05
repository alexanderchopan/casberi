import SwiftUI

/// **WHICH TOKENS HOLDINGS LISTS, AND WHICH FOLD (prd §1107, user: "what if
/// someone has dozens of tokens we need to factor that in bc it does happen").**
///
/// The list drew every token, so on a wallet holding forty the Positions under
/// them were forty rows down. Now each token worth a twentieth of the whole
/// draws, five at most and never fewer than one; the rest fold into one row
/// that says how many, what they are worth and the first few names, and opens
/// every one. A fold of ONE is not a fold — that token simply draws.
struct WalletTokenFold {
    let shown: [WalletPortfolio.Position]
    let rest: [WalletPortfolio.Position]

    static let shareFloor = 0.05
    static let cap = 5

    init(_ positions: [WalletPortfolio.Position], total: Double) {
        let ordered = positions.sorted { $0.usd == $1.usd ? $0.symbol < $1.symbol : $0.usd > $1.usd }
        let big = total > 0
            ? ordered.prefix(Self.cap).prefix(while: { $0.usd / total >= Self.shareFloor })
            : ordered.prefix(Self.cap)
        var shown = Array(big.isEmpty ? ordered.prefix(1) : big)
        var rest = Array(ordered.dropFirst(shown.count))
        if rest.count == 1 {
            shown += rest
            rest = []
        }
        self.shown = shown
        self.rest = rest
    }

    var restUSD: Double { rest.reduce(0) { $0 + $1.usd } }
}

/// A token, as Holdings and the all-tokens tray draw it: its mark, its
/// symbol, whose it is where that is a question, then the day's move (or its
/// share) beside the amount, which pins to the edge.
struct WalletTokenRowLabel: View {
    let position: WalletPortfolio.Position
    let total: Double
    let move: Double?

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            // Always a mark — `TokenIcon` draws nothing for a token with no
            // picture, and the row's name then stood in a different column.
            AssetMark(name: position.symbol, size: DS.Face.list)
            VStack(alignment: .leading, spacing: 1) {
                Text(position.symbol)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                // Whose it is, only where that is a real question — one
                // watched wallet has no split to report (§212's guard).
                if position.holders.count > 1 {
                    Text(position.holders.prefix(2).map(\.label).joined(separator: " · "))
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            // **THE AMOUNT PINS TO THE EDGE, THE SHARE STANDS BEFORE IT**
            // (user, 2026-09-26: "the dollar values should be aligned").
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                // The day's move, where a read has one (prd §1090).
                if let move {
                    let flat = TokenChartStyle.isFlat(move)
                    Text(TokenChartStyle.changeText(move))
                        .dsText(.subhead12)
                        .foregroundStyle(flat ? DS.textTertiary
                                         : (move > 0 ? DS.confirmInk : DS.destructiveInk))
                        .monospacedDigit()
                } else if total > 0 {
                    let pct = Int((position.usd / total * 100).rounded())
                    if pct >= 1 {
                        Text("\(pct)%")
                            .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                            .monospacedDigit()
                    }
                }
                Text(WalletValue.money(position.usd))
                    .dsText(.price17).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
            }
        }
    }
}

/// The fold's row: "41 more tokens" over the first names, what they are
/// worth at the edge, a chevron for the tray it opens.
struct WalletTokenFoldRow: View {
    let fold: WalletTokenFold

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            ZStack {
                Circle().fill(DS.fillFaint)
                Text(verbatim: "+\(fold.rest.count)")
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
            }
            .frame(width: DS.Face.list, height: DS.Face.list)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(fold.rest.count) more tokens")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(names)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            Text(WalletValue.money(fold.restUSD))
                .dsText(.price17).foregroundStyle(DS.textPrimary)
                .monospacedDigit()
            DSChevron()
        }
    }

    /// "ARB, OP, LINK and 38 more" — the biggest few by name.
    private var names: String {
        let first = fold.rest.prefix(3).map(\.symbol)
        let left = fold.rest.count - first.count
        let joined = first.joined(separator: ", ")
        return left > 0 ? String(localized: "\(joined) and \(left) more") : joined
    }
}

/// **EVERY TOKEN (prd §1107)** — what the fold row opens: by worth, dust
/// under a dollar folded into one row at the end, and a search field at the
/// foot once there are more than twenty. A row opens the token as the room's
/// row does, after this tray has closed (one sheet at a time, §872).
struct WalletTokensSheet: View {
    let positions: [WalletPortfolio.Position]
    let total: Double
    let moves: [String: Double]
    let onOpen: (WalletPortfolio.Position) -> Void

    @State private var query = ""
    @State private var dustOpen = false
    @FocusState private var fieldFocused: Bool

    static let dustFloor = 1.0
    static let searchFrom = 20

    private var ordered: [WalletPortfolio.Position] {
        positions.sorted { $0.usd == $1.usd ? $0.symbol < $1.symbol : $0.usd > $1.usd }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        DSTray(title: String(localized: "\(positions.count) tokens"), height: 640, detents: [.large]) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmed.isEmpty {
                        let dust = ordered.filter { $0.usd < Self.dustFloor }
                        ForEach(ordered.filter { $0.usd >= Self.dustFloor }) { row($0) }
                        if !dust.isEmpty {
                            if dustOpen {
                                ForEach(dust) { row($0) }
                            } else {
                                dustRow(dust)
                            }
                        }
                    } else {
                        let found = ordered.filter { $0.symbol.localizedCaseInsensitiveContains(trimmed) }
                        ForEach(found) { row($0) }
                    }
                }
                .padding(.bottom, positions.count > Self.searchFrom ? 96 : DS.Space.s4)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if positions.count > Self.searchFrom {
                    DSTraySearchField(placeholder: String(localized: "Search \(positions.count) tokens"),
                                      text: $query, focus: $fieldFocused) { EmptyView() }
                }
            }
        }
    }

    private func row(_ position: WalletPortfolio.Position) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(position)
        } label: {
            WalletTokenRowLabel(position: position, total: total,
                                move: moves[HoldingMoves.key(position.symbol)])
                .padding(.vertical, DS.Space.s2)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .padding(.horizontal, DS.Space.s4)
    }

    /// "Under $1 · 19 tokens", opening them in place.
    private func dustRow(_ dust: [WalletPortfolio.Position]) -> some View {
        Button {
            DSHaptic.selection()
            withAnimation(DS.Motion.standard) { dustOpen = true }
        } label: {
            HStack(spacing: DS.Space.s3) {
                ZStack {
                    Circle().fill(DS.fillFaint)
                    Text(verbatim: "+\(dust.count)")
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                }
                .frame(width: DS.Face.list, height: DS.Face.list)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Under $1")
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Text(dust.count == 1 ? String(localized: "1 token")
                                         : String(localized: "\(dust.count) tokens"))
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: DS.Space.s2)
                Text(WalletValue.money(dust.reduce(0) { $0 + $1.usd }))
                    .dsText(.price17).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
            }
            .padding(.vertical, DS.Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .padding(.horizontal, DS.Space.s4)
    }
}
