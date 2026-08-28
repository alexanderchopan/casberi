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
    /// offers no plain phrasing, so this label is this app's own reading.
    ///
    /// **"Order its own sends", was "Send in order" (user ruling, prd §491).**
    /// That earlier wording had the polarity backwards: NONCE is a PERMISSION
    /// to sequence — a key holding it may use sequenced `nonce_key`s, a key
    /// without it is confined to nonce-free mode — and "Send in order" reads
    /// as a restriction the key is under rather than a capability it has. The
    /// four bits beside it all name capabilities, so one written as a
    /// constraint reads as the odd one out and is understood as the opposite
    /// of what it grants. This entry stays the one open to a better ruling,
    /// since the spec still supplies no phrasing of its own.
    private static let named: [(bit: UInt16, label: String, plain: String)] = [
        (sender,       "Sender",        "Send anywhere"),
        (policy,       "Policy",        "Send to one contract"),
        (nonce,        "Nonce",         "Order its own sends"),
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
        // **"Passkey" — never "WebAuthn"** (user ruling, prd §491: *"passkey
        // is fine, don't say webauthn"*). It is the word Apple puts in front of
        // people and the one they already know; WebAuthn is the spec behind it
        // and belongs in this comment rather than on a row. The curve names
        // above are technical because there is no plainer word for a curve —
        // this one has a plainer word, so it uses it.
        case .webAuthn:  String(localized: "Passkey")
        case .delegate:  String(localized: "Delegate")
        case .custom:    String(localized: "Custom authenticator")
        }
    }

    /// What a person calls this, not what the spec calls it — the
    /// single-key sentence's own title. Each line is the WHOLE claim this
    /// build is willing to make; nothing here is embellished past what the
    /// chain itself proves.
    ///
    /// **secp256k1 IS ITS PLAIN NAME (user ruling, prd §491: *"we can't call
    /// it wallet key, it should be like secp256 key or whatever the different
    /// keys are"*).** It read "Wallet key", which was wrong twice over. It
    /// collided with the room next door — an app whose other half is literally
    /// called Wallet, so a key type named after it reads as belonging there —
    /// and it disagreed with `label`, which has always said "secp256k1 key" and
    /// is what the LIVE READ uses: `VibenetBridge` composes every event title
    /// from `actor.kind.label`, so the chain's own events already said
    /// secp256k1 while this said Wallet. One key type, two names, depending on
    /// which surface you were looking at.
    ///
    /// The other four are unchanged: a passkey is a passkey to everyone, and
    /// `.delegate`'s "Another contract" is a different axis — plain English for
    /// something with no user-facing name — not a spec name withheld.
    var plainTitle: String {
        switch self {
        case .secp256k1: String(localized: "secp256k1 key")
        case .p256:      String(localized: "P-256 key")
        case .webAuthn:  String(localized: "Passkey")
        case .delegate:  String(localized: "Another contract")
        case .custom:    String(localized: "Custom authenticator")
        }
    }

    /// THE MARK a key row leads with (prd §495, user: *"for the icons we just
    /// add plus or locked symbol like we are elsewhere and whatever icons we
    /// need for other verbs. we don't need some emoji"*).
    ///
    /// An SF Symbol in a tinted square, the same grammar `VibenetEventRow`
    /// uses for an event's kind and every `BandRow` uses for a source — the
    /// Permissions rows were the one list in this room leading with nothing.
    ///
    /// **Each of these is a FACT this app already states in words, not a
    /// glyph invented to fill the column.** `faceid` because a passkey IS
    /// Face ID, Touch ID or a security key (`plainDetail` says exactly that);
    /// `link` because a delegate is a contract signing for this account; `key`
    /// for the two raw curves, which are keys and nothing more interesting.
    /// A key we cannot identify gets NO mark rather than a generic one — the
    /// same rule `VibenetEventRow` follows for an unfaceted event, and the
    /// reason `custom` is nil here rather than falling back to `key`.
    ///
    /// **No colour.** §490 ruled that ink in this room marks UNBOUNDEDNESS
    /// and nothing else, and an admin key already says so with its own chip;
    /// tinting the mark would either repeat that chip or contradict it.
    var markSymbol: String? {
        switch self {
        case .secp256k1, .p256: "key"
        case .webAuthn:         "faceid"
        case .delegate:         "link"
        case .custom:           nil
        }
    }

    /// The technical name plus one honest clause — nil where there is
    /// nothing certain to add. `.p256` names the CURVE only, never where a
    /// particular key happens to live (a passkey and a raw P-256 key are
    /// both possible and this build cannot tell them apart).
    var plainDetail: String? {
        switch self {
        // **NO CURVE NAME HERE** (prd §495). This is drawn directly under
        // `plainTitle`, which is "secp256k1 key", at all three of its call
        // sites — so the prefix set the word twice one line apart, §366's
        // read-its-first-line-twice. The other three cases never had one.
        case .secp256k1: String(localized: "the standard Ethereum key")
        case .p256:      String(localized: "the curve passkeys and secure enclaves use")
        // The spec's name is cut (user, prd §491: *"don't say webauthn"*).
        // What is left is the whole of what a person needs: the three things
        // that actually unlock it.
        case .webAuthn:  String(localized: "Face ID, Touch ID, or a security key")
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
    /// WHICH KEY this moment is about (2026-08-25, prd §473).
    ///
    /// The strip above this only ever needed the SHAPE of an account's
    /// history — how many moments, in what order, which way — so it threw the
    /// id away. That is also why a key could say everything about itself
    /// except when it began: the account's history knew, and nothing could ask
    /// it about one key.
    ///
    /// **Optional, and that is load-bearing**: this type is `Codable` and
    /// persisted inside `VibenetAccountItem` in `VibenetState`, Swift
    /// synthesises `decodeIfPresent`, and a non-Optional addition would fail
    /// the decode of the WHOLE room on every device that already has a
    /// snapshot — the `RSSStore.Feed` trap, which this file has now paid for
    /// three times. nil means "landed by an earlier build", which reads as a
    /// key whose beginning we cannot name; the row says nothing rather than
    /// guessing.
    var actorId: String? = nil
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
        guard let clock = expiryClock(now: now) else {
            return String(localized: "Expired \(expiresAt.formatted(.dateTime.month(.abbreviated).day()))")
        }
        return String(localized: "Expires \(clock)")
    }

    /// THE EXPIRY AS A LABEL-COLUMN VALUE (prd §495) — what sits beside a
    /// row whose LABEL is already the word "Expires".
    ///
    /// A third form beside `expiryLabel` and `expiryClock`, and the split is
    /// the same one `VibenetEventKind` makes between `title` and `phrase`:
    /// `expiryLabel` has to stand alone ("Expires in 3 days") because it is
    /// drawn where nothing else says what the date is for, and the key
    /// sheet's Terms table used it under a label reading "Expires" — so the
    /// row read "Expires · Expires in 3 days".
    ///
    /// Never just `expiryClock`: that returns nil for a key with no expiry
    /// and for one already gone, and a blank value beside "Expires" is worse
    /// than either fact.
    func expiryValue(now: Date) -> String {
        guard expiry > 0 else { return String(localized: "Never") }
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(expiry))
        guard let clock = expiryClock(now: now) else {
            return String(localized: "Expired \(expiresAt.formatted(.dateTime.month(.abbreviated).day()))")
        }
        return clock
    }

    /// THE CLOCK ALONE — "in 3 days", "tomorrow" — with no verb in front of
    /// it (prd §482). A row whose title already says *Key expiring* must not
    /// then say *Expires in 3 days* beside it, and a trailing slot has no
    /// room for the verb anyway.
    ///
    /// `expiryLabel` COMPOSES FROM THIS rather than formatting its own date,
    /// so the sentence and the trailing figure can never name different
    /// moments — the one-derivation rule this file already holds everywhere a
    /// reading is drawn twice. nil for a key that never expires and for one
    /// already expired: neither is a countdown, and both are said in words by
    /// the label instead.
    func expiryClock(now: Date) -> String? {
        guard expiry > 0 else { return nil }
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(expiry))
        guard expiresAt > now else { return nil }
        return expiresAt.formatted(.relative(presentation: .named))
    }

    /// WHICH contract a gated key may call — the half "Send to one contract"
    /// could never say (prd §463). Named when the config recognises it, short
    /// address otherwise, and nil when the key is not gated at all or the
    /// manager did not read: a gated key that cannot name its target still
    /// says it is gated, via its chip, rather than being handed a guess.
    func policyLine(known: VibenetKnownPolicyManagers) -> String? {
        guard let target = policyTarget(known: known) else { return nil }
        return String(localized: "Limited to \(target)")
    }

    /// The contract's name, or its short address — the same reading WITHOUT
    /// its preposition, for a label/value row whose label already carries one
    /// (prd §471). `policyLine` composes from this, so the two forms can never
    /// name different contracts and no caller ever parses a target back out of
    /// a localized sentence.
    func policyTarget(known: VibenetKnownPolicyManagers) -> String? {
        guard scope.raw & VibenetScope.policy != 0, let manager = policyManager else { return nil }
        return known.name(for: manager) ?? VibenetRoom.shortAddress(manager)
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

    /// Does this key still have a clock running — a REAL expiry, still ahead?
    ///
    /// ONE DEFINITION (2026-08-25, prd §471), read by `VibenetKeyAggregation`'s
    /// soonest-expiry reading and by `VibenetKeyShelf`'s bars alike. It was
    /// written out longhand in both, and two copies of one rule is how a card
    /// and the figure beneath it come to disagree about which keys are ticking
    /// — the §418 duplicate-parser lesson at the scale of a predicate. The
    /// harness caught it the moment the second copy landed: `mutate` replaces
    /// the FIRST occurrence, so breaking the rule silently mutated the shelf
    /// while the assertion watched the aggregate, and a real check went green
    /// over a real defect.
    ///
    /// Both halves are load-bearing. `expiry == 0` is Keystore's own "never"
    /// and is not a date at all, so folding it in reports a key that can never
    /// lapse as the most urgent thing in the room; and an ALREADY-LAPSED key
    /// is not something ahead — each account's `urgentLine` counts those.
    func isTicking(now: Date) -> Bool {
        expiry > 0 && TimeInterval(expiry) > now.timeIntervalSince1970
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
        guard let clock = unlockClock(now: now) else { return String(localized: "Unlock ready") }
        return String(localized: "Unlocks \(clock)")
    }

    /// The unlock's clock alone, `expiryClock`'s twin (prd §482) — and nil
    /// once the timelock is up, because "ready" is a state rather than a
    /// countdown. `unlockLabel` composes from it for the same reason.
    func unlockClock(now: Date) -> String? {
        guard let unlocksAt, unlocksAt > 0 else { return nil }
        let at = Date(timeIntervalSince1970: TimeInterval(unlocksAt))
        guard at > now else { return nil }
        return at.formatted(.relative(presentation: .named))
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
    /// WHEN THIS ROOM WAS READ, and the reason it exists is a defect this
    /// feature shipped with: `VibenetState` persists the last composed room
    /// and `FeedScreen`'s head draws it synchronously on every scroll, while
    /// `VibenetRoomSource.compose()` returns early WITHOUT saving when the
    /// config fetch fails — so a device that has been offline for three days
    /// keeps drawing the last good snapshot, complete with its confident "As
    /// of vibenet's main branch, commit a9ae95e1b" provenance, and a lock
    /// state read on Tuesday is pixel-identical to one read a second ago.
    /// That is the §83 fake status on the one network whose entire premise is
    /// that it moves under you.
    ///
    /// The provenance line was never this: it names the CONTRACTS' commit,
    /// which says what the chain was when we looked and nothing about when
    /// that was. `TodayBrief`'s "as of Xh ago" and `ASCStanding.observed` are
    /// the app's own precedents for the distinction.
    ///
    /// OPTIONAL, and load-bearing rather than tidy — this type is `Codable`
    /// and persisted, and Swift synthesises `decodeIfPresent` for an
    /// Optional, so every snapshot already on a device decodes with this as
    /// nil rather than failing the decode of the whole room (the
    /// `RSSStore.Feed` trap, third time in this file). A nil reads as "we
    /// don't know when", which is honest and survives exactly one foreground:
    /// the next composed read stamps it.
    let readAt: Date?

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
            redeployedSinceLastSeen: redeployedSinceLastSeen, readAt: readAt)
    }

    /// `readAt` DEFAULTS TO NIL rather than to `.now`, deliberately: a
    /// default of "now" would let a room composed from nothing — the empty
    /// placeholder two screens build before their first read — claim to be a
    /// fresh reading of the chain. The one call site that has really just
    /// read passes it, and `vibenet-selftest.sh` guards that it still does.
    static func compose(items raw: [VibenetAccountItem], branch: String?, commit: String?,
                         configReached: Bool, redeployedSinceLastSeen: Bool = false,
                         readAt: Date? = nil) -> VibenetRoom {
        VibenetRoom(items: ordered(raw), branch: branch, commit: commit, configReached: configReached,
                    redeployedSinceLastSeen: redeployedSinceLastSeen, readAt: readAt)
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
    static func note(_ room: VibenetRoom, drawn: Int, now: Date = .now) -> String? {
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
        // WHEN, after WHAT — the commit says what the chain was, this says
        // how long ago we looked, and only the pair is a provenance. Last in
        // the join because it is the clause that changes between draws.
        if let age = freshnessLine(room, now: now) { parts.append(age) }
        return parts.joined(separator: " · ")
    }

    /// A stale snapshot is only worth saying once it is old enough that the
    /// chain could plausibly have moved under it — under this, the card is
    /// simply current and a timestamp is noise on a caption already carrying
    /// two clauses. Forty-five minutes rather than an hour so a room read at
    /// the top of the hour does not read as fresh for fifty-nine more
    /// minutes; the wording below is in whole hours regardless.
    static let freshnessFloor: TimeInterval = 45 * 60

    /// "read 3h ago" / "read yesterday" / "read Mar 3" — nil while the read
    /// is recent, and nil when there is no `readAt` at all (a snapshot
    /// written by a build before that field existed; see the property's own
    /// doc for why that state survives exactly one foreground).
    ///
    /// NEVER a relative-date formatter: `Date.formatted(.relative)` renders
    /// a 46-minute-old read as "in 1 hour" at some rounding boundaries and
    /// this caption's whole job is to be unambiguous about the past.
    /// A read stamped in the FUTURE — a device whose clock moved backwards
    /// between the read and the draw — reads as nothing rather than as a
    /// negative age.
    static func freshnessLine(_ room: VibenetRoom, now: Date) -> String? {
        guard let readAt = room.readAt else { return nil }
        let age = now.timeIntervalSince(readAt)
        guard age >= freshnessFloor else { return nil }
        // ROUNDED, never truncated, and floored at one: the freshness floor
        // is 45 minutes, so a straight `Int(age / 3600)` prints "read 0h ago"
        // for every read between 45 and 60 minutes old — a caption that says
        // a room is both stale and zero hours old.
        let hours = max(1, Int((age / 3_600).rounded()))
        if hours < 24 { return String(localized: "read \(hours)h ago") }
        let days = hours / 24
        if days == 1 { return String(localized: "read yesterday") }
        if days < 7 { return String(localized: "read \(days) days ago") }
        return String(localized: "read \(readAt.formatted(.dateTime.month(.abbreviated).day()))")
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
                // The ids are the fixture's OWN actors (prd §473), so the
                // expanded key row can find its beginning in demo mode — a
                // block that only ever draws over real chain history is one
                // `verify.sh`'s demo coverage can never see.
                VibenetKeyMoment(block: 100, logIndex: 0, authorized: true, kind: .secp256k1,
                                 date: Date.now.addingTimeInterval(-40 * 86_400),
                                 actorId: "0x0000000000000000000000002b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c"),
                VibenetKeyMoment(block: 220, logIndex: 0, authorized: true, kind: .p256,
                                 date: Date.now.addingTimeInterval(-12 * 86_400),
                                 actorId: "0x0000000000000000000000000000000000000000000000000000000000000008"),
                VibenetKeyMoment(block: 220, logIndex: 1, authorized: false, kind: nil,
                                 date: Date.now.addingTimeInterval(-12 * 86_400)),
                VibenetKeyMoment(block: 340, logIndex: 0, authorized: true, kind: .webAuthn,
                                 date: Date.now.addingTimeInterval(-2 * 86_400),
                                 actorId: "0x0000000000000000000000000000000000000000000000000000000000000005"),
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
            // **THE UNLOCK ACTUALLY LANDS IN THE DEMO (2026-08-25, prd §479).**
            // This was pinned to 4_102_444_800 — the year 2100 — so the
            // countdown ticked forever and the moment §479 built (the bar
            // filling, the words landing, the one haptic) could not occur in
            // the demo at all: the branch that draws it was unreachable by
            // construction, which is precisely the demo-parity gap
            // `demo-selftest`'s own checks exist to catch.
            //
            // Ninety seconds out, computed live like every other date in this
            // fixture. Someone who opens the demo's unlocking account and
            // stays on it watches a timelock open, which is the one thing
            // this room can show that no other room in the app can. The
            // progress bar is honest for the whole run — `unlockDelay` is the
            // real span and `unlockProgress` reads both endpoints — and after
            // it lands the account reads "Ready to unlock", which is a true
            // statement about a fixture whose delay has elapsed.
            locked: true, hasInitiatedUnlock: true,
            unlocksAt: UInt64(Date.now.addingTimeInterval(90).timeIntervalSince1970),
            unlockDelay: 43_200,
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

        // `readAt: .now` — the fixture stands in for a read that just
        // happened (`VibenetRoomSource.compose` returns this INSTEAD of
        // touching the network), so anything less would make the demo's own
        // room draw a staleness note about a read it never made.
        return compose(items: [rich, lockedPlain, unlocking, notEstablishedYet],
                        branch: "main", commit: "a9ae95e1bdemo",
                        configReached: true, redeployedSinceLastSeen: true, readAt: .now)
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
        guard let target = sharedTarget(name: name) else { return nil }
        return String(localized: "Also authorized on \(target)")
    }

    /// "Ops" / "2 other accounts" — the same reading WITHOUT its preposition,
    /// for a label/value row whose label already carries one (prd §471,
    /// `VibenetAccountDetail.termRows`). `sharedLine` composes from this
    /// rather than restating it, so the sentence form and the table form can
    /// never name different accounts — and a caller wanting the value never
    /// has to parse it back out of a localized sentence, which is
    /// `MoneyReceipt`'s standing rule in this codebase.
    func sharedTarget(name: (String) -> String) -> String? {
        guard !isEmpty else { return nil }
        if count == 1, let only = first { return name(only.account) }
        return String(localized: "\(count) other accounts")
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

    /// The move in ETH — last minus first over the very series the line draws
    /// (2026-08-25, prd §475).
    ///
    /// Wallet states its move as "▲ $224.51 (1.8%) today", figure first, and
    /// its own note gives the reason this exists: the dollars "come from the
    /// plotted series (last − first), never from a second source: the line is
    /// what the reader is looking at, so any other derivation could contradict
    /// it on screen." Same rule here, in ETH.
    ///
    /// **Gated on `delta` rather than computed independently**, so the amount
    /// and the percentage can never disagree about whether a move happened at
    /// all: a change under `delta`'s own floor has no direction to report, and
    /// an amount printed beside no percentage would be exactly that claim.
    static func move(_ samples: [VibenetValueSample]) -> Double? {
        guard delta(samples) != nil,
              let first = samples.first?.native, let last = samples.last?.native
        else { return nil }
        return last - first
    }
}

/// ONE THING THAT NEEDS YOU, AT THE TOP (2026-08-25, prd §479).
///
/// **The room's urgency was scattered across four surfaces** and none of them
/// was the first thing you saw: a key about to expire lived in the Keys
/// card's footer (below a census and a headline), "Locked" was a pill on an
/// Accounts row, an unlock countdown was that row's subtitle, and an
/// unreached read was a footnote under the crown. So the question somebody
/// opens this room with — *is anything wrong?* — took a scroll and four
/// different readings to answer.
///
/// This is Wallet's own "Worth a look" applied here (`WalletWarningsStrip`,
/// prd §212): what's it worth and is it okay are the two questions one glance
/// asks, and they belong together. Same rules as that strip, deliberately:
///
/// - **Silent when there is nothing to say.** No empty state, no "all clear"
///   — a room with nothing wrong simply does not draw this. An all-clear
///   badge is a claim this read cannot support anyway (an unreached account
///   is not known to be fine).
/// - **It never invents urgency.** Every line here is a fact some other
///   surface already states; this only promotes it. Two readings of one fact
///   cannot drift, because both compose from the same accessors.
/// - **It states, it does not grade.** No severity colour per row — the room
///   spends its one colour on expiry urgency and nothing else (§463), and a
///   locked account is not an emergency, it is a state.
///
/// RANKED, and the order is the argument: something that needs a DECISION
/// from you outranks something merely happening to you, and a thing with a
/// clock outranks a thing without one.
enum VibenetAttention {
    /// What a line is about — the caller uses this to route the tap, never to
    /// colour the row.
    enum Subject: Equatable {
        /// A key inside its urgency window, on this account.
        case key(address: String, actorId: String)
        /// This account is locked, or unlocking.
        case account(address: String)
        /// The read did not reach the chain for this many accounts.
        case unreached(count: Int)
    }

    struct Line: Equatable, Identifiable {
        let subject: Subject
        /// The whole sentence, composed from the model's own words.
        ///
        /// **Still the whole reading, and still load-bearing** (prd §482):
        /// the parts below are how the row is DRAWN, this is what VoiceOver
        /// speaks, so a person who cannot see the three columns still gets
        /// one sentence rather than three fragments read out in a row.
        let text: String
        /// What happened, in the row's own ink — "Key expiring", "Locked".
        /// A state, never a grade: §479's rule that this strip states rather
        /// than grades is why none of these is an imperative.
        let title: String
        /// Which account, and the qualifier that makes the title specific —
        /// "Wallet key · …0b1c". nil where the line has no account to name
        /// (the unreached read is about US, not about an address).
        let detail: String?
        /// The countdown, or nil where the line has none. The ONLY place a
        /// row spends colour, and only when `urgent` — §463 spends this
        /// room's one colour on expiry urgency and nothing else, so a lock
        /// with a clock on it gets the figure and not the tint.
        let clock: String?
        /// Whether `clock` is the expiry urgency §463 governs. Never true
        /// for a lock, an unlock or an unreached read: a locked account is a
        /// state, not an alarm.
        let urgent: Bool
        /// Sorting only — never drawn, and never mapped to a colour.
        let rank: Int
        var id: String {
            switch subject {
            case .key(let a, let k):  return "key:\(a.lowercased()):\(k.lowercased())"
            case .account(let a):     return "account:\(a.lowercased())"
            case .unreached:          return "unreached"
            }
        }
    }

    /// At most this many lines. A strip that can grow without bound is a
    /// second feed, and the point of this one is that it is glanceable — the
    /// overflow is COUNTED rather than dropped (`tail`), the way every capped
    /// reading in this app says what it did not draw.
    static let rowCap = 3

    /// Every account whose keys are inside `urgencyWindow`, whose lock needs
    /// reading, or whose read failed — ranked, capped, and empty when the
    /// room is quiet.
    static func compose(_ items: [VibenetAccountItem], now: Date) -> [Line] {
        var out: [Line] = []

        // RANK 3 — a key about to expire. The only line with a real deadline
        // and the only one you can lose something by ignoring: when it
        // lapses, whatever that key was doing stops.
        for item in items {
            // `actors` is already in `orderedActors`' own order (the init
            // sorts it), so this walk is stable without re-sorting.
            for actor in item.actors where actor.expiryStanding(now: now) == .soon {
                let clock = actor.expiryClock(now: now)
                out.append(Line(
                    subject: .key(address: item.address, actorId: actor.actorId),
                    text: String(localized: "\(actor.kind.plainTitle) on \(VibenetRoom.shortAddress(item.address)) — \(actor.expiryLabel(now: now).lowercased())"),
                    title: String(localized: "Key expiring"),
                    detail: String(localized: "\(actor.kind.plainTitle) · \(VibenetRoom.shortAddress(item.address))"),
                    clock: clock,
                    // The one urgency this room tints (§463). Only ever true
                    // here, and only when there really is a countdown to
                    // tint — a key inside the window whose clock could not
                    // be read gets the row and not the colour.
                    urgent: clock != nil,
                    rank: 3))
            }
        }

        // RANK 2 — an account mid-unlock. It has a clock, and the moment it
        // reaches zero something becomes possible that was not before.
        // RANK 1 — locked with no unlock started: a state, not a countdown.
        for item in items where item.alarmed {
            if item.hasInitiatedUnlock {
                let phrase = item.unlockLabel(now: now) ?? String(localized: "Ready to unlock")
                out.append(Line(subject: .account(address: item.address),
                                text: String(localized: "\(VibenetRoom.shortAddress(item.address)) — \(phrase.lowercased())"),
                                title: String(localized: "Unlocking"),
                                detail: VibenetRoom.shortAddress(item.address),
                                // nil once the timelock is up: "ready" is a
                                // state and belongs in the title, not in a
                                // slot whose whole meaning is "time left".
                                clock: item.unlockClock(now: now),
                                urgent: false,
                                rank: 2))
            } else {
                out.append(Line(subject: .account(address: item.address),
                                text: String(localized: "\(VibenetRoom.shortAddress(item.address)) is locked"),
                                title: String(localized: "Locked"),
                                // The qualifier is what separates this row
                                // from the one above it at a glance: both
                                // say a lock, only one of them is moving.
                                detail: String(localized: "\(VibenetRoom.shortAddress(item.address)) · no unlock started"),
                                clock: nil,
                                urgent: false,
                                rank: 1))
            }
        }

        // RANK 0 — what we could not see. LAST on purpose: it is the one line
        // that is about US rather than about the account, and promoting a
        // network problem above a key that expires tomorrow would be this
        // strip grading its own failure as the reader's most urgent business.
        let unreached = items.filter { !$0.reached }.count
        if unreached > 0 {
            out.append(Line(
                subject: .unreached(count: unreached),
                text: unreached == 1
                    ? String(localized: "1 account couldn't be read")
                    : String(localized: "\(unreached) accounts couldn't be read"),
                title: String(localized: "Couldn't be read"),
                // COUNTED, never named. Several accounts can fail one pass
                // and they fail it for one reason; naming the first would
                // make a network problem look like one address's fault.
                detail: unreached == 1
                    ? String(localized: "1 account")
                    : String(localized: "\(unreached) accounts"),
                clock: nil,
                urgent: false,
                rank: 0))
        }

        // TOTAL order — rank, then the line itself, so a room with two keys
        // expiring the same day draws them in a stable order rather than in
        // whichever order the accounts happened to be walked.
        return out.sorted { a, b in
            if a.rank != b.rank { return a.rank > b.rank }
            return a.text.localizedCaseInsensitiveCompare(b.text) == .orderedAscending
        }
    }

    /// The drawn lines, capped.
    static func drawn(_ lines: [Line]) -> [Line] { Array(lines.prefix(rowCap)) }

    /// "and 2 more" — what the cap did not draw, or nothing. Counted rather
    /// than dropped, so a strip showing three of five never reads as a room
    /// with three things to answer.
    static func tail(_ lines: [Line]) -> String? {
        let hidden = lines.count - rowCap
        guard hidden > 0 else { return nil }
        return hidden == 1
            ? String(localized: "and 1 more")
            : String(localized: "and \(hidden) more")
    }
}

/// HOW FAR BACK THE CURVE LOOKS (2026-08-25, prd §479).
///
/// `VibenetValueStore` has kept real per-account history since §467 and the
/// chart only ever drew "since watching" — the whole book, however long that
/// is. A range control is what turns a line into something you can ask a
/// question of, and every reading it produces is REAL: this windows the
/// samples already on disk and never resamples, interpolates or invents a
/// point between two looks.
///
/// **A range is OFFERED only when it would draw a different line** (`options`
/// below). A "1W" chip on a book three days old is a control that changes
/// nothing — §83's dead control, wearing a time label.
enum VibenetChartRange: String, CaseIterable, Equatable {
    case week, month, all

    /// The label the chip carries. "All" rather than "Max": this book starts
    /// when you began watching, so "Max" would claim a history that predates
    /// us.
    var label: String {
        switch self {
        case .week:  return String(localized: "1W")
        case .month: return String(localized: "1M")
        case .all:   return String(localized: "All")
        }
    }

    /// How far back this range reaches, or nil for the whole book.
    var span: TimeInterval? {
        switch self {
        case .week:  return 7 * 86_400
        case .month: return 30 * 86_400
        case .all:   return nil
        }
    }

    /// What the chart's own subline says the move is measured over — the
    /// crown's delta is computed on the WINDOWED series, so the sentence
    /// beside it has to name the same window or the two disagree on screen.
    var sinceLine: String {
        switch self {
        case .week:  return String(localized: "past week")
        case .month: return String(localized: "past month")
        case .all:   return String(localized: "since watching")
        }
    }
}

extension VibenetValueHistory {
    /// The samples inside a range, oldest first.
    ///
    /// **Never fewer than two when the book has two** — a window that cuts the
    /// series down to one point would draw nothing (`series`' own rule), so a
    /// range holding one reading falls back to the two newest. The line stays
    /// honest either way: both points are real readings, and the only thing
    /// the fallback changes is that the leftmost point may predate the window
    /// the chip names, which is the truthful shape of "you have one reading
    /// this week".
    static func windowed(_ samples: [VibenetValueSample],
                         range: VibenetChartRange,
                         now: Date) -> [VibenetValueSample] {
        guard let span = range.span else { return samples }
        let floor = now.addingTimeInterval(-span)
        let inside = samples.filter { $0.at >= floor }
        if inside.count >= 2 { return inside }
        return Array(samples.suffix(2))
    }

    /// WHICH RANGES ARE WORTH OFFERING, given the book.
    ///
    /// A range earns a chip only when it holds at least two readings of its
    /// own AND draws a different span from the next one up — otherwise "1W"
    /// and "1M" and "All" are three chips drawing one identical line, which is
    /// three dead controls rather than one.
    ///
    /// Returns EMPTY when there is nothing to choose between, and the caller
    /// then draws no strip at all rather than a lone "All" chip that does
    /// nothing.
    static func options(_ samples: [VibenetValueSample], now: Date) -> [VibenetChartRange] {
        guard samples.count >= 2, let oldest = samples.first?.at else { return [] }
        let coveredBy = now.timeIntervalSince(oldest)
        var out: [VibenetChartRange] = []
        for range in [VibenetChartRange.week, .month] {
            guard let span = range.span else { continue }
            // Its own window must hold two readings…
            guard windowed(samples, range: range, now: now).count >= 2 else { continue }
            // …and the book must reach PAST it, or this range and "All" are
            // the same line under two names.
            guard coveredBy > span else { continue }
            out.append(range)
        }
        guard !out.isEmpty else { return [] }
        out.append(.all)
        return out
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

    /// How far apart the demo's readings sit.
    ///
    /// **It is NOT `VibenetValueHistory.throttle` any more (2026-08-25, prd
    /// §479), and the old comment claiming it was `a fortnight` was wrong
    /// arithmetic**: fourteen points four hours apart is 52 HOURS, about two
    /// days. That went unnoticed while the chart had one fixed window — and
    /// the moment a range control existed it mattered, because
    /// `VibenetValueHistory.options` offers a range only when the book
    /// reaches past it, so a two-day book offers nothing and the demo drew no
    /// strip at all while a real month-old room drew three chips.
    ///
    /// 36 hours over 30 readings is ~45 days: enough that 1W and 1M each hold
    /// several readings of their own and each draws a visibly different line,
    /// which is the whole condition `options` tests for.
    static let spacing: TimeInterval = 36 * 3600

    /// Deterministic — no randomness, so two demo entries draw the identical
    /// line. The dips are what keep it reading as a balance rather than a
    /// ramp, and the last stretch is deliberately busier so a 1W window has
    /// its own shape rather than being a straight run into the final point.
    static func samples(now: Date) -> [VibenetValueSample] {
        samples(endingOn: endsOn, now: now)
    }

    /// The same curve scaled to end on a given balance — what a single
    /// account's own history looks like in the demo. Scaled rather than
    /// re-shaped so every account's line is recognisably the same family of
    /// object, and so each one still ends on the figure its own crown states.
    static func samples(endingOn end: Double, now: Date) -> [VibenetValueSample] {
        let shape: [Double] = [0.72, 0.78, 0.74, 0.95, 1.10, 1.04, 1.32,
                               1.55, 1.49, 1.78, 2.05, 1.98, 2.31, 2.16,
                               2.42, 2.28, 2.55, 2.71, 2.60, 2.88, 2.74,
                               2.96, 3.12, 2.99, 3.24, 3.08, 3.31, 3.18,
                               3.36, 1.0]
        return shape.enumerated().map { index, factor in
            VibenetValueSample(
                at: now.addingTimeInterval(-Double(shape.count - 1 - index) * spacing),
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
        // **A LONE CELL IS RETURNED, and the caller decides (2026-08-27).**
        //
        // This used to `guard out.count > 1 else { return [] }`, and the
        // reason it gave was a fact about ONE caller's layout: a single
        // rectangle "repeats the crown directly above it". That was true of
        // `holdingsCard`, which sits under the crown — and false everywhere
        // else, because §491 took the total OFF the promoted Holdings scope
        // (the scope REPLACES the crown rather than sitting under it), so
        // there is nothing above it to repeat.
        //
        // Suppressing here therefore emptied the scope for any account
        // holding exactly one asset: the figure drew nothing, and
        // `holdingsList` — which is gated on the same call by §491's
        // one-derivation rule — drew nothing with it. Scoping the room to
        // such an account opened a completely blank Holdings, with no
        // sentence saying why. Two of the demo's four accounts are that
        // shape, and so is any real wallet holding only ETH.
        //
        // The rule was not wrong, it was in the wrong file: whether a
        // drawing would repeat something ABOVE it is a question only the
        // view that draws both can answer. `holdingsCard` asks it itself
        // now; this states what is held and lets each caller decide.
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

// MARK: - A key's own identity (2026-08-25, prd §470)

/// WHAT IDENTIFIES A KEY ON SCREEN, and why nothing did until now.
///
/// `actorId` is the primary key of this entire system — `Keystore` stores
/// actors as `_actorConfig[actorId][account]`, `VibenetKeyReuse` joins on it,
/// a delegate's target is decoded from it, and it is what a developer greps a
/// console log for or compares against a raw `getActorConfig` read. Every
/// screen in this room drew a key as its KIND plus its permission chips and
/// showed the id nowhere, so **two passkeys on one account were two
/// indistinguishable rows** — same title, same detail clause, often the same
/// chips — and nothing in the app could tell you which was which or hand you
/// the value to look one up.
///
/// The room's own §463 ruling stands and is not in tension with this: spec
/// INTERNALS (bit names, "Nonce", raw scope words) do not belong on screen,
/// because they ask a reader to know the spec to read their own account. An
/// identifier is the opposite — it asks nothing and answers the one question
/// a repeated row cannot ("which of these two?"). The raw *values* still stay
/// off the screen and live on the clipboard instead (`VibenetAccountDebug`).
enum VibenetKeyIdentity {
    /// "…0b1c" — the tail form, deliberately the SAME truncation grammar
    /// `VibenetRoom.shortAddress` uses rather than a second one.
    ///
    /// A room that elides two kinds of hex two different ways teaches a
    /// reader to parse before they can compare, and comparing a tail against
    /// another tail is the whole job here. Tail-only for §CLAUDE's own reason
    /// (a leading prefix plus a middle ellipsis is two truncations doing the
    /// work of one).
    ///
    /// NO NOUN IS ATTACHED, and that is load-bearing. A secp256k1 actorId IS
    /// an address right-aligned into a word, while a passkey's is a HASH of a
    /// public key with no address inside it — so a label reading "address"
    /// would be true of some rows and a fabrication on others (§83, on the
    /// screen a person reads to find out who can spend their account). The
    /// row shows bare monospaced hex; `signerAddress` below is the gated way
    /// to say the stronger thing when it is actually true.
    static func short(_ actorId: String) -> String {
        VibenetRoom.shortAddress(actorId)
    }

    /// The signing EOA behind an address-shaped actorId, or nil.
    ///
    /// Non-nil for a secp256k1 key (whose actorId is `ActorId.fromAddress`)
    /// and nil for every P-256/WebAuthn/passkey one, whose id is a hash that
    /// would decode to a plausible address belonging to nobody — see
    /// `VibenetActorId.address(fromActorId:)`, whose high-bytes-are-zero test
    /// is what keeps that from happening. A caller MUST gate a "copy signer
    /// address" affordance on this rather than offering it unconditionally:
    /// an item that is present on every row and correct on some is worse than
    /// one that appears only where it means something.
    static func signerAddress(_ actor: VibenetActor) -> String? {
        VibenetActorId.address(fromActorId: actor.actorId)
    }
}

// MARK: - The account, as a developer would paste it (2026-08-25, prd §470)

/// THE RAW READ, FOR THE CLIPBOARD ONLY — never for the screen.
///
/// §463 ruled that this room must not put spec internals in front of a person
/// ("a card spelling them out in full is still asking someone to know the
/// spec to read their own account"), and that ruling is right and untouched.
/// But a developer debugging their own keystore against the contract wants
/// exactly those internals: the actorIds, the scope as the hex word `Scopes.
/// sol` actually stores, the expiry as the unix integer `Keystore` holds
/// rather than a rendered "in 3 days".
///
/// A CLIPBOARD PAYLOAD IS WHERE THAT BELONGS. It is asked for explicitly, it
/// never competes for space with the plain-language card, and it costs a
/// reader who does not want it precisely nothing — the same split
/// `AgentContext` already draws (a screen for reading, a paste for working).
/// So the screen keeps saying "Send anywhere"; the paste says `0x0001`, and
/// says both together so a reader can map one to the other.
///
/// Foundation-only by design, like everything else in this file, so
/// `vibenet-selftest.sh` compiles it whole and can pin the format.
enum VibenetAccountDebug {

    /// Scope as the raw 16-bit word, zero-padded — `0x0013`, never `0x13`.
    ///
    /// Padded because these are compared by eye against `Scopes.sol`'s own
    /// constants and against each other, and a ragged-width column is one a
    /// reader has to right-align in their head. Lowercase hex to match every
    /// other hex string this room emits.
    static func scopeWord(_ scope: VibenetScope) -> String {
        String(format: "0x%04x", scope.raw)
    }

    /// The whole account, as plain text.
    ///
    /// EVERY UNKNOWN IS SAID AS UNKNOWN rather than omitted or zeroed — a
    /// paste is read as a complete record of what we saw, so a missing line
    /// reads as "this account has none of that" when the truth may be "the
    /// read failed". `reached: no` leads for exactly that reason: it tells a
    /// reader that everything under it is a floor rather than a census.
    static func text(for item: VibenetAccountItem, name: String?, now: Date) -> String {
        var lines: [String] = []
        lines.append("vibenet account \(item.address)")
        if let name, !name.isEmpty { lines.append("name: \(name)") }
        lines.append("copied: \(iso(now))")
        lines.append("reached: \(item.reached ? "yes" : "no — everything below is what we last saw, not a census")")
        lines.append("established: \(item.established ? "yes" : "no")")
        lines.append("locked: \(item.locked ? "yes" : "no")")
        if item.hasInitiatedUnlock {
            let at = item.unlocksAt.map { "\(iso(Date(timeIntervalSince1970: TimeInterval($0)))) (\($0))" } ?? "unknown"
            lines.append("unlockInitiated: yes, unlocksAt \(at)")
        }
        if let native = item.nativeBalance {
            lines.append("native: \(VibenetBalanceFormat.line(native))")
        } else {
            lines.append("native: unread")
        }
        for token in item.tokenBalances {
            lines.append("token \(token.symbol): \(VibenetBalanceFormat.line(token.amount))")
        }

        lines.append("keys: \(item.actors.count)")
        // ALPHABETICAL, the same judgement-free order the screen uses (§463's
        // own user ruling) — a paste that ranked keys would be this app making
        // a claim in the one artifact meant to be raw.
        for actor in VibenetAccountItem.alphabetical(item.actors) {
            lines.append("  " + keyLine(actor))
        }

        if let cs = item.changeSequences {
            lines.append("changeSequences: multichain \(cs.multichain), localEpoch \(cs.localEpoch), localSequence \(cs.localSequence)")
        } else {
            lines.append("changeSequences: unread")
        }
        return lines.joined(separator: "\n")
    }

    /// One key: id, kind, scope both ways, expiry both ways.
    ///
    /// BOTH SPELLINGS OF EACH, always — the hex/unix for working against the
    /// contract, the words for checking that this paste describes the card you
    /// were just looking at. Either alone makes the reader do a conversion the
    /// other half already did.
    static func keyLine(_ actor: VibenetActor) -> String {
        var parts: [String] = [actor.actorId, actor.kind.label]
        parts.append("scope \(scopeWord(actor.scope)) (\(actor.scope.plainSummary))")
        if actor.expiry > 0 {
            let at = Date(timeIntervalSince1970: TimeInterval(actor.expiry))
            parts.append("expires \(iso(at)) (\(actor.expiry))")
        } else {
            // Keystore's own convention, spelled out — a bare `0` in a paste
            // reads as an epoch date rather than as "never".
            parts.append("expires never (0)")
        }
        if let signer = VibenetKeyIdentity.signerAddress(actor) {
            parts.append("signer \(signer)")
        }
        parts.append("authenticator \(actor.authenticator)")
        if let manager = actor.policyManager {
            parts.append("policyManager \(manager)")
        }
        if let commitment = actor.policyCommitment {
            parts.append("policyCommitment \(commitment)")
        }
        return parts.joined(separator: "  ")
    }

    /// UTC, seconds precision, no fractional part — a timestamp somebody may
    /// paste beside a block explorer's own.
    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

// MARK: - The key tray (2026-08-25, prd §468) — which keys are in which category

/// One key in the tray, carrying the account it belongs to.
///
/// The pairing is the whole point: room-wide, a key means nothing without the
/// account it can act for, and the card above it counts keys across every
/// watched account at once.
struct VibenetTrayKey: Equatable, Identifiable {
    let address: String
    let actor: VibenetActor
    /// Account-qualified, for the reason `VibenetKeySeenDiff.keyID` gives: an
    /// `actorId` is unique WITHIN an account and nothing says it is unique
    /// across them, and a `ForEach` over a colliding id is a SwiftUI identity
    /// bug that renders as rows disappearing.
    var id: String { VibenetKeySeenDiff.keyID(address: address, actorId: actor.actorId) }
}

/// WHAT THE KEYS CARD OPENS INTO (user, 2026-08-25: *"the key card should open
/// to a list of keys and permissions that show which keys are in which
/// category"*).
///
/// The card states six numbers — "Send anywhere 4", "Pay own gas 2" — and a
/// number is the one thing you cannot act on: knowing four keys can send
/// anywhere does not tell you WHICH four, or on which account, or when any of
/// them lapses. `VibenetRoomCard.keysAggregateSection` (deleted 2026-08-25,
/// prd §469 — the same summary is now `keysCard`/`keysBody` alone) carried a
/// comment since 2026-08-24 saying it withholds its chevron because "it
/// points at a key tray that does not exist in this build, and a chevron
/// that opens nothing is the dead
/// control §83 bans". This is that screen; the chevron becomes honest with it.
///
/// **IT MIRRORS `VibenetPolicyAggregation.compose` EXACTLY** — same Admin-first
/// order, same `orderedPlainBits` order, same exclusion of an admin from every
/// bit section, same dropping of a permission nobody holds. Two derivations of
/// one grouping drift, and then a card says 4 and the list it opens shows 3.
/// The ceiling that follows is stated rather than papered over: see
/// `unnamedKeyCount`.
enum VibenetKeyTray {
    /// **ONE ROW PER KEY, A–Z (2026-08-25, prd §478), superseding the
    /// per-permission sections this enum shipped with on 2026-08-25.**
    ///
    /// §468 built this tray as sections — one heading per permission, a key
    /// listed under each permission it holds — and it answered its question
    /// from the PERMISSION's side. The cost was structural rather than
    /// cosmetic: **a card saying "8 keys" opened a list of fourteen rows**,
    /// which needed `footnote`'s own sentence to explain away, and the same
    /// key appeared three times with a different "Also:" line each time, so
    /// the one question you cannot answer by scrolling is the one somebody
    /// opens this screen with — *what can THIS key do, and when does it
    /// lapse?*
    ///
    /// This answers it from the KEY's side, which is also **§463's own
    /// settled grammar** (user: *"i think we are stuck doing chips per
    /// key"*, and *"the keys could just be listed in alphabetical order then
    /// we aren't making some judgement call"*) — the shape the account
    /// detail has drawn since that day, now the tray's too, so a key reads
    /// the same on both surfaces. The permission is still on every row, as
    /// its own chips; nothing that §468 asked to see has been taken away,
    /// and the row count now equals the key count.
    ///
    /// TOTAL and judgement-free, exactly as `ordered` was: displayed title,
    /// then account, then actorId. No grouping by account either — a key's
    /// account is on its own row, and grouping would re-introduce a heading
    /// whose only job is to be scrolled past.
    static func roster(_ items: [VibenetAccountItem]) -> [VibenetTrayKey] {
        ordered(items.flatMap { item in
            item.actors.map { VibenetTrayKey(address: item.address, actor: $0) }
        })
    }

    /// How many keys hold each named permission — the CENSUS, for the tray's
    /// own filter strip, and the exact list `VibenetPolicyAggregation.compose`
    /// gives the card above it.
    ///
    /// Forwarded rather than re-derived: two derivations of one grouping
    /// drift, and then a card says 4 and the list it opens shows 3. That was
    /// `sections`' own stated invariant and it survives its deletion.
    static func census(_ items: [VibenetAccountItem]) -> [VibenetPolicyCount] {
        VibenetPolicyAggregation.compose(items)
    }

    /// Whether a key belongs to the permission a filter names — the one
    /// membership test, so the strip's counts and what the strip SHOWS can
    /// never disagree. Mirrors `VibenetPolicyAggregation.compose` exactly:
    /// "Admin" is the admins, and a bit label excludes an admin (an admin is
    /// unrestricted, not a holder of five named bits — §463).
    static func holds(_ key: VibenetTrayKey, permission label: String) -> Bool {
        if key.actor.scope.isAdmin { return label == String(localized: "Admin") }
        guard let bit = VibenetScope.orderedPlainBits.first(where: { $0.1 == label })?.0 else { return false }
        return key.actor.scope.raw & bit != 0
    }

    /// Keys that appear in NO section — a non-admin key holding only reserved
    /// bits this build cannot name (`Scopes.sol` reserves 0x0020…0x8000).
    ///
    /// COUNTED AND SAID, never given an invented category: a section called
    /// "Other" would name a permission nobody can check, which is the one
    /// thing this whole file refuses to do. The tray states the count in a
    /// footnote so a reader can tell a key that is missing from every section
    /// from a key that was never read.
    static func unnamedKeyCount(_ items: [VibenetAccountItem]) -> Int {
        items.flatMap(\.actors)
            .filter { !$0.scope.isAdmin && $0.scope.raw & VibenetScope.known == 0 }
            .count
    }

    /// "8 keys, across 3 accounts" — what the roster is, said once at the top.
    ///
    /// **The clause it used to open with is GONE, because the thing it
    /// apologised for is (prd §478).** Under §468's sections it read "8 keys
    /// · a key with several permissions appears under each", and that
    /// sentence existed to explain why fourteen rows sat under a card saying
    /// eight. One row per key needs no such explanation; keeping the sentence
    /// would describe a screen this no longer is.
    ///
    /// The unnamed-key clause survives untouched — that one is not an
    /// apology for the layout, it is the standing §83 admission that a key
    /// holding only reserved bits is counted here and can be described
    /// nowhere.
    static func footnote(_ items: [VibenetAccountItem]) -> String? {
        let total = items.flatMap(\.actors).count
        guard total > 0 else { return nil }
        var line = total == 1 ? String(localized: "1 key") : String(localized: "\(total) keys")
        let accounts = items.filter { !$0.actors.isEmpty }.count
        if accounts > 1 {
            line += String(localized: ", across \(accounts) accounts")
        }
        let unnamed = unnamedKeyCount(items)
        if unnamed > 0 {
            line += unnamed == 1
                ? String(localized: " · 1 holds only permissions this build can't name")
                : String(localized: " · \(unnamed) hold only permissions this build can't name")
        }
        return line
    }

    /// TOTAL, and judgement-free: by the key's own displayed title, then the
    /// account, then the actorId. `VibenetAccountItem.alphabetical`'s ruling
    /// (user, §463: *"the keys could just be listed in alphabetical order then
    /// we aren't making some judgement call"*) carried across accounts — the
    /// account is the tie-break rather than the lead, because the reader is
    /// scanning a permission's members, not browsing accounts.
    /// Internal rather than private since §491: the room's Permissions list
    /// groups these keys by account and must order them the SAME way the tray
    /// does — §478's A–Z ruling ("then we aren't making some judgement call")
    /// belongs to the keys, not to one sheet that shows them.
    static func ordered(_ keys: [VibenetTrayKey]) -> [VibenetTrayKey] {
        keys.sorted { a, b in
            let t = a.actor.kind.plainTitle.localizedCaseInsensitiveCompare(b.actor.kind.plainTitle)
            if t != .orderedSame { return t == .orderedAscending }
            let addr = a.address.localizedCaseInsensitiveCompare(b.address)
            if addr != .orderedSame { return addr == .orderedAscending }
            return a.actor.actorId < b.actor.actorId
        }
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
    /// Watched accounts whose read never reached the chain. `accountCount`
    /// silently excludes them — an unreached account has an empty roster,
    /// which is indistinguishable here from one that authorized nothing — so
    /// without this the card reports "8 keys across 3 accounts" over a room
    /// where a fourth account's keys were simply never counted. The balance
    /// aggregate's own `unreachedCount` for the identical reason; this is one
    /// defect in two places.
    let unreachedCount: Int
    /// Keys that hold ONLY reserved bits this build cannot name — the gap
    /// between `total` and what the census rows add up to. Stored rather than
    /// re-derived by the card, because `VibenetKeyTray.unnamedKeyCount` takes
    /// the ITEMS and this aggregate is what the card holds; two walks of one
    /// rule is how a footnote and a tray come to disagree about the same keys.
    let unnamedCount: Int
    /// The soonest FUTURE expiry across the whole room, or nil when
    /// nothing is still ticking — `VibenetAccountItem.urgentLine`'s exact
    /// rule (`expiry == 0` never counts, an already-expired key never
    /// counts either), read once here rather than re-derived per caller.
    let soonestExpiry: VibenetKeySoonestExpiry?
    /// EVERY future expiry in the room, ascending — what the keys card draws
    /// as a runway (`WalletRunwayRail`, §417's rail at card scale).
    ///
    /// `soonestExpiry` is one date in a sentence; three keys lapsing inside a
    /// fortnight and three spread over a quarter produce the identical
    /// sentence and completely different pictures, and the spread is the
    /// thing a list cannot give at any length. Same rule as the sentence, so
    /// the two can never disagree: `expiry == 0` is Keystore's "never" and
    /// is not a date, and an ALREADY-LAPSED key is excluded — the rail's
    /// window always contains `now`, so a lapsed key would draw left of the
    /// marker under a heading about what is ahead, and each account's own
    /// `urgentLine` already counts the lapsed ones.
    let futureExpiries: [Date]

    /// THE CARD'S EYEBROW — the scope the count covers, or nil on a room
    /// where there is no scope to state (2026-08-25, prd §471).
    ///
    /// The keys card was the only one of the four stacked cards with no
    /// eyebrow: its three neighbours open with a `label12` tertiary line and
    /// it opened with a `heading17` sentence, so one card in four broke the
    /// header grammar. The old objection to fixing that was real — putting
    /// "Keys" over "8 keys authorized across 3 accounts" says the word twice
    /// — and the way past it is to put the SCOPE in the eyebrow rather than
    /// the noun, which leaves the headline saying the count alone. Same two
    /// facts, same one derivation, one of them promoted to the slot its
    /// neighbours already use.
    var scopeEyebrow: String? {
        guard accountCount > 1 else { return nil }
        return String(localized: "Across \(accountCount) accounts")
    }

    /// "9 keys" / "1 key" — the COUNT ALONE (2026-08-25, prd §475).
    ///
    /// It said "9 keys authorized" until this pass, which was right while the
    /// card introduced itself: there was no header above it and the sentence
    /// had to carry its own subject. §475 gave the card Wallet's own section
    /// header ("What's authorized"), and the word became the second half of a
    /// title the reader has just read — user: *"underneath it just say 8 keys
    /// instead of '8 keys authorized', we don't need to repeat that word."*
    ///
    /// `plainLine` below keeps the verb, and must: it is the one-line form for
    /// the probe and the harness, where nothing states the subject first.
    var countHeadline: String {
        total == 1 ? String(localized: "1 key")
                   : String(localized: "\(total) keys")
    }

    /// "9 keys authorized across 4 accounts" / "9 keys authorized" (one
    /// account) / "1 key authorized" — the room-wide count nowhere else on
    /// this card says.
    ///
    /// The ONE-LINE form, kept for `-vibenetRoomProbe` and the harness, which
    /// want a single sentence rather than the card's two slots.
    ///
    /// It carries the verb `countHeadline` dropped in §475, because this form
    /// stands alone with no section header in front of it — a probe line
    /// reading "8 keys across 3 accounts" says nothing about what the keys
    /// ARE. Both still read the same `total` and the same `scopeEyebrow`, so
    /// the count and the scope can never drift between the two; only the word
    /// the header already supplies differs.
    var plainLine: String {
        guard let scope = scopeEyebrow else {
            return total == 1 ? String(localized: "1 key authorized")
                              : String(localized: "\(total) keys authorized")
        }
        return String(localized: "\(total) keys authorized \(scope.lowercased())")
    }

    /// "1 key holds a permission this build can't name" — said on the CARD
    /// now, not only inside the tray it opens (2026-08-25, prd §471).
    ///
    /// `VibenetPolicyAggregation.compose` walks `orderedPlainBits` and drops
    /// what it cannot name, so a key holding only reserved bits (`Scopes.sol`
    /// reserves 0x0020…0x8000) contributes to `total` and to NO row — the
    /// census silently adds up to less than the headline, and nothing on the
    /// card said why. A FOOTNOTE and never a row: a row called "1 permission
    /// not named" with a count beside it reads as a permission you could go
    /// and look up, which is the invented category `VibenetKeyTray
    /// .unnamedKeyCount` already refuses to draw.
    var unnamedLine: String? {
        guard unnamedCount > 0 else { return nil }
        return unnamedCount == 1
            ? String(localized: "1 key holds a permission this build can't name")
            : String(localized: "\(unnamedCount) keys hold a permission this build can't name")
    }

    /// "1 account couldn't be read" — the count above is a FLOOR whenever
    /// this is non-nil, and saying so is what keeps it from being a wrong
    /// number. Drawn beneath the headline rather than folded into it: the
    /// headline is the room's largest sentence and a clause that is absent on
    /// every healthy room does not belong inside it.
    var unreachedLine: String? {
        guard unreachedCount > 0 else { return nil }
        return unreachedCount == 1
            ? String(localized: "1 account couldn't be read")
            : String(localized: "\(unreachedCount) accounts couldn't be read")
    }
}

// MARK: - One key's own beginning (2026-08-25, prd §473)

/// WHEN THIS KEY BEGAN — the one fact a key could not state about itself.
///
/// Everything else the expanded row shows (kind, scope, expiry, contract, run
/// count, also-on accounts) was already on the collapsed row. This is the only
/// genuinely new content, and it is why the row expands at all: the account's
/// history knew when each key was authorized and nothing could ask it about
/// ONE key, because `VibenetKeyMoment` threw the id away.
///
/// **Costs nothing.** The history is already walked, already ordered and
/// already block-dated for the strip on the same screen; this reads it back.
enum VibenetKeyOrigin {
    /// The moment this key was last AUTHORIZED, or nil.
    ///
    /// The LATEST authorization and not the first, because that is what
    /// `VibenetActorLog.survivors` means by live: an id revoked and
    /// re-authorized is a key that began again, and dating it from a
    /// superseded authorization would put its beginning before a revocation
    /// that really happened.
    ///
    /// Three ways to answer nil, all of them honest and none distinguishable
    /// on screen (the row simply says nothing): the key predates
    /// `VibenetKeyHistory.cap`, the moments were landed by a build before
    /// §473 and carry no id, or the block-time lookup failed so the moment has
    /// no date. Every one of them means "we cannot name when this began",
    /// which is exactly what drawing nothing says.
    static func authorized(_ actor: VibenetActor, in history: [VibenetKeyMoment]) -> VibenetKeyMoment? {
        history
            .filter { $0.authorized && $0.actorId?.caseInsensitiveCompare(actor.actorId) == .orderedSame }
            // Case-insensitively for the reason every hex compare in this file
            // is: an RPC's casing is not a promise.
            .max { ($0.block, $0.logIndex) < ($1.block, $1.logIndex) }
    }
}

// MARK: - A revoked key's deadline (2026-08-25, prd §473)

/// **A KEY THAT NO LONGER EXISTS MUST NOT KEEP A DEADLINE.**
///
/// `VibenetEvents.landEvents` stamps `thing.dueAt` on an ActorAuthorized row
/// so an expiring session key reaches the lock screen through the generic
/// `NotifySweep.deadlineNear` — no `NotifyKind` of this bridge's own, no new
/// notification code. That was right, and it had a half nobody built:
/// **nothing ever cleared it.** A revoke lands as its own row and the
/// authorization row is never deleted (this bridge issues no `context.delete`
/// at all), so:
///
///   authorize a key expiring in 30 days → revoke it on day 3 →
///   on day 28 the lock screen announces a deadline for a key that has not
///   existed for twenty-five days.
///
/// One field reaches three surfaces — `NotifySweep`, the "Needs you" widget
/// (`#Predicate { $0.dueAt != nil }`) and the Today brief — and **it is worse
/// than an ordinary stale number because it is ASYMMETRIC**: the room's own
/// card reads live actors off the chain, so the card correctly shows the key
/// gone while the lock screen counts down to its expiry. The app contradicts
/// itself, and the half that is wrong is the half that interrupts you. §397's
/// Privacy Pools reclaim (a returned deposit reading `Declined` for life) is
/// the same shape in a second place: evidence beats the record.
///
/// **THE JOIN IS THE `actorId`, NOT THE EXPIRY.** An expiry-within-account
/// match was drawn first (it is what `VibenetEventFacts` does for this same
/// pair of objects) and then dropped for something exact: every
/// ActorAuthorized and ActorRevoked log carries its `actorId` in `topics[2]`,
/// the landing pass is already reading those logs, and the authorization row's
/// ref is derivable from the same event. So the answer needs no tie-break, no
/// ambiguity guard and **not one extra request** — the expiry match would have
/// been a heuristic standing in for a fact already on the wire.
enum VibenetDeadlineSweep {
    /// Which of an account's actorIds are no longer live — every id the log
    /// has ever seen, minus the survivors.
    ///
    /// Derived FROM `VibenetActorLog.survivors` rather than restating its
    /// rule, so last-write-wins is defined once: an id revoked and then
    /// re-authorized is live and keeps its deadline, and this file's own
    /// mutation coverage of that rule protects both readers at once.
    static func revoked(_ events: [VibenetActorEvent]) -> Set<String> {
        Set(events.map(\.actorId)).subtracting(VibenetActorLog.survivors(events))
    }

    /// **NEVER SWEEP ON A FAILED READ.** `VibenetChain.getLogs` answers nil
    /// when its newest chunk fails, and a caller collapsing that to `[]` gets
    /// an empty event list — from which `revoked` correctly returns nothing,
    /// so an outage is harmless BY CONSTRUCTION here rather than by luck.
    /// This states the rule anyway, because the harmless version depends on a
    /// caller that keeps the optional: read the logs as `[] `and a future
    /// refactor that derives liveness some other way inherits the
    /// `ScreenshotIngest.pruneDeleted` failure — an unreachable host reading
    /// as "everything was revoked", stripping deadlines off a CloudKit-
    /// mirrored corpus on every device before anyone can quit the app.
    static func maySweep(logsAnswered: Bool, events: [VibenetActorEvent]) -> Bool {
        logsAnswered && !events.isEmpty
    }
}

// MARK: - Ordering keys by their clock (2026-08-25, prd §471)

/// SOONEST FIRST, and TOTAL — one definition for every reading that ranks the
/// room's keys by when they lapse.
///
/// Written out twice at first (the soonest-expiry reading and the shelf's
/// bars), and the harness caught it the same way it caught `isTicking`'s
/// duplicate: `mutate` replaces the FIRST occurrence, so inverting the
/// comparator broke the shelf while the assertion watched the aggregate, and a
/// real check went green over a real defect. Two copies of one ordering is the
/// §418 duplicate-parser lesson at the scale of a comparator.
///
/// The TIE-BREAKS are the point, not decoration: two keys authorized in the
/// same transaction share an expiry to the second, and a comparator that stops
/// at the timestamp is not a total order — SwiftUI then reshuffles the card
/// between composes over identical data, which reads as broken (`ASCRoom`'s
/// own ruling). Address before actorId, case-insensitively, because an RPC's
/// hex casing is not a promise.
enum VibenetKeyOrder {
    static func soonestFirst(_ a: (String, VibenetActor), _ b: (String, VibenetActor)) -> Bool {
        if a.1.expiry != b.1.expiry { return a.1.expiry < b.1.expiry }
        let addr = a.0.localizedCaseInsensitiveCompare(b.0)
        if addr != .orderedSame { return addr == .orderedAscending }
        return a.1.actorId < b.1.actorId
    }
}

// MARK: - When keys lapse (2026-08-25, prd §471)

/// One key that lapses inside the shelf's window, ready to draw as a bar.
///
/// Carries the ACTOR rather than a pre-rendered countdown, so the label is
/// recomputed fresh at draw time exactly as `expiryLabel(now:)` and
/// `unlockLabel(now:)` already are — a card left open past midnight otherwise
/// counts down to a number captured when the room composed. It carries no
/// NAME either: resolving one needs `VibenetWatch`, and this file is
/// Foundation-only by design, so the view composes "Session · Trading" the
/// same way `VibenetRoomCard.displayName` already does for every other row.
struct VibenetKeyShelfRow: Equatable, Identifiable {
    let address: String
    let actor: VibenetActor
    /// Account-qualified for `VibenetKeySeenDiff.keyID`'s own reason: an
    /// actorId is unique WITHIN an account and nothing says it is unique
    /// across them, and a `ForEach` over a colliding id renders as rows
    /// disappearing.
    var id: String { VibenetKeySeenDiff.keyID(address: address, actorId: actor.actorId) }

    /// How far along this key is toward lapsing, 0…1 against the shelf's
    /// window — so every bar on the card shares one scale and their lengths
    /// are directly comparable, which is the whole spread reading.
    ///
    /// FLOORED, and the floor is a drawing decision stated here rather than
    /// hidden in the view (`VibenetBalanceTreemap`'s own `max(0.14, …)`
    /// precedent): a key lapsing within the hour is 0.0005 of a quarter and
    /// draws as no bar at all, which reads as missing data on the one row
    /// that matters most. The number beside the bar is exact; the bar is the
    /// picture.
    func fraction(now: Date) -> Double {
        let remaining = TimeInterval(actor.expiry) - now.timeIntervalSince1970
        guard remaining > 0 else { return VibenetKeyShelf.minimumFraction }
        return min(1, max(VibenetKeyShelf.minimumFraction, remaining / VibenetKeyShelf.window))
    }

    /// "6d" / "41d" / "<1d" — the countdown at bar scale, where
    /// `expiryLabel`'s full sentence ("Expires in 6 days") does not fit and
    /// would repeat the heading above it anyway.
    ///
    /// Days are rounded UP, never down: a key with 30 hours left reading "1d"
    /// understates it on a screen whose whole job is to say how much time is
    /// left. Under a day says so rather than printing "0d", which reads as
    /// already gone.
    func countdown(now: Date) -> String {
        let remaining = TimeInterval(actor.expiry) - now.timeIntervalSince1970
        guard remaining > 0 else { return String(localized: "<1d") }
        let days = Int((remaining / 86_400).rounded(.up))
        return days <= 1 ? String(localized: "<1d") : String(localized: "\(days)d")
    }

    /// Inside `VibenetAccountItem.urgencyWindow` — the ONE row on this card
    /// that earns the room's mark. Same threshold `expiryStanding` uses, read
    /// from it rather than restated, so a key drawn blue here is a key drawn
    /// blue on its own row in the account detail.
    func isUrgent(now: Date) -> Bool { actor.expiryStanding(now: now) == .soon }
}

/// WHEN THE ROOM'S KEYS LAPSE — one bar per key, all on one scale
/// (2026-08-25, prd §471, user pick of three).
///
/// **It replaces `WalletRunwayRail` on this card, and the rail had a defect
/// here that no amount of restyling fixes.** `WidgetRunway.positions` scales
/// its axis to `min(dates, now) … max(dates, now)`; every key expiry is in
/// the FUTURE, so `now` is always the minimum and the marker was pinned at
/// 5% on every render this feature has ever drawn — a constant, carrying no
/// information, on the one element that gives the rail its meaning elsewhere.
/// The axis was elastic besides, so a single key lapsing in 2027 crushed
/// everything else into the first third. Four identical dots on an unlabelled
/// elastic axis say "four things, sometime, in some order".
///
/// §417's argument for a figure at all still stands and is honoured: three
/// keys lapsing inside a fortnight and three spread over a quarter produce
/// the identical sentence and completely different pictures. The spread is
/// still drawn — it is just read off BAR LENGTHS against a fixed window
/// rather than off dot positions on a rubber one, which needs no axis
/// furniture, no now-marker and no labels to be legible. And because the bars
/// are rows, the figure also answers WHICH KEY, which the rail could not say
/// at any size and which is precisely what the tray beneath it exists for.
///
/// **The cost, stated rather than discovered later:** this is local to
/// vibenet, so the room and the "Needs you" widget no longer share one
/// drawing of the same dates. That sharing was the rail's stated reason to be
/// reused whole, and it is given up knowingly — the widget's subject is mixed
/// deadlines INCLUDING overdue ones, where a now-marker is real and names are
/// unavailable; this card's subject is future key expiries that all have
/// names. Different questions, different figures.
///
/// Foundation-only like the rest of this file.
enum VibenetKeyShelf {
    /// A quarter, fixed. NOT the furthest expiry (that is the elastic axis
    /// this replaces) and not a rounder number for its own sake: 90 days is
    /// the horizon over which a lapsing key is something you can still act
    /// on, and holding it constant is what makes two accounts' cards
    /// comparable at a glance.
    static let window: TimeInterval = 90 * 86_400
    /// The smallest bar that still reads as a bar rather than as a hole.
    static let minimumFraction = 0.02
    /// Rows drawn before the tail takes over. Three, the same summary
    /// discipline `rowCap` keeps for the roster — this is a footer on a
    /// card, not the tray it opens.
    static let rowCap = 3

    /// nil when there is no shelf to draw, and the three declines are
    /// deliberate and different:
    ///
    /// 1. **Fewer than two future expiries.** One bar has nothing to be
    ///    compared against, so its length says nothing a sentence does not
    ///    say better — the caller falls back to `soonestExpiry.line`, which
    ///    is exactly what it did before this figure existed.
    /// 2. **Nothing inside the window.** Every key lapses more than a quarter
    ///    out; drawing three full-length bars claims urgency nobody has.
    /// 3. **No keys at all.** The card itself is already silent.
    static func compose(_ items: [VibenetAccountItem], now: Date) -> VibenetKeyShelf.Reading? {
        let pairs = items.flatMap { item in item.actors.map { (item.address, $0) } }
            .filter { $0.1.isTicking(now: now) }
        guard pairs.count >= 2 else { return nil }

        let horizon = now.timeIntervalSince1970 + window
        // TOTAL ORDER, never `sorted(by: expiry)` alone — two keys authorized
        // in the same transaction share an expiry to the second, and a
        // non-total comparator lets the card reshuffle between composes over
        // identical data, which reads as broken (`ASCRoom`'s own ruling).
        let inside = pairs
            .filter { TimeInterval($0.1.expiry) <= horizon }
            .sorted(by: VibenetKeyOrder.soonestFirst)
        guard !inside.isEmpty else { return nil }

        let rows = inside.prefix(rowCap)
            .map { VibenetKeyShelfRow(address: $0.0, actor: $0.1) }
        return Reading(rows: Array(rows),
                       hiddenInWindow: max(0, inside.count - rows.count),
                       beyondWindow: pairs.count - inside.count)
    }

    struct Reading: Equatable {
        let rows: [VibenetKeyShelfRow]
        /// Inside the window but past `rowCap`.
        let hiddenInWindow: Int
        /// Future, but further out than the window — never drawn as a bar,
        /// because a bar pinned at full length says "a quarter away" about a
        /// key lapsing in 2027.
        let beyondWindow: Int

        /// "2 more within 90 days · 1 lapses later", or nothing.
        ///
        /// The two counts are said APART and never summed: one names keys you
        /// could not fit on the card and the other names keys the card
        /// deliberately does not chart, and folding them into one number
        /// would make the card's own bound look like the room's.
        var tailLine: String? {
            var parts: [String] = []
            if hiddenInWindow > 0 {
                parts.append(hiddenInWindow == 1
                    ? String(localized: "1 more within 90 days")
                    : String(localized: "\(hiddenInWindow) more within 90 days"))
            }
            if beyondWindow > 0 {
                parts.append(beyondWindow == 1
                    ? String(localized: "1 expires later")
                    : String(localized: "\(beyondWindow) expire later"))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
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
            .filter { $0.1.isTicking(now: now) }
            .min(by: VibenetKeyOrder.soonestFirst)
            .map { VibenetKeySoonestExpiry(address: $0.0, actor: $0.1) }

        // Same rule, same one definition — filtered as ACTORS and only then
        // reduced to dates, rather than re-testing raw seconds a second way.
        let futureExpiries = pairs
            .filter { $0.1.isTicking(now: now) }
            .map { Date(timeIntervalSince1970: TimeInterval($0.1.expiry)) }
            .sorted()

        return VibenetKeyAggregate(total: pairs.count, byKind: byKind,
                                    accountCount: accountCount,
                                    unreachedCount: items.filter { !$0.reached }.count,
                                    unnamedCount: VibenetKeyTray.unnamedKeyCount(items),
                                    soonestExpiry: soonest, futureExpiries: futureExpiries)
    }
}

// MARK: - What changed since you last looked

/// The room's keys, DIFFED against what this device last saw.
///
/// Every card in this room is a snapshot: it says what is true now and never
/// what moved. The landed events (`VibenetEvents`) carry the moments, but they
/// arrive in the feed as rows you scroll past, so the one question a person
/// opens a keystore room with — *did anything change while I wasn't looking* —
/// had no answer on the surface built to answer it. `redeployedSinceLastSeen`
/// already proves the pattern belongs here; this is the same shape for the
/// thing that matters more than a contract address.
///
/// Foundation-only like the rest of this file: the ledger itself lives in
/// `VibenetKeysSeen` (UserDefaults, `VibenetSeenCommit`'s neighbour) and is
/// handed in already read, so nothing here touches a store. "Have you looked
/// at this" is a fact about THIS DEVICE'S SCREEN — the `AddressConnectionsSeen`
/// ruling — so it is deliberately not synced and deliberately not a `Thing`.
struct VibenetKeyChanges: Equatable, Codable {
    /// The keys seen for the first time this look, as `keyID`s. A SET rather
    /// than a count, so a key row can mark itself rather than the card merely
    /// announcing a number nobody can locate.
    let added: Set<String>
    /// Keys that were in the ledger and are not in the roster any more.
    /// A COUNT and not a set, because there is nothing left to mark: the row
    /// is gone. Never the same thing as `added.count` inverted — an account
    /// can gain and lose keys in one window.
    let revokedCount: Int

    var isEmpty: Bool { added.isEmpty && revokedCount == 0 }

    /// "2 new" / "2 new · 1 gone" — the PILL form (2026-08-25, prd §471).
    ///
    /// `line` below is a sentence and was drawn as a third caption stacked
    /// under the headline, on a card already carrying an eyebrow, a headline,
    /// an unreached apology and a census. This is the same two facts at pill
    /// length so the news can sit ON the headline row instead of pushing
    /// everything down.
    ///
    /// ONE COLOUR FOR BOTH CLAUSES, inherited from `line`: a revocation you
    /// performed and a revocation somebody else performed read identically
    /// from the chain, so neither clause may be graded against the other.
    /// "Gone" rather than "revoked" only because the pill has no room for the
    /// longer word; the sentence form keeps the precise one.
    var pillLine: String? {
        guard !isEmpty else { return nil }
        var parts: [String] = []
        if !added.isEmpty { parts.append(String(localized: "\(added.count) new")) }
        if revokedCount > 0 { parts.append(String(localized: "\(revokedCount) gone")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "2 keys new since you last looked · 1 revoked", or nothing.
    ///
    /// REVOKED IS NEVER SAID ALONE AS A GOOD THING and never coloured here —
    /// a revocation you performed and a revocation somebody else performed
    /// read identically from the chain, so this states the fact and leaves
    /// the judgement to the person, exactly as `AddressConnections` refuses
    /// to rank a relationship.
    var line: String? {
        guard !isEmpty else { return nil }
        var parts: [String] = []
        if !added.isEmpty {
            parts.append(added.count == 1
                ? String(localized: "1 key new since you last looked")
                : String(localized: "\(added.count) keys new since you last looked"))
        }
        if revokedCount > 0 {
            // Worded to stand alone when it is the only clause: "1 revoked"
            // under nothing else would be a fragment.
            parts.append(added.isEmpty
                ? (revokedCount == 1
                    ? String(localized: "1 key revoked since you last looked")
                    : String(localized: "\(revokedCount) keys revoked since you last looked"))
                : (revokedCount == 1
                    ? String(localized: "1 revoked")
                    : String(localized: "\(revokedCount) revoked")))
        }
        return parts.joined(separator: " · ")
    }
}

enum VibenetKeySeenDiff {
    /// The ledger's key. An `actorId` is unique WITHIN an account and nothing
    /// says it is unique across them (a delegate authenticator's id is derived
    /// from an address, and one address can be a delegate for several
    /// accounts) — so filing by `actorId` alone would let one account's key
    /// mark another's as already seen, which fails in the direction that
    /// hides a change rather than inventing one, i.e. silently.
    ///
    /// Lowercased on both halves: an address's case is an EIP-55 checksum and
    /// the chain hands back both spellings across different calls.
    static func keyID(address: String, actorId: String) -> String {
        "\(address.lowercased())|\(actorId.lowercased())"
    }

    /// What moved since `seen` was written.
    ///
    /// THREE REFUSALS, and each of them is a way to be confidently wrong:
    ///
    /// 1. **An account with no entry in the ledger seeds SILENTLY.** A first
    ///    look at a newly-watched account would otherwise report every key it
    ///    has ever had as new — the Hyperliquid first-sight bug, which this
    ///    codebase has now paid for in four bridges.
    /// 2. **AN UNREACHED ACCOUNT CONTRIBUTES NOTHING.** Its roster is empty
    ///    because the read failed, not because its keys were revoked, and
    ///    reading that as a revocation announces a security event that did not
    ///    happen every time the devnet has a bad minute. This is
    ///    `ScreenshotIngest.pruneDeleted`'s never-prune-on-an-empty-read rule
    ///    in a room that draws rather than deletes.
    /// 3. **An account no longer watched contributes no revocations.** You
    ///    stopped watching it; its keys did not go anywhere.
    static func since(seen: [String: Set<String>], items: [VibenetAccountItem]) -> VibenetKeyChanges {
        var added: Set<String> = []
        var revoked = 0
        for item in items {
            guard item.reached else { continue }
            let key = item.address.lowercased()
            guard let before = seen[key] else { continue }
            let now = Set(item.actors.map { keyID(address: item.address, actorId: $0.actorId) })
            added.formUnion(now.subtracting(before))
            revoked += before.subtracting(now).count
        }
        return VibenetKeyChanges(added: added, revokedCount: revoked)
    }

    /// The ledger after this look. Keyed on the CURRENT roster, so an address
    /// that is no longer watched drops out — and an UNREACHED account keeps
    /// whatever it had, never an empty set: overwriting it with the failed
    /// read's nothing would make the next successful read report every one of
    /// its keys as new. Rule 2 above, in the half that writes.
    static func advanced(seen: [String: Set<String>], items: [VibenetAccountItem]) -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for item in items {
            let key = item.address.lowercased()
            if item.reached {
                out[key] = Set(item.actors.map { keyID(address: item.address, actorId: $0.actorId) })
            } else if let before = seen[key] {
                out[key] = before
            }
        }
        return out
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
    /// HOW MANY ACCOUNTS THE TOTAL BELOW ACTUALLY COVERS, and it exists
    /// because the card shipped stating a partial sum as a whole one: the
    /// crown heads `nativeTotal` with "Across your accounts" while
    /// `compose` drops every account whose `eth_getBalance` did not answer,
    /// so three watched with one unreachable printed a two-account total
    /// under a three-account sentence. That is exactly what §349 ruled out
    /// for Gnosis Pay and Railgun — a sum missing any part may not be stated
    /// as though it were complete.
    ///
    /// The figure is KEPT rather than withheld (Railgun's all-or-nothing rule
    /// is right for money that must reconcile; a devnet balance is a reading,
    /// and half a reading is worth more than none) — what changes is the
    /// sentence over it. See `nativeHeading`.
    let readCount: Int
    /// Watched accounts whose read did not reach the chain at all. Distinct
    /// from `accountCount - readCount`: an account can be reached and still
    /// have no native balance (that one read failing alone), and the two are
    /// different sentences.
    let unreachedCount: Int
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

    /// The crown's own heading, owned by the model rather than hardcoded in
    /// the card, so the words and the arithmetic they describe can never
    /// drift apart (the `SafeRoom.subject` rule: one function, both readers).
    ///
    /// "Across your accounts" ONLY when the total really covers all of them.
    /// A partial sum says so and says how partial, which is the whole of the
    /// fix: the figure stays useful and stops claiming to be everything.
    /// A single account never counts — "Across 1 of 1 accounts" is arithmetic
    /// nobody needs.
    var nativeHeading: String {
        guard nativeTotal != nil else { return String(localized: "Across your accounts") }
        guard readCount < accountCount else { return String(localized: "Across your accounts") }
        return String(localized: "Across \(readCount) of \(accountCount) accounts")
    }

    /// What the room could not see, in words, or nothing. Separate from
    /// `plainLine` because that line is the card's own subtitle and this is
    /// an apology — folding them would make every healthy room's subtitle
    /// carry a clause it never uses.
    var unreachedLine: String? {
        guard unreachedCount > 0 else { return nil }
        return unreachedCount == 1
            ? String(localized: "1 account couldn't be read")
            : String(localized: "\(unreachedCount) accounts couldn't be read")
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
            readCount: natives.count, unreachedCount: items.filter { !$0.reached }.count,
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

    /// The §308 FACETS this event carries, stamped on `Thing.tags` at
    /// landing.
    ///
    /// This room lands exactly four kinds of thing and, until now, no way to
    /// ask for one of them: every other landing bridge in the app got facets
    /// and this one shipped without, so "revoked keys on vibenet" was a
    /// free-text search over a display title. The gating rule (§308: a facet
    /// filters only alongside a NAMED source) matters more here than almost
    /// anywhere, because "key" and "locked" are ordinary English AND words
    /// this corpus is full of — a note about an API key, an article about a
    /// locked account somewhere else.
    ///
    /// A REVOKE CARRIES BOTH `Key` AND `Revoked`, deliberately: it is a key
    /// event, so "keys on vibenet" must reach it, and the revocation is the
    /// narrower question asked on top. A lock event carries no `Key` at all —
    /// it is about the account.
    var facetTags: [String] {
        switch self {
        case .actorAuthorized: return ["Key"]
        case .actorRevoked: return ["Key", "Revoked"]
        case .locked: return ["Locked"]
        case .unlockInitiated: return ["Unlocking"]
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
