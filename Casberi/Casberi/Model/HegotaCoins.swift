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
}
