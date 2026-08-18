import Foundation

/// WHAT KEYS CAN SIGN AS YOU (2026-08-18, prd §402).
///
/// Altana's keystore is an onchain registry of an account's signing
/// credentials — passkeys, hardware keys, session keys, backups — kept on L1
/// so every chain can reference one source of truth. It is `WalletActingParties`'
/// question (§293) asked about SIGNATURES rather than about modules and
/// delegates, so it lands as a fourth species in that inventory rather than as
/// a catalog seat of its own.
///
/// ## Why it is not a seat
///
/// Because it would be a seat that can never light up. Measured 2026-08-18
/// over the contract's ENTIRE history — 1.2M blocks, reaching past the
/// deployment at block 25474389 — the L1 keystore holds **five logs**: two
/// ownership transfers, a controller authorization, an ownership handover, and
/// exactly one key registration, belonging to the deployer. A tile promising
/// to read something nobody has is §83's fake status.
///
/// The inventory has no such problem: it already draws nothing when there is
/// nothing to say, so a wallet with no keystore entry sees no change anywhere.
///
/// ## What it costs
///
/// ONE `eth_call` per watched wallet per pass. `getKeys` answers an
/// unregistered address with an empty array rather than reverting (measured),
/// so the common case — which today is every case — ends after one call with
/// no error handling and no follow-up. Detail calls fire only on a hit.
///
/// ## The read surface is wider than the documentation
///
/// `docs.altana.network` advertises `isValidKey` — a POINT query answering
/// "is this key allowed?", which requires already knowing the key, and so can
/// never produce an inventory. Pulling the dispatch table out of the deployed
/// bytecode found 24 selectors on L1 including `getKeys(address)`, a real
/// enumeration. Every selector below was read from that bytecode and confirmed
/// against a public signature database; none was recalled.
///
/// ## L1 only, deliberately
///
/// Base carries a KeyStoreCache that mirrors L1 by storage proof, and it
/// returns the right key ids. But `isValidKey` there reverts with
/// `Cache: call populateKey before isValidKey` (measured) — the per-key
/// population has never been run for the one key that exists, so the cache
/// can list and cannot answer. Reading L1 alone is both simpler and the only
/// thing we can currently stand behind.
///
/// ## Reads only
///
/// The write verbs (`registerKey` `0xa5c2bd05`, `initialRegisterKey`
/// `0x96295a64`, `revokeKey` `0x3cf26a01`, `updateNonce` `0xd7e54cad`,
/// `setAuthorizedContract` `0xf2fa7392`, `populateKey` `0x5ed1e59a`) are named
/// here so the promise is checkable and NEVER called. `scripts/wallet-viz-selftest.sh`
/// fails the build if one appears in a call site — prd §112 holds, nothing
/// here signs, and a prose promise does not count.
///
/// Foundation-only so the harness compiles it as shipped: every failure in
/// this file is a wrong reading that renders perfectly.
enum AltanaKeystore {

    // MARK: - Deployment

    /// One EXECUTION chain the keystore is deployed on, with its own hosts.
    ///
    /// **This table is why the first cut of this seat read empty for everyone**
    /// (2026-08-18, corrected the same day). It shipped reading Ethereum
    /// alone, on the strength of a measurement that was Ethereum-only — and
    /// the explorer then said 39 keys, **38 of them on BNB Smart Chain**.
    /// Verified by calling `getKeys` on real accounts across both: 18 keys on
    /// BNB across 7 accounts, 0 on Ethereum for every one of them. So the
    /// reader was pointed at the chain holding 1/39th of the data and would
    /// have answered "no keys" for every real user of the registry, forever,
    /// with no error anywhere. The standing lesson is the one this codebase
    /// keeps re-earning: **a measurement of one chain is not a measurement of
    /// the network** — ask where the data IS before deciding where to read.
    ///
    /// It carries its OWN hosts rather than joining `WalletApprovals.allChains`
    /// deliberately. That pool serves balances, approvals and transfers for
    /// every watched wallet, and BNB is not in it; adding a fifth chain there
    /// to serve one contract would put every other wallet read on a chain
    /// nobody asked for. This seat reads one fixed address per chain, so it
    /// needs a host list, not a chain abstraction.
    struct Registry: Equatable {
        /// For copy and for the explorer link.
        let label: String
        /// The keystore contract on this chain, lowercased.
        let contract: String
        /// Tried in order; the first that answers wins.
        let hosts: [String]
    }

    /// Measured live 2026-08-18: both deployed, both answering `getKeys`.
    ///
    /// BNB leads because that is where the keys are — the read walks in this
    /// order and an account with nothing anywhere costs one call per chain,
    /// so the cheap common case should fail fast on the busy chain first.
    static let registries: [Registry] = [
        Registry(label: "BNB Smart Chain",
                 contract: "0x6572427ed530badcf7375cf9a4709d8d2b0e7e0a",
                 hosts: ["https://bsc-rpc.publicnode.com",
                         "https://bsc-dataseed.binance.org"]),
        Registry(label: "Ethereum",
                 contract: "0xb70fda90c1d576ba8399946a0c10ecd9d9ea923b",
                 hosts: ["https://ethereum-rpc.publicnode.com",
                         "https://rpc.mevblocker.io"]),
    ]

    // MARK: - Selectors (read from deployed bytecode, 2026-08-18)

    /// `getKeys(address)` → `bytes32[]`. The inventory, and the only call made
    /// for a wallet with nothing registered.
    static let getKeysSelector = "0x34e80c34"
    /// `isRootKey(address,bytes32)` → root credential vs. scoped session.
    static let isRootKeySelector = "0xe1248ed6"
    /// `isKeyActive(address,bytes32)` → live vs. revoked.
    static let isKeyActiveSelector = "0x1364c24d"
    /// `getExpiry(address,bytes32)` → `uint40` seconds; 0 means never.
    static let getExpirySelector = "0x3b49ad47"
    /// `getNonce(address,bytes32)` → whether this key has ever signed.
    static let getNonceSelector = "0x9e2de5a6"
    /// `getKey(address,bytes32)` → the whole record. Read for ONE field the
    /// individual getters don't publish: when the key was registered.
    static let getKeySelector = "0x314f5c11"
    /// `getPublicKey(address,bytes32)` → the raw key material, read only to
    /// decide which curve it lies on (§404).
    static let getPublicKeySelector = "0x7cefdd5d"

    /// Named to be refused, never called. See the type doc.
    static let writeSelectors: Set<String> = [
        "0xa5c2bd05", "0x96295a64", "0x3cf26a01",
        "0xd7e54cad", "0xf2fa7392", "0x5ed1e59a",
    ]

    /// A hostile or garbled reply could claim any array length it likes, and
    /// the decoder would build it. Capped — and the cap is REPORTED rather
    /// than applied in silence (§307's rule: a truncated read that looks
    /// complete is worse than a short one that says so). Far above any
    /// plausible real key count.
    static let maxKeys = 64

    /// How many keys we read the DETAILS of in one pass.
    ///
    /// Separate from `maxKeys`, which guards the decoder against a garbled
    /// length word. This one is a request budget: each key costs four further
    /// `eth_call`s (active, root, expiry, nonce), so an account at the decode
    /// cap would spend 256 sequential reads on a foreground pass — the burst
    /// that made `AerodromeDeFi` need a pacer. Twelve is far above any real
    /// account and bounds a pass at 48 calls; anything past it is reported as
    /// truncated, never dropped in silence.
    static let maxDetailedKeys = 12

    // MARK: - Encoding

    /// `selector + leftPad32(address)`. nil for anything that is not a
    /// 20-byte hex address — a malformed argument would otherwise be padded
    /// into a DIFFERENT, valid-looking address and read somebody else's keys.
    static func encode(_ selector: String, address: String) -> String? {
        guard let a = normalizedAddressBody(address) else { return nil }
        return selector + String(repeating: "0", count: 24) + a
    }

    /// `selector + leftPad32(address) + keyID`. Same refusal on either half.
    static func encode(_ selector: String, address: String, keyID: String) -> String? {
        guard let a = normalizedAddressBody(address),
              let k = normalizedKeyIDBody(keyID) else { return nil }
        return selector + String(repeating: "0", count: 24) + a + k
    }

    /// 40 lowercase hex digits, no prefix — or nil.
    static func normalizedAddressBody(_ address: String) -> String? {
        var s = address.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count == 40, s.allSatisfy(\.isHexDigit) else { return nil }
        return s
    }

    /// 64 lowercase hex digits, no prefix — or nil.
    static func normalizedKeyIDBody(_ keyID: String) -> String? {
        var s = keyID.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count == 64, s.allSatisfy(\.isHexDigit) else { return nil }
        return s
    }

    // MARK: - Decoding

    /// The result of one `getKeys` call.
    ///
    /// `ids` empty with `truncated == false` is a REAL answer — "this wallet
    /// has no keys" — and is distinct from a nil return, which means the call
    /// failed or answered something we refuse to interpret. Collapsing the two
    /// would make an unreachable RPC read as a wallet with nothing registered,
    /// which is the reassuring direction and therefore the wrong one.
    struct KeyList: Equatable {
        let ids: [String]
        let truncated: Bool
    }

    /// Decodes a `bytes32[]` return.
    ///
    /// The offset word must be 0x20 — the single-return-value layout every
    /// real compiler emits, and the same assumption `IngestSupport.decodeABIString`
    /// already makes. Anything else is refused rather than guessed at: a
    /// mis-parsed offset yields key ids read from the wrong place in the
    /// buffer, which look exactly like real ones.
    static func decodeKeyIDs(_ hex: String) -> KeyList? {
        var s = hex.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 128, s.count % 64 == 0, s.allSatisfy(\.isHexDigit) else { return nil }
        guard let offset = word(s, 0), offset == 32,
              let count = word(s, 1), count >= 0 else { return nil }
        let available = (s.count / 64) - 2
        let take = min(count, min(available, maxKeys))
        var ids: [String] = []
        ids.reserveCapacity(take)
        for i in 0..<take {
            let start = (2 + i) * 64
            let lo = s.index(s.startIndex, offsetBy: start)
            let hi = s.index(lo, offsetBy: 64)
            ids.append("0x" + String(s[lo..<hi]))
        }
        return KeyList(ids: ids, truncated: count > take)
    }

    /// A single-word `bool` return. nil for anything that is neither 0 nor 1 —
    /// a contract answering 2 to `isKeyActive` is not answering "true".
    static func decodeBool(_ hex: String) -> Bool? {
        guard let v = singleWord(hex) else { return nil }
        switch v {
        case 0: return false
        case 1: return true
        default: return nil
        }
    }

    /// A single-word unsigned integer return, or nil when it does not fit an
    /// `Int` (see `word`).
    static func decodeUInt(_ hex: String) -> Int? { singleWord(hex) }

    private static func singleWord(_ hex: String) -> Int? {
        var s = hex.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count == 64, s.allSatisfy(\.isHexDigit) else { return nil }
        return word(s, 0)
    }

    /// Word `index` of a 0x-stripped ABI buffer as an `Int`.
    ///
    /// Returns nil when the value exceeds `Int` rather than truncating it: the
    /// numbers this file reads (an array length, a `uint40` expiry, a nonce)
    /// are all small by construction, so a huge word means the buffer is not
    /// what we think it is — and a silently wrapped length would size an
    /// allocation from garbage.
    static func word(_ body: String, _ index: Int) -> Int? {
        let start = index * 64
        guard body.count >= start + 64 else { return nil }
        let lo = body.index(body.startIndex, offsetBy: start)
        let hi = body.index(lo, offsetBy: 64)
        let w = body[lo..<hi]
        guard w.prefix(48).allSatisfy({ $0 == "0" }),
              let v = Int(w.suffix(16), radix: 16) else { return nil }
        return v
    }

    /// Word index of `registeredAt` in a `getKey` reply, and of the expiry
    /// that proves the layout. Both counted from the START of the returned
    /// buffer, i.e. including the leading struct offset word.
    ///
    /// Measured against four real keys on BNB (2026-08-18): word 5 held a
    /// plausible recent timestamp on every one, and word 7 equalled
    /// `getExpiry`'s answer BYTE FOR BYTE — 0 for each root key, the exact
    /// expiry for each session key.
    static let registeredAtWord = 5
    static let expiryWitnessWord = 7

    /// `registeredAt` out of a `getKey` reply — **only when the reply proves
    /// its own layout.**
    ///
    /// This is an INFERRED struct layout, and the failure mode of guessing one
    /// is a confident wrong date on a security screen: read a neighbouring
    /// word and a key registered last week renders as 1970, or as a date years
    /// out, and nothing about it looks broken. So the layout is not trusted,
    /// it is WITNESSED — word 7 must equal the expiry that `getExpiry`
    /// authoritatively returned for this same key. If the struct ever gains,
    /// loses or reorders a field, that witness stops matching and this returns
    /// nil, which costs a runway bar and a date. The room degrades; it never
    /// lies.
    ///
    /// `expectedExpiry` is seconds, 0 meaning "never" — the raw `getExpiry`
    /// value, not a `Date`, so the comparison is exact integer equality and
    /// cannot be blurred by any conversion on the way.
    static func registeredAt(fromGetKey hex: String, expectedExpiry: Int) -> Date? {
        var s = hex.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= (expiryWitnessWord + 1) * 64, s.allSatisfy(\.isHexDigit) else { return nil }
        guard let witness = word(s, expiryWitnessWord), witness == expectedExpiry else { return nil }
        guard let seconds = word(s, registeredAtWord), seconds > 0 else { return nil }
        // A registration older than the contract itself, or in the future, is
        // the right word read from a wrong buffer. Both refused.
        guard seconds >= earliestPlausibleRegistration else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// 2026-01-01. The keystore was deployed in 2026, so anything before this
    /// is not a registration date — it is a misread word wearing one.
    static let earliestPlausibleRegistration = 1_767_225_600

    /// A dynamic `bytes` return, as lowercase hex with no `0x`.
    ///
    /// Same single-return layout assumption as `decodeKeyIDs` — offset word
    /// must be 0x20 — and the same refusal rather than a re-base, for the same
    /// reason: key material read from the wrong offset is still 65 plausible
    /// bytes, and it would be tested against a curve and confidently named.
    static func decodeBytes(_ hex: String) -> String? {
        var s = hex.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count >= 128, s.allSatisfy(\.isHexDigit) else { return nil }
        guard let offset = word(s, 0), offset == 32, let length = word(s, 1),
              length > 0, length <= 256 else { return nil }
        let start = 128, need = length * 2
        guard s.count >= start + need else { return nil }
        let lo = s.index(s.startIndex, offsetBy: start)
        let hi = s.index(lo, offsetBy: need)
        return String(s[lo..<hi])
    }

    // MARK: - The model

    /// One registered credential.
    struct Key: Equatable, Identifiable {
        /// The 0x-prefixed bytes32 key id, lowercased.
        let id: String
        /// A ROOT credential (permanent authority over the account) rather
        /// than a scoped session key. The distinction is the most useful thing
        /// on the row, which is why it is read per key rather than inferred
        /// from whether an expiry is set.
        let isRoot: Bool
        /// nil means the key never expires — which is normal for a root key
        /// and notable for a session key.
        let expiry: Date?
        /// False when the key's nonce is still zero, i.e. it has been
        /// How many times this key has signed — the key's own nonce.
        ///
        /// Stored as the NUMBER rather than the old `hasEverSigned` boolean
        /// (prd §404). The call already returned it and this file was throwing
        /// the magnitude away: "signed 47 times" and "registered 62 days ago,
        /// never used" are very different credentials to be looking at, and
        /// only one of them can be said with a Bool. One source of truth —
        /// `hasEverSigned` is derived below rather than stored beside it.
        let signatureCount: Int

        /// The uncompressed public key (`04 || X || Y`), when it was read.
        /// Feeds `curve`, and nothing else — it is never displayed whole.
        var publicKey: String? = nil

        /// A credential that can act and never has, which is exactly what
        /// somebody auditing their own account wants separated from one in
        /// daily use.
        var hasEverSigned: Bool { signatureCount > 0 }

        /// What KIND of credential this is, computed from the key material
        /// itself. `.unknown` whenever the point satisfies neither curve, and
        /// the copy then says nothing.
        var curve: Curve {
            guard let publicKey else { return .unknown }
            return AltanaKeystore.curve(fromPublicKey: publicKey)
        }
        /// When the key was registered, read out of `getKey` and CROSS-CHECKED
        /// (see `registeredAt(fromGetKey:expectedExpiry:)`). nil whenever that
        /// check fails — the room then shows a key with no start, which costs
        /// a runway bar and never shows a wrong date.
        ///
        /// `var` with a default so the memberwise init keeps its old shape.
        var registeredAt: Date? = nil
        /// Which registry answered — "BNB Smart Chain" or "Ethereum". An
        /// account can hold keys on both, and a row that didn't say which
        /// would send someone to the wrong explorer.
        var chainLabel: String? = nil

        /// How long this grant was written for — the honest phrase "a 24-hour
        /// key", available only because both ends are readable. nil unless
        /// both are.
        var grantDuration: TimeInterval? {
            guard let registeredAt, let expiry, expiry > registeredAt else { return nil }
            return expiry.timeIntervalSince(registeredAt)
        }

        /// How far through its own grant this key is, 0…1 — the runway bar.
        ///
        /// It is a TRUE fraction, unlike `ASCRoom`'s runway, which had to gate
        /// on "a transition this device watched" because Apple publishes no
        /// start date. Here the chain publishes both ends, so every key gets a
        /// real bar on first sight, on every device, with nothing observed
        /// locally.
        func progress(now: Date) -> Double? {
            guard let registeredAt, let grantDuration, grantDuration > 0 else { return nil }
            let elapsed = now.timeIntervalSince(registeredAt)
            return min(1, max(0, elapsed / grantDuration))
        }

        /// The registry still lists this key as active, but its own expiry has
        /// passed — so it cannot act, whatever the list says. Measured real on
        /// BNB: two of six sampled session keys were in exactly this state.
        /// The hygiene reading nothing else surfaces.
        func isExpiredButListed(now: Date) -> Bool {
            guard let expiry else { return false }
            return expiry <= now
        }

        /// A session key past its expiry cannot act, whatever the registry
        /// still lists. Kept as a function of an injected `now` so the harness
        /// can test the boundary without waiting for one.
        func isUsable(now: Date) -> Bool {
            guard let expiry else { return true }
            return expiry > now
        }
    }

    /// Everything one address has registered.
    struct Reading: Equatable {
        /// Lowercased hex.
        let address: String
        /// Usable keys only — revoked and expired credentials are dropped by
        /// the reader, since the question is what can act NOW.
        let keys: [Key]
        /// Some of this account's keys were not read (see `maxKeys`). Stated
        /// so a capped reading can never be mistaken for a complete one.
        let truncated: Bool

        var rootCount: Int { keys.filter(\.isRoot).count }
        var sessionCount: Int { keys.count - rootCount }
        var isEmpty: Bool { keys.isEmpty && !truncated }
    }

    /// A TOTAL order: roots first, then soonest expiry, then key id.
    ///
    /// Total on purpose — a list that reshuffles between two reads of
    /// identical data reads as broken (the `ASCRoom` ruling). A key with no
    /// expiry sorts after one that has any, because a deadline is the thing
    /// worth seeing first among equals.
    static func sorted(_ keys: [Key]) -> [Key] {
        keys.sorted { a, b in
            if a.isRoot != b.isRoot { return a.isRoot }
            switch (a.expiry, b.expiry) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: break
            }
            return a.id < b.id
        }
    }

    // MARK: - What KIND of credential this is (prd §404)

    /// The curve a public key lies on — which is the most human-meaningful
    /// fact available about a credential, and the only one the registry
    /// publishes that a person already has a word for.
    ///
    /// A key is 65 bytes: `04 || X || Y`. Both curves below are defined by
    /// `y² = x³ + ax + b (mod p)`, so testing which equation the point
    /// satisfies IS the identification — no guessing, no metadata, no
    /// heuristics on length or prefix.
    ///
    /// **secp256k1 is what wallets sign with. P-256 is what WebAuthn
    /// passkeys and the Secure Enclave use.** Measured 2026-08-18 against the
    /// one real key on Ethereum: secp256k1, so the network's first credential
    /// is a wallet key rather than a passkey.
    ///
    /// `unknown` is a real answer and the copy says nothing rather than
    /// guessing — a point that satisfies neither equation is not a key we
    /// understand, and naming it anyway on a security screen is §83 at its
    /// most expensive.
    enum Curve: String, Equatable {
        case secp256k1, p256, unknown

        /// The word a person already knows. nil for `unknown`, which is what
        /// keeps the label honest — a row simply omits it.
        var label: String? {
            switch self {
            case .secp256k1: String(localized: "Wallet key")
            case .p256:      String(localized: "Passkey")
            case .unknown:   nil
            }
        }
    }

    private static let secp256k1P = "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f"
    private static let p256P      = "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff"
    private static let p256B      = "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b"

    /// Which curve this uncompressed public key lies on.
    ///
    /// Refuses anything that is not exactly `04` + 64 bytes of hex, and any
    /// coordinate at or above the field prime (a valid-looking point whose
    /// coordinates are out of range is not on the curve, whatever the equation
    /// says once reduced).
    static func curve(fromPublicKey hex: String) -> Curve {
        var s = hex.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count == 130, s.hasPrefix("04"), s.allSatisfy(\.isHexDigit) else { return .unknown }
        let x = BigU(hex: String(s.dropFirst(2).prefix(64)))
        let y = BigU(hex: String(s.suffix(64)))

        // secp256k1: y² = x³ + 7
        let p1 = BigU(hex: secp256k1P)
        if x < p1, y < p1 {
            let lhs = (y * y).mod(p1)
            let rhs = ((x * x).mod(p1) * x + BigU(7)).mod(p1)
            if lhs == rhs { return .secp256k1 }
        }
        // P-256: y² = x³ - 3x + b, written as x³ + (p-3)x + b so every term
        // stays unsigned.
        let p2 = BigU(hex: p256P)
        if x < p2, y < p2 {
            let a = p2 - BigU(3)
            let lhs = (y * y).mod(p2)
            let rhs = ((x * x).mod(p2) * x + (a * x).mod(p2) + BigU(hex: p256B)).mod(p2)
            if lhs == rhs { return .p256 }
        }
        return .unknown
    }

    /// A minimal unsigned big integer — just enough to test a point against a
    /// curve equation, and no more.
    ///
    /// Hand-rolled for the same reason `Keccak256` is: this file has to stay
    /// Foundation-only so the harness compiles it as shipped, and pulling in a
    /// dependency for six multiplications would trade that away. 32-bit limbs
    /// so every partial product fits a `UInt64` with no overflow handling, and
    /// modulo by binary long division because a few hundred shift-compare
    /// steps per key is free at this scale — this runs a handful of times per
    /// wallet, not in a loop.
    struct BigU: Equatable {
        /// Little-endian 32-bit limbs, no trailing zeros.
        private(set) var limbs: [UInt32]

        init(_ limbs: [UInt32]) { self.limbs = limbs; trim() }
        init(_ v: UInt32) { limbs = [v]; trim() }

        /// Big-endian hex, any length.
        init(hex: String) {
            var out: [UInt32] = []
            var chars = Array(hex)
            while !chars.isEmpty {
                let take = min(8, chars.count)
                let chunk = String(chars.suffix(take))
                chars.removeLast(take)
                out.append(UInt32(chunk, radix: 16) ?? 0)
            }
            limbs = out.isEmpty ? [0] : out
            trim()
        }

        private mutating func trim() {
            while limbs.count > 1, limbs.last == 0 { limbs.removeLast() }
            if limbs.isEmpty { limbs = [0] }
        }

        var isZero: Bool { limbs.count == 1 && limbs[0] == 0 }

        var bitWidth: Int {
            guard let top = limbs.last else { return 0 }
            return (limbs.count - 1) * 32 + (32 - top.leadingZeroBitCount)
        }

        func bit(_ i: Int) -> Bool {
            let limb = i / 32, off = i % 32
            guard limb < limbs.count else { return false }
            return (limbs[limb] >> UInt32(off)) & 1 == 1
        }

        static func < (a: BigU, b: BigU) -> Bool {
            if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count }
            for i in stride(from: a.limbs.count - 1, through: 0, by: -1) where a.limbs[i] != b.limbs[i] {
                return a.limbs[i] < b.limbs[i]
            }
            return false
        }

        static func + (a: BigU, b: BigU) -> BigU {
            var out: [UInt32] = []
            var carry: UInt64 = 0
            for i in 0..<max(a.limbs.count, b.limbs.count) {
                let sum = UInt64(i < a.limbs.count ? a.limbs[i] : 0)
                        + UInt64(i < b.limbs.count ? b.limbs[i] : 0) + carry
                out.append(UInt32(truncatingIfNeeded: sum))
                carry = sum >> 32
            }
            if carry > 0 { out.append(UInt32(carry)) }
            return BigU(out)
        }

        /// `a - b`, and the caller must know `a >= b` — this is only ever
        /// reached from the division loop and from `p - 3`, both of which do.
        static func - (a: BigU, b: BigU) -> BigU {
            var out: [UInt32] = []
            var borrow: Int64 = 0
            for i in 0..<a.limbs.count {
                var diff = Int64(a.limbs[i]) - Int64(i < b.limbs.count ? b.limbs[i] : 0) - borrow
                if diff < 0 { diff += 1 << 32; borrow = 1 } else { borrow = 0 }
                out.append(UInt32(diff))
            }
            return BigU(out)
        }

        static func * (a: BigU, b: BigU) -> BigU {
            var out = [UInt32](repeating: 0, count: a.limbs.count + b.limbs.count)
            for i in 0..<a.limbs.count {
                var carry: UInt64 = 0
                for j in 0..<b.limbs.count {
                    let cur = UInt64(out[i + j]) + UInt64(a.limbs[i]) * UInt64(b.limbs[j]) + carry
                    out[i + j] = UInt32(truncatingIfNeeded: cur)
                    carry = cur >> 32
                }
                var k = i + b.limbs.count
                while carry > 0 {
                    let cur = UInt64(out[k]) + carry
                    out[k] = UInt32(truncatingIfNeeded: cur)
                    carry = cur >> 32
                    k += 1
                }
            }
            return BigU(out)
        }

        /// Binary long division remainder.
        func mod(_ m: BigU) -> BigU {
            guard !m.isZero else { return self }
            if self < m { return self }
            var rem = BigU(0)
            for i in stride(from: bitWidth - 1, through: 0, by: -1) {
                // rem = rem * 2 + bit(i)
                rem = rem + rem
                if bit(i) { rem = rem + BigU(1) }
                if !(rem < m) { rem = rem - m }
            }
            return rem
        }
    }

    // MARK: - News

    /// Which key ids are NEW since the last pass.
    ///
    /// `previous == nil` is first sight and answers EMPTY — the Hyperliquid
    /// first-sight rule (§ Hyperliquid, 2026-07-30): watching a wallet that
    /// already holds three keys must not land three "a new key can sign as
    /// you" alarms describing registrations that happened long before anyone
    /// was watching. Only a key that appears WHILE we are watching is news,
    /// and then it is alarm-class — a credential added to your account that
    /// you did not add is the most valuable thing this read can say.
    ///
    /// Order follows `current`, so a caller reporting several keys reports
    /// them in the order the registry lists them rather than a set's.
    static func newlyAppeared(previous: [String]?, current: [String]) -> [String] {
        guard let previous else { return [] }
        let seen = Set(previous.map { $0.lowercased() })
        return current.filter { !seen.contains($0.lowercased()) }
    }

    /// Everything that CHANGED between two passes (prd §404).
    ///
    /// `newlyAppeared` above reports arrivals and nothing else, which left two
    /// events we can see and were not saying:
    ///
    /// - **A revocation.** A key vanishing from `getKeys` is the one lifecycle
    ///   event the registry publishes for free, and it was disappearing in
    ///   silence — the room could say a key arrived and never that one left.
    /// - **First use.** A nonce moving off zero means a credential that had
    ///   never signed just signed. On a root key that sat unused for months
    ///   that is the most specific thing this seat can ever say, and it costs
    ///   nothing: the nonce is already read for every key on every pass.
    ///
    /// First sight answers EMPTY, same rule and same reason as
    /// `newlyAppeared` — a wallet already holding keys must not report them
    /// all as arrivals, and a key that had already signed before we ever
    /// looked has no first use for us to witness.
    ///
    /// Order is deterministic: arrivals and first-uses follow the registry's
    /// own order, then revocations sorted by id. A `Set` would reorder these
    /// between runs and re-shuffle the rows a person just read.
    enum Change: Equatable {
        case added(String)
        case revoked(String)
        case firstUse(String)

        var keyID: String {
            switch self {
            case .added(let k), .revoked(let k), .firstUse(let k): k
            }
        }
    }

    static func changes(previous: [String: Int]?, current: [(id: String, nonce: Int)]) -> [Change] {
        guard let previous else { return [] }
        var before: [String: Int] = [:]
        for (k, v) in previous { before[k.lowercased()] = v }

        var out: [Change] = []
        var seen = Set<String>()
        for entry in current {
            let id = entry.id.lowercased()
            seen.insert(id)
            guard let was = before[id] else { out.append(.added(id)); continue }
            // A nonce can only climb, so a fall means we misread one of the
            // two — say nothing rather than announce a signature that didn't
            // happen.
            if was == 0, entry.nonce > 0 { out.append(.firstUse(id)) }
        }
        for id in before.keys.sorted() where !seen.contains(id) {
            out.append(.revoked(id))
        }
        return out
    }
}
