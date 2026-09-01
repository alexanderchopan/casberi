import Foundation

/// The Ethrex Hegotá UTXO set, read from what the chain publishes about itself.
///
/// Hegotá's mode-5 frames spend and create UTXOs held by a vault predeploy, and
/// the whole set is reconstructible with no indexer and no key: the vault emits
/// a `UtxoCreated` LOG3 per coin (`topics = [signature, source, recipient]`,
/// `data = index ‖ value`) and keeps a spent BITMAP in its own storage, one bit
/// per coin. So `eth_getLogs` filtered on the recipient topic gives every coin
/// an address was ever paid, and one `eth_getStorageAt` per 256 coins says
/// which of them are still unspent.
///
/// ## THE READ CHECKS ITSELF, AND IS MADE TO
///
/// Measured against the live chain on 2026-08-27: reconstructing every unspent
/// coin summed to **1.120287 ETH**, and the vault's own `eth_getBalance` was
/// **1.120287 ETH** — exact. That is not a coincidence to admire, it is the
/// card's gate. `reconciles(unspent:vaultWei:)` must agree before anything is
/// drawn, because an arithmetic that can prove itself right has to, or the
/// first drifted parse ships as a confident wrong number in the largest type on
/// the card (§83, in the one place a reader has no way to check us).
///
/// ## EVERY REFUSAL HERE IS DELIBERATE
///
/// Each of these returns nil rather than a plausible number, because on this
/// card a wrong figure renders exactly as well as a right one:
///   • a coin whose spent BIT could not be read is not "unspent" — the whole
///     set is refused, since one silently-assumed bit is the difference between
///     money you have and money you spent
///   • a log whose topic is not address-shaped yields no coin
///   • a value too large to hold exactly is refused rather than rounded
///   • a spend whose outputs exceed its inputs yields no fee, because a
///     negative fee is a parse bug wearing a number
///
/// Foundation-only by design — no chain access, no `Decimal` formatting, no
/// SwiftUI — so `scripts/hegota-selftest.sh` compiles it WHOLE and unmodified.
enum HegotaChain {
    static let chainID = 3151908

    /// **Predeploys, at fixed spec-assigned addresses — and this is where
    /// Hegotá is EASIER than vibenet.** vibenet's contracts redeploy without
    /// warning, so its whole `VibenetConfig` apparatus exists to fetch the
    /// address map before every read and its file header bans an address
    /// literal outright. These are predeploys: the chain installs them at
    /// activation at the addresses the EIPs assign, so a literal here is the
    /// correct spelling rather than a hazard. Verified on chain 2026-08-27 —
    /// both carry code.
    static let vault = "0x0000000000000000000000000000000000008312"
    static let nonceManager = "0x0000000000000000000000000000000000008250"

    /// EIP-7708 emits a transfer log for every ETH movement from this address,
    /// which is what makes an address's whole value history one `eth_getLogs`
    /// rather than an indexer's job.
    static let transferLogSource = "0xfffffffffffffffffffffffffffffffffffffffe"

    /// `keccak("UtxoCreated…")` as the vault's own runtime code emits it — the
    /// topic is a literal INSIDE that 76-byte predeploy, so it can be checked
    /// against `eth_getCode` rather than taken on trust. Measured 2026-08-27.
    static let utxoCreatedTopic =
        "0x3b19241465a47bc187f1d9c7db70834855a907183742a4b63aa824c576296f5e"

    /// The ordinary ERC-20 `Transfer` signature, which EIP-7708 reuses.
    static let transferTopic =
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
}

// MARK: - Words off the wire

enum HegotaWord {
    /// A 32-byte log word as an exact integer.
    ///
    /// **Refuses rather than rounds.** `Decimal` carries 38 significant digits,
    /// so anything under 2^96 wei (about 79 billion ETH, against a real supply
    /// near 120 million) is exact and anything above it would silently lose its
    /// low digits — and a wei figure that has quietly lost its tail is a number
    /// nobody can see is wrong.
    static func integer(_ hexWord: String) -> Decimal? {
        guard let body = normalized(hexWord) else { return nil }
        // The top 40 nibbles must be zero, leaving 24 to carry the value.
        guard body.prefix(40).allSatisfy({ $0 == "0" }) else { return nil }
        var acc = Decimal(0)
        for ch in body.suffix(24) {
            guard let d = ch.hexDigitValue else { return nil }
            acc = acc * 16 + Decimal(d)
        }
        return acc
    }

    /// A 32-byte word as a `UInt64` — for a coin's index, which the vault
    /// allocates from a counter and which its own storage layout bounds at
    /// 2^64. A word that does not fit is refused, never truncated.
    static func index(_ hexWord: String) -> UInt64? {
        guard let body = normalized(hexWord) else { return nil }
        guard body.prefix(48).allSatisfy({ $0 == "0" }) else { return nil }
        return UInt64(body.suffix(16), radix: 16)
    }

    /// An address out of a 32-byte topic.
    ///
    /// The upper 12 bytes MUST be zero. A topic that is not address-shaped is
    /// not an address we failed to read, it is a log we have misunderstood —
    /// and taking its low 20 bytes anyway invents a counterparty.
    static func address(topic: String) -> String? {
        guard let body = normalized(topic) else { return nil }
        guard body.prefix(24).allSatisfy({ $0 == "0" }) else { return nil }
        return "0x" + body.suffix(40).lowercased()
    }

    /// Exactly 64 hex characters, with or without the `0x`. Anything else is a
    /// shape we did not expect and must not guess at.
    static func normalized(_ hex: String) -> String? {
        var s = Substring(hex)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = s.dropFirst(2) }
        guard s.count == 64, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(s)
    }
}

// MARK: - The spent bitmap

enum HegotaVaultStorage {
    /// Which storage word holds a coin's spent bit. One word covers 256 coins,
    /// which is what makes the whole set readable in a handful of requests.
    static func word(index: UInt64) -> UInt64 { index >> 8 }

    /// The vault's spent-bit region begins at 2^129 and runs one word per 256
    /// coins: `slot = 2^129 + (index >> 8)`. The regions of that storage layout
    /// are provably disjoint for index below 2^64, so the sum never carries out
    /// of the low nibbles into the marker bit.
    ///
    /// Built as a padded 32-byte word rather than by arithmetic, because 2^129
    /// does not fit any fixed-width integer this file is allowed to reach for.
    /// Bit 129 lands in nibble 32 counted from the right, which is index 31
    /// counted from the left of a 64-nibble word, and carries the value 2.
    static func spentSlot(index: UInt64) -> String {
        var nibbles = [Character](repeating: "0", count: 64)
        nibbles[31] = "2"
        let low = String(word(index: index), radix: 16)
        for (offset, ch) in low.reversed().enumerated() {
            nibbles[63 - offset] = ch
        }
        return "0x" + String(nibbles)
    }

    /// Is this coin spent, according to the word its bit lives in?
    ///
    /// Returns nil for a word we could not read, and the caller must treat that
    /// as "we don't know" rather than "not spent" — see `HegotaCoins.unspent`.
    static func isSpent(index: UInt64, word hexWord: String) -> Bool? {
        guard let body = HegotaWord.normalized(hexWord) else { return nil }
        let bit = Int(index & 0xFF)
        let chars = Array(body)
        guard let digit = chars[63 - bit / 4].hexDigitValue else { return nil }
        return (digit >> (bit % 4)) & 1 == 1
    }
}

// MARK: - Coins

struct HegotaCoin: Equatable, Sendable, Codable {
    let index: UInt64
    let wei: Decimal
    /// Who created this coin. Equal to `owner` when it is change coming back.
    let source: String
    let owner: String
    let block: UInt64
    /// The transaction that created this UTXO.
    ///
    /// **What makes a coin openable.** Everything else we know about a coin is
    /// already on its row, so a sheet would repeat it — but coins created by
    /// the SAME transaction are the outputs of one spend, and that is the whole
    /// UTXO reading: money went in, and came back out as several pieces, one of
    /// them change. Optional because a coin decoded before this was stored has
    /// no hash and simply does not open.
    var createdBy: String? = nil

    /// When the coin was created. The same bounded header read a move's time
    /// comes from, and nil for the same reason: an index is an ordinal, not
    /// an age, and the vault's counter says which coin came first and nothing
    /// about when.
    var timestamp: Date? = nil

    /// A time interpolated between two headers we read — `HegotaMove`'s own
    /// field and the same grading rule: an estimate is stated to the day.
    var estimatedAt: Date? = nil

    /// A coin that came back to whoever spent it — the change output, and the
    /// single most explanatory row on the card, because it is the part of the
    /// UTXO model an account-balance reader has no intuition for.
    var isChange: Bool { source == owner }
}

enum HegotaCoins {
    /// One `UtxoCreated` log as a coin. Every field is checked; a log that does
    /// not parse whole yields nothing rather than a partly-guessed coin.
    static func coin(topics: [String], data: String, block: UInt64,
                     tx: String? = nil) -> HegotaCoin? {
        guard topics.count == 3,
              HegotaWord.normalized(topics[0])?.lowercased()
                == HegotaWord.normalized(HegotaChain.utxoCreatedTopic)?.lowercased(),
              let source = HegotaWord.address(topic: topics[1]),
              let owner = HegotaWord.address(topic: topics[2])
        else { return nil }

        var body = Substring(data)
        if body.hasPrefix("0x") || body.hasPrefix("0X") { body = body.dropFirst(2) }
        guard body.count == 128 else { return nil }
        guard let index = HegotaWord.index(String(body.prefix(64))),
              let wei = HegotaWord.integer(String(body.suffix(64)))
        else { return nil }

        return HegotaCoin(index: index, wei: wei, source: source, owner: owner,
                          block: block, createdBy: tx)
    }

    /// The unspent coins, oldest first.
    ///
    /// **Returns nil if ANY coin's bit could not be read.** A missing word is
    /// not evidence of anything, and treating it as unspent shows money that is
    /// already gone — the one wrong answer on this card that a reader would act
    /// on. Refusing the whole set is right rather than harsh, because the card
    /// below reconciles against the vault and a partial set can never
    /// reconcile: a half-answer would fail the gate anyway, having first cost a
    /// reader the impression that we knew.
    ///
    /// Ordered by index, which is the vault's own allocation counter and
    /// therefore age. Age is the ordering the drawing wants, and the only one
    /// available without a second read per coin.
    static func unspent(_ coins: [HegotaCoin], words: [UInt64: String]) -> [HegotaCoin]? {
        var out: [HegotaCoin] = []
        for coin in coins {
            guard let word = words[HegotaVaultStorage.word(index: coin.index)],
                  let spent = HegotaVaultStorage.isSpent(index: coin.index, word: word)
            else { return nil }
            if !spent { out.append(coin) }
        }
        return out.sorted { $0.index < $1.index }
    }

    static func total(_ coins: [HegotaCoin]) -> Decimal {
        coins.reduce(Decimal(0)) { $0 + $1.wei }
    }

    /// Does the reconstructed set account for exactly what the vault holds?
    ///
    /// EXACT equality, deliberately — these are integers off the same chain,
    /// not measurements, so a tolerance would only ever hide a bug. Note this
    /// is the whole-chain check: it holds across every owner's coins together,
    /// which is why the card runs it over the full set rather than the watched
    /// address's slice.
    static func reconciles(unspent: [HegotaCoin], vaultWei: Decimal) -> Bool {
        total(unspent) == vaultWei
    }

    /// What a spend paid the chain: inputs minus outputs.
    ///
    /// **Derived, never reported.** Nothing on the wire states a UTXO frame's
    /// fee, and this is the same standard the money receipt holds itself to.
    /// Returns nil when the outputs exceed the inputs, because conservation
    /// makes that impossible on chain — so it is our parse that is wrong, and a
    /// negative fee would render as confidently as a real one.
    static func fee(inputs: [Decimal], outputs: [Decimal]) -> Decimal? {
        guard !inputs.isEmpty else { return nil }
        let spent = inputs.reduce(Decimal(0), +)
        let out = outputs.reduce(Decimal(0), +)
        return out > spent ? nil : spent - out
    }

    /// Wei as ETH. No price, ever — this is test ETH and it is worth nothing,
    /// so an amount here is a quantity and never a value.
    static func eth(_ wei: Decimal) -> Decimal {
        wei / Decimal(sign: .plus, exponent: 18, significand: 1)
    }

    /// A coin's share of the set it is drawn in, 0…1.
    ///
    /// **Of THIS ADDRESS'S coins, never of the vault** — the vault's share is
    /// `censusLine`'s, and mixing the two denominators inside one card is how a
    /// cell ends up claiming 45% of somebody else's money. Nil on an empty set:
    /// a share of nothing is undefined, not zero.
    ///
    /// It replaced `dominance` (prd §555), which answered one question about
    /// the whole set — "is one piece almost all of it" — for a CAPTION that no
    /// longer exists. Every drawn cell prints its own share now, which answers
    /// the same question on the cell that raises it, and for every cell rather
    /// than only the leader.
    static func share(_ wei: Decimal, of coins: [HegotaCoin]) -> Double? {
        let sum = total(coins)
        guard sum > 0 else { return nil }
        return NSDecimalNumber(decimal: wei / sum).doubleValue
    }
}

// MARK: - The whole chain's vault, and what our slice is of it

/// The census the reconciliation already performed and then threw away.
///
/// **This costs NOTHING new (2026-08-27).** `readCoinState` reads every
/// `UtxoCreated` log on the chain and every spent bit, because conservation can
/// only be checked across all owners at once — and then kept a single Bool. The
/// set it proved complete holds the answer to "how much of this chain's vault
/// is mine", which is a reading no other room in this app can make about
/// anything: not a share we estimated, a share we verified.
///
/// It is stated only when the set RECONCILED, for the same reason `coinsWei` is:
/// an unreconciled census is a denominator nobody should read.
struct HegotaCensus: Equatable, Sendable, Codable {
    /// Unspent coins across every owner on the chain.
    let coins: Int
    /// Distinct owners holding at least one unspent coin.
    let owners: Int
    /// What the whole vault holds — equal to its `eth_getBalance`, which is
    /// what "reconciled" means.
    let wei: Decimal
    /// This room's own slice of it.
    let mineCoins: Int
    let mineWei: Decimal

    /// Our share of the vault, 0…1. Nil when the vault is empty — a share of
    /// nothing is not zero, it is undefined, and drawing it as zero says the
    /// person holds none of something that does not exist.
    var share: Double? {
        guard wei > 0 else { return nil }
        return NSDecimalNumber(decimal: mineWei / wei).doubleValue
    }

    /// Whether this address is the only owner in the vault. Worth its own
    /// sentence: on a devnet it is a real and common state, and "all of it" is
    /// a different reading from "most of it".
    var soleOwner: Bool { owners == 1 && mineCoins == coins && mineCoins > 0 }

    /// Compose over the whole chain's proven-unspent set.
    ///
    /// Returns nil when the set did not reconcile or holds nothing — the card
    /// then says nothing rather than a census over numbers we could not check.
    /// `mine` is matched case-insensitively for `HegotaParty`'s reason: an
    /// EIP-55 address and an RPC's lowercase answer are one account.
    static func of(_ all: [HegotaCoin], mine watched: [String],
                   reconciled: Bool) -> HegotaCensus? {
        guard reconciled, !all.isEmpty else { return nil }
        let keys = Set(watched.map { $0.lowercased() })
        let mine = all.filter { keys.contains($0.owner.lowercased()) }
        return HegotaCensus(coins: all.count,
                            owners: Set(all.map { $0.owner.lowercased() }).count,
                            wei: HegotaCoins.total(all),
                            mineCoins: mine.count,
                            mineWei: HegotaCoins.total(mine))
    }
}

// MARK: - Where a keyed nonce's counter lives

/// The nonce manager's storage layout — MEASURED, because the contract will not
/// answer a call (prd §509).
///
/// **The predeploy's whole runtime is five bytes**, `0x60006000fd` —
/// `PUSH0 PUSH0 REVERT` — so every `eth_call` against it reverts and there is no
/// getter to ask. Its state is still public, and reading it directly is the only
/// way to learn a keyed counter's real value.
///
/// **The slot is `keccak256(pad32(address) ‖ pad32(key))`**, confirmed against
/// the live chain 2026-08-28: the only address on this devnet sending on named
/// keys reads `0x1` at that slot for BOTH `0xbeef01` and `0x1234`, matching its
/// one observed send on each. Four other plausible layouts (key-first, the
/// Solidity nested-mapping form, and two packed forms) all read zero, so the
/// derivation is pinned by a positive AND four negatives rather than by one
/// lucky hit.
///
/// Why it matters: `HegotaNonceLane.sends` is COUNTED FROM OBSERVED MOVES, which
/// undercounts by construction — a send that moved no ETH emits no transfer log.
/// That is the exact gap §504 closed for key 0 with `eth_getTransactionCount`,
/// and this is the same fix for every other key. The card says "at least"
/// today precisely because this number was not available.
enum HegotaNonceStorage {
    /// The storage slot holding `address`'s counter for one named `key`.
    ///
    /// Returns nil rather than a guessed slot when either input is not
    /// hex-shaped: a wrong slot reads as a legitimate zero, which would report
    /// "never sent on this key" about a key the room is only listing BECAUSE it
    /// has been sent on.
    static func slot(address: String, key: String) -> String? {
        guard let a = word(address), let k = word(key) else { return nil }
        return "0x" + Keccak256.hexString(Keccak256.hash(a + k))
    }

    /// A value as a left-padded 32-byte word. Both halves of the preimage are
    /// padded — an address is 20 bytes and a key is however many the sender
    /// chose, and the layout hashes two full words.
    private static func word(_ hex: String) -> [UInt8]? {
        var body = Substring(hex.lowercased())
        if body.hasPrefix("0x") { body = body.dropFirst(2) }
        guard !body.isEmpty, body.count <= 64, body.allSatisfy(\.isHexDigit) else { return nil }
        let padded = String(repeating: "0", count: 64 - body.count) + body
        var out: [UInt8] = []
        out.reserveCapacity(32)
        var i = padded.startIndex
        while i < padded.endIndex {
            let j = padded.index(i, offsetBy: 2)
            guard let b = UInt8(padded[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        return out
    }
}

// MARK: - Is this still the same chain?

/// Whether the chain we just read is the chain we read last time.
///
/// **The one failure mode every other refusal in this room misses (2026-08-27).**
/// Every guard here — an unreached host, a coin whose spent bit would not read,
/// an account left out of a total — protects against a read that FAILED. A
/// devnet relaunch is the opposite: all three hosts answer perfectly, quickly,
/// and with nothing. Balance zero, no transfer logs, no coins, no lanes. Drawn
/// through the room's ordinary paths that is an account whose money left, on the
/// screen whose largest number is a balance — and both worked examples, which
/// are hardcoded addresses, go blank at once. Hegotá is an experimental devnet;
/// being relaunched from genesis is a thing it is expected to do.
///
/// **The signal is the GENESIS HASH, not the tip going backwards.** A tip below
/// the high-water mark has three causes and only one is a reset: a host serving
/// a stale view, a reorg, and a relaunch. Genesis is decisive — a new chain has
/// a new genesis block, and an unchanged one proves the history is still ours
/// however far behind a particular host happens to be.
enum HegotaGenesis {
    enum Verdict: String, Equatable, Sendable {
        /// Same chain, same history.
        case same
        /// The devnet was relaunched. Everything we knew about it is gone —
        /// not spent, not moved: never happened on this chain.
        case restarted
        /// A host answered for some OTHER chain. Different failure, different
        /// sentence: the reads are wrong rather than the history being gone.
        case differentChain
        /// Nothing to compare — a first sweep, or a read that did not answer.
        /// **Never `same`**: not knowing is not knowing.
        case unknown
    }

    /// Compare what a sweep saw against what the device remembers.
    ///
    /// Order matters: the chain id is checked FIRST, because if a host is
    /// serving a different chain then its genesis differing is a consequence
    /// rather than the finding, and "the devnet restarted" would be the wrong
    /// sentence to show for it.
    static func verdict(chainID: Int?, genesis: String?,
                        knownGenesis: String?) -> Verdict {
        if let chainID, chainID != HegotaChain.chainID { return .differentChain }
        guard let seen = genesis.flatMap(HegotaWord.normalized)?.lowercased(),
              let known = knownGenesis.flatMap(HegotaWord.normalized)?.lowercased()
        else { return .unknown }
        return seen == known ? .same : .restarted
    }
}

// MARK: - Turning a block number into a time

/// The room's clock past the header window.
///
/// **Measured 2026-08-27, and the measurement is what makes this honest.**
/// Hegotá produces a block every six seconds, and across its whole history —
/// 310,833 blocks — the timestamps ran a total of 72 seconds ahead of exact
/// six-second spacing, i.e. twelve missed slots in twenty-one days. So a block
/// number interpolated between two headers we actually READ is accurate to
/// within the missed slots inside that bracket, which at this chain's rate is
/// seconds.
///
/// That is what retires the room's old refusal. `readTimes` reads at most
/// `timeDepth` headers, so anything older carried no time at all and the room
/// had undated rows by design — correct when a block number was the only clock
/// we had, and needlessly strict once two real headers bracket the row.
///
/// **The estimate is still not the same thing as a reading**, so it is returned
/// as a distinct case rather than filled into `timestamp`: an interpolated time
/// is stated to the DAY, and a read one keeps its clock. Anything outside the
/// bracket is refused rather than extrapolated — beyond the newest header we
/// hold, drift has no ceiling we have measured.
enum HegotaClock {
    /// Seconds per block on this chain.
    static let slotSeconds: Double = 6

    /// Estimate a block's time from the headers we hold.
    ///
    /// Returns nil unless the block sits BETWEEN two known headers. Both
    /// neighbours are used rather than one plus the slot time, because the
    /// interpolation then carries the real spacing of that stretch — including
    /// whatever slots it missed — instead of assuming a rate.
    static func estimate(block: UInt64, from known: [UInt64: Date]) -> Date? {
        guard !known.isEmpty else { return nil }
        if let exact = known[block] { return exact }

        var below: (UInt64, Date)?
        var above: (UInt64, Date)?
        for (candidate, when) in known {
            if candidate < block, below == nil || candidate > below!.0 {
                below = (candidate, when)
            }
            if candidate > block, above == nil || candidate < above!.0 {
                above = (candidate, when)
            }
        }
        guard let low = below, let high = above, high.0 > low.0 else { return nil }
        let span = Double(high.0 - low.0)
        let into = Double(block - low.0)
        let seconds = high.1.timeIntervalSince(low.1)
        return low.1.addingTimeInterval(seconds * (into / span))
    }
}

// MARK: - The census, said out loud

extension HegotaCensus {
    /// What our slice is of the whole vault, in a sentence.
    ///
    /// **It is a fact about the CHAIN, not about your coins.** It used to sit
    /// under the Coins figure's treemap, where 116pt of map plus a two-line
    /// share ran the 168pt figure slot over and clipped the drawing (prd §555,
    /// user: *"we need to get rid of the '1% of everything…' helper text bc it
    /// clips the image of the treemap"*). It lives in the coin list's footer
    /// now, beside the reconciliation sentence it is really a companion to.
    ///
    /// Here rather than in the view so there is ONE of it: it was written into
    /// two files during the move, which is the drift this project has a
    /// paragraph about in three other places.
    ///
    /// **Nil when the vault is empty**, following `share`'s own rule: a share
    /// of nothing is undefined, and printing 0% says the person holds none of
    /// something that does not exist.
    var line: String? {
        guard let share else { return nil }
        return soleOwner
            ? String(localized: "Every UTXO on the chain is yours")
            : String(localized: "\(Int((share * 100).rounded()))% of everything in the vault, across \(String(owners)) owners")
    }
}
