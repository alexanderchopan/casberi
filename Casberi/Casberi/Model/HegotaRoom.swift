import Foundation

/// What the Ethrex Hegotá room LEADS with, and what it refuses to say.
///
/// Foundation-only by design — it takes the composed accounts and decides,
/// touching no chain and no view — so `scripts/hegota-selftest.sh` compiles it
/// WHOLE. Every failure it catches renders as a perfectly ordinary room: a head
/// that leads with the wrong reading, a total that includes an account we never
/// reached, or a card claiming coins over a set that did not reconcile.
enum HegotaRoom {

    /// Which reading leads. Ranked, not stacked — one head, the way every other
    /// room in this app composes.
    ///
    /// **Coins leads when there are any**, because it is the reading no other
    /// room in this app can draw. Sponsorship outranks nonces below it for the
    /// same reason in miniature: somebody else paying your gas is rarer and
    /// more surprising than a parallel send. Moves is the fallback and is what
    /// nearly every address on this chain will show.
    enum Lead: String, Equatable, Sendable {
        case coins, sponsored, nonces, moves, nothing
    }

    struct Head: Equatable, Sendable {
        let lead: Lead
        /// Has a sweep finished at all?
        ///
        /// **Distinct from `everythingUnreached`, and the difference is the
        /// whole point.** Before the first sweep we have not tried; after a
        /// failed one we tried and could not. Collapsing them makes a room you
        /// just opened announce "couldn't reach the chain" — reported from a
        /// device as an address that "has nothing", which was neither a failure
        /// nor an empty account but a read that had not run.
        let hasRead: Bool
        /// The native total across every REACHED account. Nil when none was
        /// reached — an unreached sweep has no total, and zero is a claim.
        let balanceWei: Decimal?
        /// How many accounts answered, out of how many are watched. The room
        /// says so when they differ, because a total that quietly omits an
        /// account is the silent wrong answer this whole file exists to avoid.
        let reached: Int
        let watched: Int
        let coinCount: Int
        let coinsWei: Decimal?
        let sponsoredCount: Int
        let laneCount: Int
        let moveCount: Int

        var partial: Bool { reached < watched }
        var everythingUnreached: Bool { watched > 0 && reached == 0 }
    }

    /// Compose the head over every watched account.
    ///
    /// Returns nil when nothing is watched at all — there is no room, rather
    /// than an empty one.
    static func head(_ accounts: [HegotaAccount], hasRead: Bool = true, watching: Int = 0) -> Head? {
        // A watch list with no sweep yet is still a room — it is the room
        // saying it is working, which is why `watching` is carried in.
        guard !accounts.isEmpty else {
            guard watching > 0 else { return nil }
            return Head(lead: .nothing, hasRead: hasRead, balanceWei: nil,
                        reached: 0, watched: watching, coinCount: 0, coinsWei: nil,
                        sponsoredCount: 0, laneCount: 0, moveCount: 0)
        }
        let reached = accounts.filter(\.reached)

        // **The total sums REACHED accounts only, and an unreached one makes it
        // partial rather than smaller.** Silently folding a failed read in as
        // zero is how a balance drops for a network reason and reads as money
        // leaving.
        let balance: Decimal? = reached.isEmpty
            ? nil
            : reached.compactMap(\.balanceWei).reduce(Decimal(0), +)

        let coins = reached.flatMap { $0.hasCoins ? ($0.unspent ?? []) : [] }
        let coinsWei: Decimal? = coins.isEmpty ? nil : HegotaCoins.total(coins)
        let sponsored = reached.reduce(0) { $0 + $1.sponsored.count }
        let lanes = reached.reduce(0) { $0 + $1.lanes.count }
        let moves = reached.reduce(0) { $0 + $1.moves.count }

        let lead: Lead
        if !coins.isEmpty { lead = .coins }
        else if sponsored > 0 { lead = .sponsored }
        else if lanes > 0 { lead = .nonces }
        else if moves > 0 { lead = .moves }
        else { lead = .nothing }

        return Head(lead: lead, hasRead: hasRead, balanceWei: balance,
                    reached: reached.count, watched: accounts.count,
                    coinCount: coins.count, coinsWei: coinsWei,
                    sponsoredCount: sponsored, laneCount: lanes, moveCount: moves)
    }

    /// Which scopes the strip should offer, derived from the room rather than
    /// from the watch list.
    ///
    /// **From the ROOM, never the watch list** — the face rail's own rule, and
    /// the two legitimately disagree: an address can be watched while its sweep
    /// has not landed, and a chip that opens an empty scope is the dead control
    /// §83 bans.
    static func sections(_ accounts: [HegotaAccount]) -> [HegotaSection] {
        let reached = accounts.filter(\.reached)
        guard !reached.isEmpty else { return [] }
        return HegotaSection.present(
            frames: reached.contains { $0.hasFrames },
            coins: reached.contains { $0.hasCoins },
            nonces: reached.contains { $0.hasLanes },
            sponsors: reached.contains { $0.hasSponsors })
    }

    /// The split a spend performed: what went in, what came out, what the chain
    /// took. Nil unless every part is known, because a partly-read split is a
    /// diagram that teaches the wrong thing.
    struct Split: Equatable, Sendable {
        let inputs: [Decimal]
        let outputs: [HegotaCoin]
        let fee: Decimal
        var changeCount: Int { outputs.filter(\.isChange).count }
    }

    /// Read a spend's split from the coins it created and the coins it consumed.
    ///
    /// The inputs are supplied by the caller because they are not in the
    /// creation logs — a spent coin is known by its BIT, not by an event, so
    /// nothing on the wire names which coins a spend consumed. That is a real
    /// ceiling and it is why this takes the inputs rather than deriving them.
    static func split(inputs: [Decimal], outputs: [HegotaCoin]) -> Split? {
        guard !inputs.isEmpty, !outputs.isEmpty else { return nil }
        guard let fee = HegotaCoins.fee(inputs: inputs, outputs: outputs.map(\.wei)) else { return nil }
        return Split(inputs: inputs, outputs: outputs.sorted { $0.index < $1.index }, fee: fee)
    }

    /// The running balance, oldest first — the crown's sparkline.
    ///
    /// **EXACT, not sampled.** Every ETH movement on this chain is an EIP-7708
    /// log, so the whole history reconstructs from the moves themselves: start
    /// at today's balance and walk backwards, undoing each move. Every other
    /// balance line in this app is `WalletStore.ValueSample`'s four-hourly
    /// snapshot because mainnet gives it no choice; this one has no gaps to
    /// interpolate across, which is worth saying on the card.
    ///
    /// Returns nil below two points — a chart of one value is a dot claiming
    /// to be a trend.
    static func valueSeries(_ account: HegotaAccount) -> [Double]? {
        guard let balance = account.balanceWei, !account.moves.isEmpty else { return nil }
        let ordered = account.moves.sorted { $0.block > $1.block }   // newest first
        var running = balance
        var series: [Double] = [(running as NSDecimalNumber).doubleValue / 1e18]
        for move in ordered {
            // Undo it: money that came IN was not there before, money that
            // went OUT still was.
            running += move.incoming ? -move.wei : move.wei
            // **AND UNDO THE FEE THIS ADDRESS PAID (§509).** A fee leaves the
            // balance and emits NO transfer log — measured on this chain: a
            // frame transaction's receipt carries only its value-move log, and
            // nothing sends the 91,201,976-wei fee to the coinbase — so a
            // reconstruction built from logs alone drifts by exactly the gas
            // this address has spent. `feeWei` is held for the newest
            // `frameDepth` moves, so the recent stretch is exact and the older
            // one is unchanged; the clamp below stays as the floor for it.
            //
            // Only when THIS address paid: a sponsored transaction cost it
            // nothing, and adding back somebody else's gas would bend the line
            // the wrong way on precisely the transactions this chain exists to
            // show off.
            if !move.incoming, !move.isSponsored, let fee = move.feeWei {
                running += fee
            }
            if running < 0 { running = 0 }   // an unread fee is still a gap; never draw below zero
            series.append((running as NSDecimalNumber).doubleValue / 1e18)
        }
        return series.count >= 2 ? series.reversed() : nil
    }

    /// What the line did across that span, as a fraction — the crown's delta.
    static func valueDelta(_ account: HegotaAccount) -> Double? {
        guard let s = valueSeries(account), let first = s.first, let last = s.last,
              first > 0 else { return nil }
        return (last - first) / first
    }
}

// MARK: - How to scale a bar chart nobody can read

/// Whether a set of amounts can be drawn as plain bars.
///
/// **The problem this exists for is specific to a devnet and it is severe.**
/// Hegotá prefunds addresses, so one watched account holds 999,999,898 ETH
/// beside another's 1.13 — a ratio of nine hundred million to one. Drawn as
/// ordinary bars that is one full-width bar and one bar 0.0000001pt long, i.e.
/// nothing, for the account the person actually uses.
///
/// So: **plain bars when the set is comparable, a log scale when it isn't, and
/// the chart SAYS which** — because a log axis read as a linear one understates
/// a difference by orders of magnitude, and a chart that quietly switches
/// scales is worse than either. `spreadCeiling` is where it flips: at 100x the
/// smallest bar is still 1% of the largest, which is a visible sliver; past
/// that it is not.
enum HegotaScale: String, Equatable, Sendable {
    case linear, logarithmic

    static let spreadCeiling: Double = 100

    static func of(_ values: [Decimal]) -> HegotaScale {
        let positive = values.map { NSDecimalNumber(decimal: $0).doubleValue }.filter { $0 > 0 }
        guard let low = positive.min(), let high = positive.max(), low > 0 else { return .linear }
        return high / low > spreadCeiling ? .logarithmic : .linear
    }

    /// A value's share of the longest bar, 0...1.
    ///
    /// **The floor is not decoration.** A bar of zero length is indistinguishable
    /// from an account that is missing from the chart, so anything with real
    /// value keeps a visible stub; a true zero returns zero and draws nothing,
    /// which is the honest difference.
    static func share(_ value: Decimal, in values: [Decimal], scale: HegotaScale) -> Double {
        let v = NSDecimalNumber(decimal: value).doubleValue
        guard v > 0 else { return 0 }
        let all = values.map { NSDecimalNumber(decimal: $0).doubleValue }.filter { $0 > 0 }
        guard let high = all.max(), high > 0 else { return 0 }
        switch scale {
        case .linear:
            return max(0.02, min(1, v / high))
        case .logarithmic:
            // Anchored a decade below the smallest real value, so the smallest
            // bar is a readable fraction rather than zero.
            guard let low = all.min(), low > 0 else { return 1 }
            let floor = log10(low) - 1
            let top = log10(high)
            guard top > floor else { return 1 }
            return max(0.06, min(1, (log10(v) - floor) / (top - floor)))
        }
    }
}

// MARK: - Who the other side is

/// What the room knows about the address on the other end of a move.
///
/// **A hex string is not a counterparty.** Every row in this room named the
/// other side `…8312` or `…a776` — including the person's OWN other watched
/// account, and including the vault predeploy their money was sitting in — so
/// a room full of your own housekeeping read as a room full of strangers.
///
/// Pure and here rather than in the view because it is a DECISION, and the
/// wrong one is invisible: naming a stranger as yourself is the worst failure
/// this room could have, and it renders as an ordinary row.
enum HegotaParty: Equatable, Sendable {
    /// The UTXO vault predeploy — money you moved into your own pieces.
    case vault
    /// The keyed-nonce manager predeploy.
    ///
    /// **Named for the vault's own reason (2026-08-27).** Both are predeploys
    /// at fixed addresses that this room already knows by name, and a frame
    /// sheet reading "Ran against 0x…8250" makes the person do a lookup the app
    /// could have done — in the scope named after that very contract. It is the
    /// counterparty of a `sender` frame, so it turns up on exactly the
    /// transactions the Nonces scope is about.
    case nonceManager
    /// Another address this person watches. Carries it so the caller can find
    /// its name, which lives in the watch list rather than here.
    case mine(String)
    case stranger(String)

    /// **Matching is case-insensitive and that is load-bearing**, not tidiness:
    /// EIP-55 checksummed input, an RPC's lowercase answer and a typed address
    /// are three spellings of one account, and an exact compare would file a
    /// person's own address as a stranger for the entirely invisible reason
    /// that they capitalised it when they pasted it.
    static func of(_ address: String, watched: [String]) -> HegotaParty {
        if address.caseInsensitiveCompare(HegotaChain.vault) == .orderedSame { return .vault }
        if address.caseInsensitiveCompare(HegotaChain.nonceManager) == .orderedSame {
            return .nonceManager
        }
        if let match = watched.first(where: { $0.caseInsensitiveCompare(address) == .orderedSame }) {
            return .mine(match)
        }
        return .stranger(address)
    }

    var isMine: Bool { if case .mine = self { return true }; return false }
}

// MARK: - What crossed the edge

/// Hegotá's flow band — **Wallet's bones, this chain's vocabulary.**
///
/// `WalletFlow.Band` is the shape ("what came in, what went out, from and to
/// whom"), and it is the right shape here because the question is identical.
/// What differs is everything inside it: the amounts are ETH quantities and
/// not dollars (this is test money, there is no price and inventing one would
/// be §83 where a reader cannot check us), and the lanes carry the FRAME MODES
/// that moved them, which is the reading no other chain in this app can offer.
///
/// A REDUCTION rather than a reuse, and deliberately so — the same call
/// `AgentPanelGrid` made about the same band. Feeding ETH into a field named
/// `usd` and a view that formats dollars is how a room ends up confidently
/// printing "$1.00" over one Ether.
enum HegotaFlow {

    /// One counterparty, folded.
    struct Lane: Identifiable, Equatable, Sendable {
        /// The side is part of the identity: the vault legitimately appears on
        /// both, and folding them together would net a deposit against a
        /// withdrawal and draw neither.
        let id: String
        let address: String
        let wei: Decimal
        let count: Int
        /// The frame modes that carried this lane's money, most-used first.
        /// **Empty is a real answer** — ordinary type-`0x2` transactions ran no
        /// frames — and the view draws a plain lane for it rather than
        /// inventing a step.
        let modes: [HegotaFrame.Mode]
        /// True for the folded tail, which the view NAMES rather than dropping
        /// (the no-silent-caps rule).
        let isOther: Bool
    }

    struct Band: Equatable, Sendable {
        let inLanes: [Lane]
        let outLanes: [Lane]
        let inWei: Decimal
        let outWei: Decimal

        /// **ONE scale across both sides.** If each side normalised to its own
        /// total, a 0.03 ETH week of outflow would draw exactly as wide as a
        /// 1.16 ETH week of inflow, and the band's only real claim — that these
        /// two are not the same size — would be the one thing it got wrong.
        var scaleWei: Decimal { max(inWei, outWei) }
        var netWei: Decimal { inWei - outWei }
        var laneCount: Int { inLanes.count + outLanes.count }
    }

    /// How many lanes a side draws before the rest are folded into one named
    /// tail.
    ///
    /// **Three plus a tail is a HEIGHT budget.** A lane is a 20pt row and the
    /// slot gives the whole figure 180pt under its headline; five lanes a side
    /// plus two captions overruns it, and `DSRoomSlot` clips silently.
    static let laneLimit = 3

    static func band(_ moves: [HegotaMove]) -> Band? {
        let ins = lanes(moves.filter(\.incoming), side: "in")
        let outs = lanes(moves.filter { !$0.incoming }, side: "out")
        guard !ins.isEmpty || !outs.isEmpty else { return nil }
        return Band(inLanes: ins, outLanes: outs,
                    inWei: ins.reduce(Decimal(0)) { $0 + $1.wei },
                    outWei: outs.reduce(Decimal(0)) { $0 + $1.wei })
    }

    /// Fold one side's moves by counterparty, biggest first.
    ///
    /// **Ranked by amount and not by count**, because the band's bar heights
    /// are amounts: a lane ordered by count would put a run of dust above the
    /// transfer that actually moved the money. Ties break on the address so the
    /// order is TOTAL — a band that reshuffles between opens over identical
    /// data reads as broken.
    static func lanes(_ moves: [HegotaMove], side: String) -> [Lane] {
        var byParty: [String: [HegotaMove]] = [:]
        for move in moves where move.wei > 0 {
            byParty[move.counterparty.lowercased(), default: []].append(move)
        }
        let ranked = byParty.map { address, list -> Lane in
            Lane(id: "\(side):\(address)", address: address,
                 wei: list.reduce(Decimal(0)) { $0 + $1.wei },
                 count: list.count, modes: modes(of: list), isOther: false)
        }
        .sorted { $0.wei != $1.wei ? $0.wei > $1.wei : $0.address < $1.address }

        guard ranked.count > laneLimit else { return ranked }
        let kept = Array(ranked.prefix(laneLimit))
        let tail = ranked.dropFirst(laneLimit)
        let folded = Lane(id: "\(side):other", address: "",
                          wei: tail.reduce(Decimal(0)) { $0 + $1.wei },
                          count: tail.reduce(0) { $0 + $1.count },
                          modes: [], isOther: true)
        return kept + [folded]
    }

    /// The frame modes that carried a lane, most-used first.
    ///
    /// A count, not a set, because "this lane is mostly UTXO work with one
    /// verify" and "this lane is half verify" are different facts and the
    /// leading mode is the one the lane is coloured by.
    static func modes(of moves: [HegotaMove]) -> [HegotaFrame.Mode] {
        var tally: [HegotaFrame.Mode: Int] = [:]
        for move in moves {
            for frame in move.frames ?? [] { tally[frame.mode, default: 0] += 1 }
        }
        return tally.sorted {
            $0.value != $1.value ? $0.value > $1.value
                                 : $0.key.rawValue < $1.key.rawValue
        }.map(\.key)
    }
}

// MARK: - Every counter, including the one nobody lists

/// The nonce scope's totals.
///
/// **It exists to say the things the LIST structurally cannot.** The rows below
/// enumerate the NAMED keys — that is what a keyed nonce is — so the ordinary
/// nonce, key 0, the single counter every other chain gives you and usually the
/// busiest thing on the account, appears nowhere in them. Nor does any total,
/// since a list of per-key counts never sums itself.
///
/// So no chart: with one or two sends per key there is nothing to plot, and
/// three attempts at plotting it produced three drawings nobody could read.
/// Three figures, each a fact the list is missing.
struct HegotaNonceTotals: Equatable, Sendable {
    /// Sends on the ordinary nonce.
    ///
    /// **The chain's own counter when it was read, and only the observable
    /// moves when it was not (2026-08-27).** Every other figure in this room is
    /// reconstructed from transfer logs, and this one cannot be: a transaction
    /// that moved no ETH emits no transfer log, so counting outgoing moves
    /// undercounts — on the chain whose entire subject is transactions that
    /// verify, check and call rather than pay, and in the scope whose whole
    /// claim is to count sends. `eth_getTransactionCount` IS the ordinary
    /// nonce, so it is not a better estimate of this number, it is the number.
    let ordinarySends: Int
    let keyedSends: Int
    /// Counters in all: the named keys, plus key 0 when it has ever been used.
    let counters: Int
    /// Sends on key 0 that moved no value — the ordinary nonce minus the
    /// outgoing moves that carried no named key.
    ///
    /// Nil when the nonce was not read (not knowable) and when the gap is zero
    /// (nothing to say), which are different silences with the same drawing and
    /// the caller may not distinguish them — nothing is claimed either way.
    let valuelessSends: Int?
    /// Whether `ordinarySends` came off the chain's own counter. The figure
    /// draws the same number either way; this is what stops a DERIVED count
    /// being narrated as the chain's, and what a self-test can pin.
    let nonceRead: Bool

    var total: Int { ordinarySends + keyedSends }

    static func of(_ moves: [HegotaMove], lanes: [HegotaNonceLane],
                   nonceCount: UInt64? = nil, valuelessSends: Int? = nil) -> HegotaNonceTotals {
        // Fold by hash: a self-payment lands as two moves for one transaction,
        // and the counter it advanced was one.
        var seen = Set<String>()
        let observed = moves.filter { move in
            guard !move.incoming, move.nonceKeys.isEmpty else { return false }
            return seen.insert(move.hash.lowercased()).inserted
        }.count
        // **The chain's counter can only ever be >= what we observed**, since
        // every value-moving send also advanced it. A smaller one means the
        // read describes a different address than the logs do — a reorg, a
        // reset, or a bug — so the observed floor is kept rather than reporting
        // fewer sends than we can literally name below.
        let ordinary = nonceCount.map { max(Int($0), observed) } ?? observed
        let keyed = lanes.reduce(0) { $0 + $1.sends }
        return HegotaNonceTotals(ordinarySends: ordinary, keyedSends: keyed,
                                 counters: lanes.count + (ordinary > 0 ? 1 : 0),
                                 valuelessSends: valuelessSends,
                                 nonceRead: nonceCount != nil)
    }
}

// MARK: - What the transactions actually DID

/// The Frames scope's figure — the anatomy of this address's transactions.
///
/// **The scope exists because Activity structurally cannot answer this.** That
/// list is built from transfer logs, so it holds transactions that MOVED money
/// and describes them by amount and counterparty; a frame transaction is a
/// sequence of named steps, and until this scope the sequence appeared nowhere
/// as a subject — only as a 5pt texture strip on a row, and inside a sheet you
/// had to know to open.
///
/// The mix is a census over every frame of every transaction whose receipt was
/// read, and the ORDER is the ranking the figure draws: commonest first, ties
/// broken by the mode's own name so the drawing is stable between opens.
struct HegotaFrameMix: Equatable, Sendable {
    struct Slice: Equatable, Sendable, Identifiable {
        let mode: HegotaFrame.Mode
        let count: Int
        var id: String { mode.rawValue }
    }

    let slices: [Slice]
    /// Transactions counted — never the frame count, which is `total`.
    let transactions: Int
    /// Frames in all.
    let total: Int
    /// How many of those frames FAILED. Failure is rare here by construction,
    /// so this is normally 0 and the figure says nothing about it.
    let failed: Int
    /// Frames whose receipt could not be paired, so their outcome is unknown.
    /// Kept apart from `failed` for the reason the strip draws them hollow: a
    /// step we could not read is not a step that went wrong.
    let unknown: Int

    var busiest: Slice? { slices.first }

    /// The modes that SHARE the top count — one normally, several on a tie
    /// (prd §510).
    ///
    /// **`busiest` is the head of the drawing's ORDER; this is the CAPTION's
    /// question, and they are not the same question.** `of(_:)` breaks a tie
    /// on the mode's own name so the figure is stable between opens, which is
    /// right for an
    /// ORDER and wrong for a SUPERLATIVE: on a 7–7 Send/Verify split the
    /// caption read "mostly Send steps" because `sender` sorts before
    /// `verify`, while the legend one line below printed both sevens. A
    /// winner decided by the alphabet, contradicted on the same card, is §83's
    /// fake status — so a caption asks for the leaders and says "evenly" when
    /// there is more than one.
    var leaders: [Slice] {
        guard let top = slices.first else { return [] }
        return Array(slices.prefix { $0.count == top.count })
    }

    /// True only when ONE mode really is commonest. A single-mode mix is
    /// deliberately not "mostly" anything either — it is all of them, and the
    /// caption says so.
    var hasCommonest: Bool { leaders.count == 1 && slices.count > 1 }

    /// Compose over the transactions whose frames were actually read.
    ///
    /// Returns nil when there is nothing to draw. **A transaction with exactly
    /// one frame still counts** — a one-step frame transaction is a real thing
    /// on this chain and excluding it would make the scope disagree with the
    /// list underneath it, which is `HegotaRoom.sections`' own gate.
    static func of(_ moves: [HegotaMove]) -> HegotaFrameMix? {
        var seen = Set<String>()
        let framed = moves.filter { move in
            guard let f = move.frames, !f.isEmpty else { return false }
            return seen.insert(move.hash.lowercased()).inserted
        }
        guard !framed.isEmpty else { return nil }

        var tally: [HegotaFrame.Mode: Int] = [:]
        var failed = 0, unknown = 0, total = 0
        for move in framed {
            for frame in move.frames ?? [] {
                tally[frame.mode, default: 0] += 1
                total += 1
                switch frame.succeeded {
                case .some(false): failed += 1
                case .none:        unknown += 1
                case .some(true):  break
                }
            }
        }
        let slices = tally.sorted {
            $0.value != $1.value ? $0.value > $1.value
                                 : $0.key.rawValue < $1.key.rawValue
        }.map { Slice(mode: $0.key, count: $0.value) }

        return HegotaFrameMix(slices: slices, transactions: framed.count,
                              total: total, failed: failed, unknown: unknown)
    }
}

// MARK: - Who paid for whom

/// One sponsor and everything they paid for.
///
/// **The Sponsors scope's subject is the SPONSOR**, and until this existed the
/// scope was Activity filtered — the same rows, in the same shape, ordered by
/// when rather than by who. Somebody paying for eleven of your transactions
/// and eleven people paying once each are completely different facts about
/// your account, and a flat list cannot tell them apart.
struct HegotaSponsor: Equatable, Sendable, Identifiable {
    let payer: String
    let moves: [HegotaMove]
    /// The gas they actually spent, summed — nil unless EVERY move's fee was
    /// read. A partial sum understates what somebody gave you, and it does it
    /// silently; the card says the count instead.
    let feeWei: Decimal?

    var id: String { payer }

    /// Group the sponsored moves by who paid.
    ///
    /// Ordered by how much they paid FOR (count), then by recency, then by
    /// address — a total order, because a card that reshuffles between opens
    /// over identical data reads as broken.
    static func group(_ moves: [HegotaMove]) -> [HegotaSponsor] {
        var byPayer: [String: [HegotaMove]] = [:]
        for move in moves where move.isSponsored {
            guard let payer = move.payer?.lowercased() else { continue }
            byPayer[payer, default: []].append(move)
        }
        return byPayer.map { payer, list in
            let ordered = list.sorted { $0.block > $1.block }
            let fees = ordered.map(\.feeWei)
            let total: Decimal? = fees.contains(where: { $0 == nil })
                ? nil : fees.compactMap { $0 }.reduce(0, +)
            return HegotaSponsor(payer: payer, moves: ordered, feeWei: total)
        }
        .sorted {
            if $0.moves.count != $1.moves.count { return $0.moves.count > $1.moves.count }
            let a = $0.moves.first?.block ?? 0, b = $1.moves.first?.block ?? 0
            if a != b { return a > b }
            return $0.payer < $1.payer
        }
    }
}
