import Foundation

/// THE KIND TILES OF THE SAFE, GITHUB AND STRIPE ROOMS (prd §815), AND OF
/// APP STORE CONNECT, HUGGING FACE, POSTHOG, L2BEAT AND WALLETBEAT (prd §816).
///
/// **Where a room has a head, the tiles ride its `scopes:` slot** — the Privy
/// pattern, `DSRoomChassis.Head`'s own geometry — and the head stays exactly as
/// it was (user, 2026-09-18: "keep the safe head the way it was"). Only a room
/// with no head drawn leads with its cover and draws the tiles under it.
///
/// The wallet family and Privy scope their rooms with `DSScopeTiles`; these
/// rooms scope theirs the same way, on the same template, so the tiles
/// sit at one height in every room (user, 2026-09-18: "that is a template. we
/// follow it in all rooms, so the buttons can't be in different places on
/// each screen"). What differs is only what a tile HOLDS: here a tile is a
/// kind of row, read off the row's own ref, URL or tags — never its title.
///
/// **One case per MEANING, never per room** (user, 2026-09-18: "you can't
/// reuse an existing icon we use for a different type of tile, and you can't
/// make up new icons for existing icons we have"). A meaning two rooms share
/// is one case here and one glyph in `ScopeTileGlyph`.
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
    // App Store Connect (prd §816)
    case versions, reviews, builds
    // Hugging Face (prd §816)
    case models, datasets, papers
    // PostHog (prd §816)
    case metrics, annotations, milestones
    // L2BEAT and Walletbeat (prd §816) — News and Revisions are ONE meaning in
    // both rooms, so one case each and one glyph each.
    case chains, wallets, news, revisions

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
        case .versions:     return String(localized: "Versions")
        case .reviews:      return String(localized: "Reviews")
        case .builds:       return String(localized: "Builds")
        case .models:       return String(localized: "Models")
        case .datasets:     return String(localized: "Datasets")
        case .papers:       return String(localized: "Papers")
        case .metrics:      return String(localized: "Metrics")
        case .annotations:  return String(localized: "Annotations")
        case .milestones:   return String(localized: "Milestones")
        case .chains:       return String(localized: "Chains")
        case .wallets:      return String(localized: "Wallets")
        case .news:         return String(localized: "News")
        case .revisions:    return String(localized: "Revisions")
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
        case .versions:     return String(localized: "App versions and their review verdicts")
        case .reviews:      return String(localized: "Customer reviews")
        case .builds:       return String(localized: "Builds processed for testing")
        case .models:       return String(localized: "New models")
        case .datasets:     return String(localized: "New datasets")
        case .papers:       return String(localized: "Daily papers")
        case .metrics:      return String(localized: "The metrics you watch")
        case .annotations:  return String(localized: "Annotations on your charts")
        case .milestones:   return String(localized: "Milestones your metrics reached")
        case .chains:       return String(localized: "The chains you watch")
        case .wallets:      return String(localized: "The wallets you watch")
        case .news:         return String(localized: "Milestones and incidents")
        case .revisions:    return String(localized: "Changes to a rating")
        }
    }
}

enum RoomKindTiles {

    /// The rooms that carry kind tiles. The source names are spelled here
    /// because the harness cannot compile the bridges; the selftest holds them
    /// to `SafeBridge.sourceName`, `StripeWatch.source`, the GitHub seat,
    /// `ASCShape.source` and the Hugging Face seat.
    enum Room: String, CaseIterable, Sendable {
        case safe, github, stripe, appStoreConnect, huggingFace, posthog, l2beat, walletbeat

        init?(source: String) {
            switch source {
            case "Safe":              self = .safe
            case "GitHub":            self = .github
            case "Stripe":            self = .stripe
            case "App Store Connect": self = .appStoreConnect
            case "Hugging Face":      self = .huggingFace
            case "PostHog":           self = .posthog
            case "L2BEAT":            self = .l2beat
            case "Walletbeat":        self = .walletbeat
            default:                  return nil
            }
        }

        var source: String {
            switch self {
            case .safe:            return "Safe"
            case .github:          return "GitHub"
            case .stripe:          return "Stripe"
            case .appStoreConnect: return "App Store Connect"
            case .huggingFace:     return "Hugging Face"
            case .posthog:         return "PostHog"
            case .l2beat:          return "L2BEAT"
            case .walletbeat:      return "Walletbeat"
            }
        }

        /// Every tile the room could offer, All first, in drawing order.
        var order: [RoomKindTile] {
            switch self {
            case .safe:   return [.all, .queue, .activity, .permissions]
            case .github: return [.all, .pullRequests, .issues, .releases]
            case .stripe: return [.all, .payments, .payouts, .disputes]
            case .appStoreConnect: return [.all, .versions, .reviews, .builds]
            case .huggingFace:     return [.all, .models, .datasets, .papers]
            case .posthog:         return [.all, .metrics, .annotations, .milestones]
            case .l2beat:          return [.all, .chains, .news, .revisions]
            case .walletbeat:      return [.all, .wallets, .news, .revisions]
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

    // MARK: - App Store Connect's and Hugging Face's ref families (prd §816)

    /// Each matched WITH its closing colon: `asc:build` is a prefix of
    /// `asc:buildexpiry:`, the expiry warning, which is All only.
    static let ascVersion = "asc:version:"
    static let ascReview  = "asc:review:"
    static let ascBuild   = "asc:build:"
    /// `hf:<repo>:<id>` for a watched author's release (`HuggingFaceRepo`'s
    /// raw value) and `hf:paper:<arxiv id>` for a daily paper. A Space is
    /// `hf:space:` and is All only.
    static let hfModel    = "hf:model:"
    static let hfDataset  = "hf:dataset:"
    static let hfPaper    = "hf:paper:"
    /// PostHog: `posthog:metric:<event>`, `posthog:annotation:<id>`,
    /// `posthog:milestone:<event>:<n>`. A silence alert (`posthog:silence:`)
    /// is All only. `posthog:m` is a prefix of both the metric and the
    /// milestone, so the colon is part of every prefix.
    static let posthogMetric     = "posthog:metric:"
    static let posthogAnnotation = "posthog:annotation:"
    static let posthogMilestone  = "posthog:milestone:"
    /// L2BEAT's and Walletbeat's identities (`L2beatIdentity`,
    /// `WalletbeatIdentity`), spelled here for the harness.
    static let l2beatChain       = "l2beat:chain:"
    static let l2beatNews        = "l2beat:news:"
    static let l2beatRevision    = "l2beat:rev:"
    static let walletbeatWallet  = "walletbeat:wallet:"
    static let walletbeatNews    = "walletbeat:news:"
    static let walletbeatRevision = "walletbeat:rev:"

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
        /// activity and watches; an executed Safe transaction's pending row;
        /// App Store Connect's build-expiry warning; Hugging Face's Spaces;
        /// PostHog's silence alerts).
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
            case .appStoreConnect:
                guard let ref else { return nil }
                if ref.hasPrefix(RoomKindTiles.ascVersion) { return .versions }
                if ref.hasPrefix(RoomKindTiles.ascReview) { return .reviews }
                if ref.hasPrefix(RoomKindTiles.ascBuild) { return .builds }
                return nil
            case .huggingFace:
                guard let ref else { return nil }
                if ref.hasPrefix(RoomKindTiles.hfModel) { return .models }
                if ref.hasPrefix(RoomKindTiles.hfDataset) { return .datasets }
                if ref.hasPrefix(RoomKindTiles.hfPaper) { return .papers }
                return nil
            case .posthog:
                guard let ref else { return nil }
                if ref.hasPrefix(RoomKindTiles.posthogMetric) { return .metrics }
                if ref.hasPrefix(RoomKindTiles.posthogAnnotation) { return .annotations }
                if ref.hasPrefix(RoomKindTiles.posthogMilestone) { return .milestones }
                return nil
            case .l2beat:
                guard let ref else { return nil }
                if ref.hasPrefix(RoomKindTiles.l2beatChain) { return .chains }
                if ref.hasPrefix(RoomKindTiles.l2beatNews) { return .news }
                if ref.hasPrefix(RoomKindTiles.l2beatRevision) { return .revisions }
                return nil
            case .walletbeat:
                guard let ref else { return nil }
                if ref.hasPrefix(RoomKindTiles.walletbeatWallet) { return .wallets }
                if ref.hasPrefix(RoomKindTiles.walletbeatNews) { return .news }
                if ref.hasPrefix(RoomKindTiles.walletbeatRevision) { return .revisions }
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
