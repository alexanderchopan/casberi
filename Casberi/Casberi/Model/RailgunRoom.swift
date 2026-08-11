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

    // MARK: - The bar

    static func share(moves: Int, of top: Int) -> Double {
        guard top > 0 else { return 0 }
        return min(max(Double(moves) / Double(top), 0), 1)
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

    /// "340.5 USDC shielded" — plain units, not `.formatted(.currency())`:
    /// a token symbol is not an ISO 4217 code. Self-contained (not
    /// `WalletIngest.format`) so this file stays Foundation-only.
    static func amountText(_ amount: Double, symbol: String) -> String {
        let formatted = amount.formatted(.number.precision(.fractionLength(0...4)))
        return "\(formatted) \(symbol)"
    }

    /// The line beside a token: how much moved, in real units when known,
    /// falling back to a bare count — the `PeerRoom.tokenLine` shape.
    static func tokenLine(_ token: Token) -> String {
        if let shielded = token.shieldedAmount, let unshielded = token.unshieldedAmount,
           token.shields > 0, token.unshields > 0 {
            return String(localized: "\(amountText(shielded, symbol: token.symbol)) shielded · \(amountText(unshielded, symbol: token.symbol)) received")
        }
        if token.unshields > 0 {
            if let unshielded = token.unshieldedAmount {
                return String(localized: "\(amountText(unshielded, symbol: token.symbol)) received")
            }
            return token.unshields == 1 ? String(localized: "1 received")
                                        : String(localized: "\(token.unshields) received")
        }
        if let shielded = token.shieldedAmount {
            return String(localized: "\(amountText(shielded, symbol: token.symbol)) shielded")
        }
        return token.shields == 1 ? String(localized: "1 shielded")
                                  : String(localized: "\(token.shields) shielded")
    }

    /// The one line at the top of the card. Volume leads, the same reasoning
    /// as `PeerRoom.headline`: nothing here is trouble, so there is no
    /// "trouble first" rung to open with.
    static func headline(_ room: RailgunRoom) -> String {
        guard room.moves > 0 else { return String(localized: "Nothing has moved yet") }
        guard let lead = room.lead else {
            // Real moves, no token honestly readable on any of them.
            return String(localized: "\(movesLabel(room.moves)) through Railgun")
        }
        if room.tokens.count > 1 {
            return String(localized: "Mostly \(lead.symbol) — \(movesLabel(room.moves)) across \(room.tokens.count) tokens")
        }
        return String(localized: "\(movesLabel(room.moves)) in \(lead.symbol)")
    }

    /// The line under it — the SHAPE of the traffic (in vs out), never a
    /// restatement of the headline's token/volume.
    static func note(_ room: RailgunRoom) -> String {
        if room.shields > 0 && room.unshields > 0 {
            return String(localized: "\(room.shields) shielded · \(room.unshields) received")
        }
        if room.unshields > 0 {
            return String(localized: "Receiving only — \(room.unshields) in, nothing shielded")
        }
        if room.shields > 0 {
            return String(localized: "Shielding only — \(room.shields) in, nothing received")
        }
        return String(localized: "Nothing has moved yet")
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
