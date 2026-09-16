import Foundation

/// WHETHER AN ADDRESS BELONGS TO A VERIFIED HUMAN (prd §784, 2026-09-16) — the
/// pure half, encoders and verdict, with every read in `WorldIDSource`.
///
/// World ID's address book is one contract on World Chain holding one mapping:
/// `addressVerifiedUntil(address) → uint256`, the second an Orb verification
/// expires, or zero for an address it has never seen. Anybody may read it. So
/// this is a keyless `eth_call` and **no seat, no account, no key and no
/// World App** — the same class as `WeiNames` and for the same reason (prd
/// §515a: a fact the wallet can read on its own never also ships as an offer).
///
/// **Foundation-only BY DESIGN** (`Keccak256` beside it is pure too), so
/// `scripts/worldid-selftest.sh` compiles this file WHOLE and unmodified and
/// every assertion is about the bytes the app runs.
///
/// ## What this fact is worth, and what it is not
///
/// Worth: an address in this book is one a person proved themselves for, once,
/// at an Orb. Two places in this app care. An address you are about to pay —
/// a poisoned look-alike (`AddressSafety.lookalikes`) cannot carry the mark
/// its target carries. And a face in a social room — `FarcasterIngest` already
/// resolves an account's verified addresses, so the room can finally answer
/// "is anybody there" instead of leaving you to guess.
///
/// Not worth, and the surfaces must never say otherwise (§83): **a zero is
/// not "not a person".** It means this book has no verification for this
/// address, which is the ordinary answer for almost every address on earth.
/// So `absent` and `unknown` both draw NOTHING. `verified` draws, and so does
/// `lapsed` — "was verified, and it ran out" is a different fact from "never
/// was", and the date is what says so.
///
/// ## Measured, and deliberately not
///
/// The contract address and the mapping's name are World's published ones. The
/// selector is computed off `Keccak256` at call time rather than hardcoded
/// (`WeiNames`' rule — the one place a typo produces a revert that reads
/// exactly like a dead contract), and the harness pins it against a keccak
/// implementation written independently of this app's.
///
/// **UNMEASURED against the live contract** (the session that wrote this had
/// no route to World Chain): whether a permanent verification is stored as a
/// far-future second or as a sentinel this file would read as malformed. That
/// is what `-worldIDProbe` prints the RAW word for. Read it before trusting
/// `Status` on an address you know is verified.
enum WorldID {

    /// Alchemy's id for World Chain, matching `WalletChainStore.selectable`.
    /// The read does not depend on that chain being switched on — this book is
    /// a fact about an address, not a wallet you follow.
    static let network = "worldchain-mainnet"
    static let chainId = 480

    /// The World ID address book. Published by World; deployed on World Chain.
    static let addressBook = "0x57b930D551e677CC36e2fA036Ae2fe8FdaE0330D"

    /// The keyless host the read goes to. Declared in `NetworkReach` under
    /// "World ID" — this file is the only place it is spelled.
    ///
    /// **NOT the wallet's `worldchain-mainnet.g.alchemy.com`, and that is the
    /// fix rather than a preference.** The receipts screen resolves a row's
    /// service BY HOST (`NetworkLedger.resolvedService` is `byHost ?? named`,
    /// and the host match wins because it is the half a static audit can
    /// prove), so one host reached by two callers can only ever be labelled
    /// with one of their names. Sharing Alchemy's host filed this read under
    /// the **Wallet bridge** — for a person who never connected Wallet — while
    /// the code, prd §784 and the harness all claimed otherwise. Two purposes,
    /// two hosts, and each row says something true.
    ///
    /// dRPC because this app already reaches that provider and has measured it
    /// (`WeiNamesSource`'s pacer was tuned against `eth.drpc.org`); their chain
    /// subdomains are uniform. **UNMEASURED for World Chain** — `-worldIDProbe`
    /// prints the host it called and whether anything answered.
    static let rpc = "https://worldchain.drpc.org"

    /// The mapping's public getter.
    static let verifiedUntilSignature = "addressVerifiedUntil(address)"

    /// What the book says about one address.
    ///
    /// Four cases and not three: `unknown` (never asked, or nothing answered)
    /// and `absent` (asked, and the book holds nothing) must never render the
    /// same way — "not verified" is a claim we have not earned until we have
    /// looked, and even then it is not a claim about the person.
    enum Status: Equatable {
        case unknown
        case absent
        case verified(until: Date)
        case lapsed(at: Date)

        var isVerified: Bool { if case .verified = self { return true }; return false }
    }

    // MARK: - Calldata

    /// A function selector computed at call time, never hardcoded — bare hex,
    /// no `0x`, so a fragment can never reach `eth_call` by itself.
    static func selector(_ signature: String) -> String {
        Keccak256.hexString(Array(Keccak256.hash(Array(signature.utf8)).prefix(4)))
    }

    /// `addressVerifiedUntil(address)`, or nil when the input is not a hex
    /// address — refused rather than padded, so a handle or a `.sol` address
    /// can never be asked about here and answered "absent".
    static func verifiedUntilCalldata(address: String) -> String? {
        guard let word = addressWord(address) else { return nil }
        return "0x" + selector(verifiedUntilSignature) + word
    }

    /// A left-padded 32-byte word for a hex address. Lowercased: EIP-55 case
    /// is a checksum, never identity.
    static func addressWord(_ address: String) -> String? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.hasPrefix("0x"), value.count == 42,
              value.dropFirst(2).allSatisfy(\.isHexDigit) else { return nil }
        return String(repeating: "0", count: 64 - 40) + String(value.dropFirst(2))
    }

    // MARK: - Decoding

    /// The nth 32-byte word of an `eth_call` return, without `0x`, lowercased
    /// — nil when the response is short or malformed, which is how a reverted
    /// call and a real answer are told apart.
    static func word(_ hex: String, _ n: Int) -> String? {
        let s = (hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex).lowercased()
        guard s.allSatisfy(\.isHexDigit) else { return nil }
        let start = n * 64
        guard s.count >= start + 64 else { return nil }
        let i0 = s.index(s.startIndex, offsetBy: start)
        let i1 = s.index(s.startIndex, offsetBy: start + 64)
        return String(s[i0..<i1])
    }

    /// The unix second the return carries: 0 for an address the book has never
    /// seen, nil for anything this file cannot read as a number — an empty
    /// return (a revert, a wrong contract, a chain that did not answer) and a
    /// word too large for an `Int` alike. **nil is never "not verified"**; it
    /// is "we do not know", and `Status` keeps them apart.
    static func verifiedUntilSeconds(from hex: String) -> Int? {
        guard let word = word(hex, 0) else { return nil }
        let digits = word.drop(while: { $0 == "0" })
        if digits.isEmpty { return 0 }
        return Int(digits, radix: 16)
    }

    /// The verdict for a return, as of a moment. The clock is a parameter so
    /// the harness can stand either side of an expiry.
    static func status(fromReturn hex: String, asOf now: Date) -> Status {
        guard let seconds = verifiedUntilSeconds(from: hex) else { return .unknown }
        return status(untilUnix: seconds, asOf: now)
    }

    /// The second stored for an answer the chain gave that this file could not
    /// read as a number — a word too large for an `Int`, which is what a
    /// permanent-verification sentinel would look like (UNMEASURED, see the
    /// header). It is stored so the address is not re-asked on every visit,
    /// and it reads back as `.unknown`, which draws nothing: we were answered
    /// and we do not know what it said.
    static let unreadableSeconds = -1

    /// The verdict for a stored second. A verification EXPIRES, so the stored
    /// number keeps answering as the clock moves past it — a lapsed mark needs
    /// no second read to stop claiming.
    static func status(untilUnix seconds: Int, asOf now: Date) -> Status {
        guard seconds != unreadableSeconds else { return .unknown }
        guard seconds > 0 else { return .absent }
        let until = Date(timeIntervalSince1970: TimeInterval(seconds))
        return until > now ? .verified(until: until) : .lapsed(at: until)
    }
}
