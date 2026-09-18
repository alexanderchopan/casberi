import Foundation

/// THE KIND TILES OF THE SAFE, GITHUB AND STRIPE ROOMS (prd §815).
///
/// The wallet family and Privy scope their rooms with `DSScopeTiles`; these
/// three rooms scope theirs the same way, on the same template, so the tiles
/// sit at one height in every room (user, 2026-09-18: "that is a template. we
/// follow it in all rooms, so the buttons can't be in different places on
/// each screen"). What differs is only what a tile HOLDS: here a tile is a
/// kind of row, read off the row's own ref, URL or tags — never its title.
///
/// **All is always first, and the room opens on it** ("for all of them we need
/// a button that is 'all'"). A tile is offered only over at least one row of
/// its kind (§83: a tile over nothing is a dead control), and a room with fewer
/// than TWO kinds draws no tiles at all — All beside one kind draws the same
/// list twice, which is the §805 Privy defect.
///
/// Foundation-only, so `scripts/room-kind-tiles-selftest.sh` compiles it whole
/// (with `GitHubRowTag.swift` and its `GitHubLinks` dependency). The glyphs are
/// `ScopeTileGlyphs.swift`'s, where every tile glyph in the app is one table.
enum RoomKindTile: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    // Safe
    case queue, activity, permissions
    // GitHub
    case pullRequests, issues, releases
    // Stripe
    case payments, payouts, disputes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:          return String(localized: "All")
        case .queue:        return String(localized: "Queue")
        case .activity:     return String(localized: "Activity")
        case .permissions:  return String(localized: "Permissions")
        case .pullRequests: return String(localized: "Pull requests")
        case .issues:       return String(localized: "Issues")
        case .releases:     return String(localized: "Releases")
        case .payments:     return String(localized: "Payments")
        case .payouts:      return String(localized: "Payouts")
        case .disputes:     return String(localized: "Disputes")
        }
    }

    var summary: String {
        switch self {
        case .all:          return String(localized: "Everything in this room")
        case .queue:        return String(localized: "Transactions waiting for signatures")
        case .activity:     return String(localized: "What was signed, executed or replaced")
        case .permissions:  return String(localized: "Owners, threshold, modules and guards")
        case .pullRequests: return String(localized: "Pull requests")
        case .issues:       return String(localized: "Issues")
        case .releases:     return String(localized: "Releases")
        case .payments:     return String(localized: "Failed, recovered and canceled payments")
        case .payouts:      return String(localized: "Money paid out to your bank")
        case .disputes:     return String(localized: "Disputes opened and closed")
        }
    }
}

enum RoomKindTiles {

    /// The rooms that carry kind tiles. The source names are spelled here
    /// because the harness cannot compile the bridges; the selftest holds them
    /// to `SafeBridge.sourceName`, `StripeWatch.source` and the GitHub seat.
    enum Room: String, CaseIterable, Sendable {
        case safe, github, stripe

        init?(source: String) {
            switch source {
            case "Safe":   self = .safe
            case "GitHub": self = .github
            case "Stripe": self = .stripe
            default:       return nil
            }
        }

        var source: String {
            switch self {
            case .safe:   return "Safe"
            case .github: return "GitHub"
            case .stripe: return "Stripe"
            }
        }

        /// Every tile the room could offer, All first, in drawing order.
        var order: [RoomKindTile] {
            switch self {
            case .safe:   return [.all, .queue, .activity, .permissions]
            case .github: return [.all, .pullRequests, .issues, .releases]
            case .stripe: return [.all, .payments, .payouts, .disputes]
            }
        }
    }

    // MARK: - Safe's ref family

    /// ORDER MATTERS: `wallet:safe:` is a prefix of none of the others, but a
    /// test written as `hasPrefix("wallet:safe")` claims all four, so each is
    /// matched with its closing colon and the pending one is matched exactly.
    static let safePending  = "wallet:safe:"
    static let safeOutcome  = "wallet:safeoutcome:"
    static let safeSigned   = "wallet:safesigned:"
    static let safeConfig   = "wallet:safeconfig:"

    /// `<seg>:<safeTxHash>` — the tail a pending ref and its outcome share
    /// (`SafeBridge.landOutcome` builds the outcome from the pending ref's
    /// last segment).
    static func safeTail(_ ref: String, prefix: String) -> String? {
        guard ref.hasPrefix(prefix) else { return nil }
        let tail = String(ref.dropFirst(prefix.count)).lowercased()
        return tail.isEmpty ? nil : tail
    }

    // MARK: - The census

    /// What a room's rows hold, read once over the whole room, so a row's kind
    /// can depend on its siblings — the one case being Safe's queue, where a
    /// pending row SURVIVES its execution (`SafeBridge.landOutcome` lands a
    /// new outcome row and never deletes the pending one). A pending row whose
    /// outcome has landed is history: it shows under All only, and its outcome
    /// row is in Activity.
    struct Census: Sendable {
        let room: Room
        /// Safe: the `<seg>:<hash>` tails of every landed outcome.
        var resolvedSafe: Set<String> = []

        init(room: Room, refs: [String?]) {
            self.room = room
            guard room == .safe else { return }
            for ref in refs {
                if let ref, let tail = RoomKindTiles.safeTail(ref, prefix: RoomKindTiles.safeOutcome) {
                    resolvedSafe.insert(tail)
                }
            }
        }

        /// The row's kind in this room, or nil when it belongs to All alone
        /// (Stripe's runway and silence alerts; GitHub's stars, gists,
        /// activity and watches; an executed Safe transaction's pending row).
        func kind(ref: String?, url: String?, tags: [String]) -> RoomKindTile? {
            switch room {
            case .safe:
                guard let ref else { return nil }
                if ref.hasPrefix(RoomKindTiles.safeOutcome) || ref.hasPrefix(RoomKindTiles.safeSigned) {
                    return .activity
                }
                if ref.hasPrefix(RoomKindTiles.safeConfig) { return .permissions }
                if let tail = RoomKindTiles.safeTail(ref, prefix: RoomKindTiles.safePending) {
                    return resolvedSafe.contains(tail) ? nil : .queue
                }
                return nil
            case .github:
                switch GitHubRowTag.kind(ref: ref, url: url) {
                case .pullRequest: return .pullRequests
                case .issue:       return .issues
                case .release:     return .releases
                default:           return nil
                }
            case .stripe:
                // Events only: the runway and silence alerts are about the
                // account, not a kind of event, and show under All.
                guard ref?.hasPrefix("stripe:event:") == true else { return nil }
                if tags.contains("Dispute") { return .disputes }
                if tags.contains("Payout") { return .payouts }
                // `invoice.payment_failed`, `invoice.payment_succeeded` (a
                // recovery) and `customer.subscription.deleted`.
                if tags.contains("Dunning") || tags.contains("Churn") { return .payments }
                return nil
            }
        }
    }

    // MARK: - Tiles

    /// The tiles to draw: All, then every kind present, in the room's order —
    /// or none, when fewer than two kinds are present.
    static func present(room: Room, kinds: Set<RoomKindTile>) -> [RoomKindTile] {
        let shown = room.order.filter { $0 != .all && kinds.contains($0) }
        guard shown.count >= 2 else { return [] }
        return [.all] + shown
    }

    /// A pick whose kind is no longer offered falls back to All.
    static func resolve(_ pick: RoomKindTile, present: [RoomKindTile]) -> RoomKindTile {
        present.contains(pick) ? pick : .all
    }

    /// Whether a row of `kind` shows under `pick`.
    static func allows(_ pick: RoomKindTile, kind: RoomKindTile?) -> Bool {
        pick == .all || kind == pick
    }

    // MARK: - Stripe's open disputes

    /// How many disputes are open: an opened dispute with no closing row for
    /// the same dispute. Both rows carry the dispute's dashboard URL (the
    /// closing row's `resolves` is that URL), and the opening title is the
    /// bridge's fixed English literal "Dispute opened".
    static func openDisputes(_ rows: [(url: String?, tags: [String], title: String)]) -> Int {
        var opened: Set<String> = []
        var closed: Set<String> = []
        for row in rows where row.tags.contains("Dispute") {
            guard let url = row.url, !url.isEmpty else { continue }
            if row.title.hasPrefix("Dispute opened") { opened.insert(url) } else { closed.insert(url) }
        }
        return opened.subtracting(closed).count
    }
}
