import Foundation
import Observation
import SwiftData

/// The Hugging Face bridge (2026-08-03) — what the AI world actually shipped
/// today, from the place it ships. Two reads, both keyless:
///
///   • **Watched authors** — name an org or a person (`meta-llama`, `google`,
///     `karpathy`) and their NEW models, datasets and Spaces land as links.
///     This is the GitHub-releases shape pointed at the hub AI publishes to.
///   • **Daily Papers** — Hugging Face's own curated daily list, which lands
///     with a real title, the full abstract, a thumbnail and its first
///     author, so a paper row wears a face instead of a naked arXiv URL.
///
/// No account, no key, nothing to mint: every endpoint below answers
/// anonymously (MEASURED 2026-08-03, see each `fetch`). That puts it in the
/// GeckoTerminal/Farcaster tier rather than the PostHog/Stripe one — there is
/// no token to store, so there is nothing here a leak could spend.
///
/// **The module doctrine is the whole design constraint.** Hugging Face is a
/// firehose of COUNTS — downloads, likes, trending scores — and a count is
/// never a thing here (the PostHog lesson). So none of them land: a repo's
/// download total is not news, and a repo being UPDATED is not news either
/// (weights get touched constantly, and `lastModified` moves for a README
/// typo). Exactly one repo shape is an event: it did not exist, and now it
/// does. Hence `createdAt`, never `lastModified`.
///
/// **First sight BACKFILLS a small page rather than seeding silently**, which
/// diverges from the Peer/Morpho/Hyperliquid cursor rule on purpose. Those
/// seed silently because their first read is a STATE that would otherwise
/// land as fake news ("22 positions opened!"). Here the person has just typed
/// an author's name and is owed proof the watch works, so the newest few land
/// immediately — stamped with their REAL `createdAt`, so they sort back to
/// where they happened and a three-year-old model can never read as today.
/// That is the same split `PrivacyPoolsBridge` makes, for the same reason.
///
/// Deliberately NOT built, so the next person doesn't think it was forgotten:
///   • **Your own likes.** `api/users/<name>/likes` is public and answers 200
///     (measured), and a like IS a save — the shape this app is built on. It
///     needs the person's own HF handle, which most people who'd use Casberi
///     don't have, so it would be a field that reads as required and is blank
///     forever. Worth adding the day the seat has users who'd fill it.
///   • **Following-graph import.** Same objection plus the Farcaster lesson:
///     a follow graph is a picker, not a mirror, and that's a screen of its
///     own (prd §87).
enum HuggingFaceRepo: String, CaseIterable, Identifiable {
    case model, dataset, space

    var id: String { rawValue }

    /// The API path piece — every hub route is the plural.
    var path: String { rawValue + "s" }

    /// What the row's trailing clause says happened. "Space" is capitalised
    /// because Hugging Face capitalises it — it's a product name there, not a
    /// common noun.
    var noun: String {
        switch self {
        case .model:   String(localized: "new model")
        case .dataset: String(localized: "new dataset")
        case .space:   String(localized: "new Space")
        }
    }
}

// MARK: - Store (just the watched authors and one toggle — no key to mint)

@Observable
final class HuggingFaceStore {
    static let shared = HuggingFaceStore()
    private static let authorsKey = "hf.authors.v1"
    private static let papersKey = "hf.dailyPapers.v1"
    /// Which authors have had their first-sight backfill. Distinct from
    /// "has any thing landed": an author who has published nothing yet must
    /// still count as seeded, or every pass would re-run the backfill branch
    /// and re-decide the cap against an empty corpus. `Metric.seeded`'s
    /// lesson from PostHog, in a second bridge.
    private static let seededKey = "hf.seeded.v1"

    private(set) var authors: [String] { didSet { persist(authors, Self.authorsKey) } }
    private var seeded: Set<String> { didSet { persist(Array(seeded), Self.seededKey) } }

    /// Hugging Face's own curated daily paper list. Off until asked for — it
    /// lands ~10 rows a day, which is a real amount of feed for someone who
    /// only wanted to watch one org.
    var dailyPapers: Bool {
        didSet { UserDefaults.standard.set(dailyPapers, forKey: Self.papersKey) }
    }

    private init() {
        func load(_ key: String) -> [String] {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let saved = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return saved
        }
        authors = load(Self.authorsKey)
        seeded = Set(load(Self.seededKey))
        dailyPapers = UserDefaults.standard.bool(forKey: Self.papersKey)
    }

    var connected: Bool { !authors.isEmpty || dailyPapers }

    func isWatching(_ author: String) -> Bool {
        authors.contains { $0.caseInsensitiveCompare(author) == .orderedSame }
    }

    /// Adds an author, normalised the way the hub writes it. Returns false
    /// when it was already watched, so the screen can say so rather than
    /// silently no-op.
    @discardableResult
    func add(_ author: String) -> Bool {
        let name = Self.normalize(author)
        guard !name.isEmpty, !isWatching(name) else { return false }
        authors.append(name)
        return true
    }

    func remove(_ author: String) {
        authors.removeAll { $0.caseInsensitiveCompare(author) == .orderedSame }
        seeded.remove(author.lowercased())
    }

    func hasSeeded(_ author: String) -> Bool { seeded.contains(author.lowercased()) }
    func markSeeded(_ author: String) { seeded.insert(author.lowercased()) }

    func disconnect() {
        authors = []
        seeded = []
        dailyPapers = false
    }

    private func persist(_ list: [String], _ key: String) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Accepts what a person actually pastes: a bare name, a profile URL, or
    /// a full repo id. `huggingface.co/meta-llama/Llama-4` and
    /// `meta-llama/Llama-4` both mean the org `meta-llama` — taking the first
    /// path component is what makes pasting a model page work, which is how
    /// most people will arrive here.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        for host in ["huggingface.co/", "hf.co/"] where s.lowercased().hasPrefix(host) {
            s = String(s.dropFirst(host.count))
        }
        // The hub routes repo pages under a kind segment; an org page isn't
        // prefixed at all. Drop the segment so a pasted dataset URL resolves
        // to its owner rather than the literal word "datasets".
        for segment in ["models/", "datasets/", "spaces/"] where s.lowercased().hasPrefix(segment) {
            s = String(s.dropFirst(segment.count))
        }
        s = s.split(separator: "/").first.map(String.init) ?? s
        return s.split(separator: "?").first.map(String.init) ?? s
    }
}

// MARK: - Ingest

enum HuggingFaceIngest {

    /// Serializes refreshes — the launch hook races the foreground sweep, and
    /// both would read `existing` before either saved (the RSS lesson).
    @MainActor private static var running = false

    /// How many rows a newly-watched author lands immediately, per repo kind.
    /// Low on purpose: it's proof the watch works, not a history import.
    private static let firstSightCap = 3
    /// The newest-N window each pass reads per author per kind. An author who
    /// publishes more than this between two opens loses the tail — accepted,
    /// the same bound OpenSea and GeckoTerminal take ("the corpus doesn't need
    /// the tail"), and the alternative is paging a firehose forever.
    private static let pageSize = 10
    /// Daily Papers lands about ten a day; twenty covers a weekend away.
    private static let paperPage = 20

    private struct Release {
        let id: String            // "google/gemma-3-27b" — owner included
        let repo: HuggingFaceRepo
        let createdAt: Date
        /// What the repo DOES — `text-generation`, `image-to-text`. The hub's
        /// own single most useful field about a model and the closest thing it
        /// publishes to a subject.
        let pipeline: String?
        /// What it loads with — `transformers`, `diffusers`, `gguf`.
        let library: String?
        /// A few of the repo's own free-form tags, already filtered (see
        /// `hubTags(_:)`).
        let hubTags: [String]
        /// Behind an access request. NOT a reason to drop the row — see
        /// `isGated(_:)` and the landing below.
        let gated: Bool

        /// The row's tags. "Release" always, then what the hub says this repo
        /// IS. None of these is a COUNT, so the doctrine in this file's header
        /// is untouched: downloads, likes and trending scores stay out, and
        /// `lastModified` still isn't read anywhere.
        var tags: [String] {
            var out = ["Release"]
            if gated { out.append("Gated") }
            if let pipeline = pipeline { out.append(pipeline) }
            if let library = library { out.append(library) }
            return (out + hubTags).reduced()
        }
    }

    private struct Paper {
        let arxivID: String
        let title: String
        let abstract: String
        let thumbnail: String?
        let publishedAt: Date
        /// The first author's name, the way a paper is cited. Nil when the
        /// payload names nobody — never a stand-in.
        let leadAuthor: String?
    }

    // MARK: - Reads

    /// One author's newest repos of one kind, or nil when the fetch failed.
    /// Empty is a real answer: this org has never published a Space.
    ///
    /// MEASURED 2026-08-03 (curl, no key, no headers): `models`, `datasets`
    /// and `spaces` all answer 200 anonymously and all three honour
    /// `sort=createdAt&direction=-1` (verified newest-first against
    /// `meta-llama` and `openai`). `spaces` is the one that carries no
    /// `author` field of its own — hence the owner is read off `id`'s prefix
    /// below for every kind, rather than trusting a field two of three have.
    private static func fetch(author: String, repo: HuggingFaceRepo) async -> [Release]? {
        guard let escaped = author.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        let url = "https://huggingface.co/api/\(repo.path)?author=\(escaped)"
            + "&sort=createdAt&direction=-1&limit=\(pageSize)"
        guard let rows = await IngestSupport.getJSON(url) as? [[String: Any]] else { return nil }
        return rows.compactMap { row -> Release? in
            guard let id = (row["id"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
                  let created = IngestSupport.isoDate(row["createdAt"])
            else { return nil }
            // A private repo can't be opened by the person reading the feed,
            // and a disabled one 404s — neither is worth a row.
            if (row["private"] as? Bool) == true { return nil }
            if (row["disabled"] as? Bool) == true { return nil }
            // A GATED repo is NOT dropped, and the difference from those two
            // is what the tap finds: a private or disabled page 404s, while a
            // gated page opens perfectly and shows an access-request form. It
            // being published IS the news, so it lands wearing the word rather
            // than being silently withheld — and before 2026-08-06 it landed
            // wearing nothing at all, as an ordinary link that turned out not
            // to be openable.
            return Release(id: id, repo: repo, createdAt: created,
                           pipeline: Self.term(row["pipeline_tag"]),
                           library: Self.term(row["library_name"]),
                           hubTags: Self.hubTags(row["tags"]),
                           gated: Self.isGated(row["gated"]))
        }
    }

    /// A single hub field as a tag — trimmed, and nil when it's empty or
    /// carries anything but a plain identifier. The hub's own spellings are
    /// kept (`text-generation`, not "Text generation"): they're the words
    /// people search the hub with, and re-casing them would make a tag that
    /// matches nothing anyone would type.
    private static func term(_ raw: Any?) -> String? {
        guard let s = (raw as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty, s.count <= 40, !s.contains(":") else { return nil }
        return s
    }

    /// A few of a repo's own free-form tags. FILTERED and CAPPED, and both
    /// halves are load-bearing.
    ///
    /// A model's `tags` array runs to thirty entries and is mostly machinery —
    /// `license:apache-2.0`, `arxiv:2307.09288`, `base_model:meta-llama/…`,
    /// `region:us`, `endpoints_compatible`. Landing it whole would put a dozen
    /// tags on every row, and tag overlap is exactly what the thing sheet's
    /// Related shelf and the Themes treemap read — so every Hugging Face row
    /// would become "related" to every other, which is the failure the
    /// Watchlist tag already taught this app (`ThingSheetView.streamRelated`
    /// carries a token exception for precisely that reason).
    ///
    /// Three rules, each one an explainable "this names no subject": a
    /// namespaced entry (anything with a colon) is hub metadata; anything
    /// under three characters is a language code (`en`, `fr`) — the same bar
    /// `VisualCorpusMatch` sets on its labels; and the handful of compatibility
    /// flags below describe the hub's own plumbing. A DENYLIST, not an
    /// allowlist: an allowlist would silently hide whatever the hub starts
    /// publishing next, which is the failure `AgentModels` was built to end.
    private static func hubTags(_ raw: Any?) -> [String] {
        let stoplist: Set<String> = [
            "endpoints_compatible", "autotrain_compatible", "compatible",
            "text-generation-inference", "custom_code", "has_space", "region",
        ]
        return ((raw as? [String]) ?? [])
            .compactMap { term($0) }
            .filter { $0.count > 2 && !stoplist.contains($0.lowercased()) }
            .reduced()
            .prefix(3)
            .map { $0 }
    }

    /// `gated` is NOT a Bool on the wire: the hub sends `false` for an open
    /// repo and the STRINGS `"auto"` or `"manual"` for a gated one. The
    /// `as? Bool == true` test the `private`/`disabled` fields above use would
    /// therefore read every gated repo as open — so anything that isn't a
    /// literal `false` is gated.
    private static func isGated(_ raw: Any?) -> Bool {
        if let flag = raw as? Bool { return flag }
        if let word = raw as? String {
            return !word.isEmpty && word.lowercased() != "false"
        }
        return false
    }

    /// Today's curated papers, or nil when the fetch failed. MEASURED
    /// 2026-08-03: `api/daily_papers` answers 200 anonymously with `title`,
    /// `summary` (the FULL abstract, not a clipping), `thumbnail` (a real CDN
    /// image), `publishedAt`, and a nested `paper.id` that is the arXiv id.
    private static func fetchPapers() async -> [Paper]? {
        let url = "https://huggingface.co/api/daily_papers?limit=\(paperPage)"
        guard let rows = await IngestSupport.getJSON(url) as? [[String: Any]] else { return nil }
        return rows.compactMap { row -> Paper? in
            let paper = row["paper"] as? [String: Any] ?? [:]
            // The arXiv id is the join key AND the permalink's last component
            // (`huggingface.co/papers/<id>` — measured 200). Without it there
            // is nothing stable to dedupe on, so the row is dropped rather
            // than keyed on a title that could be edited.
            guard let arxiv = (paper["id"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !arxiv.isEmpty,
                  let title = (row["title"] as? String ?? paper["title"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
            else { return nil }
            let abstract = (row["summary"] as? String ?? paper["summary"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let published = IngestSupport.isoDate(row["publishedAt"])
                ?? IngestSupport.isoDate(paper["publishedAt"]) ?? Date()
            let thumb = (row["thumbnail"] as? String)?.trimmingCharacters(in: .whitespaces)
            return Paper(arxivID: arxiv, title: title, abstract: abstract,
                         thumbnail: (thumb?.isEmpty == false) ? thumb : nil,
                         publishedAt: published,
                         leadAuthor: Self.leadAuthor(paper["authors"]))
        }
    }

    /// The FIRST author of a paper, which is how a paper is cited and the only
    /// one of a twenty-name list a single field can honestly hold. Reads
    /// `paper.authors`, whose entries the hub serves as objects (`name`,
    /// `user`, `hidden`) — a plain string list is accepted too, since one
    /// field shape is a thin thing to bet a whole read on. Nil when the list
    /// is absent or names nobody: a paper with no credited author is better
    /// than a paper credited to a guess.
    private static func leadAuthor(_ raw: Any?) -> String? {
        func clean(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty, s.count <= 80 else { return nil }
            return s
        }
        if let rows = raw as? [[String: Any]] {
            return rows.compactMap { clean($0["name"] as? String) }.first
        }
        if let names = raw as? [String] {
            return names.compactMap { clean($0) }.first
        }
        return nil
    }

    // MARK: - Land

    /// Fetches every watched author (and the daily papers, when on) and lands
    /// what's new. Returns the number of NEW things, 0 when up to date, nil
    /// when nothing was reachable (offline).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = HuggingFaceStore.shared
        let authors = store.authors
        guard store.connected, !running else { return running ? 0 : nil }
        running = true
        defer { running = false }

        // One job per author/kind pair. The hub publishes no documented
        // anonymous rate limit, so this stays modestly bounded rather than
        // firing 3× the watch list at once.
        let jobs = authors.flatMap { author in
            HuggingFaceRepo.allCases.map { (author, $0) }
        }
        let results = await IngestSupport.boundedGather(jobs, maxConcurrent: 4) { job in
            (job.0, job.1, await fetch(author: job.0, repo: job.1))
        }
        let papers = store.dailyPapers ? await fetchPapers() : nil

        var existing = IngestSupport.existingSourceRefs(context, source: "Hugging Face")
        var added = 0
        var reachedAny = false

        // Which authors this pass actually reached, so they can be marked
        // seeded AFTER every kind is done. Marking inside the loop below
        // marked the author on their FIRST kind, so kinds two and three read
        // as already-seeded and landed a full page each — first sight was
        // 3 models + 10 datasets + 10 Spaces, not the 3-per-kind this
        // documents (caught by `-hfProbe` on the first real run, 2026-08-03:
        // a second pass moments later reported exactly 7 more per author,
        // which is the models the cap had held back).
        var reachedAuthors: Set<String> = []

        for (author, repo, releases) in results {
            guard let releases else { continue }
            reachedAny = true
            reachedAuthors.insert(author)
            // The backfill cap applies per kind on the author's FIRST pass
            // only; after that the page window is the only bound.
            let fresh = store.hasSeeded(author) ? Array(releases)
                                                : Array(releases.prefix(firstSightCap))
            for release in fresh {
                let ref = "hf:\(repo.rawValue):\(release.id.lowercased())"
                guard !existing.contains(ref) else { continue }
                let thing = Thing(
                    kind: .link,
                    // Repo ids are author-controlled and can carry anything;
                    // the one-line-title invariant is enforced at the door,
                    // same as OpenSea and GeckoTerminal.
                    title: IngestSupport.titleLine("\(release.id) · \(repo.noun)"),
                    content: "https://huggingface.co/\(pathPrefix(repo))\(release.id)",
                    source: "Hugging Face",
                    // The REAL publish time, not `.now` — a backfilled release
                    // from 2024 sorts back to 2024 and can't fake urgency.
                    capturedAt: release.createdAt,
                    // "Release", then what the hub says this repo is — see
                    // `Release.tags`. Still no counts anywhere.
                    tags: release.tags,
                    sourceRef: ref
                )
                thing.authorHandle = owner(of: release.id)
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
            }
        }
        for author in reachedAuthors { store.markSeeded(author) }

        if let papers {
            reachedAny = true
            for paper in papers {
                let ref = "hf:paper:\(paper.arxivID)"
                guard !existing.contains(ref) else { continue }
                let thing = Thing(
                    kind: .link,
                    title: IngestSupport.titleLine(paper.title),
                    content: "https://huggingface.co/papers/\(paper.arxivID)",
                    source: "Hugging Face",
                    capturedAt: paper.publishedAt,
                    tags: ["Paper"],
                    sourceRef: ref
                )
                // The abstract rides `enrichedText`, which is retrieval-only
                // by the 2026-07-15 ruling — so a paper is findable by what
                // it's ABOUT while the row still reads as a title and a
                // picture rather than a wall of prose. No source-gated
                // display exception here: unlike Privacy Pools' one-line
                // anonymity cover, an abstract is a paragraph.
                if !paper.abstract.isEmpty { thing.enrichedText = paper.abstract }
                thing.previewImageURL = paper.thumbnail
                // Who wrote it — the same backend slot a release stamps its
                // OWNER into, so "that paper by Karpathy" has something to
                // match. No screen reads it for this source (ShapedRows'
                // trailing slot has no "Hugging Face" case) and no leaderboard
                // ranks on it (`FeedInsight.leaderboard` has no case either),
                // so it can't quietly become a claim that this one person
                // wrote a twenty-author paper.
                thing.authorHandle = paper.leadAuthor
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
            }
        }

        if added > 0 { context.saveHonestly() }
        return reachedAny ? added : nil
    }

    /// `refresh`, except a caller that finds a pass already in flight WAITS
    /// for it rather than taking the guard's 0 (2026-08-03). For the probe
    /// only — production callers keep the plain guard, which is correct for
    /// them: the foreground sweep genuinely wants "someone else has this,
    /// skip", not a queue.
    ///
    /// It exists because `-hfWatch` and `-hfProbe` in ONE launch both call
    /// `refresh`, so the probe took the 0 and dumped the corpus BEFORE the
    /// landing it was meant to observe had inserted anything — on a fresh
    /// install that prints `0 new` and zero rows, which reads exactly like a
    /// broken bridge. That trap is documented for Farcaster ("fire probes ONE
    /// per launch"); documenting it again is how it gets re-hit, so this
    /// removes it instead.
    @MainActor
    static func refreshWaiting(context: ModelContext) async -> Int? {
        // Bounded: a wait that can't end would hang the probe with no output
        // at all, which is a worse failure than the one it's fixing.
        var ticks = 0
        while running, ticks < 300 {
            try? await Task.sleep(for: .milliseconds(100))
            ticks += 1
        }
        return await refresh(context: context)
    }

    // MARK: - Helpers

    /// A model page sits at the bare id; datasets and Spaces are namespaced.
    private static func pathPrefix(_ repo: HuggingFaceRepo) -> String {
        switch repo {
        case .model:   ""
        case .dataset: "datasets/"
        case .space:   "spaces/"
        }
    }

    /// The owner half of `owner/name`. Nil for the handful of legacy models
    /// published at the root with no owner at all (`gpt2`, `bert-base-uncased`)
    /// — an invented handle there would be worse than none.
    private static func owner(of id: String) -> String? {
        let parts = id.split(separator: "/")
        return parts.count >= 2 ? String(parts[0]) : nil
    }
}
