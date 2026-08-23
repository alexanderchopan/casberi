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
///   * YouTube's link is a watch page. Its description is in `summary`,
///     straight from the feed; scraping the page adds player chrome and
///     recommendation titles, i.e. other people's video names landing in this
///     video's retrieval text. That reason was written before it was TRUE:
///     a YouTube description rides `<media:description>`, which `FeedParser`
///     did not match until 2026-08-06, so every video really did land with an
///     empty `summary` and nothing else to search. The abstention was right
///     for the wrong reason and is now right for the stated one.
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

    // MARK: - Eligibility

    /// Whether this row is an article we could read, and the address to read
    /// it at — the ONE rule, shared by the background sweep and the tap
    /// (2026-08-23).
    ///
    /// Extracted rather than written twice on purpose. The sweep and
    /// `fetchOnOpen` disagree about WHEN to read (see that function) and must
    /// not disagree about WHAT is readable: a tap that fetched a row the sweep
    /// considers ineligible would download a podcast's audio file to take its
    /// first 512KB as text, and a tap that refused one the sweep accepts would
    /// leave the reader looking at a preview card for an article the app is
    /// perfectly willing to read on its own schedule.
    ///
    /// `sources` is checked here and is redundant for the sweep, whose fetch
    /// is already scoped per source — kept because the tap has no such loop
    /// and a shared rule that relies on its caller's scoping is not shared.
    static func readableURL(for thing: Thing) -> URL? {
        guard sources.contains(thing.source),
              thing.kind == .link,
              // The publisher already gave us the article's opening — see
              // `thinSummary`. Applies to the tap too: a `content:encoded`
              // feed ships the whole piece here, and `summaryBlock` draws it.
              (thing.summary?.count ?? 0) < thinSummary,
              // A podcast episode with no `<link>` of its own carries its
              // AUDIO as `content` (2026-08-06, `RSSIngest`) — the same URL
              // it files on `externalLink`, which is what identifies one
              // here. `fetchReadable` would download the whole file before
              // taking its first 512KB as text, and a podcast followed
              // through the RSS bridge is an ordinary RSS row otherwise.
              thing.externalLink != thing.content,
              let url = URL(string: thing.content.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.hasPrefix("http") == true
        else { return nil }
        return url
    }

    /// Does this row already hold a body worth drawing?
    static func hasBody(_ thing: Thing) -> Bool {
        !((thing.enrichedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - The ledger

    private static func ledger() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: Int]) ?? [:]
    }

    private static func writeLedger(_ attempts: [String: Int]) {
        var attempts = attempts
        if attempts.count > ledgerCap {
            attempts = Dictionary(uniqueKeysWithValues: Array(attempts).suffix(ledgerCap))
        }
        UserDefaults.standard.set(attempts, forKey: ledgerKey)
    }

    // MARK: - The tap

    /// Refs being fetched right now, so a sheet that re-renders mid-fetch —
    /// or a second window showing the same story — cannot start a second
    /// request for one article. Main-actor state guarded by this function's
    /// own isolation; there is no background caller.
    @MainActor private static var inFlight: Set<String> = []

    /// Is this row's article being read right now? The view's spinner reads
    /// this so a re-render mid-fetch keeps showing the placeholder rather
    /// than blinking back to nothing.
    @MainActor static func isFetching(_ thing: Thing) -> Bool {
        guard let ref = thing.sourceRef else { return false }
        return inFlight.contains(ref)
    }

    /// THE ARTICLE, BECAUSE SOMEBODY OPENED IT (2026-08-23, prd §455).
    ///
    /// WHY THIS EXISTS. `sweep` is a background pass and is bounded like one:
    /// `perPass` (6) rows per foreground, inside a thirty-day `window`,
    /// abandoned after `maxAttempts`. Those bounds are right for work the app
    /// does on its own schedule and they mean that on any real multi-feed
    /// corpus most stories still have no body when you open them — so the
    /// sheet fell back to a link preview card and the only way to read the
    /// piece was to leave for the browser. The reader had paid for the fetch
    /// on six rows and got it on whichever six the sweep happened to reach.
    ///
    /// A tap is the one moment the body is CERTAINLY wanted, and it is the
    /// cheapest possible signal to act on: one request, made because a person
    /// asked, against a page they are already looking at the headline of.
    ///
    /// THREE OF THE SWEEP'S BOUNDS ARE DELIBERATELY NOT APPLIED, and each
    /// omission is the point rather than an oversight:
    ///
    ///   * **The window.** You opened it; its age is not our business. The
    ///     thirty days bound how much work the app may do unasked, and this is
    ///     asked.
    ///   * **`maxAttempts`.** The ledger exists to stop a robot asking a
    ///     publisher's server the same dead question forever. A person
    ///     re-opening a story is not that, and refusing them on the strength
    ///     of two failures the app made last week is a control that does
    ///     nothing for a reason nobody can see (§83).
    ///   * **`perPass` and `pace`.** There is nothing to pace: one open is one
    ///     request, and the bound on how many is how many stories somebody
    ///     opens.
    ///
    /// **Failures still COUNT into the ledger**, which is the asymmetry worth
    /// stating: the tap does not READ the ledger and does WRITE it, so a
    /// paywalled article somebody opens twice teaches the background sweep to
    /// leave it alone without the person ever being told no. A success clears
    /// the entry, exactly as the sweep's does.
    ///
    /// Returns whether a body landed, for the caller's own state.
    @MainActor
    @discardableResult
    static func fetchOnOpen(_ thing: Thing, context: ModelContext) async -> Bool {
        // Held-reference guard (CLAUDE.md corollary 5's neighbour): this is a
        // `Thing` handed in from a view and a heal pass can tombstone it
        // between the sheet mounting and this running.
        guard thing.isLive, !hasBody(thing) else { return false }
        guard let ref = thing.sourceRef, let url = readableURL(for: thing) else { return false }
        guard !inFlight.contains(ref) else { return false }
        inFlight.insert(ref)
        defer { inFlight.remove(ref) }

        // Read BEFORE the fetch — it names the service for the receipts screen
        // (prd §289: this host is the person's own publisher, so the reach
        // registry structurally cannot name it and the call site must), and
        // the row can be gone by the time the fetch returns.
        let service = thing.source
        let body = await LinkTitle.fetchReadable(url, as: service)

        // Up to eight seconds passed (CLAUDE.md corollary 6). The reference is
        // re-checked rather than trusted.
        guard thing.isLive else { return false }
        var attempts = ledger()
        guard let body, !body.isEmpty else {
            attempts[ref] = (attempts[ref] ?? 0) + 1
            writeLedger(attempts)
            return false
        }
        attempts.removeValue(forKey: ref)
        writeLedger(attempts)
        thing.enrichedText = body
        // The vector was built on a headline; it is stale the moment the
        // article lands behind it (the `Thing.enrichedText` contract).
        thing.embedding = nil
        context.saveHonestly()
        return true
    }

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
        // Held across this pass's awaits, so a `fetchOnOpen` that lands in the
        // same window is overwritten by the final write below. Stated rather
        // than guarded: the ledger only bounds how often the BACKGROUND asks
        // again, so the whole cost of losing an entry is one extra attempt on
        // a later foreground — and the tap deliberately does not read it.
        var attempts = ledger()
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
            // `readableURL` is the shared rule (2026-08-23) — see its doc for
            // why the tap and this pass must agree on WHAT is readable while
            // disagreeing about when. The ledger check stays here: it is the
            // one bound that is this pass's alone, since a person's tap is not
            // a robot re-asking.
            guard let ref = thing.sourceRef,
                  (attempts[ref] ?? 0) < maxAttempts,
                  let url = readableURL(for: thing)
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
        writeLedger(attempts)
        return report
    }
}
