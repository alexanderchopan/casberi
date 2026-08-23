import Foundation

/// THE VIBENET ROOM — what a watched account's account-abstraction state
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
    private static let named: [(bit: UInt16, label: String)] = [
        (sender, "Sender"), (policy, "Policy"), (nonce, "Nonce"),
        (selfPayer, "Self-payer"), (sponsorPayer, "Sponsor-payer"),
    ]

    var names: [String] {
        VibenetScope.named.filter { raw & $0.bit != 0 }.map(\.label)
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
enum VibenetAuthenticatorKind: Equatable, Hashable {
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

    /// The one alarm-worthy fact (the task's own ruling): a locked account.
    /// Deliberately NOT "not established" — an account that has never done
    /// anything isn't broken, it just hasn't been used yet.
    var alarmed: Bool { locked }

    init(address: String, reached: Bool, established: Bool, actors: [VibenetActor],
         locked: Bool, hasInitiatedUnlock: Bool, unlocksAt: UInt64?, unlockDelay: UInt16?) {
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
    }

    /// By kind, then actorId — TOTAL, so a card reshuffling its own actor
    /// list between opens over an unchanged roster reads as broken.
    static func orderedActors(_ actors: [VibenetActor]) -> [VibenetActor] {
        actors.sorted { a, b in
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

    /// The row's own line — what a person reads under the address.
    static func rowLine(_ item: VibenetAccountItem) -> String {
        if item.locked {
            return item.hasInitiatedUnlock
                ? String(localized: "Locked — unlock initiated")
                : String(localized: "Locked")
        }
        guard item.reached else { return String(localized: "Couldn't reach the chain") }
        guard item.established else { return String(localized: "Not established yet") }
        return actorSummary(item.actors)
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

    /// "0x8130…40ac" — a devnet test address, shown in the middle-elided
    /// form people recognize from an explorer, rather than
    /// `WalletStore.shortAddress`'s tail-only form (that ruling is about a
    /// real wallet's poisoning-lookalike risk on a personal name; a pasted
    /// devnet address has neither).
    static func shortAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
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
}
