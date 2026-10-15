import Foundation

/// PLASMA ONE'S SETTLEMENT, DECODED (2026-10-15, prd §1311) — the pure half of
/// the fourth onchain card. Foundation and `Keccak256` only, so
/// `scripts/plasma-one-selftest.sh` compiles this file WHOLE and unmodified
/// against real logs; everything that asks a host lives in `PlasmaOneCard`.
///
/// **The card does not settle per purchase. It settles once a day, in a
/// batch**, and that is the fact the whole seat is shaped around. Rain, the
/// issuer, keeps each cardholder's money in a card contract of their own and
/// sweeps every card's day out of it at 12:31–12:34 UTC — measured on ten
/// consecutive days (10-06 → 10-15), 3,257 to 6,705 settlements a day, twenty
/// to a transaction, nothing in between. A tap writes nothing to the chain.
/// So a row here is "the card settled $X today", never a purchase, and the
/// head counts DAYS (`CardSpendRoom.Unit.settledDay`).
///
/// MEASURED (2026-10-15, live against `rpc.plasma.to`, chain 9745, blocks
/// ~1.00s — 100,000 blocks spanned 100,013s). Re-measure before "fixing" any of
/// these:
/// - **The event.** Each card contract emits
///   `SettledBalance(address indexed owner, address indexed recipient,
///   (address,uint256) indexed asset, bytes32 id)` — the signature hashes to
///   `settledBalanceTopic`, matched against live logs, not trusted from a
///   signature database. `recipient` was the ONE Safe below for all 53,997
///   settlements in ten days.
/// - **The amount is NOT in the event in the clear.** An indexed tuple is
///   stored as its hash, so topic3 is `keccak256(abi.encode(token, amount))`.
///   The money is the USDT0 `Transfer` from the card to the Safe at
///   `logIndex − 1` in the same transaction, and the hash CHECKS it: 53,997 of
///   53,997 paired and verified, $0.01 to $253,442.64, median $28.64. A pair
///   whose hash disagrees is refused, never landed (`settlements`).
/// - **USDT0, six decimals**, every settlement in the window — `decimals()`
///   read on chain. The card is a dollar card, so the amount is money.
/// - **The owner is INDEXED**, so a person's card is found from their own
///   address with one topic filter — the reverse lookup ether.fi Cash cannot
///   have (`EtherFiCash`'s header). 14,651 owner ↔ card pairs in ten days,
///   strictly one to one; 40 of 40 sampled card contracts answer `owner()`
///   (`ownerSelector`) with their topic1; every one is the same 499-byte proxy
///   over one beacon (`cardBeacon`); 200 of 200 sampled owners are one 107-byte
///   smart-account proxy (Biconomy Nexus), never a plain key.
/// - The `id` is a UUIDv7, minted 04:16–04:41 UTC — eight hours before the
///   money moves. A person gets one to three a day; what splits them is
///   Rain's and unknown, so a row is the DAY, every part summed (`days`).
///
/// What is NOT known, and so not claimed anywhere: which purchases a day's
/// settlement covers, how a refund nets, and whether every card on the Safe
/// is Plasma One rather than another Rain programme on Plasma (12 of 60
/// sampled owners hold "Plasma One USD", which points that way and proves
/// nothing).
enum PlasmaOneSettlement {

    /// `keccak256("SettledBalance(address,address,(address,uint256),bytes32)")`.
    static let settledBalanceTopic =
        "0x0b2f6e461557f87970a7aa808930560b0e0def3b63ec629d8f9231da8cac6dfc"
    /// ERC-20 `Transfer(address indexed from, address indexed to, uint256)`.
    static let transferTopic =
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
    /// Where every settlement lands. Filtering topic2 on it is what keeps a
    /// stranger's contract emitting the same event out of a person's room.
    static let settlementSafe = "0xc7eda2b178c8488aa98dd1a3711566634d725268"
    /// USDT0 on Plasma — `symbol()` "USDT0", `decimals()` 6.
    static let usdt0 = "0xb8ce59fc3717ada4c02eadf9682a9e934f625ebb"
    static let usdt0Decimals = 6
    /// The beacon every card contract asks for its implementation, baked into
    /// the card's own bytecode. A watched address whose code carries it IS a
    /// card contract.
    static let cardBeacon = "42529da25d82ba7810d7f51d614915b8c7e11acc"
    /// A card contract's 499 bytes — measured on 40 of 40.
    static let cardCodeBytes = 499
    /// `owner()` on a card contract (`0x6115ca0c`) — the address it settles
    /// for, read out of its own bytecode, never guessed.
    static let ownerSelector = "0x6115ca0c"
    /// `balanceOf(address)`.
    static let balanceOfSelector = "0x70a08231"

    /// One settlement, paired and checked.
    struct Settlement: Equatable {
        /// Lowercased `0x…`, as the topic named it.
        let owner: String
        /// The card contract that paid — the log's own address.
        let card: String
        let txHash: String
        let logIndex: Int
        let block: Int
        /// The block's time, from the log itself (`blockTimestamp`, which
        /// both measured hosts carry); nil when a host leaves it out, and then
        /// the bridge asks for the block rather than dating it now (§790).
        let at: Date?
        /// Whole dollars.
        let amount: Double

        /// The dedupe key of ONE part of a day — what the rowless
        /// `.settlement` fact keeps, so a re-read never adds a part twice.
        var key: String { "\(txHash.lowercased()):\(logIndex)" }
    }

    /// Pairs every `SettledBalance` with the USDT0 transfer at `logIndex − 1`
    /// and keeps only those the hash proves. `rejected` counts what failed —
    /// an unpaired log, a different recipient, a hash that disagrees — so the
    /// probe can say it rather than the room going quietly short.
    static func settlements(settled: [[String: Any]],
                            transfers: [[String: Any]]) -> (paired: [Settlement], rejected: Int) {
        var byPosition: [String: [String: Any]] = [:]
        for t in transfers {
            guard let tx = (t["transactionHash"] as? String)?.lowercased(),
                  let index = (t["logIndex"] as? String).flatMap(hexInt)
            else { continue }
            byPosition["\(tx):\(index)"] = t
        }
        var out: [Settlement] = []
        var rejected = 0
        var seen = Set<String>()
        for log in settled {
            guard (log["removed"] as? Bool) != true,
                  let topics = log["topics"] as? [String], topics.count == 4,
                  topics[0].lowercased() == settledBalanceTopic,
                  let owner = address(fromTopic: topics[1]),
                  address(fromTopic: topics[2]) == settlementSafe,
                  let card = (log["address"] as? String)?.lowercased(),
                  let tx = (log["transactionHash"] as? String)?.lowercased(),
                  let index = (log["logIndex"] as? String).flatMap(hexInt),
                  let block = (log["blockNumber"] as? String).flatMap(hexInt),
                  let transfer = byPosition["\(tx):\(index - 1)"],
                  let word = pairedWord(transfer, card: card),
                  assetHash(token: usdt0, word: word) == topics[3].lowercased(),
                  let amount = dollars(word)
            else { rejected += 1; continue }
            let s = Settlement(owner: owner, card: card, txHash: tx, logIndex: index,
                               block: block,
                               at: (log["blockTimestamp"] as? String)
                                   .flatMap(hexInt)
                                   .map { Date(timeIntervalSince1970: TimeInterval($0)) },
                               amount: amount)
            if seen.insert(s.key).inserted { out.append(s) }
        }
        return (out, rejected)
    }

    /// The transfer's 32-byte value word, when it is USDT0 moving from THIS
    /// card to the Safe — anything else is not this settlement's money.
    private static func pairedWord(_ transfer: [String: Any], card: String) -> String? {
        guard (transfer["address"] as? String)?.lowercased() == usdt0,
              let topics = transfer["topics"] as? [String], topics.count == 3,
              topics[0].lowercased() == transferTopic,
              address(fromTopic: topics[1]) == card,
              address(fromTopic: topics[2]) == settlementSafe,
              let data = (transfer["data"] as? String)?.lowercased(),
              data.hasPrefix("0x"), data.count == 66
        else { return nil }
        return String(data.dropFirst(2))
    }

    /// `keccak256(abi.encode(token, uint256))` as a topic — the indexed
    /// tuple's own encoding, which is what lets the chain check the amount.
    static func assetHash(token: String, word: String) -> String {
        let hex = String(repeating: "0", count: 24) + token.dropFirst(2).lowercased() + word
        return "0x" + Keccak256.hexString(Keccak256.hash(bytes(hex)))
    }

    /// The USDT0 word in dollars. Through `Decimal`, never `Double` on the
    /// raw integer first, so a large settlement cannot lose its cents.
    static func dollars(_ word: String) -> Double? {
        let digits = word.drop { $0 == "0" }
        guard digits.count <= 30 else { return nil }   // beyond any real card
        var value = Decimal(0)
        for c in digits {
            guard let d = c.hexDigitValue else { return nil }
            value = value * 16 + Decimal(d)
        }
        var scaled = value / pow(Decimal(10), usdt0Decimals)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, usdt0Decimals, .plain)
        // Through the decimal STRING: `NSDecimalNumber.doubleValue` can land
        // one ulp off ("56.900000000000006"), where parsing "56.9" gives the
        // double every other reader of 56.9 holds.
        return Double(NSDecimalNumber(decimal: rounded).stringValue)
    }

    // MARK: - Days

    /// One row: everything one owner's card settled on one UTC day.
    struct Day: Equatable {
        /// `yyyy-MM-dd`, UTC — see `dayKey`.
        let key: String
        let owner: String
        /// Oldest first.
        let parts: [Settlement]
        var total: Double { parts.reduce(0) { $0 + $1.amount } }
        var newest: Settlement? { parts.last }
        var ref: String { PlasmaOneSettlement.ref(owner: owner, day: key) }
    }

    /// The row's `sourceRef`. The DAY, not a settlement: a second settlement
    /// on the same day joins the first row rather than becoming a second one.
    static func ref(owner: String, day: String) -> String {
        "plasmaone:day:\(owner.lowercased()):\(day)"
    }

    /// The namespace every row of this seat lands under.
    static let refPrefix = "plasmaone:day:"

    /// The UTC calendar day. UTC on purpose, and safe: the batch runs
    /// 12:31–12:34 UTC, so it never straddles a UTC midnight, and a key in the
    /// phone's own zone would move when the person travels and split a day
    /// that was already landed into two rows.
    static func dayKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Settlements grouped into days, per owner. A settlement with no time
    /// joins no day — the bridge dates it before calling this, or holds it.
    static func days(_ settlements: [Settlement]) -> [Day] {
        var groups: [String: [Settlement]] = [:]
        for s in settlements {
            guard let at = s.at else { continue }
            groups["\(s.owner)|\(dayKey(at))", default: []].append(s)
        }
        return groups.map { key, parts in
            let split = key.split(separator: "|", maxSplits: 1).map(String.init)
            return Day(key: split[1], owner: split[0],
                       parts: parts.sorted { ($0.block, $0.logIndex) < ($1.block, $1.logIndex) })
        }
        .sorted { ($0.key, $0.owner) < ($1.key, $1.owner) }
    }

    /// One part as a row keeps it: `<tx>:<logIndex>|<amount>|<unix seconds>`.
    /// The row's money is recomputed from these (`Kept`), so a day that grew
    /// can never disagree with the parts it holds.
    static func factValue(_ s: Settlement) -> String? {
        guard let at = s.at else { return nil }
        return "\(s.key)|\(s.amount)|\(Int(at.timeIntervalSince1970))"
    }

    /// A kept part, read back. nil for anything that is not exactly the shape
    /// `factValue` writes — such a fact counts toward nothing.
    struct Kept: Equatable {
        let key: String
        let amount: Double
        let at: Date
        /// The transaction half of the key, for the row's link.
        var txHash: String { String(key.split(separator: ":").first ?? "") }

        init?(_ value: String) {
            let parts = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, parts[0].contains(":"),
                  let amount = Double(parts[1]), amount.isFinite, amount >= 0,
                  let t = TimeInterval(parts[2])
            else { return nil }
            key = parts[0]
            self.amount = amount
            at = Date(timeIntervalSince1970: t)
        }
    }

    /// A row's total and newest moment, off its kept parts. Summed through
    /// `Decimal` at six places so twenty parts add to the cent.
    static func total(of kept: [Kept]) -> (amount: Double, newest: Kept)? {
        guard let newest = kept.max(by: { ($0.at, $0.key) < ($1.at, $1.key) }) else { return nil }
        var sum = Decimal(0)
        for k in kept { sum += Decimal(string: String(k.amount)) ?? Decimal(k.amount) }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &sum, usdt0Decimals, .plain)
        return (Double(NSDecimalNumber(decimal: rounded).stringValue) ?? 0, newest)
    }

    /// The parts of `day` not already on its row. Empty means the row already
    /// holds all of it — a rewound cursor or a re-watch re-reads the same
    /// settlements, and must not add them twice.
    static func newParts(of day: Day, alreadyKept kept: Set<String>) -> [Settlement] {
        day.parts.filter { !kept.contains($0.key) }
    }

    // MARK: - Code

    /// Is this bytecode a Plasma One card contract? Its own size and the
    /// beacon it carries — both measured on every sampled card.
    static func isCardCode(_ code: String) -> Bool {
        let hex = code.lowercased()
        return hex.hasPrefix("0x") && (hex.count - 2) / 2 == cardCodeBytes
            && hex.contains(cardBeacon)
    }

    /// Can this address hold a card at all? Owners are smart accounts; a
    /// plain key ("0x" — no code) never is one.
    static func hasCode(_ code: String) -> Bool {
        let hex = code.lowercased()
        return hex.hasPrefix("0x") && hex.count > 2
    }

    // MARK: - Hex

    /// An address as a 32-byte indexed log topic.
    static func topic(_ address: String) -> String {
        "0x000000000000000000000000" + address.dropFirst(2).lowercased()
    }

    /// A topic or a 32-byte word's last twenty bytes, as `0x…` lowercased;
    /// nil for anything that is not a word.
    static func address(fromTopic topic: String) -> String? {
        let hex = topic.lowercased()
        guard hex.hasPrefix("0x"), hex.count == 66 else { return nil }
        return "0x" + hex.suffix(40)
    }

    static func hexInt(_ hex: String) -> Int? {
        let body = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        return Int(body, radix: 16)
    }

    private static func bytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return out
    }
}
