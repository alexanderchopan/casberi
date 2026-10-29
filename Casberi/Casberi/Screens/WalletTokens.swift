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
            // **ONE LINE, NO SUBTEXT (prd §1338, user: "don't need the
            // subtext").** Whose it is lives in the token's sheet.
            Text(position.symbol)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            // **THE AMOUNT PINS TO THE EDGE, THE SHARE STANDS BEFORE IT**
            // (user, 2026-09-26: "the dollar values should be aligned").
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                // The day's move, where a read has one (prd §1090).
                // A move that rounds to nothing says nothing (§83, prd
                // §1338): a stablecoin's "0.0%" is dropped, not greyed.
                if let move {
                    if !TokenChartStyle.isFlat(move) {
                        Text(TokenChartStyle.changeText(move))
                            .dsText(.subhead12)
                            .foregroundStyle(move > 0 ? DS.confirmInk : DS.destructiveInk)
                            .monospacedDigit()
                    }
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
            VStack(alignment: .leading, spacing: 2) {
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
    /// The tokens you hid (`HiddenTokens`): out of the list and the total,
    /// named in one row at the foot that brings each back (§83).
    var hidden: [WalletPortfolio.HiddenItem] = []
    let onOpen: (WalletPortfolio.Position) -> Void
    /// Hide (true) or show (false) a token or one contract of it, from a
    /// row's long press (prd §1591).
    var onHide: ((HiddenTokens.Target, Bool) -> Void)? = nil

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
        DSTray(title: String(localized: "\(positions.count) tokens"), height: 640, detents: [.large], scrollsItself: true) {
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
                    if !hidden.isEmpty, onHide != nil { hiddenRow }
                }
                .padding(.bottom, positions.count > Self.searchFrom ? 96 : DS.Space.s4)
            }
            .scrollDismissesKeyboard(.interactively)
            .dsFindField {
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
                .walletRowPitch()
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .contextMenu {
            // Out of the list and the total (user: "when i open tokens i
            // should be able to long press and hide tokens").
            if let onHide { TokenHideMenu(position: position, onHide: onHide) }
        }
        .padding(.horizontal, DS.Space.s4)
    }

    /// "Hidden · 3", what they are worth and that the total leaves them out;
    /// its menu brings each back.
    private var hiddenRow: some View {
        Menu {
            ForEach(hidden) { item in
                Button {
                    onHide?(item.target, false)
                } label: {
                    if let place = item.place {
                        Label(String(localized: "Show \(item.symbol) on \(place)"), systemImage: "eye")
                    } else {
                        Label(String(localized: "Show \(item.symbol)"), systemImage: "eye")
                    }
                }
            }
        } label: {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "eye.slash")
                    .dsGlyph(.body, weight: .medium)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: DS.Face.list, height: DS.Face.list)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Hidden · \(hidden.count)"))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Text(String(localized: "\(WalletValue.money(hidden.reduce(0) { $0 + $1.usd })), not in the total"))
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: DS.Space.s2)
            }
            // The Tokens rows' one pitch (prd §1482), as the dust row's.
            .walletRowPitch()
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
                VStack(alignment: .leading, spacing: 2) {
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
            .walletRowPitch()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .padding(.horizontal, DS.Space.s4)
    }
}

/// A token's Hide, from a long press (prd §1591): the Tokens list's rows and
/// Holdings' own. A row made of one source hides by its symbol, as before. A
/// row made of more (a spam token wearing the real one's symbol, or a wallet
/// beside an exchange) lists each contract with its place and worth, so the
/// spam goes and the real money stays, and "Every <symbol>" hides them all.
struct TokenHideMenu: View {
    let position: WalletPortfolio.Position
    let onHide: (HiddenTokens.Target, Bool) -> Void

    /// Contracts, plus one for any exchange, bank or app holding the symbol.
    static func sources(_ position: WalletPortfolio.Position) -> Int {
        position.contracts.count + (position.holders.contains { WalletPortfolio.isVenue($0.address) } ? 1 : 0)
    }

    var body: some View {
        if Self.sources(position) > 1 {
            Menu {
                ForEach(position.contracts, id: \.key) { contract in
                    Button {
                        onHide(.contract(contract.key), true)
                    } label: {
                        Text(verbatim: line(contract))
                    }
                }
                Button {
                    onHide(.symbol(position.symbol), true)
                } label: {
                    Text("Every \(position.symbol)")
                }
            } label: {
                Label(String(localized: "Hide \(position.symbol)"), systemImage: "eye.slash")
            }
        } else {
            Button {
                onHide(.symbol(position.symbol), true)
            } label: {
                Label(String(localized: "Hide \(position.symbol)"), systemImage: "eye.slash")
            }
        }
    }

    /// "Base · ...e07a · $512", the worth left out under Hide balances.
    private func line(_ contract: (key: String, usd: Double)) -> String {
        let place = HiddenTokens.place(contract.key)
        return BalancePrivacy.shared.withheld ? place : "\(place) · \(WalletValue.money(contract.usd))"
    }
}
