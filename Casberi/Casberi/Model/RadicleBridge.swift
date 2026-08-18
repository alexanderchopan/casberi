import Foundation
import Observation
import SwiftData

/// The Radicle bridge (prd §400, 2026-08-18) — peer-to-peer Git, read off a
/// seed node's `radicle-httpd` gateway. Watch a repo by its id and what happens
/// to it lands: a patch proposed, a patch merged, an issue opened, an issue
/// closed.
///
/// **Keyless, and read-only in the strongest grade this catalog has.** Trello's
/// promise is a minted `scope=read` token, PostHog's and Stripe's are boxes
/// someone ticked, Privacy.com's and Cursor's are conduct. Radicle's is that
/// **there is no credential at all**: measured 2026-08-18, the root read's own
/// `links[]` advertises six routes and every one is a `GET`, and nothing in
/// this file sends an `Authorization` header because there is none to send.
/// Writing to Radicle needs the `rad` CLI against a local node with a signing
/// key — it is not something this API can do. So the seat sits in the keyless
/// GeckoTerminal/Farcaster tier, where a leak has nothing to spend.
///
/// **The sweep is cheap by construction.** A patch and an issue carry no
/// top-level timestamp, so there is nothing to ask "what changed since" with;
/// instead one `GET /repos/:rid` returns all six patch/issue counts, and a diff
/// against the stored snapshot decides whether to walk patches or issues at
/// all. A quiet pass is exactly one request per watched repo — the
/// `HyperliquidDeFi.sync` snapshot-diff shape.
///
/// **`activity` is deliberately not read.** §400's first draft proposed a room
/// head fed by it, on the belief that it returns the whole history. Measured
/// across six repos, its oldest entry is always ≤363 days old — `heartwood`
/// returns 860 timestamps whose oldest is 2025-08-20 for a repo years older
/// than that. Feeding a span strip from a trailing year would claim a span it
/// cannot see, which is precisely the bug §398 had just fixed for the journals.
/// The head is a later pass over the dates this bridge recovers exactly.
///
/// **The seed is the trust boundary.** Whichever seed you name sees which repos
/// you ask about, and it only serves what it happens to seed — there is no
/// global index. Both facts are in the setup copy, not a footnote.
///
/// **UNMEASURED:** nothing on this host can open a patch, merge one or close an
/// issue, so the landing paths have never run against a real change. Every read
/// returns nil on failure and every date is refused rather than guessed, so it
/// fails safe. `scripts/radicle-selftest.sh` compiles `RadicleWire` whole and
/// is the only proof these shapings are right.
@Observable
final class RadicleStore {
    static let shared = RadicleStore()

    private static let seedKey = "radicle.seed.v1"
    private static let reposKey = "radicle.repos.v1"
    private static let namesKey = "radicle.names.v1"
    private static let snapshotsKey = "radicle.snapshots.v1"
    private static let seededKey = "radicle.seeded.v1"
    private static let openKey = "radicle.open.v1"

    /// The seeds Radicle's own explorer ships as its preferred pair, both
    /// measured live 2026-08-18. The default matters: a bridge that opened on
    /// an empty host field would make the person's first act a decision they
    /// have no way to make.
    static let defaultSeeds = ["rosa.radicle.network", "iris.radicle.network"]

    var seed: String {
        didSet { UserDefaults.standard.set(seed, forKey: Self.seedKey) }
    }

    private(set) var repos: [String] {
        didSet { persist(repos, Self.reposKey) }
    }

    /// RID → the repo's own name, learned from the sweep. Kept so the watch
    /// list and every landed title can say "heartwood" instead of
    /// `rad:z3gqcJUoA1n9…`, which is not a name a person can read.
    private(set) var names: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(names) {
                UserDefaults.standard.set(data, forKey: Self.namesKey)
            }
        }
    }

    /// RID → the last counts we saw. The whole change-detection mechanism.
    private var snapshots: [String: RadicleWire.Snapshot] {
        didSet {
            if let data = try? JSONEncoder().encode(snapshots) {
                UserDefaults.standard.set(data, forKey: Self.snapshotsKey)
            }
        }
    }

    /// RID → what is still open there, written by the sweep from the page it
    /// already fetched (prd §401). The `ASCStanding` shape: bridge state, kept
    /// beside the rows rather than derived from them, because a landed row
    /// says a patch was PROPOSED and can never say it is still unresolved.
    private var openItems: [String: [RadicleWire.OpenItem]] {
        didSet {
            if let data = try? JSONEncoder().encode(openItems) {
                UserDefaults.standard.set(data, forKey: Self.openKey)
            }
        }
    }

    /// Which repos have had their first-sight pass. Distinct from "has any
    /// thing landed": a repo with no patches and no issues must still count as
    /// seeded, or every pass would re-run the backfill branch against an empty
    /// corpus. `HuggingFaceStore.seeded`'s reason, which is PostHog's before it.
    private var seeded: Set<String> {
        didSet { persist(Array(seeded), Self.seededKey) }
    }

    private init() {
        func load(_ key: String) -> [String] {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let saved = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return saved
        }
        seed = UserDefaults.standard.string(forKey: Self.seedKey) ?? Self.defaultSeeds[0]
        repos = load(Self.reposKey)
        seeded = Set(load(Self.seededKey))
        if let data = UserDefaults.standard.data(forKey: Self.namesKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            names = saved
        } else { names = [:] }
        if let data = UserDefaults.standard.data(forKey: Self.snapshotsKey),
           let saved = try? JSONDecoder().decode([String: RadicleWire.Snapshot].self,
                                                 from: data) {
            snapshots = saved
        } else { snapshots = [:] }
        if let data = UserDefaults.standard.data(forKey: Self.openKey),
           let saved = try? JSONDecoder().decode([String: [RadicleWire.OpenItem]].self,
                                                 from: data) {
            openItems = saved
        } else { openItems = [:] }
    }

    var connected: Bool { !repos.isEmpty }

    func isWatching(_ rid: String) -> Bool {
        guard let id = RadicleWire.normalizeRID(rid) else { return false }
        return repos.contains(id)
    }

    /// Adds a repo. Returns false when the id can't be read or is already
    /// watched, so the screen can say which rather than silently no-op.
    @discardableResult
    func add(_ rid: String) -> Bool {
        guard let id = RadicleWire.normalizeRID(rid), !repos.contains(id) else { return false }
        repos.append(id)
        return true
    }

    func remove(_ rid: String) {
        let id = RadicleWire.normalizeRID(rid) ?? rid
        repos.removeAll { $0 == id }
        names.removeValue(forKey: id)
        snapshots.removeValue(forKey: id)
        openItems.removeValue(forKey: id)
        seeded.remove(id)
    }

    func name(for rid: String) -> String? { names[rid] }
    func rememberName(_ name: String, for rid: String) { names[rid] = name }

    func snapshot(for rid: String) -> RadicleWire.Snapshot? { snapshots[rid] }
    func remember(_ snapshot: RadicleWire.Snapshot, for rid: String) {
        snapshots[rid] = snapshot
    }

    func open(for rid: String) -> [RadicleWire.OpenItem] { openItems[rid] ?? [] }
    func rememberOpen(_ items: [RadicleWire.OpenItem], for rid: String) {
        openItems[rid] = items
    }

    /// Every watched repo's open work, newest-repo-order irrelevant — the head
    /// ranks them itself.
    var allOpen: [(rid: String, name: String?, items: [RadicleWire.OpenItem])] {
        repos.map { (rid: $0, name: names[$0], items: openItems[$0] ?? []) }
    }

    func hasSeeded(_ rid: String) -> Bool { seeded.contains(rid) }
    func markSeeded(_ rid: String) { seeded.insert(rid) }

    func disconnect() {
        repos = []
        names = [:]
        snapshots = [:]
        openItems = [:]
        seeded = []
        seed = Self.defaultSeeds[0]
        UserDefaults.standard.removeObject(forKey: Self.openKey)
    }

    /// The demo's watched repo and its open work (prd §401).
    ///
    /// **The head reads STATE, so the demo must seed state** — seeding rows
    /// alone leaves the card correctly declining, and `verify.sh`'s room-head
    /// coverage is a HARD FAIL that would report that as a real gap (§375's X
    /// lesson). Reachable outside every `#if DEBUG` on purpose: `ChipMemory`
    /// shipped its own seed DEBUG-only once, invisible to every check here
    /// because they all compile DEBUG.
    func seedDemo(rid: String, name: String, open: [RadicleWire.OpenItem]) {
        if !repos.contains(rid) { repos.append(rid) }
        names[rid] = name
        openItems[rid] = open
        seeded.insert(rid)
    }

    /// Unwinds `seedDemo` BY NAME, never a blanket wipe — a dev install watches
    /// real repos through this same store.
    func forgetDemo(rid: String) {
        repos.removeAll { $0 == rid }
        names.removeValue(forKey: rid)
        openItems.removeValue(forKey: rid)
        snapshots.removeValue(forKey: rid)
        seeded.remove(rid)
    }

    private func persist(_ list: [String], _ key: String) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Ingest

enum RadicleIngest {

    /// The service name every request declares to `NetworkLedger`.
    ///
    /// **This is the §289 case, and the first Work seat to have it.** The seed
    /// host is TYPED BY THE PERSON, so `NetworkReach` cannot declare it — only
    /// the two defaults are listed there. Naming the service on every call is
    /// what keeps a self-chosen seed from reading as an undeclared reach on the
    /// receipts screen. Drop the `service:` argument from any request below and
    /// that screen quietly starts lying.
    static let service = "Radicle"

    @MainActor private static var running = false

    /// How many already-existing patches/issues a newly-watched repo lands.
    /// Low on purpose: it is proof the watch works, not a history import — and
    /// every one carries its REAL recovered date, so they sort back to when
    /// they happened rather than crowding today.
    private static let firstSightCap = 5
    /// The newest-N window each pass reads per repo per kind.
    private static let pageSize = 30
    /// A watch list is a handful of repos; this keeps a cold pass from firing
    /// the whole list at a single volunteer-run seed at once.
    private static let concurrency = 3

    // MARK: - Reads

    private static func base(_ seed: String) -> String { "https://\(seed)/api/v1" }

    /// One repo's counts. The cheap read every pass makes.
    private static func fetchRepo(seed: String, rid: String) async -> RadicleWire.Repo? {
        guard let escaped = rid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        guard let root = await IngestSupport.getJSON(
            "\(base(seed))/repos/\(escaped)", service: service) as? [String: Any]
        else { return nil }
        return RadicleWire.repo(root, rid: rid)
    }

    private static func fetchPatches(seed: String, rid: String) async -> [RadicleWire.Patch]? {
        guard let escaped = rid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        guard let rows = await IngestSupport.getJSON(
            "\(base(seed))/repos/\(escaped)/patches?perPage=\(pageSize)",
            service: service) as? [[String: Any]]
        else { return nil }
        return rows.compactMap(RadicleWire.patch)
    }

    private static func fetchIssues(seed: String, rid: String) async -> [RadicleWire.Issue]? {
        guard let escaped = rid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        guard let rows = await IngestSupport.getJSON(
            "\(base(seed))/repos/\(escaped)/issues?perPage=\(pageSize)",
            service: service) as? [[String: Any]]
        else { return nil }
        return rows.compactMap(RadicleWire.issue)
    }

    /// Name → repos, for the setup screen only.
    ///
    /// **MEASURED EXPENSIVE, and never called from the sweep.** `/repos/search`
    /// answers 200 in 5.3s, 5.3s and 6.5s against 0.26s for every other read on
    /// the same seed, and a first attempt at a 20s ceiling timed out outright.
    /// §400's first draft treated search as a per-seed CAPABILITY gated by an
    /// `/info` endpoint that does not exist (404, measured); it is really a
    /// pacing problem. So it sits behind an explicit tap that shows a spinner,
    /// and an id is always accepted directly.
    static func search(seed: String, query: String) async -> [RadicleWire.Repo] {
        guard let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              !escaped.isEmpty
        else { return [] }
        guard let rows = await IngestSupport.getJSON(
            "\(base(seed))/repos/search?q=\(escaped)", service: service) as? [[String: Any]]
        else { return [] }
        return rows.compactMap { RadicleWire.repo($0) }
    }

    /// Does this host actually speak `radicle-httpd`? The root read is free and
    /// is the one the setup screen validates with.
    ///
    /// It returns the API version because that is the drift signal: §400's first
    /// draft recorded the official explorer pinning `~0.18.0`, and both
    /// preferred seeds answer **6.1.0** today. Nothing here REFUSES a version —
    /// a pin written from a stale client is exactly what would have refused
    /// every working seed — it is reported so a human can see it move.
    static func probeSeed(_ seed: String) async -> (ok: Bool, apiVersion: String?) {
        guard let root = await IngestSupport.getJSON(base(seed), service: service)
                as? [String: Any]
        else { return (false, nil) }
        let isHTTPD = (root["service"] as? String)?.contains("radicle") == true
        return (isHTTPD, root["apiVersion"] as? String)
    }

    // MARK: - Land

    /// Sweeps every watched repo and lands what changed. Returns the number of
    /// new things, 0 when up to date, nil when nothing was reachable.
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = RadicleStore.shared
        guard store.connected, !running else { return running ? 0 : nil }
        running = true
        defer { running = false }

        let seed = store.seed
        let watched = store.repos
        let heads = await IngestSupport.boundedGather(watched, maxConcurrent: concurrency) {
            rid in (rid, await fetchRepo(seed: seed, rid: rid))
        }

        var existing = IngestSupport.existingSourceRefs(context, source: "Radicle")
        var added = 0
        var reachedAny = false

        for (rid, repo) in heads {
            guard let repo else { continue }
            reachedAny = true
            store.rememberName(repo.name, for: rid)

            let old = store.snapshot(for: rid)
            let firstSight = !store.hasSeeded(rid)
            // A first pass always walks; after that only a moved count spends
            // a request. `old == nil` on a repo already marked seeded means a
            // snapshot that failed to decode — walk rather than go blind.
            let walkPatches = firstSight || old.map { repo.snapshot.patchesChanged(from: $0) } ?? true
            let walkIssues = firstSight || old.map { repo.snapshot.issuesChanged(from: $0) } ?? true
            // The ONLY evidence an issue close ever leaves (see
            // `RadicleWire.Issue.closedDate`). Never true on first sight, so a
            // close that happened before you started watching is not invented.
            let sawClose = !firstSight && (old.map { repo.snapshot.sawIssueClose(from: $0) } ?? false)

            var walkedPatches: [RadicleWire.Patch]?
            var walkedIssues: [RadicleWire.Issue]?
            if walkPatches, let patches = await fetchPatches(seed: seed, rid: rid) {
                walkedPatches = patches
                added += landPatches(patches, repo: repo, rid: rid, seed: seed,
                                     firstSight: firstSight,
                                     existing: &existing, context: context)
            }
            if walkIssues, let issues = await fetchIssues(seed: seed, rid: rid) {
                walkedIssues = issues
                added += landIssues(issues, repo: repo, rid: rid, seed: seed,
                                    firstSight: firstSight, sawClose: sawClose,
                                    existing: &existing, context: context)
            }
            // What is still unresolved, kept for the room head (prd §401).
            // FREE: these are the pages just fetched, which until now were read
            // for what to land and then discarded.
            //
            // Merged PER KIND, not written wholesale. A repo whose patch
            // counts moved re-fetches patches ALONE, so writing the combined
            // result of that pass would blank the issues and the head would
            // read it as "every issue closed". Each half is replaced only when
            // that half was actually walked; the quiet one keeps its previous
            // answer, which is still true precisely because nothing moved.
            if walkedPatches != nil || walkedIssues != nil {
                let fresh = RadicleWire.openItems(patches: walkedPatches ?? [],
                                                  issues: walkedIssues ?? [])
                // Keep exactly the halves this pass did NOT walk. Spelled as
                // the direct statement of that, because the ternary form of it
                // silently keeps stale issues alongside fresh ones whenever
                // both sides walk — which is every first sight.
                let kept = store.open(for: rid).filter { item in
                    switch item.kind {
                    case .patch: return walkedPatches == nil
                    case .issue: return walkedIssues == nil
                    }
                }
                store.rememberOpen(fresh + kept, for: rid)
            }

            // The snapshot advances only AFTER the rows are in the context —
            // moving it first would skip a window forever on a crash, which is
            // `StripeBridge`'s cursor rule.
            store.remember(repo.snapshot, for: rid)
            store.markSeeded(rid)
        }

        if added > 0 { context.saveHonestly() }
        return reachedAny ? added : nil
    }

    /// `refresh`, except a caller that finds a pass already in flight WAITS
    /// rather than taking the guard's 0 — for the probe only, so `-radicleWatch`
    /// and `-radicleProbe` can share one launch. Production callers keep the
    /// plain guard, which is right for them: the foreground sweep genuinely
    /// wants "someone else has this, skip" (`HuggingFaceIngest`'s reason).
    @MainActor
    static func refreshWaiting(context: ModelContext) async -> Int? {
        // Bounded: a wait that can't end would hang the probe with no output
        // at all, which is a worse failure than the one it fixes.
        var ticks = 0
        while running, ticks < 300 {
            try? await Task.sleep(for: .milliseconds(100))
            ticks += 1
        }
        return await refresh(context: context)
    }

    @MainActor
    private static func landPatches(_ patches: [RadicleWire.Patch],
                                    repo: RadicleWire.Repo, rid: String, seed: String,
                                    firstSight: Bool,
                                    existing: inout Set<String>,
                                    context: ModelContext) -> Int {
        var added = 0
        // On first sight the newest few, so the watch proves itself; after
        // that the whole page window, bounded by `pageSize`.
        let considered = firstSight ? Array(patches.prefix(firstSightCap)) : patches
        for patch in considered {
            let link = RadicleWire.permalink(seed: seed, rid: rid, path: "patches/\(patch.id)")
            // OPENED — dated from `revisions[0].timestamp`, which is exact, so
            // it backfills honestly and sorts back to when it happened.
            if let opened = patch.opened {
                let ref = "radicle:patch:\(rid):\(patch.id):opened"
                if !existing.contains(ref) {
                    land(ref: ref, existing: &existing, context: context,
                         title: RadicleWire.title(repo: repo.name, verb: "patch",
                                                  subject: patch.title),
                         link: link, when: opened, who: patch.author,
                         tags: ["Patch", "Proposed"])
                    added += 1
                }
            }
            // MERGED — its own row and its own moment, from
            // `merges[0].timestamp`. A separate ref from the open, because the
            // two are different events with different dates and different
            // people; collapsing them would lose whichever came second.
            if patch.isMerged, let merged = patch.merged {
                let ref = "radicle:patch:\(rid):\(patch.id):merged"
                if !existing.contains(ref) {
                    land(ref: ref, existing: &existing, context: context,
                         title: RadicleWire.title(repo: repo.name, verb: "merged",
                                                  subject: patch.title),
                         link: link, when: merged,
                         who: patch.mergedBy ?? patch.author,
                         tags: ["Patch", "Merged"])
                    added += 1
                }
            }
        }
        return added
    }

    @MainActor
    private static func landIssues(_ issues: [RadicleWire.Issue],
                                   repo: RadicleWire.Repo, rid: String, seed: String,
                                   firstSight: Bool, sawClose: Bool,
                                   existing: inout Set<String>,
                                   context: ModelContext) -> Int {
        var added = 0
        let considered = firstSight ? Array(issues.prefix(firstSightCap)) : issues
        for issue in considered {
            let link = RadicleWire.permalink(seed: seed, rid: rid, path: "issues/\(issue.id)")
            if let opened = issue.opened {
                let ref = "radicle:issue:\(rid):\(issue.id):opened"
                if !existing.contains(ref) {
                    land(ref: ref, existing: &existing, context: context,
                         title: RadicleWire.title(repo: repo.name, verb: "issue",
                                                  subject: issue.title),
                         link: link, when: opened, who: issue.author,
                         tags: ["Issue", "Opened"])
                    added += 1
                }
            }
            // A CLOSE has no date on the wire at all (measured — see
            // `Issue.closedDate`). It lands only when THIS DEVICE watched the
            // closed count rise, stamped with now, which is true to within one
            // refresh. Never on first sight: an issue already closed when you
            // started watching closed on a day nobody can recover, and `.now`
            // there would drop years-old work into today's feed.
            if issue.isClosed, sawClose {
                let ref = "radicle:issue:\(rid):\(issue.id):closed"
                if !existing.contains(ref) {
                    land(ref: ref, existing: &existing, context: context,
                         title: RadicleWire.title(repo: repo.name, verb: "closed",
                                                  subject: issue.title),
                         link: link, when: Date(), who: issue.author,
                         tags: ["Issue", "Closed"])
                    added += 1
                }
            }
        }
        return added
    }

    /// One row. Existing `Thing` fields only — no new property, so **no
    /// CloudKit Production deploy** (see CLAUDE.md's schema rule).
    @MainActor
    private static func land(ref: String, existing: inout Set<String>,
                             context: ModelContext,
                             title: String, link: String, when: Date,
                             who: RadicleWire.Party, tags: [String]) {
        let thing = Thing(
            kind: .link,
            // Patch and issue titles are author-controlled free text; the
            // one-line-title invariant is enforced at the door, same as every
            // other bridge here.
            title: IngestSupport.titleLine(title),
            content: link,
            source: "Radicle",
            capturedAt: when,
            tags: tags,
            sourceRef: ref
        )
        // The alias when Radicle published one, else the DID's tail — never an
        // invented handle (`RadicleWire.Party.display`).
        thing.authorHandle = who.display
        context.insert(thing)
        existing.insert(ref)
        SpotlightIndex.index([thing])
    }
}
