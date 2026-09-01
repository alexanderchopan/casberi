import Foundation

/// Renewing a followed name — PREPARED here, signed somewhere else
/// (2026-08-31, prd §540). The §112 preparing surface, second instance:
/// `WalletPrepare` does this for an approval's revoke, and this does it for a
/// `.eth` renewal. Casberi reads the price, encodes the transaction, quotes
/// the fee, and hands the whole thing to the person's own wallet. It signs
/// nothing and holds no key.
///
/// Foundation-only BY DESIGN so `scripts/ens-renew-selftest.sh` compiles it
/// WHOLE and unmodified. Nothing here fetches; `ENSRenewPrepare` does the
/// reads and calls in.
///
/// **WHY THIS FILE IS THE DANGEROUS ONE.** Every prepared transaction this app
/// has ever produced carries `"value": "0x0"` — a revoke costs gas and moves
/// nothing. This one moves REAL MONEY when signed, and a wrong byte here is
/// not a crash: it is a well-formed transaction that a wallet will happily
/// sign and a chain will happily execute, doing something nobody asked for.
/// That is why the ABI encoding below is pinned against vectors produced by an
/// independent implementation rather than merely eyeballed.
///
/// **EVERY CONSTANT HERE WAS MEASURED ON MAINNET 2026-08-31**, not recalled,
/// and two of them would have shipped as bugs from memory alone. See each.
enum ENSRenew {

    // MARK: - The contract

    /// The `.eth` registrar controller. **MEASURED 2026-08-31**: this address
    /// holds 9,739 bytes of code and `BaseRegistrar.controllers(…)` answers
    /// `1` for it.
    ///
    /// **THE TRAP, and it is the expensive one.** The long-standing controller
    /// everybody's notes and blog posts name —
    /// `0x253553366Da8546fC250F225fe3d25d0C782303b` — is **NO LONGER
    /// AUTHORIZED**: `controllers(…)` answers `0` for it today, measured the
    /// same minute as the above. Calldata built against it still ENCODES
    /// perfectly, still looks right in a wallet's confirm screen, and reverts
    /// on submission after the person has already approved spending money.
    /// A hardcoded "well-known" address is exactly how that ships.
    static let controller = "0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547"

    /// `renew(string,uint256,bytes32)` — **THREE arguments, not two.** The old
    /// controller took `renew(string,uint256)`; the live one takes a third
    /// `referrer` word (ENS's referral programme). Measured by reading the
    /// deployed bytecode for both selectors: the two-argument form is ABSENT
    /// from the live controller and the three-argument form is PRESENT.
    ///
    /// Derived from the signature rather than pasted as a magic constant
    /// (`AerodromeDeFi`'s precedent), so the harness can pin the derivation
    /// against the measured value instead of pinning a number to itself.
    static var renewSignature: String { "renew(string,uint256,bytes32)" }
    static var rentPriceSignature: String { "rentPrice(string,uint256)" }

    static var renewSelector: String { selector(renewSignature) }
    static var rentPriceSelector: String { selector(rentPriceSignature) }

    /// No referrer. A zero word — this app is nobody's referrer and inventing
    /// one would silently attribute somebody's renewal to a party they never
    /// chose.
    static let noReferrer = String(repeating: "0", count: 64)

    /// Ethereum mainnet. `.eth` names live in exactly one place; there is no
    /// chain picker here and there must never be one.
    static let chainID = 1

    // MARK: - How long

    /// ENS prices by the 365-day year, NOT the calendar year — `duration` is
    /// a raw number of seconds added to the expiry, so a leap year does not
    /// buy an extra day and must not be drawn as though it did.
    static let year: Int = 31_536_000

    enum Term: Int, CaseIterable, Identifiable {
        case oneYear = 1
        case twoYears = 2
        case fiveYears = 5

        var id: Int { rawValue }
        var seconds: Int { rawValue * ENSRenew.year }
        var label: String {
            rawValue == 1
                ? String(localized: "1 year")
                : String(localized: "\(rawValue) years")
        }
    }

    // MARK: - What it costs

    /// The controller's price for a term, as read. Both words are kept even
    /// though only one is charged — see `payable`.
    struct Price: Equatable {
        /// The registration fee, in wei.
        let base: Double
        /// The temporary premium on a name inside its post-release decay
        /// window, in wei.
        ///
        /// **NOT charged on a renewal, and that is measured, not assumed.**
        /// The controller's own `renew` reverts only on
        /// `msg.value < price.base` — the premium never enters the comparison,
        /// because a premium is what you pay to REGISTER a released name, and
        /// a released name cannot be renewed at all. Kept so the card can
        /// explain a nonzero premium rather than silently ignore it.
        let premium: Double
    }

    /// What to actually put in `value`: the base plus a small buffer.
    ///
    /// **Why a buffer at all.** ENS prices in USD and converts through an
    /// oracle at execution time, so the wei figure drifts between the quote
    /// and the signature. Sending exactly the quote is a transaction that
    /// reverts the moment ETH ticks down — after the person has approved it.
    ///
    /// **Why the buffer is SAFE.** The controller refunds the difference:
    /// `if (msg.value > price.base) payable(msg.sender).transfer(msg.value -
    /// price.base)`. Read from the deployed contract's source, not assumed.
    ///
    /// **Why the buffer is SMALL.** That refund is a `.transfer()`, which
    /// forwards 2,300 gas — enough for an EOA and NOT necessarily enough for a
    /// smart-account wallet with a real `receive()`. A failed refund reverts
    /// the whole renewal. So the buffer covers oracle drift and no more; a
    /// generous one would turn "I paid a little extra" into "it didn't go
    /// through" on exactly the wallets that are hardest to debug.
    static let bufferPercent: Double = 5

    static func payable(base: Double) -> Double {
        base * (1 + bufferPercent / 100)
    }

    // MARK: - The transaction

    /// The `renew` calldata for one label and one term.
    ///
    /// **THE LABEL, NEVER THE NAME.** The controller hashes what it is given —
    /// `keccak256(bytes(label))` — so handing it `"vitalik.eth"` renews the
    /// label *"vitalik.eth"*, a different (and almost certainly unregistered)
    /// entry, while the transaction succeeds and the money leaves. Callers
    /// pass `ENSName.label(of:)`, and this refuses anything with a dot in it
    /// rather than trusting them.
    static func calldata(label: String, term: Term) -> String? {
        guard !label.isEmpty, !label.contains("."), !label.contains(where: \.isWhitespace)
        else { return nil }
        // Head: offset to the string's data, the duration, the referrer. The
        // offset is 0x60 because three head words precede the tail — not 0x40
        // as in the two-argument form the old controller took.
        return "0x" + renewSelector
            + word(0x60)
            + word(term.seconds)
            + noReferrer
            + encodedString(label)
    }

    /// The `rentPrice` calldata. Two head words here, so the offset is 0x40 —
    /// spelled out rather than shared with `calldata` above, because the two
    /// functions have different arities and a shared constant would silently
    /// be wrong for one of them.
    static func priceCalldata(label: String, term: Term) -> String? {
        guard !label.isEmpty, !label.contains("."), !label.contains(where: \.isWhitespace)
        else { return nil }
        return "0x" + rentPriceSelector
            + word(0x40)
            + word(term.seconds)
            + encodedString(label)
    }

    /// The wallet-ready transaction, as the same JSON object shape
    /// `WalletPrepare` hands out for a revoke — so anything that already knows
    /// how to take one of ours knows how to take this.
    ///
    /// `value` is a real amount here, which is the whole difference.
    static func transactionJSON(from: String, label: String, term: Term,
                                base: Double) -> String? {
        guard let data = calldata(label: label, term: term), base > 0 else { return nil }
        let value = weiHex(payable(base: base))
        return """
        {"chainId": \(chainID), "data": "\(data)", "from": "\(from)", \
        "to": "\(controller)", "value": "\(value)"}
        """
    }

    // MARK: - Words

    /// "0.0020 ETH". Never a fiat figure: this app has no ETH price it trusts
    /// on this path, and a dollar number quoted beside a transaction somebody
    /// is about to sign is the §83 number-people-believe in its most expensive
    /// form.
    static func ethLine(_ wei: Double) -> String {
        let eth = wei / 1e18
        // Four places carries the 5-plus-character tier (0.0020 ETH) without
        // rounding it to nothing; more places is noise nobody reads.
        return String(format: "%.4f ETH", eth)
    }

    /// The one sentence this card owes that no other prepare surface does.
    ///
    /// **Renewing is PERMISSIONLESS** — measured by reading the deployed
    /// controller's `renew`, which has no owner check of any kind: it takes
    /// the money, extends the registration, and never asks who is paying. So
    /// this card can genuinely offer to renew a name somebody else owns.
    ///
    /// That is a real capability and a real footgun, and the difference is one
    /// sentence: **paying does not transfer the name.** A person who renews a
    /// name they follow has bought that name's owner another year, and gets
    /// nothing. Nobody should learn that after signing.
    static func ownershipNote(isYours: Bool) -> String? {
        isYours ? nil : String(localized: "Renewing pays for this name and does not transfer it — it stays with its current owner.")
    }

    // MARK: - ABI

    /// A `String` as an ABI dynamic `string`: a length word, then the UTF-8
    /// bytes, right-padded to a whole number of words.
    static func encodedString(_ s: String) -> String {
        let bytes = Array(s.utf8)
        // THE LENGTH IS IN BYTES, NOT CHARACTERS. `"café"` is four characters
        // and five bytes; encoding `4` there produces a transaction that is
        // well-formed, signable, and renews a truncated label. Pinned as a
        // harness vector for exactly that reason.
        var hex = word(bytes.count)
        hex += bytes.map { String(format: "%02x", $0) }.joined()
        // Pad to the next word boundary — and add NOTHING when the length is
        // already a multiple of 32. The naive `32 - count % 32` appends a
        // whole dead word on a 32-byte label, which no ordinary name would
        // ever reveal. Also pinned.
        let remainder = bytes.count % 32
        if remainder != 0 { hex += String(repeating: "00", count: 32 - remainder) }
        return hex
    }

    /// A `UInt` as a 32-byte ABI word.
    static func word(_ n: Int) -> String { String(format: "%064x", n) }

    /// A wei amount as a minimal `0x`-prefixed hex quantity, which is what the
    /// JSON-RPC `value` field takes.
    ///
    /// The amount is ROUNDED UP. A `Double` cannot hold a wei figure exactly,
    /// and rounding down lands below `price.base` — a transaction that reverts
    /// for the sake of a fraction of a wei, which is the one rounding
    /// direction that can actually fail.
    static func weiHex(_ wei: Double) -> String {
        guard wei > 0, wei.isFinite else { return "0x0" }
        let rounded = wei.rounded(.up)
        // Above 2^63 a UInt64 conversion traps; no ENS price approaches it,
        // but a prepared transaction must never be the thing that crashes.
        guard rounded < 9.2e18 else { return "0x0" }
        return "0x" + String(UInt64(rounded), radix: 16)
    }

    /// A function selector: the first four bytes of the signature's Keccak-256.
    static func selector(_ signature: String) -> String {
        Keccak256.hexString(Array(Keccak256.hash(Array(signature.utf8)).prefix(4)))
    }
}
