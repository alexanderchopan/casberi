import SwiftUI

/// WHERE THE MONEY MOVED, AS ROWS — the Wallet Home list (prd §692, user:
/// *"i don't like the sankey on the home list area it looks weird to have a
/// chart there now that i see it. can we change it to a list format"*).
///
/// **The reading is unchanged; the shape is not.** §690 put `WalletFlowBand`
/// in Home's list half because the crown says how much moved and the band says
/// through whom. That substance stands — this draws the SAME
/// `WalletFlow.Band`, so no number here can disagree with the one the brief's
/// band states. What changed is that the list half of a room is a list
/// everywhere else in this app, and a diagram sitting in it reads as a second
/// figure under the crown's own.
///
/// **The net leads (prd §695).** "in $7K · out $3K · Kept +$4K" is the one
/// reading neither block can state — a column of amounts says where the money
/// went, and only their difference says whether you ended up with more. It was
/// the band's and was dropped when the drawing became rows; putting it back is
/// the correction.
///
/// **Two blocks, because in and out are two facts.** A single list of signed
/// amounts makes the reader do the grouping the band did for free; captioned
/// blocks are the grammar this app already uses when one scope holds two kinds
/// of thing (`RoomListBlock`, Frames' sponsor list before it).
///
/// **A row says WHO, HOW MANY and HOW MUCH, and nothing else.** No share bar:
/// the amounts are already comparable as numbers down one column, and a bar
/// per row is the tally §292 refused. The folded "Other" lane keeps its own
/// row — dropping it would leave the two block totals unaccounted for, which
/// is the §510 contradiction (a census and a capped drawing disagreeing with
/// nothing to reconcile them).
///
/// The band itself is NOT deleted: `GenRenderer` draws it from
/// `TodayBrief.flowBand`, where a diagram in a brief is the right shape.
///
/// **A TOKEN WITH NO PRICE IS A ROW, NOT A REASON TO DRAW NOTHING (prd §727,
/// user: "it could also say how much of a token came in without converting it
/// into dollars" → "plain row").** Home used to take the brief's `Band`, and
/// with it the floor that refuses a window less than half priced — so a wallet
/// that is mostly airdropped tokens nobody trades read "Only 31 of 99 moves
/// carry a price" over an empty bar, while its real USDC and WETH moves went
/// unlisted. It takes `WalletFlow.Home` now: the priced rows with no floor,
/// then one plain row per token that came in unpriced — symbol and quantity,
/// no sender, no dollar figure, and never in the net above.
struct WalletFlowRows: View {
    let home: WalletFlow.Home
    /// The window the band was read over — "the last 24 hours", say. Stated
    /// once above the blocks rather than per block, since both describe it.
    let windowLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            if let band = home.band {
                summaryLine(band)
                if !band.inLanes.isEmpty {
                    RoomListBlock(caption: String(localized: "Came in · \(windowLabel)")) {
                        lanes(band.inLanes, incoming: true)
                    }
                }
                if !band.outLanes.isEmpty {
                    RoomListBlock(caption: String(localized: "Went out · \(windowLabel)")) {
                        lanes(band.outLanes, incoming: false)
                    }
                }
            }
            if !home.tokens.isEmpty {
                RoomListBlock(caption: String(localized: "Came in with no price · \(windowLabel)")) {
                    tokenRows(home.tokens)
                }
            }
            if let note = unpricedNote {
                Text(note)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// **THE NET, PUT BACK (prd §695, user: "ok, so yes put net back").**
    ///
    /// `WalletFlowBand` carried "in $7K · out $3K · Kept +$4K" above its
    /// drawing and §692 dropped it silently when the drawing became rows —
    /// substance lost to a shape change, which is the thing a shape change is
    /// least entitled to do. It is the one reading neither block can state: a
    /// column of amounts says where the money went and only their difference
    /// says whether you ended up with more.
    ///
    /// **`WalletValue.money`, the same formatter the band used**, so the two
    /// surfaces cannot round one window two ways.
    ///
    /// **A net that rounds to nothing draws no line at all** — §83's `isFlat`
    /// rule, that a change with no direction gets no sign and no colour — and
    /// a down window stays in plain ink rather than red: spending is not a
    /// failure, and red here would be the app grading an ordinary week.
    @ViewBuilder
    private func summaryLine(_ band: WalletFlow.Band) -> some View {
        let net = band.netUSD
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Text("in \(WalletValue.money(band.inUSD)) · out \(WalletValue.money(band.outUSD))")
                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                .monospacedDigit()
            if abs(net) >= 1 {
                Text(net > 0
                     ? String(localized: "Kept +\(WalletValue.money(net))")
                     : String(localized: "Down −\(WalletValue.money(-net))"))
                    .dsText(.subhead12)
                    .foregroundStyle(net > 0 ? DS.confirm : DS.textSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1).minimumScaleFactor(0.85)
    }

    @ViewBuilder
    private func lanes(_ lanes: [WalletFlow.Lane], incoming: Bool) -> some View {
        VStack(spacing: DS.Space.s2) {
            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                WalletRow(mark: mark(lane),
                          title: title(lane),
                          subtitle: transactions(lane.count)) {
                    // **THE SIGN IS THE DIRECTION, and the block caption says
                    // it too.** Both, deliberately: a row read alone — by
                    // VoiceOver, or scrolled past its caption — has to carry
                    // which way the money went.
                    WalletRowValue(value: (incoming ? "+" : "−") + WalletValue.money(lane.usd))
                }
                .chartArrival(index: index, reduceMotion: reduceMotion)
            }
        }
    }

    /// One plain row per token that came in with no price (prd §727). The
    /// terminal form: nothing opens, because a row here is usually several
    /// moves folded together, the same reason a lane opens nothing.
    @ViewBuilder
    private func tokenRows(_ tokens: [WalletFlow.UnpricedToken]) -> some View {
        VStack(spacing: DS.Space.s2) {
            ForEach(Array(tokens.enumerated()), id: \.element.id) { index, token in
                WalletRow(terminal: tokenMark(token),
                          title: tokenTitle(token),
                          subtitle: transactions(token.count))
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
        }
    }

    /// The token's own mark where the app bundles one, a quiet monogram where
    /// it doesn't. Quiet ink, because an unpriced token is not money this
    /// card can vouch for.
    private func tokenMark(_ token: WalletFlow.UnpricedToken) -> WalletRowMark {
        if token.isOther { return .symbol("ellipsis", tint: DS.textTertiary) }
        return .asset(token.symbol, tint: DS.textTertiary)
    }

    /// "1,000 MCAT", through `WalletValue.token` so hidden balances hide the
    /// quantity and keep the symbol (§374). A token whose amount could not be
    /// summed says its symbol alone rather than a partial number.
    private func tokenTitle(_ token: WalletFlow.UnpricedToken) -> String {
        if token.isOther {
            return token.tokens == 1
                ? String(localized: "1 more token")
                : String(localized: "\(String(token.tokens)) more tokens")
        }
        guard let amount = token.amount else { return token.symbol }
        return WalletValue.token(amount, token.symbol)
    }

    private func transactions(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 transaction")
            : String(localized: "\(String(count)) transactions")
    }

    /// A counterparty wears its FACE; the folded lane wears a glyph, because
    /// it is not a party at all.
    private func mark(_ lane: WalletFlow.Lane) -> WalletRow.Mark {
        if lane.isOther { return .symbol("ellipsis", tint: DS.textTertiary) }
        return .face(lane.key)
    }

    /// **An unnamed counterparty shows its ADDRESS, not an empty line.** The
    /// band could draw a value alone in a slab this narrow; a row has a title
    /// column that would sit blank, and a short address is what every other
    /// list in this app puts there.
    private func title(_ lane: WalletFlow.Lane) -> String {
        if !lane.name.isEmpty { return lane.name }
        return WalletStore.shortAddress(lane.key)
    }

    /// What no row names, said once at the foot. Since §727 the unpriced moves
    /// that came in are ROWS, so this counts only the rest: sent ones, and any
    /// stamped with no symbol.
    private var unpricedNote: String? {
        var parts: [String] = []
        if home.unlistedUnpriced > 0 {
            parts.append(home.unlistedUnpriced == 1
                         ? String(localized: "1 move had no price to read")
                         : String(localized: "\(String(home.unlistedUnpriced)) moves had no price to read"))
        }
        if home.predatingCount > 0 {
            parts.append(home.predatingCount == 1
                         ? String(localized: "1 predates what this app priced")
                         : String(localized: "\(String(home.predatingCount)) predate what this app priced"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
