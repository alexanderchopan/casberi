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

    /// The L1 keystore, lowercased. One entry, because there is one source of
    /// truth by the design's own claim — the L2 caches are mirrors and this
    /// reads the original (see the type doc).
    ///
    /// Measured live 2026-08-18: deployed, answering, `owner()` set.
    static let network = "eth-mainnet"
    static let contract = "0xb70fda90c1d576ba8399946a0c10ecd9d9ea923b"

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
        /// registered and never used. Worth stating plainly: a credential that
        /// can act and never has is exactly what somebody auditing their own
        /// account wants separated from one in daily use.
        let hasEverSigned: Bool

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
}
