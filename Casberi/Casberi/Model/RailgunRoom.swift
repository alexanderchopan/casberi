import Foundation

/// THE RAILGUN ROOM'S HEAD (2026-08-11) — what's moving through the shielded
/// pool, by token.
///
/// Railgun was the one wallet-riding seat (`RailgunBridge`, prd §268) with no
/// room head at all, unlike its three siblings (`PeerRoom`, `PrivacyPoolsRoom`,
/// `GnosisPayRoom`, prd §349) — a plain list of shields and unshields with no
/// standing answer to "what am I actually moving through this". This is that
/// answer, grouped the way Railgun's own doc already reasons about it: there is
/// no "rail" here (no funding platform, no maker/taker), so the one axis worth
/// grouping on is the TOKEN.
///
/// ## It spends nothing
///
/// Every fact is on a landed row — the `sourceRef` prefix `RailgunBridge`
/// stamps (`railgun:shield:…` / `railgun:unshield:…`) and, since 2026-08-11,
/// `priceValue`/`priceCurrency`: the SAME generic "amount, in this currency,
/// never summed across currencies" meaning `GnosisPayRoom` and `PeerRoom`
/// already read. No request, no new `Thing` property, no CloudKit deploy.
///
/// ## What it may NOT draw: a sender, or the pool's inside
///
/// `RailgunBridge`'s own honesty rule carries straight through: an unshield
/// can never name who sent it (the chain cannot tell "you withdrew" from
/// "someone paid you" — that is the product working), and nothing inside the
/// pool is read, estimated, or implied. This card only ever counts and sums
/// what the bridge already landed as SHIELD or UNSHIELD moves.
///
/// ## What it may NOT draw: a complete history
///
/// `RailgunBridge`'s own doc states the ceiling plainly: only a DIRECT move is
/// attributable, and that is about half of them (RelayAdapt-routed and
/// native-ETH shields carry no wallet→pool transfer log at all). That ceiling
/// is already named on the catalog summary, the setup screen, and the seat's
/// own capability lines — this card doesn't repeat it, the same way
/// `PeerRoom` doesn't repeat "capture only" in its footnote either.
///
/// Foundation-only by design so `scripts/wallet-rooms-selftest.sh` can compile
/// it WHOLE and unmodified. Everything touching `Thing` lives in
/// `RailgunRoomSource`.
struct RailgunRoom: Equatable {

    // MARK: - What a row is

    enum Direction: String, Equatable {
        case shield, unshield
    }

    /// The `sourceRef` prefixes `RailgunBridge` lands. Neither is a prefix of
    /// the other, so — unlike `PeerRoom.kind(ref:)` — there is no ordering
    /// trap here; the explicit table is kept anyway, for the same reason
    /// every sibling room keeps one: a ref shape this build doesn't
    /// recognise must read as nil, never as a guess.
    static let prefixes: [(String, Direction)] = [
        ("railgun:shield:", .shield),
        ("railgun:unshield:", .unshield),
    ]

    static func direction(ref: String?) -> Direction? {
        guard let ref else { return nil }
        for (prefix, direction) in prefixes where ref.hasPrefix(prefix) { return direction }
        return nil
    }

    /// One landed row, reduced to what this card reads.
    struct Sighting: Equatable {
        let ref: String?
        /// `Thing.priceCurrency` — the token's symbol. Nil whenever the
        /// contract answered no real `symbol()` (the row then wears a
        /// shortened hex address in its title, and this card excludes it
        /// from every token bucket rather than group under a fake name).
        let token: String?
        /// `Thing.priceValue`. Nil whenever `decimals()` couldn't be read,
        /// even if the symbol is known — the same pairing `RailgunBridge`
        /// requires before it will state an amount at all.
        let amount: Double?
        let at: Date
    }

    /// One token's standing — the `PeerRoom.Token` shape, keyed by symbol
    /// instead of funding rail (Railgun has no rail to group by).
    struct Token: Identifiable, Equatable {
        var id: String { symbol }
        let symbol: String
        let shields: Int
        let unshields: Int
        /// Sum of `amount` across SHIELD moves for this token — nil unless
        /// every shield counted here carried a known amount. A partial sum
        /// presented as complete is the failure this stays silent to avoid.
        let shieldedAmount: Double?
        let unshieldedAmount: Double?
        let newest: Date
        var moves: Int { shields + unshields }
    }

    /// Ranked — see `ordered`.
    let tokens: [Token]
    /// Every settled shield. `unplaced` is a SUBSET, not a sibling — see
    /// `PeerRoom.unplaced` for the identical reasoning.
    let shields: Int
    let unshields: Int
    /// Moves whose token symbol could not be read at all. Counted, never
    /// bucketed under an invented "Unknown" token.
    let unplaced: Int
    let newest: Date?

    /// Below this the card is not worth drawing: one move is a row, and the
    /// row already says everything this card would.
    static let minimumMoves = 2

    var moves: Int { shields + unshields }
    var lead: Token? { tokens.first }
    var isEmpty: Bool { moves < RailgunRoom.minimumMoves }

    // MARK: - Composing

    static func compose(moves sightings: [Sighting]) -> RailgunRoom {
        var shields = 0, unshields = 0, unplaced = 0
        var newest: Date?
        var buckets: [String: (shields: Int, unshields: Int,
                               shieldedAmount: Double, shieldedKnown: Bool,
                               unshieldedAmount: Double, unshieldedKnown: Bool,
                               newest: Date)] = [:]

        for sighting in sightings {
            guard let dir = direction(ref: sighting.ref) else { continue }
            if newest == nil || sighting.at > newest! { newest = sighting.at }
            if dir == .shield { shields += 1 } else { unshields += 1 }

            let symbol = sighting.token?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let symbol, !symbol.isEmpty else { unplaced += 1; continue }
            var bucket = buckets[symbol] ?? (shields: 0, unshields: 0,
                                             shieldedAmount: 0, shieldedKnown: true,
                                             unshieldedAmount: 0, unshieldedKnown: true,
                                             newest: sighting.at)
            if dir == .shield {
                bucket.shields += 1
                if let amount = sighting.amount { bucket.shieldedAmount += amount }
                else { bucket.shieldedKnown = false }
            } else {
                bucket.unshields += 1
                if let amount = sighting.amount { bucket.unshieldedAmount += amount }
                else { bucket.unshieldedKnown = false }
            }
            if sighting.at > bucket.newest { bucket.newest = sighting.at }
            buckets[symbol] = bucket
        }

        let tokens = buckets.map { symbol, b in
            Token(symbol: symbol, shields: b.shields, unshields: b.unshields,
                 shieldedAmount: (b.shields > 0 && b.shieldedKnown) ? b.shieldedAmount : nil,
                 unshieldedAmount: (b.unshields > 0 && b.unshieldedKnown) ? b.unshieldedAmount : nil,
                 newest: b.newest)
        }
        return RailgunRoom(tokens: ordered(tokens), shields: shields, unshields: unshields,
                           unplaced: unplaced, newest: newest)
    }

    // MARK: - Ranking

    /// Moves, then recency, then symbol — TOTAL, the `PeerRoom.ordered`
    /// reasoning. No "trouble first" rung: neither a shield nor an unshield
    /// is trouble, and the one honest caveat this seat carries (only direct
    /// moves are attributable) is stated on the setup screen, not ranked.
    static func ordered(_ tokens: [Token]) -> [Token] {
        tokens.sorted { a, b in
            if a.moves != b.moves { return a.moves > b.moves }
            if a.newest != b.newest { return a.newest > b.newest }
            return a.symbol < b.symbol
        }
    }

    // MARK: - The drawing

    /// The per-token drawing: how much went INTO the pool against how much
    /// came BACK, as two fractions — the hairline pair `RailgunRoomCard`
    /// draws under each token's figures.
    ///
    /// **Each row is scaled to its OWN maximum, never to a shared one, and
    /// that is the whole honesty of it.** No two tokens here share a unit
    /// (3 ETH against 500 DAI is the sum this room already refuses to make),
    /// so a common axis would invite exactly the comparison the composer
    /// declines. Scaled to itself, the pair claims only what is true of one
    /// token: this much went in, this much of it came back.
    ///
    /// Which is also why it REPLACED a share-of-the-busiest-token bar
    /// (prd §485, 2026-08-26): that bar measured MOVE COUNT while the line of text
    /// beside it stated an AMOUNT, so read left to right it looked like a
    /// picture of the number printed next to it. One row, one quantity.
    ///
    /// nil whenever either side's amount is unknown — a direction with no
    /// readable amount cannot be drawn against one that has one, and half a
    /// pair drawn as a whole is the partial-sum failure `Token` exists to
    /// refuse. A direction with no MOVES is a real zero, not an unknown.
    static func pair(_ token: Token) -> (into: Double, back: Double)? {
        let into: Double? = token.shields == 0 ? 0 : token.shieldedAmount
        let back: Double? = token.unshields == 0 ? 0 : token.unshieldedAmount
        guard let into, let back else { return nil }
        let top = max(into, back)
        guard top > 0 else { return nil }
        return (min(into / top, 1), min(back / top, 1))
    }

    // MARK: - Days

    static func days(from now: Date, to later: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - Words

    static func movesLabel(_ count: Int) -> String {
        count == 1 ? String(localized: "1 move") : String(localized: "\(count) moves")
    }

    /// "340.5 USDC" — plain units, not `.formatted(.currency())`: a token
    /// symbol is not an ISO 4217 code. Self-contained (not
    /// `WalletIngest.format`) so this file stays Foundation-only.
    ///
    /// `symbol` is OPTIONAL because on the card the token's name is the row's
    /// own leading label, so repeating it inside both figures beside it said
    /// the same word three times on one line. The probe still passes one.
    ///
    /// `mask` is the §374 hide-balances string, PASSED IN rather than read:
    /// this file is Foundation-only and compiled WHOLE by
    /// `scripts/wallet-rooms-selftest.sh`, so it cannot reach `BalancePrivacy`.
    static func amountText(_ amount: Double, symbol: String? = nil, mask: String? = nil) -> String {
        let figure = mask ?? amount.formatted(.number.precision(.fractionLength(0...4)))
        guard let symbol, !symbol.isEmpty else { return figure }
        return "\(figure) \(symbol)"
    }

    /// The figures beside a token: what went in, and what came back — in real
    /// units when known, falling back to a bare count.
    ///
    /// `symbol` defaults to nil for the card (the row already names the
    /// token); the probe passes the symbol so a dumped line stands alone.
    /// `mask` — see `amountText`. The bare-count fallbacks are unaffected: a
    /// count of shields is not a balance.
    static func tokenLine(_ token: Token, symbol: String? = nil, mask: String? = nil) -> String {
        if let shielded = token.shieldedAmount, let back = token.unshieldedAmount,
           token.shields > 0, token.unshields > 0 {
            return String(localized: "\(amountText(shielded, symbol: symbol, mask: mask)) shielded · \(amountText(back, symbol: symbol, mask: mask)) back")
        }
        if token.unshields > 0 {
            if let back = token.unshieldedAmount {
                return String(localized: "\(amountText(back, symbol: symbol, mask: mask)) received")
            }
            return token.unshields == 1 ? String(localized: "1 received")
                                        : String(localized: "\(token.unshields) received")
        }
        if let shielded = token.shieldedAmount {
            return String(localized: "\(amountText(shielded, symbol: symbol, mask: mask)) shielded")
        }
        return token.shields == 1 ? String(localized: "1 shielded")
                                  : String(localized: "\(token.shields) shielded")
    }

    /// The one line at the top of the card. Volume leads, the same reasoning
    /// as `PeerRoom.headline`: nothing here is trouble, so there is no
    /// "trouble first" rung to open with.
    ///
    /// **The subline under it retired 2026-08-26** (§483's restraint, applied
    /// one room over). It read "7 shielded · 5 received" — which, now that
    /// every drawn token carries both of its own figures, is the sum of one
    /// column and the sum of the other, both already on screen. Exactly the
    /// deletion the wallet crown's caption took, for exactly §208's reason.
    static func headline(_ room: RailgunRoom) -> String {
        guard room.moves > 0 else { return String(localized: "Nothing has moved yet") }
        // TWO cases, not three (2026-08-26). "6 moves in ETH" over a single row
        // labelled ETH printed the token's name twice in fourteen points of
        // each other; the room-level sentence now says what only it can say,
        // and the rows name the tokens. The same sentence covers a room where
        // no token was readable at all — true in both, and the rows below are
        // what tell them apart.
        guard let lead = room.lead, room.tokens.count > 1 else {
            return String(localized: "\(movesLabel(room.moves)) through Railgun")
        }
        return String(localized: "Mostly \(lead.symbol) — \(movesLabel(room.moves)) across \(room.tokens.count) tokens")
    }

    /// The quiet line at the foot: tokens not drawn, moves that could not be
    /// placed, and how long the room has been still.
    static func footnote(_ room: RailgunRoom, drawn: Int, now: Date = .now) -> String? {
        var parts: [String] = []
        let hidden = room.tokens.count - drawn
        if hidden > 0 {
            parts.append(hidden == 1 ? String(localized: "1 more token")
                                     : String(localized: "\(hidden) more tokens"))
        }
        if room.unplaced > 0 {
            parts.append(room.unplaced == 1
                         ? String(localized: "1 move has no readable token")
                         : String(localized: "\(room.unplaced) moves have no readable token"))
        }
        if let idle = idleNote(newest: room.newest, now: now) { parts.append(idle) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "nothing for 45 days" — the `PrivacyPoolsRoom` threshold: shielding is
    /// a deliberate, occasional act, not a habit with a natural cadence.
    static func idleNote(newest: Date?, now: Date = .now, quietAfter: Int = 45) -> String? {
        guard let newest else { return nil }
        let days = days(from: newest, to: now)
        guard days >= quietAfter else { return nil }
        return String(localized: "nothing for \(days) days")
    }
}
