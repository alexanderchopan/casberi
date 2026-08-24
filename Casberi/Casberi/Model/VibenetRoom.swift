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
struct VibenetScope: Equatable {
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
    private static let named: [(bit: UInt16, label: String, plain: String)] = [
        (sender,       "Sender",        "Send any"),
        (policy,       "Policy",        "Send limited"),
        (nonce,        "Nonce",         "Nonce"),
        (selfPayer,    "Self-payer",    "Pay own gas"),
        (sponsorPayer, "Sponsor-payer", "Pay others"),
    ]

    var names: [String] {
        VibenetScope.named.filter { raw & $0.bit != 0 }.map(\.label)
    }

    /// The granted bits in PLAIN words — `plainSummary`'s comma-joined
    /// sentence and `grantedPlainLabels`' separate chips (R3.1) both read
    /// off this one list, so the two forms of this card never teach two
    /// different names for one permission.
    var plainNames: [String] {
        VibenetScope.named.filter { raw & $0.bit != 0 }.map(\.plain)
    }

    /// R3.1 — the granted permissions as SEPARATE chip labels, replacing the
    /// matrix: `plainNames` plus one trailing "+N unknown" element when a
    /// reserved bit is set (never an invented name for it, §83). Empty scope
    /// returns `[]` — the caller draws its own "can't originate anything
    /// yet" sentence rather than a chip row with nothing in it.
    var grantedPlainLabels: [String] {
        var parts = plainNames
        if unknownCount > 0 {
            parts.append(unknownCount == 1
                ? String(localized: "+1 unknown")
                : String(localized: "+\(unknownCount) unknown"))
        }
        return parts
    }

    /// "Send any, Pay own gas" / "Send any, +1 unknown" / "No permissions".
    var plainSummary: String {
        var parts = plainNames
        if unknownCount > 0 {
            parts.append(unknownCount == 1
                ? String(localized: "+1 unknown")
                : String(localized: "+\(unknownCount) unknown"))
        }
        guard !parts.isEmpty else { return String(localized: "No permissions") }
        return parts.joined(separator: ", ")
    }

    /// Set bits past `known` — counted, never named. Inventing a name for a
    /// reserved bit is exactly the fake status §83 bans; a count is the
    /// honest ceiling of what this build actually knows.
    var unknownCount: Int {
        (raw & ~VibenetScope.known).nonzeroBitCount
    }

    /// "Sender, Self-payer" / "Sender, Self-payer +1 more" / "+2 unknown" /
    /// "No scope". Zero is a real, valid state — an authorized actor that
    /// can originate nothing yet — so it gets its own honest word rather
    /// than reading as a blank line that looks like a read that failed.
    var summary: String {
        var parts = names
        if unknownCount > 0 {
            parts.append(unknownCount == 1
                ? String(localized: "+1 unknown")
                : String(localized: "+\(unknownCount) unknown"))
        }
        guard !parts.isEmpty else { return String(localized: "No scope") }
        return parts.joined(separator: ", ")
    }

    /// How many powers this key holds in total — named bits PLUS reserved
    /// ones, because a bit this build can't name is still a power the key
    /// carries. `byReach` (below) ranks keys by it so the most-privileged
    /// one is read first; treating every scope as equally weighted (the
    /// first cut, back when this was a matrix) meant SENDER — "may
    /// originate transactions to anyone" — got the same visual standing
    /// as NONCE, which is a sequencing detail.
    var grantedCount: Int { names.count + unknownCount }
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

/// Which of the Keystore's named authenticators an actor's key is, or a
/// custom one this build doesn't recognize. `Hashable` so `actorSummary`
/// can group a roster by kind without a hand-rolled key.
enum VibenetAuthenticatorKind: Equatable, Hashable, CaseIterable {
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
struct VibenetKeyMoment: Identifiable, Equatable {
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

struct VibenetActor: Identifiable, Equatable {
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
}

struct VibenetAccountItem: Identifiable, Equatable {
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

    /// The one alarm-worthy fact (the task's own ruling): a locked account.
    /// Deliberately NOT "not established" — an account that has never done
    /// anything isn't broken, it just hasn't been used yet.
    var alarmed: Bool { locked }

    init(address: String, reached: Bool, established: Bool, actors: [VibenetActor],
         locked: Bool, hasInitiatedUnlock: Bool, unlocksAt: UInt64?, unlockDelay: UInt16?,
         changeSequences: VibenetChangeSequences? = nil, history: [VibenetKeyMoment] = []) {
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

    /// The MATRIX's column order: most powers first, so the key that can do
    /// the most is the first one read. Distinct from `orderedActors` above
    /// and deliberately so — that one answers "what kinds of key are on this
    /// account" (a roster, best in the contract's own declaration order),
    /// this one answers "which key should I look at first" (a ranking).
    /// Falls back to `orderedActors`' rule on a tie, so it stays TOTAL and
    /// the columns can never reshuffle between opens.
    static func byReach(_ actors: [VibenetActor]) -> [VibenetActor] {
        actors.sorted { a, b in
            if a.scope.grantedCount != b.scope.grantedCount {
                return a.scope.grantedCount > b.scope.grantedCount
            }
            if a.kind.sortRank != b.kind.sortRank { return a.kind.sortRank < b.kind.sortRank }
            return a.actorId < b.actorId
        }
    }
}

// MARK: - The room

struct VibenetRoom: Equatable {
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
    static func rowLine(_ item: VibenetAccountItem) -> String {
        guard item.reached else { return String(localized: "Couldn't reach the chain") }
        guard item.established else { return String(localized: "Not established yet") }
        guard !item.actors.isEmpty else { return String(localized: "No keys authorized") }
        return item.actors.count == 1
            ? String(localized: "1 key")
            : String(localized: "\(item.actors.count) keys")
    }

    /// The one sentence at the top of the card.
    static func headline(_ room: VibenetRoom) -> String {
        guard room.configReached else {
            return String(localized: "Couldn't read vibenet's current contracts")
        }
        guard !room.items.isEmpty else {
            return String(localized: "Nothing watched on vibenet yet")
        }
        if room.lockedCount > 0 {
            return room.lockedCount == 1
                ? String(localized: "1 watched account is locked")
                : String(localized: "\(room.lockedCount) watched accounts are locked")
        }
        let unreached = room.items.filter { !$0.reached }.count
        if unreached == room.items.count {
            return String(localized: "Couldn't reach vibenet for any watched account")
        }
        if room.establishedCount == 0 {
            return room.items.count == 1
                ? String(localized: "Not established yet")
                : String(localized: "None of these are established yet")
        }
        return room.items.count == 1
            ? String(localized: "1 account established on vibenet")
            : String(localized: "\(room.establishedCount) of \(room.items.count) established on vibenet")
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

    /// The line under it — the config's own provenance, since vibenet's
    /// contracts rotate and a stale screenshot is exactly the failure mode
    /// this whole feature is built to avoid.
    static func note(_ room: VibenetRoom) -> String {
        guard room.configReached else {
            return String(localized: "vibenet is an experimental devnet — its contracts redeploy often, and this read couldn't reach the current set.")
        }
        let commit = room.commit.map { String($0.prefix(9)) }
        // The single most on-theme fact this room can report — leads over
        // the plain provenance line whenever it's true, since it's not just
        // "here's when this was read", it's "the ground moved since you were
        // last here, and everything below was already re-checked against it".
        if room.redeployedSinceLastSeen, let commit {
            return String(localized: "vibenet redeployed since you last checked — now at commit \(commit), and every watched account was just re-read against it.")
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
                // via `.identify` against a live config — so these three
                // addresses are never compared against anything and their
                // exact value is cosmetic. They deliberately do NOT start
                // "0x8130…" (vibenet's own vanity prefix, see `shortAddress`'s
                // doc below): the drift guard that forbids a hardcoded
                // vibenet contract address anywhere outside a comment can't
                // tell a demo fixture from a live call, and it shouldn't have
                // to — a fake address that merely LOOKS unlike a real
                // contract is the simpler fix.
                VibenetActor(actorId: "0x0000000000000000000000000000000000000000000000000000000000000002",
                             authenticator: "0xaaaa1111222233334444555566667777888899aa",
                             kind: .p256, scope: VibenetScope(raw: VibenetScope.sender), expiry: 0),
                VibenetActor(actorId: "0x0000000000000000000000000000000000000000000000000000000000000003",
                             authenticator: "0xbbbb1111222233334444555566667777888899bb",
                             kind: .webAuthn, scope: VibenetScope(raw: VibenetScope.policy | VibenetScope.nonce),
                             expiry: 0),
                VibenetActor(actorId: "0x0000000000000000000000000000000000000000000000000000000000000004",
                             authenticator: "0xcccc1111222233334444555566667777888899cc",
                             kind: .delegate, scope: VibenetScope(raw: VibenetScope.sponsorPayer), expiry: 0),
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
            ]))

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
            locked: true, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil)

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

// MARK: - Multichain sync standing

/// `Keystore.getChangeSequences(address)`'s own three fields, in its own
/// declared order — how far THIS chain's copy of an account's config has
/// progressed. `multichain` is the count of changes applied off the
/// multichain channel (`chain_id = 0`, per the EIP's own spec — a config
/// change made there is meant to apply on every chain the account exists
/// on); `localEpoch`/`localSequence` are this chain's own local-only
/// history, which has no cross-chain meaning at all.
struct VibenetChangeSequences: Equatable {
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
        }
    }
}
