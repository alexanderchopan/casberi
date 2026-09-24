import Foundation

/// THE KIND TILES OF THE SAFE, GITHUB AND STRIPE ROOMS (prd §815), AND OF
/// APP STORE CONNECT, HUGGING FACE, POSTHOG, L2BEAT AND WALLETBEAT (prd §820), AND OF
/// SPLITS (prd §820), AND — SINCE prd §911 — OF EVERY ROOM WHOSE ROWS ALREADY
/// CARRY A KIND: Polar, Dodo Payments, GitLab, Radicle, Sentry, Vercel,
/// PagerDuty, npm, PyPI, AWS, Cursor and Apple Health.
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
    // Splits (prd §820) — its Queue and Activity are Safe's cases above.
    case accounts
    // prd §911 — the rooms whose rows already carried a kind and drew no
    // tiles. A meaning two rooms share is one case (Sales and Disputes in
    // Polar and Dodo Payments; Deploys in Vercel and AWS; Failed in Vercel
    // and Cursor; Issues in GitLab and Radicle beside GitHub).
    case sales, subscriptions
    case mergeRequests, patches
    case errors, regressions
    case deploys, failed
    case alarms, costs
    case incidents, resolved
    case deprecations
    case workouts, sleep, mood

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
        case .accounts:     return String(localized: "Accounts")
        case .sales:         return String(localized: "Sales")
        case .subscriptions: return String(localized: "Subscriptions")
        case .mergeRequests: return String(localized: "Merge requests")
        case .patches:       return String(localized: "Patches")
        case .errors:        return String(localized: "Errors")
        case .regressions:   return String(localized: "Regressions")
        case .deploys:       return String(localized: "Deploys")
        case .failed:        return String(localized: "Failed")
        case .alarms:        return String(localized: "Alarms")
        case .costs:         return String(localized: "Costs")
        case .incidents:     return String(localized: "Incidents")
        case .resolved:      return String(localized: "Resolved")
        case .deprecations:  return String(localized: "Deprecations")
        case .workouts:      return String(localized: "Workouts")
        case .sleep:         return String(localized: "Sleep")
        case .mood:          return String(localized: "Mood")
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
        case .accounts:     return String(localized: "Your team's accounts")
        case .sales:         return String(localized: "Money that came in")
        case .subscriptions: return String(localized: "Started, renewed, canceled and recovered")
        case .mergeRequests: return String(localized: "Merge requests")
        case .patches:       return String(localized: "Patches proposed and merged")
        case .errors:        return String(localized: "Issues that opened")
        case .regressions:   return String(localized: "Issues that came back or escalated")
        case .deploys:       return String(localized: "Deploys that went out")
        case .failed:        return String(localized: "What did not finish")
        case .alarms:        return String(localized: "Alarms that changed state")
        case .costs:         return String(localized: "Spend that broke its pattern")
        case .incidents:     return String(localized: "Incidents that triggered")
        case .resolved:      return String(localized: "Incidents that resolved")
        case .deprecations:  return String(localized: "Packages marked deprecated")
        case .workouts:      return String(localized: "Workouts")
        case .sleep:         return String(localized: "Nights of sleep")
        case .mood:          return String(localized: "Moods you logged")
        }
    }
}

enum RoomKindTiles {

    /// The rooms that carry kind tiles. The source names are spelled here
    /// because the harness cannot compile the bridges; the selftest holds them
    /// to `SafeBridge.sourceName`, `StripeWatch.source`, the GitHub seat,
    /// `ASCShape.source` and the Hugging Face seat.
    enum Room: String, CaseIterable, Sendable {
        case safe, github, stripe, appStoreConnect, huggingFace, posthog, l2beat, walletbeat, splits
        // prd §911.
        case polar, dodoPayments, gitlab, radicle, sentry, vercel, pagerduty, npm, pypi, aws, cursor, appleHealth

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
            case "Splits":            self = .splits
            case "Polar":             self = .polar
            case "Dodo Payments":     self = .dodoPayments
            case "GitLab":            self = .gitlab
            case "Radicle":           self = .radicle
            case "Sentry":            self = .sentry
            case "Vercel":            self = .vercel
            case "PagerDuty":         self = .pagerduty
            case "npm":               self = .npm
            case "PyPI":              self = .pypi
            case "AWS":               self = .aws
            case "Cursor":            self = .cursor
            case "Apple Health":      self = .appleHealth
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
            case .splits:          return "Splits"
            case .polar:           return "Polar"
            case .dodoPayments:    return "Dodo Payments"
            case .gitlab:          return "GitLab"
            case .radicle:         return "Radicle"
            case .sentry:          return "Sentry"
            case .vercel:          return "Vercel"
            case .pagerduty:       return "PagerDuty"
            case .npm:             return "npm"
            case .pypi:            return "PyPI"
            case .aws:             return "AWS"
            case .cursor:          return "Cursor"
            case .appleHealth:     return "Apple Health"
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
            case .splits:          return [.all, .accounts, .queue, .activity]
            // The two Merchants of Record share Stripe's Disputes and one
            // Sales/Subscriptions vocabulary (prd §911). Four tiles, one full
            // row: a fifth wrapped alone onto a second (measured), so a
            // refund is All only.
            case .polar, .dodoPayments: return [.all, .sales, .subscriptions, .disputes]
            case .gitlab:          return [.all, .mergeRequests, .issues]
            case .radicle:         return [.all, .patches, .issues]
            case .sentry:          return [.all, .errors, .regressions]
            case .vercel:          return [.all, .deploys, .failed]
            case .pagerduty:       return [.all, .incidents, .resolved]
            case .npm, .pypi:      return [.all, .releases, .deprecations]
            case .aws:             return [.all, .alarms, .deploys, .costs]
            // A run that opened a pull request, or one that did not finish;
            // a plain finished run is All only.
            case .cursor:          return [.all, .pullRequests, .failed]
            case .appleHealth:     return [.all, .workouts, .sleep, .mood]
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
    /// Splits' rows (`SplitsShape.accountPrefix`, `.txPrefix`), spelled here
    /// for the harness (prd §820).
    static let splitsAccount     = "splits:account:"
    static let splitsTx          = "splits:tx:"
    /// prd §911 — the ref families the twelve new rooms land, spelled here
    /// for the harness. Where a bridge ALSO tags the row (Polar's and Dodo's
    /// `tag`, Radicle's, Vercel's, Cursor's facets), the tag is read as well,
    /// because the demo's rows carry `demo:` refs and the real tags.
    static let polarOrder        = "polar:order:"
    static let polarSubscription = "polar:subscription:"
    static let polarRefund       = "polar:refund:"
    static let polarDispute      = "polar:dispute:"
    static let dodoPayment       = "dodopayments:payment:"
    static let dodoSubscription  = "dodopayments:subscription:"
    static let dodoRefund        = "dodopayments:refund:"
    static let dodoDispute       = "dodopayments:dispute:"
    static let gitlabIssue       = "gitlab:issue:"
    static let gitlabMR          = "gitlab:mr:"
    static let radiclePatch      = "radicle:patch:"
    static let radicleIssue      = "radicle:issue:"
    /// `sentry:issue:<id>` is a new issue; a crossing is
    /// `sentry:<substatus>:<id>:<n>` with `regressed` or `escalating`.
    static let sentryIssue       = "sentry:issue:"
    static let sentryRegressed   = "sentry:regressed:"
    static let sentryEscalating  = "sentry:escalating:"
    static let vercelDeploy      = "vercel:deploy:"
    static let vercelFailureTag  = "Build failure"
    static let pagerdutyIncident = "pagerduty:incident:"
    static let pagerdutyResolved = "pagerduty:resolved:"
    /// `<registry>:release:` / `<registry>:deprecated:` — the registry's raw
    /// value, `npm` or `pypi`.
    static let packageRelease    = ":release:"
    static let packageDeprecated = ":deprecated:"
    static let awsAlarm          = "aws:alarm:"
    static let awsPipeline       = "aws:pipeline:"
    static let awsCost           = "aws:costanomaly:"
    /// Cursor's outcome facets (`CursorAgentStatus.facetTags`) and its PR
    /// tag, spelled here for the harness.
    static let cursorRun         = "cursor:agent:"
    static let cursorFailedTags: Set<String> = ["Failed", "Expired", "Cancelled"]
    static let cursorPRTag       = "PR"
    static let healthWorkout     = "hkworkout:"
    static let healthSleep       = "hksleep:"
    static let healthMood        = "hkmood:"

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
            case .splits:
                guard let ref else { return nil }
                if ref.hasPrefix(RoomKindTiles.splitsAccount) { return .accounts }
                // A proposal waiting on signatures is Queue — Safe's meaning,
                // so Safe's case — and a scheduled payment lands as one
                // (prd §820). `SplitsShape.waitingTag`.
                if ref.hasPrefix(RoomKindTiles.splitsTx) { return tags.contains("Waiting") ? .queue : .activity }
                return nil
            case .polar:
                // The bridge's own `tag` rides first in `tags`; the ref
                // agrees. Read both so the demo's `demo:` rows sort too.
                if ref?.hasPrefix(RoomKindTiles.polarDispute) == true || tags.contains("Dispute") { return .disputes }
                // A refund is All only — checked before Sale so a refunded
                // order never counts as money that came in.
                if ref?.hasPrefix(RoomKindTiles.polarRefund) == true || tags.contains("Refund") { return nil }
                if ref?.hasPrefix(RoomKindTiles.polarSubscription) == true || tags.contains("Subscription") { return .subscriptions }
                if ref?.hasPrefix(RoomKindTiles.polarOrder) == true || tags.contains("Sale") { return .sales }
                return nil
            case .dodoPayments:
                if ref?.hasPrefix(RoomKindTiles.dodoDispute) == true || tags.contains("Dispute") { return .disputes }
                if ref?.hasPrefix(RoomKindTiles.dodoRefund) == true || tags.contains("Refund") { return nil }
                if ref?.hasPrefix(RoomKindTiles.dodoSubscription) == true || tags.contains("Subscription") { return .subscriptions }
                if ref?.hasPrefix(RoomKindTiles.dodoPayment) == true || tags.contains("Payment") { return .sales }
                return nil
            case .gitlab:
                guard let ref else { return nil }
                if ref.hasPrefix(RoomKindTiles.gitlabMR) { return .mergeRequests }
                if ref.hasPrefix(RoomKindTiles.gitlabIssue) { return .issues }
                return nil
            case .radicle:
                if ref?.hasPrefix(RoomKindTiles.radiclePatch) == true || tags.contains("Patch") { return .patches }
                if ref?.hasPrefix(RoomKindTiles.radicleIssue) == true || tags.contains("Issue") { return .issues }
                return nil
            case .sentry:
                guard let ref else { return nil }
                if ref.hasPrefix(RoomKindTiles.sentryIssue) { return .errors }
                if ref.hasPrefix(RoomKindTiles.sentryRegressed) || ref.hasPrefix(RoomKindTiles.sentryEscalating) {
                    return .regressions
                }
                return nil
            case .vercel:
                guard ref?.hasPrefix(RoomKindTiles.vercelDeploy) == true else { return nil }
                return tags.contains(RoomKindTiles.vercelFailureTag) ? .failed : .deploys
            case .pagerduty:
                guard let ref else { return nil }
                if ref.hasPrefix(RoomKindTiles.pagerdutyIncident) { return .incidents }
                if ref.hasPrefix(RoomKindTiles.pagerdutyResolved) { return .resolved }
                return nil
            case .npm, .pypi:
                guard let ref, ref.hasPrefix(room == .npm ? "npm" : "pypi") else { return nil }
                if ref.contains(RoomKindTiles.packageRelease) { return .releases }
                if ref.contains(RoomKindTiles.packageDeprecated) { return .deprecations }
                return nil
            case .aws:
                // The bridge's tags are LOCALIZED (`String(localized: "Alarm")`),
                // so the ref decides for a real row and the tag only catches
                // the demo's `demo:` rows, which are English.
                if ref?.hasPrefix(RoomKindTiles.awsAlarm) == true || tags.contains("Alarm") { return .alarms }
                if ref?.hasPrefix(RoomKindTiles.awsPipeline) == true || tags.contains("Deploy") { return .deploys }
                if ref?.hasPrefix(RoomKindTiles.awsCost) == true || tags.contains("Cost") { return .costs }
                return nil
            case .cursor:
                // Failed before PR: a run that opened a pull request and then
                // expired is the one somebody has to go back to.
                if tags.contains(where: { RoomKindTiles.cursorFailedTags.contains($0) }) { return .failed }
                if tags.contains(RoomKindTiles.cursorPRTag) { return .pullRequests }
                return nil
            case .appleHealth:
                guard let ref else { return nil }
                if ref.hasPrefix(RoomKindTiles.healthWorkout) { return .workouts }
                if ref.hasPrefix(RoomKindTiles.healthSleep) { return .sleep }
                if ref.hasPrefix(RoomKindTiles.healthMood) { return .mood }
                return nil
            }
        }
    }

    // MARK: - Tiles

    /// The tiles to draw: All, then every kind present, in the room's order —
    /// or none, when no pick would change the list.
    ///
    /// A pick changes the list when two kinds are present, OR when one is and
    /// some row belongs to no tile (`hasUnkinded`: it shows under All only).
    /// §805's defect was All beside a kind that IS the whole room; a GitHub
    /// room of watched-repo Activity plus two pull requests is not that — its
    /// Pull requests tile narrows to two rows (user, 2026-09-18: "i already
    /// have at least two pull requests").
    static func present(room: Room, kinds: Set<RoomKindTile>,
                        hasUnkinded: Bool = false) -> [RoomKindTile] {
        let shown = room.order.filter { $0 != .all && kinds.contains($0) }
        guard shown.count >= 2 || (shown.count == 1 && hasUnkinded) else { return [] }
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
