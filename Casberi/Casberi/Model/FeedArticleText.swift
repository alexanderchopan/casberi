import Foundation
import SwiftData

/// What a followed article actually SAYS (2026-08-06).
///
/// WHY THIS EXISTS. A feed hands over a headline and, usually, a short
/// abstract — `<description>` is a lede, and plenty of feeds ship one sentence
/// or a bare "Read more". `FeedParser` keeps whatever is there (`Thing.
/// summary`, 2026-07-22), which fixed the sheet reading like a bare link. It
/// did not fix RETRIEVAL: a corpus of six hundred stories whose entire
/// searchable text is a headline answers "what did I save about the pension
/// reform?" with whatever happened to put those words in a title. The article
/// itself was never read.
///
/// So this fetches the page the row already links to and keeps its readable
/// substance in `enrichedText` — retrieval-only by the 2026-07-15 ruling, so
/// nothing on any screen changes and no answer ever quotes scraped text as if
/// the publisher wrote it into the feed. It is the same `LinkTitle.
/// fetchReadable` pass a link YOU paste has had for a year; feed rows simply
/// never got it, because they arrive named and `LinkTitle.enrich` bails on
/// anything already wearing a real title.
///
/// TWO SOURCES, AND THE OTHER THREE ARE DELIBERATE ABSTENTIONS:
///   * RSS and Substack land ARTICLES — a page whose whole point is prose.
///   * YouTube's link is a watch page. Its description is already in
///     `summary`, straight from the feed; scraping the page adds player
///     chrome and recommendation titles, i.e. other people's video names
///     landing in this video's retrieval text.
///   * Reddit's link is a reddit.com permalink. The selftext is already in
///     `summary`; the page's prose is the COMMENTS, which are strangers'
///     words filed under a row that is not theirs (§83's shape).
///   * Podcasts' link is an episode page that is usually the show notes the
///     feed already handed us, and often a player with no prose at all.
///
/// BOUNDED, PACED, LEDGERED — the `InstagramCaptions` discipline, for the same
/// reason: one measured request proves nothing about six hundred. A row is
/// attempted at most `maxAttempts` times and then left alone; a paywall or a
/// dead link is not going to start working, and asking a publisher's server
/// again every ten minutes forever is rude.
///
/// RECENT ROWS ONLY. A feed's back catalogue can be thousands of stories, and
/// a thirty-day window is where searching actually happens. It also bounds the
/// total work this can ever do to roughly what arrived recently, rather than
/// to the size of the corpus.
enum FeedArticleText {

    /// The bridges whose rows link to an article. See the type doc for why the
    /// other three abstain.
    static let sources: Set<String> = ["RSS", "Substack"]

    struct Report {
        var enriched = 0
        var failed = 0
        var considered = 0
        /// Five rows failed in a row. A pass that stopped and a pass that had
        /// nothing to do both end with `enriched == 0`, and only one of them
        /// means something is wrong.
        var backedOff = false
    }

    /// Rows per foreground pass. At `pace` that is about eight seconds of
    /// background work against several different publishers (unlike
    /// `InstagramCaptions`, which walks one host).
    static let perPass = 6

    /// Between requests.
    static let pace: Duration = .milliseconds(1200)

    /// A summary this long or longer is already substance — the publisher
    /// gave us the article's opening, and a scrape would mostly repeat it.
    /// Feeds that ship `content:encoded` land well past this and are skipped
    /// entirely, which is most of the good ones.
    static let thinSummary = 400

    /// How far back a row can be and still be worth reading. See the type doc.
    static let window: TimeInterval = 30 * 86400

    private static let backOffAfter = 5
    private static let maxAttempts = 2
    private static let ledgerKey = "feed.articleText.attempts"
    private static let ledgerCap = 3000

    // MARK: - The pass

    /// Reads up to `perPass` thin rows, newest first.
    ///
    /// `trace` is the probe's window and nothing else uses it. One line PER
    /// ROW rather than a joined summary — a walk that goes wrong goes wrong at
    /// a particular row, and a single long NSLog gets truncated by the log
    /// reader (the `-todayProbe` lesson).
    @discardableResult
    @MainActor
    static func sweep(context: ModelContext, limit: Int? = nil,
                      trace: Bool = false) async -> Report {
        var report = Report()
        var attempts = (UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: Int]) ?? [:]
        let cutoff = Date.now.addingTimeInterval(-window)
        // One fetch per source rather than one over the whole recent corpus:
        // the source is a plain string column with a predicate that pushes
        // down to SQL, where `sources.contains(…)` would drag every recent
        // note, screenshot and transfer into memory to throw nearly all of
        // them away.
        var rows: [Thing] = []
        for source in sources.sorted() {
            let descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate<Thing> {
                    $0.source == source && $0.enrichedText == nil && $0.capturedAt > cutoff
                },
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            // `.live` at the boundary (CLAUDE.md corollary 4) — this array is
            // held across every await below, and a foreground heal deletes
            // under it.
            rows.append(contentsOf: ((try? context.fetch(descriptor)) ?? []).filter(\.isLive))
        }
        rows.sort { $0.capturedAt > $1.capturedAt }

        // Keyed by REF, not by row: a CloudKit merge or a re-follow can hand
        // the same article a new `Thing`, and re-fetching a publisher's page
        // for a story we already read is exactly what the ledger prevents.
        let pending = rows.compactMap { thing -> (ref: String, url: URL)? in
            guard thing.kind == .link,
                  (thing.summary?.count ?? 0) < thinSummary,
                  let ref = thing.sourceRef,
                  (attempts[ref] ?? 0) < maxAttempts,
                  let url = URL(string: thing.content.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme?.hasPrefix("http") == true
            else { return nil }
            return (ref, url)
        }
        report.considered = pending.count
        var failRun = 0

        for (ref, url) in pending.prefix(limit ?? perPass) {
            // The source the row belongs to, read BEFORE the fetch — it names
            // the service for the receipts screen, and the row can be gone by
            // the time the fetch returns.
            let service = rows.first { $0.isLive && $0.sourceRef == ref }?.source ?? "RSS"
            let body = await LinkTitle.fetchReadable(url, as: service)
            // Up to eight seconds passed. The row is re-found by ref rather
            // than held across the suspension (CLAUDE.md corollary 6).
            guard let thing = rows.first(where: { $0.isLive && $0.sourceRef == ref }) else { continue }
            guard let body, !body.isEmpty else {
                report.failed += 1
                failRun += 1
                attempts[ref] = (attempts[ref] ?? 0) + 1
                if trace { NSLog("articleText| MISS | %@ | %@", thing.source, url.absoluteString) }
                if failRun >= backOffAfter {
                    report.backedOff = true
                    break
                }
                try? await Task.sleep(for: pace)
                continue
            }
            failRun = 0
            report.enriched += 1
            // No ledger entry on success: the row's `enrichedText` is no
            // longer nil, so the fetch above can never see it again. The
            // ledger is for FAILURES only, which is what keeps it small.
            attempts.removeValue(forKey: ref)
            thing.enrichedText = body
            // The vector was built on a headline; it is stale the moment the
            // article lands behind it (the `Thing.enrichedText` contract).
            thing.embedding = nil
            if trace {
                NSLog("articleText| %d chars | %@ | %@", body.count, thing.source, thing.title)
            }
            try? await Task.sleep(for: pace)
        }

        if report.enriched > 0 {
            context.saveHonestly()
        }
        if attempts.count > ledgerCap {
            attempts = Dictionary(uniqueKeysWithValues: Array(attempts).suffix(ledgerCap))
        }
        UserDefaults.standard.set(attempts, forKey: ledgerKey)
        return report
    }
}
