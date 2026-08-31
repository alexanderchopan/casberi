import Foundation
import SwiftData

/// The cross-source cluster derivations — what's left of the old Home board
/// composer after the Pinned board retired (2026-07-20, docs/agent-brief.md
/// rulings 11-12). The board's own composition (`compose`/`daily`,
/// `appendPinnedApps`, `appendWalletHoldings`, the cover, `awayLine`,
/// `boardSources`) is gone; the agent's `KeptAskComposers` reimplements the
/// away-window read independently now (the same parallel-reads pattern this
/// file and `RootShell` always used with each other, not a shared private
/// helper). What survives are the two derivations that outlived the board:
/// `projectClusters` (the tag-clustering the Themes treemap draws from,
/// `FeedScreen`'s own top-of-feed card since 2026-07-18) and `themesDocument`
/// itself, plus `MCPTools`'s week-synthesis tool, which reads
/// `projectClusters` directly.
enum HomeComposition {

    struct Cluster {
        let name: String
        let things: [Thing]
    }

    /// Until tags form, the map speaks in APPS: real things clustered by
    /// source (min 2, "You" included). Honest for a fresh corpus — bridge
    /// things arrive untagged, and a real user's Home earned no map at all.
    static func sourceClusters(things: [Thing]) -> [Cluster] {
        var buckets: [String: [Thing]] = [:]
        // `where thing.isLive` — this is called from a view body with a
        // caller-derived array, so a delete can land between the derive and
        // this loop. Guarding the SHARED helper covers every caller, which is
        // the half of corollary 2 that was written down and never enforced.
        for thing in things where thing.isLive {
            buckets[thing.source, default: []].append(thing)
        }
        return buckets
            .filter { $0.value.count >= 2 }
            .map { Cluster(name: $0.key, things: $0.value) }
            .sorted {
                $0.things.count != $1.things.count
                    ? $0.things.count > $1.things.count
                    : $0.name < $1.name
            }
    }

    /// THE TAGS A THEME IS NEVER MADE OF (2026-08-14).
    ///
    /// A theme is what your corpus is ABOUT. Until this date the only tags
    /// `projectClusters` refused were the kind type-tags (`link`, `note`, …),
    /// so every label a BRIDGE stamps on its own rows clustered as a theme —
    /// and those out-count real subjects by orders of magnitude the moment an
    /// archive lands or a few tokens are watched. The map on a real corpus
    /// read "Post 3,200 · Liked 1,800 · Watchlist 14 · Conversation 9", which
    /// is a facet inventory of the plumbing, not a reading of the subject
    /// matter, and it crowded every genuine theme out of all six cells.
    ///
    /// TWO HALVES, AND ONLY ONE OF THEM IS A LIST. The facet half is DERIVED
    /// from `Retriever.facetTags` — that vocabulary already exists, is already
    /// the app's own definition of "a half of a room rather than a subject in
    /// it", and deriving means a facet added there is excluded here the same
    /// day. The status half has no registry to read (a bridge stamps its state
    /// labels inline, and `Thing.tags` records no provenance), so it is a hand
    /// list — and therefore guarded: `scripts/theme-tags-audit.py` fails the
    /// build on any literal tag in the tree that is neither listed here nor
    /// ruled a real subject, which is the only reason a hand list is allowed
    /// to sit in this codebase at all.
    ///
    /// WHAT WAS CONSIDERED AND DECLINED: "a theme spans ≥2 sources" is a
    /// tempting derivation needing no list, and it is wrong — `Liked` is
    /// stamped by X, Instagram AND TikTok, `Watchlist` by Tokens, Stocktwits
    /// AND PostHog, so the mechanical tags are exactly the ones that span
    /// sources best. It would have re-admitted every tag this exists to keep
    /// out while excluding a real single-source subject like "Book club".
    static let mechanicalTags: Set<String> = {
        Retriever.facetTags.union([
            // Bridge state and row-type labels, by the bridge that stamps them.
            "Agent run", "Session",                       // Cursor, Claude Code
            "Annotation", "Milestone", "Silence",         // PostHog
            "Build", "Build failure", "Deploy",           // Vercel
            "Deadline", "Your turn",                      // reminders, Safe
            "Deal",                                       // Deals
            "Delivered", "Module added",                  // Safe, 7579
            "Deprecated", "Issue",
            "Regression", "Resolved",                     // GitHub, Sentry
            "Card", "Payment", "Pending", "Settled",      // Apple Wallet, cards
            "Price drop", "Price rise", "Refund",
            "Paper",                                      // Hugging Face
            // Altana (prd §402) and the chain a wallet row sits on. Both are
            // STATE by this set's own rule: a key type says what a key IS and
            // a chain name says where a row happened, and neither says what
            // anything is ABOUT. A chain in particular is the `Onchain` test
            // run backwards — that one is in KNOWN_SUBJECT because it is a
            // theme somebody keeps things about, while "BNB Smart Chain" is a
            // venue stamped on every row that touched it.
            "Root key", "Session key",                    // Altana keystore
            // vibenet (prd §468). STATE by this set's own rule: it says what a
            // key IS (EIP-8130 scope 0, unrestricted), never what anything is
            // about. Deliberately not a facet either — nobody types "admin
            // key" as a search, and its whole job is to route one row to the
            // lock screen (`NotifySweep.classify`).
            "Admin key",                                  // vibenet keystore
            "BNB Smart Chain",                            // wallet chain label
            // Radicle (prd §400). All five are STATE, not subject: they say
            // what happened to a patch or an issue, never what it is about.
            // Deliberately not facets either — `Issue` above is already
            // mechanical-only for the same reason, and "opened"/"closed"/
            // "merged"/"proposed" are among the most ordinary words in the
            // language, so promoting them would hide every link and note
            // about the subject (§397's `Account` reasoning).
            "Patch", "Proposed", "Merged", "Opened", "Closed",
            // GitHub's three notification ASKS (prd §401) — what a thread wants
            // from you, stamped as data so `GitHubRoom` never has to read it
            // back out of a clamped title. State, not subject: they say what is
            // being asked, never what it is about. Not facets, for the reason
            // "Opened"/"Closed" above are not — "review", "assigned" and
            // "mentioned" are ordinary words this corpus is full of.
            "Review", "Assigned", "Mentioned",
            // X's account record (prd §396) — the day you joined, and every
            // handle you have worn. Deliberately NOT a facet in
            // `Retriever.facetTags`: "account" is among the most ordinary
            // words in the language and this corpus is full of accounts, so
            // it would be the first genuinely misleading entry in that table.
            // Hand-listed here, which is what this half of the set is for.
            //
            // ("Photo" left this list on 2026-08-18 — it is a facet now, so
            // the derived half excludes it. §375 said in as many words that
            // the tag made "photos I posted" a filter and it had never reached
            // the vocabulary; this list's own comment recorded that gap for
            // five days.)
            "Account",
            "Runway",                                     // Stripe, Cloudflare
            "Shielded",                                   // Privacy Pools
            "Trending", "Watching", "Watchlist",          // discovery, watches
            // ENS (prd §534). What a followed name's row IS right now, never
            // what it is about — "Grace" is the window after expiry only its
            // owner can still renew, "Registered" is a watched name somebody
            // else just claimed. The name itself ("nick.eth") is still a real
            // subject and stays out of this set.
            "Grace", "Registered",
            // A watched GitHub person's pushes and releases (prd §519). STATE
            // by this set's own rule — it says what a row IS, never what it is
            // about. Deliberately NOT a §308 facet either: "activity" is among
            // the most ordinary words in the language, and gating it behind a
            // named source would still leave it filtering half the corpus's
            // vocabulary for a tag one bridge stamps.
            "Activity",                                   // GitHub, watched people
        // Walletbeat (prd §419). What a row IS, never what it is about: the kind of
        // wallet, the kind of incident, and whether it is still open. The wallet NAMES
        // this room also stamps are deliberately absent — "Rabby" really is a subject
        // somebody's corpus can be about, and the themes map is right to draw it.
        "Software", "Hardware",                       // which kind of wallet
        "Vulnerability", "Data breach", "Unresolved", // which kind of incident, and its state
        // L2BEAT (prd §428). Same principle: what a row IS, never what it is about.
        // The chain NAMES this room also stamps are deliberately absent — "Base" really
        // is a subject somebody's corpus can be about, and the themes map is right to
        // draw it. "Incident" is already above, from Walletbeat's own entry.
        "Layer 2", "Layer 3",                         // which layer a chain sits on
        "Stage 0", "Stage 1", "Stage 2",              // L2BEAT's own rung, not a subject
        "Milestone", "Stage",                         // which kind of record
        // AWS bridge — landed without a ledger entry, so no prd § to cite here.
        // "Alarm" and "Cost" are CloudWatch/Cost Explorer STATE labels stamped
        // on a row, never what it's about (the Radicle/Walletbeat rule). "Arn"
        // is NOT a `Thing.tags` value at all — this audit's STAMP regex matches
        // any `tags:` parameter, and `AWSXML.textValues(in:tags:)` happens to
        // name its own (unrelated) argument `tags` too. Ruled here rather than
        // fixing the regex, since narrowing it to `Thing(` risks missing a real
        // stamp built through a helper the same way.
        "Alarm", "Cost", "Arn",
        ])
    }()

    /// Everything `projectClusters` refuses, folded once — the kind type-tags
    /// it always refused plus the mechanical tags above. Built once rather than
    /// per call: this runs over the whole corpus, and `MCPTools` walks it too.
    private static let excludedTagKeys: Set<String> =
        Set(ThingKind.allCases.map { $0.typeTag.lowercased() })
            .union(mechanicalTags.map { $0.lowercased() })

    /// A project is a computed cluster; membership rides a tag (brief §3).
    static func projectClusters(things: [Thing]) -> [Cluster] {
        let excluded = excludedTagKeys
        // Keyed by FOLDED tag (2026-08-14): the buckets used to key on the raw
        // string while the exclusion compared lowercased, so `design` and
        // `Design` were two themes competing for cells — and being split, each
        // half could fall under the min-2 floor and the subject vanish from a
        // map that holds the things twice over. `spellings` keeps every
        // original so the cell can be LABELLED in the spelling the corpus
        // actually uses most, rather than in whichever case happened to land
        // first.
        var buckets: [String: [Thing]] = [:]
        var spellings: [String: [String: Int]] = [:]
        // `where thing.isLive` — build 177's crash site exactly: the themes
        // treemap's lede read `thing.tags` off the All room's stale snapshot.
        // `isImportReceipt` — the app's own "you imported N things" row is not
        // something the person did, so every aggregate over a room excludes it
        // (see `Corpus.isImportReceipt`); this one had been missing it, and it
        // carries the source's tags, so it padded a theme by one per import.
        for thing in things where thing.isLive && !Corpus.isImportReceipt(thing) {
            for tag in thing.tags {
                let key = tag.lowercased()
                guard !excluded.contains(key) else { continue }
                // One thing counts ONCE per folded tag. `Thing.tags.reduced()`
                // folds case at init, but plenty of bridges mutate `tags`
                // afterwards and several test membership with a CASE-SENSITIVE
                // `contains` — so a row really can end up carrying "Gone" and
                // "gone", which before folding were two clusters and after it
                // would be one thing counted twice. Identity against the
                // bucket's last entry is enough because one thing's tags are
                // walked consecutively, so a repeat is always the tail.
                if buckets[key]?.last === thing { continue }
                buckets[key, default: []].append(thing)
                spellings[key, default: [:]][tag, default: 0] += 1
            }
        }
        return buckets
            .filter { $0.value.count >= 2 }
            .map { key, things in
                // Majority spelling, ties broken alphabetically so the label
                // is stable across passes rather than dictionary-ordered.
                let name = (spellings[key] ?? [:])
                    .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                    .first?.key ?? key
                return Cluster(name: name, things: things)
            }
            .sorted {
                // Magnitude, then name — stable. (Project pins died 2026-07-07.)
                $0.things.count != $1.things.count
                    ? $0.things.count > $1.things.count
                    : $0.name < $1.name
            }
    }

    /// The Themes treemap document — the cross-source overview that moved OFF
    /// Home to the top of the "All" feed (2026-07-18, user: "should it go on
    /// all?"): a cross-source view belongs on the cross-source feed, same
    /// split that already sent the Wallet treemap to the Wallet feed. Same
    /// TagMap component/sizing the wallet treemap draws (no `genSpan` pin, so
    /// it takes the renderer's own unconstrained size — answering "is it too
    /// large / same as the wallet one?": identically sized, since it's the
    /// same component). Nil when no project has clustered yet — same standard
    /// `projectClusters` always held (min 2 things sharing a real tag).
    static func themesDocument(things: [Thing]) -> [String]? {
        themesDocument(clusters: projectClusters(things: things))
    }

    /// Same doc, from clusters already computed — for a caller (FeedScreen's
    /// `themesData` memo, 2026-07-21) that computes the cluster list once and
    /// would otherwise call `projectClusters` a second time over the same
    /// things just to get it.
    static func themesDocument(clusters: [Cluster]) -> [String]? {
        guard !clusters.isEmpty else { return nil }
        let items = clusters.prefix(cellCap).map { "\($0.name) \($0.things.count)" }
        let sub = themesSubline(clusters: clusters)
        return ["root = TagMap(\(q(String(localized: "Themes"))), \(sub.map(q) ?? "null"), [\(items.joined(separator: ", "))])"]
    }

    /// How many cells the map draws — `UnitTreemap`'s six-cell layout.
    private static let cellCap = 6

    /// The map's subline — the honesty valve the topic map's own subtitle
    /// already carries: the map draws six cells and says nothing when there
    /// are eleven themes, and a silently truncated map looks exactly like a
    /// complete one. Nil when the map is whole.
    ///
    /// The "Most new this week" freshness leader that briefly lived here is
    /// GONE, hours after it shipped (prd §385, user: "the 'most new this
    /// week...' is useless") — the day's freshness reading moved to where the
    /// day is, the All feed's Today header (`DayBrief.whisper`), and the map
    /// itself moved above the fold the same pass. What survives from that
    /// morning's reasoning: re-ranking cells by recency stays declined —
    /// magnitude-is-area is the treemap's one honest voice, and a map that
    /// reshuffles by window stops being a map of your corpus.
    static func themesSubline(clusters: [Cluster]) -> String? {
        guard clusters.count > cellCap else { return nil }
        return String(localized: "\(cellCap) of \(clusters.count) shown")
    }

    /// Quotes a string for the document; strips embedded quotes rather than
    /// escaping (the line grammar has no escape sequence).
    private static func q(_ s: String) -> String {
        // GenParser splits the whole document on "\n" per line (brief §5) —
        // a raw newline inside a value (a multi-line social post, Goal 3)
        // would fracture one doc line into several malformed ones. Collapse
        // to spaces, same "no escape sequence" treatment as embedded quotes.
        let flat = s.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(flat.replacingOccurrences(of: "\"", with: ""))\""
    }
}
