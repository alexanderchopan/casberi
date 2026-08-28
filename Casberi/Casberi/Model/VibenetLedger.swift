import Foundation

/// The vibenet reads this room was making and throwing away — money movement,
/// the chain's own pulse, an account's origin, a policy's individual runs, and
/// the identity of a token whose `decimals()` does not answer (prd §507,
/// 2026-08-28).
///
/// **Every type here is pure and Foundation-only**, for the reason
/// `VibenetRoom.swift` is: nothing on this host can make a devnet transfer a
/// token, halt a chain, or run a session key, so `scripts/vibenet-selftest.sh`
/// compiling this file WHOLE is not the best proof these numbers are right —
/// it is the only one. A separate file rather than more of `VibenetRoom.swift`
/// (already ~3,900 lines) so the harness can name what it is proving.
///
/// ## What each of these is for, and the honesty rail on it
///
/// The room could say what an account HOLDS and never what MOVED: there is not
/// one `Transfer` topic in the bridge, so Activity held key and lock events
/// only, Holdings drew a number with no motion, and the balance curve was
/// built out of our own polling — six app opens before it could draw a line,
/// and structurally blind to everything before the day you started watching.
/// The chain has all of it. What follows is the arithmetic that turns those
/// logs into readings, with one rule running through the whole file: **a
/// bounded read may never present itself as a complete one** (`isComplete`
/// below, and `VibenetLedger.cap`).

// MARK: - Transfers

/// Which way a transfer went, from the watched account's point of view.
///
/// `.selfMove` is a real and separate answer rather than a rounding of "in":
/// an account sending to itself moves no value, so counting it as either
/// direction would inflate both a counterparty's tally and the reconstructed
/// balance series by exactly the amount that never left.
enum VibenetTransferDirection: String, Equatable, Codable, Sendable {
    case incoming, outgoing, selfMove

    /// The sign this transfer applies to the account's balance. Zero for a
    /// self-move, which is the whole reason the case exists.
    var sign: Double {
        switch self {
        case .incoming: return 1
        case .outgoing: return -1
        case .selfMove: return 0
        }
    }
}

/// One ERC-20 `Transfer` touching a watched account.
///
/// `at` is OPTIONAL and never defaulted to `.now`: a block whose timestamp
/// could not be read is a transfer we cannot place in time, and stamping it
/// with the moment we looked would date real history to today — the mistake
/// `WalletApprovals` and `PeerRoom` each already have a rule against.
struct VibenetTransfer: Identifiable, Equatable, Codable, Sendable {
    /// Unique on chain: one log is one (transaction, index) pair.
    var id: String { "\(txHash):\(logIndex)" }
    let symbol: String
    let direction: VibenetTransferDirection
    /// The other side. For a self-move this is the account itself.
    let counterparty: String
    /// Scaled by the token's own confirmed decimals — never by an assumed 18
    /// (`VibenetTokenIdentity`'s whole reason for existing).
    let amount: Double
    let at: Date?
    let txHash: String
    let block: Int
    let logIndex: Int
    /// An ERC-721 transfer's token id, when this move was one.
    ///
    /// **The two Transfer events are the SAME signature and a different
    /// shape**, which is the trap here: an ERC-20 carries three topics and
    /// puts the amount in `data`; an ERC-721 indexes the token id as a FOURTH
    /// topic and carries no data at all. A decoder written for one reads the
    /// other as an amount of zero — a transfer of nothing, landed as a real
    /// row — so the topic count is what decides, and a 721 move is one item
    /// with an id rather than an amount.
    var tokenID: String? = nil

    init(symbol: String, direction: VibenetTransferDirection, counterparty: String,
         amount: Double, at: Date?, txHash: String, block: Int, logIndex: Int,
         tokenID: String? = nil) {
        self.symbol = symbol
        self.direction = direction
        self.counterparty = counterparty
        self.amount = amount
        self.at = at
        self.txHash = txHash
        self.block = block
        self.logIndex = logIndex
        self.tokenID = tokenID
    }

    /// What the row says moved — "12.5 USDV", or "NFV #42" for a token id.
    var display: String {
        if let tokenID { return "\(symbol) #\(tokenID)" }
        return "\(VibenetBalanceFormat.line(amount)) \(symbol)"
    }
}

/// A person or contract this account has moved tokens with, and how often.
///
/// **Ranked by the NUMBER OF MOVES, never by amount**, and that is not a
/// preference: an account can hold two tokens with no shared unit and no
/// price, so ordering by size would silently compare 500 USDV against 12 NFV.
/// The same ruling `PrivacyPoolsRoom` makes about its own holdings, and
/// §349's about a room that cannot sum.
struct VibenetCounterparty: Identifiable, Equatable, Sendable {
    var id: String { address }
    let address: String
    let incoming: Int
    let outgoing: Int
    /// The most recent move with this address, when any of them could be
    /// dated. Nil is "we could not place it", never "long ago".
    let newest: Date?

    var moves: Int { incoming + outgoing }

    /// "4 moves · 3 in, 1 out". Never a total amount, for the reason the
    /// type's own doc gives.
    var line: String {
        let count = moves == 1 ? String(localized: "1 move") : String(localized: "\(moves) moves")
        if incoming > 0 && outgoing > 0 {
            return "\(count) · \(String(localized: "\(incoming) in, \(outgoing) out"))"
        }
        if outgoing == 0 { return "\(count) · \(String(localized: "received only"))" }
        return "\(count) · \(String(localized: "sent only"))"
    }
}

/// A reconstructed balance-over-time series for ONE token.
///
/// The points are real: each is the balance implied by the account's CURRENT
/// balance walked backwards over its own transfers, so nothing here is
/// interpolated and nothing is a guess. What it cannot promise is that it
/// reaches the beginning — see `isComplete`.
struct VibenetBalanceSeries: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        let at: Date
        let balance: Double
    }
    let symbol: String
    /// Oldest first, so it plots left to right like every other curve here.
    let points: [Point]
    /// Whether the walk reached this account's first transfer.
    ///
    /// **False means the earliest point is a POSITION, not a beginning.** The
    /// log read is bounded (`VibenetLedger.cap`, and `VibenetLogChunking`'s
    /// own block reach above it), so a busy account's oldest visible point is
    /// simply where our reading starts. A view that draws an incomplete series
    /// as though it began at zero tells the same lie a truncated import tells
    /// (§307), in a picture.
    let isComplete: Bool

    var values: [Double] { points.map(\.balance) }
}

enum VibenetLedger {
    /// How many transfers per account we keep. A devnet account is not a
    /// wallet with a decade of history, and this bounds both the block-time
    /// lookups the read pays for and the size of the persisted snapshot.
    ///
    /// A read that COMES BACK FULL is the signal, not the ceiling: see
    /// `series`'s `isComplete`.
    static let cap = 120

    /// Newest first, by block then log index — a TOTAL order, so a persisted
    /// snapshot and a fresh read of an identical chain can never disagree
    /// about which transfer leads (`VibenetPolicyUse`'s own rule; `Dictionary`
    /// iteration order is not stable across runs and neither is an RPC's).
    static func ordered(_ transfers: [VibenetTransfer]) -> [VibenetTransfer] {
        transfers.sorted { a, b in
            if a.block != b.block { return a.block > b.block }
            if a.logIndex != b.logIndex { return a.logIndex > b.logIndex }
            return a.txHash > b.txHash
        }
    }

    /// The bound applied AFTER ordering, so what is kept is the newest — the
    /// opposite order drops today's transfers to keep last month's, which is
    /// the silent-truncation class (§307) wearing a cap that looks correct.
    static func capped(_ transfers: [VibenetTransfer]) -> [VibenetTransfer] {
        Array(ordered(transfers).prefix(cap))
    }

    /// Who this account moves tokens with, ranked.
    ///
    /// A SELF-MOVE IS EXCLUDED: the account is not its own counterparty, and
    /// listing it would put the row you are already looking at at the top of
    /// its own list. Ties break by newest, then by address, so the order is
    /// total.
    static func counterparties(_ transfers: [VibenetTransfer], limit: Int = 6)
        -> [VibenetCounterparty] {
        var incoming: [String: Int] = [:]
        var outgoing: [String: Int] = [:]
        var newest: [String: Date] = [:]
        var casing: [String: String] = [:]
        for t in transfers where t.direction != .selfMove {
            let key = t.counterparty.lowercased()
            guard key.contains(where: { $0 != "0" && $0 != "x" }) else { continue }
            casing[key] = casing[key] ?? t.counterparty
            switch t.direction {
            case .incoming: incoming[key, default: 0] += 1
            case .outgoing: outgoing[key, default: 0] += 1
            case .selfMove: break
            }
            if let at = t.at, at > (newest[key] ?? .distantPast) { newest[key] = at }
        }
        let rows = casing.keys.map { key in
            VibenetCounterparty(address: casing[key] ?? key,
                                incoming: incoming[key] ?? 0,
                                outgoing: outgoing[key] ?? 0,
                                newest: newest[key])
        }
        return Array(rows.sorted { a, b in
            if a.moves != b.moves { return a.moves > b.moves }
            let an = a.newest ?? .distantPast, bn = b.newest ?? .distantPast
            if an != bn { return an > bn }
            return a.address.localizedCaseInsensitiveCompare(b.address) == .orderedAscending
        }.prefix(limit))
    }

    /// The balance curve implied by a CURRENT balance and the transfers that
    /// produced it — the reading `VibenetValueHistory` could never make,
    /// because it can only record what it saw while the app was open.
    ///
    /// Walks BACKWARDS from now: the balance before a transfer is the balance
    /// after it minus what that transfer did. Each transfer therefore
    /// contributes the point immediately BEFORE it, and `now` carries the
    /// current balance. Undated transfers are dropped from the walk rather
    /// than placed — an undated point has no x — and dropping one makes the
    /// series incomplete, because every earlier point is then off by its
    /// amount.
    ///
    /// Returns nil under two points: one point is a flat line and a flat line
    /// on a balance chart reads as "went to zero", the failure this codebase
    /// names in three other places.
    static func series(symbol: String, current: Double, transfers: [VibenetTransfer],
                       now: Date, capReached: Bool = false) -> VibenetBalanceSeries? {
        let mine = ordered(transfers).filter { $0.symbol == symbol }
        guard !mine.isEmpty else { return nil }
        var points: [VibenetBalanceSeries.Point] = [.init(at: now, balance: current)]
        var running = current
        var dropped = false
        for t in mine {
            // A token-id move is not an amount and must never enter a balance
            // walk: adding 1 for an NFT to a USDV curve would bend the line by
            // a number that means "one thing", not "one token".
            guard t.tokenID == nil else { dropped = true; continue }
            guard let at = t.at else { dropped = true; continue }
            running -= t.amount * t.direction.sign
            points.append(.init(at: at, balance: running))
        }
        guard points.count >= 2 else { return nil }
        return VibenetBalanceSeries(symbol: symbol,
                                    points: points.sorted { $0.at < $1.at },
                                    isComplete: !dropped && !capReached)
    }

    /// "3 in, 1 out today" is a tally; this is the one sentence the ledger
    /// earns — what moved, most recently. Nil when nothing has.
    static func lastMoveLine(_ transfers: [VibenetTransfer], now: Date) -> String? {
        guard let newest = ordered(transfers).first(where: { $0.at != nil }),
              let at = newest.at else { return nil }
        let when = at.formatted(.relative(presentation: .named))
        let amount = VibenetBalanceFormat.line(newest.amount)
        switch newest.direction {
        case .incoming: return String(localized: "Received \(amount) \(newest.symbol) \(when)")
        case .outgoing: return String(localized: "Sent \(amount) \(newest.symbol) \(when)")
        case .selfMove: return String(localized: "Moved \(amount) \(newest.symbol) to itself \(when)")
        }
    }
}

// MARK: - The chain's own pulse

/// Whether the devnet is still producing blocks (prd §507).
///
/// **This is the fact an ephemeral devnet most owes its reader and the room
/// could not state.** `VibenetChain.blockNumber()` has been called on every
/// single read since the seat shipped — to chunk the log walk — and its answer
/// was used for arithmetic and thrown away. So "your account is quiet" and
/// "the chain stopped three days ago" rendered identically, on the one network
/// whose own documentation warns it is temporary.
///
/// `readAt` (§468) is a fact about US; this is the fact about the CHAIN, and
/// the two are exactly as different as `ASCStanding.observed` is from a
/// version's own state.
struct VibenetChainPulse: Equatable, Codable, Sendable {
    let tip: Int
    /// When the tip block was mined. Nil when the block-time read failed —
    /// which yields `.unknown` below, never a claim in either direction.
    let lastBlockAt: Date?
    /// Seconds per block, measured across a real span of this chain's own
    /// blocks rather than assumed. Nil when the sample could not be read.
    let secondsPerBlock: Double?

    enum Verdict: String, Equatable, Sendable {
        /// Producing blocks at about the rate it should.
        case moving
        /// Answering, but the tip is older than a handful of expected blocks.
        case slow
        /// Nothing for long enough that this is a fact about the chain, not
        /// about the network in between.
        case stalled
        /// The block time could not be read. NOT an alarm: not knowing and
        /// knowing it is dead are different, and only one of them is news.
        case unknown
    }

    /// How many expected block-times of silence before each verdict. A
    /// MULTIPLE of the measured rate rather than a fixed clock, because a
    /// devnet's block time is its own business — the sibling deployments of
    /// this protocol have run at two seconds and at twelve.
    static let slowAfterBlocks: Double = 20
    static let stalledAfterBlocks: Double = 900
    /// The floors, for a chain whose rate could not be measured (or is
    /// absurdly fast): silence is only interesting after a few minutes, and
    /// only alarming after a few hours.
    static let slowFloor: TimeInterval = 5 * 60
    static let stalledFloor: TimeInterval = 6 * 3600

    func verdict(now: Date = .now) -> Verdict {
        guard let lastBlockAt else { return .unknown }
        let idle = now.timeIntervalSince(lastBlockAt)
        // A tip stamped in the future is a clock disagreement, never a
        // stalled chain — read as moving rather than as an alarm.
        guard idle > 0 else { return .moving }
        let rate = secondsPerBlock ?? 0
        let slowAt = max(Self.slowFloor, rate * Self.slowAfterBlocks)
        let stalledAt = max(Self.stalledFloor, rate * Self.stalledAfterBlocks)
        if idle >= stalledAt { return .stalled }
        if idle >= slowAt { return .slow }
        return .moving
    }

    /// The line the room draws. Silent while the chain is moving normally —
    /// a marker that is always lit is chrome (§493's own ruling about this
    /// room's dots), and "the devnet is working" is not news.
    func line(now: Date = .now) -> String? {
        switch verdict(now: now) {
        case .moving: return nil
        case .unknown: return nil
        case .slow:
            guard let lastBlockAt else { return nil }
            return String(localized: "Last block \(lastBlockAt.formatted(.relative(presentation: .named)))")
        case .stalled:
            guard let lastBlockAt else { return nil }
            return String(localized: "This devnet has produced no block since \(lastBlockAt.formatted(date: .abbreviated, time: .shortened))")
        }
    }

    /// The always-available provenance clause, for the place that already
    /// prints when WE looked — "block 1,284,003" is what the room was read
    /// AGAINST, and on a chain that redeploys it is the only stable coordinate
    /// a screenshot can carry.
    var blockLine: String {
        // Lowercase and grouping-free: this is a FRAGMENT in a caption joined
        // by " · " beside "read 3h ago", not a sentence, and a block height is
        // an identifier rather than a quantity — "1,284,003" reads as an
        // amount of something.
        String(localized: "block \(tip.formatted(.number.grouping(.never)))")
    }

    /// "≈2s a block". Nil when unmeasured — never a default rate, because a
    /// wrong one moves the verdict thresholds above with it.
    var rateLine: String? {
        guard let secondsPerBlock, secondsPerBlock > 0, secondsPerBlock.isFinite else { return nil }
        if secondsPerBlock < 1 { return String(localized: "under a second a block") }
        return String(localized: "≈\(Int(secondsPerBlock.rounded()))s a block")
    }
}

// MARK: - Where an account came from

/// An account's own beginning, off `AccountCreated` (prd §507).
///
/// The bridge has read this event since the seat shipped and only ever
/// GLOBALLY, for the empty state's "recently created" list — the account
/// topic is indexed, so asking it about a watched address was always one
/// filtered read away, and the room could not say how old its own accounts
/// were.
struct VibenetOrigin: Equatable, Codable, Sendable {
    let createdAt: Date?
    /// The account implementation's code hash, out of the event's own data.
    ///
    /// **This is the fact worth having on a chain that redeploys weekly**:
    /// two accounts sharing a hash run the same implementation, and two that
    /// do not are two different builds of it, which no other read here can
    /// see. Never rendered whole — it is 32 bytes nobody reads — and never
    /// resolved into a NAME, because we have no map from hash to build and
    /// inventing one would be §83 in the one place it is unfalsifiable.
    let codeHash: String?
    let txHash: String?
    /// The creating log's index within its transaction — carried for ONE
    /// reason: a landed event's ref is `vibenet:<segment>:<txHash>:<logIndex>`
    /// and one transaction can create several accounts, so a ref built with a
    /// hardcoded zero would dedupe two accounts' creations into one row.
    var logIndex: Int? = nil

    init(createdAt: Date?, codeHash: String?, txHash: String?, logIndex: Int? = nil) {
        self.createdAt = createdAt
        self.codeHash = codeHash
        self.txHash = txHash
        self.logIndex = logIndex
    }

    /// "impl …7f2a" — the short form the Accounts scope groups on.
    var implementationLabel: String? {
        guard let codeHash, codeHash.count >= 6,
              codeHash.dropFirst(2).contains(where: { $0 != "0" }) else { return nil }
        return String(localized: "impl …\(String(codeHash.suffix(4)))")
    }

    func ageLine(now: Date = .now) -> String? {
        guard let createdAt, createdAt <= now else { return nil }
        return String(localized: "Created \(createdAt.formatted(.relative(presentation: .named)))")
    }
}

enum VibenetOrigins {
    /// How many DISTINCT account implementations the watched roster runs.
    ///
    /// Counted over accounts whose origin was actually read — an account we
    /// could not read is not a third implementation, and folding it in would
    /// report drift that is only our own missing data.
    static func implementations(_ origins: [VibenetOrigin?]) -> Int {
        Set(origins.compactMap { $0?.codeHash?.lowercased() }
            .filter { $0.dropFirst(2).contains(where: { $0 != "0" }) }).count
    }

    /// "3 accounts on 2 implementations" — drawn only when they really differ,
    /// because on a healthy roster they never do and a line saying "1
    /// implementation" is a line saying nothing.
    static func driftLine(_ origins: [VibenetOrigin?]) -> String? {
        let n = implementations(origins)
        guard n > 1 else { return nil }
        return String(localized: "\(n) different account implementations")
    }
}

// MARK: - Individual policy runs

/// ONE execution of a policy-gated key (prd §507).
///
/// `VibenetPolicyUse` has folded these per commitment since 2026-08-24 — a
/// count and a most-recent date, shown on one line inside one sheet — so a
/// session key that ran every day produced nothing in Activity at all. The
/// runs were in the same `eth_getLogs` the fold was computed from.
///
/// `caller` is the log's own non-indexed word: who actually invoked the key.
/// It is the difference between "4 uses" and "used by the account you also
/// watch", and it was never decoded.
struct VibenetPolicyRun: Identifiable, Equatable, Codable, Sendable {
    var id: String { "\(txHash):\(logIndex)" }
    let commitment: String
    /// Nil when the log carried no readable caller — never the account
    /// itself as a fallback, which would claim you ran your own key.
    let caller: String?
    let at: Date?
    let txHash: String
    let block: Int
    let logIndex: Int
}

enum VibenetPolicyRuns {
    /// How many runs are KEPT with their dates and stored in the snapshot.
    ///
    /// The bound is on block-time lookups and on the size of a persisted
    /// value, not on the arithmetic: `fold` below is handed every run the
    /// read saw, so the COUNTS stay exact and only the oldest runs lose their
    /// date. That split matters — an undercounted "4 uses" is a wrong fact
    /// about a key's authority, while an undated run past the two hundredth
    /// is a row nobody scrolls to.
    static let cap = 240

    /// The per-commitment fold `VibenetPolicyUse` has always carried — count
    /// and most recent use — moved here from the bridge so it can be proven
    /// with no network in sight, which is this file's whole reason.
    ///
    /// Sorted by commitment: a TOTAL order, because this array is `Codable`
    /// into `VibenetState` and `Dictionary` iteration order is not stable
    /// across runs.
    static func fold(_ runs: [VibenetPolicyRun]) -> [VibenetPolicyUse] {
        var counts: [String: Int] = [:]
        var newest: [String: Date] = [:]
        for run in runs {
            let key = run.commitment.lowercased()
            counts[key, default: 0] += 1
            if let at = run.at, at > (newest[key] ?? .distantPast) { newest[key] = at }
        }
        return counts.map { VibenetPolicyUse(commitment: $0.key, count: $0.value,
                                             lastUsed: newest[$0.key]) }
            .sorted { $0.commitment < $1.commitment }
    }

    /// Newest first, total order — `VibenetLedger.ordered`'s rule, for the
    /// same persisted-snapshot reason.
    static func ordered(_ runs: [VibenetPolicyRun]) -> [VibenetPolicyRun] {
        runs.sorted { a, b in
            if a.block != b.block { return a.block > b.block }
            if a.logIndex != b.logIndex { return a.logIndex > b.logIndex }
            return a.txHash > b.txHash
        }
    }

    /// The runs belonging to one key, by its own commitment. Case-folded,
    /// because a topic's hex casing is not a promise (every comparison in
    /// this bridge is).
    static func runs(_ runs: [VibenetPolicyRun], forCommitment commitment: String?)
        -> [VibenetPolicyRun] {
        guard let commitment, !commitment.isEmpty else { return [] }
        let want = commitment.lowercased()
        return ordered(runs.filter { $0.commitment.lowercased() == want })
    }

    /// "Used by …4b1c" — the clause `VibenetPolicyUse.line` could never say.
    /// Nil when no run named a caller, and nil when SEVERAL DID: a key run by
    /// two different callers has no single answer, and naming the newest one
    /// would state a fact about who can spend that is true only of the last
    /// time (the unambiguous-join rule `VibenetEventFacts` already keeps).
    /// **A CALLER THAT IS THE ACCOUNT NAMES NOBODY, and that is the common
    /// case rather than a corner (MEASURED 2026-08-28 against the live
    /// devnet).** Every `PolicyExecuted` sampled there carries a `caller`
    /// equal to its own account topic — the account runs its own session key —
    /// so an ungated version of this would print "Used by …bc3c" under a key
    /// belonging to …bc3c, on the sheet you opened by tapping …bc3c. That is
    /// the same nothing a self-move row says, refused for the same reason.
    ///
    /// `account` is optional so a caller with nothing to compare against still
    /// gets the honest answer rather than being dropped for want of context.
    static func callerLine(_ runs: [VibenetPolicyRun], account: String? = nil) -> String? {
        let mine = account?.lowercased()
        let callers = Set(runs.compactMap { $0.caller?.lowercased() }
            .filter { $0.dropFirst(2).contains(where: { $0 != "0" }) })
        guard callers.count == 1, let only = callers.first else { return nil }
        guard only != mine else { return nil }
        return String(localized: "Used by \(VibenetRoom.shortAddress(only))")
    }
}

// MARK: - What a token actually is

/// How a token's raw balance becomes a number (prd §507).
///
/// **The bug this exists for is silent and shipped**: `VibenetRead
/// .tokenBalance` scales every balance by a live `decimals()` read and drops
/// the balance entirely when that read fails — which is the correct refusal
/// for a token whose scale is unknown, and the WRONG answer for an ERC-721,
/// where `decimals()` does not exist, reverts, and means "this is a count".
/// The demo fixture shows `NFV: 12` while a live NFV that is a 721 would be
/// absent from the room forever, with nothing anywhere saying why.
///
/// So the read asks a second question before giving up, and only ever a
/// question with a definite answer: ERC-165 `supportsInterface(0x80ac58cd)`.
/// A token that says yes is COUNTED; one that answers neither is still
/// dropped, because "we could not learn the scale" remains a real state and
/// assuming 18 (or 0) is the standing lesson this codebase has paid for in
/// Solana SPL and in Gnosis Pay's USDCe.
enum VibenetTokenIdentity: String, Equatable, Codable, Sendable {
    /// `decimals()` answered: a fungible amount, scaled.
    case fungible
    /// ERC-165 says ERC-721: a count of things, never scaled and never
    /// printed with decimal places.
    case collectible

    /// The scaled amount, or nil where the raw value cannot honestly become
    /// one. A collectible's raw word IS its count.
    func amount(raw: Double, decimals: Int?) -> Double? {
        guard raw.isFinite, raw >= 0 else { return nil }
        switch self {
        case .collectible:
            // A count with a fraction in it is not a count — a 721 balance is
            // a whole number and anything else means we are reading the wrong
            // word.
            guard raw == raw.rounded(), raw < 1e12 else { return nil }
            return raw
        case .fungible:
            guard let decimals, (0...36).contains(decimals) else { return nil }
            return raw / pow(10, Double(decimals))
        }
    }
}

// MARK: - The native curve, backfilled from the chain

/// Which historical blocks to ask for a balance at, so the native curve can
/// start before the day somebody installed this app (prd §507).
///
/// `VibenetValueHistory` needs six readings and takes them two minutes apart
/// at best, so a new watch draws nothing for its first ten minutes and can
/// never draw anything from before it existed. `eth_getBalance` takes a block
/// tag, so the chain can answer the same question about last week — IF this
/// node keeps that state. Most devnet nodes do; a pruned one answers an error
/// or a zero, and both are handled by the caller refusing to record.
enum VibenetNativeBackfill {
    /// How many historical points to buy. Each is one `eth_getBalance` plus
    /// one block-time read, so this is the whole cost of the feature and it is
    /// paid ONCE per account (`VibenetBackfillLedger` in the bridge).
    static let samples = 8
    /// How far back to reach, in blocks — 500,000, and the number is MEASURED
    /// rather than picked (2026-08-28, against the live devnet).
    ///
    /// vibenet produces a block every **2.0 seconds** (measured across 500
    /// real blocks), so the first cut's 200,000 reached back **4.6 days** on a
    /// chain that was 490,000 blocks — about eleven days — old: a "history"
    /// curve covering the most recent third of the chain's life. At 500,000 it
    /// spans the whole of it today, and `min(reach, tip)` keeps that honest on
    /// a chain that outlives the figure.
    ///
    /// Still bounded rather than "to genesis": this is a curve, not an
    /// archive, and an unbounded reach on a chain of unknown length is the
    /// crawl `VibenetLogChunking` already refuses.
    ///
    /// **The premise itself is measured too**: this node SERVES historical
    /// state — the faucet address reads 89,992 ETH at block 90,030 and
    /// 89,941 at the tip, and zero at block 1 — so these points are real
    /// readings rather than a hope about what a devnet keeps.
    static let reach = 500_000

    /// Evenly spaced, oldest first, never below zero and never the tip itself
    /// (the tip's balance is the live read the caller already holds).
    ///
    /// Returns [] when the chain is too young to have a span worth sampling —
    /// on a chain of forty blocks the samples would be adjacent and the curve
    /// would be eight readings of the same afternoon.
    static func blocks(tip: Int, reach: Int = reach, samples: Int = samples) -> [Int] {
        guard tip > 0, samples > 1 else { return [] }
        let span = min(reach, tip)
        guard span >= samples else { return [] }
        let step = span / samples
        guard step > 0 else { return [] }
        var out: [Int] = []
        var block = tip - span
        while block < tip && out.count < samples {
            out.append(max(0, block))
            block += step
        }
        return out
    }
}

extension VibenetValueHistory {
    /// Fold chain-read points into the locally sampled ones.
    ///
    /// **Both halves are real readings** — one taken when the app was open,
    /// one taken by asking the node what the balance was at a block it
    /// mined — so this merges rather than preferring: nothing here
    /// interpolates, and a chain point inside a minute of a local one is
    /// dropped as the same reading twice rather than drawn as a step.
    ///
    /// Capped from the OLDEST end, like `appending`: a curve that drops its
    /// newest points to keep its oldest is a chart about last month.
    static func merged(local: [VibenetValueSample], chain: [VibenetValueSample])
        -> [VibenetValueSample] {
        let all = (local + chain).sorted { $0.at < $1.at }
        var out: [VibenetValueSample] = []
        for sample in all {
            if let last = out.last, sample.at.timeIntervalSince(last.at) < 60 { continue }
            out.append(sample)
        }
        if out.count > cap { out.removeFirst(out.count - cap) }
        return out
    }
}

// MARK: - The log envelope

/// Decoding the non-indexed half of a log (prd §507).
///
/// Everything this bridge read until now lived in INDEXED topics, which are
/// fixed 32-byte words needing no decoding at all. Three of the facts above
/// do not: a `Transfer`'s amount, `AccountCreated`'s code hash, and
/// `PolicyExecuted`'s caller are all in `data`.
///
/// **The envelope is certain; the contents of `ActorAuthorized`'s `actorData`
/// are not.** ABI encoding of a dynamic `bytes` is an offset word, a length
/// word, then the payload — that framing is the specification and this file
/// implements exactly it. What an authenticator packs INSIDE that payload is
/// authenticator-specific and has never been measured against this devnet, so
/// `dynamicBytes` is reported by `-vibenetProbe` and drawn by nothing. Naming
/// a key's kind out of an unmeasured layout is exactly the confident wrong
/// answer this room's own doc bans.
enum VibenetLogData {
    /// One 32-byte word of a log's `data`, 0-based. Nil past the end.
    static func word(_ hex: String, at index: Int) -> String? {
        var s = hex.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.allSatisfy(\.isHexDigit) else { return nil }
        let start = index * 64
        guard s.count >= start + 64 else { return nil }
        let i = s.index(s.startIndex, offsetBy: start)
        let j = s.index(i, offsetBy: 64)
        return String(s[i..<j])
    }

    /// The 20-byte address in a 32-byte word — with the high-12-bytes-are-zero
    /// test that `VibenetActorId.address` already makes its whole check, and
    /// for the same reason: without it every hash yields a plausible address
    /// belonging to nobody, and this value is compared against real watched
    /// accounts.
    static func address(_ hex: String, at index: Int) -> String? {
        guard let w = word(hex, at: index) else { return nil }
        guard w.prefix(24).allSatisfy({ $0 == "0" }) else { return nil }
        let tail = String(w.suffix(40))
        guard tail.contains(where: { $0 != "0" }) else { return nil }
        return "0x" + tail
    }

    /// A `uint256` as a Double. Loses precision above 2^53 by construction and
    /// that is acceptable HERE and only here: every consumer divides by the
    /// token's decimals to produce a display figure, and no comparison in this
    /// file is exact. Nil for a word that is not there.
    static func uint(_ hex: String, at index: Int) -> Double? {
        guard let w = word(hex, at: index) else { return nil }
        var value = 0.0
        for ch in w {
            guard let digit = ch.hexDigitValue else { return nil }
            value = value * 16 + Double(digit)
        }
        return value.isFinite ? value : nil
    }

    /// The same word as a `UInt64`, or nil when it will not fit.
    ///
    /// **`UInt64(someDouble)` TRAPS** on a value past its range, and every
    /// input here is a 32-byte word off a public devnet that anybody can emit
    /// a log on — so the naive conversion is a crash a stranger can cause.
    /// A word too large is not a number this app has any use for anyway: both
    /// its callers read a duration and a unix timestamp.
    static func uint64(_ hex: String, at index: Int) -> UInt64? {
        guard let value = uint(hex, at: index), value.isFinite, value >= 0,
              value < 9.0e18 else { return nil }
        return UInt64(value)
    }

    /// The payload of a single dynamic `bytes` argument — offset, length,
    /// then the bytes. Returns the payload as `0x`-prefixed hex.
    ///
    /// **Every bound is checked rather than trusted**, because this reads a
    /// length out of attacker-controlled data and then indexes with it: a
    /// length larger than the log is a refusal, never a crash and never a
    /// truncated read presented as the whole thing.
    static func dynamicBytes(_ hex: String, offsetWordAt index: Int = 0) -> String? {
        guard let offset = uint(hex, at: index), offset >= 0,
              offset <= 4096, offset.truncatingRemainder(dividingBy: 32) == 0 else { return nil }
        let lengthWord = Int(offset) / 32
        guard let length = uint(hex, at: lengthWord), length >= 0, length <= 4096 else { return nil }
        var s = hex.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        let start = (lengthWord + 1) * 64
        let need = Int(length) * 2
        guard s.count >= start + need else { return nil }
        let i = s.index(s.startIndex, offsetBy: start)
        let j = s.index(i, offsetBy: need)
        return "0x" + String(s[i..<j])
    }
}

// MARK: - The lock's own numbers

/// The two facts the lock events carry in `data` and nothing read (prd §507).
///
/// `AccountLocked(address indexed account, uint16 unlockDelay)` and
/// `AccountUnlockInitiated(address indexed account, uint48 unlocksAt)` each
/// put their one interesting number in the non-indexed half — so a landed
/// lock said "locked on vibenet" with no timelock, and a landed unlock said
/// "started unlocking" without the one thing anybody wants from it, which is
/// when it opens. `getLockStatus` reports both as STATE, seen only by someone
/// standing in the room; these are the rows that reach a feed.
enum VibenetLockDetail {
    /// "2-day timelock" — `unlockDelay` is SECONDS (`VibenetAccountItem
    /// .unlockWindow` already reads it that way, and the two must not
    /// disagree about the unit).
    ///
    /// Nil at zero, which is Keystore's own "no delay": a lock that opens
    /// immediately has no timelock to name, and "0-second timelock" is a
    /// clause that reads as a bug.
    static func timelockPhrase(seconds: UInt64) -> String? {
        guard seconds > 0 else { return nil }
        let days = Int((Double(seconds) / 86_400).rounded())
        if days >= 1 {
            return days == 1 ? String(localized: "1-day timelock")
                             : String(localized: "\(days)-day timelock")
        }
        let hours = Int((Double(seconds) / 3_600).rounded())
        if hours >= 1 {
            return hours == 1 ? String(localized: "1-hour timelock")
                              : String(localized: "\(hours)-hour timelock")
        }
        return String(localized: "under an hour")
    }

    /// "opens in 2 days" — off `unlocksAt`, a unix timestamp.
    ///
    /// **Bounded before it is trusted**: a zero is Keystore's own "not
    /// unlocking", and a wildly out-of-range word is a decode that went wrong,
    /// not a lock that opens in the year 40,000. Either yields nil rather than
    /// a sentence about a date nobody can act on.
    static func opensPhrase(unlocksAt: UInt64, now: Date = .now) -> String? {
        guard unlocksAt > 0 else { return nil }
        let at = Date(timeIntervalSince1970: TimeInterval(unlocksAt))
        guard at.timeIntervalSince(now) > -365 * 86_400,
              at.timeIntervalSince(now) < 10 * 365 * 86_400 else { return nil }
        return String(localized: "opens \(at.formatted(.relative(presentation: .named)))")
    }
}
