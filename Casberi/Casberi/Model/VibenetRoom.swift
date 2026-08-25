import Foundation

/// THE VIBENET ROOM — what a watched account's keystore state
/// looks like, for Base's experimental EIP-8130 devnet.
///
/// Everything here is LIVE STATE, never a landed `Thing`. A vibenet devnet
/// account has no story for the corpus — no news, nothing a screenshot would
/// reference, nothing worth searching for a week later — so unlike Peer or
/// Privacy Pools (whose watched-wallet rides land real events) this room
/// reads fresh every time it's asked, the `StripeRoom` balance /
/// `SafeSigner.Standing` shape: a number that changes constantly and is
/// composed on demand from `VibenetRead`, never persisted as a `Thing`.
///
/// Foundation-only by design, so `scripts/vibenet-selftest.sh` can compile it
/// WHOLE and unmodified — the strongest form of "the harness ran the shipped
/// logic". Nothing on this host can make a devnet account authorize an actor,
/// revoke one, or lock itself, so the harness is not the best proof this
/// composition is right, it is the ONLY one.

// MARK: - Scope

/// One actor's permission bits (`Scopes.sol`). A raw `UInt16` rather than an
/// `OptionSet`, so a bit this build has never heard of round-trips through
/// the type unharmed instead of being silently dropped by an `OptionSet`
/// whose `rawValue` only ever holds the cases it declares.
struct VibenetScope: Equatable, Codable {
    let raw: UInt16

    static let sender: UInt16       = 0x0001
    static let policy: UInt16       = 0x0002
    static let nonce: UInt16        = 0x0004
    static let selfPayer: UInt16    = 0x0008
    static let sponsorPayer: UInt16 = 0x0010

    /// Every bit this build can name. Bits 0x0020…0x8000 are reserved by
    /// `Scopes.sol` for a future scope — real, and none of this app's
    /// business to guess a name for.
    static let known: UInt16 = sender | policy | nonce | selfPayer | sponsorPayer

    /// Named bits, in `Scopes.sol`'s own declared order — never alphabetical,
    /// so "Sender, Policy, Nonce" reads as the contract's own list rather
    /// than one this file happened to sort.
    ///
    /// TWO NAMES PER BIT, and the split is the point. `label` is the
    /// contract's own constant name, which is right in a probe dump a
    /// developer reads beside the spec. `plain` is what the bit MEANS, which
    /// is the only thing that belongs on screen: "Sender" / "Policy" /
    /// "Nonce" are EIP-8130 internals, and a card spelling them out in full
    /// is still asking someone to know the spec to read their own account.
    /// "Policy" in particular is actively misleading — it does not grant a
    /// policy, it RESTRICTS sending to one.
    ///
    /// FOUR OF THE FIVE PLAIN NAMES ARE THE SPEC'S OWN WORDS, and the fifth
    /// is ours — worth knowing before anyone "improves" one. EIP-8130 defines
    /// SENDER as "may originate transactions to any `call.to`" (hence "Send
    /// anywhere", which names the DESTINATION axis so it can never be read as
    /// "unrestricted" — see `isAdmin`), POLICY as "may call exactly one
    /// target: its configured `manager`", SELF_PAYER as "paying the account's
    /// own gas when `payer == sender`", and SPONSOR_PAYER as acting "as
    /// `payer_auth` for a different sender". NONCE is the invented one: the
    /// spec defines only the mechanism — a restricted actor may use sequenced
    /// `nonce_key`s rather than being confined to nonce-free mode — and
    /// offers no plain phrasing, so "Send in order" is this app's reading of
    /// it and is the one label here open to a better ruling.
    private static let named: [(bit: UInt16, label: String, plain: String)] = [
        (sender,       "Sender",        "Send anywhere"),
        (policy,       "Policy",        "Send to one contract"),
        (nonce,        "Nonce",         "Send in order"),
        (selfPayer,    "Self-payer",    "Pay own gas"),
        (sponsorPayer, "Sponsor-payer", "Pay others' gas"),
    ]

    /// SCOPE ZERO IS UNRESTRICTED, NOT EMPTY (prd §463) — the spec is explicit: "A value
    /// of `0x00` means unrestricted (admin), while non-zero values grant only
    /// specific contexts." This file shipped believing the opposite, calling
    /// zero "No scope" / "No permissions" and describing it as "an actor that
    /// can originate nothing yet", which displayed a key holding TOTAL
    /// authority as one holding none — the §83 fake status in the direction
    /// that matters most, on the one screen someone reads to find out who can
    /// spend their account. `grantedCount` made it worse by ranking such a key
    /// LAST, so `byReach` — whose whole job was to surface the most-privileged
    /// key first — surfaced it last instead. That ordering is gone now (see
    /// `alphabetical`); what survives is this flag and the inverted chip it
    /// drives, which says "total authority" without reordering anything.
    ///
    /// An admin is deliberately NOT rendered as all five bits set: it holds
    /// every capability INCLUDING the reserved ones this build cannot name,
    /// so listing five would understate it. It gets one word of its own.
    var isAdmin: Bool { raw == 0 }

    /// The named bits paired with their plain wording, in the contract's own
    /// declared order — the one list anything counting BY PERMISSION walks,
    /// so a room card and a key row can never disagree about either the
    /// wording or the order.
    static var orderedPlainBits: [(UInt16, String)] {
        named.map { ($0.bit, $0.plain) }
    }

    var names: [String] {
        guard !isAdmin else { return [String(localized: "Admin")] }
        return VibenetScope.named.filter { raw & $0.bit != 0 }.map(\.label)
    }

    /// The granted bits in PLAIN words — `plainSummary`'s comma-joined
    /// sentence and `grantedPlainLabels`' separate chips (R3.1) both read
    /// off this one list, so the two forms of this card never teach two
    /// different names for one permission.
    var plainNames: [String] {
        guard !isAdmin else { return [String(localized: "Admin")] }
        return VibenetScope.named.filter { raw & $0.bit != 0 }.map(\.plain)
    }

    /// R3.1 — the granted permissions as SEPARATE chip labels: `plainNames`
    /// plus one trailing "+N unknown" element when a reserved bit is set
    /// (never an invented name for it, §83).
    ///
    /// NEVER EMPTY, and that is a consequence of `isAdmin` rather than a
    /// coincidence worth relying on loosely: a scope with no bits set is an
    /// admin and yields `["Admin"]`, and any non-zero scope sets at least one
    /// bit, which is either named or counted. The caller therefore needs no
    /// empty-chip-row branch — the one it used to carry said "Can't act on
    /// its own yet", which was the inverted reading of scope 0.
    var grantedPlainLabels: [String] {
        var parts = plainNames
        if unknownCount > 0 {
            parts.append(unknownCount == 1
                ? String(localized: "+1 unknown")
                : String(localized: "+\(unknownCount) unknown"))
        }
        return parts
    }

    /// "Send anywhere, Pay own gas" / "Send anywhere, +1 unknown" /
    /// "Admin — no restrictions". There is no empty case: a scope with no
    /// bits set is an admin, and every non-zero scope names at least one bit
    /// or counts an unknown one.
    var plainSummary: String {
        guard !isAdmin else { return String(localized: "Admin — no restrictions") }
        var parts = plainNames
        if unknownCount > 0 {
            parts.append(unknownCount == 1
                ? String(localized: "+1 unknown")
                : String(localized: "+\(unknownCount) unknown"))
        }
        return parts.joined(separator: ", ")
    }

    /// Set bits past `known` — counted, never named. Inventing a name for a
    /// reserved bit is exactly the fake status §83 bans; a count is the
    /// honest ceiling of what this build actually knows.
    var unknownCount: Int {
        (raw & ~VibenetScope.known).nonzeroBitCount
    }

    /// "Sender, Self-payer" / "Sender, Self-payer +1 more" / "+2 unknown" /
    /// "Admin (unrestricted)" — the developer-facing form, in the contract's
    /// own constant names, which is what a probe dump should print beside the
    /// spec.
    var summary: String {
        guard !isAdmin else { return String(localized: "Admin (unrestricted)") }
        var parts = names
        if unknownCount > 0 {
            parts.append(unknownCount == 1
                ? String(localized: "+1 unknown")
                : String(localized: "+\(unknownCount) unknown"))
        }
        return parts.joined(separator: ", ")
    }

    /// How many powers this key holds in total — named bits PLUS reserved
    /// ones, because a bit this build can't name is still a power the key
    /// carries. Deliberately counts the BITS ONLY: an admin holds every
    /// capability there is, which is not a number this can express, so
    /// ranking asks `reach` instead and this stays the plain bit tally.
    var grantedCount: Int {
        guard !isAdmin else { return 0 }
        return VibenetScope.named.filter { raw & $0.bit != 0 }.count + unknownCount
    }

}

// MARK: - Authenticator identity

/// The three DYNAMIC authenticator addresses `VibenetAuthenticatorKind
/// .identify` compares against — carried as plain data rather than the live
/// config type itself, so this pure file needs no dependency on the network
/// layer and the harness can hand it a fixture instead of a real payload.
///
/// **NEVER a literal in this file.** vibenet is an ephemeral devnet whose
/// contracts get redeployed every few days (`docs` — three redeploys in
/// three days on the sibling Sepolia network); these three addresses come
/// from `VibenetConfig`'s live fetch of `api.vibes.base.org` and change
/// out from under any build that hardcodes them. The one address this file
/// MAY hardcode is `K1_AUTHENTICATOR` (`address(1)`), because `Keystore.sol`
/// itself declares it a fixed constant, the same on every chain, never
/// rotated with the rest of the deployment.
struct VibenetKnownAuthenticators: Equatable {
    let p256: String
    let webAuthn: String
    let delegate: String
}

/// The Keystore contracts a policy manager might BE, so a gated key can name
/// what it is gated to instead of printing hex at somebody (prd §463).
///
/// MEASURED, not assumed: every policy-gated key on vibenet on 2026-08-24 —
/// 7 of the 34 live actors sampled — named the same manager, and it is
/// exactly the config's own `PolicyManager`. Both addresses were already
/// parsed by `VibenetConfig` and read by nothing.
struct VibenetKnownPolicyManagers: Equatable {
    let policyManager: String?
    let sessionPolicy: String?

    /// The manager's name, or nil when it is a contract this build cannot
    /// name — the caller shows the short address then, never an invented
    /// label (§83).
    func name(for address: String) -> String? {
        func same(_ a: String?) -> Bool {
            guard let a else { return false }
            return a.caseInsensitiveCompare(address) == .orderedSame
        }
        if same(policyManager) { return String(localized: "the policy manager") }
        if same(sessionPolicy) { return String(localized: "the session policy") }
        return nil
    }
}

/// Which of the Keystore's named authenticators an actor's key is, or a
/// custom one this build doesn't recognize. `Hashable` so `actorSummary`
/// can group a roster by kind without a hand-rolled key.
enum VibenetAuthenticatorKind: String, Equatable, Hashable, CaseIterable, Codable {
    case secp256k1
    case p256
    case webAuthn
    case delegate
    /// An authenticator address that matches none of the four known ones —
    /// never guessed at further than this.
    case custom

    var label: String {
        switch self {
        case .secp256k1: String(localized: "secp256k1 key")
        case .p256:      String(localized: "P-256 key")
        case .webAuthn:  String(localized: "Passkey")
        case .delegate:  String(localized: "Delegate")
        case .custom:    String(localized: "Custom authenticator")
        }
    }

    /// What a person calls this, not what the spec calls it — the
    /// single-key sentence's own title. Each line is the WHOLE claim this
    /// build is willing to make; nothing here is embellished past what the
    /// chain itself proves.
    var plainTitle: String {
        switch self {
        case .secp256k1: String(localized: "Wallet key")
        case .p256:      String(localized: "P-256 key")
        case .webAuthn:  String(localized: "Passkey")
        case .delegate:  String(localized: "Another contract")
        case .custom:    String(localized: "Custom authenticator")
        }
    }

    /// The technical name plus one honest clause — nil where there is
    /// nothing certain to add. `.p256` names the CURVE only, never where a
    /// particular key happens to live (a passkey and a raw P-256 key are
    /// both possible and this build cannot tell them apart).
    var plainDetail: String? {
        switch self {
        case .secp256k1: String(localized: "secp256k1 — the standard Ethereum key")
        case .p256:      String(localized: "the curve passkeys and secure enclaves use")
        case .webAuthn:  String(localized: "Face ID, Touch ID, or a security key — WebAuthn")
        case .delegate:  String(localized: "a contract signs for this account")
        case .custom:    nil
        }
    }

    /// `label` without its "key"/"authenticator" suffix — for a legend cell
    /// narrow enough that the full label would wrap mid-word. Never used
    /// where there's room for the real label (the grid, the row summary);
    /// the kind strip is the one place five of these sit shoulder to
    /// shoulder in a fixed width.
    var shortLabel: String {
        switch self {
        case .secp256k1: "secp256k1"
        case .p256:      "P-256"
        case .webAuthn:  String(localized: "Passkey")
        case .delegate:  String(localized: "Delegate")
        case .custom:    String(localized: "Custom")
        }
    }

    /// A per-kind mark so an actor roster reads at a glance — "this account
    /// has a passkey and a key" — rather than only through four label rows
    /// of near-identical text. `.custom` gets a question mark on purpose:
    /// an authenticator this build can't identify earns no invented icon
    /// any more than it earns an invented name.
    var symbolName: String {
        switch self {
        case .secp256k1: "key.fill"
        case .p256:      "key.horizontal.fill"
        case .webAuthn:  "faceid"
        case .delegate:  "link"
        case .custom:    "questionmark.circle"
        }
    }

    /// A stable order for the roster to sort by — the Keystore's own
    /// declaration order (K1, then the three named contracts, unknown
    /// last), never alphabetical on the localized label.
    var sortRank: Int {
        switch self {
        case .secp256k1: 0
        case .p256:       1
        case .webAuthn:   2
        case .delegate:   3
        case .custom:     4
        }
    }

    /// `Keystore.sol`'s own fixed constant, `address(1)` — see the doc on
    /// `VibenetKnownAuthenticators` for why this is the one address this
    /// file may hardcode.
    static let k1Address = "0x0000000000000000000000000000000000000001"

    /// The zero address — what a revoked (or never-real) actor's
    /// authenticator reads back as. Not a KIND (a caller filters these out
    /// before they ever reach `identify`), but named here so both halves of
    /// this file agree on the one literal address either of them may use.
    static let zeroAddress = "0x0000000000000000000000000000000000000000"

    /// Compared case-insensitively — an RPC response's hex casing is not a
    /// promise, and a live-fetched address must match its own lowercase
    /// self just as reliably as a checksummed one.
    static func identify(authenticator: String,
                          known: VibenetKnownAuthenticators) -> VibenetAuthenticatorKind {
        let a = authenticator.lowercased()
        if a == k1Address { return .secp256k1 }
        if a == known.p256.lowercased() { return .p256 }
        if a == known.webAuthn.lowercased() { return .webAuthn }
        if a == known.delegate.lowercased() { return .delegate }
        return .custom
    }
}

// MARK: - actorId, and what it actually identifies (MEASURED 2026-08-24)

/// `ActorId.fromAddress(addr)` is `bytes32(uint256(uint160(addr)))` — an
/// address right-aligned into a 32-byte word, so the low 20 bytes are the
/// address and the high 12 are zero. That one line of `ActorId.sol` is the
/// key to two facts this feature had wrong from the day it shipped, both
/// found by decoding real `ActorAuthorized` logs off vibenet rather than by
/// reading Swift (chain height 328,220, 199 authorizations sampled):
///
/// **1. `authenticator` IS NOT THE KEY.** It is the CONTRACT that validates
/// the key. 127 of those 199 actors are secp256k1 and every single one
/// carries `authenticator == 0x…01` (`K1_AUTHENTICATOR`, `Keystore.sol`'s
/// own fixed constant) across 112 DISTINCT accounts — while only 118 of them
/// are distinct keys. So comparing authenticators to find a reused key
/// reports that every ordinary wallet key on every pair of watched accounts
/// is the same key. It is `actorId` that identifies a key, globally:
/// `Keystore` stores actors as `_actorConfig[actorId][account]`, so one
/// actorId appearing under two accounts is the same key authorized twice,
/// which is exactly the fact `VibenetKeyReuse` exists to state.
///
/// **2. A DELEGATE'S TARGET IS IN ITS actorId, NOT ITS authenticator.**
/// `DelegateAuthenticator.authenticate` returns
/// `actorId = ActorId.fromAddress(delegate)`, and the actor's authenticator
/// is the DelegateAuthenticator CONTRACT — the same address for every
/// delegate on the chain (all 5 live ones read `0x8130b7d4…`). So a mapping
/// that compared an authenticator against another account's address could
/// never match on a live read, however many delegate relationships really
/// existed.
///
/// Both bugs rendered perfectly and both were invisible to the harness,
/// because the demo fixture hand-set values the chain does not produce — a
/// fixture only tests the rule it names if it FAILS that rule and passes
/// every other one, and these fixtures failed a rule vibenet never applies.
enum VibenetActorId {
    /// The address an address-derived actorId names, or nil when the id is
    /// not address-shaped (a P-256/WebAuthn key's id is a hash of its public
    /// key, which has no address inside it and must never be read as one).
    ///
    /// The high-12-bytes-are-zero test is the WHOLE check and it is not
    /// merely a sanity guard: without it every 32-byte hash yields a
    /// plausible-looking 20-byte "address" that belongs to nobody, and this
    /// value is compared against real watched addresses.
    static func address(fromActorId actorId: String) -> String? {
        var s = actorId.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count == 64, s.allSatisfy(\.isHexDigit) else { return nil }
        guard s.prefix(24).allSatisfy({ $0 == "0" }) else { return nil }
        let tail = String(s.suffix(40))
        // All-zero is the zero address, never a real account.
        guard tail.contains(where: { $0 != "0" }) else { return nil }
        return "0x" + tail
    }

    /// The reverse — an address as the 32-byte actorId word that
    /// `ActorId.fromAddress` would produce, which is what an indexed
    /// `eth_getLogs` topic filter needs to ask "who named this address as
    /// their delegate".
    static func actorId(forAddress address: String) -> String? {
        var s = address.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count == 40, s.allSatisfy(\.isHexDigit) else { return nil }
        return "0x" + String(repeating: "0", count: 24) + s
    }
}

/// A candidate for the empty state's "recently created on vibenet" list —
/// a real address off `AccountCreated`, never a demo prop. `createdAt` is
/// nil on a failed block-time lookup and is OMITTED by the view rather than
/// guessed — the same discipline `VibenetActor.expiry` uses for its own
/// clock fact.
struct VibenetDiscoveredAccount: Identifiable, Equatable {
    var id: String { address }
    let address: String
    let createdAt: Date?
}

// MARK: - The actor log union

/// One `ActorAuthorized`/`ActorRevoked` event off the Keystore's log stream
/// — the pure shape `VibenetRead.actorIDs` reduces a raw `eth_getLogs`
/// response to, so the union arithmetic below can be harness-tested with no
/// network in sight.
struct VibenetActorEvent: Equatable {
    let actorId: String
    let authorized: Bool
    let block: Int
    let logIndex: Int
}

enum VibenetActorLog {
    /// Which actorIds are LIVE after every authorization/revocation event
    /// for an account, order-independent in the input.
    ///
    /// Sorted chronologically (block, then log index within a block) and
    /// reduced to the LATEST event per actorId — last-write-wins. That is
    /// the whole rule, and it is the one that makes a revoked-then-
    /// reauthorized actorId read as live again: an id whose most recent
    /// event is a revocation is dropped, and one whose most recent event is
    /// an authorization survives, however many times it flipped before
    /// that. `scripts/vibenet-selftest.sh` mutation-proves both halves —
    /// an authorize-then-revoke sequence must NOT survive, and a
    /// revoke-then-reauthorize sequence MUST.
    static func survivors(_ events: [VibenetActorEvent]) -> Set<String> {
        let chronological = events.sorted { ($0.block, $0.logIndex) < ($1.block, $1.logIndex) }
        var latest: [String: Bool] = [:]
        for e in chronological { latest[e.actorId] = e.authorized }
        return Set(latest.filter(\.value).map(\.key))
    }
}

// MARK: - Chunked eth_getLogs walk (measured 2026-08-23)

/// The block ranges `VibenetChain.getLogs` walks — pulled out as pure
/// arithmetic so the boundary math (no gaps, no overlaps, the genesis
/// stop, the chunk-count circuit breaker) is harness-tested rather than
/// trusted to a live devnet read, the same reason every other piece of
/// address/permission arithmetic in this file has a pure core.
///
/// THE BUG THIS EXISTS TO PREVENT: the RPC enforces a 100,000-block
/// ceiling on `eth_getLogs` (measured, "query exceeds max block range
/// 100000") and this file originally read from block 0 unbounded — fine
/// while the devnet was young, silently broken the moment its height
/// passed that ceiling (285,133 the day this was measured). The failure
/// mode was invisible: the RPC's error response has no `"result"` field,
/// so `VibenetChain.call` correctly reads it as nil, and every caller of
/// `getLogs` already treats nil as "unreached" — so a genuinely
/// established account read as "not established yet" and the empty-state
/// discovery read as nothing found, both from the SAME call failing the
/// SAME way, with no error surfaced anywhere a person could see it.
enum VibenetLogChunking {
    /// TIP-BACKWARD, never forward: if the chunk-count breaker below is
    /// ever hit, the history dropped is the OLDEST, not the newest — a
    /// just-authorized key must always be inside the walked window, even
    /// on a devnet that outgrows every bound this file sets today.
    static func ranges(tip: Int, maxRange: Int, maxChunks: Int) -> [(from: Int, to: Int)] {
        guard tip >= 0, maxRange > 0, maxChunks > 0 else { return [] }
        var out: [(from: Int, to: Int)] = []
        var to = tip
        var chunk = 0
        while to >= 0, chunk < maxChunks {
            let from = max(0, to - maxRange + 1)
            out.append((from, to))
            // An early exit, not a correctness guard — `to = from - 1`
            // when `from == 0` sets `to = -1`, and the loop's own
            // `to >= 0` catches that on the NEXT check regardless, with no
            // further append either way. Kept only to avoid one wasted
            // iteration; removing it changes no output, which is why no
            // mutation here would be catchable (checked before shipping).
            if from == 0 { break }
            to = from - 1
            chunk += 1
        }
        return out
    }
}

// MARK: - The key history strip (R2.1)

/// One moment in an account's own story — a key added or a key revoked,
/// off the SAME `ActorAuthorized`/`ActorRevoked` events `VibenetActorLog
/// .survivors` already reduces to a live roster. Order is EXACT (block,
/// then logIndex); `date` is a best-effort clock label and may be nil.
struct VibenetKeyMoment: Identifiable, Equatable, Codable {
    var id: String { "\(block):\(logIndex):\(authorized)" }
    let block: Int
    let logIndex: Int
    let authorized: Bool
    /// nil for a revoked actor (its kind at the moment of revocation isn't
    /// re-derivable without an archive node — never guessed) and for any
    /// authorized actor this build's current read can no longer confirm.
    let kind: VibenetAuthenticatorKind?
    /// nil on a failed block-time lookup — the moment still draws (its
    /// ORDER is exact regardless) but can never be an endpoint label.
    let date: Date?
}

/// The strip's own arithmetic — a SEQUENCE, deliberately not a time-
/// proportional axis. Order is exact; a degenerate span (several events in
/// one block) has no honest layout on a real clock, so positions are drawn
/// evenly spaced and only the two endpoint labels carry actual dates.
enum VibenetKeyHistory {
    /// The most recent moments a card will ever draw — bounding the block-
    /// time lookups `account(_:contracts:)` pays for one per distinct block.
    static let cap = 10

    /// TOTAL order (block, then logIndex, then a stable authorized/revoked
    /// tiebreak) — a second pass over the same set must agree with the
    /// first, or the strip reshuffles between opens over an unchanged
    /// history.
    static func ordered(_ moments: [VibenetKeyMoment]) -> [VibenetKeyMoment] {
        moments.sorted {
            if $0.block != $1.block { return $0.block < $1.block }
            if $0.logIndex != $1.logIndex { return $0.logIndex < $1.logIndex }
            return $0.authorized && !$1.authorized
        }
    }

    /// The newest `cap` events, chronologically ordered — applied to the
    /// RAW event log before block-time resolution, so a bounded read never
    /// pays for a block time it won't draw.
    static func newest(_ events: [VibenetActorEvent], cap: Int = VibenetKeyHistory.cap) -> [VibenetActorEvent] {
        let chronological = events.sorted { ($0.block, $0.logIndex) < ($1.block, $1.logIndex) }
        return Array(chronological.suffix(cap))
    }

    /// Whether these moments are a real SEQUENCE — i.e. they happened at
    /// more than one moment in time. Two keys authorized in the SAME
    /// transaction share a block and a timestamp, so drawing them as two
    /// dots side by side claims an order that does not exist: nothing
    /// happened before anything else, and the reader is invited to infer
    /// a story from a picture of one. (Measured on the live devnet: an
    /// account created with a wallet key and a passkey lands both in
    /// block 204532, log index 0 and 1.) The dots draw only when this is
    /// true; otherwise the summary sentence and its one date say the
    /// whole of it, which is all there is to say.
    static func isSequence(_ moments: [VibenetKeyMoment]) -> Bool {
        Set(moments.map(\.block)).count > 1
    }

    /// "3 keys added · 1 revoked" — each half omitted at zero; both zero
    /// yields nil, and the strip doesn't draw at all (there is nothing to
    /// summarize).
    static func summaryLine(_ moments: [VibenetKeyMoment]) -> String? {
        let added = moments.filter(\.authorized).count
        let revoked = moments.count - added
        var parts: [String] = []
        if added > 0 {
            parts.append(added == 1 ? String(localized: "1 key added") : String(localized: "\(added) keys added"))
        }
        if revoked > 0 {
            parts.append(revoked == 1 ? String(localized: "1 revoked") : String(localized: "\(revoked) revoked"))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// (oldest, newest) short date labels off `ordered` moments — nil for
    /// an endpoint whose own `date` is nil (never guessed), and the newest
    /// label collapses to nil when it would just repeat the oldest one.
    static func endpointLabels(_ moments: [VibenetKeyMoment], now: Date) -> (oldest: String?, newest: String?) {
        guard let first = moments.first, let last = moments.last else { return (nil, nil) }
        func label(_ date: Date?) -> String? {
            guard let date else { return nil }
            let days = now.timeIntervalSince(date) / 86_400
            if days >= 0, days < 30 { return date.formatted(.relative(presentation: .named)) }
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        let oldest = label(first.date)
        var newest = label(last.date)
        if newest == oldest { newest = nil }
        return (oldest, newest)
    }
}

// MARK: - One actor, one account

struct VibenetActor: Identifiable, Equatable, Codable {
    var id: String { actorId }
    let actorId: String
    let authenticator: String
    let kind: VibenetAuthenticatorKind
    let scope: VibenetScope
    /// Unix seconds; 0 is `Keystore.sol`'s own convention for "no expiry
    /// set", never a date. This file states the raw fact and does no clock
    /// arithmetic on it — the caller decides whether to compare it to "now",
    /// so nothing here can quietly disagree with what time the view drew at.
    let expiry: UInt64
    /// The ONE contract a policy-gated key may call — `Keystore.sol`'s
    /// `getPolicyManager`, read only for keys whose POLICY bit is set and nil
    /// for every other key (prd §463). "Send to one contract" states the
    /// restriction and could never say WHICH contract, which is the half that
    /// makes the restriction meaningful: gated to a session policy you
    /// recognise is a different fact from gated to something you don't.
    ///
    /// OPTIONAL, and that is load-bearing rather than tidy: this type is
    /// `Codable` and persisted in `VibenetState`'s snapshot, and Swift
    /// synthesises `decodeIfPresent` for an Optional, so every snapshot
    /// already on a device decodes with this as nil. A non-optional field
    /// would fail the decode of the whole room — the `RSSStore.Feed` trap
    /// this codebase has paid for twice.
    var policyManager: String?
    /// `Keystore.getPolicyCommitment` — the hash of the policy configuration
    /// this key is bound to, read in the SAME call as `policyManager`
    /// (`getActorWithPolicy`) and nil for every ungated key. Optional for the
    /// `policyManager` reason: this type is persisted in `VibenetState`'s
    /// snapshot, and Swift synthesises `decodeIfPresent` for an Optional, so
    /// every snapshot already on a device decodes with this as nil.
    ///
    /// **IT IS AN IDENTIFIER, NEVER A READING**, and that distinction is this
    /// field's whole reason to be careful: the commitment is what
    /// `PolicyManager` emits on every execution (`PolicyExecuted`'s third
    /// indexed topic), so it is the join that lets a session key say how many
    /// times it has actually been used. It is NOT the policy, and the policy
    /// itself is not on chain at all — see `VibenetPolicyReadability`.
    var policyCommitment: String?

    /// The ACCOUNT a delegate actor delegates to — decoded from `actorId`,
    /// which is where `DelegateAuthenticator` puts it (see `VibenetActorId`
    /// for the measurement). nil for every non-delegate actor, and nil for a
    /// delegate whose id is somehow not address-shaped, which the chain
    /// should never produce but which must not be guessed at if it does.
    var delegateAddress: String? {
        guard kind == .delegate else { return nil }
        return VibenetActorId.address(fromActorId: actorId)
    }

    /// "Never expires" / "Expired Mar 3" / "Expires in 3h" — this key's own
    /// clock, read and then thrown away by every screen this feature has
    /// shipped so far even though `expiry` was fetched from the very first
    /// commit. Takes `now` as a PARAMETER rather than reading `Date.now`
    /// itself, the same discipline `BriefLedger`/`AppVisit` use for anything
    /// clock-dependent — a harness fixture can then assert an exact
    /// three-way boundary (never / expired / counting down) without being
    /// at the mercy of when the test happens to run.
    func expiryLabel(now: Date) -> String {
        guard expiry > 0 else { return String(localized: "Never expires") }
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(expiry))
        guard expiresAt > now else {
            return String(localized: "Expired \(expiresAt.formatted(.dateTime.month(.abbreviated).day()))")
        }
        return String(localized: "Expires \(expiresAt.formatted(.relative(presentation: .named)))")
    }

    /// WHICH contract a gated key may call — the half "Send to one contract"
    /// could never say (prd §463). Named when the config recognises it, short
    /// address otherwise, and nil when the key is not gated at all or the
    /// manager did not read: a gated key that cannot name its target still
    /// says it is gated, via its chip, rather than being handed a guess.
    func policyLine(known: VibenetKnownPolicyManagers) -> String? {
        guard scope.raw & VibenetScope.policy != 0, let manager = policyManager else { return nil }
        if let name = known.name(for: manager) {
            return String(localized: "Limited to \(name)")
        }
        return String(localized: "Limited to \(VibenetRoom.shortAddress(manager))")
    }

    /// What weight a key's expiry has earned on screen. The label alone
    /// could not say this: "Expires in 3 days" and "Never expires" are the
    /// same sentence shape, so drawn in one ink they read as equally
    /// unremarkable, which is how a key three days from lapsing sat in
    /// `textTertiary` at the bottom of its own row. The row asks this and
    /// draws accordingly — and a key that never expires still SAYS so, since
    /// nothing printed under a heading about expiry reads as unknown rather
    /// than as never.
    enum ExpiryStanding {
        /// Keystore's own "never" — `expiry == 0`, a fact, drawn quietly.
        case never
        /// Already lapsed: a standing fact, not a clock.
        case expired
        /// Ticking inside `VibenetAccountItem.urgencyWindow`.
        case soon
        /// Dated, but far enough out to be ordinary.
        case later
    }

    func expiryStanding(now: Date) -> ExpiryStanding {
        guard expiry > 0 else { return .never }
        let at = TimeInterval(expiry)
        guard at > now.timeIntervalSince1970 else { return .expired }
        return at - now.timeIntervalSince1970 <= VibenetAccountItem.urgencyWindow ? .soon : .later
    }
}

/// One ERC-20-shaped balance a vibenet account holds — USDV or NFV today,
/// whichever the live config named a contract for. A named struct rather
/// than a tuple so `VibenetAccountItem` stays `Codable` (Codable doesn't
/// synthesize for tuples, the same reason `VibenetKeyKindCount` exists
/// above). `symbol` is the config's OWN field name, uppercased — never a
/// live `symbol()` read, because the field naming ("usdv"/"nfv") already
/// states the identity for free, and a second `eth_call` per account per
/// pass to confirm what the config already told us would be spent for
/// nothing.
struct VibenetTokenBalance: Equatable, Codable {
    let symbol: String
    let amount: Double
}

/// A raw chain balance, rounded to a readable number of decimals — NEVER
/// currency-formatted (§83): these are devnet tokens with no real market
/// price, so a `$` sign or a thousands-grouped figure here would be
/// exactly the fake status this codebase's honesty rule exists to ban.
/// Four decimal places, trailing zeros trimmed — enough precision to
/// separate "some" from "dust" on a devnet without printing eighteen
/// digits nobody reads.
enum VibenetBalanceFormat {
    /// A fraction as a percentage — "6.0%" — never signed, because the arrow
    /// beside it carries the direction and printing both says it twice.
    static func percent(_ change: Double) -> String {
        String(format: "%.1f%%", abs(change) * 100)
    }

    static func line(_ amount: Double) -> String {
        guard amount.isFinite else { return "0" }
        let rounded = (amount * 10_000).rounded() / 10_000
        var s = String(format: "%.4f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

struct VibenetAccountItem: Identifiable, Equatable, Codable {
    var id: String { address }
    let address: String
    /// Whether THIS read reached the chain at all. A chain that never
    /// answered and an account that genuinely holds nothing render as the
    /// same "nothing to show" unless this is carried apart from
    /// `established`.
    let reached: Bool
    let established: Bool
    /// The surviving actor roster: authorized, not later revoked, and
    /// re-confirmed live via `getActorConfig` (see `VibenetRoom`'s own doc
    /// for why the log union alone isn't authoritative). Empty on an
    /// account that IS established but authorized nothing this build can
    /// see — a real state, distinct from `established == false`.
    let actors: [VibenetActor]
    let locked: Bool
    let hasInitiatedUnlock: Bool
    let unlocksAt: UInt64?
    let unlockDelay: UInt16?
    /// This ONE chain's change-sequence standing (`getChangeSequences`) —
    /// `nil` when the read wasn't attempted or failed, never a zeroed
    /// struct standing in for "unknown". See `VibenetMultichainSync` for
    /// what this becomes once more than one chain can hold this account;
    /// today it's the whole of "what has this account done, on the one
    /// chain 8130 actually runs on".
    let changeSequences: VibenetChangeSequences?
    /// The account's own story — every `ActorAuthorized`/`ActorRevoked`
    /// moment `actorEvents` already fetched to compute `actors`, bounded to
    /// `VibenetKeyHistory.cap` and pre-ordered by `VibenetKeyHistory
    /// .ordered`. Empty when the read failed or nothing has ever happened,
    /// same shape as `actors` — never a signal of its own.
    let history: [VibenetKeyMoment]
    /// This account's native (vibenet ETH-equivalent) balance — nil when
    /// the `eth_getBalance` read failed, NEVER a guessed zero (§83): a
    /// genuine zero balance and an unreached read must not look the same
    /// to a caller deciding whether to trust this number. Always 18
    /// decimals (an EVM-wide constant for the native asset, the one
    /// balance in this feature safe to scale without a live `decimals()`
    /// read first — see `VibenetRead.account`'s own doc).
    let nativeBalance: Double?
    /// USDV/NFV balances — one entry per token the live config named a
    /// contract for AND whose `decimals()` this build could confirm.
    /// A token whose decimals read failed is simply ABSENT from this
    /// array rather than present with an invented scale (the standing
    /// lesson this codebase has paid for twice already: Solana SPL,
    /// Gnosis Pay's USDCe being 6 not 18). Never summed across symbols —
    /// they're different assets with no shared unit, the `PrivacyPoolsRoom`
    /// rule.
    let tokenBalances: [VibenetTokenBalance]
    /// Every `PolicyExecuted` this account has emitted, folded per
    /// commitment — joined to a gated key by `policyCommitment`. Empty when
    /// the account has no gated key, when the read failed, or when nothing
    /// has ever executed; a key's OWN zero is spoken ("Never used") off its
    /// commitment being absent from this list, which is why an empty array
    /// here is not itself a signal.
    let policyUses: [VibenetPolicyUse]
    /// Accounts that authorized THIS address as their delegate — Base's own
    /// "Sub-accounts". Empty when none, when the read failed, or when the
    /// address is not a delegate anywhere, which are not distinguished
    /// because none of them has anything to draw.
    let subAccounts: [VibenetSubAccount]

    /// The one alarm-worthy fact (the task's own ruling): a locked account.
    /// Deliberately NOT "not established" — an account that has never done
    /// anything isn't broken, it just hasn't been used yet.
    var alarmed: Bool { locked }

    init(address: String, reached: Bool, established: Bool, actors: [VibenetActor],
         locked: Bool, hasInitiatedUnlock: Bool, unlocksAt: UInt64?, unlockDelay: UInt16?,
         changeSequences: VibenetChangeSequences? = nil, history: [VibenetKeyMoment] = [],
         nativeBalance: Double? = nil, tokenBalances: [VibenetTokenBalance] = [],
         policyUses: [VibenetPolicyUse] = [], subAccounts: [VibenetSubAccount] = []) {
        self.address = address
        self.reached = reached
        self.established = established
        // Ordered here, once, at the boundary — every reader (the card, the
        // probe) sees the same deterministic order rather than re-sorting
        // the roster its own way.
        self.actors = VibenetAccountItem.orderedActors(actors)
        self.locked = locked
        self.hasInitiatedUnlock = hasInitiatedUnlock
        self.unlocksAt = unlocksAt
        self.unlockDelay = unlockDelay
        self.changeSequences = changeSequences
        self.history = history
        self.nativeBalance = nativeBalance
        self.tokenBalances = tokenBalances
        self.policyUses = policyUses
        self.subAccounts = VibenetSubAccounts.ordered(subAccounts)
    }

    /// The row's own alarm clock, R2.2 — the soonest FUTURE expiry inside
    /// `urgencyWindow`, or a count of already-expired keys when nothing is
    /// still ticking. A ticking clock is actionable; a lapsed one is a
    /// standing fact, so the ticking one wins when both exist. `expiry == 0`
    /// (Keystore's own "never") never counts either way.
    static let urgencyWindow: TimeInterval = 7 * 86_400

    func urgentLine(now: Date) -> String? {
        let dated = actors.filter { $0.expiry > 0 }
        let soonestFuture = dated
            .map { $0.expiry }
            .filter { TimeInterval($0) > now.timeIntervalSince1970 }
            .min()
        if let soonestFuture {
            let at = Date(timeIntervalSince1970: TimeInterval(soonestFuture))
            guard at.timeIntervalSince(now) <= Self.urgencyWindow else { return nil }
            return String(localized: "Key expires \(at.formatted(.relative(presentation: .named)))")
        }
        let expiredCount = dated.filter { TimeInterval($0.expiry) <= now.timeIntervalSince1970 }.count
        guard expiredCount > 0 else { return nil }
        return expiredCount == 1
            ? String(localized: "1 key expired")
            : String(localized: "\(expiredCount) keys expired")
    }

    /// "Unlocks in 3h" / "Unlock ready" — the lock badge's own clock,
    /// alongside the key expiry it was already sitting next to. `unlocksAt`
    /// is `Keystore.sol`'s own convention: nil/0 until an unlock has been
    /// INITIATED, so this returns nil rather than a sentence for the plain
    /// "Locked" state, which has no countdown to show yet.
    func unlockLabel(now: Date) -> String? {
        guard let unlocksAt, unlocksAt > 0 else { return nil }
        let at = Date(timeIntervalSince1970: TimeInterval(unlocksAt))
        guard at > now else { return String(localized: "Unlock ready") }
        return String(localized: "Unlocks \(at.formatted(.relative(presentation: .named)))")
    }

    /// 0…1 through the unlock timelock, or nil when EITHER endpoint is
    /// unknown — a bar with a guessed start is exactly the fake status §83
    /// bans, so this returns nothing rather than inventing a starting point.
    /// `unlockDelay` (seconds) plus `unlocksAt` gives the start for free:
    /// `start = unlocksAt - unlockDelay`. Clamped, so a delay measured
    /// slightly wrong by the chain never draws a bar past either end.
    func unlockProgress(now: Date) -> Double? {
        guard hasInitiatedUnlock,
              let unlocksAt, unlocksAt > 0,
              let unlockDelay, unlockDelay > 0
        else { return nil }
        let end = TimeInterval(unlocksAt)
        let start = end - TimeInterval(unlockDelay)
        let elapsed = now.timeIntervalSince1970 - start
        let total = end - start
        guard total > 0 else { return nil }
        return min(1, max(0, elapsed / total))
    }

    /// By kind, then actorId — TOTAL, so a card reshuffling its own actor
    /// list between opens over an unchanged roster reads as broken.
    static func orderedActors(_ actors: [VibenetActor]) -> [VibenetActor] {
        actors.sorted { a, b in
            if a.kind.sortRank != b.kind.sortRank { return a.kind.sortRank < b.kind.sortRank }
            return a.actorId < b.actorId
        }
    }

    /// ALPHABETICAL by the key's own displayed title, then actorId — a
    /// TOTAL order, and deliberately not a ranking (user, 2026-08-24: *"for
    /// ease the keys could just be listed in alphabetical order then we
    /// aren't making some judgement call"*).
    ///
    /// This REPLACES `byReach`, which sorted most-powerful-first. Ranking by
    /// power is the app deciding which of your keys matters, and it was the
    /// last survivor of the matrix this tray spent four passes refusing. The
    /// work that ordering was doing is done visually instead: an admin's chip
    /// INVERTS, so total authority is loud wherever it happens to sort, and
    /// nothing has to be reordered to say so.
    ///
    /// Sorts on `plainTitle` rather than `kind.sortRank` because the reader
    /// sees the title — an order they cannot reproduce by looking is not the
    /// judgement-free order they asked for.
    static func alphabetical(_ actors: [VibenetActor]) -> [VibenetActor] {
        actors.sorted { a, b in
            let f = a.kind.plainTitle.localizedCaseInsensitiveCompare(b.kind.plainTitle)
            if f != .orderedSame { return f == .orderedAscending }
            return a.actorId < b.actorId
        }
    }
}

// MARK: - The room

struct VibenetRoom: Equatable, Codable {
    let items: [VibenetAccountItem]
    /// The live config's own provenance ("as of commit a9ae95e1b") — so a
    /// screenshot of this card stays legible about WHEN it was true, on a
    /// network whose addresses can be different again by the time it's read.
    let branch: String?
    let commit: String?
    /// Whether the CONFIG fetch itself reached — kept apart from any one
    /// account's `reached`, because a config miss means every address below
    /// used a stale-or-absent set of addresses and none of their reads can
    /// be trusted, while a good config with one address unreachable is a
    /// narrower, far more ordinary failure.
    let configReached: Bool
    /// Whether THIS device has already seen a different commit than the one
    /// this read carries — a fact about the screen, not the chain, so it's
    /// handed in already computed (the `AddressConnectionsSeen`/`ChipMemory`
    /// shape) rather than read here; this file stays Foundation-only with no
    /// UserDefaults of its own. False on a first-ever read by construction —
    /// there's nothing yet to compare against, never a redeploy to report.
    let redeployedSinceLastSeen: Bool

    var isEmpty: Bool { items.isEmpty }
    var lockedCount: Int { items.filter(\.alarmed).count }
    var establishedCount: Int { items.filter(\.established).count }

    /// The single most urgent account — `items.first` once `ordered` has
    /// run (locked-first, then unreached, then established, then
    /// address), the `ASCRoom.lead` shape (2026-08-23). Several accounts
    /// are NOT mergeable the way a wallet balance is — one being locked
    /// says nothing about another's key count — so unlike the wallet
    /// crown this room has no single combined number to lead with. What
    /// it has instead is the one account that most needs a look, promoted
    /// to the headline; everyone else is a row underneath.
    var lead: VibenetAccountItem? { items.first }

    /// The room narrowed to ONE account, or whole when nothing is picked
    /// (2026-08-23). The face rail scopes the CARD, not just the rows
    /// beneath it — that is how the wallet rail behaves one venue over
    /// ("click all you see all, click one you see one"), and a rail that
    /// filtered only the events while the card kept listing every account
    /// is the same control meaning two different things in two rooms of
    /// the same fold.
    ///
    /// An address that is no longer watched scopes to NOTHING rather than
    /// silently falling back to everything: a stale pick showing the whole
    /// room looks identical to no pick at all, and the rail would be lit
    /// on a face whose room it was not describing.
    func scoped(to address: String?) -> VibenetRoom {
        guard let address else { return self }
        return VibenetRoom(
            items: items.filter { $0.address.caseInsensitiveCompare(address) == .orderedSame },
            branch: branch, commit: commit, configReached: configReached,
            redeployedSinceLastSeen: redeployedSinceLastSeen)
    }

    static func compose(items raw: [VibenetAccountItem], branch: String?, commit: String?,
                         configReached: Bool, redeployedSinceLastSeen: Bool = false) -> VibenetRoom {
        VibenetRoom(items: ordered(raw), branch: branch, commit: commit, configReached: configReached,
                    redeployedSinceLastSeen: redeployedSinceLastSeen)
    }

    /// A locked account first (the one alarm this room can raise), then an
    /// unreached read (worth more attention than a read that answered and
    /// simply found nothing), then established-before-not, then by address —
    /// TOTAL, so the card can never reshuffle between opens over identical
    /// reads.
    static func ordered(_ items: [VibenetAccountItem]) -> [VibenetAccountItem] {
        items.sorted { a, b in
            if a.alarmed != b.alarmed { return a.alarmed }
            if a.reached != b.reached { return !a.reached }
            if a.established != b.established { return a.established }
            return a.address.localizedCaseInsensitiveCompare(b.address) == .orderedAscending
        }
    }

    // MARK: Words

    /// "1 secp256k1 key, 1 passkey" / "No actors authorized" — grouped by
    /// kind, in the order each kind was FIRST seen in the roster (which is
    /// itself `orderedActors`'s kind-then-id order, so this reads stably).
    static func actorSummary(_ actors: [VibenetActor]) -> String {
        guard !actors.isEmpty else { return String(localized: "No actors authorized") }
        var counts: [VibenetAuthenticatorKind: Int] = [:]
        var order: [VibenetAuthenticatorKind] = []
        for actor in actors {
            if counts[actor.kind] == nil { order.append(actor.kind) }
            counts[actor.kind, default: 0] += 1
        }
        let parts = order.map { kind -> String in
            let n = counts[kind] ?? 0
            return n == 1 ? String(localized: "1 \(kind.label)")
                          : String(localized: "\(n) \(kind.label)s")
        }
        return parts.joined(separator: ", ")
    }

    /// The row's own line — what a person reads under the address. Two
    /// redundancies deliberately absent: it NEVER restates
    /// "Locked"/"Unlocking" (the badge already says that in bold beside it),
    /// and it counts the keys rather than NAMING them, because the detail
    /// sheet's key rows (R3.1) spell out every kind in full the moment
    /// someone opens it — listing them here too printed "1 secp256k1 key,
    /// 1 P-256 key, 1 Passkey, 1 Delegate, 1 Custom authenticator" across
    /// two wrapped lines on the one screen meant to be a summary.
    /// WHY an account is not established, and what ends it (prd §463, user:
    /// *"for the not established rooms, need to say that they need to
    /// complete their first transaction to deploy the account"*).
    ///
    /// `rowLine` says the STATE in three words because it is a row's
    /// subtitle; a card has room for the mechanism, and without it "Not
    /// established yet" reads as something the person is expected to fix
    /// and given no way to. An EIP-8130 account is counterfactual until its
    /// first transaction deploys it — the address is real and can already
    /// hold funds before that happens, which is the part that surprises
    /// people and is why the balance still draws above this line.
    ///
    /// nil for every other state: a reached, established account has
    /// nothing to explain, and an UNREACHED one must not be told why it is
    /// undeployed when the truth is that we could not look (§83).
    static func undeployedExplainer(_ item: VibenetAccountItem) -> String? {
        guard item.reached, !item.established else { return nil }
        return String(localized: "The account deploys with its first transaction — until then there's nothing to read. We check on every refresh.")
    }

    static func rowLine(_ item: VibenetAccountItem) -> String {
        guard item.reached else { return String(localized: "Couldn't reach the chain") }
        guard item.established else { return String(localized: "Not established yet") }
        guard !item.actors.isEmpty else { return String(localized: "No keys authorized") }
        return item.actors.count == 1
            ? String(localized: "1 key")
            : String(localized: "\(item.actors.count) keys")
    }

    /// The lead account's own state, as one sentence — `ASCRoom.headline`'s
    /// exact shape (2026-08-23), superseding a rolled-up "N of M" count.
    /// That count read as a contradiction the moment the card's hero drew
    /// every watched face while the sentence counted only the locked
    /// ones ("2 watched accounts are locked" above four faces), and it
    /// answered a question nobody asked — "how many are locked" is not
    /// "what should I look at first". This says the second thing: the
    /// single most urgent account's short address, its state, and its own
    /// clock if it has one — never a nickname (a per-device UI fact this
    /// Foundation-only file has no business depending on; the CARD
    /// substitutes one when drawing the lead as a row).
    static func headline(_ room: VibenetRoom, now: Date) -> String {
        guard room.configReached else {
            return String(localized: "Couldn't read vibenet's current contracts")
        }
        guard let lead = room.lead else {
            return String(localized: "Nothing watched on vibenet yet")
        }
        var line = "\(shortAddress(lead.address)) · \(stateWord(lead))"
        if let wait = leadWait(lead, now: now) { line += " · \(wait)" }
        return line
    }

    /// "Locked" / "Unlocking" / whatever `rowLine` already says for an
    /// unalarmed account — reusing its exact vocabulary so the headline
    /// and the row underneath it can never disagree about what one
    /// account's state is called. `rowLine` itself never says
    /// Locked/Unlocking (a row draws a separate badge for that); the
    /// headline has no badge beside it, so it has to say the word itself.
    private static func stateWord(_ item: VibenetAccountItem) -> String {
        guard item.alarmed else { return rowLine(item) }
        return item.hasInitiatedUnlock ? String(localized: "Unlocking") : String(localized: "Locked")
    }

    /// The lead's own clock — an unlock countdown first (closer to
    /// actionable than a key merely expiring), else the key-expiry
    /// urgency line.
    private static func leadWait(_ item: VibenetAccountItem, now: Date) -> String? {
        item.unlockLabel(now: now) ?? item.urgentLine(now: now)
    }

    /// "…0b1c" — `WalletStore.shortAddress`'s tail-only form (user ruling,
    /// 2026-08-23, superseding this file's own earlier middle-elided
    /// choice). A leading prefix plus a middle ellipsis is TWO truncations
    /// doing the job of one; the tail alone is what a person actually
    /// compares against the row beside it.
    static func shortAddress(_ address: String) -> String {
        guard address.count > 5 else { return address }
        return "…\(address.suffix(4))"
    }

    /// The quiet line at the BOTTOM of the card (2026-08-23, the
    /// `ASCRoom.note(_:drawn:)` shape) — how many more accounts aren't
    /// drawn, and the config's own provenance, joined, either, or
    /// neither. Moved off the top: it used to be the first thing in the
    /// room's scrollable content, which put it directly under the room's
    /// own floating settings gear with no surface behind it to separate
    /// the two — reported as "look at it touching the walls". Now it
    /// lives INSIDE the one card, at the bottom, the same position every
    /// other room's provenance line already keeps.
    static func note(_ room: VibenetRoom, drawn: Int) -> String? {
        guard room.configReached else {
            return String(localized: "vibenet is an experimental devnet — its contracts redeploy often, and this read couldn't reach the current set.")
        }
        var parts: [String] = []
        let hidden = room.items.count - drawn
        if hidden > 0 {
            parts.append(hidden == 1 ? String(localized: "1 more watched")
                                     : String(localized: "\(hidden) more watched"))
        }
        parts.append(provenanceLine(room))
        return parts.joined(separator: " · ")
    }

    /// The config's own provenance alone, since vibenet's contracts
    /// rotate and a stale screenshot is exactly the failure mode this
    /// whole feature is built to avoid. Trimmed to a fragment (2026-08-23)
    /// to match the terse, joined-by-" · " register every other room's
    /// bottom-of-card note already uses — "and every watched account was
    /// just re-read against it" was true but is implied by a fresh read
    /// existing at all, and a caption this small has no room for a clause
    /// that isn't carrying new information.
    private static func provenanceLine(_ room: VibenetRoom) -> String {
        let commit = room.commit.map { String($0.prefix(9)) }
        if room.redeployedSinceLastSeen, let commit {
            return String(localized: "vibenet redeployed — now at commit \(commit)")
        }
        switch (room.branch, commit) {
        case let (branch?, commit?):
            return String(localized: "As of vibenet's \(branch) branch, commit \(commit)")
        case let (nil, commit?):
            return String(localized: "As of vibenet commit \(commit)")
        default:
            return String(localized: "Read live from vibenet — addresses redeploy often")
        }
    }

    // MARK: - Demo fixture

    /// The demo's fixed snapshot, and every state this card can draw shown
    /// at once: all five nameable authenticator kinds, a rich established
    /// roster, a plain lock and a mid-unlock (so the badge's two words both
    /// show), an address still waiting to be established, a future key
    /// expiry on both a multi-key account's key rows and a single-key
    /// account's (R3.1), an unlock runway, and a non-nil
    /// `changeSequences` standing (the multichain
    /// footer line, otherwise never exercised in the demo). R2: a
    /// multi-moment key history (the strip) and a single-moment one (its
    /// no-strip floor), and a key expiring inside the 7-day urgency window
    /// (the collapsed row's own alarm line). Nothing here
    /// is a real read — `VibenetRoomSource.compose()` returns this directly
    /// under `DemoMode.isActive`, BEFORE it would otherwise touch the
    /// network, because this room keeps no persistence layer of its own for
    /// `DemoSeedAll` to seed into (see that file's `seedVibenet` for the
    /// other half — the matching watched addresses, so the setup screen's
    /// own list agrees with what this card shows). Kept in `VibenetRoom.swift`
    /// rather than `DemoSeedAll.swift` so it's covered by the same
    /// Foundation-only harness as everything else this file composes.
    ///
    /// NOT exercised here: a nickname. `VibenetWatch`'s names map is a live
    /// UserDefaults store this value-type fixture can't seed — check it by
    /// hand (context menu → "Name this account…") rather than faking a
    /// static name into a card meant to prove the READ path.
    static func demoFixture() -> VibenetRoom {
        let rich = VibenetAccountItem(
            address: "0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b",
            reached: true, established: true,
            actors: [
                // A future expiry, deliberately — the demo's ONE fixture
                // exercising the expiry sub-label on a multi-key account's
                // key row (R3.1). Fixed far enough out that this fixture
                // doesn't need updating for years.
                VibenetActor(actorId: "0x0000000000000000000000000000000000000000000000000000000000000001",
                             authenticator: "0x0000000000000000000000000000000000000001",
                             kind: .secp256k1, scope: VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer),
                             expiry: 4_102_444_800),
                // The fixture sets `kind` EXPLICITLY rather than deriving it
                // via `.identify` against a live config, so the p256 and
                // webAuthn addresses below are never compared against
                // anything and their exact value is cosmetic. They
                // deliberately do NOT start "0x8130…" (vibenet's own vanity
                // prefix, see `shortAddress`'s doc below): the drift guard
                // that forbids a hardcoded vibenet contract address anywhere
                // outside a comment can't tell a demo fixture from a live
                // call, and it shouldn't have to — a fake address that
                // merely LOOKS unlike a real contract is the simpler fix.
                VibenetActor(actorId: "0x0000000000000000000000000000000000000000000000000000000000000002",
                             authenticator: "0xaaaa1111222233334444555566667777888899aa",
                             kind: .p256, scope: VibenetScope(raw: VibenetScope.sender), expiry: 0),
                // A SESSION KEY, exactly as vibenet's own live ones read:
                // scope 0x0006 (POLICY|NONCE) — all 22 gated actors sampled
                // on 2026-08-24 carried precisely that — gated to the
                // config's policy manager, and carrying a commitment that
                // joins to the `policyUses` entry below. It is the fixture
                // for Base's "Monthly Vibes" subscription shape, and the one
                // place the demo can prove that a used session key says so
                // while its TERMS stay unreadable (`VibenetPolicyReadability`).
                VibenetActor(actorId: "0x0000000000000000000000000000000000000000000000000000000000000003",
                             authenticator: "0xbbbb1111222233334444555566667777888899bb",
                             kind: .webAuthn, scope: VibenetScope(raw: VibenetScope.policy | VibenetScope.nonce),
                             expiry: 0,
                             policyManager: "0xdddd1111222233334444555566667777888899dd",
                             policyCommitment: "0x00000000000000000000000000000000000000000000000000000000000000c0"),
                // THE ONE demo actor whose id IS compared against something —
                // and the fixture that was ENCODED WRONG until 2026-08-24.
                //
                // "rich" authorized "lockedPlain" as its delegate. On the real
                // chain that reads as `actorId = ActorId.fromAddress(delegate)`
                // — lockedPlain's address right-aligned into a 32-byte word —
                // with `authenticator` being the DelegateAuthenticator
                // CONTRACT, the same for every delegate on vibenet. This
                // fixture used to put the delegate's address in the
                // AUTHENTICATOR field, which the chain never does, so it
                // proved `VibenetAccountMapping.links` worked while the live
                // path could not match once. A fixture that encodes data the
                // chain does not produce tests nothing but itself.
                // 24 zeros then `lockedPlain`'s 40 hex chars = one 32-byte word.
                VibenetActor(actorId: "0x0000000000000000000000002b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c",
                             authenticator: "0xeeee1111222233334444555566667777888899ee",
                             kind: .delegate, scope: VibenetScope(raw: VibenetScope.sponsorPayer), expiry: 0),
                // SCOPE 0 — the admin, and the one state the demo could not
                // show before (prd §463). It renders as a single inverted
                // "Admin" chip rather than as five permissions, so the demo
                // exercises both the reading and the treatment that says
                // "this key has no limits at all" without reordering the
                // roster to make the point. Realistic on an AA account: an
                // original owner key alongside a scoped session key.
                VibenetActor(actorId: "0x0000000000000000000000000000000000000000000000000000000000000008",
                             authenticator: "0xcccc1111222233334444555566667777888899cc",
                             kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: 0),
                // A scope this build has no name for — the roster's honest
                // "+1 unknown" fallback, never an invented label.
                VibenetActor(actorId: "0x0000000000000000000000000000000000000000000000000000000000000005",
                             authenticator: "0x9999999999999999999999999999999999999a",
                             kind: .custom, scope: VibenetScope(raw: VibenetScope.sender | 0x0400), expiry: 0),
            ],
            locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil,
            // R2.1: 4 moments, computed relative to now so the fixture
            // never goes stale — two adds, a revoke, an add. `demoFixture`
            // is the one place in this file allowed to read `Date.now`
            // (composed live, never persisted).
            history: VibenetKeyHistory.ordered([
                VibenetKeyMoment(block: 100, logIndex: 0, authorized: true, kind: .secp256k1,
                                 date: Date.now.addingTimeInterval(-40 * 86_400)),
                VibenetKeyMoment(block: 220, logIndex: 0, authorized: true, kind: .p256,
                                 date: Date.now.addingTimeInterval(-12 * 86_400)),
                VibenetKeyMoment(block: 220, logIndex: 1, authorized: false, kind: nil,
                                 date: Date.now.addingTimeInterval(-12 * 86_400)),
                VibenetKeyMoment(block: 340, logIndex: 0, authorized: true, kind: .webAuthn,
                                 date: Date.now.addingTimeInterval(-2 * 86_400)),
            ]),
            // Balances (2026-08-24): a native reading AND both token
            // balances, so the demo exercises every branch the chip strip
            // and the hero can draw — a lone account with neither would
            // leave the "does this fold correctly" question untested.
            nativeBalance: 2.5,
            tokenBalances: [VibenetTokenBalance(symbol: "USDV", amount: 500.25),
                            VibenetTokenBalance(symbol: "NFV", amount: 12)],
            // The session key above HAS run — the one demo fixture proving a
            // gated key can say how often it acted while still refusing to
            // state terms it cannot read.
            policyUses: [VibenetPolicyUse(
                commitment: "0x00000000000000000000000000000000000000000000000000000000000000c0",
                count: 4, lastUsed: Date.now.addingTimeInterval(-2 * 86_400))],
            // Base's "Spending Account" shape: one sub-account already
            // watched (so it also appears as a linked account) and one NOT,
            // which is the whole reason this read exists — an account you can
            // act for and had no idea about.
            subAccounts: [
                VibenetSubAccount(address: "0x3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d",
                                  watched: true,
                                  authorizedAt: Date.now.addingTimeInterval(-9 * 86_400)),
                VibenetSubAccount(address: "0x7f1e2d3c4b5a69788796a5b4c3d2e1f009182736",
                                  watched: false,
                                  authorizedAt: Date.now.addingTimeInterval(-3 * 86_400)),
            ])

        let lockedPlain = VibenetAccountItem(
            address: "0x2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c",
            reached: true, established: true,
            actors: [VibenetActor(actorId: "0x0000000000000000000000000000000000000000000000000000000000000006",
                                   authenticator: "0x0000000000000000000000000000000000000001",
                                   kind: .secp256k1, scope: VibenetScope(raw: VibenetScope.sender),
                                   // R2.2: inside the 7-day urgency window —
                                   // this row's own collapsed subtitle
                                   // leads with it instead of a key count.
                                   expiry: UInt64(Date.now.addingTimeInterval(3 * 86_400).timeIntervalSince1970))],
            locked: true, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil,
            // A native reading with NO token balances — the demo's other
            // real branch: some accounts hold vibenet ETH and nothing else.
            nativeBalance: 0.014)

        let unlocking = VibenetAccountItem(
            address: "0x3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d",
            reached: true, established: true,
            actors: [VibenetActor(actorId: "0x0000000000000000000000000000000000000000000000000000000000000007",
                                   authenticator: "0x0000000000000000000000000000000000000001",
                                   kind: .secp256k1, scope: VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer),
                                   // A single-actor account with an
                                   // expiry too — R3.1's key row draws the
                                   // same way whether an account has one
                                   // key or several, so this just doubles
                                   // the expiry-sub-label coverage above.
                                   expiry: 4_102_444_800)],
            locked: true, hasInitiatedUnlock: true, unlocksAt: 4_102_444_800, unlockDelay: 43_200,
            // The multichain footer line has never rendered in the demo —
            // this is the fixture's one non-nil standing.
            changeSequences: VibenetChangeSequences(multichain: 12, localEpoch: 2, localSequence: 5),
            // R2.1's no-strip floor: exactly one moment, so the summary
            // line shows and the dot strip itself does not.
            history: [VibenetKeyMoment(block: 50, logIndex: 0, authorized: true, kind: .secp256k1,
                                       date: Date.now.addingTimeInterval(-60 * 86_400))])

        let notEstablishedYet = VibenetAccountItem(
            address: "0x4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e",
            reached: true, established: false,
            actors: [], locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil)

        return compose(items: [rich, lockedPlain, unlocking, notEstablishedYet],
                        branch: "main", commit: "a9ae95e1bdemo",
                        configReached: true, redeployedSinceLastSeen: true)
    }
}

// MARK: - Delegate mapping (2026-08-24)

/// There is no concept of accounts relating to each other anywhere in this
/// file — every watched address composes into a flat, independent
/// `VibenetAccountItem`. But EIP-8130 gives us exactly ONE real signal that
/// says otherwise: a `.delegate` actor's `authenticator` field IS another
/// account's address, meaning that account can act for this one. That is
/// the whole of it — there is no sub-account hierarchy in the spec to draw
/// beyond this, and this file will never invent one past what a single
/// `.delegate` actor actually states.
struct VibenetDelegateLink: Identifiable, Equatable {
    var id: String { "\(from):\(to)" }
    /// The account that authorized the delegate.
    let from: String
    /// The watched address acting as `from`'s delegate.
    let to: String
}

enum VibenetAccountMapping {
    /// Every WATCHED-to-WATCHED delegate relationship in the room —
    /// derived STRICTLY from `.delegate` actors whose `authenticator`
    /// matches another item's `address`, case-insensitively (the same rule
    /// `VibenetAuthenticatorKind.identify` already uses to compare a
    /// live-fetched address against itself: an RPC's hex casing is not a
    /// promise).
    ///
    /// A `.delegate` actor whose authenticator points at an address nobody
    /// watches is real — this build simply has no second account to say
    /// anything about — and is deliberately EXCLUDED here rather than
    /// turned into a link to nowhere. The honesty rule cuts both ways:
    /// never invent a relationship this build can't confirm, and never
    /// silently drop the half of the picture it CAN.
    ///
    /// TOTAL order (`from`, then `to`, both case-insensitive) — a mapping
    /// section that reshuffles between opens over an unchanged room reads
    /// as broken, the same standard every other roster in this file holds.
    static func links(_ items: [VibenetAccountItem]) -> [VibenetDelegateLink] {
        var out: [VibenetDelegateLink] = []
        for item in items {
            for actor in item.actors where actor.kind == .delegate {
                // `delegateAddress`, NEVER `authenticator` — a delegate
                // actor's authenticator is the DelegateAuthenticator
                // CONTRACT, identical for every delegate on the chain, so
                // the old comparison could not match a real account once.
                // See `VibenetActorId` for the live measurement.
                guard let delegate = actor.delegateAddress,
                      let target = items.first(where: {
                    $0.address.caseInsensitiveCompare(delegate) == .orderedSame
                }) else { continue }
                out.append(VibenetDelegateLink(from: item.address, to: target.address))
            }
        }
        return out.sorted { a, b in
            let f = a.from.localizedCaseInsensitiveCompare(b.from)
            if f != .orderedSame { return f == .orderedAscending }
            return a.to.localizedCaseInsensitiveCompare(b.to) == .orderedAscending
        }
    }
}

// MARK: - Shared keys across accounts (2026-08-24)

/// One OTHER watched account that authorizes the exact same key as the
/// account being asked about — the literal `authenticator` address, not a
/// delegate relationship. `VibenetAccountMapping.links` already owns "this
/// other account can act for me"; a `.delegate` actor's `authenticator`
/// names another ACCOUNT, not a key, so `.delegate` is excluded from
/// `VibenetKeyReuse.sharing` on purpose — otherwise the same pair of
/// addresses would draw twice, once under each heading, disagreeing about
/// what actually relates them.
struct VibenetSharedKey: Identifiable, Equatable, Hashable {
    var id: String { "\(account):\(actorId)" }
    /// The other watched account this key is ALSO authorized on.
    let account: String
    /// THE KEY'S OWN IDENTITY — the actorId, never the authenticator (which
    /// names the validating contract and is shared by every key of a kind;
    /// see `VibenetActorId` for the measurement that caught this). `Keystore`
    /// stores actors as `_actorConfig[actorId][account]`, so one actorId
    /// under two accounts is one key authorized twice, which is precisely
    /// what this type claims.
    let actorId: String
    let kind: VibenetAuthenticatorKind
}

/// A fact none of this room's other sections state: the same signing key
/// authorized on more than one watched account. Delegation says "this
/// account can act for that one"; this says something a delegate link
/// can't — that losing (or leaking) ONE key endangers every account
/// listed here, even when none of them has ever named another as its
/// delegate.
enum VibenetKeyReuse {
    /// Every account `item` shares a literal key with, one row per shared
    /// authenticator — compared case-insensitively (an RPC's hex casing is
    /// not a promise, the same rule `VibenetAccountMapping.links` already
    /// applies). `items` is the FULL watch list, not a rail-narrowed
    /// `room.items` — a shared key can name an account currently out of
    /// scope, same reasoning `VibenetAccountDetail`'s callers already
    /// apply to `links`.
    ///
    /// TOTAL order (account, then the Keystore's own kind order) — the
    /// same reshuffle discipline every roster in this file holds.
    static func sharing(_ item: VibenetAccountItem, in items: [VibenetAccountItem]) -> [VibenetSharedKey] {
        var out: Set<VibenetSharedKey> = []
        for actor in item.actors where actor.kind != .delegate {
            for other in items where other.address.caseInsensitiveCompare(item.address) != .orderedSame {
                // MATCHED ON actorId. Matching on `authenticator` — which
                // this shipped doing — compares which CONTRACT validates the
                // key, and 127 of the 199 live actors sampled on 2026-08-24
                // shared one (`K1_AUTHENTICATOR`) across 112 distinct
                // accounts. That reported the most ordinary configuration
                // there is — two accounts, a wallet key each — as a reused
                // key, on the row whose whole job is warning that losing one
                // key endangers several accounts. A false alarm here is worse
                // than silence: it teaches the reader to ignore the line.
                guard other.actors.contains(where: {
                    $0.kind != .delegate &&
                    $0.actorId.caseInsensitiveCompare(actor.actorId) == .orderedSame
                }) else { continue }
                out.insert(VibenetSharedKey(account: other.address, actorId: actor.actorId, kind: actor.kind))
            }
        }
        return out.sorted { a, b in
            let f = a.account.localizedCaseInsensitiveCompare(b.account)
            if f != .orderedSame { return f == .orderedAscending }
            return a.kind.sortRank < b.kind.sortRank
        }
    }
}

extension Array where Element == VibenetSharedKey {
    /// "Also authorized on …0b1c" / "Also authorized on 3 other accounts" —
    /// drawn beside the one key it's about (`VibenetAccountDetail.keyRow`
    /// already filters to entries sharing THAT actor's own authenticator),
    /// so this only ever names WHERE, never re-states which key or why.
    /// nil when empty — most keys aren't reused, and a clause repeating
    /// that on every ordinary key is the empty state this codebase omits
    /// rather than prints (§83).
    ///
    /// TAKES ITS NAME RESOLVER rather than reaching `VibenetWatch.shared`
    /// (prd §463),
    /// and that is not a style preference: this file is Foundation-only so
    /// the harness can compile it WHOLE, and the nickname store is a
    /// UserDefaults singleton from `VibenetBridge`. Reaching it from here
    /// broke that invariant the day this function shipped, which took
    /// `scripts/vibenet-selftest.sh` — 150 assertions over the whole room —
    /// down with it, and is why the reuse logic it was added to flag had no
    /// coverage at all: it could not have had any. The closure keeps the
    /// nickname lookup at the call site, where the store already lives.
    func sharedLine(name: (String) -> String) -> String? {
        guard !isEmpty else { return nil }
        if count == 1, let only = first {
            return String(localized: "Also authorized on \(name(only.account))")
        }
        return String(localized: "Also authorized on \(count) other accounts")
    }
}

// MARK: - What a session key's policy says — and what it CANNOT say

/// **THE SPEND CAP IS NOT ON CHAIN. DO NOT GO LOOKING FOR IT AGAIN.**
///
/// Base's own account demo (`chain.base.org/demos/account`) presents two
/// apps built on EIP-8130 — a "Monthly Vibes" SUBSCRIPTION ("at most 5 USDC
/// per month, and only via the USDC transfer") and a "Spending Account"
/// sub-account. Neither is a new primitive: the subscription is a
/// POLICY-scoped actor bound to `SessionPolicy`, and the spending account is
/// a second account with the main one authorized as a delegate. Both are
/// shapes this room already reads. What this room could not say is the part
/// people actually want — the CAP — and the reason is structural, not a gap
/// in this app:
///
/// `SessionPolicy` stores **mutable spend usage only**. Its `Config` (the
/// `TokenLimit[]` carrying `token`, `limit`, `period` and `recipients`, and
/// the `CallScope[]` carrying allowed targets and selectors) is COMMITTED,
/// not stored: `Keystore` keeps `manager(20) || commitment(32)` and nothing
/// else, the commitment being a hash the config is checked against when it
/// is re-supplied on every execute. `SessionPolicy.getCurrentSpend` does
/// exist and would give the period usage — but it takes the `TokenLimit`
/// as an argument and its own doc says the result "is only meaningful when
/// `limit` is the committed TokenLimit from the binding's config", which is
/// exactly the thing we do not have. There is no event carrying the config
/// either: `ActorAuthorized`'s `actorData` is
/// `authenticator || expiry || scope || bytes4(0) || manager || commitment`
/// (decoded from real logs, 2026-08-24) and stops at the commitment.
///
/// So a cap shown here would be invented, and a spend bar would be invented
/// twice over. What IS readable is whether the key has been USED, which is
/// `VibenetPolicyUse` below — and the honest sentence that the terms live
/// off chain, which is this enum's own line. Revisit only if Base ships a
/// getter that takes `(account, actorId)` and returns the config.
enum VibenetPolicyReadability {
    /// Said once, under a gated key, and never dressed up as a limitation of
    /// this app: the reader is being told a true thing about EIP-8130.
    static var note: String {
        String(localized: "Its limits were agreed off chain — only the account and the app hold the terms.")
    }
}

/// How many times a policy-gated key has actually executed, and when it last
/// did — the one live fact about a session key that the chain does publish.
///
/// `PolicyManager` emits
/// `PolicyExecuted(address indexed account, address indexed policy, bytes32
/// indexed commitment, address caller)` on every run, so a key's own
/// `policyCommitment` joins straight to its usage with no decoding at all —
/// all three fields this needs are indexed topics. MEASURED 2026-08-24:
/// topic0 `0x0576b52e…`, 6 executions live on vibenet's PolicyManager.
///
/// This is what turns "Limited to the policy manager" — a sentence that
/// reads identically for all 22 gated keys on the devnet — into a fact about
/// YOUR key. It is deliberately a COUNT and a DATE, never a rate, an average
/// or a projection: three executions is not "3 per month", and a
/// subscription that has run once is not "£5/mo".
struct VibenetPolicyUse: Equatable, Codable {
    /// The commitment these executions were recorded against — the join key,
    /// carried so a caller can match it to an actor without re-deriving it.
    let commitment: String
    let count: Int
    /// The most recent execution's block time, or nil when the block-time
    /// lookup failed. Never `.now`: a fallback rendered as a sentence dates
    /// an old execution to today, the standing rule this bridge already
    /// keeps for every landed event.
    let lastUsed: Date?

    /// "Used 4 times · last 2 days ago" / "Used once" / "Never used" —
    /// the whole claim. A zero count is a REAL and useful reading on a
    /// subscription key (it says the thing has never charged), so unlike
    /// most empty states in this codebase it is spoken rather than omitted.
    func line(now: Date) -> String {
        let uses = count == 0
            ? String(localized: "Never used")
            : (count == 1 ? String(localized: "Used once")
                          : String(localized: "Used \(count) times"))
        guard count > 0, let lastUsed else { return uses }
        return "\(uses) · \(String(localized: "last \(lastUsed.formatted(.relative(presentation: .named)))"))"
    }
}

extension Array where Element == VibenetPolicyUse {
    /// This list's entry for one actor's commitment, or nil. Case-insensitive
    /// for the reason every hex compare in this file is: an RPC's casing is
    /// not a promise.
    func use(for actor: VibenetActor) -> VibenetPolicyUse? {
        guard let commitment = actor.policyCommitment else { return nil }
        return first { $0.commitment.caseInsensitiveCompare(commitment) == .orderedSame }
    }
}

// MARK: - Sub-accounts: who names a watched address as their delegate

/// An account that authorized a watched address as its DELEGATE — i.e. an
/// account the watched address can act for. Base's own demo calls this a
/// "Spending Account" and gives it a tab of its own ("Sub-accounts") beside
/// Assets, Owners and Session keys.
///
/// `VibenetAccountMapping.links` already finds these, but only between two
/// addresses the person has BOTH already watched, which is the case that
/// needs no discovery. This is the other direction and the useful one: a
/// single indexed log filter — `ActorAuthorized` with `topics[2]` pinned to
/// `ActorId.fromAddress(watched)` — returns every account on the chain that
/// named this address, watched or not. One cheap filtered read per watched
/// address, no global walk (MEASURED 2026-08-24: the filter answers, and
/// finds the one real delegator of a sampled account).
struct VibenetSubAccount: Identifiable, Equatable, Codable {
    var id: String { address }
    /// The account that did the authorizing — the one this watched address
    /// can act for.
    let address: String
    /// Whether this device already watches it. The whole point of the read
    /// is the FALSE case (an account you can act for and had no idea about),
    /// so the flag is what lets the view offer to watch it rather than
    /// listing something already on screen elsewhere.
    let watched: Bool
    /// When the authorization landed, nil on a failed block-time lookup.
    let authorizedAt: Date?
}

enum VibenetSubAccounts {
    /// "You can act for 2 accounts · 1 not watched" — nil when there are
    /// none, which is the ordinary case and earns no empty row.
    static func line(_ accounts: [VibenetSubAccount]) -> String? {
        guard !accounts.isEmpty else { return nil }
        let unwatched = accounts.filter { !$0.watched }.count
        var line = accounts.count == 1
            ? String(localized: "Can act for 1 account")
            : String(localized: "Can act for \(accounts.count) accounts")
        if unwatched > 0 {
            line += unwatched == 1
                ? String(localized: " · 1 not watched")
                : String(localized: " · \(unwatched) not watched")
        }
        return line
    }

    /// Unwatched first (they are the discovery this read exists for), then
    /// newest, then address — TOTAL, so the list cannot reshuffle between
    /// opens over an unchanged chain.
    static func ordered(_ accounts: [VibenetSubAccount]) -> [VibenetSubAccount] {
        accounts.sorted { a, b in
            if a.watched != b.watched { return !a.watched }
            switch (a.authorizedAt, b.authorizedAt) {
            case let (x?, y?) where x != y: return x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default: break
            }
            return a.address.localizedCaseInsensitiveCompare(b.address) == .orderedAscending
        }
    }
}

// MARK: - Owners vs session keys (Base's own information architecture)

/// Base's account demo splits an account's keys into **Owners** and
/// **Session keys**, and that split is not a presentation choice — it is the
/// POLICY scope bit, which is the difference between a key that can spend
/// the account and one that may only call one contract under terms the
/// account agreed to. This room drew both as one undifferentiated list, so
/// an admin key and a capped subscription key sat shoulder to shoulder with
/// nothing but chip colour between them.
///
/// THREE groups, not two, because there is a real third case Base's own UI
/// has no room for: a key with neither the POLICY bit nor total authority —
/// scoped, but not to a contract. Folding it into either group would be a
/// claim about it that the scope does not make.
enum VibenetKeyGroup: String, Equatable, Codable, CaseIterable {
    /// Scope 0 — unrestricted. The spec's own word is admin.
    case owner
    /// The POLICY bit: may call exactly one target, its configured manager.
    case session
    /// Everything else — scoped, but not gated to a contract.
    case scoped

    /// Declaration order IS display order: owners first, because a key that
    /// can do anything outranks one that can do one thing.
    var sortRank: Int {
        switch self {
        case .owner: 0
        case .session: 1
        case .scoped: 2
        }
    }

    var title: String {
        switch self {
        case .owner:   String(localized: "Owners")
        case .session: String(localized: "Session keys")
        case .scoped:  String(localized: "Limited keys")
        }
    }

    /// One clause saying what membership MEANS — drawn under the heading, so
    /// the group name never has to be guessed at from the keys inside it.
    var caption: String {
        switch self {
        case .owner:   String(localized: "Full control of this account")
        case .session: String(localized: "Limited to one contract, under agreed terms")
        case .scoped:  String(localized: "Some permissions, no contract limit")
        }
    }

    static func of(_ actor: VibenetActor) -> VibenetKeyGroup {
        if actor.scope.isAdmin { return .owner }
        if actor.scope.raw & VibenetScope.policy != 0 { return .session }
        return .scoped
    }
}

/// One group and its keys, ready to draw.
struct VibenetKeySection: Identifiable, Equatable {
    var id: String { group.rawValue }
    let group: VibenetKeyGroup
    let actors: [VibenetActor]
}

enum VibenetKeyGrouping {
    /// The account's keys, split by what they can do and alphabetical WITHIN
    /// each group — `VibenetAccountItem.alphabetical`'s judgement-free order
    /// preserved exactly (user, 2026-08-24: *"for ease the keys could just be
    /// listed in alphabetical order then we aren't making some judgement
    /// call"*). Grouping is NOT ranking: it names a real distinction the
    /// scope bits already draw, rather than deciding which of your keys
    /// matters. An empty group is omitted, never drawn as a heading with
    /// nothing under it.
    static func sections(_ actors: [VibenetActor]) -> [VibenetKeySection] {
        var buckets: [VibenetKeyGroup: [VibenetActor]] = [:]
        for actor in actors { buckets[VibenetKeyGroup.of(actor), default: []].append(actor) }
        return VibenetKeyGroup.allCases
            .sorted { $0.sortRank < $1.sortRank }
            .compactMap { group in
                guard let members = buckets[group], !members.isEmpty else { return nil }
                return VibenetKeySection(group: group,
                                         actors: VibenetAccountItem.alphabetical(members))
            }
    }
}

// MARK: - Aggregate key summary (2026-08-24)

/// One kind's share of the aggregate — a named struct rather than a tuple,
/// so `VibenetKeyAggregate` stays plainly `Equatable`: a tuple has no
/// automatic `Equatable` conformance for `Array` to key off, however
/// Equatable its own elements are.
struct VibenetKeyKindCount: Equatable {
    let kind: VibenetAuthenticatorKind
    let count: Int
}

/// The one key across every watched account whose clock ticks soonest —
/// the address it belongs to, alongside the actor itself so a caller can
/// still reach every other fact about it (`expiryLabel`, `kind`, `scope`)
/// without this file re-deriving a second, narrower view of the same actor.
struct VibenetKeySoonestExpiry: Equatable {
    let address: String
    let actor: VibenetActor

    /// "…0b1c's key expires in 3 days" — reuses `VibenetActor
    /// .expiryLabel`'s own clock arithmetic rather than re-deriving it, so
    /// the callout and the key's own row (wherever it happens to be drawn)
    /// can never disagree about when this key actually expires. Takes
    /// `now` as a parameter, same discipline as every other clock fact in
    /// this file — this reading is captured once by `VibenetKeyAggregation
    /// .compose`, but the LABEL is recomputed fresh each time a caller
    /// draws it, exactly like `unlockLabel(now:)` and `expiryLabel(now:)`
    /// already are.
    func line(now: Date) -> String {
        String(localized: "\(VibenetRoom.shortAddress(address))'s key \(actor.expiryLabel(now: now).lowercased())")
    }
}

/// Every key across every watched account, at once — the one fact nowhere
/// in this room states today. `VibenetRoom.actorSummary` already answers
/// "how many keys does THIS account have"; nothing answers "how many keys
/// am I responsible for in total, and is any one of them about to lapse".
/// One permission, and how many keys in the room hold it.
struct VibenetPolicyCount: Equatable {
    let label: String
    let count: Int
}

/// The room's keys counted BY WHAT THEY CAN DO, not by what kind of key they
/// are (prd §463). `VibenetKeyAggregation` answers "4 secp256k1, 1 passkey",
/// which is taxonomy — it says nothing about who can spend. This answers the
/// question the room is actually opened with.
///
/// ADMIN LEADS AND IS COUNTED APART, never folded into the five bits: scope 0
/// holds every capability including the reserved ones this build cannot name,
/// so adding it to "Send anywhere" would both understate it and inflate a
/// count that is supposed to mean "these specific keys carry this specific
/// bit".
///
/// Rows in `Scopes.sol`'s own declared order, and a permission NOBODY holds is
/// dropped rather than printed as a zero — an empty row on this card is not
/// the reading a silent year is on a journal strip, it is a permission that
/// simply does not appear in this room.
/// One reading of the room's native total, at a moment.
///
/// `usd` is deliberately NOT the field name Wallet uses, because this is not
/// dollars — vibenet has no price feed and this is native ETH. Naming it
/// `native` is the difference between a chart of what the accounts HOLD and a
/// chart of what they are WORTH, and only one of those is a claim this app can
/// make here.
struct VibenetValueSample: Equatable, Codable {
    let at: Date
    let native: Double
}

/// The room's balance history — what makes a sparkline possible at all.
///
/// The card had no line because nothing recorded one, and the first instinct
/// was to seed a curve into the demo alone. That would have been worse than no
/// line: a demo drawing a chart the shipped app cannot draw is a promise about
/// the product, made on the one screen someone judges it by. So the history is
/// REAL — recorded from the same sweep that already reads the balances, on
/// every device, and the demo seeds this same store rather than a private
/// fixture.
///
/// The 4-hour throttle and the thinning are `WalletStore.recordSample`'s, on
/// purpose: two histories of the same shape in one app that disagree about how
/// often a point lands would make two charts that cannot be compared.
enum VibenetValueHistory {
    /// The SETTLED interval, mirroring `WalletStore.recordSample`'s own — once
    /// a curve exists, four hours is the right resolution for a balance and
    /// anything finer is just more points saying the same thing.
    static let throttle: TimeInterval = 4 * 3600
    /// **The OPENING interval, and the reason it exists (2026-08-24, reported:
    /// "the app still does not have sparkline").** `series` needs two readings
    /// and the settled throttle only lets a second one land four hours after
    /// the first — so on the day this bridge ships, and for every person who
    /// watches their first account, the curve is structurally unreachable. It
    /// was not that the chart was broken; it was that the chart could not yet
    /// have anything to draw, and the room simply said nothing about it.
    ///
    /// Wallet never hit this because its history has been accumulating for
    /// months; a NEW store has to earn its first curve, and at four hours a
    /// person watching an account and looking at the room twice in an evening
    /// sees an empty space both times.
    ///
    /// Every point is still a REAL reading of a real balance — this shortens
    /// how often we look, never invents a value between two looks. The curve
    /// is honest from the first frame; it just fills in over minutes instead
    /// of over a day, and hands back to `throttle` the moment it can draw.
    static let openingThrottle: TimeInterval = 120
    /// How many readings a curve wants before the interval settles down.
    static let minimumForCurve = 6
    static let cap = 180

    /// How long to wait before the NEXT reading, given how many are already
    /// held. See `openingThrottle` for why this is not one constant.
    static func interval(forExisting count: Int) -> TimeInterval {
        count < minimumForCurve ? openingThrottle : throttle
    }

    /// A sample is kept only when the last one is older than the interval that
    /// applies at this stage — the caller may call this every sweep and, once
    /// the curve is established, usually writes nothing.
    static func appending(_ samples: [VibenetValueSample],
                          native: Double,
                          now: Date) -> [VibenetValueSample]? {
        if let last = samples.last,
           now.timeIntervalSince(last.at) < interval(forExisting: samples.count) { return nil }
        var out = samples
        out.append(VibenetValueSample(at: now, native: native))
        if out.count > cap { out.removeFirst(out.count - cap) }
        return out
    }

    /// The plotted series, oldest first. Fewer than two readings draws
    /// NOTHING: one point is a flat line, and a flat line on a balance chart
    /// reads as "went to zero" — the failure this codebase already names.
    static func series(_ samples: [VibenetValueSample]) -> [Double]? {
        guard samples.count >= 2 else { return nil }
        return samples.map(\.native)
    }

    /// The change across the plotted window, or nil when there is no window
    /// or the move rounds to nothing — a change that rounds to zero has no
    /// direction, so it gets no arrow and no colour (§83's own corollary).
    static func delta(_ samples: [VibenetValueSample]) -> Double? {
        guard let first = samples.first?.native, let last = samples.last?.native,
              samples.count >= 2, first > 0 else { return nil }
        let change = (last - first) / first
        return abs(change) < 0.0005 ? nil : change
    }
}

/// The demo's balance curve, as PURE logic so the harness can hold it.
///
/// It lives here rather than in `DemoSeedAll` for the reason every other
/// checkable rule in this feature does: that file is not Foundation-only and
/// the harness cannot compile it, so a curve written there would be the one
/// part of the demo nothing could assert. `DemoSeedAll` calls this and writes
/// the result into the REAL store.
enum VibenetDemoHistoryShape {
    /// Ends on `VibenetRoom.demoFixture()`'s own native total, because the
    /// crown states that number directly above the line and a curve ending
    /// anywhere else would contradict the figure it sits under.
    static let endsOn = 2.514

    /// Deterministic — no randomness, so two demo entries draw the identical
    /// line. Spaced at the store's own throttle, so this is exactly the shape
    /// a real watcher's readings would have after a fortnight. The dips are
    /// what keep it reading as a balance rather than a ramp.
    static func samples(now: Date) -> [VibenetValueSample] {
        samples(endingOn: endsOn, now: now)
    }

    /// The same curve scaled to end on a given balance — what a single
    /// account's own history looks like in the demo. Scaled rather than
    /// re-shaped so every account's line is recognisably the same family of
    /// object, and so each one still ends on the figure its own crown states.
    static func samples(endingOn end: Double, now: Date) -> [VibenetValueSample] {
        let shape: [Double] = [0.72, 0.78, 0.74, 0.95, 1.10, 1.04, 1.32,
                               1.55, 1.49, 1.78, 2.05, 1.98, 2.31, 1.0]
        return shape.enumerated().map { index, factor in
            VibenetValueSample(
                at: now.addingTimeInterval(-Double(shape.count - 1 - index) * VibenetValueHistory.throttle),
                native: end * factor)
        }
    }
}

/// One cell of the room's holdings drawing.
struct VibenetTreemapCell: Equatable {
    let symbol: String
    let amount: String
    /// What tone this cell draws at, 0…1 — see `VibenetBalanceTreemap`.
    let share: Double
}

/// The room's holdings as areas, for `DS.ink(magnitude:)`.
///
/// THE HONEST PART, and the reason this is a named type rather than three
/// lines in the view: there is NO PRICE FEED here. Wallet's treemap sizes its
/// cells by true USD share because it knows what a token is worth; this room
/// knows only that an account holds 2.5 ETH and 500 USDV, and those do not
/// convert. So the tone carries RANK — native first, then tokens in their own
/// sorted order — never a cross-asset ratio, which would be a made-up number
/// presented as an area and read as one.
///
/// Native leads because it is the one holding every vibenet account has in the
/// same unit, which is also why the crown above states it and nothing else.
enum VibenetBalanceTreemap {
    static let maxCells = 3

    static func cells(_ aggregate: VibenetBalanceAggregate) -> [VibenetTreemapCell] {
        var out: [VibenetTreemapCell] = []
        if let native = aggregate.nativeTotal {
            out.append(VibenetTreemapCell(symbol: "ETH",
                                          amount: VibenetBalanceFormat.line(native),
                                          share: 1.0))
        }
        // The tokens RAMP rather than sharing one tone. They are ranked by the
        // aggregate's own order and the ink follows that rank, which is what
        // makes the block read as a treemap (a field of related areas, biggest
        // and brightest first) rather than as two identical boxes beside a
        // large one. Floored so the last cell is still a surface and not a
        // hole in the card.
        for (index, total) in aggregate.tokenTotals.enumerated() {
            out.append(VibenetTreemapCell(symbol: total.symbol,
                                          amount: VibenetBalanceFormat.line(total.amount),
                                          share: max(0.14, 0.46 - Double(index) * 0.16)))
        }
        // A lone cell is not a treemap, it is a rectangle repeating the crown
        // directly above it — the caller draws nothing rather than that.
        guard out.count > 1 else { return [] }
        return Array(out.prefix(maxCells))
    }
}

enum VibenetPolicyAggregation {
    static func compose(_ items: [VibenetAccountItem]) -> [VibenetPolicyCount] {
        let actors = items.flatMap(\.actors)
        guard !actors.isEmpty else { return [] }
        var out: [VibenetPolicyCount] = []
        let admins = actors.filter { $0.scope.isAdmin }.count
        if admins > 0 {
            out.append(VibenetPolicyCount(label: String(localized: "Admin"), count: admins))
        }
        for (bit, plain) in VibenetScope.orderedPlainBits {
            let n = actors.filter { !$0.scope.isAdmin && $0.scope.raw & bit != 0 }.count
            if n > 0 { out.append(VibenetPolicyCount(label: plain, count: n)) }
        }
        return out
    }
}

struct VibenetKeyAggregate: Equatable {
    let total: Int
    /// By kind, in the Keystore's OWN declared order (`sortRank`) — never
    /// alphabetical, and never "whichever kind this build happened to see
    /// first while walking the accounts", which depends on which account
    /// was iterated first and would make the identical room report a
    /// different-looking order across two composes.
    let byKind: [VibenetKeyKindCount]
    /// How many of the watched accounts contribute at least one key — an
    /// account holding none isn't counted, so "9 keys across 4 accounts"
    /// never claims a key for an account that authorized nothing.
    let accountCount: Int
    /// The soonest FUTURE expiry across the whole room, or nil when
    /// nothing is still ticking — `VibenetAccountItem.urgentLine`'s exact
    /// rule (`expiry == 0` never counts, an already-expired key never
    /// counts either), read once here rather than re-derived per caller.
    let soonestExpiry: VibenetKeySoonestExpiry?

    /// "9 keys authorized across 4 accounts" / "9 keys authorized" (one
    /// account) / "1 key authorized" — the room-wide count nowhere else on
    /// this card says.
    var plainLine: String {
        guard accountCount > 1 else {
            return total == 1 ? String(localized: "1 key authorized")
                              : String(localized: "\(total) keys authorized")
        }
        return String(localized: "\(total) keys authorized across \(accountCount) accounts")
    }
}

enum VibenetKeyAggregation {
    /// nil when the room draws no keys at all — an aggregate block with
    /// nothing to aggregate is exactly the kind of empty state this
    /// codebase omits rather than shows (§83), the same silence
    /// `VibenetRoom.note` already keeps for a room with no lead.
    static func compose(_ items: [VibenetAccountItem], now: Date) -> VibenetKeyAggregate? {
        let pairs = items.flatMap { item in item.actors.map { (item.address, $0) } }
        guard !pairs.isEmpty else { return nil }

        var counts: [VibenetAuthenticatorKind: Int] = [:]
        for (_, actor) in pairs { counts[actor.kind, default: 0] += 1 }
        let byKind = VibenetAuthenticatorKind.allCases
            .sorted { $0.sortRank < $1.sortRank }
            .compactMap { kind -> VibenetKeyKindCount? in
                guard let n = counts[kind], n > 0 else { return nil }
                return VibenetKeyKindCount(kind: kind, count: n)
            }

        let accountCount = items.filter { !$0.actors.isEmpty }.count

        let soonest = pairs
            .filter { $0.1.expiry > 0 && TimeInterval($0.1.expiry) > now.timeIntervalSince1970 }
            .min { a, b in
                if a.1.expiry != b.1.expiry { return a.1.expiry < b.1.expiry }
                let addr = a.0.localizedCaseInsensitiveCompare(b.0)
                if addr != .orderedSame { return addr == .orderedAscending }
                return a.1.actorId < b.1.actorId
            }
            .map { VibenetKeySoonestExpiry(address: $0.0, actor: $0.1) }

        return VibenetKeyAggregate(total: pairs.count, byKind: byKind,
                                    accountCount: accountCount, soonestExpiry: soonest)
    }
}

// MARK: - Balance aggregate (2026-08-24) — the feed room's own stat block

/// One symbol's TOTAL across every account that holds it — a named struct
/// for the same reason `VibenetTokenBalance` is: `Array` needs its element
/// Equatable, and a tuple never conforms.
struct VibenetTokenTotal: Equatable {
    let symbol: String
    let amount: Double
}

/// The unscoped feed room's own reading — "N accounts and balance", the
/// user's own words for the whole of what belongs there (mapping and
/// per-account detail moved OFF this room entirely, see `VibenetRoomCard`'s
/// own header doc). Distinct from `VibenetKeyAggregate` on purpose: this is
/// MONEY, that is KEYS, and the two are drawn in that order on the card
/// because that's the order the user asked for them in.
struct VibenetBalanceAggregate: Equatable {
    let accountCount: Int
    /// A real state, never printed at zero — see `plainLine`.
    let lockedCount: Int
    /// Sum of every item's OWN `nativeBalance` that landed a reading — nil
    /// when NOT ONE watched account has one, never a guessed 0 (§83): a
    /// room where every native read failed and a room genuinely holding
    /// zero must not look the same.
    let nativeTotal: Double?
    /// Per-symbol totals — summed WITHIN a symbol only (USDV with USDV,
    /// NFV with NFV), never across symbols and never combined with
    /// `nativeTotal`: different assets, no shared unit, the
    /// `PrivacyPoolsRoom`/`VibenetAccountItem.tokenBalances` rule reused
    /// at the room level. Sorted by symbol — TOTAL order, so the chip row
    /// can't reshuffle between opens depending on which account the walk
    /// reached first.
    let tokenTotals: [VibenetTokenTotal]

    /// "4 accounts" / "4 accounts · 1 locked" — `lockedCount == 0` is
    /// omitted entirely rather than printed as "· 0 locked": a real state
    /// (nothing is locked) is not the same as nothing to report, but zero
    /// is also not alarming enough to earn a clause on the room's own
    /// summary line (the row-level alarm badge already says so per row).
    var plainLine: String {
        var line = accountCount == 1
            ? String(localized: "1 account")
            : String(localized: "\(accountCount) accounts")
        if lockedCount > 0 {
            line += lockedCount == 1
                ? String(localized: " · 1 locked")
                : String(localized: " · \(lockedCount) locked")
        }
        return line
    }
}

enum VibenetBalanceAggregation {
    /// nil only when there are no accounts at all — every OTHER field is
    /// independently omittable by the view (no native reading anywhere,
    /// no token balance anywhere), which is why this returns a value even
    /// when both totals are empty: "N accounts" is still real information
    /// with nothing else to say yet.
    static func compose(_ items: [VibenetAccountItem]) -> VibenetBalanceAggregate? {
        guard !items.isEmpty else { return nil }
        let natives = items.compactMap(\.nativeBalance)
        let nativeTotal = natives.isEmpty ? nil : natives.reduce(0, +)
        var sums: [String: Double] = [:]
        for item in items {
            for balance in item.tokenBalances {
                sums[balance.symbol, default: 0] += balance.amount
            }
        }
        let tokenTotals = sums
            .map { VibenetTokenTotal(symbol: $0.key, amount: $0.value) }
            .sorted { $0.symbol < $1.symbol }
        return VibenetBalanceAggregate(
            accountCount: items.count, lockedCount: items.filter(\.alarmed).count,
            nativeTotal: nativeTotal, tokenTotals: tokenTotals)
    }
}

// MARK: - Multichain sync standing

/// `Keystore.getChangeSequences(address)`'s own three fields, in its own
/// declared order — how far THIS chain's copy of an account's config has
/// progressed. `multichain` is the count of changes applied off the
/// multichain channel (`chain_id = 0`, per the EIP's own spec — a config
/// change made there is meant to apply on every chain the account exists
/// on); `localEpoch`/`localSequence` are this chain's own local-only
/// history, which has no cross-chain meaning at all.
struct VibenetChangeSequences: Equatable, Codable {
    let multichain: UInt64
    let localEpoch: UInt32
    let localSequence: UInt32

    /// R2.3 — the footer's two number-hero chips, replacing a sentence that
    /// said nothing about THIS account. The wording is the whole of the
    /// EIP's own meaning for these two fields: `multichain` is changes
    /// applied off the cross-chain channel, `localSequence` is this
    /// chain's own count within the current epoch. Zero is a real reading
    /// and is never hidden — an account that has changed nothing yet says
    /// so, same as one that's changed a dozen times.
    var chips: [(value: String, label: String)] {
        [(String(multichain), String(localized: "cross-chain changes")),
         (String(localSequence), String(localized: "local, epoch \(localEpoch)"))]
    }

    /// The same two numbers as ONE English sentence, or nothing.
    ///
    /// The chips above are honest and unreadable: "0 cross-chain changes"
    /// and "1 local, epoch 0" are the EIP's vocabulary, not a person's,
    /// and one of them is usually a zero that means "this never happened"
    /// — a stat with no reading. What a person can actually use is
    /// whether this account's SETUP has been changed since it was made,
    /// and whether those changes were meant for every chain or only this
    /// one. Nil when both counts are zero: nothing has changed, and the
    /// history above already says when the keys arrived.
    var plainLine: String? {
        let local = Int(localSequence)
        let shared = Int(multichain)
        switch (shared, local) {
        case (0, 0):
            return nil
        case (0, let l):
            return l == 1
                ? String(localized: "Changed once, on this chain only")
                : String(localized: "Changed \(l) times, on this chain only")
        case (let s, 0):
            return s == 1
                ? String(localized: "Changed once, shared across chains")
                : String(localized: "Changed \(s) times, shared across chains")
        case (let s, let l):
            return String(localized: "Changed \(l) times here, \(s) shared across chains")
        }
    }
}

/// One chain's standing for one account — what `VibenetMultichainSync`
/// compares across.
struct VibenetChainStanding: Equatable {
    let chainName: String
    let sequences: VibenetChangeSequences
}

/// "Which chains haven't applied the account's latest multichain change
/// yet" — the team's own ask, and specified rather than guessed: EIP-8130
/// accounts can exist on several chains, a config change on the multichain
/// channel is meant to reach all of them, and `multichain` is exactly the
/// counter that says whether one has.
///
/// TODAY THIS IS HONESTLY A ONE-CHAIN READING. EIP-8130 runs on vibenet
/// (plus its own Sepolia testbed, which this app doesn't watch) — there is
/// no second LIVE chain a real account can be compared against yet. This
/// exists now, ready and correct, so that the day Cobalt puts the protocol
/// on a second chain, lighting it up is "read one more chain's standing and
/// append it to the array" — not a redesign. Never claims a sync gap it
/// cannot see: with fewer than two standings there is nothing to be behind,
/// so it says that in as many words rather than defaulting to a silent "all
/// caught up", which would be a claim about chains this build never read.
enum VibenetMultichainSync {
    static func summary(_ standings: [VibenetChainStanding]) -> String {
        guard standings.count > 1 else {
            return String(localized: "Only one EIP-8130 chain to compare — nothing to sync yet")
        }
        let leading = standings.map(\.sequences.multichain).max() ?? 0
        let behind = laggingChains(standings)
        guard !behind.isEmpty else {
            return String(localized: "Every chain has applied the latest multichain change (#\(leading))")
        }
        return behind.count == 1
            ? String(localized: "1 chain hasn't applied the latest multichain change yet")
            : String(localized: "\(behind.count) chains haven't applied the latest multichain change yet")
    }

    /// Chains strictly behind the leading `multichain` count — empty (never
    /// guessed at) below two standings, the same honesty rule as `summary`.
    static func laggingChains(_ standings: [VibenetChainStanding]) -> [VibenetChainStanding] {
        guard standings.count > 1 else { return [] }
        let leading = standings.map(\.sequences.multichain).max() ?? 0
        return standings.filter { $0.sequences.multichain < leading }
    }
}

// MARK: - Landed events (the feed's own door into this room)

/// The three `Keystore` events worth landing as a `Thing` — the
/// `WalletApprovals` shape, applied here for the first time. Everything
/// else this room reads is pure live state and is never landed (see the
/// model file's own header doc for why); these three are different in kind,
/// not degree: a NEW key gaining the power to act for a watched account, a
/// key losing it, or the account locking outright, are each a security-
/// relevant CHANGE worth surfacing even to someone who never reopens this
/// screen — exactly the argument that already justifies landing a token
/// approval.
enum VibenetEventKind: Equatable {
    case actorAuthorized
    case actorRevoked
    case locked
    /// An unlock has BEGUN — the timelock is running and the account
    /// becomes spendable when it elapses. `getLockStatus` already reports
    /// this as state, but state is only seen by someone standing in the
    /// room; the event is what reaches a feed somebody scrolls, and of
    /// everything a locked account can do this is the one worth arriving.
    case unlockInitiated

    /// `keyLabel` is the resolved kind ("secp256k1 key") when the live
    /// re-read at landing time could confirm it, nil when the actor was
    /// already gone by the time this ran (revoked-then-landed in the same
    /// pass) — the title still lands, just without a kind it can't prove.
    func title(shortAddress: String, keyLabel: String?) -> String {
        switch self {
        case .actorAuthorized:
            if let keyLabel {
                return String(localized: "New \(keyLabel) authorized for \(shortAddress)")
            }
            return String(localized: "New key authorized for \(shortAddress)")
        case .actorRevoked:
            return String(localized: "Key revoked for \(shortAddress)")
        case .locked:
            return String(localized: "\(shortAddress) locked on vibenet")
        case .unlockInitiated:
            return String(localized: "\(shortAddress) started unlocking on vibenet")
        }
    }

    /// The `sourceRef` namespace this event lands under. ONE constant per
    /// kind, read by both the stamp and anything matching rows back — the
    /// §311 lesson, where a room head matched `privacypools:deposit:` while
    /// deposits landed `privacypools:dep:`, so every row read Pending for
    /// life and the room simply went quiet.
    var refSegment: String {
        switch self {
        case .actorAuthorized, .actorRevoked: return "actor"
        case .locked: return "locked"
        case .unlockInitiated: return "unlocking"
        }
    }

    /// The same event with NO address in it — what a row says when the
    /// face and name beside it have already said who (R4.2).
    ///
    /// Two strings rather than one renamed, and the split is load-bearing:
    /// `title` above is what the All feed, search, Spotlight and a
    /// notification show, none of which carries a face, so it has to
    /// stand alone and keep naming the account. Inside the vibenet room
    /// the row leads with the account's own face and name, and repeating
    /// the address in the line beneath is §366's "read its first line
    /// twice" — the same fact, twice, one line apart.
    func phrase(keyLabel: String?) -> String {
        switch self {
        case .actorAuthorized:
            if let keyLabel {
                return String(localized: "New \(keyLabel) authorized")
            }
            return String(localized: "New key authorized")
        case .actorRevoked:
            return String(localized: "Key revoked")
        case .locked:
            return String(localized: "Locked on vibenet")
        case .unlockInitiated:
            return String(localized: "Unlock started")
        }
    }
}
